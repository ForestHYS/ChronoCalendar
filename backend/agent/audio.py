import base64
import binascii
import io
import logging
from dataclasses import dataclass
from typing import Optional

from django.conf import settings
from openai import (
    APIConnectionError,
    APITimeoutError,
    AuthenticationError,
    OpenAI,
    OpenAIError,
    RateLimitError,
)

from .llm import _load_llm_config

logger = logging.getLogger(__name__)


DEFAULT_ASR_MODEL = "gpt-4o-mini-transcribe"
DEFAULT_TTS_MODEL = "gpt-4o-mini-tts"
SUPPORTED_INPUT_FORMATS = {"wav", "mp3"}
SUPPORTED_OUTPUT_FORMATS = {"mp3", "wav"}
MAX_AUDIO_BYTES = 8 * 1024 * 1024


@dataclass(frozen=True)
class AudioResult:
    ok: bool
    data: Optional[dict]
    error: Optional[str] = None


def _asr_model(user_id: str) -> str:
    return _voice_config_value(
        user_id,
        "asr_model",
        getattr(settings, "AGENT_ASR_MODEL", "") or DEFAULT_ASR_MODEL,
    )


def _tts_model(user_id: str) -> str:
    return _voice_config_value(
        user_id,
        "tts_model",
        getattr(settings, "AGENT_TTS_MODEL", "") or DEFAULT_TTS_MODEL,
    )


def _tts_voice(user_id: str, requested: str) -> str:
    return (requested or _voice_config_value(user_id, "tts_voice", "alloy")).strip()


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


def _client_for_user(user_id: str) -> tuple[Optional[OpenAI], Optional[str], Optional[str]]:
    api_key, base_url, _ = _load_llm_config(user_id)
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

    client, base_url, err = _client_for_user(user_id)
    if err:
        return AudioResult(ok=False, data=None, error=err)

    model = _asr_model(user_id)
    try:
        audio_file = io.BytesIO(raw)
        audio_file.name = f"audio.{audio_format}"
        resp = client.audio.transcriptions.create(
            model=model,
            file=audio_file,
            response_format="json",
        )
        text = (getattr(resp, "text", "") or "").strip()
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
    voice: str = "alloy",
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

    client, base_url, err = _client_for_user(user_id)
    if err:
        return AudioResult(ok=False, data=None, error=err)

    model = _tts_model(user_id)
    try:
        resp = client.audio.speech.create(
            model=model,
            voice=voice,
            input=text,
            response_format=audio_format,
            instructions="Speak in a natural, clear, concise assistant voice.",
        )
        audio_bytes = _binary_response_bytes(resp)
        if not audio_bytes:
            return AudioResult(ok=False, data=None, error="empty_audio_response")
        mime = "audio/mpeg" if audio_format == "mp3" else "audio/wav"
        return AudioResult(
            ok=True,
            data={
                "audio_base64": base64.b64encode(audio_bytes).decode("ascii"),
                "format": audio_format,
                "mime_type": mime,
                "model": model,
            },
        )
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
            "Audio TTS OpenAIError (model=%s base_url=%s type=%s)",
            model,
            base_url or "default",
            type(e).__name__,
        )
        return AudioResult(ok=False, data=None, error=f"openai_error:{type(e).__name__}")
    except Exception as e:
        logger.exception("Audio TTS unexpected error")
        return AudioResult(ok=False, data=None, error=f"audio_error:{type(e).__name__}")


def _binary_response_bytes(resp) -> bytes:
    content = getattr(resp, "content", None)
    if isinstance(content, bytes):
        return content
    read = getattr(resp, "read", None)
    if callable(read):
        data = read()
        if isinstance(data, bytes):
            return data
    return b""
