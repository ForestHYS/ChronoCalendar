"""
serializers.py

三类任务（block / ddl / todo）统一使用 TaskSerializer 处理。
序列化器基于 serializers.Serializer（非 ModelSerializer），
以便对多态字段进行精确控制。
"""

from rest_framework import serializers

from .models import SubTask, Tag, Task, TaskBlock, TaskDDL, TaskTodo

# ---------------------------------------------------------------------------
# 哨兵对象：区分「字段未传入」与「字段传入了 null」
# ---------------------------------------------------------------------------
_UNSET = object()


# ---------------------------------------------------------------------------
# Tag
# ---------------------------------------------------------------------------

class TagSerializer(serializers.ModelSerializer):
    class Meta:
        model = Tag
        fields = ["id", "name", "color", "created_at", "updated_at"]
        read_only_fields = ["id", "created_at", "updated_at"]

    def validate_name(self, value):
        n = (value or "").strip()
        if not n:
            raise serializers.ValidationError("标签名称不能为空")
        if len(n) > 20:
            raise serializers.ValidationError("标签名称不能超过 20 个字符")
        return n


# ---------------------------------------------------------------------------
# SubTask
# ---------------------------------------------------------------------------

class SubTaskSerializer(serializers.ModelSerializer):
    class Meta:
        model = SubTask
        fields = ["id", "title", "done", "order", "created_at", "updated_at"]
        read_only_fields = ["id", "created_at", "updated_at"]

    def validate_order(self, value):
        if value < 1:
            raise serializers.ValidationError("order 必须 >= 1")
        return value


# ---------------------------------------------------------------------------
# Task（多态序列化器）
# ---------------------------------------------------------------------------

