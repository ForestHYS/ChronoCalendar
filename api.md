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

