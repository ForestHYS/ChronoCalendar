from __future__ import annotations

from typing import Any, Dict, List, Optional, TypedDict

from langgraph.graph import END, StateGraph

from .history import build_llm_message_list
from .plan_interaction import (
    compose_plan_outline,
    compose_plan_questions,
    compose_schedule_preview,
)
from .llm import call_llm_json, call_llm_text
from .registry import get_skill, normalize_args, skills_prompt_for
from .models import AgentSession, ApprovalRequest
from .task_types_guide import TASK_TYPES_GUIDE
from .timezone_ctx import calendar_range_hints, timezone_prompt_lines, user_now_payload
from . import tools
import logging

logger = logging.getLogger(__name__)

VALID_INTENTS = frozenset(
    {"chat", "create_task", "query_tasks", "plan", "delete"}
)


def _terminal_response(resp: Optional[dict]) -> bool:
    if not resp:
        return False
    return resp.get("type") in (
        "message",
        "open_editor",
        "query_result",
        "approval_required",
        "plan_questions",
        "plan_outline",
        "plan_preview",
    )


class AgentState(TypedDict, total=False):
    user_id: str
    session_id: str
    input_text: str
    client_context: dict
    chat_history: list
    history_summary: str
    intent: str
    scratchpad: list
    last_tool: dict
    response: dict


def _normalize_input(state: AgentState) -> AgentState:
    text = (state.get("input_text") or "").strip()
    state["input_text"] = text
    if state.get("scratchpad") is None:
        state["scratchpad"] = []
    if state.get("chat_history") is None:
        state["chat_history"] = []
    return state


def _time_context_block(client_context: dict) -> str:
    return "时间与用户时区：\n" + timezone_prompt_lines(client_context)


def _base_user_payload(state: AgentState) -> Dict[str, Any]:
    ctx = state.get("client_context") or {}
    return {
        "user_local_time": user_now_payload(ctx),
        "calendar_hints": calendar_range_hints(ctx),
        "client_context": ctx,
        "user_input": state.get("input_text") or "",
        "intent": state.get("intent"),
        "last_tool": state.get("last_tool"),
    }


def _llm_fail_message() -> dict:
    return {
        "type": "message",
        "text": "AI 暂时无法解析回复，请稍后重试或换一种说法。",
    }


def _classify_intent(state: AgentState) -> AgentState:
    """阶段 1：LLM 意图分类。"""
    if _terminal_response(state.get("response")):
        return state

    text = state.get("input_text") or ""
    ctx = state.get("client_context") or {}
    history = (state.get("chat_history") or [])[-4:]
    system = (
        "你是日程 app 的意图分类器。根据用户最新一句话（结合少量上下文）判断意图。\n"
        "只输出 JSON：{\"intent\":\"...\"}\n"
        "intent 取值：\n"
        "- chat：问候、闲聊、问现在几点\n"
        "- create_task：创建/添加单个任务（含 block/ddl/todo）；"
        "「加入日程」「添加到日历」等表述属于创建，不是查询\n"
        "- query_tasks：查询、搜索、列出已有任务，或问某天有什么安排\n"
        "- plan：长期规划、多天的学习计划/项目安排\n"
        "- delete：删除任务\n"
        "若用户正在长期规划流程中但明确退出或转向其他意图，由规划续聊处理；此处仍按真实意图分类。\n"
    )
    user_payload = {
        "user_local_time": user_now_payload(ctx),
        "user_input": text,
    }
    messages = build_llm_message_list(
        system=system,
        user_payload=user_payload,
        history_summary=state.get("history_summary"),
        chat_history=history,
    )
    r = call_llm_json(system=system, user="", messages=messages)
    intent = "chat"
    if r.ok and r.data:
        raw = (r.data.get("intent") or "").strip().lower()
        if raw in VALID_INTENTS:
            intent = raw
    else:
        logger.warning("intent classify LLM failed: %s", r.error)

    state["intent"] = intent
    state["scratchpad"].append({"intent": intent})
    return state


