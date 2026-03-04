# AI 管家演化架构设计

## 文档信息

| 项目 | 值 |
|------|-----|
| 版本 | 2.0 |
| 创建日期 | 2026-03-02 |
| 更新日期 | 2026-03-02 |
| 关联文档 | 00_overview.md, 01_system_architecture.md, 04_service_interfaces.md |

---

## 1. 概述

### 1.1 定位

AI 管家是 RippleFlow 平台的**灵魂**，是平台的"大脑"：

```
传统机器人：被动响应，执行固定逻辑
AI 管家：主动感知，智能决策，持续演化
```

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **信息平权** | 确保信息公平触达每个需要的人 |
| **智能推荐** | 发现有价值的信息并推荐给相关人员 |
| **总结提炼** | 将复杂信息转化为易理解的形式 |
| **问答辅助** | 帮助用户快速找到答案 |
| **任务跟踪** | 跟踪任务进度，确保不遗漏 |
| **及时提醒** | 在关键时刻提醒相关人员 |

### 1.3 设计原则

1. **提示词驱动**：职责和技能存储在提示词中，而非硬编码
2. **感知-决策-执行**：管家通过观察平台状态自主决策行动
3. **自省与演化**：定期反思，优化职责和沉淀最佳实践
4. **冷启动友好**：核心提示词确保管家具备基本能力
5. **零代码扩展**：新功能通过扩展脚本实现
6. **人机协作**：管家建议，人类最终决策

---

## 2. 平台核心架构

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        RippleFlow 平台                           │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐   │
│  │ 消息队列 │ │ 知识库  │ │ 待办系统 │ │ 订阅系统 │ │ 问答系统 │   │
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘   │
│       │           │           │           │           │         │
│       └───────────┴───────────┴───────────┴───────────┘         │
│                               │                                  │
│                               │ 事件推送 (HTTP POST)             │
│                               ▼                                  │
│                    nullclaw gateway:3000                         │
│                               │                                  │
│                               ▼                                  │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    nullclaw Agent (AI 管家)                      │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                  Channels (事件接收)                         ││
│  │  message.received | thread.created | todo.* | user.*        ││
│  └─────────────────────────┬───────────────────────────────────┘│
│                            │                                     │
│                            ▼                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ 感知层      │  │ 决策层      │  │ 执行层      │              │
│  │ Observation │→ │ Decision    │→ │ Action      │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│        ↑                ↑                ↓                       │
│        └────────────────┴────────────────┘                       │
│                      自省反馈环                                   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              Memory 三层架构 (nullclaw)                      ││
│  │  L1 活跃层 | L2 归档层 | L3 核心层                           ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              提示词知识库 (Prompt KB)                        ││
│  │  core/ | duties/ | skills/ | insights/ | extensions/        ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

**架构说明**：

| 组件 | 职责 | 实现方式 |
|------|------|----------|
| **RippleFlow 平台** | 数据存储、业务 API、CLI 命令 | FastAPI + SQLite/PG |
| **事件推送** | 平台事件推送到 nullclaw | HTTP POST |
| **nullclaw channels** | 接收并路由事件 | nullclaw 原生能力 |
| **nullclaw memory** | 三层记忆管理 | nullclaw 原生能力 |
| **nullclaw cron** | 定时任务调度 | nullclaw 原生能力 |
| **nullclaw tools** | 工具调用（shell/http/file） | nullclaw 原生能力 |

### 2.2 感知-决策-执行循环

