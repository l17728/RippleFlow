# RippleFlow nullclaw 对接配置

## 概述

| 项目 | 值 |
|------|------|
| 创建日期 | 2026-03-03 |
| 更新日期 | 2026-03-03 |
| 目标 | 将 RippleFlow 与 nullclaw 框架对接 |
| nullclaw 版本 | 2026.3.x |
| 架构版本 | v2.0（策略由 nullclaw 提供） |

### 核心设计理念

**策略与机制分离**：
- **RippleFlow 平台**：只暴露能力（API + CLI），不包含任何策略逻辑
- **nullclaw**：负责所有智能逻辑（Routine 脚本、LLM 决策、自省学习）

```
┌─────────────────────────────────────────────────────────────────┐
│                    架构关系图                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │               RippleFlow 平台（机制）                    │   │
│  │                                                         │   │
│  │  能力暴露：                                              │   │
│  │  ├── REST API（HTTP 接口）                              │   │
│  │  └── CLI 命令（Shell 接口）                              │   │
│  │                                                         │   │
│  │  数据库：SQLite / PostgreSQL                            │   │
│  │  缓存：内存缓存 / Redis                                  │   │
│  │                                                         │   │
│  │  不包含：                                                │   │
│  │  ❌ 规则引擎                                             │   │
│  │  ❌ Routine 脚本                                         │   │
│  │  ❌ 策略决策逻辑                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              ↑                                  │
│                              │ rf help / rf <command>           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   nullclaw                               │   │
│  │                                                         │   │
│  │  智能逻辑：                                              │   │
│  │  ├── Routine 脚本（固化逻辑）                           │   │
│  │  ├── LLM 智能层（灵活决策）                             │   │
│  │  ├── 自省学习（持续优化）                               │   │
│  │  └── 定时任务（周期调度）                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 一、nullclaw 原生能力与自研替代分析

### 1.1 核心原则：优先使用 nullclaw 原生能力

```
┌─────────────────────────────────────────────────────────────────┐
│                nullclaw 原生能力 vs 自研对比                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ❌ 不再自研（使用 nullclaw 原生）    ✅ 需要开发（RippleFlow）  │
│  ────────────────────────────────    ─────────────────────────  │
│                                                                 │
│  • 事件总线 → channels/webhook      • 数据存储（SQLite/PG）     │
│  • 触发机制 → channels + cron        • 全文索引（FTS5）         │
│  • 记忆系统 → memory 三层架构        • 业务 API（CRUD）         │
│  • 工具调用 → tools 模块             • CLI 命令（rf）           │
│  • 配对验证 → security.pairing       • Webhook 接收端           │
│  • 审计日志 → security.audit         • 消息处理流水线           │
│  • 自主控制 → autonomy 模块          • 知识图谱构建             │
│  • 定时任务 → cron 模块              • LLM Prompt 模板         │
│  • 成本控制 → autonomy.cost_control  • 前端 Dashboard          │
│  • 多代理 → agents 模块              • 多平台适配器            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                架构价值                                  │   │
│  │                                                         │   │
│  │  使用 nullclaw 原生能力：                                │   │
│  │  • 减少约 40% 的开发工作量                               │   │
│  │  • 避免"重复造轮子"导致的维护负担                        │   │
│  │  • 自动获得 nullclaw 的功能更新                          │   │
│  │  • 专注于 RippleFlow 核心业务价值                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Channels（事件通道）- 替代"事件总线"

**原设计**：在 `08_ai_butler_architecture.md` 中设计了"事件总线 (Event Bus)"
**新方案**：使用 nullclaw channels 原生能力

```
┌─────────────────────────────────────────────────────────────────┐
│                    nullclaw Channels 架构                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  RippleFlow 平台                nullclaw Agent                  │
│  ─────────────                  ─────────────                   │
│                                                                 │
│  消息入库完成 ──────────────────→ channel: message.received     │
│  话题创建完成 ──────────────────→ channel: thread.created       │
│  待办状态变更 ──────────────────→ channel: todo.status_changed  │
│  敏感内容检测 ──────────────────→ channel: sensitive.detected   │
│  问答请求 ──────────────────────→ channel: user.query           │
│                                                                 │
│  nullclaw 自动：                                                │
│  • 接收 channel 事件                                            │
│  • 根据 Routine 脚本判断是否需要行动                            │
│  • 执行相应的 CLI 命令                                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**事件推送方式**：

RippleFlow 平台在业务操作完成后，通过 HTTP POST 推送事件到 nullclaw gateway：

```bash
# RippleFlow 平台代码示例
async def notify_nullclaw(event_type: str, payload: dict):
    await http_post(
        url="${NULLCLAW_GATEWAY_URL}/webhook/rippleflow",
        json={
            "event": event_type,
            "timestamp": datetime.utcnow().isoformat(),
            "payload": payload
        }
    )
```

**nullclaw 配置**：

```json
{
  "channels": {
    "enabled": ["dingtalk", "lark", "web", "rippleflow_events"],

    "rippleflow_events": {
      "type": "webhook",
      "webhook_path": "/webhook/rippleflow",
      "events": [
        "message.received",
        "thread.created",
        "thread.updated",
        "todo.created",
        "todo.completed",
        "sensitive.detected",
        "sensitive.authorized",
        "user.query",
        "user.feedback"
      ]
    }
  }
}
```

### 1.3 Memory（三层记忆系统）- 替代简单 MEMORY.md

**原设计**：仅有 MEMORY.md 文件
**新方案**：使用 nullclaw memory 三层架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    nullclaw Memory 三层架构                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  L1 活跃层 (.rippleflow/memory/)                                │
│  ─────────────────────────────                                  │
│  • 最近 7 天的对话和事件                                         │
│  • 自动加载到上下文                                             │
│  • 每日自动归档                                                 │
│                                                                 │
│  L2 归档层 (.rippleflow/archive/)                               │
│  ─────────────────────────────                                  │
│  • 压缩后的历史摘要                                             │
│  • LLM 自动生成摘要                                             │
│  • 保留原始内容（可追溯）                                        │
│                                                                 │
│  L3 核心层 (.rippleflow/MEMORY.md)                              │
│  ─────────────────────────────                                  │
│  • 永久保留的核心知识                                            │
│  • 人工审核后才会更新                                           │
│  • 最大 20000 字符                                              │
│                                                                 │
│  nullclaw 自动处理：                                            │
│  • compaction: 每日 2:00 自动压缩                               │
│  • hygiene: 每周日 3:00 清理过期内容                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**nullclaw 配置**：

```json
{
  "memory": {
    "backend": "markdown",
    "workspace_dir": ".rippleflow",
    "layers": {
      "L1_active": {
        "path": "memory/",
        "max_age_days": 7,
        "auto_archive": true
      },
      "L2_archive": {
        "path": "archive/",
        "max_age_days": 90,
        "keep_original": true
      },
      "L3_core": {
        "path": "MEMORY.md",
        "max_size": 20000,
        "require_review": true
      }
    },
    "lifecycle": {
      "compaction": {
        "enabled": true,
        "schedule": "0 2 * * *",
        "max_age_days": 30,
        "summary_model": "glm-4-plus",
        "min_messages_to_compress": 50
      },
      "hygiene": {
        "enabled": true,
        "schedule": "0 3 * * 0",
        "remove_duplicates": true,
        "archive_old_files": true
      }
    }
  }
}
```

### 1.4 Tools（工具模块）- 管家能力调用

**原设计**：未定义管家工具调用机制
**新方案**：使用 nullclaw tools 模块

```
┌─────────────────────────────────────────────────────────────────┐
│                    nullclaw Tools 工具集                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  shell_execute（命令执行）                                       │
│  ─────────────────────                                          │
│  • 执行 rf 命令与 RippleFlow 平台交互                            │
│  • 安全限制：只允许执行白名单命令                                 │
│  • 超时控制：防止命令卡死                                        │
│                                                                 │
│  http_request（HTTP 请求）                                       │
│  ─────────────────────                                          │
│  • 调用外部 API（如企业内部系统）                                 │
│  • 获取外部数据（如天气、日历等）                                 │
│  • 发送通知到其他系统                                            │
│                                                                 │
│  file_read / file_write（文件操作）                              │
│  ─────────────────────────────                                  │
│  • 读取/写入 .rippleflow/ 目录下的文件                           │
│  • 创建新的 Routine 脚本                                        │
│  • 更新 insights/ 自省沉淀                                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**nullclaw 配置**：

