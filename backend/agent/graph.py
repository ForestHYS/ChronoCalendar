from __future__ import annotations

from typing import Any, Dict, List, Optional, TypedDict

from django.utils import timezone

from langgraph.graph import END, StateGraph

from .llm import call_llm_json
from .registry import get_skill, iter_skills, normalize_args, skills_prompt_lines
from .models import AgentSession, ApprovalRequest
from . import tools
import logging

logger = logging.getLogger(__name__)


def _terminal_response(resp: Optional[dict]) -> bool:
    if not resp:
        return False
    return resp.get("type") in (
        "message",
        "open_editor",
        "query_result",
        "approval_required",
        "plan_preview",
    )


class AgentState(TypedDict, total=False):
    user_id: str
    session_id: str
    input_text: str
    client_context: dict
    scratchpad: list
    last_tool: dict
    response: dict


def _normalize_input(state: AgentState) -> AgentState:
    text = (state.get("input_text") or "").strip()
    state["input_text"] = text
    if state.get("scratchpad") is None:
        state["scratchpad"] = []
    return state


def _tool_catalog_prompt() -> str:
    lines = skills_prompt_lines()
    return "\n".join(lines)


def _decide_next(state: AgentState) -> AgentState:
    """LLM 决策：respond / open_editor / tool。"""
    if _terminal_response(state.get("response")):
        return state

    text = state.get("input_text") or ""
    ctx = state.get("client_context") or {}
    now = timezone.now().isoformat()
    last_tool = state.get("last_tool")
    scratchpad = state.get("scratchpad") or []

    system = (
        "你是一个日程/任务 app 的 AI 助手。\n"
        "你可以与用户闲聊并正常用中文回复。\n"
        "当需要查询数据、生成草稿、冲突检测或申请删除任务时，必须使用工具。\n"
        "你必须输出严格 JSON 对象，不要输出任何额外文字。\n\n"
        "输出格式之一：\n"
        '{"action":"respond","text":"..."}\n'
        '{"action":"open_editor","task_draft":{...}}\n'
        '{"action":"tool","tool":"<skill_name>","args":{...}}\n\n'
        "可用工具（Skill）说明：\n"
        f"{_tool_catalog_prompt()}\n\n"
        "规则：\n"
        "- 创建/编辑单个任务不能直接落库；生成草稿请用 build_task_draft，最终返回 open_editor。\n"
        "- 删除任务必须使用工具 delete_task（只会创建审批请求，不会立即删除）。\n"
        "- 若用户提出长期规划需求（如'帮我安排一周学习计划'、'规划下个月项目进度'、"
        "'制定N天/周/月的XXX计划'），必须使用 generate_long_term_plan 工具，"
        "并根据当前时间（now）推算 start_date 和 end_date（ISO 日期格式，如 2026-05-24）。\n"
        "- 若用户明确说'直接添加/创建/加入日程'，则在 args 中传 create_immediately=true；否则传 false。\n"
        "- 若用户只是问候/闲聊，用 respond。\n"
        "- 若已有 last_tool（上一轮工具结果），请基于它给出最终 respond / open_editor / tool。\n"
    )
    user = {
        "now": now,
        "client_context": ctx,
        "user_input": text,
        "last_tool": last_tool,
    }
    r = call_llm_json(system=system, user=str(user))
    if not r.ok or not r.data:
        logger.warning("LLM unavailable for decide_next: %s", r.error)
        state["response"] = {
            "type": "message",
            "text": "AI 未接入或配置无效，无法处理你的请求。请检查 LLM 配置（AGENT_LLM_*）。",
        }
        return state

    state["scratchpad"].append({"llm_decision": r.data})
    state["response"] = {"type": "decision", "decision": r.data}
    return state


def _run_tool(state: AgentState) -> AgentState:
    """处理 decision：respond/open_editor 直接落盘；tool 执行或进入审批。"""
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
        state["response"] = {"type": "message", "text": decision.get("text") or "收到。"}
        return state
    if action == "open_editor":
        state["response"] = {
            "type": "open_editor",
            "task_draft": decision.get("task_draft") if isinstance(decision.get("task_draft"), dict) else {},
        }
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

    # 需要人工审批：不落库执行，只创建 ApprovalRequest
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

    # 普通工具执行
    try:
        args = normalize_args(skill.name, raw_args)
    except ValueError as e:
        state["response"] = {"type": "message", "text": str(e)}
        return state

    from .registry import run_skill

    try:
        out = run_skill(skill.name, user_id, raw_args)
    except Exception as e:
        logger.exception("run_skill failed")
        state["response"] = {"type": "message", "text": f"工具执行失败：{e}"}
        return state

    state["last_tool"] = {"tool": skill.name, "args": args, "output": out}
    state["response"] = {}
    return state


