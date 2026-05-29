"""三类任务职责说明与 few-shot，供 Agent prompt 使用。"""

TASK_TYPES_GUIDE = """
## 三类任务职责（必须按语义选对 type）

| type | 含义 | 必填时间字段 | 典型场景 |
|------|------|--------------|----------|
| block | 固定占用时段的日程块 | start_at + end_at（ISO8601，用户本地理解后转 UTC） | 上课、会议、健身课、医生预约 |
| ddl | 只需在截止前完成 | due_at | 交作业、报名截止、合同ddl、报告提交日 |
| todo | 可拆子任务、可记预计总时长 | due_at 可选；可传 expected_minutes、subtasks | 学习计划、复习周、项目阶段、家务清单 |

## 选型 few-shot（创建单条任务时参考）

- 「明天下午三点到五点高数课」→ block，start_at/end_at
- 「周五前提交实验报告」→ ddl，due_at
- 「这周学完第三章并做习题」→ todo，due_at + expected_minutes，subtasks 可拆步骤
- 「每天晨跑 30 分钟」若用户给具体时段 → block；若只说习惯目标 → todo
- 用户说「会议/课程/约会/训练课」→ 优先 block
- 用户说「截止/之前交/deadline」→ 优先 ddl
- 用户说「计划/安排学习/多步完成/预计多久」→ 优先 todo
- 不要默认一律用 block；长期多阶段规划应走 plan_gather_requirements 两阶段流程

## task_draft / build_task_draft 字段

- 公共：type, title, description, tag_ids
- block：start_at, end_at
- ddl：due_at
- todo：due_at（可选）, expected_minutes（整数分钟）, subtasks: [{"title":"..."}, ...]
"""