```json
{
  "tools": {
    "enabled": [
      "shell_execute",
      "http_request",
      "file_read",
      "file_write"
    ],

    "shell_execute": {
      "allowed_commands": ["rf"],
      "working_directory": "${RIPPLEFLOW_HOME}",
      "timeout": 30000,
      "max_output_size": 65536
    },

    "http_request": {
      "allowed_domains": ["*"],
      "timeout": 10000,
      "max_response_size": 1048576
    },

    "file_read": {
      "allowed_paths": [
        ".rippleflow/*",
        "/tmp/rippleflow/*"
      ]
    },

    "file_write": {
      "allowed_paths": [
        ".rippleflow/insights/*",
        ".rippleflow/prompts/ROUTINES/*",
        ".rippleflow/proposals/*"
      ],
      "max_file_size": 1048576
    }
  }
}
```

### 1.5 Security（安全模块）- 替代自研安全机制

**原设计**：有审计设计，无配对验证
**新方案**：使用 nullclaw security 完整安全能力

```
┌─────────────────────────────────────────────────────────────────┐
│                    nullclaw Security 安全机制                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Pairing（配对验证）                                             │
│  ─────────────────                                              │
│  • 新设备首次连接需要输入配对码                                   │
│  • 防止未授权设备接入                                            │
│  • 配对码 6 位，5 分钟有效                                       │
│                                                                 │
│  Audit（审计日志）                                               │
│  ─────────────────                                              │
│  • 记录所有敏感操作                                              │
│  • tool_call: 工具调用记录                                      │
│  • routine_create: Routine 创建记录                             │
│  • proposal_submit: 提案提交记录                                │
│  • reflection_audit: 自省操作审计                                │
│                                                                 │
│  Rate Limiting（频率限制）                                       │
│  ─────────────────                                              │
│  • 防止滥用                                                      │
│  • 可配置每分钟请求数                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**nullclaw 配置**：

```json
{
  "security": {
    "pairing": {
      "enabled": true,
      "code_length": 6,
      "expiry_seconds": 300,
      "max_attempts": 3
    },

    "audit": {
      "enabled": true,
      "log_path": ".rippleflow/logs/audit.log",
      "retention_days": 365,
      "events": [
        "tool_call",
        "routine_create",
        "routine_modify",
        "proposal_submit",
        "memory_modify",
        "cost_exceeded"
      ],
      "reflection_audit": {
        "enabled": true,
        "log_path": ".rippleflow/logs/reflection_audit.log",
        "retention_days": 365
      }
    },

    "rate_limit": {
      "enabled": true,
      "requests_per_minute": 60,
      "burst": 10
    }
  }
}
```

### 1.6 Autonomy（自主控制模块）- 新增能力

**原设计**：无自主控制机制
**新方案**：使用 nullclaw autonomy 模块

```
┌─────────────────────────────────────────────────────────────────┐
│                    nullclaw Autonomy 自主控制                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  自主等级（level: 0-3）                                          │
│  ─────────────────────                                          │
│  • Level 0: 完全被动，只响应明确请求                              │
│  • Level 1: 可执行低风险操作（L1 权限）                           │
│  • Level 2: 可执行中等风险操作（L2 权限）                         │
│  • Level 3: 可自主决策大部分操作                                  │
│                                                                 │
│  成本控制                                                        │
│  ────────                                                       │
│  • max_cost_per_day: 每日最大成本                                │
│  • max_tokens_per_request: 单次最大 token                       │
│  • alert_threshold: 超过阈值告警                                 │
│                                                                 │
│  确认要求                                                        │
│  ────────                                                       │
│  • 指定哪些操作需要人工确认                                       │
│  • sensitive_escalate: 敏感授权升级                              │
│  • routine_create_l2: 创建 L2 级 Routine                        │
│  • proposal_submit: 提交新命令提案                               │
│                                                                 │
│  自省策略                                                        │
│  ────────                                                       │
│  • auto_apply: 是否自动应用优化                                  │
│  • require_human_review: 是否需要人工审核                        │
│  • audit_all_changes: 是否审计所有变更                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**nullclaw 配置**：

```json
{
  "autonomy": {
    "level": 2,

    "cost_control": {
      "max_cost_per_day": 10.0,
      "max_tokens_per_request": 4096,
      "alert_threshold": 0.8,
      "currency": "CNY"
    },

    "require_confirmation": [
      "sensitive_escalate",
      "routine_create_l2",
      "proposal_submit",
      "memory_modify_l3"
    ],

    "reflection_policy": {
      "auto_apply_l1": true,
      "auto_apply_l2": false,
      "require_human_review": true,
      "audit_all_changes": true,
      "max_auto_changes_per_day": 5
    }
  }
}
```

### 1.7 Cron（定时任务模块）- 替代 Celery Beat

**原设计**：使用 Celery Beat + Redis 实现定时任务
**新方案**：使用 nullclaw cron 原生能力

```
┌─────────────────────────────────────────────────────────────────┐
│                    nullclaw Cron 定时任务                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  nullclaw 原生支持：                                             │
│  • 标准 cron 表达式                                              │
│  • 时区支持                                                      │
│  • 任务依赖                                                      │
│  • 失败重试                                                      │
│                                                                 │
│  RippleFlow 不需要：                                             │
│  ❌ Celery Beat 配置                                            │
│  ❌ Celery Worker 进程                                          │
│  ❌ Redis 作为消息队列（可选用于缓存）                            │
│  ❌ 定时任务调度代码                                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 1.8 Agents（多代理模块）- 新增能力

**原设计**：单一 AI 管家
**新方案**：支持多 Agent 协作

```
┌─────────────────────────────────────────────────────────────────┐
│                    nullclaw 多 Agent 架构                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  rippleflow_butler（主管家）                                     │
│  ───────────────────────                                        │
│  • 职责：总控、协调、决策                                        │
│  • 模型：glm-4-plus                                             │
│                                                                 │
│  rippleflow_qa（问答专家）                                       │
│  ───────────────────────                                        │
│  • 职责：问答、搜索、知识检索                                     │
│  • 模型：glm-4-plus                                             │
│  • 专注领域：qa_faq, reference_data                             │
│                                                                 │
│  rippleflow_analyst（分析专家）                                  │
│  ───────────────────────                                        │
│  • 职责：统计、报告、趋势分析                                     │
│  • 模型：glm-4-plus                                             │
│  • 专注领域：contribution, collaboration                        │
│                                                                 │
│  rippleflow_coordinator（协调专家）                              │
│  ───────────────────────                                        │
│  • 职责：任务分配、进度跟踪                                       │
│  • 模型：glm-4                                                  │
│  • 专注领域：action_item, todos                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**nullclaw 配置**：