```
┌──────────────────────────────────────────────────────────────────┐
│                         感知层 (Observation)                      │
│                                                                  │
│  通过 nullclaw channels 接收平台事件：                            │
│  • message.received: 新消息入库                                  │
│  • thread.created: 新话题线索创建                                │
│  • todo.created/completed: 待办状态变更                          │
│  • sensitive.detected: 敏感内容检测                              │
│  • user.query: 用户发起问答                                      │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                         决策层 (Decision)                         │
│                                                                  │
│  1. 这个事件与哪些职责相关？                                      │
│  2. 是否需要采取行动？                                           │
│  3. 行动的优先级是什么？                                         │
│  4. 用什么方式执行？                                             │
│  5. 是否需要审批？                                               │
│                                                                  │
│  决策来源：                                                       │
│  • Routine 脚本（固化逻辑）                                      │
│  • LLM 智能层（灵活决策）                                        │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                         执行层 (Action)                           │
│                                                                  │
│  通过 nullclaw tools 执行：                                      │
│  • shell_execute: 执行 rf 命令                                  │
│  • http_request: 调用外部 API                                   │
│  • file_read/write: 操作文件                                    │
│                                                                  │
│  典型操作：                                                       │
│  发送通知 | 生成报告 | 创建任务 | 回复问答 | 更新知识库           │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                         自省层 (Reflection)                       │
│                                                                  │
│  分析执行效果 | 提取模式 | 沉淀最佳实践 | 优化提示词              │
│  生成平台改进建议                                                │
│                                                                  │
│  输出到：                                                         │
│  • insights/daily/ - 每日自省                                   │
│  • insights/weekly/ - 每周复盘                                  │
│  • proposals/ - 能力扩展提案                                    │
└──────────────────────────────────────────────────────────────────┘
```

---

## 3. 提示词分级架构

### 3.1 目录结构

借鉴 skill 设计理念，采用**目录隔离 + 多级索引**：

```
butler_prompts/
├── core/                          # 核心提示词（冷启动必需，不可修改）
│   ├── identity.md                # 身份定位
│   ├── principles.md              # 行为准则
│   ├── permissions.md             # 权限边界
│   └── triggers.md                # 触发框架
│
├── duties/                        # 职责定义（管家可优化）
│   ├── index.yaml                 # 职责索引
│   ├── information_equity.yaml    # 信息平权
│   ├── recommendation.yaml        # 智能推荐
│   ├── summarization.yaml         # 总结提炼
│   ├── qa_assistant.yaml          # 问答辅助
│   ├── tracking.yaml              # 任务跟踪
│   └── reminder.yaml              # 及时提醒
│
├── skills/                        # 技能模板（具体执行方法）
│   ├── index.yaml                 # 技能索引
│   ├── data_visualization.md      # 数据可视化
│   ├── link_summary.md            # 链接摘要
│   ├── task_extraction.md         # 任务提取
│   ├── meeting_notes.md           # 会议纪要
│   └── weekly_digest.md           # 周报生成
│
├── templates/                     # 输出模板
│   ├── notification/              # 通知模板
│   ├── report/                    # 报告模板
│   └── card/                      # 卡片消息模板
│
├── insights/                      # 自省沉淀（动态增长）
│   ├── best_practices.yaml        # 最佳实践
│   ├── user_preferences.yaml      # 用户偏好
│   ├── failure_lessons.yaml       # 失败教训
│   └── optimization_history.yaml  # 优化历史
│
└── extensions/                    # 扩展脚本（无需改代码）
    ├── index.yaml                 # 扩展索引
    ├── reports/                   # 自定义报告
    ├── webhooks/                  # 外部集成
    └── analyzers/                 # 自定义分析器
```

### 3.2 核心提示词（不可修改）

这是管家的"出厂设置"，确保冷启动时具备基本能力：

```markdown
# core/identity.md

你叫"管家"，是 RippleFlow 知识库平台的智能运营者。

## 你的使命
让团队的群聊历史变成一个会思考、会回答、会自动整理的活知识库，
实现信息平权，让每个人都能获取所需的上下文。

## 你的核心职责（按优先级）
1. **信息平权**：确保信息公平触达每个需要的人
2. **智能推荐**：发现有价值的信息并推荐给相关人员
3. **总结提炼**：将复杂信息转化为易理解的形式
4. **问答辅助**：帮助用户快速找到答案
5. **任务跟踪**：跟踪任务进度，确保不遗漏
6. **及时提醒**：在关键时刻提醒相关人员

## 你的行为准则
1. 主动但不打扰：判断用户是否需要介入
2. 建议而非命令：最终决定权在人
3. 学习并改进：每次交互都是学习机会
4. 人机协作：你建议，人类决策

## 你的权限边界
- L0（只读）：自由执行
- L1（轻度行动）：自由执行，记录日志
- L2（中度行动）：执行后汇报
- L3（高度行动）：事前审批
```

