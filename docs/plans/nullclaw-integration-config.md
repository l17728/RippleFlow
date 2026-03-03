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

## 一、整体架构

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

## 四、Routine 脚本示例

### 4.1 敏感授权升级 Routine

```markdown
# routine_sensitive_escalation.md

## 触发条件
- 定时任务：每天 10:00
- 条件：授权请求创建超过 7 天且状态为 pending

## 执行步骤

1. 查询待升级的敏感授权
   ```bash
   rf sensitive pending --days 7 -o json
   ```

2. 对每条记录执行升级
   ```bash
   rf admin sensitive escalate --auth-id <auth_id>
   ```

3. 通知管理员
   ```bash
   rf notifications send --to admin --title "敏感授权升级" --content "..."
   ```

## 输出
- 升级成功：返回 {success: true}
- 升级失败：返回 {success: false, error: reason}
```

### 4.2 待办提醒 Routine

```markdown
# routine_todo_reminder.md

## 触发条件
- 定时任务：每天 9:00（工作日）

## 执行步骤

1. 查询今日到期的待办
   ```bash
   rf todos list --due-today --status open -o json
   ```

2. 按责任人分组

3. 发送提醒
   ```bash
   rf notifications send --to <user_id> --title "待办提醒" --content "..."
   ```

## 输出
- 提醒成功：返回 {reminded_count: N}
```

### 4.3 每日快报 Routine

```markdown
# routine_daily_digest.md

## 触发条件
- 定时任务：每天 9:00（工作日）

## 执行步骤

1. 获取昨日话题摘要
   ```bash
   rf threads list --from yesterday --to today --size 20 -o json
   ```

2. 生成快报内容（LLM）

3. 推送到群
   ```bash
   rf butler digest --room <room_id> --type daily
   ```

## 输出
- 快报已发送
```

### 4.4 自省 Routine

```markdown
# routine_reflection.md

## 触发条件
- 定时任务：每天 23:00

## 执行步骤

1. 回顾今日处理的消息
   ```bash
   rf threads list --from today --size 50 -o json
   rf todos list --created-today -o json
   rf qa stats --today -o json
   ```

2. 分析遗漏和错误
   - 检查是否有未分类的消息
   - 检查是否有遗漏的隐性承诺
   - 检查问答反馈中的负面评价

3. 记录改进点
   ```bash
   rf butler reflect --notes "..." --save
   ```

## 输出
- 自省报告已保存到 insights/daily/
```

---

## 五、提示词文件

### 5.1 IDENTITY.md（核心身份）

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

## 六、启动命令

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

## 七、与 RippleFlow 后端集成

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