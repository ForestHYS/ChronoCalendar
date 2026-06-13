## API 文档

本文合并原 API、数据库、Agent 与后端接口说明，按当前代码实现校准。

### 1. 概述与约定

- **Base URL**：`/api/v1`
- **认证**：Bearer Token（`Authorization: Bearer <access_token>`）
- **时间**：统一使用 ISO 8601（UTC）存储与传输；客户端展示时按本地时区转换
- **ID**：用户、任务、标签、子任务、专注会话、Agent 会话均使用 UUID
- **通用响应结构**
  - 成功：`{ "data": ... }`
  - 失败：`{ "error": { "code": "STRING", "message": "STRING", "details": {...?} } }`
- **任务类型**
  - `block`：固定占用时间（有 `start_at/end_at`）
  - `ddl`：仅截止时间（有 `due_at`）
  - `todo`：可含子任务或预期投入时长（`expected_minutes?`，可选 `due_at?`）
- **任务提醒**：服务端仅持久化 `remind_at`；实际响铃、通知和前台半屏弹窗由客户端本地调度。服务端不提供 `/devices`、`/notifications`、FCM 推送或定时触发提醒。

---

### 2. Auth（账号体系）

#### 2.1 注册

- **POST** `/auth/register/`
- 无需认证
- **Body**

```json
{ "email": "user@example.com", "password": "yourpassword", "name": "张三" }
```

`name` 可选。

#### 2.2 登录

- **POST** `/auth/login/`
- 无需认证
- **Body**

```json
{ "email": "user@example.com", "password": "yourpassword" }
```

- **Resp**

```json
{
  "data": {
    "access_token": "...",
    "refresh_token": "...",
    "user": { "id": "...", "name": "张三" }
  }
}
```

#### 2.3 刷新 Token

- **POST** `/auth/refresh/`

```json
{ "refresh_token": "..." }
```

#### 2.4 退出登录

- **POST** `/auth/logout/`

```json
{ "refresh_token": "..." }
```

服务端会尝试将 refresh token 加入黑名单；客户端也应清除本地 token。

#### 2.5 修改昵称

- **PATCH** `/auth/me/`

```json
{ "name": "新昵称" }
```

#### 2.6 注销账户

- **DELETE** `/auth/me/`

```json
{ "current_password": "xxx", "refresh_token": "..." }
```

#### 2.7 修改密码

- **POST** `/auth/change-password/`

```json
{ "current_password": "old", "new_password": "new_password" }
```

---

### 3. 标签（用户自定义）

| 操作 | Method | URL | Body |
|------|--------|-----|------|
| 创建标签 | `POST` | `/tags/` | `{ "name": "学习", "color": "#4F46E5" }` |
| 获取标签列表 | `GET` | `/tags/` | - |
| 更新标签 | `PATCH` | `/tags/{tagId}/` | `{ "name": "...", "color": "..." }` |
| 删除标签 | `DELETE` | `/tags/{tagId}/` | - |

标签名不能为空；同一用户下标签名唯一。

---

### 4. 任务（block / ddl / todo）

#### 4.0 任务数据模型

三类任务共享 `/tasks/` 集合，以 `type` 字段区分。服务端创建后不允许 PATCH 修改 `type`。

##### 4.0.1 通用字段

| 字段 | 类型 | 读写 | 说明 |
|---|---|---|---|
| `id` | `string` | 只读 | UUID |
| `type` | `"block" \| "ddl" \| "todo"` | 创建必填 | 任务类型 |
| `title` | `string` | 必填 | 任务标题 |
| `description` | `string` | 可选 | 备注，默认空字符串 |
| `tag_ids` | `string[]` | 可选 | 关联标签 ID 列表 |
| `tags` | `Tag[]` | 只读 | 标签对象快照 |
| `status` | `"active" \| "completed" \| "cancelled" \| "overdue"` | 只读 | `overdue` 为计算值，不落库 |
| `remind_at` | `datetime?` | 可选 | 提醒时间；`null` 表示关闭提醒 |
| `snoozed_until` | `datetime?` | 只读 | 稍后时间 |
| `focus_total_seconds` | `number` | 只读 | 已停止专注会话的累计秒数 |
| `last_activity_at` | `datetime` | 只读 | 最近活动时间，用于 Todo 排序 |
| `completed_at` | `datetime?` | 只读 | 完成时间 |
| `created_at` / `updated_at` | `datetime` | 只读 | 创建 / 更新时间 |

##### 4.0.2 Block —— 固定时间段任务

