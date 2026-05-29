from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional

from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from django.utils.dateparse import parse_datetime

from tasks.models import Task, TaskBlock, TaskDDL, TaskTodo, SubTask

from .timezone_ctx import format_dt_local, resolve_user_tz, user_now_payload


def _parse_iso(
    dt: str,
    *,
    client_context: Optional[Dict[str, Any]] = None,
) -> Optional[datetime]:
    if not dt:
        return None
    raw = str(dt).strip()
    parsed = parse_datetime(raw)
    if parsed is None:
        try:
            parsed = datetime.fromisoformat(raw)
        except Exception:
            return None
    if timezone.is_aware(parsed):
        return parsed
    tz = resolve_user_tz(client_context)
    return timezone.make_aware(parsed, tz)


def _task_to_search_row(
    t: Task,
    *,
    client_context: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    row: Dict[str, Any] = {
        "id": str(t.id),
        "type": t.type,
        "title": t.title,
        "status": t.effective_status,
        "time_summary": "",
    }
    if t.type == Task.Type.BLOCK and hasattr(t, "block_detail"):
        bd = t.block_detail
        row["start_at"] = bd.start_at.isoformat()
        row["end_at"] = bd.end_at.isoformat()
        s = format_dt_local(bd.start_at, client_context)
        e = format_dt_local(bd.end_at, client_context)
        row["time_summary"] = f"{s} — {e}" if s and e else ""
    elif t.type == Task.Type.DDL and hasattr(t, "ddl_detail"):
        d = t.ddl_detail.due_at
        row["due_at"] = d.isoformat()
        due = format_dt_local(d, client_context)
        row["time_summary"] = f"截止 {due}" if due else ""
    elif t.type == Task.Type.TODO and hasattr(t, "todo_detail"):
        td = t.todo_detail
        if td.due_at:
            row["due_at"] = td.due_at.isoformat()
            due = format_dt_local(td.due_at, client_context)
            row["time_summary"] = f"截止 {due}" if due else ""
    return row


def search_tasks(
    *,
    user_id: str,
    q: str = "",
    task_type: Optional[str] = None,
    limit: int = 10,
    range_from: Optional[str] = None,
    range_to: Optional[str] = None,
    client_context: Optional[Dict[str, Any]] = None,
) -> dict:
    """
    查询任务。支持标题关键词、类型、时间区间 range_from/range_to（须成对）。
    指定时间区间时仅返回与该区间有交集的任务；无匹配则 items 为空，不返回其它日期任务。
    """
    qs = (
        Task.objects.filter(user_id=user_id)
        .select_related("block_detail", "ddl_detail", "todo_detail")
        .prefetch_related("tags", "subtasks")
    )

    rf_raw = (range_from or "").strip()
    rt_raw = (range_to or "").strip()
    range_applied = bool(rf_raw and rt_raw)

    if bool(rf_raw) != bool(rt_raw):
        return {
            "ok": False,
            "error": "range_from 与 range_to 须同时提供",
            "items": [],
            "count": 0,
            "range_applied": False,
        }

    if range_applied:
        rf = _parse_iso(rf_raw, client_context=client_context)
        rt = _parse_iso(rt_raw, client_context=client_context)
        if not rf or not rt or rt <= rf:
            return {
                "ok": False,
                "error": "invalid_time_range",
                "items": [],
                "count": 0,
                "range_applied": True,
            }
        qs = qs.filter(
            Q(
                type=Task.Type.BLOCK,
                block_detail__start_at__lt=rt,
                block_detail__end_at__gt=rf,
            )
            | Q(
                type=Task.Type.DDL,
                ddl_detail__due_at__gte=rf,
                ddl_detail__due_at__lt=rt,
            )
            | Q(
                type=Task.Type.TODO,
                todo_detail__due_at__gte=rf,
                todo_detail__due_at__lt=rt,
            )
        )
        qs = qs.order_by("block_detail__start_at", "ddl_detail__due_at", "todo_detail__due_at")
    else:
        qs = qs.order_by("-last_activity_at")

    if task_type in ("block", "ddl", "todo"):
        qs = qs.filter(type=task_type)
    if q.strip():
        qs = qs.filter(title__icontains=q.strip())

    items = list(qs[: max(1, min(limit, 50))])
    results = [_task_to_search_row(t, client_context=client_context) for t in items]

    payload: Dict[str, Any] = {
        "ok": True,
        "items": results,
        "count": len(results),
        "range_applied": range_applied,
    }
    if range_applied:
        payload["range_from"] = rf_raw
        payload["range_to"] = rt_raw
    return payload


def build_task_draft(
    *,
    task_type: str,
    title: str,
    description: str = "",
    start_at: Optional[str] = None,
    end_at: Optional[str] = None,
    due_at: Optional[str] = None,
    expected_minutes: Optional[int] = None,
    subtasks: Optional[list] = None,
    tag_ids: Optional[list] = None,
) -> dict:
    """构造单条任务草稿（不落库）。task_type 须为 block | ddl | todo。"""
    tt = (task_type or "").strip().lower()
    if tt not in ("block", "ddl", "todo"):
        return {"ok": False, "error": f"无效 task_type: {task_type!r}，须为 block、ddl 或 todo"}

    d: Dict[str, Any] = {
        "ok": True,
        "type": tt,
        "title": (title or "新任务")[:255],
        "description": description or "",
        "tag_ids": tag_ids if isinstance(tag_ids, list) else [],
    }
    if start_at:
        d["start_at"] = start_at
    if end_at:
        d["end_at"] = end_at
    if due_at:
        d["due_at"] = due_at
    if tt == "todo":
        if expected_minutes is not None:
            try:
                em = int(expected_minutes)
                if em > 0:
                    d["expected_minutes"] = em
            except (TypeError, ValueError):
                pass
        if isinstance(subtasks, list):
            cleaned = []
            for item in subtasks:
                if isinstance(item, dict) and (item.get("title") or "").strip():
                    cleaned.append({"title": str(item["title"]).strip()[:255]})
                elif isinstance(item, str) and item.strip():
                    cleaned.append({"title": item.strip()[:255]})
            if cleaned:
                d["subtasks"] = cleaned
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
    client_context: Optional[Dict[str, Any]] = None,
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
        "- due_at 在 start_date 到 end_date 之间均匀分布，须为 ISO8601 且带时区偏移（与用户本地一致）\n"
        "- 任务循序渐进，先基础后进阶\n"
        "- 子任务标题简洁具体，如'阅读第3章'、'完成练习题 1-10'\n"
        "- 所有 ISO8601 时间必须包含完整的日期、时间与时区偏移\n"
    )

    local = user_now_payload(client_context)
    user_msg = {
        "goal": goal,
        "start_date": start_date,
        "end_date": end_date,
        "daily_hours": daily_hours,
        "user_local_time": local,
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
        batch_result = create_tasks_batch(
            user_id=user_id, tasks=tasks, client_context=client_context
        )
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


def create_tasks_batch(
    *,
    user_id: str,
    tasks: list,
    client_context: Optional[Dict[str, Any]] = None,
) -> dict:
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
                    parsed_remind = _parse_iso(
                        str(remind_raw), client_context=client_context
                    )
                    if parsed_remind:
                        task.remind_at = parsed_remind
                task.save()

                t_type = task.type
                if t_type == Task.Type.BLOCK:
                    s = _parse_iso(
                        str(task_data.get("start_at") or ""),
                        client_context=client_context,
                    )
                    e = _parse_iso(
                        str(task_data.get("end_at") or ""),
                        client_context=client_context,
                    )
                    if s and e and e > s:
                        TaskBlock.objects.create(task=task, start_at=s, end_at=e)
                elif t_type == Task.Type.DDL:
                    d = _parse_iso(
                        str(task_data.get("due_at") or ""),
                        client_context=client_context,
                    )
                    if d:
                        TaskDDL.objects.create(task=task, due_at=d)
                elif t_type == Task.Type.TODO:
                    d = _parse_iso(
                        str(task_data.get("due_at") or ""),
                        client_context=client_context,
                    )
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

