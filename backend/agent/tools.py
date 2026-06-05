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


def resolve_delete_task_target(
    *,
    user_id: str,
    task_id: Optional[str] = None,
    q: Optional[str] = None,
    client_context: Optional[Dict[str, Any]] = None,
) -> dict:
    """
    根据 task_id 或标题关键词 q（仅 title 模糊匹配）定位待删除任务。
    返回结构化结果，不含面向用户的文案（由 Compose 阶段 LLM 生成）。
    """
    tid = (task_id or "").strip()
    keyword = (q or "").strip()

    if tid:
        summ = task_summary_for_approval(user_id=user_id, task_id=tid)
        if summ.get("ok"):
            return {
                "ok": True,
                "task_id": tid,
                "task": summ["task"],
                "resolved_by": "task_id",
            }

    if not keyword:
        if tid:
            return {"ok": False, "error": "not_found", "task_id": tid}
        return {"ok": False, "error": "missing_target"}

    sr = search_tasks(
        user_id=user_id,
        q=keyword,
        limit=10,
        client_context=client_context,
    )
    items = sr.get("items") if isinstance(sr.get("items"), list) else []
    if not items:
        return {"ok": False, "error": "not_found", "q": keyword, "match_by": "title"}
    if len(items) == 1:
        only_id = str(items[0].get("id") or "")
        summ = task_summary_for_approval(user_id=user_id, task_id=only_id)
        if summ.get("ok"):
            return {
                "ok": True,
                "task_id": only_id,
                "task": summ["task"],
                "resolved_by": "q",
                "q": keyword,
            }
        return {"ok": False, "error": "resolve_failed", "q": keyword}

    return {
        "ok": False,
        "error": "ambiguous",
        "items": items,
        "q": keyword,
        "count": len(items),
        "match_by": "title",
    }


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
# 长期规划工具（Planning → Scheduling 两阶段）
# ---------------------------------------------------------------------------

