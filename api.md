## API 文档

### 1. 概述与约定

- **Base URL**：`/api/v1`
- **认证**：Bearer Token（`Authorization: Bearer <token>`）
- **时间**：统一使用 ISO 8601（UTC）存储与传输；客户端展示可按本地时区转换
- **通用响应结构**
  - 成功：`{ "data": ... }`
  - 失败：`{ "error": { "code": "STRING", "message": "STRING", "details": {...?} } }`
- **任务类型**
  - `block`：固定占用时间（有 `start_at/end_at`）
  - `ddl`：仅截止时间（有 `due_at`）
  - `todo`：可含子任务或预期投入时长（`expected_minutes?`，可选 `due_at?`）
- **任务提醒**：由 **Android 客户端本地调度**（如 `AlarmManager` + 系统通知；App 在前台时可展示半屏弹窗）。服务端仅持久化提醒时间等字段，**不提供推送、不注册设备 Token**；用户未打开 App 时的响铃依赖本地已注册的闹钟。

> 若仅本地存储、不同步云端，可省略 Auth 与下列 REST 接口，提醒字段仅存 Room/SQLite。

---

### 2. Auth（最小账号体系）

#### 2.1 登录

- **POST** `/auth/login`
- **Body**

```json
{ "email": "a@b.com", "password": "xxx" }
```

- **Resp**

```json
{
  "data": {
    "access_token": "...",
    "refresh_token": "...",
    "user": { "id": "...", "name": "..." }
  }
}
```

#### 2.2 刷新 Token

- **POST** `/auth/refresh`
- **Body**

```json
{ "refresh_token": "..." }
```

#### 2.3 退出登录

- **POST** `/auth/logout`

---

### 3. 标签（用户自定义）

#### 3.1 创建标签

- **POST** `/tags`
- **Body**

```json
{ "name": "学习", "color": "#4F46E5" }
```

#### 3.2 获取标签列表

- **GET** `/tags`

#### 3.3 更新标签

- **PATCH** `/tags/{tagId}`
- **Body**

```json
{ "name": "娱乐", "color": "#22C55E" }
```

#### 3.4 删除标签

- **DELETE** `/tags/{tagId}`

---

### 4. 任务（block / ddl / todo）

#### 4.0 任务数据模型

> 三类任务共享一个 `/tasks` 集合，以 `type` 字段区分。

---

##### 4.0.1 通用字段（三类任务均有）

| 字段 | 类型 | 读写 | 说明 |
|---|---|---|---|
| `id` | `string` | 只读 | 任务唯一标识（UUID） |
| `type` | `"block" \| "ddl" \| "todo"` | 创建时必填，不可修改 | 任务类型 |
| `title` | `string` | 必填 | 任务标题 |
| `description` | `string?` | 可选 | 备注说明，默认空字符串 |
| `tag_ids` | `string[]` | 可选 | 关联标签 ID 列表，默认 `[]` |
| `status` | `"active" \| "completed" \| "cancelled" \| "overdue"` | 只读 | 任务状态；`overdue` 由服务端在截止时间过期后自动标记（block/ddl 按 `end_at`/`due_at`；todo 按 `due_at`，无 `due_at` 则永不 overdue） |
| `remind_at` | `datetime?` | 可选 | 提醒时间（ISO 8601 UTC）；`null` 表示不提醒；服务端仅持久化，提醒由客户端本地调度 |
| `focus_total_seconds` | `number` | 只读 | 关联番茄钟会话的累计专注秒数 |
| `created_at` | `datetime` | 只读 | 创建时间（UTC） |
| `updated_at` | `datetime` | 只读 | 最近更新时间（UTC） |

---

##### 4.0.2 Block —— 固定时间段任务

> 适用场景：上课、会议、健身等有明确起止时间的占用块。

在通用字段基础上，额外包含：

| 字段 | 类型 | 读写 | 说明 |
|---|---|---|---|
| `start_at` | `datetime` | 必填 | 任务开始时间（UTC） |
| `end_at` | `datetime` | 必填 | 任务结束时间（UTC）；须严格晚于 `start_at` |

