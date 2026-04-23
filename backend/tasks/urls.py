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
    # 子任务：PATCH / DELETE /subtasks/{id}/
    path(
        "subtasks/<uuid:pk>/",
        views.SubTaskDetailView.as_view(),
        name="subtask-detail",
    ),
]