```json
{
  "agents": {
    "rippleflow_butler": {
      "provider": "zhipu",
      "model": "glm-4-plus",
      "system_prompt_file": "prompts/IDENTITY.md",
      "max_history_messages": 100,
      "max_tool_iterations": 50,
      "temperature": 0.7,
      "workspace_dir": ".rippleflow",
      "shell": {
        "enabled": true,
        "allowed_commands": ["rf"],
        "working_directory": "${RIPPLEFLOW_HOME}"
      }
    },

    "rippleflow_qa": {
      "provider": "zhipu",
      "model": "glm-4-plus",
      "system_prompt_file": "prompts/QA_EXPERT.md",
      "max_history_messages": 50,
      "temperature": 0.3,
      "specialization": ["qa_faq", "reference_data", "tech_decision"]
    },

    "rippleflow_analyst": {
      "provider": "zhipu",
      "model": "glm-4-plus",
      "system_prompt_file": "prompts/ANALYST.md",
      "max_history_messages": 30,
      "temperature": 0.5,
      "specialization": ["contribution", "collaboration", "stats"]
    },

    "rippleflow_coordinator": {
      "provider": "zhipu",
      "model": "glm-4",
      "system_prompt_file": "prompts/COORDINATOR.md",
      "max_history_messages": 50,
      "temperature": 0.4,
      "specialization": ["action_item", "todos", "reminder"]
    }
  }
}
```

### 1.9 需要重构的原设计清单

| 文件 | 原设计 | 重构方案 |
|------|--------|----------|
| `08_ai_butler_architecture.md` | 事件总线 (Event Bus) | 删除，使用 nullclaw channels |
| `08_ai_butler_architecture.md` | 感知模块事件监听 | 简化，事件由 nullclaw 接收 |
| `08_ai_butler_architecture.md` | 触发框架 triggers.md | 保留，作为 Routine 脚本的触发条件 |
| `01_system_architecture.md` | Celery Beat 定时任务 | 删除，使用 nullclaw cron |
| `01_system_architecture.md` | Redis 作为消息队列 | 可选，仅用于缓存 |
| `04_service_interfaces.md` | ButlerScheduler 接口 | 删除，由 nullclaw 调度 |
| 新增 | - | RippleFlow 事件推送接口 |

---

## 二、整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    RippleFlow on nullclaw                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Workspace 目录                         │   │
│  │                                                          │   │
│  │  .rippleflow/                                            │   │
│  │  ├── config.json           ← nullclaw 配置              │   │
│  │  │                                                      │   │
│  │  ├── MEMORY.md             ← L3 核心层（知识图谱）       │   │
│  │  │                                                      │   │
│  │  ├── memory/               ← L1 活跃层                   │   │
│  │  │   └── 2026-03-03.md     ← 今日话题                   │   │
│  │  │                                                      │   │
│  │  ├── archive/              ← L2 归档层                   │   │
│  │  │   ├── summaries/        ← 摘要                        │   │
│  │  │   └── originals/        ← 压缩原文                    │   │
│  │  │                                                      │   │
│  │  ├── prompts/              ← 提示词分级                  │   │
│  │  │   ├── IDENTITY.md       ← 核心身份                   │   │
│  │  │   ├── ROUTINES/         ← Routine 脚本               │   │
│  │  │   └── SKILLS.md         ← 技能模板                   │   │
│  │  │                                                      │   │
│  │  └── insights/             ← 自省沉淀                    │   │
│  │      ├── daily/            ← 每日自省                    │   │
│  │      └── weekly/           ← 每周复盘                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    nullclaw 核心                          │   │
│  │                                                          │   │
│  │  工作流程：                                              │   │
│  │  1. rf help                    → 查询可用命令            │   │
│  │  2. rf <command> --help        → 查询命令详情            │   │
│  │  3. rf <command> [args]        → 执行操作                │   │
│  │                                                          │   │
│  │  Channels:           Cron:              Tools:            │   │
│  │  - dingtalk          - daily_digest     - shell_execute   │   │
│  │  - lark              - weekly_review    - http_request    │   │
│  │  - web               - todo_reminder    - file_*          │   │
│  │                      - butler_reflect                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 二、CLI 命令调用方式

### 2.1 nullclaw 调用流程

