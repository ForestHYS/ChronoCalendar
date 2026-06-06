# ChronoCalendar 后端接口文档

---

## 快速启动

```bash
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
# 服务运行于 http://localhost:8000
```

---

## 端点总览

| 操作 | Method | URL |
|---|---|---|
| 注册 | `POST` | `/api/v1/auth/register/` |
| 登录获取 Token | `POST` | `/api/v1/auth/login/` |
| 刷新 Token | `POST` | `/api/v1/auth/refresh/` |
| 登出 | `POST` | `/api/v1/auth/logout/` |
| 注销账户 | `DELETE` | `/api/v1/auth/me/` |
| 创建任务 | `POST` | `/api/v1/tasks/` |
| 查询任务列表 | `GET` | `/api/v1/tasks/?type=block&status=active` |
| 查询单个任务 | `GET` | `/api/v1/tasks/{id}/` |
| 更新任务 | `PATCH` | `/api/v1/tasks/{id}/` |
| 删除任务 | `DELETE` | `/api/v1/tasks/{id}/` |
| 标记完成 | `POST` | `/api/v1/tasks/{id}/complete/` |
| 取消 | `POST` | `/api/v1/tasks/{id}/cancel/` |
| 稍后 | `POST` | `/api/v1/tasks/{id}/snooze/` |
| 延期 | `POST` | `/api/v1/tasks/{id}/postpone/` |
| 新增子任务 | `POST` | `/api/v1/tasks/{id}/subtasks/` |
| 更新子任务 | `PATCH` | `/api/v1/subtasks/{id}/` |
| 删除子任务 | `DELETE` | `/api/v1/subtasks/{id}/` |
| 导出全部数据 | `GET` | `/api/v1/tasks/export/` |
| 导入数据 | `POST` | `/api/v1/tasks/import/?mode=merge\|duplicate` |

---

## 约定

- **Base URL**：`http://localhost:8000/api/v1`
- **认证**：所有接口（除登录/刷新）需在 Header 携带 `Authorization: Bearer <access_token>`
- **时间格式**：ISO 8601 UTC，例如 `2026-04-22T08:00:00Z`
- **成功响应**：`{ "data": ... }`
- **失败响应**：`{ "error": { "code": "...", "message": "...", "details": {...} } }`

---

## 认证

> 注册、登录端点无需携带 Token；刷新和登出需携带对应 token。

---

### 注册

```
POST /auth/register/
```

**请求体：**

```json
{ "email": "user@example.com", "password": "yourpassword", "name": "张三" }
```

> `name` 可选。

**成功响应（201）：**

```json
{
  "data": {
    "access_token": "<access_token>",
    "refresh_token": "<refresh_token>",
    "user": { "id": "...", "name": "张三" }
  }
}
```

---

### 登录

```
POST /auth/login/
```

**请求体：**

```json
{ "email": "user@example.com", "password": "yourpassword" }
```

**成功响应（200）：**

```json
{
  "data": {
    "access_token": "<access_token>",
    "refresh_token": "<refresh_token>",
    "user": { "id": "...", "name": "张三" }
  }
}
```

**失败响应（401）：**

```json
{ "error": { "code": "INVALID_CREDENTIALS", "message": "邮箱或密码错误" } }
```

---

### 刷新 Token

```
POST /auth/refresh/
```

**请求体：**

```json
{ "refresh_token": "<refresh_token>" }
```

**成功响应（200）：**

```json
{ "data": { "access_token": "<new_access_token>" } }
```

---

### 登出

```
POST /auth/logout/
Authorization: Bearer <access_token>
```

**请求体：**

```json
{ "refresh_token": "<refresh_token>" }
```

> 服务端将 refresh_token 加入黑名单（需启用 `token_blacklist`）。  
> 若未启用黑名单，客户端删除本地 token 即视为登出，本接口仍返回 204。

**成功响应：** `204 No Content`

---

### 注销账户

```
DELETE /auth/me/
Authorization: Bearer <access_token>
```

**请求体：**

```json
{ "current_password": "yourpassword", "refresh_token": "<refresh_token>" }
```

