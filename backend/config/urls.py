"""
config/urls.py

Base URL：/api/v1/
"""

from django.urls import include, path

urlpatterns = [
    # Auth
    path("api/v1/auth/", include("accounts.urls")),

    # 任务相关（标签 / 任务 / 子任务）
    path("api/v1/", include("tasks.urls")),
]
