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
    GET    /tasks/export/             TaskViewSet.export
    POST   /tasks/import/             TaskViewSet.import_data

  子任务
    PATCH  /subtasks/{id}/            SubTaskDetailView.patch
    DELETE /subtasks/{id}/            SubTaskDetailView.delete
"""

import uuid

from django.db import IntegrityError, transaction
from django.db.models import OuterRef, Q, Subquery, Sum
from django.shortcuts import get_object_or_404
from django.utils.dateparse import parse_datetime
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.viewsets import ViewSet

from .models import FocusSession, SubTask, Tag, Task, TaskBlock, TaskDDL, TaskTodo
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
# 导入 / 导出
# ---------------------------------------------------------------------------

EXPORT_VERSION = 1


def _iso(dt):
    return dt.isoformat() if dt else None


def _build_export(user) -> dict:
    """构建当前用户的全量任务导出 JSON。"""
    tags = list(Tag.objects.filter(user=user))
    tasks = list(_task_qs(user).prefetch_related("focus_sessions"))

    tag_items = [
        {"id": str(t.id), "name": t.name, "color": t.color}
        for t in tags
    ]

    task_items = []
    for t in tasks:
        item = {
            "id": str(t.id),
            "type": t.type,
            "title": t.title,
            "description": t.description,
            "status": t.status,
            "remind_at": _iso(t.remind_at),
            "created_at": _iso(t.created_at),
            "completed_at": _iso(t.completed_at),
            "cancelled_at": _iso(t.cancelled_at),
            "tag_ids": [str(tag.id) for tag in t.tags.all()],
            "focus_sessions": [
                {
                    "id": str(fs.id),
                    "status": fs.status,
                    "started_at": _iso(fs.started_at),
                    "ended_at": _iso(fs.ended_at),
                    "planned_seconds": fs.planned_seconds,
                    "actual_seconds": fs.actual_seconds,
                    "stop_reason": fs.stop_reason or None,
                    "noise_id": fs.noise_id,
                }
                for fs in t.focus_sessions.all()
            ],
        }
        if t.type == Task.Type.BLOCK and hasattr(t, "block_detail"):
            item["block"] = {
                "start_at": _iso(t.block_detail.start_at),
                "end_at": _iso(t.block_detail.end_at),
            }
        elif t.type == Task.Type.DDL and hasattr(t, "ddl_detail"):
            item["ddl"] = {"due_at": _iso(t.ddl_detail.due_at)}
        elif t.type == Task.Type.TODO and hasattr(t, "todo_detail"):
            item["todo"] = {
                "due_at": _iso(t.todo_detail.due_at),
                "expected_minutes": t.todo_detail.expected_minutes,
            }
            item["subtasks"] = [
                {
                    "id": str(s.id),
                    "title": s.title,
                    "done": s.done,
                    "order": s.order,
                    "done_at": _iso(s.done_at),
                    "created_at": _iso(s.created_at),
                }
                for s in t.subtasks.all()
            ]
        task_items.append(item)

    return {
        "version": EXPORT_VERSION,
        "exported_at": _iso(timezone.now()),
        "tags": tag_items,
        "tasks": task_items,
    }


def _parse_iso(value, *, field=""):
    if value is None or value == "":
        return None
    dt = parse_datetime(value)
    if dt is None:
        raise ValueError(f"{field} 不是有效的 ISO 8601 时间: {value!r}")
    return dt


def _coerce_uuid(value, *, field=""):
    try:
        return uuid.UUID(str(value))
    except (ValueError, AttributeError, TypeError):
        raise ValueError(f"{field} 不是有效的 UUID: {value!r}")


def _ensure_dict(value, *, field):
    """空 → {}；非 dict → ValueError；避免后续 .get() 抛 AttributeError 漏到 500。"""
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ValueError(f"{field} 必须为对象")
    return value


def _apply_import(user, data, mode: str) -> dict:
    """
    将导出 JSON 应用到当前用户。
    任何不通过的校验都抛 ValueError，由调用方转为 err()。
    """
    if mode not in ("merge", "duplicate"):
        raise ValueError(f"mode 必须为 merge 或 duplicate，收到 {mode!r}")
    if not isinstance(data, dict):
        raise ValueError("导入数据格式错误：顶层必须为对象")
    if data.get("version") != EXPORT_VERSION:
        raise ValueError(
            f"不支持的导出版本: {data.get('version')!r}（当前期望 {EXPORT_VERSION}）"
        )
    raw_tags = data.get("tags") or []
    raw_tasks = data.get("tasks") or []
    if not isinstance(raw_tags, list) or not isinstance(raw_tasks, list):
        raise ValueError("tags 与 tasks 必须为数组")

    summary = {
        "tags": {"created": 0, "reused": 0},
        "tasks": {"created": 0, "updated": 0},
    }

    with transaction.atomic():
        # ---- 标签：按 name 在当前用户下查或建 ----
        tag_id_map: dict = {}
        for raw in raw_tags:
            if not isinstance(raw, dict):
                raise ValueError("tags 元素必须是对象")
            name = (raw.get("name") or "").strip()
            if not name:
                raise ValueError("标签缺少 name 字段")
            old_id = raw.get("id")
            if not old_id:
                raise ValueError(f"标签 {name!r} 缺少 id 字段")
            color = (raw.get("color") or "#6366F1").strip() or "#6366F1"

            existing = Tag.objects.filter(user=user, name=name).first()
            if existing:
                tag_id_map[str(old_id)] = existing.id
                summary["tags"]["reused"] += 1
            else:
                created = Tag.objects.create(user=user, name=name, color=color)
                tag_id_map[str(old_id)] = created.id
                summary["tags"]["created"] += 1

        # ---- 任务 ----
        seen_task_ids = set()
        for raw in raw_tasks:
            if not isinstance(raw, dict):
                raise ValueError("tasks 元素必须是对象")
            old_id = raw.get("id")
            if not old_id:
                raise ValueError("任务缺少 id 字段")
            if old_id in seen_task_ids:
                raise ValueError(f"任务 id 在导入文件中重复: {old_id}")
            seen_task_ids.add(old_id)

            t_type = raw.get("type")
            if t_type not in (Task.Type.BLOCK, Task.Type.DDL, Task.Type.TODO):
                raise ValueError(f"任务 {old_id} 的 type 无效: {t_type!r}")

            t_status = raw.get("status") or Task.Status.ACTIVE
            if t_status not in (
                Task.Status.ACTIVE,
                Task.Status.COMPLETED,
                Task.Status.CANCELLED,
            ):
                raise ValueError(f"任务 {old_id} 的 status 无效: {t_status!r}")

            title = (raw.get("title") or "").strip()
            if not title:
                raise ValueError(f"任务 {old_id} 的 title 不能为空")

            common = dict(
                type=t_type,
                title=title,
                description=raw.get("description") or "",
                status=t_status,
                remind_at=_parse_iso(raw.get("remind_at"), field="remind_at"),
                completed_at=_parse_iso(raw.get("completed_at"), field="completed_at"),
                cancelled_at=_parse_iso(raw.get("cancelled_at"), field="cancelled_at"),
            )

            existing_task = None
            if mode == "merge":
                old_uuid = _coerce_uuid(old_id, field="task id")
                existing_task = Task.objects.filter(user=user, id=old_uuid).first()

            if existing_task:
                if existing_task.type != t_type:
                    raise ValueError(
                        f"任务 {old_id} 的 type 与库内记录不一致 "
                        f"(库: {existing_task.type}, 文件: {t_type})"
                    )
                # 清理旧子结构与子表，下面统一重建
                existing_task.tags.clear()
                existing_task.subtasks.all().delete()
                existing_task.focus_sessions.all().delete()
                TaskBlock.objects.filter(task=existing_task).delete()
                TaskDDL.objects.filter(task=existing_task).delete()
                TaskTodo.objects.filter(task=existing_task).delete()
                for k, v in common.items():
                    setattr(existing_task, k, v)
                existing_task.save()
                task = existing_task
                summary["tasks"]["updated"] += 1
            else:
                new_id = (
                    _coerce_uuid(old_id, field="task id")
                    if mode == "merge"
                    else uuid.uuid4()
                )
                task = Task.objects.create(user=user, id=new_id, **common)
                summary["tasks"]["created"] += 1

            # auto_now_add 会重置 created_at，需要单独 update
            created_at = _parse_iso(raw.get("created_at"), field="created_at")
            if created_at:
                Task.objects.filter(pk=task.pk).update(created_at=created_at)

            # 类型子表
            if t_type == Task.Type.BLOCK:
                blk = _ensure_dict(raw.get("block"), field=f"任务 {old_id} 的 block")
                start_at = _parse_iso(blk.get("start_at"), field="block.start_at")
                end_at = _parse_iso(blk.get("end_at"), field="block.end_at")
                if not start_at or not end_at:
                    raise ValueError(f"任务 {old_id} (block) 缺少 start_at/end_at")
                if end_at <= start_at:
                    raise ValueError(f"任务 {old_id} (block) end_at 必须晚于 start_at")
                TaskBlock.objects.create(task=task, start_at=start_at, end_at=end_at)
            elif t_type == Task.Type.DDL:
                d = _ensure_dict(raw.get("ddl"), field=f"任务 {old_id} 的 ddl")
                due_at = _parse_iso(d.get("due_at"), field="ddl.due_at")
                if not due_at:
                    raise ValueError(f"任务 {old_id} (ddl) 缺少 due_at")
                TaskDDL.objects.create(task=task, due_at=due_at)
            elif t_type == Task.Type.TODO:
                td = _ensure_dict(raw.get("todo"), field=f"任务 {old_id} 的 todo")
                em = td.get("expected_minutes")
                TaskTodo.objects.create(
                    task=task,
                    due_at=_parse_iso(td.get("due_at"), field="todo.due_at"),
                    expected_minutes=int(em) if em is not None else None,
                )
                for sub in raw.get("subtasks") or []:
                    if not isinstance(sub, dict):
                        raise ValueError(f"任务 {old_id} 的 subtasks 元素必须是对象")
                    sub_title = (sub.get("title") or "").strip()
                    if not sub_title:
                        raise ValueError(f"任务 {old_id} 的子任务 title 不能为空")
                    sub_id = (
                        _coerce_uuid(sub.get("id"), field="subtask id")
                        if mode == "merge" and sub.get("id")
                        else uuid.uuid4()
                    )
                    new_sub = SubTask.objects.create(
                        id=sub_id,
                        task=task,
                        title=sub_title,
                        done=bool(sub.get("done")),
                        order=max(1, int(sub.get("order") or 1)),
                        done_at=_parse_iso(sub.get("done_at"), field="subtask.done_at"),
                    )
                    sub_created = _parse_iso(
                        sub.get("created_at"), field="subtask.created_at"
                    )
                    if sub_created:
                        SubTask.objects.filter(pk=new_sub.pk).update(
                            created_at=sub_created
                        )

            # 标签关联
            for old_tag_id in raw.get("tag_ids") or []:
                key = str(old_tag_id)
                tag_pk = tag_id_map.get(key)
                if not tag_pk:
                    raise ValueError(
                        f"任务 {old_id} 引用未声明的 tag_id: {old_tag_id}"
                    )
                task.tags.add(tag_pk)

            # 专注会话
            valid_fs_status = {
                FocusSession.Status.RUNNING,
                FocusSession.Status.STOPPED,
            }
            for fs in raw.get("focus_sessions") or []:
                if not isinstance(fs, dict):
                    raise ValueError(
                        f"任务 {old_id} 的 focus_sessions 元素必须是对象"
                    )
                fs_status = fs.get("status") or FocusSession.Status.STOPPED
                if fs_status not in valid_fs_status:
                    raise ValueError(
                        f"任务 {old_id} 的 focus_session status 无效: {fs_status!r}"
                    )
                fs_id = (
                    _coerce_uuid(fs.get("id"), field="focus_session id")
                    if mode == "merge" and fs.get("id")
                    else uuid.uuid4()
                )
                planned = fs.get("planned_seconds")
                if planned is None:
                    raise ValueError(
                        f"任务 {old_id} 的 focus_session 缺少 planned_seconds"
                    )
                new_fs = FocusSession.objects.create(
                    id=fs_id,
                    user=user,
                    task=task,
                    status=fs_status,
                    planned_seconds=int(planned),
                    actual_seconds=fs.get("actual_seconds"),
                    ended_at=_parse_iso(
                        fs.get("ended_at"), field="focus_session.ended_at"
                    ),
                    stop_reason=fs.get("stop_reason") or None,
                    noise_id=fs.get("noise_id") or "",
                )
                started_at = _parse_iso(
                    fs.get("started_at"), field="focus_session.started_at"
                )
                if started_at:
                    FocusSession.objects.filter(pk=new_fs.pk).update(
                        started_at=started_at
                    )

    return summary


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

        # 时间范围（仅 block）
        # 用于日历区间查询 / 时间冲突检测等场景
        start_from_raw = p.get("start_from")
        start_to_raw = p.get("start_to")
        if (start_from_raw or start_to_raw) and task_type == "block":
            if start_from_raw:
                start_from = parse_datetime(start_from_raw)
                if start_from is None:
                    return err("INVALID_PARAM", "start_from 不是有效的 datetime")
                qs = qs.filter(block_detail__start_at__gte=start_from)
            if start_to_raw:
                start_to = parse_datetime(start_to_raw)
                if start_to is None:
                    return err("INVALID_PARAM", "start_to 不是有效的 datetime")
                qs = qs.filter(block_detail__start_at__lte=start_to)

        # Calendar range filter. This enhances GET /tasks/ without adding
        # another calendar-specific endpoint.
        range_from_raw = p.get("range_from")
        range_to_raw = p.get("range_to")
        if range_from_raw or range_to_raw:
            if not range_from_raw or not range_to_raw:
                return err(
                    "INVALID_PARAM",
                    "range_from and range_to must be provided together",
                )
            range_from = parse_datetime(range_from_raw)
            range_to = parse_datetime(range_to_raw)
            if range_from is None or range_to is None:
                return err(
                    "INVALID_PARAM",
                    "range_from/range_to must be valid datetimes",
                )
            if range_to <= range_from:
                return err("INVALID_PARAM", "range_to must be after range_from")
            qs = qs.filter(
                Q(
                    type="block",
                    block_detail__start_at__lt=range_to,
                    block_detail__end_at__gt=range_from,
                )
                | Q(
                    type="ddl",
                    ddl_detail__due_at__gte=range_from,
                    ddl_detail__due_at__lt=range_to,
                )
                | Q(
                    type="todo",
                    todo_detail__due_at__gte=range_from,
                    todo_detail__due_at__lt=range_to,
                )
            )

        # 关键词搜索（标题）
        q = p.get("q", "").strip()
        if q:
            qs = qs.filter(title__icontains=q)

        # 标签（支持单个 tag_id 或多个逗号分隔的 tag_ids）
        tag_ids_raw = p.get("tag_ids", "") or p.get("tag_id", "")
        tag_id_list = [t.strip() for t in tag_ids_raw.split(",") if t.strip()]
        if tag_id_list:
            for tid in tag_id_list:
                qs = qs.filter(tags__id=tid)

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
        elif sort == "created_at_desc":
            qs = qs.order_by("-created_at")
        elif sort == "created_at_asc":
            qs = qs.order_by("created_at")
        else:
            # 类型感知默认排序
            if task_type == "ddl":
                qs = qs.order_by("ddl_detail__due_at")
            elif task_type == "block":
                qs = qs.order_by("block_detail__start_at")
            elif task_type == "todo":
                qs = qs.order_by("-last_activity_at")
            else:
                qs = qs.order_by("-created_at")

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

    # ------------------------------------------------------------------ #
    # 导入 / 导出
    # ------------------------------------------------------------------ #

    @action(detail=False, methods=["get"], url_path="export")
    def export(self, request):
        """导出当前用户的全量任务数据。"""
        return ok(_build_export(request.user))

    @action(detail=False, methods=["post"], url_path="import")
    def import_data(self, request):
        """
        导入任务数据。?mode=merge|duplicate（默认 merge）。
        请求体即 _build_export 返回的对象（不带 {"data": ...} 包装）。
        """
        mode = (request.query_params.get("mode") or "merge").lower()
        try:
            summary = _apply_import(request.user, request.data, mode)
        except ValueError as e:
            return err("IMPORT_ERROR", str(e))
        except IntegrityError as e:
            return err("IMPORT_ERROR", f"数据库完整性错误: {e}")
        return ok({"mode": mode, **summary})


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