| 字段 | 类型 | 读写 | 说明 |
|---|---|---|---|
| `start_at` | `datetime` | 必填 | 开始时间 |
| `end_at` | `datetime` | 必填 | 结束时间，须晚于 `start_at` |

约束：`end_at > start_at`，否则返回 `400 INVALID_TIME_RANGE`。

##### 4.0.3 DDL —— 截止时间任务

| 字段 | 类型 | 读写 | 说明 |
|---|---|---|---|
| `due_at` | `datetime` | 必填 | 截止时间 |

##### 4.0.4 Todo —— 待办任务

| 字段 | 类型 | 读写 | 说明 |
|---|---|---|---|
| `due_at` | `datetime?` | 可选 | 可选截止时间 |
| `expected_minutes` | `number?` | 可选 | 预期投入时长，范围 1–99999 分钟 |
| `subtasks` | `SubTask[]` | 创建可传，响应只读 | 子任务列表 |

`SubTask` 结构：

| 字段 | 类型 | 读写 | 说明 |
|---|---|---|---|
| `id` | `string` | 只读 | UUID |
| `title` | `string` | 可读写 | 子任务标题 |
| `done` | `boolean` | 可读写 | 是否完成 |
| `order` | `number` | 可读写 | 排序序号，需 `>=1` |
| `created_at` / `updated_at` | `datetime` | 只读 | 创建 / 更新时间 |

##### 4.0.5 状态流转

```text
active
├── complete  -> completed
├── cancel    -> cancelled
└── due_at/end_at 过期 -> overdue（计算值）
                       └── postpone/snooze -> active
```

---

#### 4.1 创建任务

- **POST** `/tasks/`

block：

```json
{
  "type": "block",
  "title": "上课",
  "tag_ids": [],
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
  "tag_ids": [],
  "due_at": "2026-04-08T16:00:00Z"
}
```

todo：

```json
{
  "type": "todo",
  "title": "复习线代",
  "expected_minutes": 120,
  "subtasks": [{ "title": "第一章例题", "order": 1 }]
}
```

#### 4.2 获取任务列表

- **GET** `/tasks/`

| 参数 | 说明 |
|------|------|
| `type` | `block \| ddl \| todo`（可选） |
| `q` | 标题关键词，模糊匹配 |
| `tag_id` | 单标签过滤 |
| `tag_ids` | 多标签 AND 过滤，逗号分隔 |
| `status` | `active \| completed \| cancelled \| overdue` |
| `sort` | `due_at_asc/desc`、`start_at_asc/desc`、`spent_desc`、`created_at_asc/desc` |
| `page` / `page_size` | 默认 1 / 20，`page_size` 上限 100 |

默认排序：`ddl` 按 `due_at` 升序，`block` 按 `start_at` 升序，`todo` 按 `last_activity_at` 降序，混合类型按 `created_at` 降序。

#### 4.3 获取 / 更新 / 删除任务

| 操作 | Method & URL | Body |
|------|-------------|------|
| 获取详情 | `GET /tasks/{taskId}/` | - |
| 更新 | `PATCH /tasks/{taskId}/` | `title/description/tag_ids/remind_at` 及类型相关字段 |
| 删除 | `DELETE /tasks/{taskId}/` | - |

#### 4.4 状态操作

| 操作 | Method & URL | Body |
|------|-------------|------|
| 标记完成 | `POST /tasks/{taskId}/complete/` | - |
| 取消 | `POST /tasks/{taskId}/cancel/` | - |
| 稍后 | `POST /tasks/{taskId}/snooze/` | `{ "until": "2026-04-07T12:00:00Z" }` |
| 延期 | `POST /tasks/{taskId}/postpone/` | `{ "due_at": "2026-04-08T16:00:00Z" }` |

`postpone` 仅支持 `ddl` / `todo`；`block` 请通过 PATCH 更新 `start_at/end_at`。

#### 4.5 Todo 子任务

| 操作 | Method & URL | Body |
|------|-------------|------|
| 新增 | `POST /tasks/{taskId}/subtasks/` | `{ "title": "...", "order": 1 }` |
| 更新 | `PATCH /subtasks/{subtaskId}/` | `{ "title": "...", "done": true, "order": 2 }` |
| 删除 | `DELETE /subtasks/{subtaskId}/` | - |

---

### 5. 番茄钟与专注统计

#### 5.1 开始专注

- **POST** `/focus-sessions/`

```json
{ "task_id": "...", "planned_seconds": 1500, "noise_id": "rain_01" }
```

