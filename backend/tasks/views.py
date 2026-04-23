"""
views.py

实现三类任务（block / ddl / todo）的完整 REST 接口：

  标签
    GET    /tags/                     TagViewSet.list
    POST   /tags/                     TagViewSet.create
    PATCH  /tags/{id}/                TagViewSet.partial_update
    DELETE /tags/{id}/                TagViewSet.destroy

  任务
    GET    /tasks/                    TaskViewSet.list         （筛选/排序/分页）
    POST   /tasks/                    TaskViewSet.create
    GET    /tasks/{id}/               TaskViewSet.retrieve
    PATCH  /tasks/{id}/               TaskViewSet.partial_update
    DELETE /tasks/{id}/               TaskViewSet.destroy
    POST   /tasks/{id}/complete/      TaskViewSet.complete
    POST   /tasks/{id}/cancel/        TaskViewSet.cancel
    POST   /tasks/{id}/snooze/        TaskViewSet.snooze
    POST   /tasks/{id}/postpone/      TaskViewSet.postpone
    POST   /tasks/{id}/subtasks/      TaskViewSet.add_subtask

  子任务
    PATCH  /subtasks/{id}/            SubTaskDetailView.patch
    DELETE /subtasks/{id}/            SubTaskDetailView.delete
"""

from django.db.models import OuterRef, Q, Subquery, Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.viewsets import ViewSet

from .models import FocusSession, SubTask, Tag, Task
from .serializers import SubTaskSerializer, TagSerializer, TaskSerializer


# ---------------------------------------------------------------------------
# 响应辅助函数（统一包装格式）
# ---------------------------------------------------------------------------

def ok(data, http_status=status.HTTP_200_OK):
    return Response({"data": data}, status=http_status)


def err(code: str, message: str, details=None, http_status=status.HTTP_400_BAD_REQUEST):
    body = {"code": code, "message": message}
    if details is not None:
        body["details"] = details
    return Response({"error": body}, status=http_status)


# ---------------------------------------------------------------------------
# 查询集辅助
# ---------------------------------------------------------------------------

def _task_qs(user):
    """返回指定用户的任务查询集，附带所有关联数据（避免 N+1）。"""
    return (
        Task.objects.filter(user=user)
        .select_related("block_detail", "ddl_detail", "todo_detail")
        .prefetch_related("tags", "subtasks")
    )


# ---------------------------------------------------------------------------
# TagViewSet
# ---------------------------------------------------------------------------

class TagViewSet(ViewSet):
    permission_classes = [IsAuthenticated]

    def list(self, request):
        tags = Tag.objects.filter(user=request.user)
        return ok(TagSerializer(tags, many=True).data)

    def create(self, request):
        s = TagSerializer(data=request.data)
        if not s.is_valid():
            return err("VALIDATION_ERROR", "输入数据无效", s.errors)
        s.save(user=request.user)
        return ok(s.data, status.HTTP_201_CREATED)

    def partial_update(self, request, pk=None):
        tag = get_object_or_404(Tag, pk=pk, user=request.user)
        s = TagSerializer(tag, data=request.data, partial=True)
        if not s.is_valid():
            return err("VALIDATION_ERROR", "输入数据无效", s.errors)
        s.save()
        return ok(s.data)

    def destroy(self, request, pk=None):
        tag = get_object_or_404(Tag, pk=pk, user=request.user)
        tag.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


# ---------------------------------------------------------------------------
# TaskViewSet
# ---------------------------------------------------------------------------