def _summarize_search_result_text(
    items: List[Dict[str, Any]], user_input: str, *, count: int
) -> str:
    if not items:
        return "未找到匹配的任务。"
    lines = []
    for it in items[:12]:
        if not isinstance(it, dict):
            continue
        title = it.get("title") or "未命名"
        typ = it.get("type") or ""
        time_part = (it.get("time_summary") or "").strip()
        if not time_part:
            if it.get("start_at") and it.get("end_at"):
                time_part = f"{it.get('start_at')} — {it.get('end_at')}"
            elif it.get("due_at"):
                time_part = f"截止 {it.get('due_at')}"
        suffix = f" · {time_part}" if time_part else ""
        lines.append(f"- {title}（{typ}）{suffix}")
    blob = "\n".join(lines)
    system = (
        "你是日程助手。根据用户问题和任务列表，用 1～3 句中文简要说明；"
        "每条已含时间信息，勿声称列表缺少日期。不要编造列表外的任务。"
    )
    user = f"用户问题：{user_input}\n\n共 {count} 条：\n{blob}"
    r = call_llm_text(system=system, user=user)
    if r.ok and r.data and (r.data.get("text") or "").strip():
        return str(r.data["text"]).strip()
    titles = "、".join(
        (it.get("title") or "") for it in items[:3] if isinstance(it, dict)
    )
    suffix = f"等 {count} 个" if count > 3 else ""
    return f"找到 {count} 个相关任务：{titles}{suffix}。点击下方「查看详情」可打开任务页。"


def _decision_output_formats() -> str:
    return (
        "输出格式（严格 JSON，三选一）：\n"
        '{"action":"respond","text":"..."}\n'
        '{"action":"open_editor","task_draft":{...}}\n'
        '{"action":"tool","tool":"<skill_name>","args":{...}}\n'
    )


def _prompt_chat(ctx: dict) -> str:
    return (
        "你是日程 app 助手。用中文友好回复。\n"
        + _time_context_block(ctx)
        + "\n用户问「现在几点」请根据 user_local_time 直接回答，勿调用工具。\n"
        + _decision_output_formats()
        + "闲聊/问答请用 action:respond。\n"
    )


def _prompt_create_task(ctx: dict) -> str:
    return (
        "你是任务创建助手。创建单个任务不落库，须用 build_task_draft 生成草稿。\n"
        + _time_context_block(ctx)
        + "\n"
        + TASK_TYPES_GUIDE
        + "\n可用工具：\n"
        + skills_prompt_for(["build_task_draft", "check_block_conflict"])
        + "\n规则：\n"
        "- 按语义选择 block/ddl/todo，勿默认 block。\n"
        "- block 可先 check_block_conflict 再 build_task_draft，或直接 build_task_draft。\n"
        "- 时间字段用 ISO8601（用户本地理解后带时区偏移）。\n"
        "- 完成后用 open_editor（task_draft 来自工具输出）或 tool build_task_draft。\n"
        + _decision_output_formats()
    )


def _prompt_query_tasks(ctx: dict) -> str:
    return (
        "你是任务查询助手。须调用 search_tasks，禁止手写任务列表。\n"
        + _time_context_block(ctx)
        + "\n可用工具：\n"
        + skills_prompt_for(["search_tasks"])
        + "\n规则：\n"
        "- 问今天/明天/某天有哪些任务：必须传 range_from+range_to（见 calendar_hints）。\n"
        "- 无匹配时勿去掉 range 拉最近任务。\n"
        "- 按标题搜可传 q。\n"
        + _decision_output_formats()
        + "调用 search_tasks 时用 action:tool。\n"
    )


def _prompt_plan(ctx: dict) -> str:
    return (
        "你是长期规划助手，采用 Planning → Scheduling 两阶段流程。\n"
        + _time_context_block(ctx)
        + "\n当前处于 Planning 第一步：用户首次提出长期规划时，"
        "须调用 plan_gather_requirements 生成选择题，勿直接生成任务或方案。\n"
        "用户在规划中途的文字修改、退出由专用续聊处理，此处仅处理新发起的规划。\n"
        "可用工具：\n"
        + skills_prompt_for(["plan_gather_requirements"])
        + "\n规则：\n"
        "- goal 取用户目标描述（可结合上下文补全）。\n"
        "- 用户提交选择题答案、确认方案等后续步骤由前端结构化交互完成，"
        "此时勿重复调用 plan_gather_requirements。\n"
        + _decision_output_formats()
    )


def _prompt_delete() -> str:
    return (
        "你是任务删除助手。删除须调用 delete_task（会进入审批，不会立刻删除）。\n"
        "可用工具：\n"
        + skills_prompt_for(["delete_task"])
        + "\n"
        + _decision_output_formats()
    )


