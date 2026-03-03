# RippleFlow AI 管家 nullclaw 对接配置

## 概述

| 项目 | 值 |
|------|------|
| 创建日期 | 2026-03-03 |
| 目标 | 将 RippleFlow AI 管家对接到 nullclaw 框架 |
| nullclaw 版本 | 2026.3.x |

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
│  │  │   ├── IDENTITY.md       ← core/identity              │   │
│  │  │   ├── DUTIES.md         ← duties/*                   │   │
│  │  │   └── SKILLS.md         ← skills/*                   │   │
│  │  │                                                      │   │
│  │  └── insights/             ← 自省沉淀                    │   │
│  │      ├── daily/            ← 每日自省                    │   │
│  │      └── weekly/           ← 每周复盘                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    nullclaw 核心                          │   │
│  │                                                          │   │
│  │  Channels:          Tools:           Cron:               │   │
│  │  - dingtalk         - sensitive_*     - daily_reflection │   │
│  │  - lark             - todo_*          - weekly_review    │   │
│  │  - web              - thread_*        - monthly_evolve   │   │
│  │                     - butler_*                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 二、config.json 配置

```json
{
  "$schema": "https://nullclaw.ai/schema/config.json",
  "version": "2026.3.1",

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
      "workspace_dir": ".rippleflow"
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
    },
    "retrieval": {
      "mode": "hybrid",
      "fts_weight": 0.6,
      "semantic_weight": 0.4
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
      "sensitive_escalate",
      "sensitive_notify",
      "todo_reminder",
      "todo_overdue",
      "thread_notify",
      "thread_drift",
      "digest_daily",
      "digest_weekly",
      "butler_reflect",
      "butler_evolve",
      "knowledge_extract",
      "collaboration_analyze"
    ],

    "permissions": {
      "L1": ["thread_notify", "todo_reminder", "sensitive_notify"],
      "L2": ["sensitive_escalate", "digest_daily", "digest_weekly"],
      "L3": ["butler_reflect", "butler_evolve", "knowledge_extract"]
    }
  },

  "cron": {
    "enabled": true,
    "jobs": [
      {
        "name": "daily_reflection",
        "schedule": "0 23 * * *",
        "tool": "butler_reflect",
        "agent": "rippleflow_butler"
      },
      {
        "name": "weekly_review",
        "schedule": "0 9 * * 1",
        "tool": "digest_weekly",
        "agent": "rippleflow_butler"
      },
      {
        "name": "monthly_evolution",
        "schedule": "0 9 1 * *",
        "tool": "butler_evolve",
        "agent": "rippleflow_butler"
      },
      {
        "name": "daily_compact",
        "schedule": "0 2 * * *",
        "action": "memory_compact"
      },
      {
        "name": "todo_morning_reminder",
        "schedule": "0 9 * * 1-5",
        "tool": "todo_reminder",
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
    "sandbox": {
      "enabled": false
    },
    "audit": {
      "enabled": true,
      "log_path": ".rippleflow/logs/audit.log",
      "reflection_audit": {
        "enabled": true,
        "log_path": ".rippleflow/logs/reflection_audit.log",
        "include_fields": [
          "timestamp",
          "reflection_type",
          "improvement_category",
          "improvement_detail",
          "affected_components",
          "proposed_action",
          "confidence"
        ],
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

## 三、提示词文件

### 3.1 IDENTITY.md（核心身份）

```markdown
# RippleFlow AI 管家

## 身份

你是 RippleFlow 群聊知识库的 AI 管家，负责将群聊历史转化为可问答的活知识库。

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
```

### 3.2 DUTIES.md（职责定义）

```markdown
# 管家职责定义

## 1. 消息处理流程

当收到群消息时：
1. 分析消息类型（问题/决策/任务/闲聊）
2. 提取关键信息（参与者、时间、关键词）
3. 关联现有话题或创建新话题
4. 更新话题摘要
5. 检测待办事项和隐性承诺

## 2. 敏感信息处理

当检测到敏感信息时：
1. 识别敏感类型（密码/密钥/个人信息）
2. 创建授权请求
3. 通知相关当事人
4. 7天无响应 → 升级管理员

## 3. 任务跟踪

对于识别到的任务：
1. 确认责任人和截止时间
2. 添加到任务列表
3. 截止前提醒责任人
4. 检测完成信号更新状态

## 4. 知识沉淀

对于有价值的讨论：
1. 提取核心结论
2. 归类到对应分类
3. 更新知识图谱
4. 定期生成摘要

## 5. 自省机制

每日 23:00：
- 回顾当日处理的消息
- 识别遗漏或错误
- 记录改进点

每周一 9:00：
- 汇总本周知识沉淀
- 分析热点话题
- 建议优化方向
```

### 3.3 SKILLS.md（技能模板）

```markdown
# 管家技能

## 1. 隐性承诺识别

检测模式：
- "我回头..."
- "我会..."
- "计划下周..."
- "周三前..."

处理：创建待确认任务，24小时内确认。

## 2. 完成信号检测

检测信号：
- "已完成"
- "搞定了"
- "done"
- "✅"

处理：自动更新相关任务状态为已完成。

## 3. 多步骤任务拆解

当检测到复杂任务时：
1. 识别任务边界
2. 拆解为子任务
3. 分配责任人和时间
4. 建立依赖关系

## 4. 知识图谱更新

从话题中提取：
- 实体（人、技术、项目）
- 关系（使用、负责、参与）
- 属性（时间、状态、优先级）

## 5. 协作网络分析

定期分析：
- 互动频率
- 问答关系
- 任务分配模式

识别领域专家和信息桥梁。
```

---

## 四、Memory 文件布局

### 4.1 MEMORY.md（L3 核心层）

```markdown
# RippleFlow 知识库核心

## 技术栈

| 技术 | 用途 | 负责人 |
|------|------|--------|
| FastAPI | 后端框架 | 张三 |
| PostgreSQL | 主数据库 | 李四 |
| Redis | 缓存 | 王五 |

## 关键决策

### 2026-03-01: Redis 集群架构
- 决策：采用 3主3从 + Sentinel
- 参与者：张三、李四
- 状态：已完成

### 2026-02-15: API 规范
- 决策：RESTful + OpenAPI 3.0
- 参与者：全体
- 状态：已完成

## 术语词典

| 术语 | 定义 |
|------|------|
| 话题线索 | Topic Thread，一条有价值的讨论线索 |
| 活摘要 | Living Summary，随消息更新的话题摘要 |
| 隐性承诺 | 从聊天中识别的非明确任务承诺 |

## 专家网络

| 领域 | 专家 | 置信度 |
|------|------|--------|
| Redis | 张三 | 0.95 |
| PostgreSQL | 李四 | 0.9 |
| Python | 王五 | 0.85 |
```

### 4.2 memory/2026-03-03.md（L1 活跃层）

```markdown
# 2026-03-03 话题记录

## 话题: Redis 集群部署进度

**分类**: tech_decision
**状态**: active
**参与者**: 张三、李四、王五

### 摘要
今天完成了 Redis 集群的服务器申请，预计本周完成部署。

### 消息记录

**09:15 张三**:
服务器申请已提交，等待运维审批。

**10:30 李四**:
提醒：审批通常需要 1-2 天，建议提前准备部署脚本。

**14:00 王五**:
部署脚本已准备好，在 docs/scripts/redis-cluster.sh

### 待办事项
- [ ] 服务器审批（张三，周三前）
- [ ] 准备监控告警（王五）

---

## 话题: API 接口规范补充

**分类**: discussion_notes
**状态**: resolved

### 摘要
补充了分页接口的统一规范。

### 决策
1. 分页参数：page, size
2. 返回格式：items, total, page, size
```

---

## 五、Tools 定义

### 5.1 sensitive_escalate Tool

```zig
// src/tools/sensitive_escalate.zig

const std = @import("std");
const Tool = @import("../tools/root.zig").Tool;
const JsonObjectMap = std.json.ObjectMap;

pub const SensitiveEscalateTool = struct {
    pub fn execute(
        args: JsonObjectMap,
        allocator: std.mem.Allocator
    ) !ToolResult {
        // 获取参数
        const thread_id = args.get("thread_id").?.string;
        const days_pending = args.get("days_pending").?.integer;

        // L2 权限操作：升级敏感信息到管理员
        // 实现逻辑...

        return ToolResult{
            .success = true,
            .output = "Sensitive content escalated to admin",
        };
    }

    pub fn name() []const u8 {
        return "sensitive_escalate";
    }

    pub fn description() []const u8 {
        return "升级敏感信息到管理员（L2权限）";
    }

    pub fn parametersJson(allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator,
            \\{{
            \\  "type": "object",
            \\  "properties": {{
            \\    "thread_id": {{"type": "string", "format": "uuid"}},
            \\    "days_pending": {{"type": "integer"}}
            \\  }},
            \\  "required": ["thread_id"]
            \\}}
        , .{});
    }
};
```

### 5.2 butler_reflect Tool

```zig
// src/tools/butler_reflect.zig

pub const ButlerReflectTool = struct {
    pub fn execute(
        args: JsonObjectMap,
        allocator: std.mem.Allocator
    ) !ToolResult {
        // 每日自省逻辑
        // 1. 回顾今日消息
        // 2. 识别遗漏/错误
        // 3. 生成改进建议
        // 4. 写入 insights/daily/

        return ToolResult{
            .success = true,
            .output = "Daily reflection completed",
        };
    }

    pub fn name() []const u8 {
        return "butler_reflect";
    }

    pub fn description() []const u8 {
        return "AI管家每日自省";
    }
};
```

---

## 六、启动命令

```bash
# 初始化 workspace
mkdir -p .rippleflow/{memory,archive/{summaries,originals},prompts,insights/{daily,weekly}}

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
│                                   │   - 处理消息            │  │
│                                   │   - 更新 Memory         │  │
│                                   │   - 触发 Tools          │  │
│                                   └───────────┬─────────────┘  │
│                                               │                │
│                                               ▼                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   RippleFlow 后端                        │   │
│  │                                                         │   │
│  │  PostgreSQL:                                            │   │
│  │  - topic_threads (与 memory/*.md 同步)                  │   │
│  │  - action_items                                         │   │
│  │  - sensitive_authorizations                             │   │
│  │                                                         │   │
│  │  API Server:8080                                        │   │
│  │  - 查询接口                                             │   │
│  │  - 管理接口                                             │   │
│  │  - 知识图谱查询                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 八、同步机制

### 8.1 Memory ↔ PostgreSQL 同步

```python
# sync_service.py

class MemorySyncService:
    """Memory 文件与 PostgreSQL 同步"""

    async def sync_to_db(self):
        """将 Memory 文件同步到数据库"""
        # 1. 读取 memory/*.md 文件
        # 2. 解析话题结构
        # 3. 更新 topic_threads 表
        # 4. 更新知识图谱
        pass

    async def sync_from_db(self):
        """将数据库同步到 Memory 文件"""
        # 1. 查询 topic_threads
        # 2. 生成 memory/YYYY-MM-DD.md
        pass
```

---

## 九、环境变量

```bash
# .env
ZHIPU_API_KEY=your_zhipu_api_key
DINGTALK_APP_KEY=your_dingtalk_app_key
DINGTALK_APP_SECRET=your_dingtalk_app_secret
DINGTALK_WEBHOOK=https://oapi.dingtalk.com/robot/send?access_token=xxx
LARK_APP_ID=your_lark_app_id
LARK_APP_SECRET=your_lark_app_secret
LARK_WEBHOOK=https://open.feishu.cn/open-apis/bot/v2/hook/xxx
```

---

## 十、验证清单

- [ ] nullclaw 编译成功 (`zig build`)
- [ ] 测试通过 (`zig build test --summary all`)
- [ ] 配置文件加载成功
- [ ] Memory 文件创建成功
- [ ] Channel 连接成功（钉钉/飞书）
- [ ] Tool 执行成功
- [ ] Cron 任务调度成功

---

**文档版本**: v1.0
**创建时间**: 2026-03-03