```
┌─────────────────────────────────────────────────────────────────┐
│                    nullclaw 调用 RippleFlow                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Step 1: 发现能力                                              │
│  ─────────────────                                             │
│  $ rf help                                                     │
│                                                                 │
│  输出：                                                         │
│  命令:                                                          │
│    auth          认证与会话                                     │
│    threads       话题线索管理                                   │
│    search        全文搜索                                       │
│    qa            智能问答                                       │
│    todos         个人待办管理                                   │
│    actions       群聊任务管理                                   │
│    sensitive     敏感授权处理                                   │
│    ...                                                          │
│                                                                 │
│  Step 2: 查询详情                                              │
│  ─────────────────                                             │
│  $ rf threads search --help                                     │
│                                                                 │
│  输出：                                                         │
│  用法: rf threads search <query> [options]                      │
│  选项:                                                          │
│    --category <cat>    限定类别                                │
│    --domain <domain>   限定四大类                              │
│    --size <n>          结果数量                                │
│                                                                 │
│  Step 3: 执行命令                                              │
│  ─────────────────                                             │
│  $ rf threads search "Redis配置" --category qa_faq -o json      │
│                                                                 │
│  输出：                                                         │
│  {                                                              │
│    "results": [...],                                            │
│    "total": 5                                                   │
│  }                                                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 核心 CLI 命令速查

| 命令 | 说明 | 示例 |
|------|------|------|
| `rf help` | 查询所有命令 | `rf help` |
| `rf <cmd> --help` | 查询命令详情 | `rf threads --help` |
| `rf threads list` | 列出话题 | `rf threads list --category qa_faq` |
| `rf threads search` | 搜索话题 | `rf threads search "Redis"` |
| `rf qa` | 智能问答 | `rf qa "如何配置连接池"` |
| `rf todos list` | 列出待办 | `rf todos list --overdue` |
| `rf todos add` | 创建待办 | `rf todos add "完成文档" --due 2026-03-10` |
| `rf sensitive pending` | 待授权列表 | `rf sensitive pending` |
| `rf sensitive decide` | 提交决策 | `rf sensitive decide <id> --decision approve` |
| `rf butler digest` | 生成快报 | `rf butler digest --room <id> --type daily` |

### 2.3 nullclaw Shell Tool 配置

```json
{
  "tools": {
    "enabled": ["shell_execute", "http_request", "file_read", "file_write"],

    "shell_execute": {
      "allowed_commands": ["rf"],
      "working_directory": "/path/to/rippleflow",
      "timeout": 30000,
      "max_output_size": 65536
    }
  }
}
```

---

## 三、config.json 配置

```json
{
  "$schema": "https://nullclaw.ai/schema/config.json",
  "version": "2026.3.2",

  "models": {
    "default_provider": "zhipu",
    "providers": {
      "zhipu": {
        "api_key": "${ZHIPU_API_KEY}",
        "model": "glm-4-plus",
        "base_url": "https://open.bigmodel.cn/api/paas/v4"
      },
      "fallback": {
        "provider": "zhipu",
        "model": "glm-4"
      }
    }
  },

  "agents": {
    "rippleflow_butler": {
      "provider": "zhipu",
      "model": "glm-4-plus",
      "system_prompt_file": "prompts/IDENTITY.md",
      "max_history_messages": 100,
      "max_tool_iterations": 50,
      "temperature": 0.7,
      "workspace_dir": ".rippleflow",

      "shell": {
        "enabled": true,
        "allowed_commands": ["rf"],
        "working_directory": "${RIPPLEFLOW_HOME}"
      }
    }
  },

  "memory": {
    "backend": "markdown",
    "workspace_dir": ".rippleflow",
    "lifecycle": {
      "compaction": {
        "enabled": true,
        "schedule": "0 2 * * *",
        "max_age_days": 30,
        "summary_model": "glm-4-plus"
      },
      "hygiene": {
        "enabled": true,
        "schedule": "0 3 * * 0"
      }
    }
  },

  "channels": {
    "enabled": ["dingtalk", "lark", "web"],

    "dingtalk": {
      "app_key": "${DINGTALK_APP_KEY}",
      "app_secret": "${DINGTALK_APP_SECRET}",
      "webhook_url": "${DINGTALK_WEBHOOK}"
    },

    "lark": {
      "app_id": "${LARK_APP_ID}",
      "app_secret": "${LARK_APP_SECRET}",
      "webhook_url": "${LARK_WEBHOOK}"
    },

    "web": {
      "port": 8080,
      "host": "0.0.0.0",
      "webhook_path": "/webhook/message"
    }
  },

  "tools": {
    "enabled": [
      "shell_execute",
      "http_request",
      "file_read",
      "file_write"
    ],

    "shell_execute": {
      "allowed_commands": ["rf"],
      "timeout": 30000
    }
  },

  "cron": {
    "enabled": true,
    "jobs": [
      {
        "name": "daily_digest",
        "schedule": "0 9 * * 1-5",
        "prompt": "生成每日快报并发送到群",
        "agent": "rippleflow_butler"
      },
      {
        "name": "weekly_review",
        "schedule": "0 9 * * 1",
        "prompt": "生成每周周报并发送到群",
        "agent": "rippleflow_butler"
      },
      {
        "name": "todo_reminder",
        "schedule": "0 9 * * 1-5",
        "prompt": "检查今日到期的待办，提醒相关人员",
        "agent": "rippleflow_butler"
      },
      {
        "name": "sensitive_check",
        "schedule": "0 10 * * *",
        "prompt": "检查是否有超过7天未处理的敏感授权，执行升级流程",
        "agent": "rippleflow_butler"
      },
      {
        "name": "daily_reflection",
        "schedule": "0 23 * * *",
        "prompt": "回顾今日处理的消息，识别遗漏或错误，记录改进点",
        "agent": "rippleflow_butler"
      },
      {
        "name": "monthly_evolution",
        "schedule": "0 9 1 * *",
        "prompt": "分析本月运营数据，提出系统优化建议",
        "agent": "rippleflow_butler"
      }
    ]
  },

  "security": {
    "pairing": {
      "enabled": true,
      "code_length": 6,
      "expiry_seconds": 300
    },
    "audit": {
      "enabled": true,
      "log_path": ".rippleflow/logs/audit.log",
      "reflection_audit": {
        "enabled": true,
        "log_path": ".rippleflow/logs/reflection_audit.log",
        "retention_days": 365
      }
    }
  },

  "autonomy": {
    "level": 2,
    "max_cost_per_day": 10.0,
    "require_confirmation": ["sensitive_escalate", "butler_evolve"],
    "reflection_policy": {
      "auto_apply": false,
      "require_human_review": true,
      "audit_all_changes": true
    }
  },

  "gateway": {
    "enabled": true,
    "port": 3000,
    "host": "0.0.0.0",
    "pairing_enabled": true
  }
}
```

---

## 四、完整 Routine 脚本清单

### 4.1 定时任务一览

| Routine | 调度时间 | 说明 | 权限等级 |
|---------|----------|------|----------|
| `daily_digest` | 每天 9:00（工作日） | 每日快报 | L2 |
| `weekly_review` | 每周一 9:00 | 每周周报 | L2 |
| `todo_reminder` | 每天 9:00（工作日） | 待办提醒 | L1 |
| `sensitive_escalation` | 每天 10:00 | 敏感授权升级 | L2 |
| `daily_reflection` | 每天 23:00 | 每日自省 | L3 |
| `weekly_retrospect` | 每周日 22:00 | 每周复盘 | L3 |
| `monthly_evaluation` | 每月1日 9:00 | 月度平台评估 | L3 |
| `overdue_check` | 每天 18:00 | 过期任务检查 | L1 |
| `qa_satisfaction` | 每天 17:00 | 问答满意度检查 | L1 |
| `knowledge_health` | 每周六 3:00 | 知识库健康检查 | L1 |

---

### 4.2 每日快报 Routine

```markdown
# routine_daily_digest.md

## 元信息
- id: routine_daily_digest
- name: 每日快报
- schedule: "0 9 * * 1-5"
- permission: L2
- enabled: true

## 触发条件
- 定时任务：每个工作日 9:00
- 可手动触发：rf butler digest --type daily

## 执行步骤

1. **获取昨日数据**
   ```bash
   rf threads list --from yesterday --size 20 -o json
   rf todos list --created-today --status open -o json
   rf qa stats --yesterday -o json
   ```

2. **生成快报内容**（LLM 处理）
   - 热门话题（按消息数排序）
   - 新增待办
   - 问答精选
   - 今日到期任务提醒

3. **推送到群**
   ```bash
   rf butler digest --room <room_id> --type daily
   ```

## 输出格式

```markdown
## 每日快报 (2026-03-03)

### 🔥 热门话题
1. **Redis 连接池配置方案** (技术讨论群, 12条)
   - 分类：问题解答
   - 关键结论：推荐使用 lettuce，配置参数...

2. **Docker 网络问题排查** (运维群, 8条)
   - 分类：故障案例
   - 解决方案：检查网络驱动...

### ✅ 新增待办
| 任务 | 负责人 | 截止日期 |
|------|--------|----------|
| 完成部署文档 | 张三 | 03-10 |
| 准备测试环境 | 李四 | 03-08 |

### 💬 问答精选
Q: Redis 连接池怎么配置？
A: 推荐使用 lettuce 连接池，主要参数...

### ⏰ 今日到期
- 完成代码审查 (张三)
```

## 错误处理
- 无数据时：跳过推送，记录日志
- 推送失败：重试 3 次，间隔 5 分钟
```

---

### 4.3 每周周报 Routine

```markdown
# routine_weekly_review.md

## 元信息
- id: routine_weekly_review
- name: 每周周报
- schedule: "0 9 * * 1"
- permission: L2
- enabled: true

## 触发条件
- 定时任务：每周一 9:00
- 可手动触发：rf butler digest --type weekly

## 执行步骤

1. **获取本周数据**
   ```bash
   rf threads list --from "last monday" --to today -o json
   rf todos list --completed-this-week -o json
   rf contribution leaderboard --period week -o json
   rf qa stats --week -o json
   ```

