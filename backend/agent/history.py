"""会话历史加载、格式化与超长摘要。"""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, List, Optional, Tuple

from django.conf import settings

from .llm import call_llm_json, call_llm_text
from .models import AgentMessage, AgentSession

logger = logging.getLogger(__name__)


def _max_recent_messages() -> int:
    return int(getattr(settings, "AGENT_HISTORY_MAX_MESSAGES", 16))


def _summarize_threshold() -> int:
    return int(getattr(settings, "AGENT_HISTORY_SUMMARIZE_THRESHOLD", 20))


def _assistant_content_for_history(msg: AgentMessage) -> str:
    if msg.content_text and msg.content_text.strip():
        return msg.content_text.strip()
    payload = msg.content_json if isinstance(msg.content_json, dict) else {}
    t = payload.get("type")
    if t == "open_editor":
        draft = payload.get("task_draft") if isinstance(payload.get("task_draft"), dict) else {}
        title = draft.get("title") or "未命名"
        typ = draft.get("type") or ""
        return f"[已生成任务草稿：{title}（{typ}），请用户在编辑页确认保存]"
    if t == "query_result":
        items = payload.get("items")
        n = len(items) if isinstance(items, list) else 0
        hint = payload.get("text") or ""
        return f"[查询结果：{n} 条任务。{hint}]"
    if t == "approval_required":
        return f"[需用户授权：{payload.get('summary') or ''}]"
    if t == "plan_preview":
        title = payload.get("plan_title") or "长期规划"
        tasks = payload.get("tasks")
        n = len(tasks) if isinstance(tasks, list) else 0
        return f"[长期规划预览：{title}，共 {n} 项，待用户确认创建]"
    if t == "message":
        return (payload.get("text") or "").strip() or "[助手回复]"
    return "[助手结构化回复]"


def _messages_to_llm_turns(messages: List[AgentMessage]) -> List[Dict[str, str]]:
    turns: List[Dict[str, str]] = []
    for m in messages:
        if m.role == AgentMessage.Role.USER:
            text = (m.content_text or "").strip()
            if text:
                turns.append({"role": "user", "content": text})
        elif m.role == AgentMessage.Role.ASSISTANT:
            text = _assistant_content_for_history(m)
            if text:
                turns.append({"role": "assistant", "content": text})
    return turns


def _summarize_messages(messages: List[AgentMessage]) -> str:
    lines = []
    for m in messages:
        if m.role == AgentMessage.Role.USER:
            lines.append(f"用户：{(m.content_text or '').strip()}")
        elif m.role == AgentMessage.Role.ASSISTANT:
            lines.append(f"助手：{_assistant_content_for_history(m)}")
    blob = "\n".join(lines)[:12000]
    system = (
        "请将以下多轮对话压缩为简短中文摘要（200字以内），保留：用户目标、已创建/查询的任务名、"
        "时间约定、待办与未决事项。不要编造未出现的信息。"
    )
    r = call_llm_text(system=system, user=blob)
    if r.ok and r.data and r.data.get("text"):
        return str(r.data["text"]).strip()
    logger.warning("history summarize failed: %s", r.error)
    return blob[:500] + ("…" if len(blob) > 500 else "")


def prepare_conversation_context(
    session: AgentSession,
) -> Tuple[Optional[str], List[Dict[str, str]]]:
    """
    返回 (history_summary, recent_llm_messages)。
    超出阈值时更新 session.conversation_summary 并截断近期窗口。
    """
    all_msgs = list(session.messages.order_by("created_at"))
    max_recent = _max_recent_messages()
    threshold = _summarize_threshold()

    if len(all_msgs) <= max_recent:
        summary = (session.conversation_summary or "").strip() or None
        return summary, _messages_to_llm_turns(all_msgs)

    split_at = len(all_msgs) - max_recent
    older = all_msgs[:split_at]
    recent = all_msgs[split_at:]

    summary = (session.conversation_summary or "").strip()
    through_id = session.summary_through_id

    last_older_id = older[-1].id if older else None
    need_refresh = (
        len(all_msgs) >= threshold
        and (not summary or through_id != last_older_id)
    )

    if need_refresh and older:
        new_summary = _summarize_messages(older)
        if new_summary:
            session.conversation_summary = new_summary[:4000]
            session.summary_through_id = last_older_id
            session.save(update_fields=["conversation_summary", "summary_through_id"])
            summary = new_summary
    elif not summary and len(all_msgs) >= threshold and older:
        new_summary = _summarize_messages(older)
        if new_summary:
            session.conversation_summary = new_summary[:4000]
            session.summary_through_id = last_older_id
            session.save(update_fields=["conversation_summary", "summary_through_id"])
            summary = new_summary

    return (summary or None), _messages_to_llm_turns(recent)


def build_llm_message_list(
    *,
    system: str,
    user_payload: Dict[str, Any],
    history_summary: Optional[str],
    chat_history: List[Dict[str, str]],
) -> List[Dict[str, str]]:
    """system + 可选摘要 + 历史轮次 + 当前轮 user（JSON 载荷）。"""
    messages: List[Dict[str, str]] = [{"role": "system", "content": system}]
    if history_summary:
        messages.append(
            {
                "role": "system",
                "content": f"【更早对话摘要】\n{history_summary}",
            }
        )
    for turn in chat_history:
        role = turn.get("role")
        content = turn.get("content")
        if role in ("user", "assistant") and content:
            messages.append({"role": role, "content": str(content)})
    messages.append(
        {
            "role": "user",
            "content": json.dumps(user_payload, ensure_ascii=False),
        }
    )
    return messages
