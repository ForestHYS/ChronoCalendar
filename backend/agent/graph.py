from __future__ import annotations

from typing import Any, Dict, List, Optional, TypedDict

from langgraph.graph import END, StateGraph

from .history import build_llm_message_list
from .plan_interaction import (
    compose_plan_outline,
    compose_plan_questions,
    compose_schedule_preview,
)
from .llm import (
    call_llm_json,
    is_llm_configured,
    is_missing_api_key_error,
    llm_not_configured_response,
)
from .registry import get_skill, normalize_args, skills_prompt_for
from .models import AgentSession, ApprovalRequest
from .task_types_guide import TASK_TYPES_GUIDE
from .timezone_ctx import calendar_range_hints, timezone_prompt_lines, user_now_payload
from .compose_llm import compose_user_text
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


def _llm_fail_message(error: Optional[str] = None) -> dict:
    if is_missing_api_key_error(error):
        return llm_not_configured_response()
    return {
        "type": "message",
        "text": "AI 暂时无法解析回复，请稍后重试或换一种说法。",
    }


def _classify_intent(state: AgentState) -> AgentState:
    """阶段 1：LLM 意图分类。"""
    if _terminal_response(state.get("response")):
        return state

    if not is_llm_configured(state.get("user_id")):
        state["response"] = llm_not_configured_response()
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
        "- delete：删除任务（按标题/描述即可，勿要求用户提供 id）\n"
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
    r = call_llm_json(system=system, user="", messages=messages, user_id=state.get("user_id"))
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


def _compose_ctx(state: AgentState) -> Dict[str, Any]:
    return {
        "user_input": state.get("input_text") or "",
        "intent": state.get("intent"),
        "user_id": state.get("user_id"),
        "history_summary": state.get("history_summary"),
    }


def _say(state: AgentState, scene: str, facts: Dict[str, Any]) -> str:
    c = _compose_ctx(state)
    return compose_user_text(
        user_input=c["user_input"],
        intent=c.get("intent"),
        scene=scene,
        facts=facts,
        user_id=c.get("user_id"),
        history_summary=c.get("history_summary"),
    )


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


def _prompt_delete(ctx: dict) -> str:
    return (
        "用户要删除任务。调用 delete_task；用 args.q 传标题关键词（仅按标题匹配）。\n"
        "勿索要 task_id。删除需用户审批。\n"
        + _time_context_block(ctx)
        + "\n"
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
        "delete": lambda: _prompt_delete(ctx),
    }
    system = builders.get(intent, builders["chat"])()

    messages = build_llm_message_list(
        system=system,
        user_payload=_base_user_payload(state),
        history_summary=history_summary,
        chat_history=history,
    )
    r = call_llm_json(
        system=system,
        user="",
        messages=messages,
        user_id=state.get("user_id"),
    )
    if not r.ok or not r.data:
        logger.warning("LLM unavailable for decide_by_intent(%s): %s", intent, r.error)
        state["response"] = _llm_fail_message(r.error)
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
        state["last_tool"] = {
            "tool": "_decision",
            "args": {},
            "output": {"ok": False, "error": "invalid_decision"},
        }
        state["response"] = {}
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
            state["last_tool"] = {
                "tool": "open_editor",
                "args": {},
                "output": {"ok": False, "error": "invalid_task_draft_type", "draft": draft},
            }
            state["response"] = {}
            return state
        state["response"] = {"type": "open_editor", "task_draft": draft}
        return state
    if action != "tool":
        state["last_tool"] = {
            "tool": "_decision",
            "args": {},
            "output": {"ok": False, "error": "unsupported_action", "action": action},
        }
        state["response"] = {}
        return state

    tool_name = decision.get("tool")
    raw_args = decision.get("args") or {}
    if not isinstance(raw_args, dict):
        raw_args = {}

    skill = get_skill(str(tool_name)) if tool_name else None
    if not skill:
        state["last_tool"] = {
            "tool": str(tool_name),
            "args": raw_args,
            "output": {"ok": False, "error": "unknown_tool", "tool": tool_name},
        }
        state["response"] = {}
        return state

    user_id = state.get("user_id") or ""
    client_context = state.get("client_context") or {}

    if skill.requires_approval:
        try:
            args = normalize_args(skill.name, raw_args)
        except ValueError as e:
            state["last_tool"] = {
                "tool": skill.name,
                "args": raw_args,
                "output": {"ok": False, "error": "validation", "code": str(e)},
            }
            state["response"] = {}
            return state

        if skill.name == "delete_task":
            resolved = tools.resolve_delete_task_target(
                user_id=user_id,
                task_id=args.get("task_id"),
                q=args.get("q"),
                client_context=client_context,
            )
            state["last_tool"] = {
                "tool": "delete_task",
                "args": args,
                "output": resolved,
            }
            state["response"] = {}
            return state

        state["last_tool"] = {
            "tool": skill.name,
            "args": raw_args,
            "output": {"ok": False, "error": "approval_not_configured"},
        }
        state["response"] = {}
        return state

    try:
        args = normalize_args(skill.name, raw_args)
    except ValueError as e:
        state["last_tool"] = {
            "tool": skill.name,
            "args": raw_args,
            "output": {"ok": False, "error": "validation", "code": str(e)},
        }
        state["response"] = {}
        return state

    from .registry import run_skill

    try:
        tool_raw = dict(raw_args)
        tool_raw["client_context"] = client_context
        out = run_skill(skill.name, user_id, tool_raw)
    except Exception as e:
        logger.exception("run_skill failed")
        state["last_tool"] = {
            "tool": skill.name,
            "args": raw_args,
            "output": {"ok": False, "error": "tool_exception", "detail": type(e).__name__},
        }
        state["response"] = {}
        return state

    state["last_tool"] = {"tool": skill.name, "args": args, "output": out}
    state["response"] = {}
    return state


