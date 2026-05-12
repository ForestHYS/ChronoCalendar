from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional

from tasks.models import Task


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

