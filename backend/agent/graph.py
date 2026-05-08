from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Literal, Optional, TypedDict

from django.utils import timezone

from langgraph.graph import END, StateGraph

from .llm import call_llm_json, call_llm_text
import logging

logger = logging.getLogger(__name__)

ToolName = Literal["search_tasks", "build_task_draft", "check_block_conflict"]


class AgentState(TypedDict, total=False):
    user_id: str
    input_text: str
    client_context: dict
    scratchpad: list
    last_tool: dict
    response: dict


def _normalize_input(state: AgentState) -> AgentState:
    text = (state.get("input_text") or "").strip()
    state["input_text"] = text
    return state


def _decide_next(state: AgentState) -> AgentState:
    """
    ReAct：让模型决定下一步：直接回复，或调用 tool。
    输出严格 JSON：
      {"action":"respond","text":"..."}
      {"action":"tool","tool":"search_tasks","args":{...}}
      {"action":"open_editor","task_draft":{...}}
    """
    if isinstance(state.get("response"), dict):
        return state

    text = state.get("input_text") or ""
    ctx = state.get("client_context") or {}
    now = timezone.now().isoformat()
    last_tool = state.get("last_tool")
    scratchpad = state.get("scratchpad") or []

    system = (
        "你是一个日程/任务 app 的 AI 助手。"
        "你可以与用户闲聊并正常用中文回复。"
        "当需要查询数据或做冲突检测/生成草稿时，必须使用工具。"
        "你必须输出严格 JSON 对象，不要输出任何额外文字。"
        "可用工具：\n"
        "1) search_tasks(args): {q, task_type, limit}\n"
        "2) build_task_draft(args): {task_type,title,description,start_at,end_at,due_at,tag_ids}\n"
        "3) check_block_conflict(args): {start_at,end_at}\n"
        "规则：\n"
        "- 创建/编辑任务不能直接落库，只能返回 open_editor + task_draft。\n"
        "- 如果用户只是问候/闲聊，直接 respond。\n"
        "- 如果你已经拿到工具结果（last_tool），请基于它给出最终 respond 或 open_editor。\n"
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

    state["last_tool"] = None
    state["scratchpad"] = scratchpad
    state["scratchpad"].append({"llm_decision": r.data})
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
    if action != "tool":
        return state

    tool = decision.get("tool")
    args = decision.get("args") or {}
    if not isinstance(args, dict):
        args = {}

    from . import tools  # local import

    user_id = state.get("user_id") or ""
    if tool == "search_tasks":
        out = tools.search_tasks(
            user_id=user_id,
            q=str(args.get("q") or ""),
            task_type=args.get("task_type"),
            limit=int(args.get("limit") or 10),
        )
    elif tool == "build_task_draft":
        out = tools.build_task_draft(
            task_type=str(args.get("task_type") or "block"),
            title=str(args.get("title") or "新任务"),
            description=str(args.get("description") or ""),
            start_at=args.get("start_at"),
            end_at=args.get("end_at"),
            due_at=args.get("due_at"),
            tag_ids=args.get("tag_ids") if isinstance(args.get("tag_ids"), list) else [],
        )
    elif tool == "check_block_conflict":
        out = tools.check_block_conflict(
            user_id=user_id,
            start_at=str(args.get("start_at") or ""),
            end_at=str(args.get("end_at") or ""),
        )
    else:
        out = {"ok": False, "error": "unknown_tool"}

    state["last_tool"] = {"tool": tool, "args": args, "output": out}
    # 清空 decision，让下一轮再 decide
    state["response"] = {}
    return state


def _compose_response(state: AgentState) -> AgentState:
    if isinstance(state.get("response"), dict):
        # 如果已经有最终响应，直接返回；否则继续
        if state["response"].get("type") in ("message", "open_editor", "query_result"):
            return state

    # 让模型基于 last_tool 产出最终回复
    text = state.get("input_text") or ""
    last_tool = state.get("last_tool")
    system = (
        "你是任务日历 app 的 AI 助手。你可以正常聊天。"
        "当 last_tool 存在时，请根据工具输出生成最终结果：\n"
        "- 如果 last_tool.tool == search_tasks：输出 {type:'query_result', items:[...], text:'...'}\n"
        "- 如果 last_tool.tool == build_task_draft：输出 {type:'open_editor', task_draft:{...}, message?:'...'}\n"
        "- 如果 last_tool.tool == check_block_conflict：你需要结合用户原始意图输出 {type:'message', text:'...'} 或在允许时输出 open_editor + conflict。\n"
        "你必须输出严格 JSON 对象。"
    )
    user = {"user_input": text, "last_tool": last_tool}
    r = call_llm_json(system=system, user=str(user))
    if not r.ok or not r.data:
        logger.warning("LLM unavailable for compose_response: %s", r.error)
        state["response"] = {"type": "message", "text": "AI 生成回复失败，请稍后再试。"}
        return state

    # 兜底：若 LLM 给出 respond/action，转成 message
    out = r.data
    if out.get("type") in ("message", "open_editor", "query_result"):
        state["response"] = out
        return state
    if out.get("action") == "respond":
        state["response"] = {"type": "message", "text": out.get("text") or "收到。"}
        return state
    state["response"] = {"type": "message", "text": "收到。"}
    return state


def build_graph():
    g = StateGraph(AgentState)
    g.add_node("NormalizeInput", _normalize_input)
    g.add_node("DecideNext", _decide_next)
    g.add_node("RunTool", _run_tool)
    g.add_node("ComposeResponse", _compose_response)

    g.set_entry_point("NormalizeInput")
    g.add_edge("NormalizeInput", "DecideNext")
    # Decide -> RunTool -> Decide (最多两轮：先拿工具结果，再生成回复)
    g.add_edge("DecideNext", "RunTool")
    g.add_edge("RunTool", "DecideNext")
    g.add_edge("DecideNext", "ComposeResponse")
    g.add_edge("ComposeResponse", END)
    return g.compile()

