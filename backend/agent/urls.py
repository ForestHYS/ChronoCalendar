from django.urls import path

from . import views
from . import audio_views

urlpatterns = [
    path("sessions/", views.AgentSessionCreateView.as_view(), name="agent-session-create"),
    path(
        "sessions/<uuid:session_id>/messages/",
        views.AgentMessageCreateView.as_view(),
        name="agent-message-create",
    ),
    path(
        "approvals/<uuid:approval_id>/",
        views.ApprovalDetailView.as_view(),
        name="agent-approval-detail",
    ),
    path(
        "approvals/<uuid:approval_id>/approve/",
        views.ApprovalApproveView.as_view(),
        name="agent-approval-approve",
    ),
    path(
        "approvals/<uuid:approval_id>/reject/",
        views.ApprovalRejectView.as_view(),
        name="agent-approval-reject",
    ),
    path(
        "confirm-plan/",
        views.ConfirmPlanView.as_view(),
        name="agent-confirm-plan",
    ),
    path(
        "llm-config/",
        views.UserLlmConfigView.as_view(),
        name="agent-llm-config",
    ),
    path(
        "llm-test/",
        views.UserLlmConfigTestView.as_view(),
        name="agent-llm-test",
    ),
    path("asr/", audio_views.AgentAsrView.as_view(), name="agent-asr"),
    path("tts/", audio_views.AgentTtsView.as_view(), name="agent-tts"),
]

