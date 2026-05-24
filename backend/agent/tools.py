from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional

from django.db import transaction
from django.utils import timezone

from tasks.models import Task, TaskBlock, TaskDDL, TaskTodo, SubTask


def _parse_iso(dt: str) -> Optional[datetime]:
    try:
        return datetime.fromisoformat(dt)
    except Exception:
        return None


def search_tasks(*, user_id: str, q: str = "", task_type: Optional[str] = None, limit: int = 10) -> dict:
    qs = (
        Task.objects.filter(user_id=user_id)
        .select_related("block_detail", "ddl_detail", "todo_detail")
        .prefetch_related("tags", "subtasks")
        .order_by("-last_activity_at")
    )
    if task_type in ("block", "ddl", "todo"):
        qs = qs.filter(type=task_type)
    if q.strip():
        qs = qs.filter(title__icontains=q.strip())
    items = list(qs[: max(1, min(limit, 20))])

    results: List[Dict[str, Any]] = []
    for t in items:
        row: Dict[str, Any] = {
            "id": str(t.id),
            "type": t.type,
            "title": t.title,
            "status": t.effective_status,
        }
        if t.type == Task.Type.BLOCK and hasattr(t, "block_detail"):
            row["start_at"] = t.block_detail.start_at.isoformat()
            row["end_at"] = t.block_detail.end_at.isoformat()
        elif t.type == Task.Type.DDL and hasattr(t, "ddl_detail"):
            row["due_at"] = t.ddl_detail.due_at.isoformat()
        elif t.type == Task.Type.TODO and hasattr(t, "todo_detail") and t.todo_detail.due_at:
            row["due_at"] = t.todo_detail.due_at.isoformat()
        results.append(row)

    return {"items": results, "count": len(results)}


def build_task_draft(
    *,
    task_type: str,
    title: str,
    description: str = "",
    start_at: Optional[str] = None,
    end_at: Optional[str] = None,
    due_at: Optional[str] = None,
    tag_ids: Optional[list] = None,
) -> dict:
    # 仅构造草稿（不落库）
    d: Dict[str, Any] = {
        "type": task_type,
        "title": title,
        "description": description,
        "tag_ids": tag_ids or [],
    }
    if start_at:
        d["start_at"] = start_at
    if end_at:
        d["end_at"] = end_at
    if due_at:
        d["due_at"] = due_at
    return d


def check_block_conflict(*, user_id: str, start_at: str, end_at: str) -> dict:
    s = _parse_iso(start_at)
    e = _parse_iso(end_at)
    if not s or not e or e <= s:
        return {"ok": False, "error": "invalid_time_range"}

    overlaps = (
        Task.objects.filter(user_id=user_id, type=Task.Type.BLOCK, status=Task.Status.ACTIVE)
        .filter(block_detail__start_at__lt=e, block_detail__end_at__gt=s)
        .select_related("block_detail")
        .order_by("block_detail__start_at")[:10]
    )
    items: List[Dict[str, Any]] = []
    for t in overlaps:
        bd = t.block_detail
        items.append(
            {
                "id": str(t.id),
                "title": t.title,
                "start_at": bd.start_at.isoformat(),
                "end_at": bd.end_at.isoformat(),
            }
        )
    if not items:
        return {"ok": True, "conflict": None}

    # 建议：顺延到最早不冲突时间
    cursor = e
    for t in overlaps:
        bd = t.block_detail
        if bd.end_at > cursor:
            cursor = bd.end_at
    duration = e - s
    suggested_start = cursor
    suggested_end = cursor + duration

    return {
        "ok": True,
        "conflict": {
            "new_range": {"start_at": start_at, "end_at": end_at},
            "overlaps": items,
            "suggestions": [
                {
                    "label": "顺延到不冲突的最早时间",
                    "start_at": suggested_start.isoformat(),
                    "end_at": suggested_end.isoformat(),
                }
            ],
        },
    }


def execute_delete_task(*, user_id: str, task_id: str) -> dict:
    """真正删除任务（仅应在审批通过或受控入口调用）。"""
    t = Task.objects.filter(user_id=user_id, pk=task_id).select_related("block_detail", "ddl_detail", "todo_detail").first()
    if t is None:
        return {"ok": False, "error": "not_found"}
    title = t.title
    t.delete()
    return {"ok": True, "deleted_id": str(task_id), "title": title}


def task_summary_for_approval(*, user_id: str, task_id: str) -> dict:
    """用于审批摘要，不执行删除。"""
    t = Task.objects.filter(user_id=user_id, pk=task_id).select_related("block_detail", "ddl_detail", "todo_detail").first()
    if t is None:
        return {"ok": False, "error": "not_found"}
    row: Dict[str, Any] = {
        "id": str(t.id),
        "type": t.type,
        "title": t.title,
        "status": t.effective_status,
    }
    if t.type == Task.Type.BLOCK and hasattr(t, "block_detail"):
        row["start_at"] = t.block_detail.start_at.isoformat()
        row["end_at"] = t.block_detail.end_at.isoformat()
    elif t.type == Task.Type.DDL and hasattr(t, "ddl_detail"):
        row["due_at"] = t.ddl_detail.due_at.isoformat()
    elif t.type == Task.Type.TODO and hasattr(t, "todo_detail") and t.todo_detail.due_at:
        row["due_at"] = t.todo_detail.due_at.isoformat()
    return {"ok": True, "task": row}


# ---------------------------------------------------------------------------
# 长期规划工具
# ---------------------------------------------------------------------------