def _compose_build_task_draft(state: AgentState, draft: dict) -> None:
    if draft.get("ok") is False:
        state["response"] = {
            "type": "message",
            "text": _say(
                state,
                "task_draft_failed",
                {"error": draft.get("error"), "draft": draft},
            ),
        }
        return
    clean_draft = {k: v for k, v in draft.items() if k not in ("ok", "error")}
    state["response"] = {
        "type": "open_editor",
        "task_draft": clean_draft,
        "message": _say(
            state,
            "task_draft_ready",
            {"task_draft": clean_draft},
        ),
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
        "message": _say(
            state,
            "block_conflict_checked",
            {"conflict": conflict, "task_draft": draft},
        ),
    }
    if conflict:
        resp["conflict"] = conflict
    state["response"] = resp


def _compose_delete_task(state: AgentState, out: dict, args: dict) -> None:
    user_id = state.get("user_id") or ""
    if out.get("ok"):
        tid = out.get("task_id")
        task = out.get("task") if isinstance(out.get("task"), dict) else {}
        approve_args = {"task_id": tid}
        summary = _say(
            state,
            "delete_approval",
            {"task": task, "proposed_action": approve_args},
        )
        sid = state.get("session_id")
        session = None
        if sid:
            session = AgentSession.objects.filter(pk=sid, user_id=user_id).first()
        ar = ApprovalRequest.objects.create(
            user_id=user_id,
            agent_session=session,
            skill_name="delete_task",
            args_json=approve_args,
            summary=(summary or "")[:500],
        )
        state["response"] = {
            "type": "approval_required",
            "approval_id": str(ar.id),
            "skill_name": "delete_task",
            "summary": summary,
            "task_preview": task,
            "proposed_action": {"skill_name": "delete_task", "args": approve_args},
        }
        return

    err = out.get("error")
    if err == "ambiguous":
        items = out.get("items") if isinstance(out.get("items"), list) else []
        state["response"] = {
            "type": "query_result",
            "items": items,
            "text": _say(
                state,
                "delete_ambiguous",
                {
                    "q": out.get("q"),
                    "count": out.get("count", len(items)),
                    "items": items,
                    "match_by": "title",
                },
            ),
        }
        return

    state["response"] = {
        "type": "message",
        "text": _say(
            state,
            "delete_resolve_failed",
            {"error": err, "q": out.get("q") or args.get("q"), "args": args},
        ),
    }


