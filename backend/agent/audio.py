import base64
import binascii
import json
import logging
from dataclasses import dataclass
from typing import Optional
from urllib import error as urlerror
from urllib import request as urlrequest

from django.conf import settings
from openai import (
    APIConnectionError,
    APITimeoutError,
    AuthenticationError,
    OpenAI,
    OpenAIError,
    RateLimitError,
)

logger = logging.getLogger(__name__)


DEFAULT_ASR_MODEL = "qwen3-asr-flash"
DEFAULT_TTS_MODEL = "qwen3-tts-flash"
DEFAULT_TTS_VOICE = "Cherry"
DEFAULT_ASR_BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
DEFAULT_TTS_BASE_URL = "https://dashscope.aliyuncs.com/api/v1"
QWEN_TTS_PATH = "/services/aigc/multimodal-generation/generation"
SUPPORTED_INPUT_FORMATS = {"wav", "mp3"}
SUPPORTED_OUTPUT_FORMATS = {"mp3", "wav"}
MAX_AUDIO_BYTES = 8 * 1024 * 1024


@dataclass(frozen=True)
class AudioResult:
    ok: bool
    data: Optional[dict]
    error: Optional[str] = None


def _asr_model(user_id: str) -> str:
    return _voice_config_value(user_id, "asr_model", _default_asr_model())


def _tts_model(user_id: str) -> str:
    return _voice_config_value(user_id, "tts_model", _default_tts_model())


def _tts_voice(user_id: str, requested: str) -> str:
    return (
        requested or _voice_config_value(user_id, "tts_voice", DEFAULT_TTS_VOICE)
    ).strip()


def _voice_config_value(user_id: str, field: str, default: str) -> str:
    try:
        from .models import UserLlmConfig

        cfg = UserLlmConfig.objects.filter(user_id=user_id).first()
        if cfg is not None:
            value = (getattr(cfg, field, "") or "").strip()
            if value:
                return value
    except Exception:
        pass
    return (default or "").strip()


def _default_asr_model() -> str:
    return getattr(settings, "AGENT_ASR_MODEL", "") or DEFAULT_ASR_MODEL


def _default_tts_model() -> str:
    return getattr(settings, "AGENT_TTS_MODEL", "") or DEFAULT_TTS_MODEL


def _voice_credentials(user_id: str, kind: str) -> tuple[str, Optional[str]]:
    fallback_key = (
        getattr(settings, f"AGENT_{kind.upper()}_API_KEY", "")
        or ""
    ).strip()
    fallback_base_url = (
        getattr(settings, f"AGENT_{kind.upper()}_BASE_URL", "")
        or (
            DEFAULT_ASR_BASE_URL if kind == "asr" else DEFAULT_TTS_BASE_URL
        )
    ).strip()
    try:
        from .models import UserLlmConfig

        cfg = UserLlmConfig.objects.filter(user_id=user_id).first()
    except Exception:
        cfg = None

    if cfg is None:
        return fallback_key, fallback_base_url

    api_key = (getattr(cfg, f"{kind}_api_key", "") or "").strip()
    base_url_raw = (getattr(cfg, f"{kind}_base_url", "") or "").strip()
    return (
        api_key or fallback_key,
        base_url_raw.rstrip("/") if base_url_raw else fallback_base_url.rstrip("/"),
    )


def _client_for_user(
    user_id: str,
    kind: str,
) -> tuple[Optional[OpenAI], Optional[str], Optional[str]]:
    api_key, base_url = _voice_credentials(user_id, kind)
    if not api_key:
        return None, None, "missing_api_key"
    try:
        return OpenAI(api_key=api_key, base_url=base_url), base_url, None
    except Exception as e:
        logger.exception("Audio client init failed")
        return None, base_url, f"client_init:{type(e).__name__}"


def _decode_audio(audio_base64: str) -> bytes:
    try:
        return base64.b64decode(audio_base64, validate=True)
    except (binascii.Error, ValueError) as e:
        raise ValueError("invalid_base64") from e


def _audio_data_uri(raw: bytes, audio_format: str) -> str:
    mime = "audio/mpeg" if audio_format == "mp3" else "audio/wav"
    encoded = base64.b64encode(raw).decode("ascii")
    return f"data:{mime};base64,{encoded}"


def _qwen_tts_url(base_url: Optional[str]) -> str:
    root = (base_url or DEFAULT_TTS_BASE_URL).rstrip("/")
    if root.endswith("/generation"):
        return root
    return f"{root}{QWEN_TTS_PATH}"


def _language_type(text: str) -> str:
    return "Chinese" if any("\u4e00" <= ch <= "\u9fff" for ch in text) else "English"


def _extract_tts_audio_url(data: dict) -> str:
    output = data.get("output")
    if isinstance(output, dict):
        audio = output.get("audio")
        if isinstance(audio, dict):
            url = audio.get("url")
            if isinstance(url, str) and url:
                return url
        url = output.get("url")
        if isinstance(url, str) and url:
            return url
    return ""