def generate_long_term_plan(
    *,
    user_id: str,
    goal: str,
    start_date: str,
    end_date: str,
    daily_hours: float = 2.0,
    create_immediately: bool = False,
) -> dict:
    """
    调用 LLM 根据目标和时间范围生成长期规划草稿。
    create_immediately=True 时直接落库创建所有任务并返回结果；
    否则返回 plan_preview 供前端确认。
    """
    from .llm import call_llm_json

    system = (
        "你是一个专业的日程规划助手。根据用户提供的目标和时间范围，"
        "制定详细、合理的长期计划，拆分成若干待办任务（todo 类型），"
        "每个待办任务下再细化出具体的子任务（subtasks）。\n\n"
        "输出必须是严格 JSON，格式如下：\n"
        '{"plan_title": "计划名称", "tasks": [\n'
        '  {"type": "todo", "title": "阶段/主题名称", "description": "该阶段目标说明", '
        '"due_at": "ISO8601日期时间（截止时间，精确到当天23:59:59）", '
        '"expected_minutes": 120, '
        '"subtasks": [{"title": "具体子任务1"}, {"title": "具体子任务2"}]}\n'
        "]}\n\n"
        "规则：\n"
        "- 按阶段或主题划分待办任务，每个 todo 对应一个独立的学习/工作主题\n"
        "- 每个 todo 下包含 2-6 个具体可操作的子任务（subtasks）\n"
        "- expected_minutes 为该 todo 预计总耗时（分钟），每天不超过 daily_hours 小时换算后合理估算\n"
        "- due_at 在 start_date 到 end_date 之间均匀分布，格式如 2026-05-25T23:59:59+08:00\n"
        "- 任务循序渐进，先基础后进阶\n"
        "- 子任务标题简洁具体，如'阅读第3章'、'完成练习题 1-10'\n"
        "- 所有 ISO8601 时间必须包含完整的日期和时间\n"
    )

    user_msg = {
        "goal": goal,
        "start_date": start_date,
        "end_date": end_date,
        "daily_hours": daily_hours,
        "now": timezone.now().isoformat(),
    }

    result = call_llm_json(system=system, user=str(user_msg))
    if not result.ok or not result.data:
        return {"ok": False, "error": "LLM 规划生成失败，请检查 LLM 配置。"}

    plan = result.data
    tasks = plan.get("tasks")
    if not isinstance(tasks, list):
        return {"ok": False, "error": "LLM 返回格式异常，tasks 字段缺失或类型错误。"}

    plan_title = plan.get("plan_title") or goal

    # create_immediately=True：直接落库，返回创建结果
    if create_immediately:
        batch_result = create_tasks_batch(user_id=user_id, tasks=tasks)
        return {
            "ok": True,
            "created_immediately": True,
            "plan_title": plan_title,
            "total_created": batch_result.get("total_created", 0),
            "created": batch_result.get("created", []),
            "errors": batch_result.get("errors", []),
        }

    return {
        "ok": True,
        "plan_title": plan_title,
        "tasks": tasks,
        "total": len(tasks),
        "create_immediately": False,
    }


def create_tasks_batch(*, user_id: str, tasks: list) -> dict:
    """
    批量创建任务（直接落库）。由 ConfirmPlanView 调用，不经过 LLM 决策。
    每条 task 字段：type, title, description, start_at, end_at, due_at, remind_at
    """
    created: List[Dict[str, Any]] = []
    errors: List[Dict[str, Any]] = []

    for task_data in tasks:
        if not isinstance(task_data, dict):
            continue
        try:
            with transaction.atomic():
                task = Task(
                    user_id=user_id,
                    type=task_data.get("type") or "block",
                    title=(task_data.get("title") or "未命名任务")[:255],
                    description=task_data.get("description") or "",
                )
                remind_raw = task_data.get("remind_at")
                if remind_raw:
                    parsed_remind = _parse_iso(str(remind_raw))
                    if parsed_remind:
                        task.remind_at = parsed_remind
                task.save()

                t_type = task.type
                if t_type == Task.Type.BLOCK:
                    s = _parse_iso(str(task_data.get("start_at") or ""))
                    e = _parse_iso(str(task_data.get("end_at") or ""))
                    if s and e and e > s:
                        TaskBlock.objects.create(task=task, start_at=s, end_at=e)
                elif t_type == Task.Type.DDL:
                    d = _parse_iso(str(task_data.get("due_at") or ""))
                    if d:
                        TaskDDL.objects.create(task=task, due_at=d)
                elif t_type == Task.Type.TODO:
                    d = _parse_iso(str(task_data.get("due_at") or ""))
                    expected = task_data.get("expected_minutes")
                    try:
                        expected = int(expected) if expected is not None else None
                    except (TypeError, ValueError):
                        expected = None
                    TaskTodo.objects.create(task=task, due_at=d, expected_minutes=expected)
                    subtasks_data = task_data.get("subtasks") or []
                    if isinstance(subtasks_data, list):
                        for order, sub in enumerate(subtasks_data, start=1):
                            if isinstance(sub, dict) and sub.get("title"):
                                SubTask.objects.create(
                                    task=task,
                                    title=str(sub["title"])[:255],
                                    order=order,
                                )

                created.append({"id": str(task.id), "title": task.title})
        except Exception as exc:
            errors.append({"title": task_data.get("title") or "", "error": str(exc)})

    return {
        "ok": True,
        "created": created,
        "errors": errors,
        "total_created": len(created),
    }

