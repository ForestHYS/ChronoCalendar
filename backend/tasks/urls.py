"""
tasks/urls.py

将路由注册到 DefaultRouter，并手动添加子任务详情路由。
"""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("tags", views.TagViewSet, basename="tag")
router.register("tasks", views.TaskViewSet, basename="task")

urlpatterns = [
    path("", include(router.urls)),
    path("focus-sessions/", views.FocusSessionStartView.as_view(), name="focus-session-start"),
    path(
        "focus-sessions/<uuid:pk>/stop/",
        views.FocusSessionStopView.as_view(),
        name="focus-session-stop",
    ),
    path(
        "stats/focus/last-week/",
        views.FocusStatsLastWeekView.as_view(),
        name="focus-stats-last-week",
    ),
    # 子任务：PATCH / DELETE /subtasks/{id}/
    path(
        "subtasks/<uuid:pk>/",
        views.SubTaskDetailView.as_view(),
        name="subtask-detail",
    ),
]
