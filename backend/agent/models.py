import uuid

from django.conf import settings
from django.db import models


class AgentSession(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="agent_sessions"
    )
    title = models.CharField(max_length=100, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "agent_sessions"
        ordering = ["-updated_at"]


class AgentMessage(models.Model):
    class Role(models.TextChoices):
        USER = "user", "User"
        ASSISTANT = "assistant", "Assistant"
        SYSTEM = "system", "System"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    session = models.ForeignKey(
        AgentSession, on_delete=models.CASCADE, related_name="messages"
    )
    role = models.CharField(max_length=20, choices=Role.choices)
    content_text = models.TextField(blank=True, default="")
    content_json = models.JSONField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "agent_messages"
        ordering = ["created_at"]

