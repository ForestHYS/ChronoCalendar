# 智能 Agent 技术方案（LangGraph 架构）

本文档定义：在现有「任务 / 日历 / 番茄钟」软件中新增一个**可对话的智能 Agent**。用户可输入任意文本或语音指令（如“创建任务”“查询指定任务”“规划未来一周”），Agent 能执行对应工作，并满足以下约束：

- **简单创建/编辑任务**：Agent **不直接落库创建/修改**，而是生成结构化草稿并**弹出已预填的任务编辑页**，由用户确认保存。
- **复杂规划任务**（如“规划未来一周任务”）：Agent **可以直接创建任务**，同时在 Agent 交互界面可查看本次新建的任务项（并可一键撤销/批量编辑）。
- **危险操作**（删除、批量改动、覆盖日程、取消大量任务等）：必须先请求用户批准（approve）后才能执行。
- **多模态输入**：支持语音与文字；不自建模型，调用第三方 API（LLM、ASR、可选 TTS）。

---

## 一、整体架构

### 1.1 模块划分

- **前端（Flutter）**
  - `AgentChatPage`：对话界面（文字输入 + 语音输入按钮 + 结果卡片）。
  - `TaskEditorPage`：复用现有「任务详情/编辑」UI，增加“从 Agent 草稿打开”的入口与展示。
  - `ApprovalSheet`：危险操作审批弹窗（展示变更摘要、影响范围、可撤销提示）。
  - `AgentCreatedItemsPanel`：展示本次会话/本次规划新建的任务列表（仅复杂规划直建会出现）。
- **后端（Django）**
  - `Agent API`：会话、消息、工具执行、审批、草稿生成与提交。
  - `Domain API`：任务/标签/番茄钟/统计（现有或新增），提供给 Agent 工具层调用。
  - **LangGraph Orchestrator**：Agent 的工作流引擎（可控、可中断等待用户、可审计）。
- **外部模型 API**
  - **ASR**：语音转文字（如 OpenAI / Azure / Google / 科大讯飞等，按你实际选型）。
  - **LLM**：意图识别、信息抽取、规划生成、生成 UI 草稿。
  - （可选）**TTS**：将 Agent 回复读出来（不影响核心功能）。

### 1.2 数据流概览

1. 前端发送 `text` 或 `audio` 到后端 `POST /agent/sessions/{id}/messages`  
2. 若是 `audio`：后端调用 ASR 得到 `transcript` 并进入 LangGraph  
3. LangGraph：解析意图 → 产出 plan → 调用工具（查询/创建草稿/审批/创建任务）  
4. 返回结构化 `AgentResponse` 给前端：  
   - 普通回复：以文本 + 卡片展示  
   - **简单创建/编辑**：返回 `task_draft` + `open_editor` 指令  
   - **危险操作**：返回 `approval_request`（graph 中断等待）  
   - **复杂规划直建**：返回 `created_task_ids` + `created_items` 列表卡片  

---

## 二、能力范围与意图分类（Intent Taxonomy）

### 2.1 用户可能说的话（示例）

- **创建**：创建一个明天下午 3 点到 5 点的学习任务（block）
- **编辑**：把“英语复习”截止时间改到周五晚上
- **查询**：查询「明天」有哪些任务；查询标签为“学习”的 todo；查某个任务详情
- **规划**：帮我规划未来一周的学习与运动安排（含时间块）
- **操作**：标记完成某任务；取消/延期；批量移动；删除
- **统计**：本周完成了多少任务？各标签番茄钟时长？

### 2.2 关键规则映射

- **简单创建/编辑**（单个或少量任务、低风险变更）：返回 `task_draft` 并打开编辑页，不落库。
- **复杂规划**（跨多天、多任务、包含排程策略与冲突处理）：允许直接创建，但要求前端展示“本次创建清单”，并提供“撤销/批量编辑”入口。
- **危险操作**（删除/覆盖/批量取消/批量改时间/影响范围大）：必须先走审批。