def _compose_response(state: AgentState) -> AgentState:
    if _terminal_response(state.get("response")):
        return state

    text = state.get("input_text") or ""
    last_tool = state.get("last_tool")

    # 长期规划工具的输出直接格式化，无需再过一遍 LLM
    if isinstance(last_tool, dict) and last_tool.get("tool") == "generate_long_term_plan":
        out = last_tool.get("output") or {}
        if not out.get("ok"):
            state["response"] = {
                "type": "message",
                "text": out.get("error") or "规划生成失败，请稍后再试。",
            }
            return state

        conflicts = out.get("conflicts") or []
        plan_title = out.get("plan_title") or "长期规划"
        conflict_hint = f"（{len(conflicts)} 个时段与已有日程有冲突）" if conflicts else ""

        # create_immediately=True：工具已直接落库，返回成功消息
        if out.get("created_immediately"):
            created_count = out.get("total_created", 0)
            error_count = len(out.get("errors") or [])
            state["response"] = {
                "type": "message",
                "text": (
                    f"已成功将「{plan_title}」的 {created_count} 个任务添加到你的日程中！"
                    + (f"（{error_count} 个任务创建失败）" if error_count else "")
                ),
                "refresh_tasks": True,
            }
            return state

        # create_immediately=False：返回预览
        tasks = out.get("tasks") or []
        total = out.get("total") or len(tasks)
        preview_hint = f"（注意：{len(conflicts)} 个任务与现有日程有冲突）" if conflicts else ""
        state["response"] = {
            "type": "plan_preview",
            "plan_title": plan_title,
            "tasks": tasks,
            "conflicts": conflicts,
            "message": (
                f"已为你生成「{plan_title}」，共 {total} 个待办任务{preview_hint}。"
                "请查看下方计划预览，确认无误后点击「创建全部任务」批量生成日程。"
            ),
        }
        return state

    system = (
        "你是任务日历 app 的 AI 助手。你可以正常聊天。\n"
        "当 last_tool 存在时，请根据工具输出生成最终结果（严格 JSON）：\n"
        "- last_tool.tool == search_tasks：{type:'query_result', items: last_tool.output.items, text:'简短说明'}\n"
        "- last_tool.tool == build_task_draft：{type:'open_editor', task_draft: last_tool.output, message?:'...'}\n"
        "- last_tool.tool == check_block_conflict：若有 conflict，输出 type:'open_editor' 并在顶层附带 conflict 字段（与 task_draft 同级）；"
        "task_draft 须来自用户意图；conflict 取自工具输出的 conflict 字段。\n"
        "若无 last_tool，输出 {type:'message', text:'...'}。\n"
        "必须输出严格 JSON 对象。"
    )
    user = {"user_input": text, "last_tool": last_tool}
    r = call_llm_json(system=system, user=str(user))
    if not r.ok or not r.data:
        logger.warning("LLM unavailable for compose_response: %s", r.error)
        state["response"] = {"type": "message", "text": "AI 生成回复失败，请稍后再试。"}
        return state

    out = r.data
    if out.get("type") in ("message", "open_editor", "query_result", "approval_required"):
        state["response"] = out
        return state
    if out.get("action") == "respond":
        state["response"] = {"type": "message", "text": out.get("text") or "收到。"}
        return state
    state["response"] = {"type": "message", "text": "收到。"}
    return state


def _route_after_run(state: AgentState) -> str:
    if _terminal_response(state.get("response")):
        return "compose"
    # generate_long_term_plan 结果直接进 compose，不再让 LLM 二次决策
    last_tool = state.get("last_tool") or {}
    if last_tool.get("tool") == "generate_long_term_plan":
        return "compose"
    return "decide"


def build_graph():
    g = StateGraph(AgentState)
    g.add_node("NormalizeInput", _normalize_input)
    g.add_node("DecideNext", _decide_next)
    g.add_node("RunTool", _run_tool)
    g.add_node("ComposeResponse", _compose_response)

    g.set_entry_point("NormalizeInput")
    g.add_edge("NormalizeInput", "DecideNext")
    g.add_edge("DecideNext", "RunTool")
    g.add_conditional_edges(
        "RunTool",
        _route_after_run,
        {"compose": "ComposeResponse", "decide": "DecideNext"},
    )
    g.add_edge("ComposeResponse", END)
    return g.compile()