`planned_seconds` 范围为 1 到 86400 秒。

#### 5.2 结束专注

- **POST** `/focus-sessions/{sessionId}/stop/`

```json
{ "actual_seconds": 1480, "stop_reason": "manual" }
```

`stop_reason` 可选值：`manual` / `app_killed` / `timeout`。若传入未知值，服务端按 `manual` 处理。

#### 5.3 近 7 日专注统计

- **GET** `/stats/focus/last-week/`

返回当前本地日期向前滚动窗口内的总专注秒数与按标签分组秒数。

```json
{
  "data": {
    "total_seconds": 3600,
    "by_tag": [
      { "tag_id": "uuid", "seconds": 1800 },
      { "tag_id": "__untagged__", "seconds": 1200 }
    ]
  }
}
```

> 当前服务端没有 `/home/upcoming`、`/home/recent-todos`、`/calendar/events`、`/stats/tasks/weekly`、`/tasks/{id}/focus-summary` 路由；这些页面数据由前端仓库缓存与现有 `/tasks/`、`/stats/focus/last-week/` 组合得到。

---

### 6. 导入 / 导出

#### 6.1 导出全部数据

- **GET** `/tasks/export/`

返回当前用户的标签、任务、子任务与专注会话备份数据。

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
        "focus_sessions": []
      }
    ]
  }
}
```

#### 6.2 导入数据

- **POST** `/tasks/import/?mode=merge`
- **POST** `/tasks/import/?mode=duplicate`

请求体为导出端点返回的 `data` 部分，不带外层 `{ "data": ... }`。

| mode | 行为 |
|---|---|
| `merge` | UUID 与库内已有记录匹配则覆盖，否则按文件 UUID 新建；幂等 |
| `duplicate` | 任务、子任务、专注会话全部生成新 UUID |

导入使用事务；任一记录失败会整体回滚，并返回 `IMPORT_ERROR`。

---

### 7. Agent API

Agent 基于 LangGraph 工作流。简单创建/编辑只返回草稿并打开编辑页，不直接写任务表；删除等高风险操作必须先审批。

![LangGraph Agent 工作流](assets/longgraph.png)

#### 7.1 会话与消息

| 操作 | Method | URL |
|------|--------|-----|
| 获取最近会话 | `GET` | `/agent/sessions/` |
| 创建会话 | `POST` | `/agent/sessions/` |
| 获取消息 | `GET` | `/agent/sessions/{session_id}/messages/` |
| 发送消息 | `POST` | `/agent/sessions/{session_id}/messages/` |

发送消息 Body：

```json
{
  "text": "明天下午三点提醒我复习线代",
  "client_context": {},
  "interaction": {}
}
```

`text` 与 `interaction` 至少传一个。返回：

```json
{
  "data": {
    "response": { "type": "message", "text": "..." },
    "assistant_message_id": "uuid"
  }
}
```

当前响应类型包括：

- `message`
- `open_editor`
- `query_result`
- `approval_required`
- `plan_questions`
- `plan_outline`
- `plan_preview`

#### 7.2 审批

| 操作 | Method | URL |
|------|--------|-----|
| 查看审批 | `GET` | `/agent/approvals/{approval_id}/` |
| 批准审批 | `POST` | `/agent/approvals/{approval_id}/approve/` |
| 拒绝审批 | `POST` | `/agent/approvals/{approval_id}/reject/` |

当前审批执行支持 `delete_task`。

#### 7.3 长期规划确认

- **POST** `/agent/confirm-plan/`

```json
{
  "tasks": [{ "type": "todo", "title": "阶段一复习", "subtasks": [] }],
  "client_context": {},
  "source_message_id": "uuid",
  "selected_indices": [0, 2]
}
```

单次最多创建 50 个任务。

#### 7.4 用户级 AI 配置

| 操作 | Method | URL |
|------|--------|-----|
| 获取配置 | `GET` | `/agent/llm-config/` |
| 更新配置 | `PATCH` | `/agent/llm-config/` |
| 测试 LLM | `POST` | `/agent/llm-test/` |

可配置字段：

```json
{
  "base_url": "https://api.example.com",
  "api_key": "sk-...",
  "model_name": "model",
  "asr_base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
  "asr_api_key": "sk-...",
  "asr_model": "qwen3-asr-flash",
  "tts_base_url": "https://dashscope.aliyuncs.com/api/v1",
  "tts_api_key": "sk-...",
  "tts_model": "qwen3-tts-flash",
  "tts_voice": "Cherry"
}
```

配置优先级：用户个人配置 > 服务器环境变量 > 代码默认值。没有可用 API Key 时，Agent 返回“AI 未配置”提示，不应产生 500。

#### 7.5 语音接口

- **POST** `/agent/asr/`

```json
{ "audio_base64": "...", "format": "wav" }
```

支持输入格式：`wav` / `mp3`。最大音频大小为 8MB。

- **POST** `/agent/tts/`

```json
{ "text": "你好", "voice": "Cherry", "format": "mp3" }
```

支持输出格式：`mp3` / `wav`。

#### 7.6 当前注册 Skill

| Skill | 风险 | 是否审批 | 说明 |
|------|------|----------|------|
| `search_tasks` | low | 否 | 查询任务，支持标题、类型、时间区间 |
| `build_task_draft` | low | 否 | 生成单个任务草稿 |
| `check_block_conflict` | low | 否 | 检查 block 时间冲突 |
| `delete_task` | high | 是 | 删除任务 |
| `plan_gather_requirements` | low | 否 | 长期规划需求收集 |
| `plan_generate_outline` | low | 否 | 长期规划方案大纲 |
| `plan_schedule_tasks` | low | 否 | 长期规划任务排程预览 |

---

### 8. 数据库设计

#### 8.1 核心表

| 表名 | 说明 |
|------|------|
| `users` | 自定义用户表，UUID 主键，email 登录 |
| `tags` | 用户自定义标签，`(user, name)` 唯一 |
| `tasks` | 任务母表，保存共享字段 |
| `task_block` | block 扩展表，`task_id` 一对一 |
| `task_ddl` | ddl 扩展表，`task_id` 一对一 |
| `task_todo` | todo 扩展表，`task_id` 一对一 |
| `task_tags` | 任务-标签多对多中间表 |
| `subtasks` | Todo 子任务 |
| `focus_sessions` | 番茄钟专注会话 |
| `agent_sessions` | Agent 会话 |
| `agent_messages` | Agent 消息 |
| `agent_approval_requests` | Agent 审批请求 |
| `agent_llm_config` | 用户级 LLM / ASR / TTS 配置 |

#### 8.2 任务表拆分原则

单个 `tasks` 行保存共享字段：`title`、`description`、`status`、`tags`、`remind_at`、`last_activity_at`、`snoozed_until` 等。类型专属字段放在一对一扩展表：

- `task_block(start_at, end_at)`，并由 CHECK 约束保证 `end_at > start_at`
- `task_ddl(due_at)`
- `task_todo(due_at, expected_minutes)`

读取任务时后端使用 `_task_qs(user)` 统一 `select_related` / `prefetch_related`，避免三类扩展表、标签和子任务产生 N+1 查询。

#### 8.3 计算字段

- `effective_status`：`overdue` 不落库，只在 `status=active` 且 `due_at/end_at` 已过期时返回
- `focus_total_seconds`：读取时聚合 `focus_sessions(status="stopped").actual_seconds`

#### 8.4 索引建议

- `tasks(user_id, status, type)`
- `tasks(user_id, last_activity_at)`
- `task_block(start_at)` / `task_block(end_at)`
- `task_ddl(due_at)`
- `task_todo(due_at)`
- `focus_sessions(user_id, started_at)`
- `focus_sessions(task_id, status)`

---

### 9. 错误码

| code | HTTP | 说明 |
|---|---|---|
| `VALIDATION_ERROR` | 400 | 字段格式/类型校验失败 |
| `MISSING_FIELD` | 400 | 必填字段缺失 |
| `INVALID_TIME_RANGE` | 400 | block 的 `end_at` ≤ `start_at` |
| `INVALID_OPERATION` | 422 | 操作不适用于该任务类型 |
| `ALREADY_COMPLETED` | 400 | 任务已完成，不可重复操作 |
| `ALREADY_CANCELLED` | 400 | 任务已取消，不可重复操作 |
| `IMPORT_ERROR` | 400 | 导入数据格式/字段不合法，或违反 DB 约束 |
| `NOT_FOUND` | 404 | 资源不存在或无权访问 |
| `MISSING_API_KEY` | 400 | AI / 语音 API Key 未配置 |
| `INVALID_API_KEY` | 400 | AI / 语音 API Key 无效 |
| `TIMEOUT` | 400 | AI / 语音服务连接超时 |
| `RATE_LIMIT` | 429 | AI / 语音服务额度不足或请求过于频繁 |

