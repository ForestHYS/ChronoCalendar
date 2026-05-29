import uuid

from django.contrib.auth.models import AbstractUser
from django.db import models
from django.db.models import Sum
from django.utils import timezone


# ---------------------------------------------------------------------------
# User
# ---------------------------------------------------------------------------

class User(AbstractUser):
    """自定义用户，以 email 为登录字段，主键改为 UUID。"""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField(unique=True)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = ["username"]

    class Meta:
        db_table = "users"


# ---------------------------------------------------------------------------
# Tag（用户自定义标签）
# ---------------------------------------------------------------------------

class Tag(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="tags")
    name = models.CharField(max_length=50)
    color = models.CharField(max_length=7, default="#6366F1")  # #RRGGBB
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "tags"
        unique_together = ("user", "name")

    def __str__(self):
        return self.name


# ---------------------------------------------------------------------------
# Task（统一任务母表）
# ---------------------------------------------------------------------------

class Task(models.Model):
    class Type(models.TextChoices):
        BLOCK = "block", "Block"
        DDL = "ddl", "DDL"
        TODO = "todo", "Todo"

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        COMPLETED = "completed", "Completed"
        CANCELLED = "cancelled", "Cancelled"
        # "overdue" 不落库，由 effective_status 计算返回

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="tasks")
    type = models.CharField(max_length=10, choices=Type.choices, db_index=True)
    title = models.CharField(max_length=255)
    description = models.TextField(blank=True, default="")
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.ACTIVE, db_index=True
    )
    tags = models.ManyToManyField(
        Tag, through="TaskTag", blank=True, related_name="tasks"
    )
    remind_at = models.DateTimeField(null=True, blank=True)
    last_activity_at = models.DateTimeField(auto_now_add=True, db_index=True)
    snoozed_until = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "tasks"
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["user", "status", "type"]),
            models.Index(fields=["user", "last_activity_at"]),
        ]

    def __str__(self):
        return f"[{self.type}] {self.title}"

    # ------------------------------------------------------------------
    # 计算属性
    # ------------------------------------------------------------------

    @property
    def is_overdue(self) -> bool:
        """
        overdue 不存库，运行时按类型比较截止时间计算。
        仅 status=active 的任务才可能 overdue。
        """
        if self.status != self.Status.ACTIVE:
            return False
        now = timezone.now()
        if self.type == self.Type.BLOCK:
            return hasattr(self, "block_detail") and self.block_detail.end_at < now
        if self.type == self.Type.DDL:
            return hasattr(self, "ddl_detail") and self.ddl_detail.due_at < now
        if self.type == self.Type.TODO:
            return (
                hasattr(self, "todo_detail")
                and self.todo_detail.due_at is not None
                and self.todo_detail.due_at < now
            )
        return False

    @property
    def effective_status(self) -> str:
        return "overdue" if self.is_overdue else self.status

    @property
    def focus_total_seconds(self) -> int:
        result = self.focus_sessions.filter(status="stopped").aggregate(
            total=Sum("actual_seconds")
        )
        return result["total"] or 0


# ---------------------------------------------------------------------------
# TaskTag（任务-标签 多对多中间表）
# ---------------------------------------------------------------------------

class TaskTag(models.Model):
    task = models.ForeignKey(Task, on_delete=models.CASCADE)
    tag = models.ForeignKey(Tag, on_delete=models.CASCADE)

    class Meta:
        db_table = "task_tags"
        unique_together = ("task", "tag")


# ---------------------------------------------------------------------------
# Block 扩展表：固定时间段任务
# ---------------------------------------------------------------------------

class TaskBlock(models.Model):
    task = models.OneToOneField(
        Task,
        on_delete=models.CASCADE,
        primary_key=True,
        related_name="block_detail",
    )
    start_at = models.DateTimeField(db_index=True)
    end_at = models.DateTimeField(db_index=True)

    class Meta:
        db_table = "task_block"
        constraints = [
            models.CheckConstraint(
                check=models.Q(end_at__gt=models.F("start_at")),
                name="block_end_after_start",
            )
        ]


# ---------------------------------------------------------------------------
# DDL 扩展表：仅截止时间任务
# ---------------------------------------------------------------------------

class TaskDDL(models.Model):
    task = models.OneToOneField(
        Task,
        on_delete=models.CASCADE,
        primary_key=True,
        related_name="ddl_detail",
    )
    due_at = models.DateTimeField(db_index=True)

    class Meta:
        db_table = "task_ddl"


# ---------------------------------------------------------------------------
# Todo 扩展表：可含子任务 / 预期时长的待办
# ---------------------------------------------------------------------------

class TaskTodo(models.Model):
    task = models.OneToOneField(
        Task,
        on_delete=models.CASCADE,
        primary_key=True,
        related_name="todo_detail",
    )
    expected_minutes = models.PositiveIntegerField(null=True, blank=True)
    due_at = models.DateTimeField(null=True, blank=True, db_index=True)

    class Meta:
        db_table = "task_todo"


# ---------------------------------------------------------------------------
# SubTask（todo 专属子任务）
# ---------------------------------------------------------------------------

class SubTask(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    task = models.ForeignKey(Task, on_delete=models.CASCADE, related_name="subtasks")
    title = models.CharField(max_length=255)
    done = models.BooleanField(default=False, db_index=True)
    order = models.PositiveIntegerField(default=1)
    done_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "subtasks"
        ordering = ["order"]

    def __str__(self):
        return self.title


# ---------------------------------------------------------------------------
# FocusSession（番茄钟会话；此处仅定义模型供 focus_total_seconds 聚合使用）
# ---------------------------------------------------------------------------

class FocusSession(models.Model):
    class Status(models.TextChoices):
        RUNNING = "running", "Running"
        STOPPED = "stopped", "Stopped"

    class StopReason(models.TextChoices):
        MANUAL = "manual", "Manual"
        APP_KILLED = "app_killed", "App Killed"
        TIMEOUT = "timeout", "Timeout"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        User, on_delete=models.CASCADE, related_name="focus_sessions"
    )
    task = models.ForeignKey(
        Task, on_delete=models.SET_NULL, null=True, blank=True, related_name="focus_sessions"
    )
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.RUNNING
    )
    started_at = models.DateTimeField(auto_now_add=True)
    ended_at = models.DateTimeField(null=True, blank=True)
    planned_seconds = models.PositiveIntegerField()
    actual_seconds = models.PositiveIntegerField(null=True, blank=True)
    stop_reason = models.CharField(
        max_length=20, choices=StopReason.choices, null=True, blank=True
    )
    noise_id = models.CharField(max_length=50, blank=True, default="")

    class Meta:
        db_table = "focus_sessions"
        indexes = [
            models.Index(fields=["user", "started_at"]),
            models.Index(fields=["task", "status"]),
        ]
