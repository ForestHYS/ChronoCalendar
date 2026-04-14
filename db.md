## 后端数据库设计文档

### 1. 目标与假设

- **目标**：支撑三类任务（`block/ddl/todo`）+ 标签 + Todo 子任务 + 番茄钟专注统计 + 首页聚合 + 日历视图投影
- **任务提醒**：`remind_at` 仅存库供多端同步；**实际到点响铃/通知由 Android 客户端本地调度**，不设 `devices` / `notifications` 推送相关表
- **建议数据库**：PostgreSQL（下述字段/索引以 PG 语义描述；MySQL 可近似迁移）
- **多租户隔离**：按 `user_id` 隔离数据
- **时间存储**：统一使用 UTC（`timestamptz`），展示由客户端按时区转换

---

### 2. 核心表结构

#### 2.1 `users`

- `id` (PK, uuid)
- `email` (unique)
- `password_hash`
- `name`
- `created_at`, `updated_at`

#### 2.2 `tags`（用户自定义标签）

- `id` (PK, uuid)
- `user_id` (FK -> users.id, indexed)
- `name`
- `color`（如 `#RRGGBB`）
- `created_at`, `updated_at`
- **约束**：`(user_id, name)` unique（防止同用户重名）

#### 2.3 `tasks`（统一任务母表）

- `id` (PK, uuid)
- `user_id` (FK -> users.id, indexed)
- `type` (enum: block/ddl/todo, indexed)
- `title`
- `description` (nullable)
- `status` (enum: active/completed/cancelled, indexed)
- `created_at`, `updated_at`
- `completed_at` (nullable)
- `cancelled_at` (nullable)
- `last_activity_at` (indexed)
  - 用于“最近任务/最近 todo”排序（打开详情、开始专注、勾选子任务等交互更新）
- `snoozed_until` (nullable, indexed)
  - 对应“稍后完成”
- `remind_at` (nullable, indexed)
  - 用户设定的任务提醒时间；客户端据此注册/取消本地 `AlarmManager` 闹钟；`null` 表示不提醒

> “超时 overdue”可不落库：通过 `due_at < now AND status=active` 计算；如需加速统计，可额外加冗余字段并用定时任务维护。

#### 2.4 `task_block`（block 任务扩展表）

- `task_id` (PK, FK -> tasks.id)
- `start_at` (indexed)
- `end_at` (indexed)
- **约束**：`end_at > start_at`

#### 2.5 `task_ddl`（ddl 任务扩展表）

- `task_id` (PK, FK -> tasks.id)
- `due_at` (indexed)

#### 2.6 `task_todo`（todo 任务扩展表）

- `task_id` (PK, FK -> tasks.id)
- `expected_minutes` (nullable)
- `due_at` (nullable, indexed)

#### 2.7 `task_tags`（任务-标签 多对多）

- `task_id` (FK -> tasks.id)
- `tag_id` (FK -> tags.id)
- **PK**：`(task_id, tag_id)`
- **索引**：`(tag_id, task_id)`（按标签筛选任务）

#### 2.8 `subtasks`（todo 子任务）

- `id` (PK, uuid)
- `task_id` (FK -> tasks.id, indexed)
  - 仅允许关联 `type=todo` 的任务（由应用层校验，或用触发器/约束保证）
- `title`
- `done` (bool, indexed)
- `order` (int)
- `created_at`, `updated_at`
- `done_at` (nullable)

---

### 3. 番茄钟与专注统计

#### 3.1 `focus_sessions`

- `id` (PK, uuid)
- `user_id` (FK -> users.id, indexed)
- `task_id` (FK -> tasks.id, indexed)
- `status` (enum: running/stopped, indexed)
- `started_at` (indexed)
- `ended_at` (nullable, indexed)
- `planned_seconds` (int)
- `actual_seconds` (int, nullable)（停止时计算写入）
- `stop_reason` (enum: manual/app_killed/timeout, nullable)
- `noise_id` (nullable)（白噪音预设标识）

> “每天不同标签任务上的番茄钟专注时间”可由 `focus_sessions` join `task_tags` 聚合得到；若数据量较大可做增量汇总（见 4.2）。

---

### 4. 关键查询与索引建议

#### 4.1 首页“今天+明天任务按时间排序”

- block：按 `task_block.start_at` 范围查询
- ddl：按 `task_ddl.due_at` 范围查询
- 建议索引
  - `task_block(start_at)`、`task_block(end_at)`
  - `task_ddl(due_at)`
  - `tasks(user_id, status, type)`
  - `tasks(user_id, last_activity_at)`

#### 4.2 统计（周任务数 + 每日按标签专注柱状图）

- **直接聚合（中小规模）**：按 `focus_sessions.started_at` 的日期分桶，再 join 标签聚合
- **可选汇总表（大规模/高频）**
  - `focus_daily_tag_stats(user_id, date, tag_id, seconds)`
  - 由写入 `focus_sessions` stop 时增量更新，或由定时任务重算

#### 4.3 任务列表筛选/排序

- 标签筛选：走 `task_tags(tag_id, task_id)`
- ddl 按截止时间排序：走 `task_ddl(due_at)`
- todo 按“已花费时长”排序：
  - 方案 A：查询时聚合 `sum(focus_sessions.actual_seconds)`（实现简单，压力较大）
  - 方案 B：在 `tasks` 上维护冗余 `focus_total_seconds`（每次 session stop 增量更新，更快）