服务端会校验当前密码，校验通过后删除当前用户及其关联数据。客户端应清除本地 token 并回到登录页。

**成功响应：**

```json
{ "data": { "ok": true } }
```

---

## 标签

### 获取所有标签

```
GET /tags/
```

**响应：**

```json
{
  "data": [
    { "id": "uuid", "name": "学习", "color": "#4F46E5", "created_at": "...", "updated_at": "..." }
  ]
}
```

---

### 创建标签

```
POST /tags/
```

**请求体：**

```json
{ "name": "学习", "color": "#4F46E5" }
```

---

### 更新标签

```
PATCH /tags/{tagId}/
```

**请求体（任意字段可省略）：**

```json
{ "name": "娱乐", "color": "#22C55E" }
```

---

### 删除标签

```
DELETE /tags/{tagId}/
```

**成功响应：** `204 No Content`

---

## 任务 — 通用

### 获取任务列表

```
GET /tasks/
```

**Query 参数：**

| 参数 | 可选值 | 说明 |
|---|---|---|
| `type` | `block` \| `ddl` \| `todo` | 按类型筛选 |
| `status` | `active` \| `completed` \| `cancelled` \| `overdue` | 按状态筛选 |
| `tag_id` | `<uuid>` | 按标签筛选 |
| `q` | 任意字符串 | 标题关键词搜索 |
| `sort` | `start_at_asc/desc`（block）<br>`due_at_asc/desc`（ddl/todo）<br>`spent_desc`（todo） | 排序方式 |
| `page` | 整数，默认 1 | 页码 |
| `page_size` | 整数，默认 20，最大 100 | 每页数量 |

**响应：**

```json
{
  "data": {
    "items": [ { "id": "...", "type": "ddl", "title": "...", "status": "active", "..." : "..." } ],
    "page": 1,
    "page_size": 20,
    "total": 42
  }
}
```

---

### 获取任务详情

```
GET /tasks/{taskId}/
```

---

### 更新任务（PATCH）

```
PATCH /tasks/{taskId}/
```

支持更新的通用字段：`title`、`description`、`tag_ids`、`remind_at`（传 `null` 关闭提醒）。  
类型专属字段见各类型小节。

---

### 删除任务

```
DELETE /tasks/{taskId}/
```

**成功响应：** `204 No Content`

---

## 任务 — Block（固定时间段）

适用场景：上课、会议、健身等有明确起止时间的占用块。

### 创建

```
POST /tasks/
```

**请求体：**

```json
{
  "type": "block",
  "title": "高数课",
  "description": "第五章极限",
  "tag_ids": ["<tagId>"],
  "start_at": "2026-04-22T08:00:00Z",
  "end_at":   "2026-04-22T09:40:00Z",
  "remind_at": "2026-04-22T07:50:00Z"
}
```

> `start_at` 和 `end_at` 均为**必填**；`end_at` 须严格晚于 `start_at`，否则返回 `400 INVALID_TIME_RANGE`。

**成功响应（201）：**

```json
{
  "data": {
    "id": "...",
    "type": "block",
    "title": "高数课",
    "status": "active",
    "start_at": "2026-04-22T08:00:00Z",
    "end_at":   "2026-04-22T09:40:00Z",
    "remind_at": "2026-04-22T07:50:00Z",
    "tag_ids": ["..."],
    "focus_total_seconds": 0,
    "created_at": "...",
    "updated_at": "..."
  }
}
```

### 更新时间

```
PATCH /tasks/{taskId}/
```

**请求体（仅传需要修改的字段）：**

```json
{
  "start_at": "2026-04-22T09:00:00Z",
  "end_at":   "2026-04-22T10:30:00Z"
}
```

---

## 任务 — DDL（截止时间）

适用场景：作业提交、项目汇报等仅有最终期限的任务。

### 创建

```
POST /tasks/
```

**请求体：**

```json
{
  "type": "ddl",
  "title": "提交数据库作业",
  "tag_ids": ["<tagId>"],
  "due_at": "2026-04-25T16:00:00Z",
  "remind_at": "2026-04-25T14:00:00Z"
}
```

