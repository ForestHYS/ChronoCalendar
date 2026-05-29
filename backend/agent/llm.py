import logging
import json
from dataclasses import dataclass
from typing import List, Optional

from django.conf import settings
from openai import OpenAI
from openai import AuthenticationError, APITimeoutError, APIConnectionError, OpenAIError

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class LlmResult:
    ok: bool
    data: Optional[dict]
    error: Optional[str] = None


def _default_model() -> str:
    return getattr(settings, "AGENT_LLM_MODEL", "gpt-4o-mini")


def _json_max_retries() -> int:
    return max(1, int(getattr(settings, "AGENT_LLM_JSON_MAX_RETRIES", 3)))


def _strip_markdown_fence(content: str) -> str:
    text = (content or "").strip()
    if not text.startswith("```"):
        return text
    parts = text.split("```")
    if len(parts) < 2:
        return text
    inner = parts[1].strip()
    if inner.lower().startswith("json"):
        inner = inner[4:].strip()
    return inner


def _extract_json_object(content: str) -> Optional[dict]:
    """从模型输出中解析 JSON 对象（容忍 markdown 包裹与前后杂文本）。"""
    text = _strip_markdown_fence(content)
    if not text:
        return None

    try:
        data = json.loads(text)
        return data if isinstance(data, dict) else None
    except json.JSONDecodeError:
        pass

    # 尝试提取第一个完整 {...} 块
    start = text.find("{")
    if start < 0:
        return None
    depth = 0
    for i in range(start, len(text)):
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                chunk = text[start : i + 1]
                try:
                    data = json.loads(chunk)
                    return data if isinstance(data, dict) else None
                except json.JSONDecodeError:
                    return None
    return None


def _invoke_chat(
    *,
    client: OpenAI,
    model: str,
    messages: List[dict],
    temperature: float,
    json_mode: bool = False,
) -> str:
    kwargs: dict = {
        "model": model,
        "messages": messages,
        "temperature": temperature,
    }
    if json_mode:
        kwargs["response_format"] = {"type": "json_object"}
    resp = client.chat.completions.create(**kwargs)
    choice = resp.choices[0]
    content = (choice.message.content or "").strip()
    if not content:
        fr = getattr(choice, "finish_reason", None)
        logger.warning(
            "LLM empty content (model=%s finish_reason=%s)",
            model,
            fr,
        )
    return content


def call_llm_json(
    system: str,
    user: str,
    *,
    messages: Optional[List[dict]] = None,
) -> LlmResult:
    """
    调用 LLM 并要求返回 JSON。
    - 若未配置 AGENT_LLM_API_KEY，则返回 ok=False（由上层走降级策略）。
    - JSON 解析失败时会重试（AGENT_LLM_JSON_MAX_RETRIES），并尝试从文本中提取 JSON。
    """
    api_key = (getattr(settings, "AGENT_LLM_API_KEY", "") or "").strip()
    if not api_key:
        logger.warning("LLM disabled: missing AGENT_LLM_API_KEY")
        return LlmResult(ok=False, data=None, error="missing AGENT_LLM_API_KEY")

    base_url = (getattr(settings, "AGENT_LLM_BASE_URL", "") or "").strip() or None
    model = _default_model()
    chat_messages: List[dict] = list(messages) if messages else [
        {"role": "system", "content": system},
        {"role": "user", "content": user},
    ]
    max_retries = _json_max_retries()
    last_snippet = ""

    try:
        client = OpenAI(api_key=api_key, base_url=base_url)
    except Exception as e:
        logger.exception("LLM client init failed")
        return LlmResult(ok=False, data=None, error=f"llm_error: {type(e).__name__}")

    for attempt in range(1, max_retries + 1):
        try:
            content = _invoke_chat(
                client=client,
                model=model,
                messages=chat_messages,
                temperature=0.2,
                json_mode=True,
            )
            last_snippet = content[:500]
            logger.info(
                "LLM response received (model=%s attempt=%s/%s chars=%s)",
                model,
                attempt,
                max_retries,
                len(content),
            )
            data = _extract_json_object(content)
            if data is not None:
                return LlmResult(ok=True, data=data)

            logger.warning(
                "LLM invalid JSON (model=%s attempt=%s/%s snippet=%r)",
                model,
                attempt,
                max_retries,
                last_snippet,
            )
            if attempt < max_retries:
                chat_messages = list(chat_messages) + [
                    {
                        "role": "user",
                        "content": (
                            "你上一条回复不是合法 JSON。请仅输出一个 JSON 对象，"
                            "不要用 markdown 代码块，不要加解释文字。"
                        ),
                    }
                ]
        except AuthenticationError:
            logger.warning("LLM auth failed (model=%s base_url=%s)", model, base_url or "default")
            return LlmResult(ok=False, data=None, error="invalid AGENT_LLM_API_KEY")
        except (APITimeoutError, APIConnectionError) as e:
            logger.warning(
                "LLM connection/timeout (model=%s attempt=%s type=%s)",
                model,
                attempt,
                type(e).__name__,
            )
            if attempt >= max_retries:
                return LlmResult(ok=False, data=None, error=f"llm_timeout: {type(e).__name__}")
        except OpenAIError as e:
            logger.warning(
                "LLM OpenAIError (model=%s attempt=%s type=%s)",
                model,
                attempt,
                type(e).__name__,
            )
            if attempt >= max_retries:
                return LlmResult(ok=False, data=None, error=f"openai_error: {type(e).__name__}")
        except Exception as e:
            logger.exception("LLM unexpected error (attempt=%s)", attempt)
            return LlmResult(ok=False, data=None, error=f"llm_error: {type(e).__name__}")

    return LlmResult(ok=False, data=None, error="LLM returned invalid JSON")


def call_llm_text(system: str, user: str) -> LlmResult:
    """
    调用 LLM 返回纯文本（仍用 LlmResult 容器，data=None，error 记录失败原因）。
    """
    api_key = (getattr(settings, "AGENT_LLM_API_KEY", "") or "").strip()
    if not api_key:
        logger.warning("LLM disabled: missing AGENT_LLM_API_KEY")
        return LlmResult(ok=False, data=None, error="missing AGENT_LLM_API_KEY")

    base_url = (getattr(settings, "AGENT_LLM_BASE_URL", "") or "").strip() or None
    model = _default_model()
    max_retries = _json_max_retries()
    try:
        client = OpenAI(api_key=api_key, base_url=base_url)
        for attempt in range(1, max_retries + 1):
            try:
                content = _invoke_chat(
                    client=client,
                    model=model,
                    messages=[
                        {"role": "system", "content": system},
                        {"role": "user", "content": user},
                    ],
                    temperature=0.6,
                )
                logger.info(
                    "LLM text response (model=%s chars=%s)",
                    model,
                    len(content),
                )
                return LlmResult(ok=True, data={"text": content})
            except (APITimeoutError, APIConnectionError, OpenAIError) as e:
                if attempt >= max_retries:
                    return LlmResult(ok=False, data=None, error=f"openai_error: {type(e).__name__}")
            except AuthenticationError:
                return LlmResult(ok=False, data=None, error="invalid AGENT_LLM_API_KEY")
        return LlmResult(ok=False, data=None, error="llm_error")
    except Exception as e:
        logger.exception("LLM text unexpected error")
        return LlmResult(ok=False, data=None, error=f"llm_error: {type(e).__name__}")
