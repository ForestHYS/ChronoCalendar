from rest_framework import serializers

from .models import AgentMessage, AgentSession, UserLlmConfig


class AgentSessionSerializer(serializers.ModelSerializer):
    class Meta:
        model = AgentSession
        fields = ["id", "title", "created_at", "updated_at"]
        read_only_fields = ["id", "created_at", "updated_at"]


class AgentMessageInSerializer(serializers.Serializer):
    text = serializers.CharField(allow_blank=True, max_length=5000, required=False)
    client_context = serializers.DictField(required=False)
    interaction = serializers.DictField(required=False)

    def validate(self, attrs):
        text = (attrs.get("text") or "").strip()
        interaction = attrs.get("interaction")
        if not text and not interaction:
            raise serializers.ValidationError("text 与 interaction 至少填一项")
        attrs["text"] = text or "（结构化操作）"
        return attrs


class AgentMessageOutSerializer(serializers.ModelSerializer):
    class Meta:
        model = AgentMessage
        fields = ["id", "role", "content_text", "content_json", "created_at"]
        read_only_fields = fields


class UserLlmConfigInSerializer(serializers.Serializer):
    base_url = serializers.CharField(required=False, allow_blank=True, max_length=300)
    api_key = serializers.CharField(required=False, allow_blank=True, max_length=200)
    model_name = serializers.CharField(required=False, allow_blank=True, max_length=100)
    asr_base_url = serializers.CharField(required=False, allow_blank=True, max_length=300)
    asr_api_key = serializers.CharField(required=False, allow_blank=True, max_length=200)
    asr_model = serializers.CharField(required=False, allow_blank=True, max_length=100)
    tts_base_url = serializers.CharField(required=False, allow_blank=True, max_length=300)
    tts_api_key = serializers.CharField(required=False, allow_blank=True, max_length=200)
    tts_model = serializers.CharField(required=False, allow_blank=True, max_length=100)
    tts_voice = serializers.CharField(required=False, allow_blank=True, max_length=50)


class UserLlmConfigOutSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserLlmConfig
        fields = [
            "base_url",
            "api_key",
            "model_name",
            "asr_base_url",
            "asr_api_key",
            "asr_model",
            "tts_base_url",
            "tts_api_key",
            "tts_model",
            "tts_voice",
            "updated_at",
        ]
        read_only_fields = ["updated_at"]