```yaml
# core/triggers.md

## 事件类型

### 消息类事件
- message.received: 新消息入库
- message.sensitive_detected: 敏感内容检测
- thread.created: 新话题线索创建
- thread.updated: 话题线索更新

### 用户类事件
- user.query: 用户发起问答
- user.todo_created: 用户创建待办
- user.todo_completed: 用户完成待办
- user.subscribed: 用户订阅某对象
- user.feedback: 用户提交反馈

### 系统类事件
- system.digest_time: 定时快报时间
- system.reminder_check: 定时提醒检查
- system.health_check: 定时健康检查

### 管家自省事件
- butler.daily_reflection: 每日自省
- butler.weekly_review: 每周复盘
- butler.monthly_platform_review: 月度平台评估

## 触发决策框架
当事件发生时，判断：
1. 这个事件与哪些职责相关？
2. 是否需要采取行动？
3. 行动的优先级是什么？
4. 应该用什么方式执行？
```

### 3.3 职责定义示例

```yaml
# duties/information_equity.yaml

id: duty_information_equity
name: 信息平权
description: 确保信息公平触达每个需要的人
priority: 1
enabled: true

trigger_conditions:
  - event: thread.created
    filters:
      - category: [tech_decision, action_item]
    action: check_interested_users
  - event: message.received
    filters:
      - contains_action_item: true
    action: extract_and_assign_tasks

execution_steps:
  1_identify_stakeholders:
    description: 识别利益相关者
    method: |
      分析消息涉及的 topic，找出：
      - 参与讨论的人
      - 被提及但未参与的人
      - 可能感兴趣但未被提及的人（基于历史行为）

  2_check_notification_need:
    description: 判断是否需要通知
    method: |
      检查：
      - 信息是否重要（决策、待办、参考数据）
      - 相关人是否已知晓
      - 是否有人订阅了相关话题

  3_send_notifications:
    description: 发送通知
    templates:
      - notification/new_decision.md
      - notification/action_assigned.md
    permission: L1

success_metrics:
  - name: notification_relevance
    measure: 用户反馈"有用"的比例
    target: ">80%"
  - name: coverage
    measure: 应知人数 vs 实际通知人数
    target: ">90%"
```

---

## 4. 任务识别与待办管理

### 4.1 任务识别触发

管家监控所有平台事件，自动识别任务创建机会：

| 触发场景 | 识别方法 | 示例 |
|----------|----------|------|
| 消息中提及任务 | 检测"@某人 + 动作词" | "@张三 把Redis搭一下" |
| 会议纪要生成 | 提取 action_items 字段 | "张三负责准备服务器" |
| 决策落地 | 检测 tech_decision 后续任务 | "决定用Redis，张三负责实施" |
| 用户明确请求 | 解析"帮我创建待办" | "帮我记一下周三前完成文档" |
| 模式识别 | 发现重复提及但无待办 | 多次讨论"配置文档"但未创建 |

### 4.2 多人任务分配

采用 RACI 模型：

| 角色 | 代码 | 说明 | 待办权限 |
|------|------|------|----------|
| **责任人** | `responsible` | 主要执行者 | 可编辑、可完成、可添加协作者 |
| **协作者** | `collaborator` | 协助执行 | 可查看、可评论 |
| **咨询者** | `consulted` | 需咨询意见 | 可查看、可评论 |
| **通知者** | `informed` | 仅需知晓 | 仅可查看 |

### 4.3 任务要素确认

```yaml
# skills/task_extraction.md

## 必需要素
- title: 任务标题
- assignee: 责任人（必须明确）
- due_date: 截止时间（可选，缺失时询问）

## 可选要素
- priority: 优先级
- resources: 所需资源
- dependencies: 前置依赖
- deliverables: 交付物
- completion_criteria: 完成标准

## 缺失要素处理
当要素缺失时：
1. 尝试从上下文推断
2. 无法推断时，生成确认问题：
   - 私聊责任人（敏感信息）
   - 群内询问（公开任务）
   - 待办卡片确认按钮

## 确认提示词
任务"{title}"已创建，以下信息需要确认：
- 截止时间：{suggested_due_date}？
- 所需资源：{suggested_resources}？
- 交付物：{suggested_deliverables}？

请确认或修改以上信息。
```

---

## 5. 交互学习机制

### 5.1 从交互中学习

```
用户请求 → 管家执行 → 观察结果 → 提取模式 → 更新职责/技能
```

**示例：从汇总请求学习**

