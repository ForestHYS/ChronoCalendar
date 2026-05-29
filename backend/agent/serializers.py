from rest_framework import serializers

from .models import AgentMessage, AgentSession


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

