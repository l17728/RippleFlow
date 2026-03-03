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