**约束**
- `end_at > start_at`，否则返回 `400 INVALID_TIME_RANGE`
- `status` 初始为 `active`；可手动 `complete` / `cancel`；到达 `end_at` 后若未完成，服务端将其标记为 `overdue`

**完整示例（响应）**
```json
{
  "id": "blk_001",
  "type": "block",
  "title": "高数课",
  "description": "第五章极限",
  "tag_ids": ["tag_study"],
  "status": "active",
  "start_at": "2026-04-22T08:00:00Z",
  "end_at": "2026-04-22T09:40:00Z",
  "remind_at": "2026-04-22T07:50:00Z",
  "focus_total_seconds": 0,
  "created_at": "2026-04-21T12:00:00Z",
  "updated_at": "2026-04-21T12:00:00Z"
}
```

---

##### 4.0.3 DDL —— 截止时间任务

> 适用场景：作业提交、项目汇报等仅有最终期限的任务。

在通用字段基础上，额外包含：

| 字段 | 类型 | 读写 | 说明 |
|---|---|---|---|
| `due_at` | `datetime` | 必填 | 截止时间（UTC）；超时后 `status` 自动变为 `overdue` |

**约束**
- 无 `start_at`；日历视图中该类任务以「截止点」形式呈现（`all_day` 或具体时刻，由客户端决定展示方式）
- `postpone` 操作仅更新 `due_at`，同时重置 `status` 为 `active`

**完整示例（响应）**
```json
{
  "id": "ddl_001",
  "type": "ddl",
  "title": "提交数据库作业",
  "description": "",
  "tag_ids": ["tag_study"],
  "status": "active",
  "due_at": "2026-04-25T16:00:00Z",
  "remind_at": "2026-04-25T14:00:00Z",
  "focus_total_seconds": 3600,
  "created_at": "2026-04-20T09:00:00Z",
  "updated_at": "2026-04-20T09:00:00Z"
}
```

---

##### 4.0.4 Todo —— 待办任务

> 适用场景：自由安排的学习、生活待办，可拆解为子任务或设定预期时长。

在通用字段基础上，额外包含：

| 字段 | 类型 | 读写 | 说明 |
|---|---|---|---|
| `due_at` | `datetime?` | 可选 | 可选截止时间；有值时超时后标记为 `overdue` |
| `expected_minutes` | `number?` | 可选 | 预期投入时长（分钟，正整数）；与子任务可共存 |
| `subtasks` | `SubTask[]` | 可选 | 子任务列表，默认 `[]`；创建时可一并提交，后续通过子任务接口（§5）增删改 |

**SubTask 子任务结构**

| 字段 | 类型 | 读写 | 说明 |
|---|---|---|---|
| `id` | `string` | 只读 | 子任务唯一标识（UUID） |
| `title` | `string` | 必填 | 子任务标题 |
| `done` | `boolean` | 可读写 | 是否完成，默认 `false` |
| `order` | `number` | 可读写 | 排序序号（升序展示），从 1 开始 |

**约束**
- 无子任务且 `done` 逻辑不适用时，通过 `POST /tasks/{taskId}/complete` 手动完成
- 当所有子任务均 `done: true` 时，客户端可显示「标记完成」按钮（见主页设计）
- `expected_minutes` 与 `focus_total_seconds` 可共同用于进度展示（已专注 / 预期时长）

**完整示例（响应）**
```json
{
  "id": "todo_001",
  "type": "todo",
  "title": "复习线性代数",
  "description": "期末复习",
  "tag_ids": ["tag_study"],
  "status": "active",
  "due_at": "2026-04-28T00:00:00Z",
  "remind_at": "2026-04-27T20:00:00Z",
  "expected_minutes": 120,
  "subtasks": [
    { "id": "sub_001", "title": "第一章例题", "done": true,  "order": 1 },
    { "id": "sub_002", "title": "第二章习题", "done": false, "order": 2 },
    { "id": "sub_003", "title": "真题模拟",   "done": false, "order": 3 }
  ],
  "focus_total_seconds": 5400,
  "created_at": "2026-04-20T10:00:00Z",
  "updated_at": "2026-04-21T18:30:00Z"
}
```

---

##### 4.0.5 状态流转图

