"""
可注册 Skill：统一元数据、风险等级、是否需要人工审批，以及执行入口。
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional

from . import tools


def skills_prompt_lines() -> List[str]:
    lines = []
    for s in iter_skills():
        ap = "需要人工批准后执行" if s.requires_approval else "可直接执行"
        lines.append(f"- {s.name}: {s.description}（风险={s.risk}，{ap}）")
        if s.args_hint:
            lines.append(f"  参数: {s.args_hint}")
    return lines


def skills_prompt_for(names: List[str]) -> str:
    """仅输出指定 Skill 的说明（用于拆分后的专项 prompt）。"""
    allowed = set(names)
    lines = []
    for s in iter_skills():
        if s.name not in allowed:
            continue
        ap = "需要人工批准后执行" if s.requires_approval else "可直接执行"
        lines.append(f"- {s.name}: {s.description}（风险={s.risk}，{ap}）")
        if s.args_hint:
            lines.append(f"  参数: {s.args_hint}")
    return "\n".join(lines)


@dataclass(frozen=True)
class Skill:
    name: str
    description: str
    risk: str  # low | medium | high
    requires_approval: bool
    args_hint: str
    handler: Callable[..., dict]


def _run_search_tasks(user_id: str, **kw: Any) -> dict:
    ctx = kw.pop("client_context", None)
    return tools.search_tasks(user_id=user_id, client_context=ctx, **kw)


def _run_build_draft(user_id: str, **kw: Any) -> dict:
    _ = user_id
    return tools.build_task_draft(**kw)


def _run_check_conflict(user_id: str, **kw: Any) -> dict:
    return tools.check_block_conflict(user_id=user_id, **kw)


def _run_delete_task(user_id: str, **kw: Any) -> dict:
    return tools.execute_delete_task(user_id=user_id, **kw)


def _run_generate_plan(user_id: str, **kw: Any) -> dict:
    ctx = kw.pop("client_context", None)
    return tools.generate_long_term_plan(user_id=user_id, client_context=ctx, **kw)


def _validate_search_tasks(args: dict) -> dict:
    rf = str(args.get("range_from") or "").strip()
    rt = str(args.get("range_to") or "").strip()
    if bool(rf) != bool(rt):
        raise ValueError("range_from 与 range_to 须同时提供或同时省略")
    try:
        limit = int(args.get("limit") or 20)
    except (TypeError, ValueError):
        limit = 20
    limit = max(1, min(limit, 50))
    return {
        "q": str(args.get("q") or ""),
        "task_type": args.get("task_type"),
        "limit": limit,
        "range_from": rf or None,
        "range_to": rt or None,
    }


def _validate_build_draft(args: dict) -> dict:
    tt = str(args.get("task_type") or "").strip().lower()
    if tt not in ("block", "ddl", "todo"):
        raise ValueError("task_type 必填，且须为 block、ddl 或 todo 之一")
    em = args.get("expected_minutes")
    try:
        em_val = int(em) if em is not None else None
    except (TypeError, ValueError):
        em_val = None
    subs = args.get("subtasks")
    return {
        "task_type": tt,
        "title": str(args.get("title") or "新任务"),
        "description": str(args.get("description") or ""),
        "start_at": args.get("start_at"),
        "end_at": args.get("end_at"),
        "due_at": args.get("due_at"),
        "expected_minutes": em_val,
        "subtasks": subs if isinstance(subs, list) else None,
        "tag_ids": args.get("tag_ids") if isinstance(args.get("tag_ids"), list) else [],
    }


def _validate_conflict(args: dict) -> dict:
    return {
        "start_at": str(args.get("start_at") or ""),
        "end_at": str(args.get("end_at") or ""),
    }


def _validate_delete_task(args: dict) -> dict:
    tid = args.get("task_id")
    if not tid:
        raise ValueError("task_id 必填")
    return {"task_id": str(tid)}


def _validate_generate_plan(args: dict) -> dict:
    goal = str(args.get("goal") or "").strip()
    if not goal:
        raise ValueError("goal 必填")
    start_date = str(args.get("start_date") or "").strip()
    end_date = str(args.get("end_date") or "").strip()
    if not start_date or not end_date:
        raise ValueError("start_date 和 end_date 必填")
    try:
        daily_hours = float(args.get("daily_hours") or 2.0)
    except (TypeError, ValueError):
        daily_hours = 2.0
    daily_hours = max(0.5, min(daily_hours, 8.0))
    create_immediately = bool(args.get("create_immediately", False))
    return {
        "goal": goal,
        "start_date": start_date,
        "end_date": end_date,
        "daily_hours": daily_hours,
        "create_immediately": create_immediately,
    }


SKILLS: Dict[str, Skill] = {
    "search_tasks": Skill(
        name="search_tasks",
        description=(
            "查询/搜索/列出用户任务。支持标题 q、类型 task_type、时间区间 range_from+range_to（ISO8601，须成对）。"
            "用户问「明天/今天/某天有什么任务」必须传 range_from/range_to（可用 user_payload 里 calendar_hints）；"
            "无匹配时 items 为空，勿改用无 range 查询凑数。结果含 id，前端展示「查看详情」。"
        ),
        risk="low",
        requires_approval=False,
        args_hint=(
            '{"q":"标题关键词，可空","task_type":"block|ddl|todo|null",'
            '"range_from":"区间起点ISO","range_to":"区间终点ISO","limit":20}'
        ),
        handler=_run_search_tasks,
    ),
    "build_task_draft": Skill(
        name="build_task_draft",
        description=(
            "创建单个任务草稿（不落库），type 必为 block|ddl|todo 之一，按任务语义选型（见系统说明）。"
            "block 需 start_at+end_at；ddl 需 due_at；todo 可 due_at、expected_minutes、subtasks。"
            "完成后应 open_editor 展示草稿，勿默认一律 block。"
        ),
        risk="low",
        requires_approval=False,
        args_hint=(
            '{"task_type":"block|ddl|todo","title","description",'
            '"start_at","end_at","due_at","expected_minutes","subtasks":[{"title":"..."}],"tag_ids"}'
        ),
        handler=_run_build_draft,
    ),
    "check_block_conflict": Skill(
        name="check_block_conflict",
        description="检查给定时间段是否与现有 block 任务冲突，并给出顺延建议",
        risk="low",
        requires_approval=False,
        args_hint='{"start_at":"ISO","end_at":"ISO"}',
        handler=_run_check_conflict,
    ),
    "delete_task": Skill(
        name="delete_task",
        description="删除指定任务（永久删除）。必须先由用户在前端批准，后端才会真正执行删除。",
        risk="high",
        requires_approval=True,
        args_hint='{"task_id":"uuid"}',
        handler=_run_delete_task,
    ),
    "generate_long_term_plan": Skill(
        name="generate_long_term_plan",
        description=(
            "根据用户的长期目标（如学习计划、项目安排）和时间范围，自动生成一组待办任务（todo 类型），"
            "每个待办任务下包含具体可操作的子任务（subtasks），形成阶段化的长期规划。"
            "若用户明确要求'直接添加/创建/加入日程'，则传 create_immediately=true，任务直接落库；"
            "否则传 create_immediately=false，返回预览供用户确认。"
        ),
        risk="low",
        requires_approval=False,
        args_hint='{"goal":"目标描述","start_date":"开始日期ISO","end_date":"结束日期ISO","daily_hours":2.0,"create_immediately":false}',
        handler=_run_generate_plan,
    ),
}


def get_skill(name: str) -> Optional[Skill]:
    return SKILLS.get(name)


def iter_skills() -> List[Skill]:
    return list(SKILLS.values())


def normalize_args(skill_name: str, raw: dict) -> dict:
    if skill_name == "search_tasks":
        return _validate_search_tasks(raw)
    if skill_name == "build_task_draft":
        return _validate_build_draft(raw)
    if skill_name == "check_block_conflict":
        return _validate_conflict(raw)
    if skill_name == "delete_task":
        return _validate_delete_task(raw)
    if skill_name == "generate_long_term_plan":
        return _validate_generate_plan(raw)
    raise ValueError(f"unknown skill: {skill_name}")


def run_skill(skill_name: str, user_id: str, raw_args: dict) -> dict:
    skill = get_skill(skill_name)
    if not skill:
        return {"ok": False, "error": "unknown_tool"}
    try:
        args = normalize_args(skill_name, raw_args)
    except ValueError as e:
        return {"ok": False, "error": str(e)}
    ctx = raw_args.get("client_context") if isinstance(raw_args.get("client_context"), dict) else None
    try:
        if skill_name in ("generate_long_term_plan", "search_tasks") and ctx is not None:
            return skill.handler(user_id, **args, client_context=ctx)
        return skill.handler(user_id, **args)
    except Exception as e:
        return {"ok": False, "error": str(e)}
