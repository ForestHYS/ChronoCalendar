from django.urls import path

from . import views

urlpatterns = [
    path("sessions/", views.AgentSessionCreateView.as_view(), name="agent-session-create"),
    path(
        "sessions/<uuid:session_id>/messages/",
        views.AgentMessageCreateView.as_view(),
        name="agent-message-create",
    ),
]