```
          ┌─────────────────────────────────────────┐
          │                 active                  │
          └────┬───────────┬───────────┬────────────┘
               │           │           │
      完成时间到达      手动 cancel   手动/弹窗 complete
      (block end_at /      │           │
       ddl|todo due_at)    ▼           ▼
               │       cancelled   completed
               ▼
            overdue
               │
        postpone / snooze
               │
               ▼
            active（due_at 更新）
```

---

#### 4.1 创建任务

- **POST** `/tasks`

- **Body（按类型）**

block：

```json
{
  "type": "block",
  "title": "上课",
  "description": "",
  "tag_ids": ["..."],
  "start_at": "2026-04-07T09:00:00Z",
  "end_at": "2026-04-07T10:30:00Z",
  "remind_at": "2026-04-07T08:45:00Z"
}
```

ddl：

```json
{
  "type": "ddl",
  "title": "交作业",
  "tag_ids": ["..."],
  "due_at": "2026-04-08T16:00:00Z",
  "remind_at": "2026-04-08T15:00:00Z"
}
```

todo：

```json
{
  "type": "todo",
  "title": "复习线代",
  "tag_ids": ["..."],
  "expected_minutes": 120,
  "due_at": "2026-04-10T00:00:00Z",
  "remind_at": "2026-04-09T20:00:00Z",
  "subtasks": [
    { "title": "第一章例题", "order": 1 },
    { "title": "第二章习题", "order": 2 }
  ]
}
```

- **Resp**

```json
{
  "data": {
    "id": "...",
    "type": "todo",
    "status": "active",
    "created_at": "...",
    "...": "..."
  }
}
```

#### 4.2 获取任务详情（含子任务、标签、累计专注）

- **GET** `/tasks/{taskId}`

- **Resp（示例）**

```json
{
  "data": {
    "id": "...",
    "type": "todo",
    "title": "复习线代",
    "status": "active",
    "tag_ids": ["..."],
    "expected_minutes": 120,
    "due_at": "2026-04-10T00:00:00Z",
    "remind_at": "2026-04-09T20:00:00Z",
    "focus_total_seconds": 5400,
    "subtasks": [
      { "id": "...", "title": "第一章例题", "done": true, "order": 1 },
      { "id": "...", "title": "第二章习题", "done": false, "order": 2 }
    ]
  }
}
```

#### 4.3 更新任务（编辑/保存切换）

- **PATCH** `/tasks/{taskId}`
- **Body**：允许更新 `title/description/tag_ids`、`remind_at`（`null` 表示关闭提醒）以及类型相关字段（`start_at/end_at/due_at/expected_minutes`）；`todo` 的子任务建议使用子任务接口（见下）
- **Resp**：返回更新后的任务

#### 4.4 删除任务

- **DELETE** `/tasks/{taskId}`

#### 4.5 标记完成 / 取消 / 稍后 / 延期（用户操作；与本地提醒弹窗内按钮对应）

- **POST** `/tasks/{taskId}/complete`
- **POST** `/tasks/{taskId}/cancel`
- **POST** `/tasks/{taskId}/snooze`

```json
{ "until": "2026-04-07T12:00:00Z" }
```

- **POST** `/tasks/{taskId}/postpone`

```json
{ "due_at": "2026-04-08T16:00:00Z" }
```

#### 4.6 任务列表（筛选/排序/搜索）

- **GET** `/tasks`

- **Query**
  - `type=block|ddl|todo`（可选）
  - `q=关键词`（可选）
  - `tag_id=...`（可选）
  - `status=active|completed|cancelled|overdue`（可选）
  - `sort=`
    - ddl：`due_at_asc|due_at_desc`
    - todo：`spent_desc|due_at_asc|due_at_desc`
    - block：`start_at_asc|start_at_desc`
  - `page` / `page_size`

- **Resp**

```json
{
  "data": {
    "items": [
      {
        "id": "...",
        "title": "...",
        "type": "ddl",
        "due_at": "...",
        "status": "active"
      }
    ],
    "page": 1,
    "page_size": 20,
    "total": 123
  }
}
```

---

### 5. Todo 子任务

#### 5.1 新增子任务

