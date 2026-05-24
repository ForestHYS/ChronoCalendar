import logging
import json
from dataclasses import dataclass
from typing import Optional

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


def call_llm_json(system: str, user: str) -> LlmResult:
    """
    调用 LLM 并要求返回 JSON。
    - 若未配置 AGENT_LLM_API_KEY，则返回 ok=False（由上层走降级策略）。
    - 任何鉴权/网络/格式错误都不应抛出到上层（避免 API 500）。
    """
    api_key = (getattr(settings, "AGENT_LLM_API_KEY", "") or "").strip()
    if not api_key:
        logger.warning("LLM disabled: missing AGENT_LLM_API_KEY")
        return LlmResult(ok=False, data=None, error="missing AGENT_LLM_API_KEY")

    base_url = (getattr(settings, "AGENT_LLM_BASE_URL", "") or "").strip() or None
    model = _default_model()
    try:
        client = OpenAI(api_key=api_key, base_url=base_url)
        resp = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            temperature=0.2,
        )
        content = (resp.choices[0].message.content or "").strip()
        # 剥离 LLM 可能包裹的 markdown 代码块（```json ... ``` 或 ``` ... ```）
        if content.startswith("```"):
            content = content.split("```", 2)[1]
            if content.startswith("json"):
                content = content[4:]
            content = content.strip()
        logger.info(
            "LLM response received (model=%s base_url=%s chars=%s)",
            model,
            base_url or "default",
            len(content),
        )
        data = json.loads(content)
        if not isinstance(data, dict):
            logger.warning(
                "LLM returned non-object JSON (model=%s base_url=%s snippet=%r)",
                model,
                base_url or "default",
                content[:500],
            )
            return LlmResult(ok=False, data=None, error="LLM returned non-object JSON")
        return LlmResult(ok=True, data=data)
    except AuthenticationError:
        logger.warning("LLM auth failed (model=%s base_url=%s)", model, base_url or "default")
        return LlmResult(ok=False, data=None, error="invalid AGENT_LLM_API_KEY")
    except (APITimeoutError, APIConnectionError) as e:
        logger.warning(
            "LLM connection/timeout error (model=%s base_url=%s type=%s)",
            model,
            base_url or "default",
            type(e).__name__,
        )
        return LlmResult(ok=False, data=None, error=f"llm_timeout: {type(e).__name__}")
    except (ValueError, TypeError, json.JSONDecodeError) as e:
        logger.warning(
            "LLM returned invalid JSON (model=%s base_url=%s err=%s)",
            model,
            base_url or "default",
            type(e).__name__,
        )
        return LlmResult(ok=False, data=None, error="LLM returned invalid JSON")
    except OpenAIError as e:
        logger.exception(
            "LLM OpenAIError (model=%s base_url=%s type=%s)",
            model,
            base_url or "default",
            type(e).__name__,
        )
        return LlmResult(ok=False, data=None, error=f"openai_error: {type(e).__name__}")
    except Exception as e:
        logger.exception(
            "LLM unexpected error (model=%s base_url=%s type=%s)",
            model,
            base_url or "default",
            type(e).__name__,
        )
        return LlmResult(ok=False, data=None, error=f"llm_error: {type(e).__name__}")


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
    try:
        client = OpenAI(api_key=api_key, base_url=base_url)
        resp = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            temperature=0.6,
        )
        content = (resp.choices[0].message.content or "").strip()
        logger.info(
            "LLM text response received (model=%s base_url=%s chars=%s)",
            model,
            base_url or "default",
            len(content),
        )
        # 复用 LlmResult：把文本塞进 error 之外的位置不合适，这里用 data={"text":...}
        return LlmResult(ok=True, data={"text": content})
    except AuthenticationError:
        logger.warning("LLM auth failed (model=%s base_url=%s)", model, base_url or "default")
        return LlmResult(ok=False, data=None, error="invalid AGENT_LLM_API_KEY")
    except OpenAIError as e:
        logger.exception(
            "LLM OpenAIError (model=%s base_url=%s type=%s)",
            model,
            base_url or "default",
            type(e).__name__,
        )
        return LlmResult(ok=False, data=None, error=f"openai_error: {type(e).__name__}")
    except Exception as e:
        logger.exception(
            "LLM unexpected error (model=%s base_url=%s type=%s)",
            model,
            base_url or "default",
            type(e).__name__,
        )
        return LlmResult(ok=False, data=None, error=f"llm_error: {type(e).__name__}")