def _decide_by_intent(state: AgentState) -> AgentState:
    """阶段 2：按 intent 使用专项短 prompt 决策 tool/回复。"""
    if _terminal_response(state.get("response")):
        return state

    intent = (state.get("intent") or "chat").strip().lower()
    if intent not in VALID_INTENTS:
        intent = "chat"

    ctx = state.get("client_context") or {}
    history = state.get("chat_history") or []
    history_summary = state.get("history_summary")

    builders = {
        "chat": lambda: _prompt_chat(ctx),
        "create_task": lambda: _prompt_create_task(ctx),
        "query_tasks": lambda: _prompt_query_tasks(ctx),
        "plan": lambda: _prompt_plan(ctx),
        "delete": lambda: _prompt_delete(),
    }
    system = builders.get(intent, builders["chat"])()

    messages = build_llm_message_list(
        system=system,
        user_payload=_base_user_payload(state),
        history_summary=history_summary,
        chat_history=history,
    )
    r = call_llm_json(system=system, user="", messages=messages)
    if not r.ok or not r.data:
        logger.warning("LLM unavailable for decide_by_intent(%s): %s", intent, r.error)
        state["response"] = _llm_fail_message()
        return state

    state["scratchpad"].append({"llm_decision": r.data, "intent": intent})
    state["response"] = {"type": "decision", "decision": r.data}
    return state


def _run_tool(state: AgentState) -> AgentState:
    if not isinstance(state.get("response"), dict):
        return state
    resp = state["response"]
    if resp.get("type") != "decision":
        return state

    decision = resp.get("decision")
    if not isinstance(decision, dict):
        state["response"] = {"type": "message", "text": "AI 返回格式异常。"}
        return state

    action = decision.get("action")
    if action == "respond":
        text = (decision.get("text") or "").strip() or "收到。"
        state["response"] = {"type": "message", "text": text}
        return state
    if action == "open_editor":
        draft = decision.get("task_draft") if isinstance(decision.get("task_draft"), dict) else {}
        tt = (draft.get("type") or "").strip().lower()
        if tt not in ("block", "ddl", "todo"):
            state["response"] = {
                "type": "message",
                "text": "草稿缺少有效任务类型（block/ddl/todo），请说明要创建哪类任务。",
            }
            return state
        state["response"] = {"type": "open_editor", "task_draft": draft}
        return state
    if action != "tool":
        state["response"] = {"type": "message", "text": "无法处理的指令。"}
        return state

    tool_name = decision.get("tool")
    raw_args = decision.get("args") or {}
    if not isinstance(raw_args, dict):
        raw_args = {}

    skill = get_skill(str(tool_name)) if tool_name else None
    if not skill:
        state["response"] = {"type": "message", "text": f"未知工具：{tool_name}"}
        return state

    user_id = state.get("user_id") or ""
    client_context = state.get("client_context") or {}

    if skill.requires_approval:
        try:
            args = normalize_args(skill.name, raw_args)
        except ValueError as e:
            state["response"] = {"type": "message", "text": str(e)}
            return state

        if skill.name == "delete_task":
            tid = args.get("task_id")
            summ = tools.task_summary_for_approval(user_id=user_id, task_id=tid)
            if not summ.get("ok"):
                state["response"] = {"type": "message", "text": "找不到该任务或无权删除。"}
                return state
            task = summ["task"]
            summary = f"永久删除任务「{task.get('title', '')}」（{task.get('type', '')}）"
            sid = state.get("session_id")
            session = None
            if sid:
                session = AgentSession.objects.filter(pk=sid, user_id=user_id).first()

            ar = ApprovalRequest.objects.create(
                user_id=user_id,
                agent_session=session,
                skill_name=skill.name,
                args_json=args,
                summary=summary[:500],
            )
            state["response"] = {
                "type": "approval_required",
                "approval_id": str(ar.id),
                "skill_name": skill.name,
                "summary": summary,
                "task_preview": task,
                "proposed_action": {"skill_name": skill.name, "args": args},
            }
            return state

        state["response"] = {"type": "message", "text": "该操作需要审批，但未配置审批流程。"}
        return state

    try:
        args = normalize_args(skill.name, raw_args)
    except ValueError as e:
        state["response"] = {"type": "message", "text": str(e)}
        return state

    from .registry import run_skill

    try:
        tool_raw = dict(raw_args)
        tool_raw["client_context"] = client_context
        out = run_skill(skill.name, user_id, tool_raw)
    except Exception as e:
        logger.exception("run_skill failed")
        state["response"] = {"type": "message", "text": f"工具执行失败：{e}"}
        return state

    state["last_tool"] = {"tool": skill.name, "args": args, "output": out}
    state["response"] = {}
    return state


def _compose_build_task_draft(state: AgentState, draft: dict) -> None:
    if draft.get("ok") is False:
        state["response"] = {
            "type": "message",
            "text": draft.get("error") or "草稿生成失败。",
        }
        return
    title = draft.get("title") or "新任务"
    tt = draft.get("type") or ""
    type_label = {"block": "固定时段", "ddl": "截止日期", "todo": "待办"}.get(tt, tt)
    clean_draft = {k: v for k, v in draft.items() if k not in ("ok", "error")}
    state["response"] = {
        "type": "open_editor",
        "task_draft": clean_draft,
        "message": f"已生成{type_label}任务「{title}」草稿，请确认后保存。",
    }