- **POST** `/tasks/{taskId}/subtasks`
- **Body**

```json
{ "title": "第3章复习", "order": 3 }
```

#### 5.2 更新子任务（勾选完成/改名/排序）

- **PATCH** `/subtasks/{subtaskId}`
- **Body**

```json
{ "done": true }
```

#### 5.3 删除子任务

- **DELETE** `/subtasks/{subtaskId}`

---

### 6. 首页「今天+明天」与「最近 Todo」

#### 6.1 今天与明天任务（按时间排序）

- **GET** `/home/upcoming`
- **Query**：`from`（默认今天 00:00）`to`（默认明天 23:59）
- **Resp**：返回 block（按 start_at）+ ddl（按 due_at）等合并后的列表（服务端统一排序）

#### 6.2 最近 Todo（按最近使用频率）

- **GET** `/home/recent-todos`
- **Query**：`limit=50`

---

### 7. 番茄钟（专注会话）

#### 7.1 开始专注

- **POST** `/focus-sessions`
- **Body**

```json
{ "task_id": "...", "planned_seconds": 1500, "noise_id": "rain_01" }
```

- **Resp**

```json
{
  "data": {
    "id": "...",
    "task_id": "...",
    "status": "running",
    "started_at": "...",
    "planned_seconds": 1500
  }
}
```

#### 7.2 结束专注（手动结束按钮 / 杀后台自动结束后的补报）

- **POST** `/focus-sessions/{sessionId}/stop`
- **Body**

```json
{ "ended_at": "2026-04-07T09:25:00Z", "reason": "manual|app_killed|timeout" }
```

#### 7.3 获取某任务的专注统计

- **GET** `/tasks/{taskId}/focus-summary`
- **Query**：`from/to`（可选）

---

### 8. 统计（任务数 + 专注柱状图）

#### 8.1 本周任务统计

- **GET** `/stats/tasks/weekly`
- **Query**：`week_start=2026-04-06`（可选，默认本周周一）
- **Resp**

```json
{
  "data": {
    "completed": 12,
    "pending": 7,
    "cancelled": 1,
    "overdue": 2,
    "top_tag": { "tag_id": "...", "name": "学习", "count": 6 }
  }
}
```

#### 8.2 专注统计（按天 + 按标签分组柱状图）

- **GET** `/stats/focus/daily-by-tag`
- **Query**：`from/to`
- **Resp**

```json
{
  "data": [
    {
      "date": "2026-04-07",
      "tags": [
        { "tag_id": "...", "seconds": 3600 },
        { "tag_id": "...", "seconds": 900 }
      ]
    },
    { "date": "2026-04-08", "tags": [{ "tag_id": "...", "seconds": 1800 }] }
  ]
}
```

---

### 9. 日历（日/周/月视图）

#### 9.1 获取日历事件（任务投影）

- **GET** `/calendar/events`
- **Query**
  - `view=day|week|month`
  - `anchor=2026-04-07`（视图锚点日期）
  - `tz=Asia/Shanghai`（可选，用于服务端切分 day/week/month 边界）

- **Resp（建议统一事件结构）**

```json
{
  "data": [
    {
      "id": "task:...",
      "source": "task",
      "type": "block",
      "title": "上课",
      "start_at": "...",
      "end_at": "...",
      "tag_ids": ["..."]
    },
    {
      "id": "task:...",
      "source": "task",
      "type": "ddl",
      "title": "交作业",
      "start_at": "...",
      "end_at": "...",
      "all_day": true
    }
  ]
}
```

---

### 10. 任务提醒（客户端实现，无服务端推送接口）

- **职责划分**：`remind_at` 由本 API 在创建/更新/拉取任务时返回；客户端在 **收到或本地保存任务后** 自行 `schedule` / `cancel` 系统闹钟与通知；任务完成、删除、延期、稍后后客户端应 **取消或重排** 对应闹钟。
- **无以下接口**：不提供 `/devices`、`/notifications`、FCM 推送、服务端定时触发提醒。
- **番茄钟**：计时与结束 UI 均在客户端；若需云端统计，仍仅使用「7. 番茄钟」中的 `focus-sessions` 上报，与提醒无关。

