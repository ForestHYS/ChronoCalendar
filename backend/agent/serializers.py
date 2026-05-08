from rest_framework import serializers

from .models import AgentMessage, AgentSession


class AgentSessionSerializer(serializers.ModelSerializer):
    class Meta:
        model = AgentSession
        fields = ["id", "title", "created_at", "updated_at"]
        read_only_fields = ["id", "created_at", "updated_at"]


class AgentMessageInSerializer(serializers.Serializer):
    text = serializers.CharField(allow_blank=False, max_length=5000)
    client_context = serializers.DictField(required=False)


class AgentMessageOutSerializer(serializers.ModelSerializer):
    class Meta:
        model = AgentMessage
        fields = ["id", "role", "content_text", "content_json", "created_at"]
        read_only_fields = fields