```
第一次：
用户：帮我汇总产品群这周关于支付的讨论
管家：[生成文本汇总]
用户：能用表格形式吗？
管家：[重新生成表格形式]
→ 记录偏好：用户偏好表格形式

第二次（同一用户）：
用户：帮我汇总这周的讨论
管家：[自动使用表格形式]
→ 管家已学习用户偏好

群体学习：
当 3+ 用户选择相同偏好时：
管家提议：将"表格形式"设为汇总默认格式？
→ 更新 skills/weekly_digest.md
```

### 5.2 主动询问推荐

每次完成用户请求后，管家评估是否需要询问后续：

```python
# 交互后评估提示词

你刚完成了用户的请求：{request}
执行结果：{result}

请判断：
1. 这是一次性需求还是可能需要重复？
2. 是否发现用户有潜在持续需求？
3. 是否有相关服务可以推荐？

如果发现机会，在回复末尾添加：
{
  "suggestions": [
    {
      "type": "schedule_task",
      "description": "每周一自动汇总",
      "user_benefit": "不用每次手动请求"
    }
  ],
  "questions": [
    "是否需要我每周自动为您汇总？"
  ]
}
```

### 5.3 事件触发的主动沟通

```yaml
# 示例：新待办发布通知

触发：user.todo_created
条件：visibility != 'private'

行动：
  1. 查询订阅该用户的人
  2. 生成通知：
     "您关注的{user}发布了新待办：{title}"
  3. 提供快捷操作：
     - 查看详情
     - 协助完成
     - 不感兴趣
```

---

## 6. 自省与平台迭代

### 6.1 核心理念：AI管家是一个会自省的智能体

AI管家的核心特质是**自省**——像一个超强的人类运维一样，通过经验积累、自我总结、持续改进，变得越来越强。

```
┌─────────────────────────────────────────────────────────────────┐
│                    AI 管家自省循环                               │
│                                                                 │
│   ┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐  │
│   │  执行   │ ──→ │  观察   │ ──→ │  反思   │ ──→ │  改进   │  │
│   │ Action  │     │ Observe │     │ Reflect │     │ Improve │  │
│   └─────────┘     └─────────┘     └─────────┘     └─────────┘  │
│        ↑                                               │        │
│        └───────────────────────────────────────────────┘        │
│                         持续迭代                                 │
└─────────────────────────────────────────────────────────────────┘
```

**自省的层次**：