def _plan_local_context(client_context: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    return user_now_payload(client_context)


def plan_gather_requirements(
    *,
    goal: str,
    client_context: Optional[Dict[str, Any]] = None,
    user_id: Optional[str] = None,
) -> dict:
    """
    Planning 阶段 1：根据用户目标生成细化需求的选择题。
    """
    from .llm import LLM_NOT_CONFIGURED_MESSAGE, call_llm_json, is_llm_configured, is_missing_api_key_error

    goal = (goal or "").strip()
    if not goal:
        return {"ok": False, "error": "请说明你的长期目标或计划内容。"}
    if not is_llm_configured(user_id):
        return {"ok": False, "error": LLM_NOT_CONFIGURED_MESSAGE, "code": "llm_not_configured"}

    system = (
        "你是专业的日程规划助手。用户提出长期目标，你需要生成 2～4 道选择题以细化需求。\n"
        "只输出严格 JSON：\n"
        '{"questions":[{"id":"唯一id","text":"题目","multi":false,'
        '"options":[{"id":"选项id","label":"展示文案"}]}]}\n\n'
        "建议覆盖：计划周期、每日可投入时间、侧重点/优先级、任务组织偏好。\n"
        "每题 3～5 个选项，选项 id 用简短英文或数字，label 用中文。\n"
        "multi=true 表示可多选，默认 false。\n"
    )
    user_msg = {
        "goal": goal,
        "user_local_time": _plan_local_context(client_context),
    }
    result = call_llm_json(system=system, user=str(user_msg), user_id=user_id)
    if not result.ok or not result.data:
        if is_missing_api_key_error(result.error):
            return {"ok": False, "error": LLM_NOT_CONFIGURED_MESSAGE, "code": "llm_not_configured"}
        return {"ok": False, "error": "无法生成规划问题，请稍后重试。"}

    questions = result.data.get("questions")
    if not isinstance(questions, list) or not questions:
        return {"ok": False, "error": "规划问题生成格式异常。"}

    cleaned: List[Dict[str, Any]] = []
    for q in questions[:5]:
        if not isinstance(q, dict):
            continue
        qid = str(q.get("id") or "").strip()
        text = str(q.get("text") or "").strip()
        if not qid or not text:
            continue
        opts_in = q.get("options")
        if not isinstance(opts_in, list):
            continue
        options = []
        for o in opts_in[:6]:
            if not isinstance(o, dict):
                continue
            oid = str(o.get("id") or "").strip()
            label = str(o.get("label") or "").strip()
            if oid and label:
                options.append({"id": oid, "label": label})
        if len(options) < 2:
            continue
        cleaned.append(
            {
                "id": qid,
                "text": text,
                "multi": bool(q.get("multi", False)),
                "options": options,
            }
        )

    if not cleaned:
        return {"ok": False, "error": "规划问题生成格式异常。"}

    return {
        "ok": True,
        "goal": goal,
        "questions": cleaned,
    }


def plan_generate_outline(
    *,
    goal: str,
    answers: Dict[str, Any],
    client_context: Optional[Dict[str, Any]] = None,
    refinement: Optional[str] = None,
    previous_outline: Optional[Dict[str, Any]] = None,
    user_id: Optional[str] = None,
) -> dict:
    """
    Planning 阶段 2：根据目标与用户选择题答案，生成文字方案/阶段列举。
    refinement 非空时在原方案基础上按用户文字修改，勿要求重做选择题。
    """
    from .llm import LLM_NOT_CONFIGURED_MESSAGE, call_llm_json, is_llm_configured, is_missing_api_key_error

    goal = (goal or "").strip()
    if not goal:
        return {"ok": False, "error": "缺少规划目标。"}
    if not isinstance(answers, dict):
        return {"ok": False, "error": "缺少选择题答案。"}
    if not refinement and not answers:
        return {"ok": False, "error": "缺少选择题答案。"}
    if not is_llm_configured(user_id):
        return {"ok": False, "error": LLM_NOT_CONFIGURED_MESSAGE, "code": "llm_not_configured"}

    system = (
        "你是专业的日程规划助手。根据用户目标与选择题答案，输出阶段性文字方案（不落具体日程）。\n"
        "只输出严格 JSON：\n"
        '{"plan_title":"计划名称","outline_text":"2～6段中文方案概述，可用换行分段",'
        '"phases":[{"title":"阶段名","description":"该阶段要做什么","duration_hint":"如第1周"}],'
        '"start_date":"YYYY-MM-DD","end_date":"YYYY-MM-DD","daily_hours":2.0,'
        '"planned_schedule_summary":{"todo_count":1,"block_count":2,"ddl_count":0,'
        '"summary":"一句说明预计会生成几个 todo/block（如：1个待办含多子任务+专门的讲座/活动时间段）"}}\n\n'
        "规则：\n"
        "- phases 3～6 项，循序渐进；阶段细节留给后续 subtasks，勿过碎\n"
        "- planned_schedule_summary 必填：预估排程阶段将生成的 todo_count、block_count、ddl_count\n"
        "- start_date/end_date 根据答案中的周期推算，基于 user_local_time 的日期\n"
        "- daily_hours 根据答案估算，0.5～8\n"
        "- outline_text 清晰可读；在文末或 summary 中点明预计 todo/block 数量\n"
        "- 注意，应用的block不包含可重复选项，因此每个block仅代表单次任务"
    )
    if refinement:
        system += (
            "\n用户要求修改已有文字方案。在保留原 answers 约束下按 refinement 调整，"
            "勿要求用户重做选择题。参考 previous_outline。\n"
        )
    user_msg: Dict[str, Any] = {
        "goal": goal,
        "answers": answers,
        "user_local_time": _plan_local_context(client_context),
    }
    if refinement:
        user_msg["refinement"] = refinement.strip()
    if previous_outline:
        user_msg["previous_outline"] = previous_outline
    result = call_llm_json(system=system, user=str(user_msg), user_id=user_id)
    if not result.ok or not result.data:
        if is_missing_api_key_error(result.error):
            return {"ok": False, "error": LLM_NOT_CONFIGURED_MESSAGE, "code": "llm_not_configured"}
        return {"ok": False, "error": "方案生成失败，请稍后重试。"}

    data = result.data
    phases = data.get("phases")
    if not isinstance(phases, list) or not phases:
        return {"ok": False, "error": "方案格式异常，缺少阶段列表。"}

    outline_text = str(data.get("outline_text") or "").strip()
    if not outline_text:
        return {"ok": False, "error": "方案格式异常，缺少文字说明。"}

    try:
        daily_hours = float(data.get("daily_hours") or 2.0)
    except (TypeError, ValueError):
        daily_hours = 2.0
    daily_hours = max(0.5, min(daily_hours, 8.0))

    cleaned_phases: List[Dict[str, str]] = []
    for p in phases[:12]:
        if not isinstance(p, dict):
            continue
        title = str(p.get("title") or "").strip()
        desc = str(p.get("description") or "").strip()
        if title:
            cleaned_phases.append(
                {
                    "title": title,
                    "description": desc,
                    "duration_hint": str(p.get("duration_hint") or "").strip(),
                }
            )

    if not cleaned_phases:
        return {"ok": False, "error": "方案格式异常。"}

    raw_summary = data.get("planned_schedule_summary")
    planned_summary: Dict[str, Any] = {}
    if isinstance(raw_summary, dict):
        try:
            planned_summary = {
                "todo_count": max(0, int(raw_summary.get("todo_count") or 0)),
                "block_count": max(0, int(raw_summary.get("block_count") or 0)),
                "ddl_count": max(0, int(raw_summary.get("ddl_count") or 0)),
                "summary": str(raw_summary.get("summary") or "").strip(),
            }
        except (TypeError, ValueError):
            planned_summary = {}

    return {
        "ok": True,
        "plan_title": str(data.get("plan_title") or goal).strip() or goal,
        "outline_text": outline_text,
        "phases": cleaned_phases,
        "start_date": str(data.get("start_date") or "").strip(),
        "end_date": str(data.get("end_date") or "").strip(),
        "daily_hours": daily_hours,
        "goal": goal,
        "answers": answers,
        "planned_schedule_summary": planned_summary,
    }


def plan_schedule_tasks(
    *,
    goal: str,
    plan_title: str,
    outline_text: str,
    phases: List[Dict[str, Any]],
    start_date: str,
    end_date: str,
    daily_hours: float = 2.0,
    client_context: Optional[Dict[str, Any]] = None,
    refinement: Optional[str] = None,
    previous_tasks: Optional[List[Dict[str, Any]]] = None,
    user_id: Optional[str] = None,
) -> dict:
    """
    Scheduling 阶段：根据已确认方案生成可落库的任务列表。
    任务宜少；todo 可含 due_at 与 subtasks，勿与 ddl 重复表达截止。
    """
    from .llm import LLM_NOT_CONFIGURED_MESSAGE, call_llm_json, is_llm_configured, is_missing_api_key_error

    if not (goal or "").strip():
        return {"ok": False, "error": "缺少规划目标。"}
    if not isinstance(phases, list) or not phases:
        return {"ok": False, "error": "缺少方案阶段。"}
    if not is_llm_configured(user_id):
        return {"ok": False, "error": LLM_NOT_CONFIGURED_MESSAGE, "code": "llm_not_configured"}

    system = (
        "你是日程排程助手。根据已确认的长期方案，生成精简、可创建的任务列表。\n"
        "输出严格 JSON：\n"
        '{"plan_title":"...", "tasks":[...]}\n\n'
        "tasks 每项 type 必为 block|ddl|todo 之一：\n"
        "- block：固定学习/工作时段，需 start_at+end_at（ISO8601 带时区）\n"
        "- ddl：单一硬性截止里程碑，需 due_at\n"
        "- todo：主题待办，可 due_at（截止）、expected_minutes、subtasks\n\n"
        "排程原则：\n"
        "- 任务总数不宜过多：整个计划通常 3～8 条 tasks，严禁拆成十几条或更多\n"
        "- 任务标题应该简洁明了，不要过长（详细说明写入任务描述），不要依赖上下文才能理解。例如：标题可以是 “机器学习第一章” 而不是 “第一章：支持向量机以及.....” \n"
        "- 默认优先少数 todo：用 1 条 todo（带 due_at + 5～12 个 subtasks）覆盖多阶段步骤，子任务对应方案阶段，勿为每个阶段各建一条 task；多个todo对应不同的方面，如用户要求一周规划时，可用多个todo对应不同学科或项目。\n"
        "- 三种类型可以混合，但不必强行混合\n"
        "- 若已用 todo 表达阶段与截止，不要再建 ddl（todo 的 due_at 即截止，二者勿重复）\n"
        "- 时间分布在 start_date～end_date，ISO8601 须含时区偏移（与用户本地一致）\n"
        "- 子任务标题具体可执行；每天总量不超过 daily_hours 小时\n"
    )
    if refinement:
        system += (
            "\n用户要求修改已有日程列表。在保留方案大框架下按 refinement 调整 previous_tasks，"
            "输出完整新 tasks 列表。\n"
        )
    user_msg: Dict[str, Any] = {
        "goal": goal,
        "plan_title": plan_title,
        "outline_text": outline_text,
        "phases": phases,
        "start_date": start_date,
        "end_date": end_date,
        "daily_hours": daily_hours,
        "user_local_time": _plan_local_context(client_context),
    }
    if refinement:
        user_msg["refinement"] = refinement.strip()
    if previous_tasks:
        user_msg["previous_tasks"] = previous_tasks
    result = call_llm_json(system=system, user=str(user_msg), user_id=user_id)
    if not result.ok or not result.data:
        if is_missing_api_key_error(result.error):
            return {"ok": False, "error": LLM_NOT_CONFIGURED_MESSAGE, "code": "llm_not_configured"}
        return {"ok": False, "error": "日程生成失败，请稍后重试。"}

    tasks = result.data.get("tasks")
    if not isinstance(tasks, list):
        return {"ok": False, "error": "日程格式异常，tasks 缺失。"}

    cleaned: List[Dict[str, Any]] = []
    for t in tasks[:10]:
        if not isinstance(t, dict):
            continue
        tt = str(t.get("type") or "").strip().lower()
        if tt not in ("block", "ddl", "todo"):
            continue
        title = str(t.get("title") or "").strip()
        if not title:
            continue
        item: Dict[str, Any] = {
            "type": tt,
            "title": title[:255],
            "description": str(t.get("description") or ""),
        }
        if tt == "block":
            if t.get("start_at") and t.get("end_at"):
                item["start_at"] = t["start_at"]
                item["end_at"] = t["end_at"]
                cleaned.append(item)
        elif tt == "ddl":
            if t.get("due_at"):
                item["due_at"] = t["due_at"]
                cleaned.append(item)
        elif tt == "todo":
            if t.get("due_at"):
                item["due_at"] = t["due_at"]
            em = t.get("expected_minutes")
            if em is not None:
                try:
                    item["expected_minutes"] = int(em)
                except (TypeError, ValueError):
                    pass
            subs = t.get("subtasks")
            if isinstance(subs, list):
                item["subtasks"] = [
                    {"title": str(s.get("title") or "")[:255]}
                    for s in subs
                    if isinstance(s, dict) and s.get("title")
                ]
            cleaned.append(item)

    if not cleaned:
        return {"ok": False, "error": "未能生成有效任务，请调整方案后重试。"}

    has_todo_with_due = any(
        x.get("type") == "todo" and x.get("due_at") for x in cleaned
    )
    if has_todo_with_due:
        cleaned = [x for x in cleaned if x.get("type") != "ddl"]

    if not cleaned:
        return {"ok": False, "error": "未能生成有效任务，请调整方案后重试。"}

    return {
        "ok": True,
        "plan_title": str(result.data.get("plan_title") or plan_title).strip() or plan_title,
        "tasks": cleaned,
        "total": len(cleaned),
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