def _compose_tool_failure(state: AgentState, tool_name: str, out: dict) -> None:
    err = out.get("error")
    if err == "validation":
        scene = "tool_validation"
        facts = {"tool": tool_name, "code": out.get("code")}
    elif err == "unknown_tool":
        scene = "unknown_tool"
        facts = {"tool": out.get("tool")}
    elif err == "invalid_decision":
        scene = "invalid_decision"
        facts = {}
    elif err == "invalid_task_draft_type":
        scene = "invalid_task_draft"
        facts = {"draft": out.get("draft")}
    elif err == "unsupported_action":
        scene = "unsupported_action"
        facts = {"action": out.get("action")}
    elif err == "tool_exception":
        scene = "tool_exception"
        facts = {"tool": tool_name, "detail": out.get("detail")}
    elif err == "approval_not_configured":
        scene = "approval_not_configured"
        facts = {"tool": tool_name}
    else:
        scene = "tool_error"
        facts = {"tool": tool_name, "output": out}

    state["response"] = {
        "type": "message",
        "text": _say(state, scene, facts),
    }


def _compose_response(state: AgentState) -> AgentState:
    if _terminal_response(state.get("response")):
        return state

    text = state.get("input_text") or ""
    last_tool = state.get("last_tool")

    if isinstance(last_tool, dict):
        tool_name = str(last_tool.get("tool") or "")
        out = last_tool.get("output") or {}
        args = last_tool.get("args") or {}

        if out.get("ok") is False and out.get("error") in (
            "validation",
            "unknown_tool",
            "invalid_decision",
            "invalid_task_draft_type",
            "unsupported_action",
            "tool_exception",
            "approval_not_configured",
        ):
            _compose_tool_failure(state, tool_name, out)
            return state

        if tool_name == "delete_task":
            _compose_delete_task(state, out, args)
            return state

        if tool_name == "build_task_draft":
            _compose_build_task_draft(state, out)
            return state

        if tool_name == "check_block_conflict":
            if out.get("ok") is False:
                state["response"] = {
                    "type": "message",
                    "text": _say(
                        state,
                        "block_conflict_invalid_range",
                        {"error": out.get("error"), "args": args},
                    ),
                }
            else:
                _compose_check_block_conflict(state, out, args)
            return state

        if tool_name == "search_tasks":
            if out.get("ok") is False:
                state["response"] = {
                    "type": "message",
                    "text": _say(
                        state,
                        "search_failed",
                        {"error": out.get("error"), "args": args},
                    ),
                }
                return state
            items = out.get("items") if isinstance(out.get("items"), list) else []
            count = int(out.get("count", len(items)) or 0)
            range_applied = bool(out.get("range_applied"))
            if not items:
                state["response"] = {
                    "type": "query_result",
                    "items": [],
                    "text": _say(
                        state,
                        "search_empty",
                        {
                            "range_applied": range_applied,
                            "range_from": out.get("range_from"),
                            "range_to": out.get("range_to"),
                            "args": args,
                        },
                    ),
                }
            else:
                state["response"] = {
                    "type": "query_result",
                    "items": items,
                    "text": _say(
                        state,
                        "search_results",
                        {
                            "count": count,
                            "items": items,
                            "range_applied": range_applied,
                        },
                    ),
                }
            return state

        if tool_name == "plan_gather_requirements":
            if not out.get("ok"):
                state["response"] = {
                    "type": "message",
                    "text": _say(
                        state,
                        "plan_tool_failed",
                        {"tool": tool_name, "error": out.get("error")},
                    ),
                }
                return state
            state["response"] = compose_plan_questions(out)
            return state

        if tool_name == "plan_generate_outline":
            if not out.get("ok"):
                state["response"] = {
                    "type": "message",
                    "text": _say(
                        state,
                        "plan_tool_failed",
                        {"tool": tool_name, "error": out.get("error")},
                    ),
                }
                return state
            state["response"] = compose_plan_outline(out)
            return state

        if tool_name == "plan_schedule_tasks":
            if not out.get("ok"):
                state["response"] = {
                    "type": "message",
                    "text": _say(
                        state,
                        "plan_tool_failed",
                        {"tool": tool_name, "error": out.get("error")},
                    ),
                }
                return state
            state["response"] = compose_schedule_preview(out)
            return state

        if out.get("ok") is False:
            _compose_tool_failure(state, tool_name, out)
            return state

    logger.warning("compose_response fallback: last_tool=%s", last_tool)
    state["response"] = {
        "type": "message",
        "text": _say(state, "compose_fallback", {"last_tool": last_tool}),
    }
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
