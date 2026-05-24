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


@dataclass(frozen=True)
class Skill:
    name: str
    description: str
    risk: str  # low | medium | high
    requires_approval: bool
    args_hint: str
    handler: Callable[..., dict]


def _run_search_tasks(user_id: str, **kw: Any) -> dict:
    return tools.search_tasks(user_id=user_id, **kw)


def _run_build_draft(user_id: str, **kw: Any) -> dict:
    _ = user_id
    return tools.build_task_draft(**kw)


def _run_check_conflict(user_id: str, **kw: Any) -> dict:
    return tools.check_block_conflict(user_id=user_id, **kw)


def _run_delete_task(user_id: str, **kw: Any) -> dict:
    return tools.execute_delete_task(user_id=user_id, **kw)


def _run_generate_plan(user_id: str, **kw: Any) -> dict:
    return tools.generate_long_term_plan(user_id=user_id, **kw)


def _validate_search_tasks(args: dict) -> dict:
    return {
        "q": str(args.get("q") or ""),
        "task_type": args.get("task_type"),
        "limit": int(args.get("limit") or 10),
    }


def _validate_build_draft(args: dict) -> dict:
    return {
        "task_type": str(args.get("task_type") or "block"),
        "title": str(args.get("title") or "新任务"),
        "description": str(args.get("description") or ""),
        "start_at": args.get("start_at"),
        "end_at": args.get("end_at"),
        "due_at": args.get("due_at"),
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
        description="按标题关键词与类型搜索当前用户的任务列表",
        risk="low",
        requires_approval=False,
        args_hint='{"q":"关键词","task_type":"block|ddl|todo|null","limit":10}',
        handler=_run_search_tasks,
    ),
    "build_task_draft": Skill(
        name="build_task_draft",
        description="生成单个任务草稿（不落库），用于打开编辑页让用户确认保存",
        risk="low",
        requires_approval=False,
        args_hint='{"task_type","title","description","start_at","end_at","due_at","tag_ids"}',
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
    try:
        return skill.handler(user_id, **args)
    except Exception as e:
        return {"ok": False, "error": str(e)}
