# ChronoCalendar

一款面向个人的智能日程管理应用，支持任务管理、番茄钟专注统计与 AI 自然语言助手等功能。

---

## 目录

- [项目简介](#项目简介)
- [功能特性](#功能特性)
- [技术栈](#技术栈)
- [项目结构](#项目结构)
- [快速开始](#快速开始)
- [API 说明](#api-说明)
- [AI Agent](#ai-agent)
- [数据库设计](#数据库设计)

---

## 项目简介

ChronoCalendar 是一个前后端分离的移动端日程管理应用，前端使用 **Flutter** 构建客户端（Android），后端使用 **Django REST Framework** 提供 API 服务，并集成基于 **LangGraph** 的 AI Agent，支持用户通过自然语言创建、查询、规划任务。

---

## 功能特性

### 三类任务

| 类型 | 说明 |
|------|------|
| `block` | 固定时间段任务（有 `start_at / end_at`） |
| `ddl` | 截止时间任务（有 `due_at`） |
| `todo` | 待办清单（可含子任务、预期时长，可选截止时间） |

三类任务均支持：自定义标签、番茄钟专注、完成/取消/延期/稍后等状态流转。

### 主要页面

- **主页（最近任务）**：展示今明两天任务、本周统计（完成数/标签分布）、全部 Todo 列表
- **任务列表**：按类型筛选、按标签/时间排序，支持搜索
- **日历**：日 / 周 / 月三种视图，平滑切换动画
- **设置**：账号管理、自定义标签（颜色 + 名称）
- **番茄钟**：锁屏计时，白噪音 BGM，杀后台自动结束
- **任务详情/编辑**：所有属性编辑，AI 快捷输入入口
- **AI 对话**：自然语言创建、查询、规划、危险操作审批

### 提醒机制

提醒时间存于服务端，**实际闹铃由 Android 客户端本地调度**（`AlarmManager` + 系统通知），App 在前台时展示半屏弹窗，后台时发本地推送通知。

---

## 技术栈

### 后端

| 技术 | 版本 / 说明 |
|------|------------|
| Python | 3.x |
| Django | ≥ 4.2, < 5.0 |
| Django REST Framework | ≥ 3.15 |
| SimpleJWT | ≥ 5.3，Bearer Token 认证 |
| django-cors-headers | 跨域支持 |
| LangGraph | ≥ 0.2，AI Agent 工作流引擎 |
| OpenAI SDK | ≥ 1.0，LLM 调用 |
| 数据库 | 开发环境 SQLite，生产推荐 PostgreSQL |

### 前端

| 技术 | 版本 / 说明 |
|------|------------|
| Flutter / Dart | SDK ^3.11.4 |
| go_router | ≥ 14.6，路由管理 |
| flutter_riverpod | ≥ 2.6，状态管理 |
| http | HTTP 请求 |
| audioplayers | 番茄钟白噪音播放 |
| flutter_local_notifications | 本地通知 |
| wakelock_plus | 番茄钟锁屏保活 |
| google_fonts | 字体 |
| intl | 国际化 / 时间格式化 |
| timezone | 时区处理 |

---

## 项目结构

```
ChronoCalendar/
├── backend/                  # Django 后端
│   ├── config/               # 项目配置（settings, urls, wsgi）
│   ├── accounts/             # 账号相关视图与路由
│   ├── tasks/                # 任务、标签、子任务、番茄钟模型与 API
│   │   ├── models.py         # User / Tag / Task / TaskBlock / TaskDDL / TaskTodo / SubTask / FocusSession
│   │   ├── views.py
│   │   ├── serializers.py
│   │   └── urls.py
│   ├── agent/                # AI Agent 模块
│   │   ├── graph.py          # LangGraph 工作流（意图决策 → 工具调用 → 响应）
│   │   ├── llm.py            # LLM 调用封装
│   │   ├── tools.py          # 工具实现（搜索、草稿、规划、删除审批等）
│   │   ├── registry.py       # Skill 注册与描述生成
│   │   ├── models.py         # AgentSession / AgentMessage / ApprovalRequest
│   │   ├── views.py          # Agent API 视图
│   │   └── urls.py
│   ├── manage.py
│   ├── requirements.txt
│   └── db.sqlite3            # 开发数据库（git 忽略）
│
├── frontend/                 # Flutter 前端
│   ├── lib/
│   │   ├── main.dart         # 应用入口
│   │   ├── app.dart          # 路由与主题配置
│   │   ├── core/             # 网络请求、常量、工具函数
│   │   ├── data/             # 数据层（Repository、数据源）
│   │   ├── domain/           # 领域模型与接口
│   │   ├── features/         # 按功能拆分的 UI 模块
│   │   │   ├── auth/         # 登录/注册
│   │   │   ├── home/         # 主页（最近任务 + 统计）
│   │   │   ├── task_list/    # 任务列表
│   │   │   ├── task_create/  # 新建任务
│   │   │   ├── task_detail/  # 任务详情/编辑
│   │   │   ├── calendar/     # 日历（日/周/月）
│   │   │   ├── pomodoro/     # 番茄钟
│   │   │   ├── agent_chat/   # AI 对话
│   │   │   ├── settings/     # 设置
│   │   │   └── shell/        # 底部导航壳
│   │   └── shared/           # 公共组件
│   ├── assets/audio/         # 白噪音音频资源
│   └── pubspec.yaml
│
├── design.md                 # 功能设计文档
├── visual-design.md          # 视觉设计规范
├── api.md                    # API 详细文档
├── db.md                     # 数据库设计文档
└── agent-design.md           # AI Agent 技术方案
```

---

## 快速开始

### 后端

**依赖环境**：Python 3.10+

```bash
cd backend

# 安装依赖
pip install -r requirements.txt

# 数据库迁移
python manage.py migrate

# 启动开发服务器（默认 http://localhost:8000）
python manage.py runserver
```

**LLM 配置**（可选，不配置时 Agent 功能降级）：

在 `backend/config/settings.py` 中修改以下字段：

```python
AGENT_LLM_BASE_URL = "https://your-llm-api-base/v1"
AGENT_LLM_API_KEY  = "your-api-key"
AGENT_LLM_MODEL    = "gpt-4o"   # 或其他兼容 OpenAI 接口的模型
```

> 生产部署时务必将 `SECRET_KEY` 替换为随机值，将 `DEBUG` 设为 `False`，并将数据库切换为 PostgreSQL。

### 前端

**依赖环境**：Flutter SDK ^3.11.4

```bash
cd frontend

# 获取依赖
flutter pub get

# 运行（Android 设备 / 模拟器）
flutter run
```

前端默认请求 `http://localhost:8000/api/v1`，如需修改后端地址，请更新 `lib/core/` 中的网络配置常量。

---

## API 说明

Base URL：`http://localhost:8000/api/v1`  
认证方式：`Authorization: Bearer <access_token>`

### 主要端点

| 功能 | Method | URL |
|------|--------|-----|
| 注册 | `POST` | `/auth/register/` |
| 登录 | `POST` | `/auth/login/` |
| 刷新 Token | `POST` | `/auth/refresh/` |
| 登出 | `POST` | `/auth/logout/` |
| 创建任务 | `POST` | `/tasks/` |
| 查询任务列表 | `GET` | `/tasks/?type=block&status=active` |
| 查询单个任务 | `GET` | `/tasks/{id}/` |
| 更新任务 | `PATCH` | `/tasks/{id}/` |
| 删除任务 | `DELETE` | `/tasks/{id}/` |
| 标记完成 | `POST` | `/tasks/{id}/complete/` |
| 取消任务 | `POST` | `/tasks/{id}/cancel/` |
| 稍后完成 | `POST` | `/tasks/{id}/snooze/` |
| 任务延期 | `POST` | `/tasks/{id}/postpone/` |
| 新增子任务 | `POST` | `/tasks/{id}/subtasks/` |
| 更新子任务 | `PATCH` | `/subtasks/{id}/` |
| 导出全部数据 | `GET` | `/tasks/export/` |
| 导入数据 | `POST` | `/tasks/import/?mode=merge\|duplicate` |

> 完整字段说明与响应示例见 [api.md](api.md)

---

## AI Agent

Agent 基于 **LangGraph** 工作流引擎，通过 LLM 进行意图识别与工具调用。

### 交互模式

| 意图类型 | 处理方式 |
|----------|----------|
| 简单创建/编辑（单个任务） | 生成任务草稿 → 前端弹出预填编辑页 → 用户确认后保存 |
| 复杂规划（跨多天/多任务） | 直接创建任务，前端展示"本次创建清单"，支持撤销 |
| 危险操作（删除/批量改动） | 生成审批请求 → 前端展示审批卡 → 用户批准后执行 |
| 查询/统计 | 直接返回结构化查询结果卡片 |
| 闲聊 | 自然语言回复 |

### Agent API 端点

| 功能 | Method | URL |
|------|--------|-----|
| 创建会话 | `POST` | `/agent/sessions/` |
| 发送消息 | `POST` | `/agent/sessions/{id}/messages/` |
| 获取历史消息 | `GET` | `/agent/sessions/{id}/messages/` |
| 审批操作 | `POST` | `/agent/approvals/{id}/approve/` |
| 拒绝操作 | `POST` | `/agent/approvals/{id}/reject/` |

### 可用 Agent 工具（Skill）

- `search_tasks`：按关键词/类型搜索任务
- `build_task_draft`：生成任务草稿（用于打开编辑页）
- `get_calendar_overview`：查询日历日程概览
- `generate_long_term_plan`：生成并创建长期规划任务
- `delete_task`：创建删除审批请求（不直接删除）
- `check_conflict`：检测时间冲突

---

## 数据库设计

核心表结构（以 PostgreSQL 语义描述，开发环境使用 SQLite）：

| 表名 | 说明 |
|------|------|
| `users` | 用户表，UUID 主键，email 登录 |
| `tags` | 用户自定义标签（名称 + 颜色） |
| `tasks` | 统一任务母表（type 区分三类） |
| `task_block` | block 任务扩展（start_at / end_at） |
| `task_ddl` | ddl 任务扩展（due_at） |
| `task_todo` | todo 任务扩展（expected_minutes / due_at） |
| `task_tags` | 任务-标签多对多关联 |
| `subtasks` | Todo 子任务 |
| `focus_sessions` | 番茄钟专注记录 |

> 详细字段定义、索引设计见 [db.md](db.md)
