"""长期规划：结构化交互、文字修改、退出规划。"""
from __future__ import annotations

import logging
from typing import Any, Callable, Dict, List, Optional

from .history import build_llm_message_list
from .llm import call_llm_json
from .models import AgentMessage, AgentSession
from . import tools

logger = logging.getLogger(__name__)

PLAN_CONTINUATION_ACTIONS = frozenset(
    {"modify_outline", "modify_schedule", "exit_plan", "none"}
)


def get_active_plan_state(
    session: AgentSession,
    *,
    for_text_intercept: bool = False,
) -> Optional[Dict[str, Any]]:
    """从会话消息推断当前未完成的长期规划阶段。"""
    active: Optional[Dict[str, Any]] = None
    msgs = session.messages.filter(role=AgentMessage.Role.ASSISTANT).order_by(
        "created_at"
    )
    for msg in msgs:
        payload = msg.content_json if isinstance(msg.content_json, dict) else {}
        t = payload.get("type")
        if for_text_intercept and payload.get("plan_text_suspended"):
            if t in ("plan_questions", "plan_outline", "plan_preview"):
                active = None
            continue
        if t == "plan_questions":
            if not payload.get("plan_answered"):
                active = {
                    "stage": "questions",
                    "message_id": str(msg.id),
                    "plan_context": payload.get("plan_context") or {},
                    "payload": payload,
                }
            else:
                active = None
        elif t == "plan_outline":
            active = {
                "stage": "outline",
                "message_id": str(msg.id),
                "plan_context": payload.get("plan_context") or {},
                "payload": payload,
            }
        elif t == "plan_preview":
            if not payload.get("plan_confirmed"):
                active = {
                    "stage": "scheduling",
                    "message_id": str(msg.id),
                    "plan_context": payload.get("plan_context") or {},
                    "payload": payload,
                    "tasks": payload.get("tasks") or [],
                }
            else:
                active = None
    return active


def _merge_plan_context(
    interaction: dict,
    session: AgentSession,
) -> Dict[str, Any]:
    plan_context = dict(interaction.get("plan_context") or {})
    source_message_id = interaction.get("source_message_id")
    if source_message_id:
        msg = AgentMessage.objects.filter(
            pk=source_message_id,
            session=session,
        ).first()
        if msg and isinstance(msg.content_json, dict):
            stored = msg.content_json.get("plan_context")
            if isinstance(stored, dict):
                plan_context = {**stored, **plan_context}
    return plan_context


def _mark_source_message(
    session: AgentSession,
    source_message_id: Optional[str],
    *,
    flag_key: str,
) -> None:
    if not source_message_id:
        return
    msg = AgentMessage.objects.filter(pk=source_message_id, session=session).first()
    if not msg or not isinstance(msg.content_json, dict):
        return
    merged = dict(msg.content_json)
    merged[flag_key] = True
    msg.content_json = merged
    msg.save(update_fields=["content_json"])


def _suspend_plan_text(
    session: AgentSession,
    source_message_id: Optional[str],
) -> None:
    """暂停该规划卡片的文字续聊，但不影响卡片按钮/选项继续操作。"""
    _mark_source_message(session, source_message_id, flag_key="plan_text_suspended")


def _clear_plan_text_suspension(
    session: AgentSession,
    source_message_id: Optional[str],
) -> None:
    if not source_message_id:
        return
    msg = AgentMessage.objects.filter(pk=source_message_id, session=session).first()
    if not msg or not isinstance(msg.content_json, dict):
        return
    merged = dict(msg.content_json)
    if "plan_text_suspended" not in merged:
        return
    merged.pop("plan_text_suspended", None)
    msg.content_json = merged
    msg.save(update_fields=["content_json"])


def _outline_message(out: dict) -> str:
    summary = out.get("planned_schedule_summary")
    if not isinstance(summary, dict):
        return "请阅读以下方案，可直接输入修改意见；确认后将生成具体日程。"
    todo_n = int(summary.get("todo_count") or 0)
    block_n = int(summary.get("block_count") or 0)
    note = str(summary.get("summary") or "").strip()
    base = (
        f"请阅读以下方案。预计排程约 {todo_n} 个待办、{block_n} 个固定时段"
        f"{'（' + note + '）' if note else ''}。"
        "可直接输入修改意见；确认后将生成具体日程。"
    )
    return base


