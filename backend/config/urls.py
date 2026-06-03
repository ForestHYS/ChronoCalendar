"""
config/urls.py

Base URL：/api/v1/
"""

from django.urls import include, path

from .health import healthz

urlpatterns = [
    path("healthz/", healthz),

    # Auth
    path("api/v1/auth/", include("accounts.urls")),

    # Agent
    path("api/v1/agent/", include("agent.urls")),

    # 任务相关（标签 / 任务 / 子任务）
    path("api/v1/", include("tasks.urls")),
]