2. **生成周报内容**（LLM 处理）
   - 本周话题统计
   - 待办完成率
   - 贡献排行榜
   - 下周待办预览

3. **推送到群**
   ```bash
   rf butler digest --room <room_id> --type weekly
   ```

## 输出格式

```markdown
## 每周周报 (2026年第10周)

### 📊 本周数据
| 指标 | 数量 | 环比 |
|------|------|------|
| 新增话题 | 45 | ↑ 12% |
| 问答数 | 23 | → |
| 待办完成 | 18 | ↑ 8% |
| 参与人数 | 32 | ↑ 3 |

### 🏆 贡献排行
1. 张三 - 提问 12 次，回答 8 次
2. 李四 - 提问 8 次，分享 5 篇
3. 王五 - 完成 6 个待办

### 📝 重要决策
- 决定采用 Redis Cluster 方案
- 确定下周发布 v2.1 版本

### ⏰ 下周待办
| 任务 | 负责人 | 截止日期 |
|------|--------|----------|
| 完成API文档 | 张三 | 03-15 |
| 性能测试 | 李四 | 03-17 |
```
```

---

### 4.4 待办提醒 Routine

```markdown
# routine_todo_reminder.md

## 元信息
- id: routine_todo_reminder
- name: 待办提醒
- schedule: "0 9 * * 1-5"
- permission: L1
- enabled: true

## 触发条件
- 定时任务：每个工作日 9:00

## 执行步骤

1. **查询今日到期的待办**
   ```bash
   rf todos list --due-today --status open -o json
   ```

2. **查询即将到期的待办（3天内）**
   ```bash
   rf todos list --due-before "+3 days" --status open -o json
   ```

3. **按责任人分组并发送提醒**
   ```bash
   rf notifications send --to <user_id> \
     --title "待办提醒" \
     --content "您有 N 个待办即将到期..."
   ```

## 输出格式

```
📋 待办提醒

今日到期 (2项):
- [高优] 完成部署文档
- [中优] 提交代码审查

3天内到期 (1项):
- [中优] 准备演示环境 (截止: 03-06)

回复 "完成 <任务编号>" 标记完成
```

## 个性化设置
- 用户可设置免打扰时段
- 用户可设置提醒频率（每天/隔天/仅到期日）
```

---

### 4.5 敏感授权升级 Routine

```markdown
# routine_sensitive_escalation.md

## 元信息
- id: routine_sensitive_escalation
- name: 敏感授权升级
- schedule: "0 10 * * *"
- permission: L2
- enabled: true

## 触发条件
- 定时任务：每天 10:00
- 条件：授权请求创建超过 7 天且状态为 pending

## 执行步骤

1. **查询待升级的敏感授权**
   ```bash
   rf sensitive pending --days 7 --escalation-candidates -o json
   ```

2. **对每条记录执行升级**
   ```bash
   rf admin sensitive escalate --auth-id <auth_id>
   ```

3. **通知管理员**
   ```bash
   rf notifications send --to admin \
     --title "敏感授权升级通知" \
     --content "以下敏感内容已升级处理：..."
   ```

## 升级流程

```
Day 0: 检测到敏感内容，创建授权请求
Day 1-3: 每日提醒当事人处理
Day 4-6: 隔日提醒 + 抄送相关人
Day 7: 升级管理员处理
```

## 输出格式

```json
{
  "escalated_count": 2,
  "details": [
    {
      "auth_id": "auth-001",
      "thread_title": "数据库连接配置",
      "pending_days": 7,
      "action": "escalated_to_admin"
    }
  ]
}
```
```

---

### 4.6 每日自省 Routine

```markdown
# routine_daily_reflection.md

## 元信息
- id: routine_daily_reflection
- name: 每日自省
- schedule: "0 23 * * *"
- permission: L3
- enabled: true

## 触发条件
- 定时任务：每天 23:00

## 执行步骤

1. **收集今日数据**
   ```bash
   rf threads list --from today --size 50 -o json
   rf todos list --created-today -o json
   rf todos list --completed-today -o json
   rf qa stats --today -o json
   rf butler tasks --today -o json
   ```

2. **分析遗漏和错误**（LLM 处理）
   - 检查是否有未分类的消息
   - 检查是否有遗漏的隐性承诺
   - 检查问答反馈中的负面评价
   - 检查待办识别准确率

3. **生成改进建议**
   - 行为优化建议
   - 提示词优化建议
   - 新发现的信息类别/任务类型

4. **保存自省报告**
   ```bash
   rf butler reflect --notes "..." --save
   ```

## 输出格式

```yaml
date: "2026-03-03"
summary:
  tasks_executed: 45
  success_rate: 0.92
  user_satisfaction: 4.3
  suggestion_acceptance_rate: 0.65

patterns_discovered:
  - pattern: "技术决策通知打开率更高"
    confidence: 0.85
    evidence_count: 12

issues_found:
  - type: "missed_commitment"
    description: "检测到 2 条隐性承诺未创建待办"
    action: "已补充创建"

  - type: "qa_negative_feedback"
    thread_id: "thread-xxx"
    feedback: "答案不够详细"
    action: "已标记待改进"

optimizations:
  - target: "duties/reminder.yaml"
    change: "增加用户偏好检查"
    reason: "减少投诉"
    status: "pending_review"

lessons_learned:
  - lesson: "周末提醒打扰较多"
    action: "建议增加免打扰设置"
```

## 存储路径
- `.rippleflow/insights/daily/2026-03-03.md`
```

---

### 4.7 每周复盘 Routine

```markdown
# routine_weekly_retrospect.md

## 元信息
- id: routine_weekly_retrospect
- name: 每周复盘
- schedule: "0 22 * * 0"
- permission: L3
- enabled: true

## 触发条件
- 定时任务：每周日 22:00

## 执行步骤

1. **汇总本周数据**
   ```bash
   rf butler tasks --week --status all -o json
   rf contribution stats --week -o json
   rf qa stats --week -o json
   ```

2. **分析效果趋势**
   - 各职责执行效果对比
   - 用户满意度变化
   - 任务成功率变化

3. **更新职责定义**
   - 识别需要优化的职责
   - 生成优化建议
   - 自动应用低风险优化

4. **保存复盘报告**
   ```bash
   rf butler retrospect --week 10 --save
   ```

## 输出格式

```markdown
## 每周复盘 (2026年第10周)

### 一、职责执行效果

| 职责 | 执行次数 | 成功率 | 满意度 | 趋势 |
|------|----------|--------|--------|------|
| 信息平权 | 234 | 92% | 4.2 | ↑ |
| 任务跟踪 | 156 | 88% | 4.0 | → |
| 问答辅助 | 89 | 95% | 4.5 | ↑ |

### 二、优化建议

1. **提醒时机优化**
   - 问题：周末提醒打开率低
   - 建议：工作日提醒时间提前到 8:30
   - 影响：低风险，可自动应用

2. **摘要长度优化**
   - 问题：部分摘要过长，用户反馈不够简洁
   - 建议：默认摘要长度从 500 字减少到 300 字
   - 影响：中风险，建议人工确认

### 三、自动应用优化
- [x] 提醒时间调整：8:30 → 8:00（工作日）
- [ ] 摘要长度调整：待人工确认
```
```

---

### 4.8 月度平台评估 Routine

```markdown
# routine_monthly_evaluation.md