def _download_audio(url: str) -> tuple[bytes, str]:
    req = urlrequest.Request(url, headers={"User-Agent": "ChronoCalendar/1.0"})
    with urlrequest.urlopen(req, timeout=30) as resp:
        content_type = resp.headers.get("Content-Type", "")
        return resp.read(), content_type


def _audio_format_from_content_type(content_type: str) -> str:
    value = (content_type or "").lower()
    if "wav" in value:
        return "wav"
    return "mp3"


def transcribe_with_audio_model(
    *,
    user_id: str,
    audio_base64: str,
    audio_format: str,
) -> AudioResult:
    audio_format = (audio_format or "").strip().lower()
    if audio_format not in SUPPORTED_INPUT_FORMATS:
        return AudioResult(ok=False, data=None, error="unsupported_format")

    try:
        raw = _decode_audio(audio_base64)
    except ValueError:
        return AudioResult(ok=False, data=None, error="invalid_base64")
    if not raw:
        return AudioResult(ok=False, data=None, error="empty_audio")
    if len(raw) > MAX_AUDIO_BYTES:
        return AudioResult(ok=False, data=None, error="audio_too_large")

    client, base_url, err = _client_for_user(user_id, "asr")
    if err:
        return AudioResult(ok=False, data=None, error=err)

    model = _asr_model(user_id)
    try:
        resp = client.chat.completions.create(
            model=model,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "input_audio",
                            "input_audio": {"data": _audio_data_uri(raw, audio_format)},
                        }
                    ],
                }
            ],
            extra_body={
                "asr_options": {
                    "enable_itn": True,
                }
            },
        )
        text = (resp.choices[0].message.content or "").strip()
        return AudioResult(ok=True, data={"text": text, "model": model})
    except AuthenticationError:
        return AudioResult(ok=False, data=None, error="invalid_api_key")
    except APITimeoutError:
        return AudioResult(ok=False, data=None, error="timeout")
    except APIConnectionError:
        return AudioResult(ok=False, data=None, error="connection_error")
    except RateLimitError:
        return AudioResult(ok=False, data=None, error="rate_limit")
    except OpenAIError as e:
        logger.warning(
            "Audio ASR OpenAIError (model=%s base_url=%s type=%s)",
            model,
            base_url or "default",
            type(e).__name__,
        )
        return AudioResult(ok=False, data=None, error=f"openai_error:{type(e).__name__}")
    except Exception as e:
        logger.exception("Audio ASR unexpected error")
        return AudioResult(ok=False, data=None, error=f"audio_error:{type(e).__name__}")


def synthesize_with_audio_model(
    *,
    user_id: str,
    text: str,
    voice: str = DEFAULT_TTS_VOICE,
    audio_format: str = "mp3",
) -> AudioResult:
    text = (text or "").strip()
    voice = _tts_voice(user_id, voice)
    audio_format = (audio_format or "mp3").strip().lower()
    if not text:
        return AudioResult(ok=False, data=None, error="empty_text")
    if len(text) > 2000:
        return AudioResult(ok=False, data=None, error="text_too_long")
    if audio_format not in SUPPORTED_OUTPUT_FORMATS:
        return AudioResult(ok=False, data=None, error="unsupported_format")

    api_key, base_url = _voice_credentials(user_id, "tts")
    if not api_key:
        return AudioResult(ok=False, data=None, error="missing_api_key")

    model = _tts_model(user_id)
    try:
        payload = {
            "model": model,
            "input": {
                "text": text,
                "voice": voice,
                "language_type": _language_type(text),
            },
        }
        req = urlrequest.Request(
            _qwen_tts_url(base_url),
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with urlrequest.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        audio_url = _extract_tts_audio_url(data)
        if not audio_url:
            return AudioResult(ok=False, data=None, error="empty_audio_response")
        audio_bytes, content_type = _download_audio(audio_url)
        if not audio_bytes:
            return AudioResult(ok=False, data=None, error="empty_audio_response")
        output_format = _audio_format_from_content_type(content_type)
        mime = "audio/mpeg" if output_format == "mp3" else "audio/wav"
        return AudioResult(
            ok=True,
            data={
                "audio_base64": base64.b64encode(audio_bytes).decode("ascii"),
                "format": output_format,
                "mime_type": mime,
                "model": model,
            },
        )
    except urlerror.HTTPError as e:
        if e.code in (401, 403):
            return AudioResult(ok=False, data=None, error="invalid_api_key")
        if e.code == 429:
            return AudioResult(ok=False, data=None, error="rate_limit")
        logger.warning("Audio TTS HTTPError (model=%s status=%s)", model, e.code)
        return AudioResult(ok=False, data=None, error=f"http_error:{e.code}")
    except urlerror.URLError as e:
        reason = str(getattr(e, "reason", e))
        if "timed out" in reason.lower():
            return AudioResult(ok=False, data=None, error="timeout")
        return AudioResult(ok=False, data=None, error="connection_error")
    except Exception as e:
        logger.exception("Audio TTS unexpected error")
        return AudioResult(ok=False, data=None, error=f"audio_error:{type(e).__name__}")