---

## 三、前端交互设计（Flutter）

### 3.1 新增页面：Agent 对话页（`AgentChatPage`）

#### 交互区域

- 顶部：会话标题（可显示“AI 助手”）+ 设置入口（是否朗读、模型偏好等可选）
- 中部：消息流（用户/Agent 气泡）+ 卡片渲染
- 底部：
  - 文本输入框（支持多行）
  - 语音按钮（按住说话或点击开始/结束）
  - “发送”按钮

#### 消息卡片类型（建议统一组件渲染）

- **任务草稿卡（DraftCard）**：展示 name/type/time/ddl/tags/subtasks/预计时长等
  - 按钮：`打开编辑页`（主按钮）、`继续补充`（可选）
- **创建清单卡（CreatedListCard）**：复杂规划后展示本次创建的任务列表
  - 每一项：任务摘要 + `查看详情` / `编辑` / `撤销该项`
  - 顶部可加：`撤销全部`（这属于危险操作，需审批或二次确认）
- **审批卡（ApprovalCard）**：危险操作摘要
  - 展示：将要执行的动作、影响任务数量、示例变更、不可逆提示
  - 按钮：`批准执行` / `取消`
- **查询结果卡（QueryResultCard）**：任务列表、日历摘要、统计图数据入口

### 3.2 语音输入（多模态）

#### 推荐方案（简单、稳定）

- 前端录音成 `m4a/wav`（按平台能力）
- 上传到后端：`POST /agent/sessions/{id}/messages`（multipart）
- 后端 ASR → transcript → LangGraph
- 前端在消息流中显示“语音转文字结果”（可折叠）

> 若需要更低延迟，可扩展为流式 ASR（WebSocket），但第一期建议先用“录音上传”。

### 3.3 与既有「任务详情/编辑」页面的集成

你在 `design.md` 中已经定义：详情页与编辑页共享 UI，且有 “AI 快捷设置（语音输入自动生成）”。本方案建议：

- 保持原页面结构不变，仅新增入口参数：
  - `TaskEditorPage(initialDraft: TaskDraft, source: AgentSource)`
- **简单创建/编辑**时：Agent 返回 `TaskDraft`，前端直接打开编辑页并预填；用户点击保存后才调用正常的任务创建/更新 API。
- 编辑页中显示一个轻量提示：
  - “由 AI 草稿生成，保存前请确认”

### 3.4 危险操作审批 UI（`ApprovalSheet`）

危险操作不在编辑页完成（因为可能是批量、删除等），统一使用审批弹窗：

- 展示内容：
  - 动作：删除/批量移动/批量取消/覆盖排程等
  - 影响范围：任务数量、时间跨度
  - 变更摘要（diff-like）：例如 “3 个任务开始时间 +2h”
  - 提示：是否可撤销（支持撤销的要说明撤销窗口）
- 用户选择：
  - 批准：调用 `POST /agent/approvals/{approval_id}`
  - 拒绝：调用 `POST /agent/approvals/{approval_id}/reject`

前端错误提示可复用现有 `showAppErrorDialog`（见 `frontend/lib/core/ui/app_error_dialog.dart`）来展示失败原因。

---

## 四、后端 API 设计（Django）

### 4.1 会话与消息

- `POST /agent/sessions`  
  - 返回 `session_id`
- `GET /agent/sessions/{session_id}`  
  - 返回会话元信息与最近消息（可分页）
- `POST /agent/sessions/{session_id}/messages`  
  - 输入：
    - `text`（可选）
    - `audio_file`（可选，multipart）
    - `client_context`（可选）：当前页面、已选日期视图（日/周/月）、时区、用户偏好等
  - 输出：`AgentResponse`（见 4.3）

### 4.2 草稿提交（简单创建/编辑的落库入口）

- `POST /tasks/from-draft`
  - 输入：`TaskDraft`（前端编辑页保存后提交）
  - 输出：`task_id`