## 元信息
- id: routine_monthly_evaluation
- name: 月度平台评估
- schedule: "0 9 1 * *"
- permission: L3
- enabled: true

## 触发条件
- 定时任务：每月1日 9:00

## 执行步骤

1. **收集月度数据**
   ```bash
   rf threads stats --month -o json
   rf todos stats --month -o json
   rf contribution leaderboard --period month -o json
   rf butler experience --month -o json
   ```

2. **生成平台评估报告**
   - 知识库增长趋势
   - 待办完成率趋势
   - 用户参与度分析
   - 系统健康度评估

3. **提出平台改进建议**
   - 功能优化建议
   - 新增信息类别建议
   - 新增任务类型建议

4. **发送评估报告**
   ```bash
   rf notifications send --to admin \
     --title "RippleFlow 月度评估报告" \
     --content "..."
   ```

## 输出格式

```markdown
## RippleFlow 月度评估报告 (2026年3月)

### 一、知识库增长

| 指标 | 本月 | 上月 | 变化 |
|------|------|------|------|
| 话题总数 | 1,523 | 1,456 | +4.6% |
| 新增话题 | 156 | 142 | +9.9% |
| 问答数 | 234 | 198 | +18.2% |
| 待办创建 | 89 | 76 | +17.1% |

### 二、用户参与度

- 活跃用户：32 人（环比 +3）
- 人均提问：7.3 次（环比 +0.5）
- 人均回答：4.2 次（环比 +0.3）

### 三、待办完成率

- 总待办：89 个
- 已完成：67 个（75.3%）
- 平均完成时间：3.2 天

### 四、管家自我沉淀

#### 最佳实践
1. 技术决策通知在周一上午打开率最高
2. 表格形式的周报接受度更高

#### 失败教训
1. 周末提醒打扰较多 → 已增加免打扰设置

### 五、平台改进建议

| 建议 | 原因 | 优先级 |
|------|------|--------|
| 增加任务依赖关系可视化 | 阻塞未及时发现 | 高 |
| 支持外部日历同步 | 用户需求 | 中 |
| 新增"技术分享"类别 | 15条证据支持 | 中 |

### 六、下月重点
1. 审批新增信息类别
2. 上线任务依赖可视化功能
3. 优化待办识别准确率
```
```

---

### 4.9 过期任务检查 Routine

```markdown
# routine_overdue_check.md

## 元信息
- id: routine_overdue_check
- name: 过期任务检查
- schedule: "0 18 * * 1-5"
- permission: L1
- enabled: true

## 触发条件
- 定时任务：每个工作日 18:00

## 执行步骤

1. **查询过期待办**
   ```bash
   rf todos list --overdue --status open -o json
   ```

2. **分析阻塞原因**（LLM 处理）
   - 是否有依赖关系阻塞
   - 是否资源不足
   - 是否负责人有其他优先事项

3. **发送提醒**
   ```bash
   rf notifications send --to <user_id> \
     --title "任务过期提醒" \
     --content "以下任务已过期..."
   ```

4. **更新任务状态**
   ```bash
   rf todos update <todo_id> --status in_review
   ```

## 输出格式

```
⚠️ 过期任务提醒

以下任务已过期，请及时处理：

1. [高优] 完成部署文档
   - 负责人：张三
   - 截止日期：2026-03-01（已过期 2 天）
   - 建议行动：是否需要延期或分解任务？

2. [中优] 代码审查
   - 负责人：李四
   - 截止日期：2026-02-28（已过期 3 天）
   - 阻塞原因：等待 PR 提交

回复 "延期 <任务编号> <新日期>" 或 "完成 <任务编号>"
```
```

---

### 4.10 问答满意度检查 Routine

```markdown
# routine_qa_satisfaction.md

## 元信息
- id: routine_qa_satisfaction
- name: 问答满意度检查
- schedule: "0 17 * * 1-5"
- permission: L1
- enabled: true

## 触发条件
- 定时任务：每个工作日 17:00

## 执行步骤

1. **查询今日问答反馈**
   ```bash
   rf qa feedback list --today -o json
   ```

2. **识别负面反馈**
   ```bash
   rf qa feedback list --rating-lt 3 --today -o json
   ```

3. **分析改进机会**（LLM 处理）
   - 答案是否准确
   - 答案是否完整
   - 是否需要更新知识源

4. **发送改进提醒**
   ```bash
   rf notifications send --to butler_team \
     --title "问答改进建议" \
     --content "..."
   ```

## 输出格式

```markdown
## 问答满意度报告 (2026-03-03)

### 今日统计
- 总问答数：23
- 有反馈数：18
- 平均评分：4.2/5

### 负面反馈分析

| 问题 | 评分 | 反馈 | 改进建议 |
|------|------|------|----------|
| Redis连接池配置 | 2 | 不够详细 | 补充参数说明示例 |
| Docker网络问题 | 3 | 缺少排查步骤 | 添加 step-by-step |

### 待处理
- [ ] 更新 Redis 连接池话题摘要
- [ ] 补充 Docker 网络排查流程
```
```

---

### 4.11 知识库健康检查 Routine

```markdown
# routine_knowledge_health.md

## 元信息
- id: routine_knowledge_health
- name: 知识库健康检查
- schedule: "0 3 * * 6"
- permission: L1
- enabled: true

## 触发条件
- 定时任务：每周六 3:00

## 执行步骤

1. **检查话题质量**
   ```bash
   rf threads list --status active --size 1000 -o json
   ```

2. **检查缺失摘要**
   ```bash
   rf threads list --no-summary -o json
   ```

3. **检查孤立话题**
   ```bash
   rf threads list --no-messages -o json
   ```

4. **检查过期话题**
   ```bash
   rf threads list --older-than 90 --status active -o json
   ```

5. **生成健康报告**
   ```bash
   rf butler health --full -o json
   ```

## 输出格式

```yaml
health_report:
  date: "2026-03-05"
  overall_score: 87

  topics:
    total: 1523
    active: 89
    with_summary: 1456
    missing_summary: 67
    orphaned: 3
    stale: 12

  recommendations:
    - action: "generate_summary"
      count: 67
      priority: "medium"

    - action: "archive_stale"
      count: 12
      priority: "low"

    - action: "merge_duplicates"
      count: 3
      priority: "low"

  auto_fixes:
    - type: "archive_stale"
      description: "自动归档 90 天无更新的话题"
      affected: 12
```
```

---

### 4.12 Routine 索引文件

```yaml
# .rippleflow/prompts/ROUTINES/index.yaml

routines:
  # 定时报送类
  - id: daily_digest
    file: routine_daily_digest.md
    schedule: "0 9 * * 1-5"
    permission: L2
    enabled: true

  - id: weekly_review
    file: routine_weekly_review.md
    schedule: "0 9 * * 1"
    permission: L2
    enabled: true

  # 提醒类
  - id: todo_reminder
    file: routine_todo_reminder.md
    schedule: "0 9 * * 1-5"
    permission: L1
    enabled: true

  - id: overdue_check
    file: routine_overdue_check.md
    schedule: "0 18 * * 1-5"
    permission: L1
    enabled: true

  # 流程类
  - id: sensitive_escalation
    file: routine_sensitive_escalation.md
    schedule: "0 10 * * *"
    permission: L2
    enabled: true

  - id: qa_satisfaction
    file: routine_qa_satisfaction.md
    schedule: "0 17 * * 1-5"
    permission: L1
    enabled: true

  # 自省类
  - id: daily_reflection
    file: routine_daily_reflection.md
    schedule: "0 23 * * *"
    permission: L3
    enabled: true

  - id: weekly_retrospect
    file: routine_weekly_retrospect.md
    schedule: "0 22 * * 0"
    permission: L3
    enabled: true

  - id: monthly_evaluation
    file: routine_monthly_evaluation.md
    schedule: "0 9 1 * *"
    permission: L3
    enabled: true

  # 维护类
  - id: knowledge_health
    file: routine_knowledge_health.md
    schedule: "0 3 * * 6"
    permission: L1
    enabled: true
