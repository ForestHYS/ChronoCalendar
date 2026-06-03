"""根据结构化工具/解析结果，由 LLM 生成面向用户的自然语言回复。"""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, Optional

from .llm import call_llm_text

logger = logging.getLogger(__name__)

_COMPOSE_FALLBACK = "暂时无法生成回复，请稍后重试。"


def compose_user_text(
    *,
    user_input: str,
    intent: Optional[str],
    scene: str,
    facts: Dict[str, Any],
    user_id: Optional[str] = None,
    history_summary: Optional[str] = None,
) -> str:
    """
    用 LLM 将客观 facts 组织成中文回复。不预设固定句式；失败时返回极短兜底。
    """
    system = (
        "你是日程 app 助手。根据 user_input 与 facts 中的客观数据，用自然中文回复（通常 1～4 句）。\n"
        "只使用 facts 中已有信息，勿编造任务、时间、id 或操作结果。勿要求用户提供 UUID。\n"
        "语气简洁友好，避免套话模板。\n"
        f"scene={scene}\n"
    )
    payload: Dict[str, Any] = {
        "user_input": user_input,
        "intent": intent,
        "facts": facts,
    }
    if history_summary:
        payload["history_summary"] = history_summary

    r = call_llm_text(
        system=system,
        user=json.dumps(payload, ensure_ascii=False),
        user_id=user_id,
    )
    if r.ok and r.data and (r.data.get("text") or "").strip():
        return str(r.data["text"]).strip()
    logger.warning("compose_user_text failed scene=%s err=%s", scene, r.error)
    return _COMPOSE_FALLBACK