> `due_at` 为**必填**。超过截止时间后，`status` 自动返回 `overdue`（不落库，实时计算）。

**成功响应（201）：**

```json
{
  "data": {
    "id": "...",
    "type": "ddl",
    "title": "提交数据库作业",
    "status": "active",
    "due_at": "2026-04-25T16:00:00Z",
    "remind_at": "2026-04-25T14:00:00Z",
    "tag_ids": ["..."],
    "focus_total_seconds": 0,
    "created_at": "...",
    "updated_at": "..."
  }
}
```

### 更新截止时间

```
PATCH /tasks/{taskId}/
```

```json
{ "due_at": "2026-04-26T16:00:00Z" }
```

---

## 任务 — Todo（待办）

适用场景：自由安排的学习、生活待办，可拆解为子任务或设定预期时长。

### 创建

```
POST /tasks/
```

**请求体：**

```json
{
  "type": "todo",
  "title": "复习线性代数",
  "tag_ids": ["<tagId>"],
  "due_at": "2026-04-28T00:00:00Z",
  "expected_minutes": 120,
  "remind_at": "2026-04-27T20:00:00Z",
  "subtasks": [
    { "title": "第一章例题", "order": 1 },
    { "title": "第二章习题", "order": 2 }
  ]
}
```

> `due_at`、`expected_minutes`、`subtasks` 均为**可选**；`subtasks` 仅在创建时可一并提交，后续通过子任务接口维护。

**成功响应（201）：**

```json
{
  "data": {
    "id": "...",
    "type": "todo",
    "title": "复习线性代数",
    "status": "active",
    "due_at": "2026-04-28T00:00:00Z",
    "expected_minutes": 120,
    "remind_at": "2026-04-27T20:00:00Z",
    "tag_ids": ["..."],
    "focus_total_seconds": 0,
    "subtasks": [
      { "id": "...", "title": "第一章例题", "done": false, "order": 1 },
      { "id": "...", "title": "第二章习题", "done": false, "order": 2 }
    ],
    "created_at": "...",
    "updated_at": "..."
  }
}
```

### 更新

```
PATCH /tasks/{taskId}/
```

```json
{
  "expected_minutes": 180,
  "due_at": null
}
```

> 传 `null` 表示清空该字段（如取消截止时间）。

---

## 任务状态操作

### 标记完成

```
POST /tasks/{taskId}/complete/
```

### 取消任务

```
POST /tasks/{taskId}/cancel/
```

### 稍后完成（Snooze）

```
POST /tasks/{taskId}/snooze/
```

**请求体：**

```json
{ "until": "2026-04-22T14:00:00Z" }
```

### 延期（仅 DDL / Todo）

```
POST /tasks/{taskId}/postpone/
```

**请求体：**

```json
{ "due_at": "2026-04-30T16:00:00Z" }
```

> 延期会将 `status` 重置为 `active`。Block 任务不支持此操作，请改用 `PATCH` 更新 `end_at`。

---

## 子任务

子任务仅属于 `todo` 类型的任务。

### 新增子任务

```
POST /tasks/{taskId}/subtasks/
```

**请求体：**

```json
{ "title": "第三章习题", "order": 3 }
```

**成功响应（201）：**

```json
{
  "data": { "id": "...", "title": "第三章习题", "done": false, "order": 3 }
}
```

### 更新子任务（勾选/改名/排序）

```
PATCH /subtasks/{subtaskId}/
```

**请求体（任意字段可省略）：**

```json
{ "done": true }
```

```json
{ "title": "第三章综合题", "order": 4 }
```

### 删除子任务

```
DELETE /subtasks/{subtaskId}/
```

**成功响应：** `204 No Content`

---

## 导入 / 导出

### 导出全部数据

```
GET /tasks/export/
```

无需任何参数。返回当前用户的**全量任务、标签、子任务、专注会话**，可保存为 JSON 文件用于备份。

**成功响应（200）：**

