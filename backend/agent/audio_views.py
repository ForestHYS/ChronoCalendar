from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.views import APIView

from tasks.views import err, ok

from .audio import synthesize_with_audio_model, transcribe_with_audio_model


class AgentAsrView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        audio_base64 = request.data.get("audio_base64")
        audio_format = request.data.get("format") or "wav"
        if not isinstance(audio_base64, str) or not audio_base64.strip():
            return err("VALIDATION_ERROR", "audio_base64 不能为空")

        result = transcribe_with_audio_model(
            user_id=str(request.user.id),
            audio_base64=audio_base64,
            audio_format=str(audio_format),
        )
        if result.ok:
            return ok(result.data)

        return _audio_error_response(result.error, default="语音识别失败")


class AgentTtsView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        text = request.data.get("text")
        if not isinstance(text, str) or not text.strip():
            return err("VALIDATION_ERROR", "text 不能为空")

        result = synthesize_with_audio_model(
            user_id=str(request.user.id),
            text=text,
            voice=str(request.data.get("voice") or ""),
            audio_format=str(request.data.get("format") or "mp3"),
        )
        if result.ok:
            return ok(result.data)

        return _audio_error_response(result.error, default="语音合成失败")


def _audio_error_response(code: str | None, *, default: str):
    if code == "missing_api_key":
        return err("MISSING_API_KEY", "请先在 AI 配置中填写 API Key")
    if code == "invalid_api_key":
        return err("INVALID_API_KEY", "API Key 无效或已过期")
    if code == "timeout":
        return err("TIMEOUT", "语音服务连接超时，请稍后重试")
    if code == "connection_error":
        return err("CONNECTION_FAILED", "无法连接语音服务，请检查 Base URL")
    if code in {"rate_limit", "openai_error:RateLimitError"}:
        return err(
            "RATE_LIMIT",
            "语音服务额度不足或请求过于频繁，请稍后重试或更换可用的 ASR/TTS 服务配置",
            http_status=status.HTTP_429_TOO_MANY_REQUESTS,
        )
    if code == "unsupported_format":
        return err("UNSUPPORTED_AUDIO_FORMAT", "暂不支持该音频格式")
    if code == "invalid_base64":
        return err("VALIDATION_ERROR", "音频编码格式无效")
    if code == "empty_audio":
        return err("VALIDATION_ERROR", "音频内容为空")
    if code == "audio_too_large":
        return err("PAYLOAD_TOO_LARGE", "音频文件过大，请缩短录音")
    if code == "empty_text":
        return err("VALIDATION_ERROR", "文本不能为空")
    if code == "text_too_long":
        return err("VALIDATION_ERROR", "文本过长，请缩短后再朗读")
    if code == "empty_audio_response":
        return err("AUDIO_EMPTY", "语音服务没有返回音频")
    return err("AUDIO_ERROR", default, {"reason": code or "unknown"})