def compose_plan_outline(out: dict) -> dict:
    summary = out.get("planned_schedule_summary")
    if not isinstance(summary, dict):
        summary = {}
    return {
        "type": "plan_outline",
        "plan_title": out.get("plan_title") or "长期规划",
        "message": _outline_message(out),
        "outline_text": out.get("outline_text") or "",
        "phases": out.get("phases") or [],
        "planned_schedule_summary": summary,
        "plan_context": {
            "goal": out.get("goal") or "",
            "answers": out.get("answers") or {},
            "plan_title": out.get("plan_title") or "",
            "outline_text": out.get("outline_text") or "",
            "phases": out.get("phases") or [],
            "start_date": out.get("start_date") or "",
            "end_date": out.get("end_date") or "",
            "daily_hours": out.get("daily_hours") or 2.0,
            "planned_schedule_summary": summary,
        },
    }


def compose_plan_questions(out: dict) -> dict:
    goal = out.get("goal") or ""
    questions = out.get("questions") or []
    return {
        "type": "plan_questions",
        "message": (
            "为了制定更合适的长期计划，请先确认以下几项（点选后提交）。"
            "期间也可先去聊别的，之后回来继续点选即可。"
        ),
        "questions": questions,
        "plan_context": {"goal": goal},
    }


def _schedule_plan_context(out: dict, base: Dict[str, Any]) -> Dict[str, Any]:
    ctx = dict(base)
    ctx.update(
        {
            "plan_title": out.get("plan_title") or ctx.get("plan_title") or "",
            "tasks_snapshot": out.get("tasks") or [],
        }
    )
    return ctx


def compose_schedule_preview(out: dict, *, plan_context: Optional[dict] = None) -> dict:
    tasks = out.get("tasks") or []
    total = out.get("total") or len(tasks)
    plan_title = out.get("plan_title") or "长期规划"
    base_ctx = dict(plan_context or {})
    return {
        "type": "plan_preview",
        "phase": "scheduling",
        "plan_title": plan_title,
        "tasks": tasks,
        "message": (
            f"已根据方案生成 {total} 个日程任务。"
            "可直接输入修改意见；或勾选要加入日程的项后点击创建。"
        ),
        "plan_context": _schedule_plan_context(out, base_ctx),
    }


def classify_plan_continuation(
    *,
    user_input: str,
    active_plan: Dict[str, Any],
    chat_history: List[Dict[str, str]],
    user_id: Optional[str] = None,
) -> str:
    stage = active_plan.get("stage") or ""
    system = (
        "你是长期规划流程中的意图判别器。用户在规划过程中发送了文字消息，判断其意图。\n"
        "只输出 JSON：{\"action\":\"...\"}\n"
        "action 取值：\n"
        "- modify_outline：要求修改文字方案/阶段（不必重做选择题）\n"
        "- modify_schedule：要求修改已生成的具体日程任务列表\n"
        "- exit_plan：用户暂时聊别的、停止用文字继续规划（规划卡片仍可稍后点击继续）\n"
        "- none：无法判断\n\n"
        f"当前规划阶段 stage={stage}\n"
        "- stage=outline：调整方案内容 -> modify_outline\n"
        "- stage=scheduling：调整任务条目 -> modify_schedule；若否定整体方案 -> modify_outline\n"
        "- stage=questions：仅 exit_plan 或 none（勿用 modify）\n"
        "- 「不规划了」「算了」或明显无关请求 -> exit_plan\n"
    )
    user_payload = {
        "user_input": user_input,
        "active_plan_stage": stage,
    }
    messages = build_llm_message_list(
        system=system,
        user_payload=user_payload,
        history_summary=None,
        chat_history=chat_history[-4:],
    )
    r = call_llm_json(system=system, user="", messages=messages, user_id=user_id)
    if r.ok and r.data:
        action = (r.data.get("action") or "").strip().lower()
        if action in PLAN_CONTINUATION_ACTIONS:
            return action
    logger.warning("plan continuation classify failed: %s", r.error if r else "")
    return "none"


def _run_outline_from_context(
    plan_context: Dict[str, Any],
    *,
    client_context: Optional[Dict[str, Any]],
    refinement: Optional[str] = None,
    user_id: Optional[str] = None,
) -> dict:
    goal = str(plan_context.get("goal") or "").strip()
    answers = plan_context.get("answers")
    if not isinstance(answers, dict):
        answers = {}
    previous = {
        "plan_title": plan_context.get("plan_title"),
        "outline_text": plan_context.get("outline_text"),
        "phases": plan_context.get("phases"),
        "planned_schedule_summary": plan_context.get("planned_schedule_summary"),
    }
    return tools.plan_generate_outline(
        goal=goal,
        answers=answers if answers else {"_continued": True},
        client_context=client_context,
        refinement=refinement,
        previous_outline=previous if refinement else None,
        user_id=user_id,
    )