```json
{
  "data": {
    "version": 1,
    "exported_at": "2026-05-16T12:00:00Z",
    "tags": [
      { "id": "tag-uuid", "name": "工作", "color": "#6366F1" }
    ],
    "tasks": [
      {
        "id": "task-uuid",
        "type": "block",
        "title": "周会",
        "description": "",
        "status": "active",
        "remind_at": null,
        "created_at": "2026-05-10T03:00:00Z",
        "completed_at": null,
        "cancelled_at": null,
        "tag_ids": ["tag-uuid"],
        "block": { "start_at": "...", "end_at": "..." },
        "focus_sessions": [
          {
            "id": "fs-uuid",
            "status": "stopped",
            "started_at": "...",
            "ended_at": "...",
            "planned_seconds": 1500,
            "actual_seconds": 1480,
            "stop_reason": "timeout",
            "noise_id": ""
          }
        ]
      },
      {
        "id": "...",
        "type": "todo",
        "title": "...",
        "todo": { "due_at": null, "expected_minutes": 120 },
        "subtasks": [
          {
            "id": "...",
            "title": "...",
            "done": true,
            "order": 1,
            "done_at": "...",
            "created_at": "..."
          }
        ],
        "...": "..."
      }
    ]
  }
}
```

> 字段说明：`type=block` 带 `block`；`type=ddl` 带 `ddl`；`type=todo` 带 `todo` 和 `subtasks`。
>
> **不导出**的字段（导入时由服务端重建）：`last_activity_at`、`snoozed_until`、`updated_at`。

---

### 导入数据

```
POST /tasks/import/?mode=merge
POST /tasks/import/?mode=duplicate
```

**请求体**：即导出端点返回的 `data` 部分（不带 `{"data": ...}` 包装）。

**Query 参数 `mode`**（默认 `merge`）：

| mode | 行为 |
|---|---|
| `merge` | UUID 与库内已有任务匹配 → 整体覆盖；否则按文件 UUID 新建。**幂等**，适合"还原备份"。 |
| `duplicate` | 全部生成新 UUID（包括子任务、专注会话），始终新建。适合"复制一份" / 跨账号导入。 |

> **标签**始终按 `name` 在当前用户下"找不到则创建"，与 `mode` 无关 —— 同名标签不会重复。

**成功响应（200）：**

```json
{
  "data": {
    "mode": "merge",
    "tags": { "created": 1, "reused": 2 },
    "tasks": { "created": 5, "updated": 3 }
  }
}
```

**事务原子**：导入过程中任何一条记录失败，整个导入回滚，不会留下半成品。

**常见失败：**

| 错误 message | 原因 |
|---|---|
| `不支持的导出版本: ...` | 文件 `version` 与服务端 `EXPORT_VERSION` 不匹配 |
| `任务 X 的 type 与库内记录不一致` | merge 模式下，文件中某任务 UUID 已在库存在，但 `type` 不同（type 不可变） |
| `任务 X 引用未声明的 tag_id: ...` | 任务 `tag_ids` 引用了不在文件 `tags[]` 中的标签 |
| `任务 X (block) end_at 必须晚于 start_at` | 违反 `task_block` 的 CHECK 约束 |

---

## 错误码

| code | HTTP | 说明 |
|---|---|---|
| `VALIDATION_ERROR` | 400 | 字段格式/类型校验失败 |
| `MISSING_FIELD` | 400 | 必填字段缺失 |
| `INVALID_TIME_RANGE` | 400 | block 的 `end_at` ≤ `start_at` |
| `INVALID_OPERATION` | 422 | 操作不适用于该任务类型（如对 block 执行延期） |
| `ALREADY_COMPLETED` | 400 | 任务已完成，不可重复操作 |
| `ALREADY_CANCELLED` | 400 | 任务已取消，不可重复操作 |
| `IMPORT_ERROR` | 400 | 导入数据格式/字段不合法，或违反 DB 约束 |
| —  | 401 | Token 无效或已过期，需重新登录 |
| —  | 404 | 任务/标签/子任务不存在，或无权访问 |