```

---

## 五、自省驱动的能力扩展机制

### 8.1 核心理念

```
┌─────────────────────────────────────────────────────────────────┐
│                 AI 管家能力扩展闭环                               │
│                                                                 │
│   ┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐  │
│   │  自省   │ ──→ │  评估   │ ──→ │  决策   │ ──→ │  执行   │  │
│   │ 发现新  │     │ 现有CLI │     │ 自行开发 │     │ 新能力  │  │
│   需求     │     │ 能覆盖? │     │ 或提案  │     │ 上线    │  │
│   └─────────┘     └─────────┘     └─────────┘     └─────────┘  │
│        ↑                                               │        │
│        └───────────────────────────────────────────────┘        │
│                     持续学习与演化                               │
└─────────────────────────────────────────────────────────────────┘
```

**关键原则**：
- 能用现有命令组合解决 → **自行开发新 Routine**（L2 权限）
- 需要新命令 → **提交提案**，等待人工审批（L3 权限）

### 8.2 自省发现新需求的来源

| 来源 | 示例 | 触发频率 |
|------|------|----------|
| **用户请求分析** | 多次被问到"XX在哪"，发现需要自动汇总 | 实时 |
| **失败模式识别** | 某类任务识别准确率低，需要新检测规则 | 每日自省 |
| **效率优化机会** | 手动操作频繁，可自动化 | 每周复盘 |
| **用户反馈** | "希望能自动..."的请求 | 实时 |
| **数据模式发现** | 发现新的信息类别或任务类型 | 每周 |

### 8.3 能力评估流程

```markdown
# 自省评估提示词

## 输入
- 发现的新需求：{new_requirement}
- 现有命令列表：`rf help` 输出

## 评估步骤

1. **解析需求**
   - 需求类型：[通知 | 报告 | 提醒 | 分析 | 数据处理]
   - 触发条件：[定时 | 事件 | 手动]
   - 输入数据：[话题 | 待办 | 用户 | 消息]
   - 输出格式：[通知 | 报告 | 数据]

2. **搜索可用命令**
   ```bash
   rf help
   rf <command> --help
   ```

3. **评估覆盖度**
   - 能否用单个命令解决？
   - 能否用命令组合解决？
   - 是否需要新增命令？

4. **输出评估结果**
   ```yaml
   assessment:
     requirement: "自动汇总每周新加入成员"
     can_achieve_with_existing: true
     solution:
       type: "routine"
       commands:
         - "rf admin whitelist list --active --from last-week -o json"
         - "rf notifications send --to admin --title '新成员汇总'"
       estimated_steps: 2
     new_commands_needed: []
   ```
```

### 8.4 决策矩阵

| 场景 | CLI 覆盖度 | 决策 | 权限 | 审批 |
|------|-----------|------|------|------|
| 完全覆盖 | 100% | 自行创建 Routine | L1 | 无需审批 |
| 组合可实现 | 80-99% | 自行创建 Routine | L2 | 事后汇报 |
| 需要新参数 | 60-79% | 提交参数扩展提案 | L2 | 人工审批 |
| 需要新命令 | < 60% | 提交新命令提案 | L3 | 人工审批 |

### 8.5 自行开发新 Routine 流程

#### 8.5.1 创建流程

```yaml
# 自行开发新 Routine 的标准流程

workflow:
  1_discover:
    action: "自省发现新需求"
    output: "需求描述文档"

  2_assess:
    action: "评估现有 CLI 能力"
    command: "rf help && rf <cmd> --help"
    output: "评估报告"

  3_design:
    action: "设计 Routine 逻辑"
    output: "Routine 草稿"

  4_test:
    action: "手动测试命令组合"
    command: "rf <cmd1> ... | rf <cmd2> ..."
    output: "测试结果"

  5_create:
    action: "创建 Routine 文件"
    path: ".rippleflow/prompts/ROUTINES/routine_xxx.md"
    permission: L2

  6_register:
    action: "注册到索引"
    path: ".rippleflow/prompts/ROUTINES/index.yaml"

  7_notify:
    action: "通知管理员"
    command: 'rf notifications send --to admin --title "新 Routine 已创建"'
```

#### 8.5.2 Routine 模板

```markdown
# routine_xxx.md

## 元信息
- id: routine_xxx
- name: [Routine 名称]
- schedule: "[cron 表达式]" | trigger: "[事件类型]"
- permission: L1 | L2
- enabled: true
- created_by: butler_auto
- created_at: [日期]
- source: [自省发现 | 用户请求 | 效率优化]

## 背景说明
[为什么需要这个 Routine，发现过程]

## 触发条件
- [触发条件描述]

## 执行步骤

1. [步骤1描述]
   ```bash
   rf <command> [options]
   ```

2. [步骤2描述]
   ```bash
   rf <command> [options]
   ```

## 输出格式
[输出示例]

## 错误处理
[错误处理策略]
```

### 8.6 新命令提案流程

#### 8.6.1 提案模板

```yaml
# proposals/new_command_xxx.yaml

proposal:
  id: prop_20260303_001
  type: new_command
  status: pending
  created_at: "2026-03-03T10:00:00Z"
  created_by: butler

  need:
    title: "新增命令：rf threads batch-update"
    description: |
      场景：每周需要批量更新多个话题的状态（如批量归档）
      现有方案：需要逐个执行 rf threads update，效率低
      影响：每周约 20+ 次手动操作

  current_workaround:
    commands:
      - "rf threads list --status active --older-than 30 -o json"
      - "for each: rf threads update <id> --status archived"
    pain_points:
      - "需要手动循环处理"
      - "无事务保证"
      - "效率低"

  proposed_command:
    syntax: "rf threads batch-update [options]"
    options:
      - name: "--status"
        type: enum
        required: true
      - name: "--filter"
        type: string
        description: "过滤条件 JSON"
      - name: "--dry-run"
        type: flag
    example: |
      rf threads batch-update --status archived \
        --filter '{"older_than": 30, "category": "qa_faq"}'

  estimated_effort: "medium"
  priority: "medium"

review:
  reviewed_by: null
  reviewed_at: null
  decision: null
  notes: null