def _compose_check_block_conflict(state: AgentState, out: dict, args: dict) -> None:
    conflict = out.get("conflict")
    title = (state.get("input_text") or "新任务")[:255]
    draft: Dict[str, Any] = {
        "type": "block",
        "title": title,
        "description": "",
        "tag_ids": [],
    }
    nr = (conflict or {}).get("new_range") if isinstance(conflict, dict) else None
    if isinstance(nr, dict) and nr.get("start_at") and nr.get("end_at"):
        draft["start_at"] = nr["start_at"]
        draft["end_at"] = nr["end_at"]
    elif args.get("start_at") and args.get("end_at"):
        draft["start_at"] = args["start_at"]
        draft["end_at"] = args["end_at"]

    resp: Dict[str, Any] = {
        "type": "open_editor",
        "task_draft": draft,
    }
    if conflict:
        resp["conflict"] = conflict
        resp["message"] = "检测到时间冲突，可选择建议时间或自行修改后保存。"
    else:
        resp["message"] = "该时段无冲突，请确认任务草稿后保存。"
    state["response"] = resp


def _compose_response(state: AgentState) -> AgentState:
    if _terminal_response(state.get("response")):
        return state

    text = state.get("input_text") or ""
    last_tool = state.get("last_tool")

    if isinstance(last_tool, dict):
        tool_name = last_tool.get("tool")
        out = last_tool.get("output") or {}
        args = last_tool.get("args") or {}

        if tool_name == "build_task_draft":
            _compose_build_task_draft(state, out)
            return state

        if tool_name == "check_block_conflict":
            if out.get("ok") is False:
                state["response"] = {
                    "type": "message",
                    "text": "时间范围无效，请重新说明开始和结束时间。",
                }
            else:
                _compose_check_block_conflict(state, out, args)
            return state

        if tool_name == "search_tasks":
            if out.get("ok") is False:
                state["response"] = {
                    "type": "message",
                    "text": f"无法完成查询：{out.get('error') or '查询失败'}。",
                }
                return state
            items = out.get("items") if isinstance(out.get("items"), list) else []
            count = out.get("count", len(items))
            range_applied = bool(out.get("range_applied"))
            if not items:
                empty_text = (
                    "该时间段内没有安排任务。"
                    if range_applied
                    else "未找到匹配的任务。"
                )
                state["response"] = {
                    "type": "query_result",
                    "items": [],
                    "text": empty_text,
                }
            else:
                summary = _summarize_search_result_text(
                    items, text, count=int(count) if count else len(items)
                )
                state["response"] = {
                    "type": "query_result",
                    "items": items,
                    "text": summary,
                }
            return state

        if tool_name == "plan_gather_requirements":
            if not out.get("ok"):
                state["response"] = {
                    "type": "message",
                    "text": out.get("error") or "无法生成规划问题。",
                }
                return state
            state["response"] = compose_plan_questions(out)
            return state

        if tool_name == "plan_generate_outline":
            if not out.get("ok"):
                state["response"] = {
                    "type": "message",
                    "text": out.get("error") or "方案生成失败。",
                }
                return state
            state["response"] = compose_plan_outline(out)
            return state

        if tool_name == "plan_schedule_tasks":
            if not out.get("ok"):
                state["response"] = {
                    "type": "message",
                    "text": out.get("error") or "日程生成失败。",
                }
                return state
            state["response"] = compose_schedule_preview(out)
            return state

    logger.warning("compose_response fallback: last_tool=%s", last_tool)
    state["response"] = {"type": "message", "text": "处理完成，但未生成可展示的结果。"}
    return state


def build_graph():
    g = StateGraph(AgentState)
    g.add_node("NormalizeInput", _normalize_input)
    g.add_node("ClassifyIntent", _classify_intent)
    g.add_node("DecideByIntent", _decide_by_intent)
    g.add_node("RunTool", _run_tool)
    g.add_node("ComposeResponse", _compose_response)

    g.set_entry_point("NormalizeInput")
    g.add_edge("NormalizeInput", "ClassifyIntent")
    g.add_edge("ClassifyIntent", "DecideByIntent")
    g.add_edge("DecideByIntent", "RunTool")
    g.add_edge("RunTool", "ComposeResponse")
    g.add_edge("ComposeResponse", END)
    return g.compile()