- `PATCH /tasks/{task_id}`
  - 普通编辑流程（不由 Agent 直接调用，除非在“复杂规划”或“用户明确批准的批量编辑”路径）

### 4.3 AgentResponse（结构化返回）

建议返回统一 JSON，前端用 `type` 决定渲染：

- `type: "message"`：纯文本/富文本
- `type: "open_editor"`：携带 `task_draft`，前端打开编辑页
- `type: "approval_required"`：携带 `approval_id` 与 `summary`
- `type: "created_items"`：携带 `created_task_ids` 与可展示摘要列表
- `type: "query_result"`：携带任务列表/统计数据

### 4.4 审批

- `POST /agent/approvals/{approval_id}`（批准）
- `POST /agent/approvals/{approval_id}/reject`（拒绝）
- `GET /agent/approvals/{approval_id}`（查看摘要）

审批对象建议落库保存：`who/when/why/what/diff/expire_at`，确保审计与可回溯。

---

## 五、LangGraph 工作流设计（核心）

### 5.1 状态（State）定义

建议定义一个可序列化状态（便于断点与审计）：

- `user_id`
- `session_id`
- `messages[]`：对话历史（可做摘要）
- `input`：本轮输入（text/transcript）
- `client_context`：前端上下文（时区、当前页面、当前选中日期范围）
- `intent`：本轮意图（create/edit/query/plan/complete/delete/stats…）
- `entities`：抽取结果（任务名、类型、起止时间、ddl、标签、子任务、预期时长…）
- `risk_level`：low/medium/high
- `proposed_actions[]`：准备执行的动作（包含可生成 diff）
- `approval`：若需要审批，包含 `approval_id` 与摘要
- `result`：本轮响应（结构化）

### 5.2 节点（Nodes）与路由（Router）

建议的 LangGraph 节点：

1. **NormalizeInput**
   - 若是音频：已在 API 层完成 ASR；这里统一取 `text`
   - 时区、日期语义规范化（“明天”“下周一”）
2. **ClassifyIntent**
   - LLM 分类：create/edit/query/plan/batch_update/delete/complete/stats…
3. **ExtractEntities**
   - LLM 抽取结构化字段（输出严格 schema）
4. **RiskAssess**
   - 规则 + LLM 结合：
     - 删除/批量修改/覆盖排程/影响 > N 条 → high
     - 单条创建草稿 → low
     - 规划一周并直建 → medium（若会覆盖已有 block 则升 high）
5. **PlanActions**
   - 将 intent + entities 转为具体工具调用序列（proposed_actions）
6. **ApprovalGate (conditional)**
   - 若 `risk_level == high`：创建 approval 记录并 **中断**（LangGraph 的 interrupt/pause），等待用户批准
7. **ExecuteTools**
   - 调用领域工具（查询任务、创建草稿、创建任务、批量变更…）
8. **ComposeResponse**
   - 生成 `AgentResponse`：
     - 简单创建/编辑 → `open_editor + task_draft`
     - 复杂规划直建 → `created_items`
     - 查询 → `query_result`
     - 风险审批 → `approval_required`

### 5.3 “简单创建/编辑”必须走草稿（Draft）策略

判定为简单创建/编辑时，工具层**只允许**：

- `create_task_draft(draft)`：生成草稿（不写任务表）
- `suggest_tags()` / `resolve_time()`：辅助填充

并且在 `ComposeResponse` 中必须返回 `type: "open_editor"`，禁止返回任何“已创建成功”的话术，避免用户误以为已落库。

### 5.4 “复杂规划”允许直建的边界

当满足以下条件之一，进入复杂规划（允许直建）路径：

- 用户明确表达“规划/安排未来 X 天/一周/一月”“生成计划”“帮我排时间”
- 生成任务数量 \( \ge 3 \) 或跨度 \( \ge 2 \) 天
- 需要进行冲突检查与时间槽分配（例如把学习/运动塞进空闲时间）

复杂规划直建仍需遵守：