```

#### 8.6.2 提案审批流程

```
┌─────────────────────────────────────────────────────────────────┐
│                    提案审批流程                                  │
│                                                                 │
│  1. 但家创建提案                                                │
│     └→ 保存到 proposals/ 目录                                   │
│                                                                 │
│  2. 通知管理员                                                  │
│     └→ rf notifications send --to admin --title "新提案待审批"  │
│                                                                 │
│  3. 管理员审批                                                  │
│     ├→ rf butler proposals list                                 │
│     ├→ rf butler approve <proposal_id>                          │
│     └→ rf butler reject <proposal_id> --reason "..."            │
│                                                                 │
│  4. 批准后                                                      │
│     └→ 创建 GitHub Issue，指派开发者                            │
│                                                                 │
│  5. 拒绝后                                                      │
│     └→ 记录原因，但家可学习避免类似提案                          │
└─────────────────────────────────────────────────────────────────┘
```

### 8.7 自省扩展示例

#### 示例1：自动发现并创建新 Routine

```yaml
# 自省日志示例

reflection:
  date: "2026-03-05"
  discovered_needs:
    - description: "每周一早上需要汇总上周新增的待办完成情况"
      frequency: "已连续 3 周有人手动询问"
      source: "用户请求分析"

  assessment:
    can_achieve: true
    commands_needed:
      - "rf todos list --completed-this-week -o json"
      - "rf contribution stats --week -o json"
    routine_name: "weekly_completion_summary"

  action_taken:
    type: "create_routine"
    file: "routine_weekly_completion_summary.md"
    schedule: "0 8 * * 1"
    permission: L2
    notify_admin: true
```

#### 示例2：发现需要新命令并提交提案

```yaml
# 自省日志示例

reflection:
  date: "2026-03-05"
  discovered_needs:
    - description: "批量导出某个群的历史消息为 Markdown"
      frequency: "已收到 5 次类似请求"
      source: "用户反馈"

  assessment:
    can_achieve: false
    reason: "现有命令只能单条查询，无批量导出功能"
    gap: "缺少 rf export 命令"

  action_taken:
    type: "submit_proposal"
    proposal_file: "proposals/new_command_export.yaml"
    priority: "medium"
```

### 8.8 自省能力边界

| 管家可以做的 | 管家不能做的 |
|-------------|-------------|
| 创建新 Routine（L1/L2） | 修改核心提示词（core/） |
| 组合现有命令 | 新增 CLI 命令代码 |
| 优化现有 Routine | 修改数据库 Schema |
| 提交改进提案 | 修改 API 接口 |
| 学习用户偏好 | 修改权限配置 |

---

## 六、提示词文件

### 6.1 IDENTITY.md（核心身份）

```markdown
# RippleFlow AI 管家

## 身份

你是 RippleFlow 群聊知识库的 AI 管家，负责将群聊历史转化为可问答的活知识库。

## 能力发现

你可以通过以下方式发现系统所有能力：

1. **查询可用命令**
   ```
   rf help
   ```

2. **查询命令详情**
   ```
   rf <command> --help
   ```

3. **执行命令**
   ```
   rf <command> [options]
   ```

## 核心职责

1. **信息平权**：确保群内信息对所有人可见，打破信息孤岛
2. **智能推荐**：根据用户关注点推送相关话题
3. **总结提炼**：将冗长讨论浓缩为结构化知识
4. **问答辅助**：帮助用户快速找到答案
5. **任务跟踪**：跟踪任务进度，确保不遗漏
6. **及时提醒**：在关键时刻提醒相关人员

## 权限等级

| 等级 | 操作 |
|------|------|
| L1 | 通知、提醒、摘要 |
| L2 | 敏感信息升级、日报周报 |
| L3 | 自省优化、知识提取 |

## 行为准则

- 不主动发送消息到群（仅回复）
- 敏感信息需当事人授权
- 保持中立，不偏袒任何一方
- 保护隐私，不在日志中记录敏感信息

## 文件访问

你可以访问以下文件：
- `MEMORY.md` - 核心知识库
- `memory/*.md` - 活跃话题详情
- `archive/summaries/*.md` - 归档摘要
- `insights/*.md` - 自省沉淀

使用 `@file <path>` 查看文件内容。

## 执行示例

当需要查询话题时：
```bash
rf threads search "Redis配置" --category qa_faq -o json
```

当需要创建待办时：
```bash
rf todos add "完成部署文档" --due 2026-03-10 --priority high
```

当需要处理敏感授权时：
```bash
rf sensitive pending
rf sensitive decide <auth_id> --decision approve
```
```

---

## 七、启动命令

```bash
# 初始化 workspace
mkdir -p .rippleflow/{memory,archive/{summaries,originals},prompts/ROUTINES,insights/{daily,weekly}}

# 设置环境变量
export RIPPLEFLOW_HOME=/path/to/rippleflow
export ZHIPU_API_KEY=your_api_key

# 启动 gateway 模式（接收 webhook）
nullclaw gateway --config .rippleflow/config.json

# 启动 agent 模式（交互式）
nullclaw agent --config .rippleflow/config.json --agent rippleflow_butler

# 启动 daemon 模式（后台服务）
nullclaw service --config .rippleflow/config.json
```

---

## 八、与 RippleFlow 后端集成

```
┌─────────────────────────────────────────────────────────────────┐
│                    RippleFlow 系统架构                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐     Webhook      ┌─────────────────────────┐  │
│  │ 微信/钉钉    │ ───────────────→ │ nullclaw gateway:3000  │  │
│  │ /飞书群     │                  │                         │  │
│  └─────────────┘                  └───────────┬─────────────┘  │
│                                               │                │
│                                               ▼                │
│                                   ┌─────────────────────────┐  │
│                                   │   nullclaw agent        │  │
│                                   │   (AI管家)              │  │
│                                   │                         │  │
│                                   │   能力发现：            │  │
│                                   │   rf help               │  │
│                                   │                         │  │
│                                   │   能力调用：            │  │
│                                   │   rf <command> [args]   │  │
│                                   └───────────┬─────────────┘  │
│                                               │                │
│                                               ▼                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   RippleFlow 后端                        │   │
│  │                                                         │   │
│  │  能力暴露：                                              │   │
│  │  ├── REST API :8080                                    │   │
│  │  └── CLI 命令 (rf)                                      │   │
│  │                                                         │   │
│  │  数据库：SQLite / PostgreSQL                            │   │
│  │  缓存：内存缓存 / Redis                                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 八、环境变量

```bash
# .env
RIPPLEFLOW_HOME=/path/to/rippleflow

# LLM
ZHIPU_API_KEY=your_zhipu_api_key

# Channels
DINGTALK_APP_KEY=your_dingtalk_app_key
DINGTALK_APP_SECRET=your_dingtalk_app_secret
DINGTALK_WEBHOOK=https://oapi.dingtalk.com/robot/send?access_token=xxx

LARK_APP_ID=your_lark_app_id
LARK_APP_SECRET=your_lark_app_secret
LARK_WEBHOOK=https://open.feishu.cn/open-apis/bot/v2/hook/xxx
```

---

## 九、验证清单

- [ ] nullclaw 编译成功 (`zig build`)
- [ ] 测试通过 (`zig build test --summary all`)
- [ ] 配置文件加载成功
- [ ] Memory 文件创建成功
- [ ] CLI 命令可用 (`rf help`)
- [ ] Channel 连接成功（钉钉/飞书）
- [ ] Routine 脚本执行成功
- [ ] Cron 任务调度成功

---

## 十、变更历史

| 版本 | 日期 | 变更内容 |
|------|------|----------|
| v1.0 | 2026-03-03 | 初始版本 |
| v2.0 | 2026-03-03 | 架构调整：策略由 nullclaw 提供，新增 CLI 调用方式 |

---

**文档版本**: v2.0
**更新时间**: 2026-03-03