def _run_schedule_from_context(
    plan_context: Dict[str, Any],
    *,
    client_context: Optional[Dict[str, Any]],
    refinement: Optional[str] = None,
    previous_tasks: Optional[list] = None,
    user_id: Optional[str] = None,
) -> dict:
    return tools.plan_schedule_tasks(
        goal=str(plan_context.get("goal") or "").strip(),
        plan_title=str(plan_context.get("plan_title") or "").strip(),
        outline_text=str(plan_context.get("outline_text") or "").strip(),
        phases=plan_context.get("phases") or [],
        start_date=str(plan_context.get("start_date") or "").strip(),
        end_date=str(plan_context.get("end_date") or "").strip(),
        daily_hours=plan_context.get("daily_hours") or 2.0,
        client_context=client_context,
        refinement=refinement,
        previous_tasks=previous_tasks,
        user_id=user_id,
    )


def handle_plan_text_message(
    *,
    session: AgentSession,
    user_text: str,
    active_plan: Dict[str, Any],
    chat_history: List[Dict[str, str]],
    client_context: Optional[Dict[str, Any]],
    run_general_agent: Callable[[], dict],
) -> Optional[dict]:
    """
    规划进行中的自由文字输入。返回 None 表示交回常规 Agent 图处理。
    """
    user_id = str(session.user_id)
    action = classify_plan_continuation(
        user_input=user_text,
        active_plan=active_plan,
        chat_history=chat_history,
        user_id=user_id,
    )
    stage = active_plan.get("stage") or ""
    plan_context = active_plan.get("plan_context") or {}
    message_id = active_plan.get("message_id")

    if action == "exit_plan":
        _suspend_plan_text(session, message_id)
        return run_general_agent()

    if action == "modify_outline" and stage in ("outline", "scheduling"):
        out = _run_outline_from_context(
            plan_context,
            client_context=client_context,
            refinement=user_text,
            user_id=user_id,
        )
        if not out.get("ok"):
            return {"type": "message", "text": out.get("error") or "方案修改失败。"}
        return compose_plan_outline(out)

    if action == "modify_schedule" and stage == "scheduling":
        prev_tasks = active_plan.get("tasks") or plan_context.get("tasks_snapshot")
        out = _run_schedule_from_context(
            plan_context,
            client_context=client_context,
            refinement=user_text,
            previous_tasks=prev_tasks if isinstance(prev_tasks, list) else None,
            user_id=user_id,
        )
        if not out.get("ok"):
            return {"type": "message", "text": out.get("error") or "日程修改失败。"}
        return compose_schedule_preview(out, plan_context=plan_context)

    if action == "none":
        _suspend_plan_text(session, message_id)
        return None

    return None


def handle_plan_interaction(
    *,
    session: AgentSession,
    interaction: dict,
    client_context: Optional[Dict[str, Any]] = None,
) -> dict:
    itype = (interaction.get("type") or "").strip()
    source_message_id = interaction.get("source_message_id")
    plan_context = _merge_plan_context(interaction, session)
    user_id = str(session.user_id)

    if itype == "plan_answers":
        _clear_plan_text_suspension(session, source_message_id)
        answers = interaction.get("answers")
        if not isinstance(answers, dict) or not answers:
            return {"type": "message", "text": "请先完成选择题再提交。"}
        goal = str(plan_context.get("goal") or "").strip()
        if not goal:
            return {"type": "message", "text": "缺少规划目标，请重新描述你的计划。"}

        out = tools.plan_generate_outline(
            goal=goal,
            answers=answers,
            client_context=client_context,
            user_id=user_id,
        )
        if not out.get("ok"):
            return {"type": "message", "text": out.get("error") or "方案生成失败。"}

        _mark_source_message(session, source_message_id, flag_key="plan_answered")
        return compose_plan_outline(out)

    if itype == "confirm_outline":
        _clear_plan_text_suspension(session, source_message_id)
        goal = str(plan_context.get("goal") or "").strip()
        plan_title = str(plan_context.get("plan_title") or "").strip()
        outline_text = str(plan_context.get("outline_text") or "").strip()
        phases = plan_context.get("phases")
        start_date = str(plan_context.get("start_date") or "").strip()
        end_date = str(plan_context.get("end_date") or "").strip()
        daily_hours = plan_context.get("daily_hours") or 2.0

        if not goal or not plan_title or not outline_text or not phases:
            return {"type": "message", "text": "方案数据不完整，请重新规划。"}

        out = tools.plan_schedule_tasks(
            goal=goal,
            plan_title=plan_title,
            outline_text=outline_text,
            phases=phases,
            start_date=start_date,
            end_date=end_date,
            daily_hours=daily_hours,
            client_context=client_context,
            user_id=user_id,
        )
        if not out.get("ok"):
            return {"type": "message", "text": out.get("error") or "日程生成失败。"}

        _mark_source_message(session, source_message_id, flag_key="outline_confirmed")
        return compose_schedule_preview(out, plan_context=plan_context)

    return {"type": "message", "text": "无法识别的规划操作。"}