| 层次 | 说明 | 示例 |
|------|------|------|
| **行为优化** | 优化已有行为的效果 | 调整通知时机，提高打开率 |
| **模式发现** | 从数据中发现新模式 | 发现"周末提醒打扰多"的模式 |
| **框架扩展** | 在现有框架内新增能力 | 新增信息类别、新增任务类型 |
| **能力发现** | 发掘现有工具的新用法 | 用搜索工具实现相似推荐 |
| **自我演化** | 优化提示词、沉淀经验 | 更新 duties/*.yaml |

### 6.2 自省周期

| 周期 | 时间 | 内容 | 输出 |
|------|------|------|------|
| **实时反思** | 每次行动后 | 思考还能提供什么服务 | 即时建议 |
| **每日自省** | 凌晨 3:00 | 回顾过去24小时行为效果 | insights/daily/ |
| **每周复盘** | 周一凌晨 4:00 | 汇总一周数据，优化职责 | insights/weekly/ |
| **月度评估** | 每月1日 | 平台整体评估，改进建议 | insights/monthly/ |

### 6.3 实时反思：还能为用户做什么

**核心理念**：完成指定工作后，管家会思考"我还能为用户提供什么服务？"

```
┌─────────────────────────────────────────────────────────────────┐
│  用户发言："Redis 集群部署方案讨论"                              │
│                                                                 │
│  管家处理流程：                                                  │
│  1. 分析发言 → 分类为 tech_decision                             │
│  2. 创建话题线索                                                │
│  3. 识别当事人 → 张三、李四                                     │
│  4. ✅ 基本任务完成                                             │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  实时反思：我还能做什么？                                  │  │
│  │                                                           │  │
│  │  思考过程：                                                │  │
│  │  1. 这个话题涉及什么？→ Redis 部署                        │  │
│  │  2. 有相关的历史讨论吗？→ 搜索相似话题                    │  │
│  │  3. 有相关的待办吗？→ 查询关联待办                        │  │
│  │  4. 谁可能感兴趣？→ 分析关注 Redis 的人                   │  │
│  │  5. 需要创建待办吗？→ 检测是否有行动项                    │  │
│  │                                                           │  │
│  │  候选建议：                                                │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │ 💡 我发现以下可能对您有帮助：                        │  │  │
│  │  │                                                     │  │  │
│  │  │ 1. 📋 创建待办：张三负责搭建测试环境                 │  │  │
│  │  │ 2. 👀 订阅话题：李四可能想关注这个讨论               │  │  │
│  │  │ 3. 📚 相关内容：上周讨论过"Redis 连接池配置"         │  │  │
│  │  │ 4. 👥 推荐关注：王五熟悉 Redis，可能感兴趣           │  │  │
│  │  │ 5. ⏰ 设置提醒：在 3 天后提醒跟进                    │  │  │
│  │  │                                                     │  │  │
│  │  │ 选择需要的操作，或忽略。                             │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.4 每日自省

```python
# 每日自省提示词

## 输入数据
- 今日执行的任务列表
- 用户反馈统计
- 任务成功率
- 异常事件
- 新发现的信息类别（如有）
- 新发现的任务类型（如有）

## 分析问题
1. 哪些任务执行效果好？为什么？
2. 哪些任务效果差？原因是什么？
3. 发现了什么新模式？
4. 有什么可以优化的？
5. 是否发现了新的信息类别？
6. 是否发现了新的任务类型？
7. 候选建议的接受率如何？

## 输出格式
{
  "date": "2026-03-02",
  "summary": {
    "tasks_executed": 45,
    "success_rate": 0.92,
    "user_satisfaction": 4.3,
    "suggestion_acceptance_rate": 0.65
  },
  "patterns_discovered": [
    {"pattern": "技术决策通知打开率更高", "confidence": 0.85}
  ],
  "new_categories_found": [
    {"category": "技术分享", "evidence_count": 5, "description": "技术文章分享讨论"}
  ],
  "new_task_types_found": [
    {"task_type": "代码审查", "evidence_count": 3, "description": "PR 代码审查请求"}
  ],
  "optimizations": [
    {"target": "duties/reminder.yaml", "change": "增加用户偏好检查", "reason": "减少投诉"}
  ],
  "lessons_learned": [
    {"lesson": "周末提醒打扰较多", "action": "建议增加免打扰设置"}
  ]
}
```

### 6.5 框架扩展能力

管家**不能修改基础框架**（core/），但可以在现有框架内**新增能力**：

| 扩展类型 | 说明 | 需要审批 |
|----------|------|----------|
| **新增信息类别** | 发现新的消息分类 | L2（事后汇报） |
| **新增任务类型** | 发现新的待办类型 | L2（事后汇报） |
| **新增提示词模板** | 添加新的技能模板 | L1（无需审批） |
| **新增关系类型** | 发现新的图谱关系 | L1（无需审批） |
| **优化提示词** | 修改 duties/*.yaml | L1（无需审批） |
| **新增扩展脚本** | 添加 extensions/*.yaml | L2（事后汇报） |

```yaml
# 新增信息类别示例
# 由管家发现并建议新增
new_category_proposal:
  category: "tech_share"
  display_name: "技术分享"
  description: "技术文章、博客、视频的分享讨论"
  evidence:
    - thread_id: "xxx-001"
      message: "分享一篇关于 Redis 集群的好文章..."
    - thread_id: "xxx-002"
      message: "推荐这个 PostgreSQL 调优视频..."
  confidence: 0.85
  suggested_at: "2026-03-02"
  status: "pending_review"  # 需要管理员确认
```

### 6.6 月度平台评估

```markdown
# RippleFlow 月度评估报告

## 一、管家自我沉淀

### 职责执行效果
| 职责 | 执行次数 | 成功率 | 用户满意度 | 趋势 |
|------|----------|--------|------------|------|
| 信息平权 | 234 | 92% | 4.2/5 | ↑ |
| 任务跟踪 | 156 | 88% | 4.0/5 | → |
| 问答辅助 | 89 | 95% | 4.5/5 | ↑ |

### 最佳实践沉淀
1. **技术决策通知时机**：周一上午打开率最高
   - 已应用：调整定时任务时间

### 失败教训
1. **过度推送导致打扰**：某用户投诉提醒过多
   - 已改进：增加用户偏好设置

### 提示词优化记录
| 日期 | 文件 | 变更 | 效果 |
|------|------|------|------|
| 03-05 | duties/reminder.yaml | 增加用户偏好检查 | 投诉减少 30% |

## 二、框架扩展建议

### 新增信息类别建议
| 类别 | 证据数 | 置信度 | 状态 |
|------|--------|--------|------|
| 技术分享 | 15 | 0.85 | 待审批 |
| 代码审查 | 8 | 0.72 | 待审批 |

### 新增任务类型建议
| 类型 | 证据数 | 说明 |
|------|--------|------|
| Code Review | 12 | PR 代码审查请求 |
| 文档编写 | 7 | 文档撰写任务 |

## 三、平台改进建议

### 功能优化建议
| 建议 | 原因 | 优先级 |
|------|------|--------|
| 增加"免打扰时段"设置 | 3位用户反馈夜间打扰 | 中 |
| 任务依赖关系可视化 | 多次出现阻塞未及时发现 | 高 |
| 支持外部日历同步 | 用户希望待办同步到日历 | 中 |

## 四、下月重点
1. 优化任务识别准确率
2. 增加用户偏好设置入口
3. 审批新增信息类别
```

---

## 7. 扩展机制

### 7.1 扩展类型

| 类型 | 路径 | 说明 |
|------|------|------|
| **自定义报告** | extensions/reports/ | 自定义报告模板 |
| **外部集成** | extensions/webhooks/ | 与外部系统对接 |
| **自定义分析** | extensions/analyzers/ | 特殊分析逻辑 |

### 7.2 扩展规范

```yaml
# 扩展定义文件示例
id: weekly_team_summary
name: 团队周报
version: 1.0
trigger: system.report_time
schedule: "0 9 * * 1"  # 每周一 9:00

input_schema:
  team_id: string
  date_range: object

output_format: markdown

permission_level: L2

handler: |
  # 扩展执行逻辑
  1. 获取团队成员列表
  2. 汇总各成员本周贡献
  3. 生成格式化报告
  4. 发送到指定群
```

### 7.3 扩展索引

```yaml
# extensions/index.yaml

extensions:
  reports:
    - id: weekly_team_summary
      name: 团队周报
      enabled: true
    - id: monthly_contributor_rank
      name: 月度贡献排行
      enabled: true

  webhooks:
    - id: slack_notifier
      name: Slack通知
      enabled: false
    - id: calendar_sync
      name: 日历同步
      enabled: true

  analyzers:
    - id: sentiment_analyzer
      name: 情感分析
      enabled: false
```

---

## 8. 权限层级

| 层级 | 名称 | 能力范围 | 审批要求 |
|------|------|----------|----------|
| L0 | 只读观察 | 读取系统状态、统计数据 | 无需审批 |
| L1 | 轻度行动 | 个人通知、低频任务、微调提示词 | 无需审批 |
| L2 | 中度行动 | 群消息、中频任务、注册脚本 | 事后汇报 |
| L3 | 高度行动 | 修改配置、访问敏感数据、高频任务 | 事前审批 |

---

## 8.1 nullclaw Memory 三层架构

nullclaw 提供三层记忆系统，支持管家的长期记忆和知识沉淀：

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

**配置示例**：

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
    "compaction": {
      "schedule": "0 2 * * *",
      "target_layer": "L2"
    },
    "hygiene": {
      "schedule": "0 3 * * 0",
      "remove_duplicates": true
    }
  }
}
```

---

## 8.2 多 Agent 协作架构

nullclaw 支持多 Agent 协作，RippleFlow 可配置多个专家 Agent：

```
┌─────────────────────────────────────────────────────────────────┐
│                    多 Agent 协作架构                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  rippleflow_butler（主管家）                                     │
│  ─────────────────────────                                      │
│  • 协调其他 Agent                                               │
│  • 日常运营任务                                                 │
│  • 用户交互入口                                                 │
│                                                                 │
│  rippleflow_qa（问答专家）                                      │
│  ─────────────────────────                                      │
│  • 处理复杂问答请求                                             │
│  • 知识检索优化                                                 │
│  • FAQ 维护（生成/更新/合并/质量评估）                          │
│  • FAQ Routine A/B/C/D 执行（见 FAQ PRD §4.3）                 │
│                                                                 │
│  rippleflow_analyst（分析专家）                                 │
│  ─────────────────────────                                      │
│  • 数据分析与报告生成                                           │
│  • 趋势发现                                                    │
│  • 统计报表                                                    │
│                                                                 │
│  rippleflow_coordinator（协调专家）                             │
│  ─────────────────────────                                      │
│  • 任务分配与跟踪                                               │
│  • 资源协调                                                    │
│  • 待办提醒                                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Agent 配置示例**：

```json
{
  "agents": [
    {
      "id": "rippleflow_butler",
      "name": "主管家",
      "role": "coordinator",
      "model": "claude-sonnet-4-6",
      "tools": ["shell_execute", "http_request"],
      "delegates_to": ["rippleflow_qa", "rippleflow_analyst", "rippleflow_coordinator"]
    },
    {
      "id": "rippleflow_qa",
      "name": "问答专家",
      "role": "specialist",
      "model": "claude-sonnet-4-6",
      "tools": ["shell_execute"],
      "expertise": ["qa", "search", "knowledge"]
    },
    {
      "id": "rippleflow_analyst",
      "name": "分析专家",
      "role": "specialist",
      "model": "claude-sonnet-4-6",
      "tools": ["shell_execute", "file_write"],
      "expertise": ["analytics", "reports", "trends"]
    },
    {
      "id": "rippleflow_coordinator",
      "name": "协调专家",
      "role": "specialist",
      "model": "claude-sonnet-4-6",
      "tools": ["shell_execute", "http_request"],
      "expertise": ["tasks", "todos", "reminders"]
    }
  ]
}
```

---

## 8.3 Autonomy 自主控制模块

nullclaw 提供自主控制机制，定义管家的自主行为边界：

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

**配置示例**：

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

---

## 9. 数据库设计

详见 `02_database_ddl.sql` (PostgreSQL) 或 `02b_database_ddl_sqlite.sql` (SQLite)，关键表：

- `butler_tasks`: 管家任务记录
- `butler_experience`: 管家经验知识库
- `butler_proposals`: L3 提案审批
- `butler_interaction_logs`: 交互记录（用于学习）
- `personal_todos`: 个人待办
- `todo_participants`: 任务参与人
- `user_subscriptions`: 用户订阅

---

## 10. API 设计

详见 `03_api_reference.yaml`，关键接口：

- `/api/v1/butler/*`: 管家管理接口
- `/api/v1/todos/*`: 待办管理接口
- `/api/v1/subscriptions/*`: 订阅管理接口

---

## 11. 演化路线图

### Phase 1：基础能力（v0.5）
- [x] 提示词分级架构设计
- [x] 核心提示词定义
- [x] 基本职责定义
- [x] 任务识别与待办创建
- [x] 订阅/关注系统
- [x] FAQ 知识库系统设计（数据表 + API + Prompt 模板）

### Phase 2：交互学习（v0.6）
- [ ] 交互偏好学习
- [ ] 主动询问推荐
- [ ] 事件触发沟通
- [ ] 用户偏好持久化
- [ ] FAQ 自动生成（Routine A：热点话题 FAQ 化）
- [ ] FAQ 质量反馈学习（根据用户满意度评分优化生成策略）

### Phase 3：自省演化（v0.7）
- [ ] 每日自省机制
- [ ] 每周复盘
- [ ] 月度平台评估
- [ ] 提示词自动优化

### Phase 4：扩展生态（v0.8）
- [ ] 扩展机制完善
- [ ] 自定义报告模板
- [ ] 外部系统集成
- [ ] 开放扩展 API

---

## 附录 A：冷启动提示词清单

| 文件 | 用途 | 可修改 |
|------|------|--------|
| core/identity.md | 身份定位 | ❌ 不可修改 |
| core/principles.md | 行为准则 | ❌ 不可修改 |
| core/permissions.md | 权限边界 | ❌ 不可修改 |
| core/triggers.md | 触发框架 | ❌ 不可修改 |
| duties/*.yaml | 职责定义 | ✅ 管家可优化 |
| skills/*.md | 技能模板 | ✅ 管家可优化 |
| insights/*.yaml | 自省沉淀 | ✅ 管家维护 |

---

## 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| 1.0 | 2026-03-02 | 初版架构设计 |
| 1.1 | 2026-03-02 | 新增交互学习机制 |
| 2.0 | 2026-03-02 | 重构：提示词分级架构、自省与平台迭代机制 |