class TaskSerializer(serializers.Serializer):
    """
    通用字段
    """
    # 创建时必填；更新时因 partial=True 可省略；type 不可修改
    type = serializers.ChoiceField(choices=["block", "ddl", "todo"])
    title = serializers.CharField(max_length=255)
    description = serializers.CharField(
        default="", allow_blank=True, required=False
    )
    tag_ids = serializers.ListField(
        child=serializers.UUIDField(), default=list, required=False
    )
    remind_at = serializers.DateTimeField(allow_null=True, required=False)

    """
    类型专属字段（写入）
    """
    # block
    start_at = serializers.DateTimeField(required=False)
    end_at = serializers.DateTimeField(required=False)
    # ddl / todo
    due_at = serializers.DateTimeField(allow_null=True, required=False)
    # todo
    expected_minutes = serializers.IntegerField(
        min_value=1, allow_null=True, required=False
    )
    # todo — 仅创建时可一并提交；后续通过子任务接口维护
    subtasks = serializers.ListField(
        child=serializers.DictField(), required=False, default=list, write_only=True
    )

    # ------------------------------------------------------------------
    # 字段级校验
    # ------------------------------------------------------------------

    def validate_tag_ids(self, value):
        if not value:
            return []
        request = self.context.get("request")
        user = request.user if request else None
        if user is None:
            raise serializers.ValidationError("无法获取当前用户")
        # 校验所有 tag 均属于该用户
        tags = list(Tag.objects.filter(id__in=value, user=user))
        if len(tags) != len(set(str(v) for v in value)):
            raise serializers.ValidationError("一个或多个 tag_id 无效")
        return tags  # 返回 Tag 实例列表，供 create/update 直接使用

    # ------------------------------------------------------------------
    # 对象级校验
    # ------------------------------------------------------------------

    def validate(self, data):
        task_type = data.get("type") or (
            self.instance.type if self.instance else None
        )

        if task_type == "block":
            start_at = data.get("start_at")
            end_at = data.get("end_at")
            if not self.instance:  # 创建时两者必填
                if not start_at or not end_at:
                    raise serializers.ValidationError(
                        {
                            "code": "MISSING_FIELD",
                            "message": "block 类型必须提供 start_at 和 end_at",
                        }
                    )
            if start_at and end_at and end_at <= start_at:
                raise serializers.ValidationError(
                    {
                        "code": "INVALID_TIME_RANGE",
                        "message": "end_at 必须晚于 start_at",
                    }
                )

        elif task_type == "ddl":
            if not self.instance and not data.get("due_at"):
                raise serializers.ValidationError(
                    {
                        "code": "MISSING_FIELD",
                        "message": "ddl 类型必须提供 due_at",
                    }
                )

        if task_type == "todo":
            em = data.get("expected_minutes")
            if em is not None and em is not _UNSET:
                if em < 1 or em > 99999:
                    raise serializers.ValidationError(
                        {
                            "code": "INVALID_FIELD",
                            "message": "预计投入须在 1–99999 分钟之间",
                        }
                    )

        return data

    # ------------------------------------------------------------------
    # 输出（to_representation）—— 按类型拼装响应字段
    # ------------------------------------------------------------------

    def to_representation(self, instance: Task) -> dict:
        tags_qs = instance.tags.all()
        data = {
            "id": str(instance.id),
            "type": instance.type,
            "title": instance.title,
            "description": instance.description,
            "tag_ids": [str(t.id) for t in tags_qs],
            "tags": [
                {"id": str(t.id), "name": t.name, "color": t.color}
                for t in tags_qs
            ],
            "status": instance.effective_status,
            "remind_at": instance.remind_at,
            "snoozed_until": instance.snoozed_until,
            "focus_total_seconds": instance.focus_total_seconds,
            "last_activity_at": instance.last_activity_at,
            "completed_at": instance.completed_at,
            "created_at": instance.created_at,
            "updated_at": instance.updated_at,
        }

        if instance.type == Task.Type.BLOCK and hasattr(instance, "block_detail"):
            data["start_at"] = instance.block_detail.start_at
            data["end_at"] = instance.block_detail.end_at

        elif instance.type == Task.Type.DDL and hasattr(instance, "ddl_detail"):
            data["due_at"] = instance.ddl_detail.due_at

        elif instance.type == Task.Type.TODO:
            if hasattr(instance, "todo_detail"):
                data["due_at"] = instance.todo_detail.due_at
                data["expected_minutes"] = instance.todo_detail.expected_minutes
            data["subtasks"] = SubTaskSerializer(
                instance.subtasks.all(), many=True
            ).data

        return data

    # ------------------------------------------------------------------
    # 创建
    # ------------------------------------------------------------------

    def create(self, validated_data: dict) -> Task:
        tags = validated_data.pop("tag_ids", [])
        start_at = validated_data.pop("start_at", None)
        end_at = validated_data.pop("end_at", None)
        due_at = validated_data.pop("due_at", None)
        expected_minutes = validated_data.pop("expected_minutes", None)
        subtasks_data = validated_data.pop("subtasks", [])

        task = Task.objects.create(**validated_data)

        if tags:
            task.tags.set(tags)

        if task.type == Task.Type.BLOCK:
            TaskBlock.objects.create(task=task, start_at=start_at, end_at=end_at)

        elif task.type == Task.Type.DDL:
            TaskDDL.objects.create(task=task, due_at=due_at)

        elif task.type == Task.Type.TODO:
            TaskTodo.objects.create(
                task=task, due_at=due_at, expected_minutes=expected_minutes
            )
            for st in subtasks_data:
                SubTask.objects.create(
                    task=task,
                    title=st.get("title", ""),
                    order=st.get("order", 1),
                )

        return task

    # ------------------------------------------------------------------
    # 更新（PATCH）
    # ------------------------------------------------------------------

    def update(self, instance: Task, validated_data: dict) -> Task:
        validated_data.pop("type", None)  # type 不可修改

        # 用哨兵区分"未传"与"传了 null"
        tags = validated_data.pop("tag_ids", _UNSET)
        start_at = validated_data.pop("start_at", _UNSET)
        end_at = validated_data.pop("end_at", _UNSET)
        due_at = validated_data.pop("due_at", _UNSET)
        expected_minutes = validated_data.pop("expected_minutes", _UNSET)
        validated_data.pop("subtasks", None)  # 子任务通过专属接口维护

        # 更新通用字段
        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        instance.save()

        # 更新标签
        if tags is not _UNSET:
            instance.tags.set(tags)

        # 更新类型专属字段
        if instance.type == Task.Type.BLOCK and hasattr(instance, "block_detail"):
            detail = instance.block_detail
            changed = False
            if start_at is not _UNSET:
                detail.start_at = start_at
                changed = True
            if end_at is not _UNSET:
                detail.end_at = end_at
                changed = True
            if changed:
                detail.save()

        elif instance.type == Task.Type.DDL and hasattr(instance, "ddl_detail"):
            if due_at is not _UNSET:
                instance.ddl_detail.due_at = due_at
                instance.ddl_detail.save()

        elif instance.type == Task.Type.TODO and hasattr(instance, "todo_detail"):
            detail = instance.todo_detail
            changed = False
            if due_at is not _UNSET:
                detail.due_at = due_at
                changed = True
            if expected_minutes is not _UNSET:
                detail.expected_minutes = expected_minutes
                changed = True
            if changed:
                detail.save()

        return instance