- **不覆盖**用户已有的 `block` 时间段（除非用户明确“覆盖/调整既有安排”，此时提升为 high risk 走审批）
- 对每个新建任务写入 `created_by = "agent"` 与 `agent_run_id`，以便前端展示清单与撤销

---

## 六、工具层（Tools）设计（供 LangGraph 调用）

建议采用“工具白名单”模式：LangGraph 只能调用明确注册的工具函数；不同风险等级对应不同工具集合。

### 6.1 领域工具清单

#### 查询类（低风险）

- `search_tasks(query, filters, limit)`
- `get_task(task_id)`
- `list_tasks_in_range(start, end, filters)`
- `get_user_tags()`
- `get_stats(range, group_by)`
- `get_calendar_busy_slots(start, end)`：用于规划时找空闲时间

#### 草稿类（低风险，简单创建/编辑专用）

- `create_task_draft(draft)`：仅生成草稿 id（或直接回传草稿对象），不落库任务
- `validate_task_draft(draft)`：校验字段完整性（例如 block 必须有 start/end）
- `expand_todo_subtasks(text)`：从描述生成子任务列表（可选）

#### 创建/变更类（中风险以上，复杂规划/已审批路径）

- `create_task(task)`：真正落库
- `bulk_create_tasks(tasks[])`
- `update_task(task_id, patch)`
- `bulk_update_tasks(filter, patch)`
- `complete_task(task_id)`
- `cancel_task(task_id, reason)`

#### 危险操作（必须审批后才可调用）

- `delete_task(task_id)`
- `bulk_delete_tasks(filter)`
- `reschedule_tasks(task_ids, strategy)`：批量改时间
- `overwrite_plan(range, new_tasks)`：覆盖式排程（强危险）

### 6.2 工具输出的“可展示摘要”

所有会改变数据的工具必须返回可展示的摘要字段，以支持：

- 前端「创建清单卡」展示
- 审批弹窗展示变更
- 审计日志

推荐返回：

- `affected_count`
- `task_summaries[]`：`{id, title, type, start, end, ddl, tags}`
- `diff_summary`：简要描述（例如“3 条任务开始时间 +2h”）

---

## 七、审批（Approval）中断与恢复（LangGraph interrupt）

### 7.1 何时触发审批

满足任一条件则 `risk_level = high`：

- 删除任务（单条/批量）
- 批量修改 \( \ge 5 \) 条任务（阈值可配置）
- 覆盖式排程、清空某个时间段再重排
- 涉及过去数据回写或影响统计口径的操作
- 规划时需要移动/删除已有 `block` 才能塞入新任务

### 7.2 中断点行为

在 `ApprovalGate`：

- 创建 `ApprovalRequest` 记录（包含 proposed_actions 的摘要与 diff）
- 生成 `approval_id`
- LangGraph 返回 `type: "approval_required"` 并**暂停运行**

### 7.3 用户批准后的恢复

前端点击“批准执行”：

- 调用 `POST /agent/approvals/{approval_id}`
- 后端恢复对应 `agent_run_id`（继续从 `ApprovalGate` 后的 `ExecuteTools` 跑）
- 最终返回执行结果（created/updated/deleted 的摘要）

拒绝则终止本次 run，并返回 `type: "message"` 告知“已取消操作”，同时保留审批记录用于审计。

---

## 八、复杂规划：排程策略与冲突处理

### 8.1 目标

输入通常是：

- 目标集合：学习/运动/工作等若干事项
- 约束：时间范围（未来一周）、每天可用时长、偏好（早上/晚上）、不占用已存在 block
- 产出：一组新建任务（多为 block + todo/ddl 的组合）

### 8.2 推荐的两阶段规划（更可控）

1. **Planning（规划阶段，LLM）**
   - 产出“候选任务列表”与“软约束说明”
   - 不直接填具体时间，先给出每天需要多少块、每块时长