class TaskViewSet(ViewSet):
    permission_classes = [IsAuthenticated]

    # ------------------------------------------------------------------ #
    # 内部辅助
    # ------------------------------------------------------------------ #

    def _get_task(self, request, pk):
        return get_object_or_404(_task_qs(request.user), pk=pk)

    def _serialize(self, task, request):
        return TaskSerializer(task, context={"request": request}).data

    # ------------------------------------------------------------------ #
    # CRUD
    # ------------------------------------------------------------------ #

    def list(self, request):
        qs = _task_qs(request.user)
        p = request.query_params
        now = timezone.now()

        # ---- 筛选 ----

        # 类型
        task_type = p.get("type")
        if task_type in ("block", "ddl", "todo"):
            qs = qs.filter(type=task_type)

        # 关键词搜索（标题）
        q = p.get("q", "").strip()
        if q:
            qs = qs.filter(title__icontains=q)

        # 标签
        tag_id = p.get("tag_id", "").strip()
        if tag_id:
            qs = qs.filter(tags__id=tag_id)

        # 状态（overdue 为计算值）
        raw_status = p.get("status", "").strip()
        overdue_condition = (
            Q(type="block", block_detail__end_at__lt=now)
            | Q(type="ddl", ddl_detail__due_at__lt=now)
            | Q(
                type="todo",
                todo_detail__due_at__isnull=False,
                todo_detail__due_at__lt=now,
            )
        )
        if raw_status == "overdue":
            qs = qs.filter(status="active").filter(overdue_condition)
        elif raw_status == "active":
            qs = qs.filter(status="active").exclude(overdue_condition)
        elif raw_status in ("completed", "cancelled"):
            qs = qs.filter(status=raw_status)

        # ---- 排序 ----
        sort = p.get("sort", "")
        if sort == "due_at_asc":
            qs = qs.order_by("ddl_detail__due_at", "todo_detail__due_at")
        elif sort == "due_at_desc":
            qs = qs.order_by("-ddl_detail__due_at", "-todo_detail__due_at")
        elif sort == "start_at_asc":
            qs = qs.order_by("block_detail__start_at")
        elif sort == "start_at_desc":
            qs = qs.order_by("-block_detail__start_at")
        elif sort == "spent_desc":
            # 用子查询聚合各任务的累计专注秒数
            focus_subq = (
                FocusSession.objects.filter(task=OuterRef("pk"), status="stopped")
                .values("task")
                .annotate(total=Sum("actual_seconds"))
                .values("total")
            )
            qs = qs.annotate(spent_total=Subquery(focus_subq)).order_by(
                "-spent_total"
            )

        # ---- 分页 ----
        try:
            page = max(int(p.get("page", 1)), 1)
            page_size = min(max(int(p.get("page_size", 20)), 1), 100)
        except (ValueError, TypeError):
            return err("INVALID_PARAM", "page 和 page_size 必须为整数")

        total = qs.count()
        items = qs[(page - 1) * page_size : page * page_size]

        return ok(
            {
                "items": TaskSerializer(
                    items, many=True, context={"request": request}
                ).data,
                "page": page,
                "page_size": page_size,
                "total": total,
            }
        )

    def create(self, request):
        s = TaskSerializer(data=request.data, context={"request": request})
        if not s.is_valid():
            return err("VALIDATION_ERROR", "输入数据无效", s.errors)
        task = s.save(user=request.user)
        # 重新从库中拉取（带关联数据）后返回
        task = get_object_or_404(_task_qs(request.user), pk=task.pk)
        return ok(self._serialize(task, request), status.HTTP_201_CREATED)

    def retrieve(self, request, pk=None):
        task = self._get_task(request, pk)
        return ok(self._serialize(task, request))

    def partial_update(self, request, pk=None):
        task = self._get_task(request, pk)
        s = TaskSerializer(
            task, data=request.data, partial=True, context={"request": request}
        )
        if not s.is_valid():
            return err("VALIDATION_ERROR", "输入数据无效", s.errors)
        s.save()
        # 重新拉取以反映最新状态
        task = self._get_task(request, pk)
        return ok(self._serialize(task, request))

    def destroy(self, request, pk=None):
        task = self._get_task(request, pk)
        task.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    # ------------------------------------------------------------------ #
    # 状态操作
    # ------------------------------------------------------------------ #

    @action(detail=True, methods=["post"])
    def complete(self, request, pk=None):
        task = self._get_task(request, pk)
        if task.status == Task.Status.COMPLETED:
            return err("ALREADY_COMPLETED", "任务已处于完成状态")
        task.status = Task.Status.COMPLETED
        task.completed_at = timezone.now()
        task.save()
        return ok(self._serialize(self._get_task(request, pk), request))

    @action(detail=True, methods=["post"])
    def cancel(self, request, pk=None):
        task = self._get_task(request, pk)
        if task.status == Task.Status.CANCELLED:
            return err("ALREADY_CANCELLED", "任务已处于取消状态")
        task.status = Task.Status.CANCELLED
        task.cancelled_at = timezone.now()
        task.save()
        return ok(self._serialize(self._get_task(request, pk), request))

    @action(detail=True, methods=["post"])
    def snooze(self, request, pk=None):
        """稍后完成：记录 snoozed_until，供客户端重新调度本地提醒。"""
        task = self._get_task(request, pk)
        until = request.data.get("until")
        if not until:
            return err("MISSING_FIELD", "'until' 为必填项")
        task.snoozed_until = until
        task.last_activity_at = timezone.now()
        task.save()
        return ok(self._serialize(self._get_task(request, pk), request))

    @action(detail=True, methods=["post"])
    def postpone(self, request, pk=None):
        """
        任务延期：
          - ddl：更新 due_at，重置 status 为 active
          - todo：更新 due_at，重置 status 为 active
          - block：不支持延期，应通过 PATCH 更新 end_at
        """
        task = self._get_task(request, pk)
        due_at = request.data.get("due_at")
        if not due_at:
            return err("MISSING_FIELD", "'due_at' 为必填项")

        if task.type == Task.Type.DDL:
            task.ddl_detail.due_at = due_at
            task.ddl_detail.save()
        elif task.type == Task.Type.TODO:
            task.todo_detail.due_at = due_at
            task.todo_detail.save()
        else:
            return err(
                "INVALID_OPERATION",
                "block 任务不支持延期，请通过 PATCH 更新 end_at",
                http_status=status.HTTP_422_UNPROCESSABLE_ENTITY,
            )

        task.status = Task.Status.ACTIVE
        task.save()
        return ok(self._serialize(self._get_task(request, pk), request))

    # ------------------------------------------------------------------ #
    # 子任务（创建）
    # ------------------------------------------------------------------ #

    @action(detail=True, methods=["post"], url_path="subtasks")
    def add_subtask(self, request, pk=None):
        task = self._get_task(request, pk)
        if task.type != Task.Type.TODO:
            return err(
                "INVALID_OPERATION",
                "只有 todo 类型任务支持子任务",
                http_status=status.HTTP_422_UNPROCESSABLE_ENTITY,
            )
        s = SubTaskSerializer(data=request.data)
        if not s.is_valid():
            return err("VALIDATION_ERROR", "输入数据无效", s.errors)
        subtask = s.save(task=task)
        task.last_activity_at = timezone.now()
        task.save()
        return ok(SubTaskSerializer(subtask).data, status.HTTP_201_CREATED)


# ---------------------------------------------------------------------------
# SubTaskDetailView（PATCH / DELETE /subtasks/{id}/）
# ---------------------------------------------------------------------------

class SubTaskDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def _get_subtask(self, request, pk):
        # task__user 保证只能访问自己的子任务
        return get_object_or_404(SubTask, pk=pk, task__user=request.user)

    def patch(self, request, pk):
        subtask = self._get_subtask(request, pk)
        s = SubTaskSerializer(subtask, data=request.data, partial=True)
        if not s.is_valid():
            return err("VALIDATION_ERROR", "输入数据无效", s.errors)

        # 自动维护 done_at
        extra = {}
        if request.data.get("done") is True and not subtask.done:
            extra["done_at"] = timezone.now()
        elif request.data.get("done") is False:
            extra["done_at"] = None

        s.save(**extra)

        # 更新父任务活跃时间
        task = subtask.task
        task.last_activity_at = timezone.now()
        task.save()

        return ok(SubTaskSerializer(s.instance).data)

    def delete(self, request, pk):
        subtask = self._get_subtask(request, pk)
        subtask.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)