2. **Scheduling（排程阶段，规则/算法）**
   - 使用 `get_calendar_busy_slots` 得到忙碌时间
   - 将候选 block 按优先级填入空闲时间槽（first-fit / best-fit）
   - 冲突处理：
     - 若无足够空闲：降低块时长、减少频次，或退回让用户选择（此属于“需要澄清”，但为了不打断体验，可先给出可行的最小计划 + 解释）

> 关键点：让 LLM 做“内容与意图”，让规则做“时间可行性”，这样更稳定、可预测。

### 8.3 规划直建后的可视化与撤销

为了满足“复杂规划可直建但要可查看”的要求：

- 为本次 run 写入 `agent_run_id`
- 前端展示 `AgentCreatedItemsPanel`，按天分组展示
- 提供撤销：
  - 单项撤销：`cancel_task` 或软删除（建议）
  - 全部撤销：批量撤销（属于危险操作，建议二次确认/审批）

---

## 九、数据模型与存储（建议新增表）

### 9.1 Agent 会话与消息

- `agent_session`
  - `id, user_id, created_at, updated_at, title`
- `agent_message`
  - `id, session_id, role(user/assistant/system), content_text, content_json, created_at`
  - `content_json` 用于保存结构化卡片（草稿、清单、审批摘要）

### 9.2 Agent 运行与审计

- `agent_run`
  - `id, session_id, user_id, status(running/paused/completed/failed), started_at, ended_at`
  - `graph_state_json`：LangGraph state 快照（或外部 checkpoint 存储的引用）
- `agent_action_log`
  - `id, run_id, tool_name, tool_input_json, tool_output_json, created_at`

### 9.3 审批

- `approval_request`
  - `id, run_id, user_id, status(pending/approved/rejected/expired)`
  - `summary_json`（diff、影响范围、示例）
  - `created_at, decided_at, expire_at`

### 9.4 任务表字段（建议扩展）

在现有任务表（或统一的 Task 表）上增加：

- `created_by`：`user | agent`
- `agent_run_id`（nullable）
- `source_message_id`（nullable，用于溯源）

---

## 十、安全、权限与防误操作

### 10.1 权限边界

- Agent 工具层必须复用你现有的认证体系（token/session）
- 所有工具调用必须带 `user_id`，并确保只操作该用户数据
- 对“分享/协作”（如果未来加入）要做更细粒度授权；第一期可先不支持跨用户操作

### 10.2 Prompt 注入与数据泄漏防护（最低限度可落地）

- 工具调用只允许结构化参数（schema 校验），禁止 LLM 直接拼接 SQL/ORM 条件
- 对 LLM 输出做严格校验：
  - 时间字段必须可解析且在允许范围
  - 标签必须来自用户标签集合（不认识的可建议新增，但新增标签是否危险由产品决定）
- 日志中避免写入敏感信息（例如用户的原始语音文件可只存引用并设置生命周期）

### 10.3 限流与成本控制

- 每用户每分钟消息数限制（例如 30/min）
- 对复杂规划：限制最大生成任务数（例如 50）
- 对会话历史：做摘要（summary）以降低 token 消耗

---

## 十一、可观测性与故障体验

- 对每次 `agent_run` 记录：
  - 关键节点耗时（ASR、LLM、工具调用）
  - 成功/失败原因与错误码
- 前端：
  - 失败提示使用统一弹窗（可复用 `showAppErrorDialog`）
  - 对“暂停等待审批”的状态在对话流中清晰展示

---

## 十二、落地实施顺序（建议）

1. **后端最小闭环**：会话/消息 API + LangGraph（query + 草稿 open_editor）
2. **前端对话页**：文本输入 + DraftCard → 打开 TaskEditorPage 预填
3. **语音输入**：录音上传 + ASR
4. **复杂规划**：get busy slots + bulk_create + CreatedListCard
5. **审批**：ApprovalGate interrupt + ApprovalSheet + 恢复执行
6. **增强**：统计、撤销、摘要、限流与审计完善

