# 01 系统架构设计文档

## 0. 核心定位

### 0.1 系统定位

RippleFlow 是一个**信息态势感知系统**，帮助团队成员快速掌握团队全局态势。

**核心价值链**：

```
群聊消息 → 信息挖掘 → 知识沉淀 → 态势感知 → 线索发现 → 决策支持
```

### 0.2 用户核心问题

用户通过系统希望能够快速回答：

| 问题类型 | 具体问题 | 系统能力 |
|----------|----------|----------|
| **发生了什么** | 团队最近发生了哪些重要事情？ | 全局索引、热点话题 |
| **和谁相关** | 这件事涉及哪些人？ | 知识图谱、当事人识别 |
| **状态如何** | 这件事解决了吗？进展如何？ | 状态追踪、闭环检测 |
| **瓶颈在哪** | 哪些事情卡住了？为什么？ | 未闭环分析、阻塞识别 |
| **如何解决** | 有什么解决方案？需要做什么？ | 决策记录、待办跟踪 |
| **资源需求** | 需要什么资源？谁来提供？ | 资源提取、依赖分析 |
| **支持关系** | 谁需要谁的支持？协作关系？ | 协作图谱、支持链 |

### 0.3 信息链条

系统主动挖掘和呈现**信息链条**：

```
时间线 → 人物 → 事件 → 状态 → 关联 → 瓶颈 → 资源 → 支持
```

**示例信息链**：

```
2026-03-01
    └── 张三 在产品群提出
            └── "Redis 集群部署方案讨论"
                    ├── 状态: 进行中
                    ├── 参与: 李四、王五、赵六
                    ├── 决策: 使用 Redis Cluster
                    ├── 待办: 张三负责搭建测试环境（进行中）
                    ├── 瓶颈: 测试服务器未到位
                    ├── 需要资源: 3台测试服务器
                    └── 支持: 张三需要运维团队（赵六）支持
```

### 0.4 态势感知能力

| 能力 | 说明 | 实现方式 |
|------|------|----------|
| **全局视角** | 一眼看懂团队态势 | Dashboard 全局视图 |
| **线索挖掘** | 主动发现新线索 | AI 管家分析 |
| **关联穿透** | 人、事、物的关联 | 知识图谱 |
| **瓶颈预警** | 识别卡点和阻塞 | 状态分析 |
| **资源可视化** | 谁需要什么资源 | 结构化提取 |
| **协作图谱** | 谁支持谁的关系 | 关系挖掘 |

## 1. 技术栈

| 层次 | 技术选型 | 版本 | 说明 |
|------|----------|------|------|
| Web 框架 | FastAPI | ≥ 0.111 | 异步，自动生成 OpenAPI 文档 |
| 任务队列 | Celery + 内存队列 | Celery 5.x | 异步处理消息流水线 |
| 数据库 | **PostgreSQL** 或 **SQLite** | PG ≥ 15 / SQLite ≥ 3.38 | 见下方数据库选型说明 |
| 缓存 | **内存缓存** 或 **Redis** | cachetools / Redis ≥ 7.0 | 见下方缓存选型说明 |
| LLM | 公司内部部署 | — | 全中文场景优化，无 API 调用成本 |
| 部署 | Docker Compose | — | 开发/生产一致环境 |
| 认证 | python-ldap3 + JWT | — | LDAP 鉴权 + 无状态 Token |
| 前端 | Vue 3 + TypeScript | — | Web Dashboard |
| E2E 测试 | Playwright | ≥ 1.44 | 自动化 UI 测试 |

### 1.1 数据库选型

系统支持两种数据库方案，可根据团队规模选择：

| 场景 | 推荐数据库 | 原因 |
|------|------------|------|
| **小型团队** (< 20人) | SQLite | 零配置、单文件、易备份 |
| **大型团队** / 高并发 | PostgreSQL | 支持并发写入、连接池 |
| **复杂查询分析** | PostgreSQL | 窗口函数、CTE、JSONB 索引 |
| **快速原型开发** | SQLite | 无需安装数据库服务 |

**DDL 文件对应**：
- PostgreSQL: `docs/02_database_ddl.sql`
- SQLite: `docs/02b_database_ddl_sqlite.sql`

**SQLite 特性说明**：
- 启用 WAL 模式支持多读单写
- 使用 FTS5 扩展实现全文搜索
- UUID 由应用层生成 (`uuid.uuid4()`)
- JSON 字段存储为 TEXT，使用 SQLite 内置 JSON 函数

**迁移路径**：
```
SQLite (初期) ──→ 系统压力增大 ──→ PostgreSQL (升级)
```
数据迁移脚本位于 `scripts/migrate_sqlite_to_pg.py`（待实现）。

---

## 2. 组件架构图

```
┌───────────────────────────────────────────────────────────────────────┐
│  Client Layer                                                          │
│                                                                       │
│  ┌─────────────────────────┐    ┌──────────────────────────────────┐  │
│  │  Web Dashboard (Vue 3)  │    │  聊天机器人（已有系统）           │  │
│  │  - 知识库浏览            │    │  - 自然语言查询                  │  │
│  │  - 搜索问答              │    │  - 待办/参考数据查询              │  │
│  │  - 敏感授权              │    │  - 纪要生成触发                  │  │
│  │  - 当事人修改            │    │                                  │  │
│  │  - 管理后台              │    │                                  │  │
│  └────────────┬────────────┘    └──────────────┬───────────────────┘  │
└───────────────┼──────────────────────────────┼──────────────────────┘
                │ HTTPS/REST                   │ POST /api/v1/bot/query
                ▼                              ▼
┌───────────────────────────────────────────────────────────────────────┐
│  API Layer (FastAPI)                                                   │
│                                                                       │
│  ┌──────────────┐  ┌─────────────────┐  ┌───────────────────────┐    │
│  │ AuthRouter   │  │ WebhookRouter   │  │ APIv1Router           │    │
│  │ /auth/*      │  │ /webhook/*      │  │ /api/v1/*             │    │
│  │              │  │                 │  │                       │    │
│  │ - SSO 回调   │  │ - 消息接收       │  │ - threads             │    │
│  │ - JWT 签发   │  │ - 签名验证       │  │ - search / qa         │    │
│  │ - 白名单检查  │  │ - 入队          │  │ - reference           │    │
│  └──────────────┘  └─────────────────┘  │ - action-items        │    │
│                                         │ - sensitive           │    │
│  ┌────────────────────────────────────┐  │ - notifications       │    │
│  │ AdminRouter /admin/*               │  │ - summarize           │    │
│  │ - whitelist / categories           │  └───────────────────────┘    │
│  │ - sensitive overrides / stats      │                               │
│  └────────────────────────────────────┘  ┌───────────────────────┐    │
│                                          │ BotRouter             │    │
│                                          │ /api/v1/bot/*         │    │
│                                          │ - 自然语言查询入口     │    │
│                                          │ - 意图识别            │    │
│                                          └───────────────────────┘    │
│  Middleware: JWTAuthMiddleware / RateLimitMiddleware / LogMiddleware   │
└──────────────────────────┬────────────────────────────────────────────┘
                           │
          ┌────────────────┼────────────────────┐
          ▼                ▼                    ▼
┌─────────────────────┐  ┌──────────────────┐  ┌──────────────────────┐
│  Service Layer      │  │  缓存层          │  │  LLM API             │
│                     │  │                  │  │                      │
│  MessageService     │  │  - 任务队列      │  │  (公司内部部署)       │
│  ThreadService      │  │  - 会话 Token    │  │                      │
│  SearchService      │  │  - 搜索缓存(5min) │  │                      │
│  SensitiveService   │  │  - 通知计数       │  │                      │
│  AuthService        │  └──────────────────┘  └──────────────────────┘
│  NotifyService      │
│  AdminService       │
│  LLMService         │
│  BotAdapterService  │  ← 新增：机器人请求处理
│  ChatToolService    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────────────┐
│  PostgreSQL                                                          │
│                                                                     │
│  messages               chat_rooms            chat_users            │
│  topic_threads          message_thread_links  thread_summary_history│
│  thread_modifications   reference_data_items  sensitive_auth        │
│  user_whitelist         category_definitions  notifications         │
│  processing_jobs                                                    │
└─────────────────────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Celery Workers (独立进程)                                        │
│                                                                   │
│  ProcessingPipeline      消息 5 阶段处理（Stage 0–4）              │
│  SummaryUpdateWorker     ❌ 已移除（摘要更新移交 nullclaw）         │
│  NotificationWorker      App 内通知推送                            │
│  SyncToChatWorker        修改结果同步至聊天群（用户确认后）          │
│  EscalationWorker        敏感授权超时升级                           │
│                                                                   │
│  注：定时任务由 nullclaw cron 调度，不在此处运行                    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. 消息处理流水线（Stage 0–4）+ nullclaw 摘要更新

```
Webhook 接收消息
      │
      ▼
┌─────────────────────────────────────────────────────────────────┐
│  Stage 0: 敏感检测                                               │
│                                                                 │
│  LLM 判断：涉及隐私/人事/纠纷？                                   │
│  → 有：status=sensitive_pending，通知当事人，设置升级时间(7天)    │
│  → 无：继续                                                     │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  Stage 1: 噪声过滤                                               │
│                                                                 │
│  LLM 判断：有知识价值吗？                                         │
│  → 噪声（"ok"/"哈哈"/"收到"）：status=skipped，停止              │
│  → 有价值：继续                                                  │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  Stage 2: 分类                                                   │
│                                                                 │
│  LLM 输入：消息 + 最近5条上下文 + 9类别描述                       │
│  输出：[{category, confidence}]，confidence ≥ 0.6 的类别通过      │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  Stage 3: 话题线索匹配                                           │
│                                                                 │
│  PostgreSQL 全文检索：时间窗口内相似话题（Top-5）                 │
│  LLM 判断：extend 已有线索 | create 新线索                        │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  Stage 4: 结构化提取 + 当事人识别                                │
│                                                                 │
│  按类别提取结构化字段（decision/assignee/error_msg 等）           │
│  更新 topic_threads.stakeholder_ids                             │
│  reference_data → 同步写入 reference_data_items（主存储）        │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  平台流水线结束 → 事件推送至 nullclaw                             │
│                                                                 │
│  Stage 0–4 完成，消息存储并标记可检索                             │
│  HTTP POST 事件推送至 nullclaw：                                  │
│  { thread_id, category, new_message_ids[], is_new_thread }      │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  nullclaw 侧：增量摘要更新（策略层，不属于平台流水线）             │
│                                                                 │
│  LLM 输入：现有摘要 + 新消息内容 + 类别                           │
│  LLM 输出：更新摘要 + 状态变化 + 是否漂移                         │
│  调用 PUT /api/v1/threads/{id}/summary 写回                     │
│  漂移时：追加冲突说明，通知原决策当事人                            │
│  旧摘要归档到 thread_summary_history                             │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
                      摘要更新完成，可检索
```

---

## 4. 认证流程

```
用户访问 Web Dashboard
        │
        ▼
GET /auth/sso  →  重定向至企业 SSO 登录页
        │
        ▼ 登录成功回调
GET /auth/callback?token=xxx
        │
        ├── 1. 验证 SSO Token 合法性
        ├── 2. 从 LDAP 获取用户信息（ldap_user_id, display_name, email）
        ├── 3. 查询 user_whitelist 表
        │       ├── 不存在 → 403，提示「请联系管理员申请」
        │       └── 存在且 is_active=true → 继续
        ├── 4. 签发 JWT（payload: user_id, display_name, role, exp）
        └── 5. 重定向至 /dashboard，携带 JWT（HttpOnly Cookie）
```

---

## 5. 数据流：当事人修改同步（显式确认）

```
当事人在 Web Dashboard 修改话题线索摘要
        │
        ▼
PUT /api/v1/threads/{id}/summary
        │
        ├── 1. 验证 JWT，确认是当事人（user_id in thread.stakeholder_ids）
        ├── 2. 保存修改到 thread_modifications（修改前/后/原因）
        ├── 3. 更新 topic_threads.summary
        ├── 4. 返回修改结果，前端弹出确认框：
        │       「是否同步到群聊？」
        │       ├── 用户选择「不同步」→ 流程结束
        │       └── 用户选择「同步」→ 继续
        │
        └── 5. 异步：SyncToChatWorker
                  │
                  └── 调用聊天工具 API
                      发送到 thread.primary_room_id
                      格式：「[{用户名}] 修正了「{话题}」: {修正说明}」
```

---

## 6. 数据流：敏感内容授权（含升级机制）

```
Stage 0 检测到敏感内容
        │
        ├── 确定 sensitivity_level（L1/L2/L3，LLM 判定）
        ├── 创建 sensitive_authorizations 记录
        ├── decisions = {每位当事人: "pending"}
        ├── escalation_after = L1:3天 / L2:5天 / L3:7天
        └── 异步推送 App 内通知给每位当事人
                  │
              当事人操作
         ┌────────┼────────┐
         ▼        ▼        ▼
      拒绝      授权     脱敏后授权
         │        │        │
         ▼        ▼        ▼
    立即拒绝   更新decisions  保存脱敏版本
    永不处理   检查授权阈值    L1可立即入库
              │
        达到授权阈值（L1≥1人 / L2>50% / L3全员）
              │
              ▼
    消息重入处理队列（Stage 1）


┌─────────────────────────────────────────────────────────────────┐
│  敏感授权升级流程（EscalationWorker，每日检查）                   │
│                                                                 │
│  条件：NOW() > created_at + escalation_after                    │
│        AND overall_status = 'pending'                           │
│                                                                 │
│  动作：                                                         │
│  1. 通知管理员：「以下敏感授权已超过 L1:3/L2:5/L3:7 天，请介入」 │
│  2. 通知当事人：「授权请求即将升级至管理员处理」                   │
│  3. 记录 escalated_at、escalated_to                             │
│                                                                 │
│  详细分级策略见 §38 敏感授权分级机制                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## 7. 搜索/问答数据流

```
用户提问：「Redis 连接超时怎么处理」
        │
        ▼
POST /api/v1/qa
        │
        ├── 1. LLM 提取检索关键词 → ["Redis", "连接", "超时"]
        │
        ├── 2. PostgreSQL 全文检索
        │       WHERE category IN (user_filter or all)
        │         AND last_message_at >= NOW() - INTERVAL '{window} days'
        │         AND search_vector @@ to_tsquery('simple', keywords)
        │       ORDER BY ts_rank DESC LIMIT 10
        │
        │       注：search_vector 已包含 structured_data 中的关键字段
        │
        ├── 3. 将 Top-10 话题线索的 summary 构建上下文
        │
        ├── 4. LLM：基于摘要回答问题，标注来源 thread_id
        │
        └── 5. 返回：{answer, sources: [{thread_id, title, category, last_active}]}
```

---

## 8. 机器人交互数据流（新增）

```
用户在群聊中 @机器人 发送自然语言查询
        │
        ▼
聊天机器人 → POST /api/v1/bot/query
        │
        ├── 请求体：{query, user_id, room_id, reply_to_msg_id?}
        │
        ▼
┌─────────────────────────────────────────────────────────────────┐
│  BotAdapterService 处理流程                                      │
│                                                                 │
│  1. 意图识别（LLM）                                              │
│     输入：用户自然语言                                           │
│     输出：{intent, confidence, entities}                         │
│     意图类型：search | action_items | reference | summarize      │
│                                                                 │
│  2. 权限验证                                                     │
│     验证 user_id 是否在白名单                                    │
│     按提问者权限过滤查询结果                                      │
│                                                                 │
│  3. 路由到对应 Service                                           │
│     ┌─────────────┬─────────────────────────────────┐           │
│     │ 意图        │ 调用                            │           │
│     ├─────────────┼─────────────────────────────────┤           │
│     │ search      │ SearchService.answer_question   │           │
│     │ action_items│ ThreadService.list_threads      │           │
│     │ reference   │ SearchService.find_reference    │           │
│     │ summarize   │ ThreadService.generate_summary  │           │
│     └─────────────┴─────────────────────────────────┘           │
│                                                                 │
│  4. 响应格式化                                                   │
│     将 API 结果格式化为群聊卡片消息                               │
│     包含：标题、摘要、来源链接、追问建议                          │
└─────────────────────────────────────────────────────────────────┘
        │
        ▼
返回格式化响应 → 机器人回复到群聊
```

### 8.1 支持的自然语言示例

| 用户说 | 识别意图 | 调用 API |
|--------|----------|----------|
| "Redis 连接池怎么配置" | search | `POST /api/v1/qa` |
| "我有什么待办" | action_items | `GET /api/v1/action-items?assignee=me` |
| "prod 环境的 Redis 地址是多少" | reference | `GET /api/v1/reference?env=prod&kw=Redis` |
| "生成今天产品群的会议纪要" | summarize | `POST /api/v1/summarize` |
| "上周讨论了什么重要的事" | search | `POST /api/v1/qa` (带时间过滤) |

### 8.2 机器人响应示例

```
🤖 找到 2 条相关记录：

📌 [技术决策] Redis 连接池配置方案
   决定使用 Lettuce，最大连接数 100，超时 5s
   👤 张三、李四 | 📅 2026-02-15

📌 [参考信息] Redis 生产环境配置
   prod-redis.internal:6379，密码见 Vault
   👤 王五 | 📅 2026-02-20

💬 回复此消息可追问或查看详情
💡 您也可以说："详细说说第一条" 或 "还有其他相关内容吗？"
```

---

## 9. 部署结构（Docker Compose）

```yaml
services:
  db:         # PostgreSQL 15 或 SQLite（轻量场景）
  redis:      # Redis 7（可选，仅用于缓存）
  api:        # FastAPI（uvicorn，多进程）
  worker:     # Celery Worker（消息处理流水线）
  nullclaw:   # nullclaw Agent（AI 管家 + 定时任务）
  frontend:   # Vue 3 静态文件（Nginx）
```

**变更说明**：

| 服务 | 原设计 | 新设计 |
|------|--------|--------|
| `beat` | Celery Beat（定时任务） | **删除**，由 nullclaw cron 替代 |
| `nullclaw` | 无 | **新增**，运行 AI 管家 Agent |
| `redis` | 必需（消息队列 + 缓存） | **可选**，仅用于缓存 |

所有服务通过内网通信，仅 Nginx（前端+API 反代）对内网暴露端口。

---

## 10. 接口边界定义

### 10.1 外部接口

| 方向 | 接口 | 说明 |
|------|------|------|
| 聊天工具 → RippleFlow | `POST /webhook/message` | 推送新消息 |
| RippleFlow → 聊天工具 | `POST {CHAT_TOOL_API}/send` | 发送回复（用户确认后） |
| 聊天机器人 → RippleFlow | `POST /api/v1/bot/query` | 自然语言查询入口 |
| AI 管家 → 聊天工具 | `POST {CHAT_TOOL_API}/send` | 主动推送快报/提醒 |
| **RippleFlow → nullclaw** | `POST {NULLCLAW_GATEWAY}/webhook/rippleflow` | **事件推送（新增）** |

### 10.2 内部服务接口（Python Protocol）

见 `04_service_interfaces.md`

### 10.3 前端 REST API

见 `03_api_reference.yaml`（OpenAPI 3.0）

---

## 11. AI 管家数据流（nullclaw 调度）

AI 管家由 **nullclaw** 运行，负责主动推送和知识库健康维护。

### 11.1 架构变更说明

```
原设计（已废弃）：
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ Celery Beat │ ──→ │ AIButlerSvc │ ──→ │ 聊天工具    │
└─────────────┘     └─────────────┘     └─────────────┘

新设计：
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ nullclaw    │ ──→ │ rf commands │ ──→ │ 聊天工具    │
│ cron/trigger│     │ (CLI)       │     │             │
└─────────────┘     └─────────────┘     └─────────────┘
```

### 11.2 每周知识快报流程

```
nullclaw cron (每周一 9:00)
        │
        ▼
执行 Routine: routine_weekly_review.md
        │
        ├── 1. 获取上周数据
        │       rf threads list --from last-week -o json
        │       rf todos list --completed-this-week -o json
        │       rf contribution leaderboard --period week -o json
        │
        ├── 2. 生成快报内容（LLM 处理）
        │
        ├── 3. 推送到群
        │       rf butler digest --room <room_id> --type weekly
        │
        └── 4. 记录任务
                rf butler tasks --log "weekly_digest completed"
```

### 11.3 待办到期提醒流程

```
nullclaw cron (每日 9:00)
        │
        ▼
执行 Routine: routine_todo_reminder.md
        │
        ├── 1. 查询今日到期待办
        │       rf todos list --due-today --status open -o json
        │
        ├── 2. 按责任人分组
        │
        ├── 3. 推送提醒到群
        │       @被分配者 您有 X 个待办即将到期
        │       列出具体待办
        │
        └── 4. 更新提醒计数
                action_item.reminder_count += 1
```

### 11.3 敏感授权实时状态更新

```
当事人授权/拒绝
        │
        ▼
SensitiveService.submit_decision()
        │
        ├── 1. 更新 decisions 状态
        │
        ├── 2. 通知其他当事人
        │       「张三 已授权，等待其他 2 人确认」
        │
        ├── 3. 全部授权后
        │       通知所有人「已全部授权，消息将入库」
        │       消息重入处理队列
        │
        └── 4. 任一拒绝后
                通知所有人「XXX 已拒绝，消息将不处理」
```

### 11.4 问答反馈收集流程

```
用户完成问答
        │
        ▼
前端显示反馈按钮
        │
        ├── 用户点击「有用」
        │       POST /api/v1/feedback
        │       {qa_session_id, is_helpful: true}
        │
        ├── 用户点击「无用」
        │       POST /api/v1/feedback
        │       {qa_session_id, is_helpful: false, comment: "..."}
        │
        ▼
FeedbackService.submit_qa_feedback()
        │
        ├── 1. 存储 qa_feedback 表
        │
        └── 2. 管家学习
                更新常见问题模式
                分析低分答案原因
```

### 11.5 管家自主学习流程

```
每日定时任务
        │
        ▼
AIButlerService.self_learning()
        │
        ├── 1. 分析问答反馈
        │       统计满意度趋势
        │       识别低分答案模式
        │
        ├── 2. 分析使用模式
        │       高峰时段
        │       常见问题类型
        │       快报打开率
        │
        ├── 3. 更新经验知识库
        │       butler_experience 表
        │       JSONB 格式存储
        │
        └── 4. 生成优化建议
                低分答案 → 建议人工修正
                冷门知识 → 建议推广
```

---

## 12. AI 管家架构（v2.0）

### 12.1 核心定位

AI 管家是 RippleFlow 平台的"灵魂"，通过**感知-决策-执行-自省**循环持续运营：

```
┌─────────────────────────────────────────────────────────────────┐
│                      AI 管家 (Butler)                            │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ 感知层      │  │ 决策层      │  │ 执行层      │             │
│  │ Observation │→ │ Decision    │→ │ Action      │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│        ↑                ↑                ↓                      │
│        └────────────────┴────────────────┘                      │
│                      自省反馈环                                  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────┐       │
│  │              提示词知识库 (Prompt KB)                │       │
│  │  core/ | duties/ | skills/ | insights/ | extensions/ │       │
│  └─────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

### 12.2 核心职责

| 职责 | 说明 |
|------|------|
| 信息平权 | 确保信息公平触达每个需要的人 |
| 智能推荐 | 发现有价值的信息并推荐给相关人员 |
| 总结提炼 | 将复杂信息转化为易理解的形式 |
| 问答辅助 | 帮助用户快速找到答案 |
| 任务跟踪 | 跟踪任务进度，确保不遗漏 |
| 及时提醒 | 在关键时刻提醒相关人员 |

### 12.3 提示词分级架构

```
butler_prompts/
├── core/          # 冷启动核心提示词（不可修改）
│   ├── identity.md
│   ├── principles.md
│   ├── permissions.md
│   └── triggers.md
├── duties/        # 职责定义（管家可优化）
├── skills/        # 技能模板（管家可优化）
├── insights/      # 自省沉淀（管家维护）
└── extensions/    # 扩展脚本（零代码新功能）
```

### 12.4 自省与平台迭代

| 周期 | 时间 | 内容 |
|------|------|------|
| 每日自省 | 凌晨 3:00 | 回顾行为效果，提取模式 |
| 每周复盘 | 周一凌晨 4:00 | 汇总数据，优化职责 |
| 月度评估 | 每月 1 日 | 平台整体评估，改进建议 |

### 12.5 主动服务清单

| 服务名称 | 触发条件 | 推送渠道 | 频率 |
|----------|----------|----------|------|
| 每周知识快报 | 定时（周一 9:00） | 主群推送 | 每周 |
| 待办到期提醒 | due_date - 1 天 | 群聊@提醒 | 每日检查 |
| 敏感授权状态更新 | 授权状态变化 | App 通知 + 群聊 | 实时 |
| 问答反馈请求 | 问答完成后 | Dashboard 提示 | 实时 |
| 知识库健康报告 | 每月 1 日 | Dashboard + 管理员 | 每月 |
| 孤儿线索检测 | 线索无关联消息 | 管理员通知 | 每周 |
| 摘要质量预警 | AI 置信度 < 0.6 | 当事人通知 | 实时 |

---

## 13. LLM 调用策略（补充）

### 13.1 模型降级策略

```
模型优先级链:
  glm-4-plus  (首选，质量最高)
      ↓ 降级条件满足
  glm-4-air   (一级降级，速度/成本平衡)
      ↓ 降级条件满足
  glm-4-flash (二级降级，基础可用)
      ↓ 全部失败
  抛出 LLMServiceError
```

### 13.2 降级触发条件

| 条件 | 触发动作 | 说明 |
|------|----------|------|
| 429 Rate Limit | 等待 2^n 秒后重试，3 次后降级 | 指数退避 |
| 30s 超时 | 直接降级到下一模型 | 避免长时间阻塞 |
| 500/502/503 | 等待 1 秒后重试，3 次后降级 | 服务端错误 |
| JSON 解析失败 | 重试 1 次，仍失败则降级 | 输出格式问题 |
| 连续 3 次失败 | 触发熔断 | 防止雪崩 |

### 13.3 各阶段模型要求

| 阶段 | 最低模型 | 允许降级 | 说明 |
|------|----------|----------|------|
| Stage 0 敏感检测 | glm-4-plus | ❌ 不允许 | 误判有法律风险 |
| Stage 1 噪声过滤 | glm-4-flash | ✅ 全链路 | 简单任务 |
| Stage 2 分类 | glm-4-air | ✅ 一级 | 分类精度重要 |
| Stage 3 话题匹配 | glm-4-air | ✅ 一级 | 语义理解 |
| Stage 4 结构化提取 | glm-4-air | ✅ 一级 | 结构化提取 |
| Stage 5 摘要更新 | glm-4-plus | — | **由 nullclaw 执行，不在平台流水线** |
| 问答关键词提取 | glm-4-flash | ✅ 全链路 | 简单任务 |
| 问答答案综合 | glm-4-plus | ✅ 一级 | 核心体验 |
| 会议纪要生成 | glm-4-air | ✅ 一级 | 按需生成 |

### 13.4 熔断机制

```
熔断器状态机:

  CLOSED (正常)
      ↓ 连续失败 5 次
  OPEN (熔断)
      ↓ 5 分钟后
  HALF_OPEN (探测)
      ↓ 成功 → CLOSED
      ↓ 失败 → OPEN

配置参数:
  - failure_threshold: 5      # 触发熔断的连续失败次数
  - recovery_timeout: 300     # 熔断后恢复探测时间(秒)
  - half_open_requests: 1     # 探测时的请求数
```

### 13.5 LLM 调用监控指标

```yaml
监控指标:
  - llm_call_duration_seconds{model, stage}     # 调用耗时
  - llm_call_total{model, stage, status}        # 调用次数
  - llm_call_fallback_total{from_model, to_model} # 降级次数
  - llm_json_parse_errors_total{stage}          # JSON 解析失败
  - llm_circuit_breaker_state{model}            # 熔断器状态
```

---

## 14. 缓存策略（补充）

### 14.1 缓存方案选型

系统支持两种缓存方案，可根据业务规模选择：

| 场景 | 推荐方案 | 原因 |
|------|----------|------|
| **小型团队** / 单实例 | 内存缓存 | 零依赖、简单、进程内 |
| **大型团队** / 多实例 | Redis | 支持跨进程共享、持久化 |

**当前默认：内存缓存**

### 14.2 内存缓存架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    内存缓存架构 (Python)                         │
│                                                                 │
│  实现方式: cachetools 库或自实现 TTLCache                        │
│                                                                 │
│  L1 - 会话缓存 (TTL: 24h)                                        │
│  ├── session:{user_id} → JWT payload                            │
│  └── permissions:{user_id} → role + capabilities                │
│                                                                 │
│  L2 - 搜索缓存 (TTL: 5min)                                       │
│  ├── search:{query_hash} → result set                           │
│  └── qa:{question_hash} → answer + sources                      │
│                                                                 │
│  L3 - 热数据缓存 (TTL: 1h)                                       │
│  ├── thread:{thread_id} → summary preview                       │
│  ├── user_todos:{user_id} → pending count                       │
│  └── notifications:{user_id} → unread count                     │
│                                                                 │
│  L4 - 参考数据缓存 (TTL: 24h)                                    │
│  └── reference:{service}:{env} → config values                  │
└─────────────────────────────────────────────────────────────────┘
```

### 14.3 实现代码

```python
from cachetools import TTLCache
from functools import wraps
import hashlib

class CacheManager:
    """轻量级内存缓存管理器"""

    def __init__(self):
        # 各层缓存配置
        self._caches = {
            'session': TTLCache(maxsize=1000, ttl=86400),      # 24h
            'search': TTLCache(maxsize=500, ttl=300),          # 5min
            'hot': TTLCache(maxsize=2000, ttl=3600),           # 1h
            'reference': TTLCache(maxsize=500, ttl=86400),     # 24h
        }

    def get(self, cache_type: str, key: str):
        """获取缓存"""
        cache = self._caches.get(cache_type)
        if cache and key in cache:
            return cache[key]
        return None

    def set(self, cache_type: str, key: str, value):
        """设置缓存"""
        cache = self._caches.get(cache_type)
        if cache:
            cache[key] = value

    def delete(self, cache_type: str, key: str):
        """删除缓存"""
        cache = self._caches.get(cache_type)
        if cache and key in cache:
            del cache[key]

    def clear(self, cache_type: str = None):
        """清空缓存"""
        if cache_type:
            self._caches.get(cache_type, {}).clear()
        else:
            for cache in self._caches.values():
                cache.clear()

    @staticmethod
    def hash_key(*args) -> str:
        """生成缓存 key 哈希"""
        data = '|'.join(str(a) for a in args)
        return hashlib.md5(data.encode()).hexdigest()


# 全局缓存实例
cache = CacheManager()
```

### 14.4 缓存策略详情

| 缓存类型 | Key 格式 | TTL | 失效策略 |
|----------|----------|-----|----------|
| 搜索结果 | `search:{md5(query+filters)}` | 5 分钟 | 话题更新时清空 search 缓存 |
| 问答答案 | `qa:{md5(question)}` | 5 分钟 | 来源话题更新时清空 |
| 用户权限 | `perm:{user_id}` | 1 小时 | 白名单变更时删除 |
| 待办统计 | `todos:{user_id}` | 10 分钟 | 待办状态变更时删除 |
| 参考数据 | `ref:{service}:{env}` | 24 小时 | 参考数据更新时删除 |
| 通知计数 | `notif:{user_id}` | 5 分钟 | 实时更新 |

### 14.5 内存缓存 vs Redis

| 维度 | 内存缓存 | Redis |
|------|----------|-------|
| **依赖** | 零依赖 | 需要部署 Redis 服务 |
| **数据共享** | 进程内，无法跨进程 | 多进程共享 |
| **持久化** | 重启丢失 | 支持 RDB/AOF |
| **内存限制** | 受进程内存限制 | 独立进程，可配置上限 |
| **适用场景** | 单实例、小型团队 | 多实例、高并发 |

### 14.6 迁移路径

```
内存缓存 (当前默认)
    │
    ├── 业务规模增长
    │
    ├── 需要多实例协作
    │
    └── 迁移到 Redis
```

### 14.7 Redis 方案（可选）

当业务规模增长时，可切换到 Redis：

```yaml
# config.yaml
cache:
  backend: "memory"  # memory | redis

  redis:
    host: "localhost"
    port: 6379
    db: 0
    password: "${REDIS_PASSWORD}"
    max_connections: 10
```

Redis 架构详见历史版本文档。

---

## 15. 监控与告警（补充）

### 15.1 业务监控指标

```yaml
消息处理:
  - messages_ingested_total              # 入库消息数
  - messages_processed_total{stage}      # 各阶段处理数
  - messages_skipped_noise_total         # 噪声过滤数
  - messages_sensitive_pending           # 待授权敏感数
  - message_processing_duration_seconds  # 处理耗时

知识库:
  - threads_total{category, status}      # 话题数量
  - threads_orphan_count                 # 孤儿话题数
  - summary_updates_total                # 摘要更新次数
  - modifications_total                  # 当事人修正次数

问答:
  - qa_sessions_total                    # 问答会话数
  - qa_satisfaction_avg                  # 平均满意度
  - qa_no_result_total                   # 无结果次数
  - search_query_duration_seconds        # 搜索耗时

管家:
  - butler_tasks_total{type, status}     # 任务执行数
  - butler_digest_sent_total             # 快报发送数
  - butler_reminder_sent_total           # 提醒发送数
  - butler_feedback_avg_rating           # 平均评分
```

### 15.2 系统监控指标

```yaml
LLM 服务:
  - llm_api_calls_total{model, status}   # API 调用数
  - llm_api_latency_seconds{model}       # API 延迟
  - llm_tokens_used_total{model, type}   # Token 消耗
  - llm_fallback_total                   # 降级次数
  - llm_circuit_breaker_open             # 熔断状态

数据库:
  - pg_connections_active                # 活跃连接数
  - pg_query_duration_seconds            # 查询耗时
  - pg_slow_queries_total                # 慢查询数
  - pg_table_size_bytes{table}           # 表大小

Celery:
  - celery_tasks_pending                 # 待处理任务数
  - celery_tasks_failed_total            # 失败任务数
  - celery_worker_count                  # Worker 数量
  - celery_queue_length{queue}           # 队列长度
```

### 15.3 告警规则

```yaml
P0 - 紧急 (5分钟内响应):
  - LLM 服务不可用: llm_api_error_rate > 0.5 for 2m
  - 数据库连接池耗尽: pg_connections_active > 90%
  - 消息处理堆积: celery_queue_length > 1000

P1 - 重要 (30分钟内响应):
  - 敏感授权积压: sensitive_pending_count > 50
  - 管家任务失败: butler_task_failure > 10 in 1h
  - nullclaw 响应超时: nullclaw_response_time > 30s

P2 - 一般 (1天内响应):
  - 慢查询增多: pg_slow_queries_total > 10 in 1h
  - 问答满意度下降: qa_satisfaction_avg < 3.5 for 1d
  - 孤儿话题增多: threads_orphan_count > 20
```

### 15.4 日志系统架构（新增）

RippleFlow 采用**分层日志架构**，支持异常自动检测与智能通知。

```
┌─────────────────────────────────────────────────────────────────┐
│                    RippleFlow 日志系统架构                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                日志采集层                                │   │
│  │                                                         │   │
│  │  服务端日志                    客户端日志                │   │
│  │  ├── API 访问日志             ├── 前端错误日志           │   │
│  │  ├── 业务处理日志             ├── 用户行为日志           │   │
│  │  ├── LLM 调用日志             ├── 性能指标日志           │   │
│  │  ├── 异常堆栈日志             ├── 网络请求日志           │   │
│  │  └── 审计日志                 └── 控制台日志             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                日志处理层                                │   │
│  │                                                         │   │
│  │  结构化存储        实时分析        异常检测              │   │
│  │  ├── JSON 格式    ├── 关键词匹配   ├── 错误率监控        │   │
│  │  ├── 时间索引     ├── 模式识别     ├── 异常聚合          │   │
│  │  └── 分级存储     └── 趋势分析     └── 根因定位          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                通知分发层                                │   │
│  │                                                         │   │
│  │  AI 管家接收异常事件                                     │   │
│  │        │                                                │   │
│  │        ├──→ Email 通知人类管理员                         │   │
│  │        │    └── 配置: admin_emails: [...]               │   │
│  │        │                                                │   │
│  │        └──→ 消息通道通知 nullclaw 自动开发团队            │   │
│  │             └── 配置: dev_channel_webhook: "..."        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 15.4.1 服务端日志规范

```yaml
# 日志级别定义
LOG_LEVELS:
  DEBUG:    # 开发调试信息（生产环境关闭）
  INFO:     # 正常业务流程
  WARNING:  # 潜在问题，不影响服务
  ERROR:    # 错误，需要关注
  CRITICAL: # 严重错误，需要立即处理

# 日志分类
LOG_CATEGORIES:
  # API 访问日志
  api_access:
    format: json
    fields:
      - timestamp
      - request_id
      - method
      - path
      - status_code
      - response_time_ms
      - user_id
      - client_ip
      - user_agent
    retention_days: 30

  # 业务处理日志
  business:
    format: json
    fields:
      - timestamp
      - request_id
      - service
      - action
      - entity_type
      - entity_id
      - status
      - duration_ms
      - details
    retention_days: 90

  # LLM 调用日志
  llm:
    format: json
    fields:
      - timestamp
      - request_id
      - model
      - prompt_tokens
      - completion_tokens
      - latency_ms
      - status
      - fallback_used
      - cost_estimate
    retention_days: 90

  # 异常堆栈日志
  exception:
    format: json
    fields:
      - timestamp
      - request_id
      - exception_type
      - exception_message
      - stack_trace
      - context
      - severity
    retention_days: 365

  # 审计日志（敏感操作）
  audit:
    format: json
    fields:
      - timestamp
      - user_id
      - action
      - resource_type
      - resource_id
      - old_value
      - new_value
      - ip_address
    retention_days: 365
```

#### 15.4.2 客户端日志规范

```typescript
// 前端日志配置
interface ClientLogConfig {
  // 日志级别
  level: 'debug' | 'info' | 'warn' | 'error';

  // 自动采集
  autoCollect: {
    // JavaScript 错误
    jsErrors: boolean;
    // Promise 拒绝
    promiseRejections: boolean;
    // 资源加载失败
    resourceErrors: boolean;
    // 控制台错误
    consoleErrors: boolean;
    // 网络请求
    networkRequests: {
      includeHeaders: boolean;
      includeBody: boolean;
      sensitiveFields: string[]; // 脱敏字段
    };
  };

  // 性能指标
  performance: {
    // 页面加载时间
    pageLoad: boolean;
    // 首次内容绘制
    fcp: boolean;
    // 最大内容绘制
    lcp: boolean;
    // 累积布局偏移
    cls: boolean;
    // 首次输入延迟
    fid: boolean;
  };

  // 用户行为（可选）
  userBehavior: {
    click: boolean;
    scroll: boolean;
    input: boolean;
  };
}

// 日志上报配置
interface LogUploadConfig {
  // 上报端点
  endpoint: '/api/v1/logs/client';

  // 批量上报
  batchSize: 10;
  flushInterval: 5000; // 5秒

  // 重试策略
  retry: {
    maxAttempts: 3;
    backoff: 'exponential';
    baseDelay: 1000;
  };

  // 本地缓存（离线场景）
  localStorage: {
    enabled: true;
    maxSize: 5 * 1024 * 1024; // 5MB
  };
}

// 客户端异常检测与上报配置
interface ClientExceptionMonitor {
  // 定期检查配置
  periodicCheck: {
    enabled: true;
    interval: 60000;  // 60秒检查一次
    checkItems: [
      'unhandled_errors',      // 未处理的错误
      'memory_leak',           // 内存泄漏迹象
      'network_failures',      // 网络请求失败
      'performance_degradation' // 性能下降
    ];
  };

  // 异常阈值（超过阈值立即上报）
  thresholds: {
    errorCount: 5;             // 1分钟内错误数
    memoryUsage: 0.9;          // 内存使用率 90%
    networkFailureRate: 0.3;   // 网络失败率 30%
    longTaskDuration: 5000;    // 长任务耗时 5秒
  };

  // 立即上报条件
  immediateReport: {
    criticalErrors: true;      // 关键错误立即上报
    uncaughtException: true;   // 未捕获异常立即上报
    promiseRejection: true;    // Promise 拒绝立即上报
    resourceLoadFailure: true; // 资源加载失败立即上报
  };
}

// 客户端异常检测器
class ClientExceptionDetector {
  private errorCount: number = 0;
  private lastCheckTime: number = Date.now();
  private pendingLogs: LogEntry[] = [];

  // 初始化监控
  init(config: ClientExceptionMonitor): void {
    // 1. 注册全局错误监听
    window.onerror = this.handleError.bind(this);
    window.onunhandledrejection = this.handleRejection.bind(this);

    // 2. 注册性能观察器
    this.setupPerformanceObserver();

    // 3. 启动定期检查
    setInterval(() => this.periodicCheck(config), config.periodicCheck.interval);
  }

  // 错误处理
  private handleError(event: ErrorEvent): void {
    const log: LogEntry = {
      timestamp: new Date().toISOString(),
      level: 'error',
      category: 'client',
      service: 'frontend',
      message: event.message,
      details: {
        filename: event.filename,
        lineno: event.lineno,
        colno: event.colno
      },
      exception_type: 'js_error',
      stack_trace: event.error?.stack
    };

    this.errorCount++;
    this.pendingLogs.push(log);

    // 立即上报未捕获异常
    if (this.config.immediateReport.uncaughtException) {
      this.reportImmediately(log);
    }
  }

  // Promise 拒绝处理
  private handleRejection(event: PromiseRejectionEvent): void {
    const log: LogEntry = {
      timestamp: new Date().toISOString(),
      level: 'error',
      category: 'client',
      service: 'frontend',
      message: `Unhandled Promise Rejection: ${event.reason}`,
      exception_type: 'promise_rejection',
      stack_trace: event.reason?.stack
    };

    this.pendingLogs.push(log);

    if (this.config.immediateReport.promiseRejection) {
      this.reportImmediately(log);
    }
  }

  // 定期检查
  private periodicCheck(config: ClientExceptionMonitor): void {
    const now = Date.now();
    const elapsed = now - this.lastCheckTime;

    // 检查错误率
    if (this.errorCount > config.thresholds.errorCount) {
      this.reportAlert('high_error_rate', {
        errorCount: this.errorCount,
        period: elapsed
      });
    }

    // 检查内存使用
    if (performance.memory) {
      const memoryUsage = performance.memory.usedJSHeapSize / performance.memory.jsHeapSizeLimit;
      if (memoryUsage > config.thresholds.memoryUsage) {
        this.reportAlert('memory_pressure', {
          usage: memoryUsage,
          usedMB: performance.memory.usedJSHeapSize / 1024 / 1024
        });
      }
    }

    // 重置计数器
    this.errorCount = 0;
    this.lastCheckTime = now;

    // 上报待发送日志
    if (this.pendingLogs.length > 0) {
      this.flushLogs();
    }
  }

  // 性能观察器
  private setupPerformanceObserver(): void {
    // 长任务检测
    const longTaskObserver = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        if (entry.duration > this.config.thresholds.longTaskDuration) {
          this.reportAlert('long_task', {
            duration: entry.duration,
            name: entry.name,
            startTime: entry.startTime
          });
        }
      }
    });
    longTaskObserver.observe({ entryTypes: ['longtask'] });

    // 资源加载失败检测
    const resourceObserver = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        if (entry.entryType === 'resource' && (entry as any).transferSize === 0) {
          this.reportAlert('resource_load_failure', {
            name: entry.name,
            duration: entry.duration
          });
        }
      }
    });
    resourceObserver.observe({ entryTypes: ['resource'] });
  }

  // 立即上报
  private async reportImmediately(log: LogEntry): Promise<void> {
    try {
      await fetch('/api/v1/logs/client', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ logs: [log], immediate: true })
      });
    } catch (e) {
      // 上报失败，存入本地缓存
      this.saveToLocalStorage([log]);
    }
  }

  // 批量上报
  private async flushLogs(): Promise<void> {
    if (this.pendingLogs.length === 0) return;

    const logs = [...this.pendingLogs];
    this.pendingLogs = [];

    try {
      await fetch('/api/v1/logs/client', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ logs })
      });
    } catch (e) {
      // 上报失败，存入本地缓存
      this.saveToLocalStorage(logs);
    }
  }

  // 上报告警
  private reportAlert(alertType: string, data: object): void {
    const log: LogEntry = {
      timestamp: new Date().toISOString(),
      level: 'warning',
      category: 'client',
      service: 'frontend',
      message: `Client Alert: ${alertType}`,
      details: data
    };
    this.reportImmediately(log);
  }

  // 本地存储
  private saveToLocalStorage(logs: LogEntry[]): void {
    const key = 'rippleflow_pending_logs';
    const existing = JSON.parse(localStorage.getItem(key) || '[]');
    const merged = [...existing, ...logs].slice(-100); // 最多保留 100 条
    localStorage.setItem(key, JSON.stringify(merged));
  }
}
```

#### 15.4.3 客户端异常检测流程

```
┌─────────────────────────────────────────────────────────────────┐
│                客户端异常检测与上报流程                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              实时检测（立即上报）                         │   │
│  │                                                         │   │
│  │  window.onerror ──────────────────────────┐             │   │
│  │  window.onunhandledrejection ─────────────┤             │   │
│  │  资源加载失败 ────────────────────────────┤──→ 立即上报 │   │
│  │  关键业务错误 ────────────────────────────┘              │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              定期检测（60秒周期）                         │   │
│  │                                                         │   │
│  │  ├── 错误率检查 ─── 超过阈值 → 上报告警                  │   │
│  │  ├── 内存使用检查 ─ 超过 90% → 上报告警                  │   │
│  │  ├── 长任务检测 ─── 超过 5秒 → 上报告警                  │   │
│  │  └── 待发送日志 ─── 批量上报                             │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              服务端处理                                  │   │
│  │                                                         │   │
│  │  POST /api/v1/logs/client                               │   │
│  │        │                                                │   │
│  │        ▼                                                │   │
│  │  LogService.write_log()                                 │   │
│  │        │                                                │   │
│  │        ▼                                                │   │
│  │  异常检测规则匹配                                        │   │
│  │        │                                                │   │
│  │        ├── 匹配成功 → ExceptionNotificationService       │   │
│  │        │                │                               │   │
│  │        │                ├──→ Email 通知管理员            │   │
│  │        │                └──→ Webhook 通知开发团队        │   │
│  │        │                                                │   │
│  │        └── 无需处理 → 存储日志                           │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 15.4.3 异常检测规则

```yaml
# 异常检测配置
exception_detection:
  # 自动检测规则
  rules:
    - name: high_error_rate
      description: 错误率超过阈值
      condition: "error_count / total_requests > 0.05"
      window: 5m
      severity: critical

    - name: repeated_exception
      description: 同一异常重复出现
      condition: "same_exception_count > 10"
      window: 10m
      severity: warning

    - name: llm_timeout
      description: LLM 调用超时
      condition: "llm_latency > 30000"
      severity: error

    - name: database_connection_fail
      description: 数据库连接失败
      condition: "db_connection_error > 0"
      severity: critical

    - name: client_js_error_spike
      description: 前端 JS 错误激增
      condition: "js_error_count > 50"
      window: 5m
      severity: warning

    - name: api_latency_high
      description: API 响应延迟过高
      condition: "p99_latency > 5000"
      window: 5m
      severity: warning

  # 聚合策略
  aggregation:
    # 相同异常去重
    dedup_window: 5m
    dedup_fields: [exception_type, exception_message]

    # 根因分析
    root_cause_analysis: true
    max_stack_depth: 10
```

#### 15.4.4 AI 管家异常通知机制

```yaml
# 通知配置
notification:
  # Email 通知人类管理员
  email:
    enabled: true
    # 管理员邮箱列表（从配置读取）
    recipients: ${ADMIN_EMAILS}  # 环境变量: ["admin@company.com", "dev-lead@company.com"]
    # 邮件模板
    templates:
      critical:
        subject: "[RippleFlow 紧急] {exception_type}"
        body: |
          ## 异常摘要
          - 时间: {timestamp}
          - 类型: {exception_type}
          - 严重程度: {severity}
          - 影响范围: {affected_users} 用户

          ## 异常详情
          ```
          {exception_message}
          ```

          ## 堆栈信息
          ```
          {stack_trace}
          ```

          ## 上下文
          {context_json}

          ---
          请尽快处理。查看完整日志: {log_url}

      warning:
        subject: "[RippleFlow 警告] {exception_type}"
        body: |
          检测到异常，请关注:
          - 时间: {timestamp}
          - 类型: {exception_type}
          - 详情: {exception_message}

  # 消息通道通知 nullclaw 自动开发团队
  webhook:
    enabled: true
    # Webhook URL（从配置读取）
    url: ${DEV_CHANNEL_WEBHOOK}  # 环境变量
    # 请求格式
    payload:
      source: "rippleflow-butler"
      event_type: "exception_detected"
      severity: "{severity}"
      timestamp: "{timestamp}"
      data:
        exception_type: "{exception_type}"
        exception_message: "{exception_message}"
        stack_trace: "{stack_trace}"
        context: "{context}"
        request_id: "{request_id}"
        suggested_action: "{suggested_action}"  # AI 管家建议

    # 重试策略
    retry:
      max_attempts: 3
      backoff: [1000, 5000, 15000]
```

#### 15.4.5 AI 管家异常处理 Routine

```markdown
# routine_exception_handler.md

## 触发条件
- 系统检测到异常事件
- 异常级别 >= WARNING

## 处理流程

### 1. 异常分析
- 读取异常详情和堆栈
- 分析异常类型和根因
- 评估影响范围
- 判断是否需要人工介入

### 2. 通知决策
```
if severity == "CRITICAL":
    立即通知（Email + Webhook）
elif severity == "ERROR":
    聚合后通知（5分钟窗口）
elif severity == "WARNING":
    记录日志，定时汇总
```

### 3. 执行通知
- 发送 Email 给管理员
- 发送 Webhook 给开发团队

### 4. 后续处理
- 记录通知状态
- 跟踪处理进度
- 定期汇报未解决问题

## 配置项
- admin_emails: 管理员邮箱列表
- dev_channel_webhook: 开发团队 Webhook
- notification_cooldown: 同一异常通知冷却时间（默认 30 分钟）
```

#### 15.4.6 日志查询接口

```yaml
# API: GET /api/v1/logs/search
parameters:
  - name: start_time
    type: datetime
    required: true
  - name: end_time
    type: datetime
    required: true
  - name: level
    type: enum
    values: [debug, info, warning, error, critical]
  - name: category
    type: enum
    values: [api_access, business, llm, exception, audit, client]
  - name: service
    type: string
  - name: request_id
    type: string
  - name: user_id
    type: string
  - name: keyword
    type: string
    description: 全文搜索关键词
  - name: page
    type: integer
    default: 1
  - name: size
    type: integer
    default: 50

response:
  total: integer
  logs:
    - timestamp: datetime
      level: string
      category: string
      service: string
      message: string
      details: object
      request_id: string
      user_id: string
```

#### 15.4.7 日志存储架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    日志存储分层架构                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  热数据（最近 7 天）                                             │
│  ├── 存储: Elasticsearch / Loki                                 │
│  ├── 查询: 毫秒级                                               │
│  └── 用途: 实时监控、异常检测                                    │
│                                                                 │
│  温数据（7-30 天）                                               │
│  ├── 存储: 压缩文件存储                                          │
│  ├── 查询: 秒级                                                 │
│  └── 用途: 问题排查、趋势分析                                    │
│                                                                 │
│  冷数据（30 天-1 年）                                            │
│  ├── 存储: 对象存储 / 归档                                       │
│  ├── 查询: 分钟级                                               │
│  └── 用途: 审计、合规                                           │
│                                                                 │
│  轻量部署方案（无 Elasticsearch）                                │
│  ├── 存储: 本地文件 + SQLite 索引                                │
│  ├── 查询: 秒级（使用 grep/sqlite）                              │
│  └── 适用: 小团队、单机部署                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### 15.4.8 环境变量配置

```bash
# .env 文件示例

# 管理员邮箱（多个用逗号分隔）
ADMIN_EMAILS=admin@company.com,dev-lead@company.com

# 开发团队 Webhook URL（用于通知 nullclaw 自动开发团队）
DEV_CHANNEL_WEBHOOK=https://nullclaw.example.com/webhook/rippleflow-exceptions

# SMTP 配置（用于发送邮件）
SMTP_HOST=smtp.company.com
SMTP_PORT=587
SMTP_USER=noreply@rippleflow.company.com
SMTP_PASSWORD=${SMTP_PASSWORD}

# 日志配置
LOG_LEVEL=INFO
LOG_FORMAT=json
LOG_PATH=/var/log/rippleflow

# 异常检测配置
EXCEPTION_DETECTION_ENABLED=true
EXCEPTION_NOTIFICATION_COOLDOWN=1800  # 秒
```

---

## 16. 并发控制（补充）

### 16.1 话题更新乐观锁

```
场景: 多个消息同时处理可能更新同一话题

解决方案: 使用 summary_version 实现乐观锁

更新 SQL:
  UPDATE topic_threads
  SET summary = $1,
      structured_data = $2,
      summary_version = summary_version + 1,
      summary_updated_at = NOW()
  WHERE id = $3 AND summary_version = $4

如果 affected_rows = 0:
  - 版本冲突，重新读取最新版本
  - 合并变更后重试
  - 最多重试 3 次
```

### 16.2 消息处理幂等性

```
场景: 消息可能被重复投递

解决方案: 使用 message_id + processing_stage 实现幂等

处理前检查:
  SELECT status FROM messages WHERE id = $1

  如果 status IN ('classified', 'skipped', 'sensitive_pending'):
    - 已处理完成，跳过
  如果 status = 'processing':
    - 正在处理中，等待或跳过
  如果 status = 'pending':
    - 开始处理，先更新状态为 'processing'
```

### 16.3 敏感授权并发控制

```
场景: 多个当事人同时提交授权决策

解决方案: 数据库行锁 + 原子更新

处理流程:
  BEGIN;
  SELECT * FROM sensitive_authorizations WHERE id = $1 FOR UPDATE;

  -- 检查是否已决策
  IF decisions->>$user_id IS NOT NULL AND decisions->>$user_id != 'pending':
    -- 已决策，返回当前状态
    ROLLBACK;
    RETURN;

  -- 更新决策
  UPDATE sensitive_authorizations
  SET decisions = jsonb_set(decisions, '{$user_id}', '"$decision"')
  WHERE id = $1;

  COMMIT;

  -- 检查是否全部决策完成
  -- 触发后续处理
```

## 17. 数据面与控制面分离架构（v0.6 核心设计）

### 17.1 架构总览

**核心设计理念**：系统分为**知识平台**和**AI管家Agent**两部分，策略与机制完全分离。

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         RippleFlow 系统架构                              │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                      AI 管家 Agent（控制面）                       │  │
│  │                     独立于知识平台的智能体                         │  │
│  │                                                                   │  │
│  │   ┌─────────────────────────────────────────────────────────┐    │  │
│  │   │                  Agent 核心                               │    │  │
│  │   │                                                         │    │  │
│  │   │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │    │  │
│  │   │  │ 规则引擎     │  │ LLM 智能层   │  │ 自省学习     │  │    │  │
│  │   │  │ (固化代码)   │  │ (智能决策)   │  │ (持续演化)   │  │    │  │
│  │   │  │              │  │              │  │              │  │    │  │
│  │   │  │ - 状态机     │  │ - 意图理解   │  │ - 经验沉淀   │  │    │  │
│  │   │  │ - 阈值判断   │  │ - 工具选择   │  │ - 模式发现   │  │    │  │
│  │   │  │ - 定时任务   │  │ - 行动规划   │  │ - 自我优化   │  │    │  │
│  │   │  │ - 升级机制   │  │ - 推理决策   │  │ - 框架扩展   │  │    │  │
│  │   │  └──────────────┘  └──────────────┘  └──────────────┘  │    │  │
│  │   │                                                         │    │  │
│  │   │  ┌───────────────────────────────────────────────────┐  │    │  │
│  │   │  │              工具调用层 (Tool Calling)             │  │    │  │
│  │   │  │                                                   │  │    │  │
│  │   │  │  通过 API、Function Call、命令行调用平台能力       │  │    │  │
│  │   │  └───────────────────────────────────────────────────┘  │    │  │
│  │   └─────────────────────────────────────────────────────────┘    │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                      │                                   │
│                    ┌─────────────────┼─────────────────┐               │
│                    ▼                 ▼                 ▼               │
│            调用 API          使用 Function Call      查询知识库        │
│                    │                 │                 │               │
│                    └─────────────────┼─────────────────┘               │
│                                      ▼                                   │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                       知识平台（数据面）                           │  │
│  │                      机制与数据的载体                              │  │
│  │                                                                   │  │
│  │   ┌──────────────┐ ┌──────────────┐ ┌──────────────┐             │  │
│  │   │ 消息收集层    │ │ 知识存储层    │ │ 索引检索层   │             │  │
│  │   │              │ │              │ │             │              │  │
│  │   │ Webhook      │ │ PostgreSQL   │ │ 全文检索     │             │  │
│  │   │ 消息队列     │ │ 知识图谱     │ │ 全局索引     │             │  │
│  │   └──────────────┘ └──────────────┘ └──────────────┘             │  │
│  │                                                                   │  │
│  │   ┌──────────────┐ ┌──────────────┐ ┌──────────────┐             │  │
│  │   │ 行为分析层    │ │ 统计分析层    │ │ 缓存层       │             │  │
│  │   │              │ │              │ │             │              │  │
│  │   │ 用户行为     │ │ 贡献统计     │ │ 内存缓存    │             │  │
│  │   │ 模式挖掘     │ │ 质量评估     │ │ 热数据      │             │  │
│  │   └──────────────┘ └──────────────┘ └──────────────┘             │  │
│  │                                                                   │  │
│  │   ┌───────────────────────────────────────────────────────────┐  │  │
│  │   │                   平台能力暴露层                           │  │  │
│  │   │                                                           │  │  │
│  │   │  REST API  │  Function Calls  │  CLI Commands  │  Events  │  │  │
│  │   └───────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

### 17.2 策略与机制分离

| 维度 | RippleFlow 平台（机制） | nullclaw Agent（策略） |
|------|------------------------|------------------------|
| **职责** | 提供能力和数据 | 决定何时如何使用能力 |
| **变更频率** | 低（基础设施稳定） | 高（策略持续优化） |
| **实现方式** | 固定代码、API、CLI | Routine 脚本 + LLM智能 |
| **演化方式** | 版本发布 | 自省学习、在线优化 |
| **关注点** | 正确性、性能、可靠性 | 效果、体验、智能化 |

**关键变化**：所有策略逻辑（规则引擎、Routine 脚本）由 nullclaw 提供，RippleFlow 平台只负责暴露能力。

### 17.3 RippleFlow 平台职责

RippleFlow 平台是**机制与数据的载体**，只负责暴露能力，不包含任何策略逻辑：

| 层次 | 职责 | 暴露方式 |
|------|------|----------|
| **消息收集层** | 接收群聊消息、消息队列、原始存储 | Webhook、API |
| **知识存储层** | 结构化存储、知识图谱、关联关系 | CRUD API、CLI |
| **索引检索层** | 全文索引、全局索引、图谱查询 | Search API、CLI |
| **行为分析层** | 用户行为记录、模式挖掘、偏好学习 | Analytics API、CLI |
| **统计分析层** | 贡献统计、质量评估、健康报告 | Stats API、CLI |
| **缓存层** | 热数据缓存、会话状态、临时数据 | Cache API |

**平台不包含**：
- ❌ 规则引擎
- ❌ Routine 脚本
- ❌ 策略决策逻辑
- ❌ 定时任务（由 nullclaw 调度）

### 17.4 nullclaw Agent 职责

nullclaw 是**独立的智能体**，负责所有策略逻辑：

#### 17.4.1 Agent 架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    nullclaw Agent                                │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                     感知模块                               │  │
│  │                                                           │  │
│  │  监听平台事件 → 理解当前状态 → 识别行动机会               │  │
│  │                                                           │  │
│  │  通过 CLI 查询：rf help, rf <command> --help              │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                              ▼                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                     决策模块                               │  │
│  │                                                           │  │
│  │  ┌───────────────┐     ┌───────────────┐                  │  │
│  │  │ Routine 脚本  │     │ LLM 智能层    │                  │  │
│  │  │               │     │               │                  │  │
│  │  │ 固化逻辑：    │     │ 智能决策：    │                  │  │
│  │  │ • 状态机转换  │ ──→ │ • 意图理解    │                  │  │
│  │  │ • 阈值判断    │     │ • 工具选择    │                  │  │
│  │  │ • 定时触发    │     │ • 行动规划    │                  │  │
│  │  │ • 升级规则    │     │ • 推理决策    │                  │  │
│  │  └───────────────┘     └───────────────┘                  │  │
│  │           │                     │                          │  │
│  │           └──────────┬──────────┘                          │  │
│  │                      ▼                                     │  │
│  │              统一决策输出                                   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                              ▼                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                     执行模块                               │  │
│  │                                                           │  │
│  │  工具调用 → 平台 API → Function Call → CLI Commands        │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                              ▼                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                     自省模块                               │  │
│  │                                                           │  │
│  │  观察结果 → 反思效果 → 沉淀经验 → 优化策略                 │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

#### 17.4.2 规则引擎（Routine 脚本）

规则引擎处理**确定性的、高可靠要求的**逻辑，通过**Routine 脚本（提示词）**定义：

| 规则类型 | 说明 | 示例 |
|----------|------|------|
| **状态机** | 明确的状态转换逻辑 | pending → approved → completed |
| **阈值判断** | 数值条件触发 | 敏感授权 7 天升级 |
| **定时任务** | 周期性触发 | 每日 9:00 检查到期待办 |
| **升级机制** | 超时自动处理 | 授权超时升级管理员 |
| **权限检查** | 访问控制 | 当事人才能修改摘要 |
| **格式验证** | 数据校验 | 必填字段检查 |

```
┌─────────────────────────────────────────────────────────────────┐
│                    Routine 脚本机制                              │
│                                                                 │
│  事件触发                        Agent 执行                      │
│  ────────                        ─────────                      │
│                                                                 │
│  sensitive.timeout     ──→     routine_sensitive_escalation.md  │
│  todo.due_soon         ──→     routine_todo_reminder.md        │
│  thread.created        ──→     routine_thread_notify.md         │
│  daily.09:00           ──→     routine_daily_digest.md          │
│  weekly.monday         ──→     routine_weekly_report.md         │
│                                                                 │
│  优势：                                                         │
│  • 在线更新：无需重启服务                                       │
│  • 可追溯：所有 routine 有版本历史                              │
│  • 可审计：执行日志记录决策过程                                 │
│  • 可演化：Agent 可以优化 routine 脚本                         │
└─────────────────────────────────────────────────────────────────┘
```

**Routine 脚本示例**：

```markdown
# routine_sensitive_escalation.md

## 触发条件
- 事件：sensitive.timeout
- 条件：授权请求创建超过 7 天且状态为 pending

## 执行步骤

1. 查询授权详情
   使用工具：get_sensitive_detail(authorization_id)

2. 通知管理员
   使用工具：send_notification(
     user_ids: [get_admin_list()],
     title: "敏感授权超时升级",
     content: "以下授权已超过 7 天未处理..."
   )

3. 通知当事人
   使用工具：send_notification(
     user_ids: authorization.stakeholders,
     title: "授权请求即将升级",
     content: "您的授权请求已超过 7 天，将升级至管理员处理"
   )

4. 更新状态
   使用工具：update_sensitive_status(
     authorization_id: authorization.id,
     status: "escalated",
     escalated_at: now()
   )

## 输出
- 升级成功：返回 {success: true}
- 升级失败：返回 {success: false, error: reason}
```

```markdown
# routine_todo_reminder.md

## 触发条件
- 事件：todo.due_soon（每天 9:00 检查）
- 条件：due_date 在 24 小时内且状态不是 done

## 执行步骤

1. 查询即将到期待办
   使用工具：list_todos(
     status: ["open", "in_progress"],
     due_before: now() + 24h
   )

2. 按被分配者分组
   按 assignee 分组，每人汇总待办列表

3. 发送提醒
   使用工具：send_notification(
     user_ids: [assignee],
     title: "待办即将到期",
     content: "您有 {count} 个待办即将到期..."
   )

4. 更新提醒计数
   使用工具：update_todo_reminder_count(todo_ids)

## 输出
- 提醒发送数量
- 提醒用户列表
```

```markdown
# routine_thread_notify.md

## 触发条件
- 事件：thread.created

## 执行步骤

1. 分析话题
   - 分类：thread.category
   - 当事人：thread.stakeholder_ids
   - 重要性：评估 1-5 级

2. 查找相关人员
   使用工具：search_similar_threads(thread.title)
   找到历史上相似话题的参与者

3. 查找订阅者
   使用工具：get_subscribers(
     topic: thread.topic,
     room: thread.primary_room_id
   )

4. 合并通知对象
   当事人 + 相似话题参与者 + 订阅者 - 已知晓者

5. 发送通知
   使用工具：send_notification(
     user_ids: notify_list,
     title: "新话题：{thread.title}",
     content: "摘要：{thread.summary}"
   )

## 实时反思
通知发送后，思考是否还需要：
1. 推荐相关历史内容
2. 建议创建待办
3. 建议订阅话题
```

**Routine 脚本目录结构**：

```
butler_prompts/
├── core/                      # 核心提示词（不可修改）
│   ├── identity.md
│   ├── principles.md
│   ├── permissions.md
│   └── triggers.md
│
├── routines/                  # Routine 脚本（固化逻辑的提示词形式）
│   ├── index.yaml             # Routine 索引
│   ├── sensitive/
│   │   ├── escalation.md      # 敏感授权升级
│   │   └── notify.md          # 敏感授权通知
│   ├── todo/
│   │   ├── reminder.md        # 待办提醒
│   │   ├── overdue.md         # 待办超期处理
│   │   └── complete_check.md  # 待办完成检查
│   ├── thread/
│   │   ├── notify.md          # 新话题通知
│   │   ├── drift_detect.md    # 话题漂移检测
│   │   └── close_check.md     # 话题关闭检查
│   ├── digest/
│   │   ├── daily.md           # 每日快报
│   │   └── weekly.md          # 每周周报
│   └── system/
│       ├── health_check.md    # 系统健康检查
│       └── cleanup.md         # 数据清理
│
├── duties/                    # 职责定义（管家可优化）
├── skills/                    # 技能模板
├── insights/                  # 自省沉淀
└── extensions/                # 扩展脚本
```

**Routine 索引配置**：

```yaml
# routines/index.yaml

routines:
  # 敏感授权相关
  - id: sensitive_escalation
    trigger: sensitive.timeout
    condition: "days_pending >= 7 AND status == 'pending'"
    script: routines/sensitive/escalation.md
    permission: L2
    enabled: true

  - id: sensitive_notify
    trigger: sensitive.created
    script: routines/sensitive/notify.md
    permission: L1
    enabled: true

  # 待办相关
  - id: todo_reminder
    trigger: system.cron
    schedule: "0 9 * * *"  # 每天 9:00
    script: routines/todo/reminder.md
    permission: L1
    enabled: true

  - id: todo_overdue
    trigger: todo.overdue
    script: routines/todo/overdue.md
    permission: L1
    enabled: true

  # 话题相关
  - id: thread_notify
    trigger: thread.created
    script: routines/thread/notify.md
    permission: L1
    enabled: true

  - id: thread_drift
    trigger: thread.updated
    condition: "category == 'tech_decision'"
    script: routines/thread/drift_detect.md
    permission: L1
    enabled: true

  # 快报相关
  - id: daily_digest
    trigger: system.cron
    schedule: "0 9 * * 1-5"  # 工作日 9:00
    script: routines/digest/daily.md
    permission: L2
    enabled: true

  - id: weekly_report
    trigger: system.cron
    schedule: "0 9 * * 1"  # 周一 9:00
    script: routines/digest/weekly.md
    permission: L2
    enabled: true
```

**Routine vs 硬编码的对比**：

| 维度 | 硬编码 | Routine 脚本 |
|------|--------|--------------|
| **更新方式** | 需要发布版本 | 在线更新，无需重启 |
| **可追溯性** | Git 历史 | 版本历史 + 执行日志 |
| **可审计性** | 需要额外日志 | 自然记录决策过程 |
| **演化能力** | 需要开发 | Agent 可优化 |
| **调试难度** | 需要重新部署 | 直接修改测试 |
| **灵活性** | 低 | 高 |

**Agent 执行 Routine 的流程**：

```
事件发生
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. 匹配 Routine                                                │
│     查找 routines/index.yaml 中匹配的 routine                   │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. 检查条件                                                    │
│     condition 表达式求值                                        │
└────────────────────────────┬────────────────────────────────────┘
                             │ 条件满足
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. 加载 Routine 脚本                                          │
│     读取对应的 .md 文件                                         │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. 执行 Routine                                                │
│     Agent 解析脚本，调用工具执行                                │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. 记录执行日志                                                │
│     输入、输出、决策过程、耗时                                  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  6. 实时反思（可选）                                            │
│     思考是否还需要提供其他服务                                  │
└─────────────────────────────────────────────────────────────────┘
```

#### 17.4.3 LLM 智能层

LLM 智能层处理**需要理解、判断、创造**的逻辑：

| 能力 | 说明 | 示例 |
|----------|------|------|
| **意图理解** | 理解用户自然语言 | "帮我找 Redis 相关的讨论" |
| **工具选择** | 决定调用哪个工具 | 选择搜索 API 而非问答 API |
| **行动规划** | 规划多步骤行动 | 先搜索 → 再分析 → 后推荐 |
| **推理决策** | 基于上下文推理 | 判断话题是否漂移 |
| **内容生成** | 生成回复内容 | 生成周报、摘要、通知 |
| **模式发现** | 从数据中发现模式 | 发现新的信息类别 |

#### 17.4.4 工具调用能力

Agent 通过工具调用访问平台能力：

```yaml
# 平台能力工具定义
tools:
  # 消息处理工具
  - name: search_threads
    description: 搜索话题线索
    parameters:
      query: {type: string, description: 搜索关键词}
      category: {type: string, description: 信息类别过滤}
      limit: {type: integer, default: 10}

  - name: get_thread_detail
    description: 获取话题详情
    parameters:
      thread_id: {type: string, required: true}

  # 待办管理工具
  - name: create_todo
    description: 创建待办任务
    parameters:
      title: {type: string, required: true}
      assignee: {type: string, required: true}
      due_date: {type: string}
      thread_id: {type: string}

  - name: list_todos
    description: 查询待办列表
    parameters:
      assignee: {type: string}
      status: {type: string, enum: [open, in_progress, done]}

  # 订阅管理工具
  - name: subscribe_topic
    description: 订阅话题
    parameters:
      user_id: {type: string, required: true}
      thread_id: {type: string, required: true}

  - name: subscribe_person
    description: 关注人员
    parameters:
      user_id: {type: string, required: true}
      target_user_id: {type: string, required: true}

  # 通知工具
  - name: send_notification
    description: 发送通知
    parameters:
      user_ids: {type: array, items: string}
      title: {type: string}
      content: {type: string}
      thread_id: {type: string}

  # 知识图谱工具
  - name: query_knowledge_graph
    description: 查询知识图谱
    parameters:
      node_type: {type: string}
      node_key: {type: string}
      edge_types: {type: array, items: string}

  # 分析工具
  - name: get_hot_topics
    description: 获取热点话题
    parameters:
      period: {type: string, enum: [day, week, month]}
      limit: {type: integer, default: 10}

  - name: get_user_activity
    description: 获取用户活跃度
    parameters:
      user_id: {type: string}
      period: {type: string}

  # 全局视角工具
  - name: get_global_overview
    description: 获取全局态势视图
    parameters: {}

  - name: get_attention_items
    description: 获取需要关注的事项
    parameters: {}
```

### 17.5 平台能力暴露

知识平台需要将所有能力抽象为可调用的工具：

| 暴露方式 | 说明 | 示例 |
|----------|------|------|
| **REST API** | HTTP 接口 | `/api/v1/threads/search` |
| **Function Call** | 函数定义 | `search_threads(query, category)` |
| **CLI Commands** | 命令行 | `rf threads search --query Redis` |
| **Events** | 事件通知 | `thread.created`, `todo.completed` |

### 17.6 Agent 工作流程

```
用户发言："Redis 集群部署方案讨论"

1. 感知阶段
   ├── 平台事件：message.received
   ├── 理解状态：新消息入库
   └── 识别机会：需要处理这条消息

2. 决策阶段
   ├── 规则引擎：消息分类 → tech_decision
   ├── LLM 智能层：
   │   ├── 理解内容：Redis 集群部署
   │   ├── 识别当事人：张三、李四
   │   ├── 发现相关：上周讨论过 Redis 连接池
   │   └── 规划行动：
   │       ├── 创建话题线索 ✓
   │       ├── 通知当事人 ✓
   │       ├── 推荐相关内容 ✓
   │       └── 建议创建待办（可选）

3. 执行阶段
   ├── 调用工具：create_thread(...)
   ├── 调用工具：send_notification(...)
   ├── 调用工具：search_threads(...) → 找到相关内容
   └── 调用工具：list_todos(...) → 检查是否需要创建待办

4. 自省阶段
   ├── 观察结果：话题创建成功，通知已发送
   ├── 反思效果：是否还需要其他服务？
   ├── 生成建议：
   │   ┌─────────────────────────────────────────┐
   │   │ 💡 我还可以帮您：                        │
   │   │ 1. 📋 创建待办：张三负责测试环境         │
   │   │ 2. 👀 订阅话题：李四可能想关注           │
   │   │ 3. 📚 相关内容：上周讨论过 Redis 配置    │
   │   └─────────────────────────────────────────┘
   └── 沉淀经验：记录用户偏好，优化未来推荐
```

---

## 18. 全局索引（新增）

### 18.1 概念

全局索引是团队活动的"全景视图"，让用户快速了解团队发生了什么。

### 18.2 索引结构

```sql
-- 全局索引表
CREATE TABLE global_activity_index (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    activity_type   VARCHAR(50) NOT NULL,  -- thread | task | decision | reference
    activity_id     UUID NOT NULL,
    title           VARCHAR(500),
    summary         TEXT,
    category        VARCHAR(50),
    importance      INTEGER DEFAULT 0,      -- 重要性评分 0-100
    participants    JSONB DEFAULT '[]',     -- 参与者列表
    keywords        JSONB DEFAULT '[]',     -- 关键词
    occurred_at     TIMESTAMPTZ NOT NULL,
    room_id         VARCHAR(100),
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 索引
CREATE INDEX idx_global_activity_time ON global_activity_index(occurred_at DESC);
CREATE INDEX idx_global_activity_type ON global_activity_index(activity_type);
CREATE INDEX idx_global_activity_importance ON global_activity_index(importance DESC);
CREATE INDEX idx_global_activity_keywords ON global_activity_index USING GIN(keywords);
```

### 18.3 全局索引视图

```
┌─────────────────────────────────────────────────────────────────┐
│                    全局索引视图 (Dashboard)                      │
│                                                                 │
│  时间线                                          │
│  ├── 今天                                                        │
│  │   ├── 🔴 高优先: Redis 集群部署决策                           │
│  │   ├── 📋 任务: 张三 - 完成 API 文档 (截止明天)                │
│  │   └── 📖 参考: 生产环境 Redis 配置                            │
│  ├── 昨天                                                        │
│  │   ├── 💬 讨论: 支付系统架构讨论 (15条消息)                    │
│  │   └── ❓ 问答: 如何处理 Redis 超时                            │
│  └── 本周                                                        │
│      ├── 📊 统计: 新增 23 条话题，12 条决策                      │
│      └── 👥 活跃: 张三(45条)、李四(38条)、王五(22条)             │
│                                                                 │
│  按类别筛选                                                      │
│  ├── 技术决策 (12) ├── 问答FAQ (8) ├── 待办 (15)               │
│  ├── 参考数据 (6)  ├── 问题缺陷 (4) └── 其他 (5)               │
│                                                                 │
│  按人员筛选                                                      │
│  └── @张三 @李四 @王五 全部                                      │
└─────────────────────────────────────────────────────────────────┘
```

### 18.4 索引更新机制

```
消息处理完成
      │
      ├── 创建/更新话题 → 更新全局索引
      │     importance = LLM评估重要性
      │
      ├── 创建待办 → 更新全局索引
      │     importance = 80 (高优先)
      │
      ├── 生成参考数据 → 更新全局索引
      │     importance = 60 (中优先)
      │
      └── 定时任务 (每小时)
            ├── 计算热度衰减
            ├── 合并相似活动
            └── 清理过期低重要度条目
```

---

## 19. 知识图谱（显式建模 + Schemaless 扩展）

### 19.1 设计理念

知识图谱采用**显式建模 + Schemaless 扩展**的混合架构：

```
┌─────────────────────────────────────────────────────────────────┐
│                    知识图谱双层架构                               │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  显式建模层（基类）                                        │  │
│  │                                                           │  │
│  │  • 固定的节点类型：person | team | topic | event | thing   │  │
│  │  • 固定的边类型：参与 | 负责 | 支持 | 依赖 | 提及 | ...    │  │
│  │  • 标准化的核心字段：node_key, display_name, status       │  │
│  │  • 统一的查询接口：按类型、按关系的标准查询                │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              +                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Schemaless 扩展层                                        │  │
│  │                                                           │  │
│  │  • 动态属性：attributes JSONB 存放任意字段                │  │
│  │  • 动态边类型：LLM 可发现新的关系类型                     │  │
│  │  • 动态扩展：根据业务场景新增节点子类型                   │  │
│  │  • 灵活探索：支持未预定义的查询和关联                     │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

**核心价值**：作为辅助的线索查询索引，帮助回答"谁在什么时候在哪里说了什么做了什么"。

### 19.2 显式建模部分（基类）

#### 19.2.1 固定节点类型

| 节点类型 | 说明 | 固定字段 | 动态扩展示例 |
|----------|------|----------|--------------|
| `person` | 人员 | node_key=用户ID, display_name | `{"role": "开发", "skills": ["Redis", "Python"]}` |
| `team` | 团队/群组 | node_key=群ID, display_name | `{"member_count": 45, "purpose": "技术讨论"}` |
| `topic` | 话题线索 | node_key=thread_id, display_name | `{"category": "tech_decision", "priority": "high"}` |
| `event` | 事件 | node_key=事件标识, display_name | `{"date": "2026-03-01", "type": "deployment"}` |
| `thing` | 事物 | node_key=唯一标识, display_name | `{"type": "service", "env": "prod", "owner": "张三"}` |

#### 19.2.2 固定边类型（显式关系）

| 边类型 | 说明 | source → target | 固定字段 | 动态扩展 |
|--------|------|-----------------|----------|----------|
| `participates_in` | 参与话题 | person → topic | role: 发起者/参与者 | `{"message_count": 15, "first_msg": "..."}` |
| `responsible_for` | 负责某事 | person → thing/topic | status: pending/done | `{"since": "2026-03-01", "deadline": "..."}` |
| `supports` | 提供支持 | person → person | support_type: 技术/资源/人力 | `{"context": "环境搭建", "status": "pending"}` |
| `depends_on` | 依赖关系 | thing → thing | criticality: 高/中/低 | `{"reason": "API调用", "impact": "..."}` |
| `mentions` | 提及关系 | person/topic → person/topic | context: 上下文 | `{"in_thread": "xxx", "sentiment": "positive"}` |
| `belongs_to` | 归属关系 | topic → team | primary: true/false | `{"cross_teams": ["团队A", "团队B"]}` |
| `occurred_in` | 发生在 | event/topic → team/time | - | `{"duration": "2h", "outcome": "..."}` |
| `requires` | 需要资源 | topic/person → thing | urgency: 高/中/低 | `{"amount": 3, "reason": "测试环境"}` |

### 19.3 图谱结构

```sql
-- 知识图谱节点表（显式建模 + Schemaless 扩展）
CREATE TABLE knowledge_nodes (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- 显式建模部分（固定字段）
    node_type       VARCHAR(50) NOT NULL,   -- person | team | topic | event | thing
    node_key        VARCHAR(500) NOT NULL,  -- 唯一标识
    display_name    VARCHAR(500),           -- 显示名称
    status          VARCHAR(50),            -- 状态（可选）

    -- Schemaless 扩展部分（动态属性）
    attributes      JSONB DEFAULT '{}',     -- 任意扩展属性

    -- 元数据
    source_count    INTEGER DEFAULT 0,      -- 来源证据数量
    confidence      FLOAT DEFAULT 0.5,      -- 置信度
    first_seen_at   TIMESTAMPTZ NOT NULL,
    last_seen_at    TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(node_type, node_key)
);

-- 知识图谱边表（显式建模 + Schemaless 扩展）
CREATE TABLE knowledge_edges (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- 显式建模部分（固定字段）
    source_id       UUID NOT NULL REFERENCES knowledge_nodes(id) ON DELETE CASCADE,
    target_id       UUID NOT NULL REFERENCES knowledge_nodes(id) ON DELETE CASCADE,
    edge_type       VARCHAR(100) NOT NULL,  -- 固定边类型或动态发现的新类型
    status          VARCHAR(50),            -- 状态（可选）

    -- Schemaless 扩展部分（动态属性）
    attributes      JSONB DEFAULT '{}',     -- 任意扩展属性

    -- 证据和置信度
    evidence        JSONB DEFAULT '[]',     -- 证据来源 [{thread_id, message_id, text}]
    weight          FLOAT DEFAULT 1.0,      -- 关系强度
    confidence      FLOAT DEFAULT 0.5,      -- 置信度

    -- 时间信息
    first_seen_at   TIMESTAMPTZ NOT NULL,
    last_seen_at    TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(source_id, target_id, edge_type)
);

-- 索引
CREATE INDEX idx_node_type ON knowledge_nodes(node_type);
CREATE INDEX idx_node_key ON knowledge_nodes(node_key);
CREATE INDEX idx_node_status ON knowledge_nodes(status) WHERE status IS NOT NULL;
CREATE INDEX idx_node_attrs ON knowledge_nodes USING GIN(attributes);
CREATE INDEX idx_node_search ON knowledge_nodes
    USING GIN(to_tsvector('simple', coalesce(display_name, '') || ' ' || coalesce(node_key, '')));

CREATE INDEX idx_edge_source ON knowledge_edges(source_id);
CREATE INDEX idx_edge_target ON knowledge_edges(target_id);
CREATE INDEX idx_edge_type ON knowledge_edges(edge_type);
CREATE INDEX idx_edge_status ON knowledge_edges(status) WHERE status IS NOT NULL;
CREATE INDEX idx_edge_attrs ON knowledge_edges USING GIN(attributes);

-- 边类型枚举视图（展示当前系统中存在的所有边类型）
CREATE OR REPLACE VIEW v_edge_types AS
SELECT DISTINCT edge_type, COUNT(*) as usage_count
FROM knowledge_edges
GROUP BY edge_type
ORDER BY usage_count DESC;

COMMENT ON TABLE knowledge_nodes IS '知识图谱节点：显式建模(固定字段) + Schemaless(attributes扩展)';
COMMENT ON TABLE knowledge_edges IS '知识图谱边：显式建模(固定字段) + Schemaless(attributes扩展)';
```

### 19.4 动态扩展机制

#### 19.4.1 动态节点子类型

显式定义了 5 种基本节点类型，但可以通过 attributes 扩展出子类型：

```json
// person 的扩展
{
  "sub_type": "developer",           // 动态子类型
  "skills": ["Redis", "Python"],     // 动态属性
  "experience_years": 5              // 动态属性
}

// thing 的扩展
{
  "sub_type": "service",             // 动态子类型：服务
  "tech_stack": ["FastAPI", "Redis"],
  "owner": "张三"
}

// thing 的扩展
{
  "sub_type": "resource",            // 动态子类型：资源
  "resource_type": "服务器",
  "amount_needed": 3,
  "status": "pending"
}
```

#### 19.4.2 动态边类型

显式定义了 8 种基本边类型，LLM 可以发现并创建新的边类型：

```json
// 固定边类型
{"edge_type": "supports", "attributes": {"support_type": "技术"}}

// LLM 动态发现的新边类型
{"edge_type": "mentor_of", "attributes": {"since": "2025-01", "context": "新人指导"}}
{"edge_type": "blocks", "attributes": {"reason": "资源未到位", "impact": "high"}}
{"edge_type": "reports_to", "attributes": {"formal": true}}
{"edge_type": "collaborates_with", "attributes": {"project": "RippleFlow"}}
```

新发现的边类型会被记录，经过验证后可以升级为固定边类型。

### 19.5 设计原则

| 原则 | 说明 |
|------|------|
| **显式建模保底** | 固定类型确保基本查询能力 |
| **Schemaless 扩展** | 支持业务变化和新发现 |
| **尽力而为** | 不保证完整，尽量从消息中提取 |
| **渐进积累** | 随消息处理逐步丰富 |
| **容错性** | 提取失败不影响主流程 |
| **辅助索引** | 作为线索查询的辅助手段 |

### 19.6 图谱构建流程（nullclaw 主导，尽力而为）

知识图谱构建是**策略行为**，完全由 nullclaw 管家实施。RippleFlow 平台仅提供图谱写入 API，不执行任何实体/关系提取逻辑。

```
┌─────────────────────────────────────────────────────────────────┐
│  RippleFlow 消息处理流水线（机制层，不含图谱逻辑）               │
│                                                                 │
│  Stage 4: 结构化提取（固定字段：决策/责任人/错误信息等）         │
│  Stage 5: 增量摘要更新                                           │
│  ⚠️ 已移交 nullclaw，不在平台流水线内执行                          │
│                ↓                                                │
│  流水线完成后 → HTTP POST 事件推送至 nullclaw                    │
│  事件载荷：{ thread_id, category, summary, messages[] }         │
└─────────────────────────────────────────────────────────────────┘
                ↓
┌─────────────────────────────────────────────────────────────────┐
│  nullclaw channels（接收 thread_processed 事件）                 │
│                                                                 │
│  nullclaw 决策：此话题是否值得提取实体和关系？                   │
│  （根据 category、内容复杂度、置信度阈值判断）                   │
│                ↓                                                │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  nullclaw 知识图谱提取 Routine（尽力而为）                 │  │
│  │                                                           │  │
│  │  1. LLM 识别实体和关系：                                  │  │
│  │     输入：话题摘要 + 关键消息 + 固定类型定义               │  │
│  │     输出：{                                               │  │
│  │       entities: [{type, key, name, attributes}],          │  │
│  │       relations: [{source, target, type, attributes}],    │  │
│  │       confidence                                          │  │
│  │     }                                                     │  │
│  │                                                           │  │
│  │  2. 实体归一化：                                          │  │
│  │     - person → 匹配 chat_users                           │  │
│  │     - team   → 匹配 chat_rooms                           │  │
│  │     - topic  → 关联 topic_threads.id                     │  │
│  │                                                           │  │
│  │  3. 调用平台 API 写入图谱（容错，失败不重试）：            │  │
│  │     POST /api/v1/knowledge/graph/nodes  写入节点          │  │
│  │     POST /api/v1/knowledge/graph/edges  写入关系          │  │
│  │     - 固定字段写入固定列                                  │  │
│  │     - 扩展属性写入 attributes JSONB                       │  │
│  │     - 新发现的边类型直接写入 edge_type 字段               │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

示例：nullclaw 处理话题事件后提取

话题摘要："张三希望赵六支持环境搭建，目前卡在测试服务器没到位"

nullclaw LLM 提取结果：
{
  "entities": [
    {"type": "person", "key": "张三", "name": "张三"},
    {"type": "person", "key": "赵六", "name": "赵六"},
    {"type": "thing", "key": "测试服务器", "name": "测试服务器",
     "attributes": {"sub_type": "resource", "amount": 3}},
    {"type": "thing", "key": "环境搭建", "name": "环境搭建",
     "attributes": {"sub_type": "task"}}
  ],
  "relations": [
    {"source": "赵六", "target": "张三", "type": "supports",
     "attributes": {"support_type": "技术", "context": "环境搭建", "status": "pending"}},
    {"source": "张三", "target": "测试服务器", "type": "requires",
     "attributes": {"urgency": "high"}},
    {"source": "测试服务器", "target": "环境搭建", "type": "blocks",
     "attributes": {"reason": "资源未到位"}}
  ]
}

nullclaw 调用：
  POST /api/v1/knowledge/graph/nodes  →  写入 4 个实体节点
  POST /api/v1/knowledge/graph/edges  →  写入 3 条关系边
```

**责任边界**：

| 层 | 职责 | 不做 |
|----|------|------|
| RippleFlow（机制） | 提供图谱读写 API；存储节点和边 | 不提取实体，不判断关系 |
| nullclaw（策略） | 决定何时提取；调用 LLM 识别实体关系；写入图谱 | 不修改流水线逻辑 |

### 19.7 图谱查询场景

**作为辅助索引，帮助线索查询：**

| 查询场景 | 查询方式 | 返回结果 |
|----------|----------|----------|
| **谁参与了 X 话题？** | `MATCH (p:person)-[:participates_in]->(t:topic{key:X})` | 人员列表+角色 |
| **张三需要谁的支持？** | `MATCH (p:person{key:张三})<-[:supports]-(:person)` | 支持者列表 |
| **Redis 相关有哪些人？** | `MATCH (p:person)-[r]->(t:thing) WHERE t.key LIKE '%Redis%'` | 人+关系类型 |
| **什么阻塞了这个项目？** | `MATCH (x)-[:blocks]->(t:topic{key:X})` | 阻塞点+原因 |
| **需要哪些资源？** | `MATCH (t:topic{key:X})<-[:requires]-(r:thing)` | 资源列表+状态 |
| **支持关系网络** | `MATCH (a)-[:supports]->(b)` | 支持关系图 |

### 19.8 图谱 API

```yaml
# 知识图谱查询接口
GET /api/v1/knowledge/graph/search:
  summary: 搜索知识图谱
  parameters:
    - name: q
      in: query
      description: 搜索关键词
    - name: node_type
      in: query
      description: 节点类型过滤（显式类型）
    - name: sub_type
      in: query
      description: 子类型过滤（动态类型，在attributes.sub_type中）
    - name: depth
      in: query
      description: 关联深度（默认1）
  responses:
    200:
      data:
        nodes: [{id, type, key, name, status, attributes}]
        edges: [{source, target, type, status, attributes}]

GET /api/v1/knowledge/graph/node/{node_id}/neighbors:
  summary: 获取节点的邻居
  parameters:
    - name: direction
      in: query
      description: in | out | both
    - name: edge_types
      in: query
      description: 边类型过滤
  responses:
    200:
      data:
        neighbors: [{node, edge_type, edge_status, edge_attributes}]

GET /api/v1/knowledge/graph/support-network:
  summary: 获取支持关系网络
  parameters:
    - name: person_id
      in: query
      description: 指定人员（可选，不传则返回全部）
  responses:
    200:
      data:
        support_relations: [{supporter, supported, support_type, context, status}]

GET /api/v1/knowledge/graph/bottlenecks:
  summary: 获取阻塞关系
  responses:
    200:
      data:
        blockers: [{blocked_node, blocking_node, reason, impact}]

GET /api/v1/knowledge/graph/resource-needs:
  summary: 获取资源需求
  parameters:
    - name: status
      in: query
      description: pending | fulfilled | all
  responses:
    200:
      data:
        needs: [{requester, resource, amount, urgency, status}]

GET /api/v1/knowledge/graph/edge-types:
  summary: 获取系统中所有边类型（包括动态发现的）
  responses:
    200:
      data:
        fixed_types: [participates_in, responsible_for, supports, ...]
        dynamic_types: [{type, count, first_seen, examples}]
```

### 19.9 与主索引的关系

```
┌─────────────────────────────────────────────────────────────────┐
│                        查询流程                                  │
│                                                                 │
│  用户查询："张三的工作有什么阻塞？"                             │
│                                                                 │
│  方式1：主索引（精确）                                           │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ SELECT * FROM action_items                                │  │
│  │ WHERE assignee = '张三' AND status != 'done'              │  │
│  └───────────────────────────────────────────────────────────┘  │
│  → 返回：张三的待办列表                                         │
│                                                                 │
│  方式2：知识图谱（辅助）                                         │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ MATCH (t:thing)-[:blocks]->(task:thing)                   │  │
│  │ MATCH (p:person{key:'张三'})-[:responsible_for]->(task)   │  │
│  │ RETURN t, task, p                                         │  │
│  └───────────────────────────────────────────────────────────┘  │
│  → 返回：阻塞张三的事物和原因                                   │
│                                                                 │
│  组合查询：主索引 + 知识图谱                                     │
│  → 更全面的线索发现                                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## 20. 行为分析（新增）

### 20.1 概念

行为分析模块分为两层：
- **数据采集层（RippleFlow 机制）**：记录用户行为日志，提供统计查询 API
- **模式分析层（nullclaw 策略）**：挖掘行为模式、生成推荐、评估贡献——所有涉及"理解和判断"的部分由 nullclaw 通过 API 查询后完成

### 20.2 行为数据表

```sql
-- 用户行为日志
CREATE TABLE user_behavior_logs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         VARCHAR(255) NOT NULL,
    behavior_type   VARCHAR(100) NOT NULL,  -- search | view | create | complete | subscribe
    target_type     VARCHAR(100),           -- thread | todo | reference
    target_id       UUID,
    context         JSONB DEFAULT '{}',
    session_id      UUID,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- 用户模式表（聚合）
CREATE TABLE user_behavior_patterns (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         VARCHAR(255) NOT NULL UNIQUE,
    active_hours    JSONB DEFAULT '{}',     -- 活跃时段 {"9": 15, "10": 32, ...}
    search_patterns JSONB DEFAULT '{}',     -- 搜索模式 {"tech": 20, "faq": 15}
    topic_interests JSONB DEFAULT '{}',     -- 兴趣话题 {"Redis": 10, "支付": 8}
    avg_response_time_hours FLOAT,          -- 平均响应时间
    completion_rate FLOAT,                  -- 任务完成率
    contribution_score INTEGER DEFAULT 0,   -- 贡献分
    last_updated    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_behavior_user ON user_behavior_logs(user_id, created_at DESC);
CREATE INDEX idx_behavior_type ON user_behavior_logs(behavior_type);
```

### 20.3 行为分析维度

> **执行主体说明**：下表中"应用"列的推荐、评估、优化行为，均由 **nullclaw** 通过查询行为分析 API 后决策实施，RippleFlow 平台只负责数据聚合和 API 暴露。

| 维度 | 指标 | 应用（由 nullclaw 实施） |
|------|------|------|
| **活跃时段** | 各小时活跃度 | 推送时机优化 |
| **搜索模式** | 高频搜索词 | 推荐内容 |
| **兴趣话题** | 关注话题分布 | 内容推荐 |
| **响应时间** | 任务响应速度 | 工作效率评估 |
| **完成率** | 任务完成比例 | 可靠性评估 |
| **贡献分** | 知识贡献度量 | 激励机制 |

### 20.4 行为分析 API

```yaml
# 行为分析接口
GET /api/v1/analytics/user/{user_id}/behavior:
  summary: 获取用户行为分析
  responses:
    200:
      data:
        active_hours: {hour: count}
        search_patterns: {category: count}
        topic_interests: {topic: score}
        completion_rate: float
        contribution_score: int

GET /api/v1/analytics/team/overview:
  summary: 团队行为概览
  responses:
    200:
      data:
        total_contributions: int
        top_contributors: [{user_id, score}]
        hot_topics: [{topic, count}]
        activity_trend: [{date, count}]
```

---

## 21. 热点分析与闭环状态（新增）

热点分析模块分为两层：
- **数值计算层（RippleFlow 机制）**：基于消息数、参与人数、新鲜度等统计指标计算热度分，由 nullclaw cron 定期触发 `POST /api/v1/analytics/heat/calculate` 写入 `topic_heat_scores` 表
- **洞察与推送层（nullclaw 策略）**：解读热度数据、识别异常趋势、决定推送对象和时机

热点分析模块帮助用户快速了解：
- **热点话题**：哪些话题正在被频繁讨论
- **活跃人员**：谁最活跃、贡献最多
- **闭环状态**：哪些事情已经结束、哪些还在进行、哪些需要关注

### 21.2 话题热度模型

```sql
-- 话题热度表（定时计算）
CREATE TABLE topic_heat_scores (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    thread_id       UUID NOT NULL REFERENCES topic_threads(id),
    score_date      DATE NOT NULL,

    -- 热度因子
    message_count   INTEGER DEFAULT 0,      -- 消息数量
    participant_count INTEGER DEFAULT 0,    -- 参与人数
    mention_count   INTEGER DEFAULT 0,      -- 被提及次数
    view_count      INTEGER DEFAULT 0,      -- 浏览次数
    action_count    INTEGER DEFAULT 0,      -- 关联待办数
    recency_score   FLOAT DEFAULT 0,        -- 新鲜度（最近活跃时间）
    importance_score FLOAT DEFAULT 0,       -- 重要性（决策类更高）

    -- 综合热度
    heat_score      FLOAT DEFAULT 0,        -- 综合热度分
    heat_rank       INTEGER,                -- 当日排名

    calculated_at   TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(thread_id, score_date)
);

CREATE INDEX idx_heat_score ON topic_heat_scores(score_date, heat_score DESC);
CREATE INDEX idx_heat_thread ON topic_heat_scores(thread_id);
```

### 21.3 热度计算公式

> **执行主体**：热度计算是纯数值统计（无自然语言理解），由 RippleFlow 平台提供计算接口，**nullclaw cron** 定期触发调用（每小时或每天），结果写入 `topic_heat_scores` 表。

```python
# RippleFlow 平台侧热度计算逻辑（由 nullclaw 触发调用）
def calculate_heat_score(thread, date):
    """
    话题热度计算

    热度 = 消息因子 × 参与人因子 × 新鲜度因子 × 重要性因子
    """

    # 消息因子：对数增长，避免过多主导
    message_factor = log(1 + message_count) * 10

    # 参与人因子：更多人参与 = 更热
    participant_factor = participant_count * 5

    # 新鲜度因子：最近活跃的话题更热
    hours_since_last_active = (now() - thread.last_message_at).total_seconds() / 3600
    recency_factor = 100 / (1 + hours_since_last_active / 24)  # 半衰期24小时

    # 重要性因子：不同类别权重不同
    importance_weights = {
        'tech_decision': 2.0,   # 技术决策最重要
        'action_item': 1.5,     # 待办次之
        'bug_incident': 1.5,    # 问题缺陷
        'qa_faq': 1.2,          # 问答
        'reference_data': 1.0,  # 参考数据
        'meeting_notes': 1.0,   # 会议纪要
        'team_info': 0.8,       # 团队信息
        'product_discuss': 0.8, # 产品讨论
        'others': 0.5           # 其他
    }
    importance_factor = importance_weights.get(thread.category, 0.5)

    # 综合热度
    heat_score = (message_factor + participant_factor) * recency_factor * importance_factor

    return heat_score
```

### 21.4 话题状态模型

```
话题状态分类：

┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   🔴 进行中 (Active)                                            │
│   ├── 有新消息（7天内）                                          │
│   ├── 关联待办未完成                                             │
│   └── 决策类话题未关闭                                           │
│                                                                 │
│   🟡 待关注 (Needs Attention)                                    │
│   ├── 无新消息（7-30天）                                         │
│   ├── 关联待办即将到期                                           │
│   ├── 敏感授权待处理                                             │
│   └── 长期无进展                                                 │
│                                                                 │
│   🟢 已结束 (Closed)                                             │
│   ├── 无新消息（30天+）                                          │
│   ├── 所有待办已完成                                              │
│   ├── 决策已关闭                                                 │
│   └── 明确标记为"已解决"                                         │
│                                                                 │
│   🔵 未闭环 (Open Loop)                                          │
│   ├── 提出问题但无答案                                           │
│   ├── 决策后有后续待办但未完成                                    │
│   ├── 有人负责但无进展                                           │
│   └── 等待外部输入                                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 21.5 状态判断规则

```sql
-- 话题状态视图
CREATE VIEW topic_status_view AS
SELECT
    t.id,
    t.title,
    t.category,
    t.last_message_at,

    -- 判断状态
    CASE
        -- 进行中：最近7天有消息 或 有未完成待办
        WHEN t.last_message_at > NOW() - INTERVAL '7 days' THEN 'active'
        WHEN EXISTS (
            SELECT 1 FROM action_items a
            WHERE a.thread_id = t.id AND a.status != 'done'
        ) THEN 'active'

        -- 待关注：7-30天无消息 或 敏感待处理
        WHEN t.last_message_at BETWEEN NOW() - INTERVAL '30 days' AND NOW() - INTERVAL '7 days' THEN 'needs_attention'
        WHEN EXISTS (
            SELECT 1 FROM sensitive_authorizations s
            WHERE s.thread_id = t.id AND s.overall_status = 'pending'
        ) THEN 'needs_attention'

        -- 未闭环：有问题无答案 或 决策后有待办未完成
        WHEN t.category = 'qa_faq' AND NOT EXISTS (
            SELECT 1 FROM thread_modifications m
            WHERE m.thread_id = t.id AND m.modification_type = 'answer_confirmed'
        ) THEN 'open_loop'
        WHEN t.category = 'tech_decision' AND EXISTS (
            SELECT 1 FROM action_items a
            WHERE a.thread_id = t.id AND a.status != 'done'
        ) THEN 'open_loop'

        -- 已结束：30天+无消息 且 无待办
        WHEN t.last_message_at < NOW() - INTERVAL '30 days' THEN 'closed'

        ELSE 'closed'
    END AS status,

    -- 未闭环原因
    CASE
        WHEN t.category = 'qa_faq' THEN 'pending_answer'
        WHEN t.category = 'tech_decision' THEN 'pending_action'
        ELSE NULL
    END AS open_loop_reason

FROM topic_threads t;
```

### 21.6 人员活跃度与贡献度

```sql
-- 人员活跃度统计
CREATE TABLE user_activity_stats (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         VARCHAR(255) NOT NULL UNIQUE,

    -- 活跃度指标
    messages_count      INTEGER DEFAULT 0,     -- 发言次数
    threads_created     INTEGER DEFAULT 0,     -- 发起话题数
    threads_participated INTEGER DEFAULT 0,    -- 参与话题数
    decisions_made      INTEGER DEFAULT 0,     -- 做出决策数
    questions_asked     INTEGER DEFAULT 0,     -- 提问数
    questions_answered  INTEGER DEFAULT 0,     -- 回答数

    -- 贡献度指标
    todos_created       INTEGER DEFAULT 0,     -- 创建待办数
    todos_completed     INTEGER DEFAULT 0,     -- 完成待办数
    references_added    INTEGER DEFAULT 0,     -- 添加参考数据
    summaries_edited    INTEGER DEFAULT 0,     -- 编辑摘要次数
    feedback_given      INTEGER DEFAULT 0,     -- 给出反馈次数

    -- 质量指标
    avg_response_time   FLOAT,                 -- 平均响应时间（小时）
    completion_rate     FLOAT DEFAULT 0,       -- 任务完成率
    helpful_rate        FLOAT,                 -- 回答有帮助率

    -- 综合分数
    activity_score      INTEGER DEFAULT 0,     -- 活跃度分
    contribution_score  INTEGER DEFAULT 0,     -- 贡献度分

    -- 时间维度
    period_start        DATE,                  -- 统计周期开始
    period_end          DATE,                  -- 统计周期结束
    last_updated        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_user_activity_score ON user_activity_stats(activity_score DESC);
CREATE INDEX idx_user_contrib_score ON user_activity_stats(contribution_score DESC);
```

### 21.7 活跃度与贡献度计算

```python
def calculate_user_scores(user_id, period):
    """
    计算用户活跃度和贡献度
    """

    # 活跃度 = 发言 + 参与 + 决策 + 问答
    activity_score = (
        messages_count * 1 +           # 每条消息 1 分
        threads_created * 5 +          # 发起话题 5 分
        threads_participated * 3 +     # 参与话题 3 分
        decisions_made * 10 +          # 做出决策 10 分
        questions_asked * 2 +          # 提问 2 分
        questions_answered * 5         # 回答 5 分
    )

    # 贡献度 = 待办 + 参考 + 编辑 + 反馈（带质量权重）
    contribution_score = (
        todos_created * 3 +            # 创建待办 3 分
        todos_completed * 8 +          # 完成待办 8 分
        references_added * 5 +         # 添加参考 5 分
        summaries_edited * 4 +         # 编辑摘要 4 分
        feedback_given * 2 +           # 反馈 2 分
        int(completion_rate * 20) +    # 完成率加成
        int(helpful_rate * 10)         # 有帮助率加成
    )

    return activity_score, contribution_score
```

### 21.8 全局视角仪表盘

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        RippleFlow 全局视角                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  📊 热点话题 Top 5                              活跃度趋势              │
│  ┌─────────────────────────────────────────┐   ┌──────────────────┐    │
│  │ 🔥 Redis 集群部署 (156分)               │   │  ▃▅▇▅▃▂▄▆       │    │
│  │ 🔥 支付系统架构讨论 (128分)              │   │  周一 周三 周五   │    │
│  │ 🔥 API 接口规范 (98分)                   │   └──────────────────┘    │
│  │ 💬 产品需求评审 (76分)                   │                          │
│  │ 💬 测试环境配置 (54分)                   │   待办完成率: 78%         │
│  └─────────────────────────────────────────┘   问答解决率: 85%         │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  📈 状态分布                                    🏆 活跃贡献榜            │
│  ┌─────────────────────────────────────────┐   ┌──────────────────┐    │
│  │  🔴 进行中: 23                          │   │ 张三: 458分 🥇   │    │
│  │  🟡 待关注: 8                           │   │ 李四: 392分 🥈   │    │
│  │  🔵 未闭环: 5                           │   │ 王五: 287分 🥉   │    │
│  │  🟢 已结束: 156                         │   │ 赵六: 198分      │    │
│  └─────────────────────────────────────────┘   └──────────────────┘    │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ⚠️ 需要关注事项                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │ • 敏感授权待处理: 3 条 (超时 2 天)                                  │  │
│  │ • 待办即将到期: 5 条 (张三 2, 李四 2, 王五 1)                       │  │
│  │ • 未闭环问答: 5 条 (等待答案)                                       │  │
│  │ • 待关注话题: 8 条 (7天无更新)                                      │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 21.9 全局视角 API

```yaml
# 全局视角接口
GET /api/v1/analytics/global/overview:
  summary: 全局视角概览
  responses:
    200:
      data:
        total_threads: int
        status_distribution: {active, needs_attention, open_loop, closed}
        hot_topics: [{id, title, heat_score, category}]
        activity_trend: [{date, count}]
        completion_rates: {todo, qa}

GET /api/v1/analytics/global/hot-topics:
  summary: 热点话题列表
  parameters:
    - name: period
      in: query
      description: week | month
    - name: limit
      in: query
      default: 10
  responses:
    200:
      data:
        topics: [{id, title, heat_score, rank, factors}]

GET /api/v1/analytics/global/attention-items:
  summary: 需要关注的事项
  responses:
    200:
      data:
        sensitive_pending: [{id, created_at, escalation_in}]
        todos_due_soon: [{id, title, assignee, due_date}]
        open_loops: [{id, title, reason, days_open}]
        stale_threads: [{id, title, last_active}]

GET /api/v1/analytics/users/contribution-rank:
  summary: 贡献度排行榜
  parameters:
    - name: period
      in: query
      description: week | month | all
    - name: limit
      in: query
      default: 10
  responses:
    200:
      data:
        rank: [{user_id, display_name, activity_score, contribution_score, rank}]
```

---

## 22. 信息链视图（新增）

### 22.1 概念

信息链视图是系统核心的态势感知界面，将分散的信息串联成**时间-人物-事件-状态-瓶颈-资源-支持**的完整链条。

### 22.2 信息链结构

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          信息链视图                                      │
│                                                                         │
│  时间轴 ←─────────────────────────────────────────────────────────────→ │
│                                                                         │
│  2026-03-01                                                             │
│  │                                                                      │
│  ├── 📍 事件：Redis 集群部署方案讨论                                    │
│  │   ├── 👤 发起人：张三                                                │
│  │   ├── 📍 发生在：产品技术群                                          │
│  │   └── 📊 状态：🔴 进行中 (12天)                                      │
│  │                                                                      │
│  │   ┌──────────────────────────────────────────────────────────────┐  │
│  │   │  🔗 关联链条                                                  │  │
│  │   │                                                              │  │
│  │   │  决策                                                        │  │
│  │   │  ├── ✅ 03-02 决定使用 Redis Cluster                         │  │
│  │   │  └── 📝 李四、王五参与决策                                    │  │
│  │   │                                                              │  │
│  │   │  待办                                                        │  │
│  │   │  ├── ⚠️ 张三 - 搭建测试环境 [卡住: 等待服务器]               │  │
│  │   │  ├── 🔄 李四 - 编写部署文档 [进行中]                          │  │
│  │   │  └── ⏳ 王五 - 准备监控方案 [待开始]                          │  │
│  │   │                                                              │  │
│  │   │  关联话题                                                    │  │
│  │   │  └── 📚 上周: Redis 连接池配置讨论                            │  │
│  │   └──────────────────────────────────────────────────────────────┘  │
│  │                                                                      │
│  │   ┌──────────────────────────────────────────────────────────────┐  │
│  │   │  ⚠️ 瓶颈识别                                                  │  │
│  │   │                                                              │  │
│  │   │  🔴 测试服务器未到位                                         │  │
│  │   │     └── 阻塞: 张三的待办无法推进                              │  │
│  │   │     └── 影响: 整体部署进度延迟                               │  │
│  │   └──────────────────────────────────────────────────────────────┘  │
│  │                                                                      │
│  │   ┌──────────────────────────────────────────────────────────────┐  │
│  │   │  📦 资源需求                                                  │  │
│  │   │                                                              │  │
│  │   │  需要                        来源                            │  │
│  │   │  ────                        ────                            │  │
│  │   │  3台测试服务器        ←      运维团队                        │  │
│  │   │  Redis配置模板        ←      王五                            │  │
│  │   └──────────────────────────────────────────────────────────────┘  │
│  │                                                                      │
│  │   ┌──────────────────────────────────────────────────────────────┐  │
│  │   │  🤝 支持关系                                                  │  │
│  │   │                                                              │  │
│  │   │  张三 ──需要支持──→ 赵六 (运维)                              │  │
│  │   │  李四 ──需要支持──→ 王五 (监控方案)                          │  │
│  │   └──────────────────────────────────────────────────────────────┘  │
│  │                                                                      │
└─────────────────────────────────────────────────────────────────────────┘
```

### 22.3 信息链数据结构

```sql
-- 信息链视图数据结构（用于前端展示）
-- 这是一个聚合视图，从多个表组合数据

-- 信息链 API 返回结构
{
  "thread_id": "xxx",
  "title": "Redis 集群部署方案讨论",
  "timeline": {
    "started_at": "2026-03-01T10:00:00Z",
    "last_active_at": "2026-03-03T15:30:00Z",
    "duration_days": 12
  },
  "origin": {
    "initiator": {"id": "zhangsan", "name": "张三"},
    "location": {"id": "room-001", "name": "产品技术群"}
  },
  "status": {
    "current": "active",
    "label": "进行中",
    "days_in_status": 12
  },
  "participants": [
    {"id": "zhangsan", "name": "张三", "role": "发起者"},
    {"id": "lisi", "name": "李四", "role": "决策者"},
    {"id": "wangwu", "name": "王五", "role": "参与者"}
  ],
  "chain": {
    "decisions": [
      {
        "id": "dec-001",
        "content": "决定使用 Redis Cluster",
        "made_at": "2026-03-02T14:00:00Z",
        "made_by": ["李四", "王五"]
      }
    ],
    "todos": [
      {
        "id": "todo-001",
        "title": "搭建测试环境",
        "assignee": "张三",
        "status": "blocked",
        "due_date": "2026-03-05",
        "blocked_by": "测试服务器未到位"
      },
      {
        "id": "todo-002",
        "title": "编写部署文档",
        "assignee": "李四",
        "status": "in_progress",
        "due_date": "2026-03-08"
      },
      {
        "id": "todo-003",
        "title": "准备监控方案",
        "assignee": "王五",
        "status": "pending",
        "due_date": "2026-03-10"
      }
    ],
    "related_threads": [
      {
        "id": "thread-yyy",
        "title": "Redis 连接池配置讨论",
        "relation": "相关",
        "last_active": "2026-02-25"
      }
    ]
  },
  "bottlenecks": [
    {
      "id": "bn-001",
      "type": "resource_missing",
      "description": "测试服务器未到位",
      "blocked_items": ["todo-001"],
      "impact": "high",
      "suggested_action": "联系运维团队确认服务器到位时间"
    }
  ],
  "resources": [
    {
      "need": "3台测试服务器",
      "source": "运维团队",
      "status": "pending",
      "urgency": "high"
    },
    {
      "need": "Redis配置模板",
      "source": "王五",
      "status": "pending",
      "urgency": "medium"
    }
  ],
  "support_relations": [
    {
      "from": "张三",
      "to": "赵六",
      "support_type": "资源",
      "context": "测试服务器",
      "status": "pending"
    },
    {
      "from": "李四",
      "to": "王五",
      "support_type": "技术",
      "context": "监控方案",
      "status": "pending"
    }
  ]
}
```

### 22.4 信息链 API

```yaml
# 信息链视图接口
GET /api/v1/threads/{thread_id}/chain:
  summary: 获取话题的完整信息链
  parameters:
    - name: include_related
      in: query
      description: 是否包含关联话题
      default: true
    - name: depth
      in: query
      description: 关联深度
      default: 1
  responses:
    200:
      data:
        thread: {id, title, status}
        timeline: {started_at, last_active_at, duration_days}
        origin: {initiator, location}
        participants: [{id, name, role}]
        chain:
          decisions: [{id, content, made_at, made_by}]
          todos: [{id, title, assignee, status, blocked_by}]
          related_threads: [{id, title, relation}]
        bottlenecks: [{id, type, description, blocked_items, impact}]
        resources: [{need, source, status, urgency}]
        support_relations: [{from, to, support_type, context, status}]

GET /api/v1/chain/bottlenecks:
  summary: 获取所有瓶颈
  parameters:
    - name: impact
      in: query
      description: 过滤影响级别 high | medium | low
  responses:
    200:
      data:
        bottlenecks: [{thread_id, thread_title, bottleneck_id, description, blocked_items, impact}]

GET /api/v1/chain/resources-pending:
  summary: 获取待满足的资源需求
  responses:
    200:
      data:
        resources: [{thread_id, thread_title, need, source, status, urgency}]

GET /api/v1/chain/support-network:
  summary: 获取支持关系网络
  responses:
    200:
      data:
        relations: [{from, to, support_type, context, status, thread_id}]
```

---

## 23. 瓶颈自动识别（新增）

### 23.1 瓶颈类型

| 瓶颈类型 | 识别规则 | 严重程度 | 建议行动 |
|----------|----------|----------|----------|
| **待办超期** | due_date < NOW() AND status != 'done' | 🔴 高 | 跟进负责人 |
| **资源缺失** | 消息包含"需要/缺少"但无后续确认 | 🟡 中 | 确认资源状态 |
| **单人阻塞** | 多个待办依赖同一人，该人有超期任务 | 🟡 中 | 重新分配 |
| **长期无进展** | 话题14天无更新 + 有未完成待办 | 🟡 中 | 跟进状态 |
| **敏感授权挂起** | sensitive_pending > 3天 | 🟡 中 | 提醒当事人 |
| **问答无响应** | 问答类话题72小时无答案确认 | 🟠 低 | 推荐相关人员 |
| **外部依赖** | 消息提到"等待外部/第三方" | 🟡 中 | 确认进度 |

### 23.2 瓶颈识别规则

> **执行主体**：瓶颈识别逻辑（包括判断"是否超期"、"是否阻塞"、"建议行动"）属于策略决策，由 **nullclaw** 定期执行（通过 cron Routine），查询 RippleFlow 平台 API 后由 LLM 综合判断。下方为 nullclaw 侧 Routine 的逻辑示意（非平台代码）。

```python
# nullclaw 侧瓶颈识别 Routine 逻辑示意（伪代码）
# 实际运行在 nullclaw，通过调用 RippleFlow REST API 获取数据
class BottleneckDetector:

    def detect_bottlenecks(self):
        """检测系统中的瓶颈"""
        bottlenecks = []

        # 1. 待办超期
        overdue_todos = self.query_overdue_todos()
        for todo in overdue_todos:
            bottlenecks.append({
                "type": "todo_overdue",
                "severity": "high",
                "thread_id": todo.thread_id,
                "description": f"待办「{todo.title}」已超期 {todo.days_overdue} 天",
                "blocked_items": [todo.id],
                "suggested_action": f"跟进 {todo.assignee} 确认进度"
            })

        # 2. 资源缺失（从知识图谱提取）
        resource_blocks = self.query_resource_blocks()
        for block in resource_blocks:
            bottlenecks.append({
                "type": "resource_missing",
                "severity": "medium",
                "thread_id": block.thread_id,
                "description": f"需要「{block.resource}」但未确认到位",
                "blocked_items": block.blocked_todos,
                "suggested_action": f"联系 {block.source} 确认资源状态"
            })

        # 3. 单人阻塞
        person_blocks = self.detect_person_blocks()
        for block in person_blocks:
            bottlenecks.append({
                "type": "person_blocked",
                "severity": "medium",
                "thread_id": block.thread_id,
                "description": f"{block.person} 有 {block.overdue_count} 个超期待办，阻塞其他任务",
                "blocked_items": block.blocked_todos,
                "suggested_action": "考虑重新分配或提供支持"
            })

        # 4. 长期无进展
        stale_threads = self.query_stale_threads()
        for thread in stale_threads:
            bottlenecks.append({
                "type": "stale_progress",
                "severity": "medium",
                "thread_id": thread.id,
                "description": f"话题「{thread.title}」{thread.days_stale} 天无更新",
                "blocked_items": thread.pending_todos,
                "suggested_action": "跟进状态或关闭话题"
            })

        # 5. 敏感授权挂起
        pending_sensitive = self.query_pending_sensitive()
        for auth in pending_sensitive:
            bottlenecks.append({
                "type": "sensitive_pending",
                "severity": "medium",
                "thread_id": auth.thread_id,
                "description": f"敏感授权等待 {auth.days_pending} 天",
                "blocked_items": [auth.id],
                "suggested_action": "提醒当事人或升级管理员"
            })

        # 6. 问答无响应
        unanswered_qa = self.query_unanswered_qa()
        for qa in unanswered_qa:
            bottlenecks.append({
                "type": "qa_unanswered",
                "severity": "low",
                "thread_id": qa.id,
                "description": f"问题「{qa.title}」{qa.hours_unanswered} 小时无答案",
                "blocked_items": [],
                "suggested_action": f"推荐相关专家: {qa.suggested_experts}"
            })

        return bottlenecks

    def query_resource_blocks(self):
        """从知识图谱查询资源阻塞"""
        query = """
        MATCH (p:person)-[:requires]->(r:thing)
        WHERE r.attributes.status = 'pending'
        OPTIONAL MATCH (r)-[:blocks]->(t:todo)
        RETURN p, r, collect(t) as blocked_todos
        """
        return self.graph_query(query)
```

### 23.3 瓶颈状态表

```sql
-- 瓶颈记录表
CREATE TABLE bottleneck_records (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    thread_id       UUID REFERENCES topic_threads(id),

    bottleneck_type VARCHAR(50) NOT NULL,  -- todo_overdue | resource_missing | person_blocked | ...
    severity        VARCHAR(20) NOT NULL,  -- high | medium | low
    description     TEXT NOT NULL,

    blocked_items   JSONB DEFAULT '[]',    -- 被阻塞的项目ID列表
    impact_scope    JSONB DEFAULT '{}',    -- 影响范围

    suggested_action TEXT,                 -- 建议行动
    assigned_to     VARCHAR(255),          -- 分配给谁处理
    resolved_at     TIMESTAMPTZ,           -- 解决时间

    first_detected  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_updated    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_bottleneck_thread ON bottleneck_records(thread_id);
CREATE INDEX idx_bottleneck_type ON bottleneck_records(bottleneck_type);
CREATE INDEX idx_bottleneck_severity ON bottleneck_records(severity);
CREATE INDEX idx_bottleneck_unresolved ON bottleneck_records(severity, first_detected) WHERE resolved_at IS NULL;
```

### 23.4 瓶颈通知 Routine

```markdown
# routine_bottleneck_notify.md

## 触发条件
- 定时任务：每天 9:00

## 执行步骤

1. 检测瓶颈
   使用工具：detect_bottlenecks()

2. 筛选高优先级
   过滤 severity = 'high' 或持续超过 3 天的 medium 级别

3. 通知相关人员
   FOR each bottleneck:
     IF bottleneck.type == 'todo_overdue':
       通知: 待办负责人 + 话题当事人
     ELSE IF bottleneck.type == 'resource_missing':
       通知: 资源来源方 + 需求方
     ELSE IF bottleneck.type == 'person_blocked':
       通知: 被阻塞者 + 其上级（如有）

4. 汇总报告
   发送每日瓶颈汇总到主群

## 实时反思
检查是否有新发现的瓶颈类型，建议新增检测规则
```

---

## 24. 资源需求与支持关系提取（新增）

> **执行主体**：资源需求和支持关系的语义识别属于 AI 决策行为，由 **nullclaw** 在收到话题处理完成事件后通过 LLM 提取，并调用平台 API 写入知识图谱。RippleFlow Stage 4 流水线**不**包含此逻辑。

### 24.1 资源需求提取模式

nullclaw 使用以下模式对话题摘要进行分析，识别资源需求：

```yaml
# Stage 4 资源需求提取规则
resource_extraction_patterns:
  explicit_needs:
    - pattern: "需要{n}{resource}"
      extract: {need: n, resource: resource}
    - pattern: "缺少{resource}"
      extract: {status: missing, resource: resource}
    - pattern: "希望{person/team}支持{task}"
      extract: {support_from: person, for: task}
    - pattern: "等{resource}到位"
      extract: {blocked_by: resource}
    - pattern: "如果有{resource}就能{action}"
      extract: {need: resource, enables: action}

  implicit_needs:
    - pattern: "{task}卡在{reason}"
      extract: {blocked_by: reason, task: task}
    - pattern: "等{person}的{resource}"
      extract: {waiting_for: person, resource: resource}
    - pattern: "{person}负责{task}，但{obstacle}"
      extract: {assignee: person, task: task, obstacle: obstacle}

  examples:
    - input: "需要3台测试服务器"
      output: {need: 3, resource: "测试服务器", status: "pending"}

    - input: "希望赵六支持环境搭建"
      output: {support_from: "赵六", for: "环境搭建", status: "pending"}

    - input: "搭建环境卡在服务器没到位"
      output: {task: "搭建环境", blocked_by: "服务器未到位", status: "blocked"}
```

### 24.2 支持关系提取模式

```yaml
# 支持关系提取规则
support_extraction_patterns:
  explicit_support:
    - pattern: "{person}帮我{task}"
      extract: {supporter: person, supported: speaker, task: task}
    - pattern: "希望{person}支持{task}"
      extract: {supporter: person, for: task}
    - pattern: "{person}来{task}"
      extract: {supporter: person, task: task}
    - pattern: "找{person}要{resource}"
      extract: {supporter: person, resource: resource}

  implicit_support:
    - pattern: "{person}是这方面的专家"
      extract: {expert: person, context: "expertise"}
    - pattern: "这个{task}问问{person}"
      extract: {consult: person, task: task}

  examples:
    - input: "张三帮李四搭建环境"
      output: {supporter: "张三", supported: "李四", task: "搭建环境"}

    - input: "这个Redis问题问问王五"
      output: {consult: "王五", topic: "Redis问题"}
```

### 24.3 支持关系表

```sql
-- 支持关系表（用于团队协作分析）
CREATE TABLE support_relations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    thread_id       UUID REFERENCES topic_threads(id),

    supporter_id    VARCHAR(255) NOT NULL,  -- 提供支持的人
    supported_id    VARCHAR(255),           -- 被支持的人（可选）
    support_type    VARCHAR(100),           -- 技术 | 资源 | 人力 | 决策
    support_context TEXT,                   -- 支持内容描述

    status          VARCHAR(50) DEFAULT 'pending', -- pending | fulfilled | blocked
    fulfilled_at    TIMESTAMPTZ,

    evidence_text   TEXT,                   -- 原始消息文本
    message_id      UUID REFERENCES messages(id),

    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_support_thread ON support_relations(thread_id);
CREATE INDEX idx_support_supporter ON support_relations(supporter_id);
CREATE INDEX idx_support_supported ON support_relations(supported_id);
CREATE INDEX idx_support_status ON support_relations(status);
```

### 24.4 协作网络分析

```
┌─────────────────────────────────────────────────────────────────┐
│                      协作支持网络视图                            │
│                                                                 │
│         ┌──────┐                                                │
│         │ 张三 │ ←──────────────────┐                          │
│         └──┬───┘                    │                          │
│            │                        │                          │
│    支持(环境)                       │                          │
│            │                        │                          │
│            ▼                        │                          │
│         ┌──────┐     支持(文档)     │                          │
│    ┌────│ 李四 │←───────────────┐  │                          │
│    │    └──────┘                │  │                          │
│    │         │                  │  │                          │
│    │   提供(监控方案)           │  │                          │
│    │         │                  │  │                          │
│    │         ▼                  │  │                          │
│    │    ┌──────┐                │  │                          │
│    └───→│ 王五 │                │  │                          │
│         └──────┘                │  │                          │
│            │                    │  │                          │
│      需要(服务器)               │  │                          │
│            │                    │  │                          │
│            ▼                    │  │                          │
│         ┌──────┐                │  │                          │
│         │ 赵六 │────────────────┘  │ 需要(服务器)             │
│         └──────┘                   ─┘                         │
│                                                                 │
│  统计：                                                         │
│  • 张三：需要 2 人支持，提供 1 人支持                           │
│  • 李四：需要 1 人支持，提供 0 人支持                           │
│  • 王五：需要 0 人支持，提供 2 人支持                           │
│  • 赵六：需要 0 人支持，提供 1 人支持（待确认）                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 25. 多平台适配器架构（新增）

### 25.1 概述

RippleFlow 支持多种聊天平台的消息接入，采用**平台适配器**模式实现统一的消息处理。

**支持平台**：
- 微信（个人微信 Web/Protocol，如 Wechaty）
- 飞书
- 钉书
- 自定义平台（可扩展）

### 25.2 架构设计

```
┌─────────────────────────────────────────────────────────────────┐
│                      消息接入层                                  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   消息适配器抽象                          │   │
│  │               MessageAdapter Protocol                    │   │
│  │   - normalize_message() → 统一消息格式                   │   │
│  │   - parse_user() → 统一用户标识                          │   │
│  │   - parse_room() → 统一群组标识                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              ↑                                  │
│        ┌─────────────────────┼─────────────────────┐           │
│        │                     │                     │           │
│  ┌─────┴─────┐         ┌─────┴─────┐         ┌─────┴─────┐    │
│  │ 微信适配器 │         │ 飞书适配器 │         │ 钉书适配器 │    │
│  │ Wechaty   │         │ Feishu   │         │ DingTalk  │    │
│  │ Adapter   │         │ Adapter  │         │ Adapter   │    │
│  └───────────┘         └───────────┘         └───────────┘    │
│        │                     │                     │           │
│  ┌─────┴─────┐         ┌─────┴─────┐         ┌─────┴─────┐    │
│  │ 批量导入  │         │ 批量导入  │         │ 批量导入  │    │
│  │ Importer  │         │ Importer  │         │ Importer  │    │
│  └───────────┘         └───────────┘         └───────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   自定义平台适配器                        │   │
│  │                  CustomAdapter                           │   │
│  │  支持任意平台，通过配置定义消息格式                       │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 25.3 统一消息格式

```python
# 平台无关的统一消息格式
class UnifiedMessage:
    # 平台标识
    platform: str              # wechat | feishu | dingtalk | custom
    platform_message_id: str   # 平台原始消息ID
    platform_room_id: str      # 平台原始群ID

    # 统一字段
    sender_id: str             # 发送者ID（平台用户ID）
    sender_name: str           # 发送者昵称
    room_id: str               # 群组ID（系统内统一）
    room_name: str             # 群组名称

    # 消息内容
    content: str               # 消息内容（文本）
    content_type: str          # text | image | file | link | video | audio

    # 时间信息
    sent_at: datetime          # 发送时间（UTC）
    received_at: datetime      # 接收时间（UTC）

    # 关联信息
    reply_to: Optional[str]    # 回复的消息ID
    mentions: List[str]        # @的人列表

    # 平台特有数据
    extra: dict                # 平台特有元数据
```

### 25.4 平台适配器接口

```python
# 平台适配器 Protocol
class MessageAdapter(Protocol):
    """消息适配器接口"""

    def normalize_message(self, raw_message: dict) -> UnifiedMessage:
        """将平台原始消息转换为统一格式"""
        ...

    def parse_user(self, platform_user_id: str) -> UserIdentity:
        """解析用户身份"""
        ...

    def parse_room(self, platform_room_id: str) -> RoomIdentity:
        """解析群组身份"""
        ...

    def validate_signature(self, request: Request) -> bool:
        """验证平台签名（安全校验）"""
        ...


class BatchImporter(Protocol):
    """批量导入器接口"""

    def parse_file(self, file_path: str, format: str) -> List[UnifiedMessage]:
        """解析导入文件"""
        ...

    def get_supported_formats(self) -> List[str]:
        """获取支持的文件格式"""
        ...
```

### 25.5 微信适配器

```python
# 微信适配器（基于 Wechaty）
class WechatAdapter(MessageAdapter):
    """微信消息适配器"""

    platform = "wechat"

    def normalize_message(self, raw_message: dict) -> UnifiedMessage:
        """
        Wechaty 消息格式：
        {
            "id": "msg_xxx",
            "type": "text",
            "text": "消息内容",
            "from": "contact_id",
            "room": "room_id",
            "timestamp": 1709289000,
            "mentionIds": ["contact_id_1", "contact_id_2"]
        }
        """
        return UnifiedMessage(
            platform="wechat",
            platform_message_id=raw_message["id"],
            platform_room_id=raw_message.get("room", ""),
            sender_id=raw_message["from"],
            sender_name=self._get_contact_name(raw_message["from"]),
            room_id=self._normalize_room_id(raw_message.get("room", "")),
            room_name=self._get_room_name(raw_message.get("room", "")),
            content=raw_message.get("text", ""),
            content_type=self._map_content_type(raw_message["type"]),
            sent_at=datetime.fromtimestamp(raw_message["timestamp"], tz=timezone.utc),
            received_at=datetime.now(tz=timezone.utc),
            reply_to=None,
            mentions=raw_message.get("mentionIds", []),
            extra=raw_message
        )

    def _map_content_type(self, wechat_type: str) -> str:
        type_map = {
            "text": "text",
            "image": "image",
            "video": "video",
            "audio": "audio",
            "file": "file",
            "link": "link"
        }
        return type_map.get(wechat_type, "unknown")


class WechatBatchImporter(BatchImporter):
    """微信批量导入器"""

    def get_supported_formats(self) -> List[str]:
        return ["wechat_txt", "json", "csv"]

    def parse_file(self, file_path: str, format: str) -> List[UnifiedMessage]:
        if format == "wechat_txt":
            return self._parse_wechat_txt(file_path)
        elif format == "json":
            return self._parse_json(file_path)
        elif format == "csv":
            return self._parse_csv(file_path)

    def _parse_wechat_txt(self, file_path: str) -> List[UnifiedMessage]:
        """
        解析微信导出的文本格式：

        张三 2026/3/1 10:30:00
        这是一条消息内容

        李四 2026/3/1 10:31:05
        回复张三：这是回复内容

        [图片]
        [文件] 文件名.pdf
        """
        messages = []
        current_sender = None
        current_time = None
        current_content = []

        with open(file_path, 'r', encoding='utf-8') as f:
            for line in f:
                # 尝试匹配消息头：发送者 时间
                header_match = re.match(r'^(.+?)\s+(\d{4}/\d{1,2}/\d{1,2}\s+\d{1,2}:\d{2}:\d{2})$', line.strip())

                if header_match:
                    # 保存上一条消息
                    if current_sender and current_content:
                        messages.append(self._create_message(
                            current_sender, current_time, '\n'.join(current_content)
                        ))

                    # 开始新消息
                    current_sender = header_match.group(1).strip()
                    current_time = datetime.strptime(header_match.group(2), '%Y/%m/%d %H:%M:%S')
                    current_content = []
                else:
                    # 消息内容
                    if line.strip():
                        current_content.append(line.strip())

        # 保存最后一条消息
        if current_sender and current_content:
            messages.append(self._create_message(
                current_sender, current_time, '\n'.join(current_content)
            ))

        return messages
```

### 25.6 飞书适配器

```python
# 飞书适配器
class FeishuAdapter(MessageAdapter):
    """飞书消息适配器"""

    platform = "feishu"

    def normalize_message(self, raw_message: dict) -> UnifiedMessage:
        """
        飞书消息格式：
        {
            "msg_type": "text",
            "content": "{\"text\": \"消息内容\"}",
            "create_time": "2026-03-01T10:30:00Z",
            "sender": {
                "sender_id": {"open_id": "ou_xxx"},
                "sender_type": "user"
            },
            "message_id": "om_xxx",
            "chat_id": "oc_xxx"
        }
        """
        content_data = json.loads(raw_message.get("content", "{}"))

        return UnifiedMessage(
            platform="feishu",
            platform_message_id=raw_message["message_id"],
            platform_room_id=raw_message["chat_id"],
            sender_id=raw_message["sender"]["sender_id"]["open_id"],
            sender_name=self._get_user_name(raw_message["sender"]["sender_id"]["open_id"]),
            room_id=self._normalize_room_id(raw_message["chat_id"]),
            room_name=self._get_chat_name(raw_message["chat_id"]),
            content=content_data.get("text", ""),
            content_type=self._map_content_type(raw_message["msg_type"]),
            sent_at=datetime.fromisoformat(raw_message["create_time"].replace("Z", "+00:00")),
            received_at=datetime.now(tz=timezone.utc),
            reply_to=None,
            mentions=self._extract_mentions(content_data),
            extra=raw_message
        )


class FeishuBatchImporter(BatchImporter):
    """飞书批量导入器"""

    def get_supported_formats(self) -> List[str]:
        return ["feishu_json", "json", "csv"]

    def parse_file(self, file_path: str, format: str) -> List[UnifiedMessage]:
        if format == "feishu_json":
            return self._parse_feishu_export(file_path)
        # ...
```

### 25.7 钉书适配器

```python
# 钉书适配器
class DingtalkAdapter(MessageAdapter):
    """钉书消息适配器"""

    platform = "dingtalk"

    def normalize_message(self, raw_message: dict) -> UnifiedMessage:
        """
        钉书消息格式：
        {
            "msgId": "xxx",
            "content": "消息内容",
            "gmtCreate": 1709289000000,
            "senderNick": "张三",
            "senderStaffId": "user123",
            "conversationId": "cidxxx",
            "conversationType": 2,
            "msgType": "text"
        }
        """
        return UnifiedMessage(
            platform="dingtalk",
            platform_message_id=raw_message["msgId"],
            platform_room_id=raw_message["conversationId"],
            sender_id=raw_message["senderStaffId"],
            sender_name=raw_message["senderNick"],
            room_id=self._normalize_room_id(raw_message["conversationId"]),
            room_name=self._get_conversation_name(raw_message["conversationId"]),
            content=raw_message["content"],
            content_type=self._map_content_type(raw_message["msgType"]),
            sent_at=datetime.fromtimestamp(raw_message["gmtCreate"] / 1000, tz=timezone.utc),
            received_at=datetime.now(tz=timezone.utc),
            reply_to=None,
            mentions=self._extract_mentions(raw_message),
            extra=raw_message
        )
```

### 25.8 平台适配器注册表

```python
# 平台适配器注册表
class PlatformAdapterRegistry:
    """平台适配器注册表"""

    _adapters: Dict[str, MessageAdapter] = {}
    _importers: Dict[str, BatchImporter] = {}

    @classmethod
    def register(cls, platform: str, adapter: MessageAdapter, importer: BatchImporter = None):
        """注册平台适配器"""
        cls._adapters[platform] = adapter
        if importer:
            cls._importers[platform] = importer

    @classmethod
    def get_adapter(cls, platform: str) -> MessageAdapter:
        """获取平台适配器"""
        if platform not in cls._adapters:
            raise ValueError(f"Unsupported platform: {platform}")
        return cls._adapters[platform]

    @classmethod
    def get_importer(cls, platform: str) -> Optional[BatchImporter]:
        """获取批量导入器"""
        return cls._importers.get(platform)

    @classmethod
    def list_platforms(cls) -> List[str]:
        """列出所有支持的平台"""
        return list(cls._adapters.keys())


# 初始化注册
def init_platform_adapters():
    # 微信
    PlatformAdapterRegistry.register(
        "wechat",
        WechatAdapter(),
        WechatBatchImporter()
    )

    # 飞书
    PlatformAdapterRegistry.register(
        "feishu",
        FeishuAdapter(),
        FeishuBatchImporter()
    )

    # 钉书
    PlatformAdapterRegistry.register(
        "dingtalk",
        DingtalkAdapter(),
        DingtalkBatchImporter()
    )

    # 自定义平台
    PlatformAdapterRegistry.register(
        "custom",
        CustomAdapter(),
        CustomBatchImporter()
    )
```

---

## 26. 批量导入与时序重放（新增）

### 26.1 概述

批量导入功能允许用户导入聊天软件导出的历史消息，系统通过**时序重放**模式模拟消息流，逐条进入处理流水线。

**应用场景**：
- 聊天软件不支持实时消息同步
- 迁移历史数据到新系统
- 补充缺失的时间段数据

### 26.2 导入流程架构

```
┌─────────────────────────────────────────────────────────────────┐
│                      批量导入流程                                │
│                                                                 │
│  1. 上传文件                                                    │
│     POST /import/{platform}/batch                              │
│     Body: {room_id, file, time_range, options}                 │
│                                                                 │
│  2. 创建导入任务                                                │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  import_jobs 表                                     │    │
│     │  - id, platform, room_id                            │    │
│     │  - total_count, processed_count, failed_count       │    │
│     │  - status: pending | processing | completed | failed │    │
│     │  - options: {time_scale, skip_noise, ...}           │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  3. 解析文件                                                    │
│     ┌─────────────────────────────────────────────────────┐    │
│     │  平台解析器（BatchImporter）                         │    │
│     │  ↓                                                   │    │
│     │  解析 → 验证 → 标准化 → 排序                         │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  4. 时序重放处理                                                │
│     ┌─────────────────────────────────────────────────────┐    │
│     │                                                     │    │
│     │  按原始时间排序消息                                  │    │
│     │  ↓                                                   │    │
│     │  模拟时间间隔（可选加速）                            │    │
│     │  ↓                                                   │    │
│     │  逐条进入消息处理流水线（Stage 0-4）                 │    │
│     │  ↓                                                   │    │
│     │  更新导入进度                                        │    │
│     │                                                     │    │
│     └─────────────────────────────────────────────────────┘    │
│                                                                 │
│  5. 完成通知                                                    │
│     生成导入报告 → 通知管理员                                   │
└─────────────────────────────────────────────────────────────────┘
```

### 26.3 导入任务表

```sql
-- 导入任务表
CREATE TABLE import_jobs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    platform        VARCHAR(50) NOT NULL,   -- wechat | feishu | dingtalk | custom
    room_id         VARCHAR(255) NOT NULL,  -- 目标群组ID

    -- 文件信息
    file_name       VARCHAR(500),
    file_path       VARCHAR(1000),
    file_size       BIGINT,
    file_format     VARCHAR(50),            -- wechat_txt | json | csv | ...

    -- 进度信息
    total_count     INTEGER DEFAULT 0,
    processed_count INTEGER DEFAULT 0,
    failed_count    INTEGER DEFAULT 0,
    skipped_count   INTEGER DEFAULT 0,

    -- 状态
    status          VARCHAR(50) DEFAULT 'pending',  -- pending | parsing | processing | completed | failed | cancelled

    -- 时间范围
    time_range_start TIMESTAMPTZ,
    time_range_end   TIMESTAMPTZ,

    -- 导入选项
    options         JSONB DEFAULT '{}',
    -- {
    --   "time_scale": 1.0,        -- 时间加速因子（1.0=实时，10.0=10倍速）
    --   "skip_noise": true,       -- 跳过噪声消息
    --   "batch_size": 100,        -- 批处理大小
    --   "reprocess": false        -- 是否重新处理已存在的消息
    -- }

    -- 结果统计
    result_summary  JSONB DEFAULT '{}',
    -- {
    --   "threads_created": 15,
    --   "threads_updated": 8,
    --   "action_items_created": 5,
    --   "decisions_created": 3,
    --   "errors": [...]
    -- }

    -- 时间信息
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    created_by      VARCHAR(255) NOT NULL
);

CREATE INDEX idx_import_status ON import_jobs(status, created_at DESC);
CREATE INDEX idx_import_room ON import_jobs(room_id);
CREATE INDEX idx_import_platform ON import_jobs(platform);

-- 导入消息记录表（追踪每条消息的导入状态）
CREATE TABLE import_message_logs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id          UUID NOT NULL REFERENCES import_jobs(id) ON DELETE CASCADE,

    -- 消息信息
    platform_message_id VARCHAR(500),
    sender_id       VARCHAR(255),
    sender_name     VARCHAR(255),
    content_preview TEXT,
    sent_at         TIMESTAMPTZ,

    -- 处理结果
    status          VARCHAR(50) NOT NULL,  -- pending | processed | skipped | failed
    message_id      UUID REFERENCES messages(id),
    thread_id       UUID REFERENCES topic_threads(id),
    error_message   TEXT,

    processed_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_import_msg_job ON import_message_logs(job_id, status);
CREATE INDEX idx_import_msg_status ON import_message_logs(status);
```

### 26.4 时序重放引擎

```python
# 时序重放引擎
class TimedReplayEngine:
    """时序重放引擎"""

    def __init__(self, job_id: str, options: dict):
        self.job_id = job_id
        self.time_scale = options.get("time_scale", 1.0)  # 默认实时
        self.batch_size = options.get("batch_size", 100)
        self.skip_noise = options.get("skip_noise", True)

    async def replay(self, messages: List[UnifiedMessage]):
        """执行时序重放"""

        # 按时间排序
        sorted_messages = sorted(messages, key=lambda m: m.sent_at)

        # 分批处理
        for batch in self._batch_messages(sorted_messages):
            for msg in batch:
                # 模拟时间间隔（可选加速）
                await self._apply_time_delay(msg, batch[0])

                # 处理消息
                await self._process_message(msg)

                # 更新进度
                await self._update_progress()

        # 生成报告
        await self._generate_report()

    async def _apply_time_delay(self, msg: UnifiedMessage, prev_msg: UnifiedMessage):
        """应用时间延迟"""
        if prev_msg and self.time_scale > 0:
            time_diff = (msg.sent_at - prev_msg.sent_at).total_seconds()
            # 应用时间加速
            actual_delay = time_diff / self.time_scale
            if actual_delay > 0:
                await asyncio.sleep(min(actual_delay, 1.0))  # 最大延迟1秒

    async def _process_message(self, msg: UnifiedMessage):
        """处理单条消息"""
        try:
            # 进入消息处理流水线
            result = await message_pipeline.process(msg)

            # 记录结果
            await self._log_message_result(msg, result)

        except Exception as e:
            await self._log_message_error(msg, str(e))

    def _batch_messages(self, messages: List[UnifiedMessage]) -> Iterator[List[UnifiedMessage]]:
        """分批处理消息"""
        for i in range(0, len(messages), self.batch_size):
            yield messages[i:i + self.batch_size]
```

### 26.5 导入 API

```yaml
# 批量导入接口
POST /api/v1/import/{platform}/batch:
  summary: 批量导入消息
  parameters:
    - name: platform
      in: path
      required: true
      enum: [wechat, feishu, dingtalk, custom]
  requestBody:
    content:
      multipart/form-data:
        schema:
          properties:
            file:
              type: string
              format: binary
              description: 导入文件
            room_id:
              type: string
              description: 目标群组ID
            options:
              type: object
              properties:
                time_scale:
                  type: number
                  default: 0
                  description: 时间加速因子（0=不延迟，最大速度）
                skip_noise:
                  type: boolean
                  default: true
                reprocess:
                  type: boolean
                  default: false
  responses:
    200:
      content:
        application/json:
          schema:
            properties:
              job_id:
                type: string
              status:
                type: string
              estimated_time:
                type: string

GET /api/v1/import/{platform}/status/{job_id}:
  summary: 查询导入任务状态
  responses:
    200:
      content:
        application/json:
          schema:
            properties:
              job_id:
                type: string
              status:
                type: string
              progress:
                type: object
                properties:
                  total:
                    type: integer
                  processed:
                    type: integer
                  failed:
                    type: integer
                  percentage:
                    type: number
              result_summary:
                type: object

GET /api/v1/import/{platform}/formats:
  summary: 获取支持的导入格式
  responses:
    200:
      content:
        application/json:
          schema:
            properties:
              formats:
                type: array
                items:
                  type: object
                  properties:
                    id:
                      type: string
                    name:
                      type: string
                    description:
                      type: string
                    example:
                      type: string

DELETE /api/v1/import/{platform}/jobs/{job_id}:
  summary: 取消导入任务
  responses:
    200:
      content:
        application/json:
          schema:
            properties:
              status:
                type: string
              message:
                type: string

GET /api/v1/import/jobs:
  summary: 列出导入任务
  parameters:
    - name: status
      in: query
      enum: [pending, processing, completed, failed, all]
    - name: platform
      in: query
    - name: limit
      in: query
      default: 20
  responses:
    200:
      content:
        application/json:
          schema:
            properties:
              jobs:
                type: array
                items:
                  $ref: '#/components/schemas/ImportJob'
```

### 26.6 Webhook 扩展接口

```yaml
# 多平台 Webhook 接口
POST /webhook/{platform}/message:
  summary: 接收平台消息
  parameters:
    - name: platform
      in: path
      required: true
      enum: [wechat, feishu, dingtalk, custom]
  requestBody:
    content:
      application/json:
        schema:
          description: 平台原始消息格式
  responses:
    200:
      content:
        application/json:
          schema:
            properties:
              status:
                type: string
              message_id:
                type: string

POST /webhook/{platform}/event:
  summary: 接收平台事件
  parameters:
    - name: platform
      in: path
      required: true
  requestBody:
    content:
      application/json:
        schema:
          description: 平台事件格式
  responses:
    200:
      content:
        application/json:
          schema:
            properties:
              status:
                type: string
```

### 26.7 平台数据表扩展

```sql
-- 平台群组映射表
CREATE TABLE platform_rooms (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    platform        VARCHAR(50) NOT NULL,
    platform_room_id VARCHAR(255) NOT NULL,
    room_id         UUID REFERENCES chat_rooms(id),

    room_name       VARCHAR(500),
    room_type       VARCHAR(50),            -- group | private

    -- 同步状态
    sync_enabled    BOOLEAN DEFAULT true,
    last_sync_at    TIMESTAMPTZ,
    last_message_id VARCHAR(500),

    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(platform, platform_room_id)
);

CREATE INDEX idx_platform_rooms ON platform_rooms(platform, platform_room_id);

-- 平台用户映射表
CREATE TABLE platform_users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    platform        VARCHAR(50) NOT NULL,
    platform_user_id VARCHAR(255) NOT NULL,
    user_id         UUID REFERENCES chat_users(id),

    display_name    VARCHAR(500),
    avatar_url      VARCHAR(1000),

    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(platform, platform_user_id)
);

CREATE INDEX idx_platform_users ON platform_users(platform, platform_user_id);
```

---

## 27. 微信群对接架构（新增）

### 27.1 概述

微信个人号没有官方开放 API，本系统采用**混合架构**实现微信群消息接入：

| 方案 | 说明 | 实时性 | 风险 |
|------|------|--------|------|
| **Wechaty 实时同步** | 小号 + 只读模式 | 实时 | ⚠️ 中等 |
| **批量导入增量更新** | 手动上传 + 时间戳过滤 | 非实时 | ✅ 无 |

**混合架构**：实时通道优先，批量导入兜底。

### 27.2 架构设计

```
┌─────────────────────────────────────────────────────────────────┐
│                    微信消息接入架构                              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                实时通道 (Wechaty)                        │   │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │   │
│  │  │ 小号登录    │───→│ 只收消息    │───→│ 推送到队列  │  │   │
│  │  │ iPad协议    │    │ 不主动发送  │    │ 处理流水线  │  │   │
│  │  └─────────────┘    └─────────────┘    └─────────────┘  │   │
│  │         ⚠️ 有风险但只读模式风险较低                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼ 断开时自动切换                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                批量导入通道（增量更新）                   │   │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │   │
│  │  │ 上传文件    │───→│ 时间戳过滤  │───→│ 去重入库    │  │   │
│  │  │ 多格式解析  │    │ 只导入新增  │    │ 补齐缺失    │  │   │
│  │  └─────────────┘    └─────────────┘    └─────────────┘  │   │
│  │         ✅ 稳定可靠，作为兜底方案                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   同步状态追踪                           │   │
│  │  - 记录每个群的最后同步时间                               │   │
│  │  - 追踪实时通道在线状态                                   │   │
│  │  - 支持断点续传                                           │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 27.3 Wechaty 实时同步服务

```python
# wechat_sync_service.py
from wechaty import Wechaty, Message
from typing import Optional

class WechatSyncService:
    """微信实时同步服务（只读模式）"""

    def __init__(self):
        self.bot: Optional[Wechaty] = None
        self.sync_mode = "readonly"  # 只读模式，不主动发送
        self.monitored_rooms: set[str] = set()

    async def start(self, room_ids: list[str]):
        """启动同步（使用小号）"""
        self.bot = WechatyBuilder.build(
            puppet="wechaty-puppet-service",
            token=settings.WECHATY_TOKEN
        )

        self.monitored_rooms = set(room_ids)

        # 注册消息监听
        self.bot.on("message", self._on_message)
        self.bot.on("login", self._on_login)
        self.bot.on("logout", self._on_logout)

        await self.bot.start()

    async def _on_message(self, message: Message):
        """消息回调（只收不发）"""
        try:
            # 只处理群消息
            room = message.room()
            if not room:
                return

            room_id = room.room_id

            # 只处理监控的群
            if room_id not in self.monitored_rooms:
                return

            # 转换为统一格式
            unified = await self._normalize_message(message)

            # 推送到处理队列
            await message_queue.push(unified)

            # 更新同步状态
            await self._update_sync_status(unified)

        except Exception as e:
            logger.error(f"Error processing message: {e}")

    async def stop(self):
        """停止同步"""
        if self.bot:
            await self.bot.stop()
            self.bot = None
            await self._update_realtime_status("offline")
```

### 27.4 增量导入服务

```python
# incremental_import_service.py
import hashlib
from datetime import datetime

class IncrementalImportService:
    """增量导入服务"""

    async def import_incremental(
        self,
        room_id: str,
        file_path: str,
        format: str,
        options: dict = None
    ) -> ImportResult:
        """增量导入消息"""

        # 1. 获取最后同步时间
        last_sync = await self._get_last_sync_time(room_id)

        # 2. 解析文件
        parser = self._get_parser(format)
        messages = await parser.parse(file_path)

        # 3. 时间戳过滤：只保留新消息
        new_messages = [
            m for m in messages
            if m.sent_at > last_sync
        ]

        # 4. 去重检查（发送者+时间+内容哈希）
        deduped = await self._deduplicate(room_id, new_messages)

        # 5. 批量处理
        result = await self._batch_process(room_id, deduped)

        # 6. 更新同步状态
        if result.processed > 0:
            last_message = max(messages, key=lambda m: m.sent_at)
            await self._update_sync_status(
                room_id,
                last_message.sent_at,
                last_message.platform_message_id
            )

        return result

    def _make_message_hash(self, msg: UnifiedMessage) -> str:
        """生成消息唯一哈希：发送者+时间戳+内容"""
        content = f"{msg.sender_id}|{int(msg.sent_at.timestamp())}|{msg.content}"
        return hashlib.sha256(content.encode()).hexdigest()
```

### 27.5 微信同步状态表

```sql
-- 微信同步状态表
CREATE TABLE wechat_sync_status (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_id         UUID NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,

    -- 同步模式
    sync_mode       VARCHAR(50) DEFAULT 'batch',
    -- realtime: 仅实时同步
    -- batch: 仅批量导入
    -- hybrid: 混合模式（实时优先，批量兜底）

    -- 实时同步状态
    realtime_status VARCHAR(50),  -- online | offline | error
    realtime_last_heartbeat TIMESTAMPTZ,
    realtime_error  TEXT,

    -- 批量同步状态
    last_sync_time  TIMESTAMPTZ,
    last_message_id VARCHAR(500),
    last_message_hash VARCHAR(64),  -- SHA256 内容哈希

    -- 统计
    total_imported  BIGINT DEFAULT 0,
    total_skipped   BIGINT DEFAULT 0,
    total_failed    BIGINT DEFAULT 0,

    -- 时间
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(room_id)
);

CREATE INDEX idx_wechat_sync_room ON wechat_sync_status(room_id);
CREATE INDEX idx_wechat_sync_mode ON wechat_sync_status(sync_mode);
CREATE INDEX idx_wechat_sync_realtime ON wechat_sync_status(realtime_status);

-- 为消息表添加内容哈希字段（用于去重）
ALTER TABLE messages ADD COLUMN IF NOT EXISTS content_hash VARCHAR(64);
CREATE INDEX IF NOT EXISTS idx_messages_content_hash ON messages(room_id, content_hash);
```

### 27.6 微信同步 API

```yaml
# 微信同步管理 API
/api/v1/wechat:
  endpoints:
    # 启动实时同步
    POST /sync/start:
      summary: 启动 Wechaty 实时同步
      auth: admin
      request:
        room_ids: string[]  # 要监控的群组ID列表
        mode: readonly | full  # 只读模式风险更低

    # 停止实时同步
    POST /sync/stop:
      summary: 停止实时同步
      auth: admin

    # 获取同步状态
    GET /sync/status:
      summary: 获取同步状态
      response:
        realtime_status: online | offline | error
        rooms:
          - room_id: string
            sync_mode: realtime | batch | hybrid
            last_sync_time: datetime
            total_imported: int

    # 增量导入
    POST /import/incremental:
      summary: 增量导入微信消息
      request:
        content-type: multipart/form-data
        file: binary
        room_id: string
        format: wechat_txt | wechat_db | json | csv
      response:
        job_id: string
        total_count: int
        new_count: int
        skipped_count: int

    # 支持的导入格式
    GET /import/formats:
      summary: 获取支持的导入格式
      response:
        formats:
          - id: wechat_txt
            name: 微信文本格式
          - id: wechat_db
            name: 微信数据库
          - id: json
            name: JSON格式
          - id: csv
            name: CSV格式
```

### 27.7 风险控制

| 风险 | 等级 | 缓解措施 |
|------|------|----------|
| 小号封号 | 🟡 中 | 只读模式、低频拉取、使用老号、风险隔离 |
| 实时通道断开 | 🟡 中 | 自动检测、告警通知、批量导入兜底 |
| 消息重复导入 | 🟢 低 | 时间戳+哈希双重去重 |
| 数据丢失 | 🟢 低 | 批量导入兜底、断点续传、状态追踪 |

### 27.8 配置项

```yaml
# config.yaml
wechat:
  wechaty:
    enabled: false
    puppet: "wechaty-puppet-service"
    token: "${WECHATY_TOKEN}"
    mode: "readonly"  # readonly | full
    heartbeat_interval: 300  # 5 分钟

  sync:
    default_mode: "batch"  # realtime | batch | hybrid
    dedup_window: 86400  # 去重窗口：24小时
    max_retry: 3

  import:
    max_file_size: 100MB
    supported_formats:
      - wechat_txt
      - wechat_db
      - json
      - csv
```

---

## 28. 四大类信息分类架构（新增）

### 28.1 概述

根据专家审查报告建议，RippleFlow 采用**四大类信息分类架构**作为系统顶层分类标准：

| 分类 | 含义 | 说明 |
|------|------|------|
| **knowledge** | 知识库 | FAQ、经验总结、术语规则、外部资源 |
| **action** | 任务与待办 | 显性任务、隐性承诺、多步骤事项 |
| **event** | 事件与线索 | 项目里程碑、问题处理全过程、决策过程 |
| **collaboration** | 协作网络 | 沟通关系、任务关系、知识关系 |

### 28.2 分层分类架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         顶层分类 (info_domain)                               │
├───────────────────┬───────────────────┬───────────────────┬─────────────────┤
│ 1. knowledge      │ 2. action         │ 3. event          │ 4. collaboration│
│ 知识库            │ 任务与待办         │ 事件与线索         │ 协作网络         │
├───────────────────┼───────────────────┼───────────────────┼─────────────────┤
│ 二级分类:         │ 二级分类:          │ 二级分类:          │ 关系类型:        │
│ • qa_faq          │ • action_item     │ • tech_decision   │ • 沟通关系       │
│ • knowledge_share │   (增强隐性承诺)   │ • bug_incident    │ • 任务关系       │
│ • reference_data  │                   │ • project_update  │ • 知识关系       │
│ • env_config      │                   │ • discussion_notes│                 │
└───────────────────┴───────────────────┴───────────────────┴─────────────────┘
```

### 28.3 与现有系统融合分析

#### 知识库类 (Knowledge)

| 维度 | 专家建议 | 现有系统 | 关系 |
|------|----------|----------|------|
| 分类 | FAQ、经验总结、术语规则、外部资源 | qa_faq, knowledge_share, reference_data, env_config | ✅ 匹配 |
| 提取模板 | 详细的 Prompt 模板和触发关键词 | 已有 trigger_hints | 🔄 增强 |

#### 任务与待办 (Action Items)

| 维度 | 专家建议 | 现有系统 | 关系 |
|------|----------|----------|------|
| 显性任务 | @{person} {action} {deadline} | 已支持 | ✅ 匹配 |
| 隐性承诺 | "我回头..."、"我会..." 自动识别 | ❌ 不支持 | 🆕 新增 |
| 多步骤拆解 | 拆解项目计划为具体任务步骤 | ❌ 不支持 | 🆕 新增 |
| 完成信号 | 自动检测"已完成"、"搞定了"、"done" | ❌ 不支持 | 🆕 新增 |

#### 事件与线索 (Event Threads)

| 维度 | 专家建议 | 现有系统 | 关系 |
|------|----------|----------|------|
| 分类 | 里程碑、问题处理、客户互动 | tech_decision, bug_incident, project_update | ✅ 匹配 |
| 状态变迁追踪 | 线索状态变迁算法 | ❌ 只有最终状态 | 🆕 新增 |

#### 协作网络 (Collaboration Graph)

| 维度 | 专家建议 | 现有系统 | 关系 |
|------|----------|----------|------|
| 关系类型 | 沟通关系、任务关系、知识关系 | ❌ 不支持 | 🆕 新增 |
| 权重计算 | @提及:3.0, 回复:2.0 | ❌ 不支持 | 🆕 新增 |

### 28.4 隐性承诺识别

```python
class ImplicitCommitmentDetector:
    """隐性承诺检测器"""

    PATTERNS = [
        (r'我(回头|之后|明天|下周|尽快)', 0.8),
        (r'(我|咱们)(需要|得|应该|要)', 0.7),
        (r'(记|写)一下', 0.6),
        (r'.*(前|之前).*(给|发|提交|完成)', 0.9),
        (r'(计划|准备|打算)', 0.7),
    ]

    async def detect(self, message: Message) -> Optional[ImplicitCommitment]:
        """检测消息中的隐性承诺"""
        for pattern, confidence in self.PATTERNS:
            if re.search(pattern, message.content):
                return ImplicitCommitment(
                    message_id=message.id,
                    pattern=pattern,
                    confidence=confidence,
                    status='identified'
                )
        return None
```

### 28.5 完成信号检测

```python
class CompletionSignalDetector:
    """完成信号检测器"""

    SIGNALS = {
        'exact': ['已完成', '搞定了', 'done', '完成了', '解决了'],
        'emoji': ['✅', '🎉', '💪'],
    }

    async def detect_completion(self, message: Message) -> Optional[CompletionSignal]:
        """检测消息中的完成信号"""
        content = message.content.strip()

        if content in self.SIGNALS['exact']:
            return CompletionSignal(signal=content, confidence=1.0, type='exact')

        for emoji in self.SIGNALS['emoji']:
            if emoji in content:
                return CompletionSignal(signal=emoji, confidence=0.9, type='emoji')

        return None
```

### 28.6 协作网络分析

```yaml
relation_types:
  communication:           # 沟通关系
    - frequent_collaborators    # 频繁协作
    - information_bridge        # 信息桥梁
    - knowledge_expert          # 领域专家

  task_based:              # 任务关系
    - task_assigner             # 任务分配者
    - task_executor             # 任务执行者
    - reviewer                  # 评审者

  knowledge_based:         # 知识关系
    - knowledge_contributor     # 知识贡献者
    - question_asker            # 提问者
    - answer_provider           # 解答者

relation_weights:
  @mention: 3.0
  reply: 2.0
  same_thread: 1.5
  same_time: 0.5
```

### 28.7 API 接口

```yaml
/api/v1/info-domains:
  get:
    summary: 获取四大类定义

/api/v1/actions/implicit:
  get:
    summary: 获取待确认的隐性承诺列表
  post:
    summary: 确认/忽略隐性承诺

/api/v1/collaboration/network:
  get:
    summary: 获取协作网络图数据

/api/v1/collaboration/experts:
  get:
    summary: 识别领域专家
```

### 28.8 前端导航分组

```
┌─────────────────────────────────────┐
│ 📚 知识库                           │
│    ├─ 问题解答 (qa_faq)            │
│    ├─ 知识分享 (knowledge_share)   │
│    ├─ 参考信息 (reference_data)    │
│    └─ 环境配置 (env_config)        │
├─────────────────────────────────────┤
│ ✅ 任务与待办                       │
│    ├─ 待确认 (隐性承诺)            │
│    ├─ 进行中                        │
│    └─ 已完成                        │
├─────────────────────────────────────┤
│ 🔀 事件与线索                       │
│    ├─ 技术决策                      │
│    ├─ 故障案例                      │
│    ├─ 项目动态                      │
│    └─ 讨论纪要                      │
├─────────────────────────────────────┤
│ 👥 协作网络                         │
│    ├─ 关系图谱                      │
│    └─ 领域专家                      │
└─────────────────────────────────────┘
```

---

## 29. 文件系统分级索引与存储架构（新增）

### 29.1 设计理念

**核心原则**：文本优先、渐进披露、按需访问

| 原则 | 说明 |
|------|------|
| **文本优先** | 使用 YAML/Markdown 存储，方便模型直接理解 |
| **减少上下文** | 原文优先级最低，优先访问摘要和索引 |
| **渐进披露** | 根据信息时效性自动降级，减少噪音 |
| **按需访问** | 原文仅通过明确指令（查询文件、@命令）访问 |

### 29.2 三级存储架构

```
.knowledge/                           # 知识库根目录
├── index.yaml                        # 全局索引（入口）
│
├── L1-active/                        # 活跃层（0-30天）
│   │                                 # 优先级最高，上下文直接可见
│   ├── threads/                      # 活跃话题详情
│   │   ├── 2026-03-redis-cluster.yaml
│   │   └── 2026-03-auth-system.yaml
│   │
│   └── index.yaml                    # L1 索引（最近话题列表）
│
├── L2-archived/                      # 归档层（30-180天）
│   │                                 # 摘要模式，原文需明确指定
│   │
│   ├── summaries/                    # 话题摘要（替代原文）
│   │   ├── 2026-02-api-design.md     # 摘要文档
│   │   └── 2026-01-db-migration.md
│   │
│   ├── originals/                    # 原始文件（压缩存储）
│   │   └── 2026-02-api-design.yaml.gz
│   │
│   └── index.yaml                    # L2 索引（摘要列表）
│
└── L3-core/                          # 核心层（永久）
│   │                                 # 高度抽象，知识图谱级别
│   │
│   ├── knowledge-graph.yaml          # 知识图谱（实体-关系）
│   ├── decision-log.yaml             # 关键决策时间线
│   ├── tech-stack.yaml               # 技术栈演进
│   ├── glossary.yaml                 # 术语词典
│   │
│   └── index.yaml                    # L3 索引
```

### 29.3 各层定位

| 层级 | 时间窗口 | 内容特征 | 访问方式 | 上下文策略 |
|------|----------|----------|----------|------------|
| **L1 活跃层** | 0-30天 | 详细、完整、实时 | 直接读取 | **默认加载** |
| **L2 归档层** | 30-180天 | 摘要、结构化 | 摘要优先 | 按需加载摘要 |
| **L3 核心层** | 永久 | 抽象、关联、推理 | 索引查询 | 索引始终加载 |

### 29.4 信息降级规则

```yaml
# 配置文件：compact-rules.yaml

compact_rules:
  L1_to_L2:
    trigger:
      condition: "last_message_at > 30 days ago"
      schedule: "0 2 * * *"  # 每天凌晨2点检查
    action:
      - name: "generate_summary"
        description: "生成话题摘要"
      - name: "compress_original"
        description: "压缩原始文件"
      - name: "update_index"
        description: "更新索引"
    preserve:
      - "原始文件压缩保存"
      - "摘要文件替代原文"
      - "索引保留引用"

  L2_to_L3:
    trigger:
      condition: "last_access_at > 180 days ago"
      schedule: "0 3 * * 0"  # 每周日凌晨3点检查
      executor: "nullclaw"   # 由 nullclaw cron 触发，非平台流水线
    action:
      - name: "extract_entities"
        description: "nullclaw 调用 LLM 提取实体/关系，写入知识图谱（POST /api/v1/knowledge/graph/nodes|edges）"
      - name: "update_decision_log"
        description: "更新决策时间线"
    preserve:
      - "摘要文件保留"
      - "原始文件归档"
```

### 29.5 文件格式规范

#### L1 活跃层格式

```yaml
# L1-active/threads/2026-03-redis-cluster.yaml

id: "thread-uuid"
title: "Redis 集群部署方案"
category: "tech_decision"
info_domain: "event"
status: "active"

# 时间信息
created_at: "2026-03-01T10:00:00Z"
last_message_at: "2026-03-03T15:30:00Z"
message_count: 45

# 活摘要（LLM维护）
summary: |
  讨论了 Redis 集群的部署方案，最终决定采用 3主3从架构，
  使用 Sentinel 实现高可用。预计本周完成部署。

# 关键决策
decisions:
  - content: "采用 3主3从架构"
    decided_at: "2026-03-02T14:00:00Z"
    decided_by: ["张三", "李四"]

# 待办事项
action_items:
  - title: "申请服务器资源"
    assignee: "张三"
    status: "in_progress"
    due_date: "2026-03-05"

# 参与者
stakeholders: ["张三", "李四", "王五"]

# 消息列表（完整内容）
messages:
  - id: "msg-001"
    sender: "张三"
    sent_at: "2026-03-01T10:00:00Z"
    content: "我们需要部署 Redis 集群..."
  - id: "msg-002"
    sender: "李四"
    sent_at: "2026-03-01T10:05:00Z"
    content: "建议使用 3主3从架构..."
  # ... 更多消息
```

#### L2 归档层格式（摘要）

```markdown
# L2-archived/summaries/2026-02-api-design.md

# API 设计方案讨论（已归档）

> 归档时间：2026-03-05
> 原始话题：thread-uuid-xxx
> 消息数：78条
> 参与者：张三、李四、王五

## 摘要

本次讨论确定了 API 设计规范，采用 RESTful 风格，统一响应格式。

## 关键决策

1. **API 风格**：RESTful，遵循 OpenAPI 3.0 规范
2. **认证方式**：JWT Token，有效期 24 小时
3. **版本控制**：URL 路径版本（/api/v1/）

## 待办事项

- [x] 完成设计文档
- [x] 代码评审
- [x] 上线测试环境

## 相关链接

- 设计文档：[链接]
- 原始讨论：@file original:2026-02-api-design.yaml

---
*此摘要由系统自动生成，原文已压缩归档。使用 @file 命令查看原文。*
```

#### L3 核心层格式

```yaml
# L3-core/knowledge-graph.yaml

nodes:
  - id: "redis"
    type: "technology"
    name: "Redis"
    attributes:
      category: "database"
      purpose: "缓存、会话存储"
      first_used: "2024-01-15"
      usage_count: 15

  - id: "zhang_san"
    type: "person"
    name: "张三"
    attributes:
      role: "backend_developer"
      expertise: ["redis", "postgresql", "python"]

edges:
  - source: "zhang_san"
    target: "redis"
    type: "expert_in"
    weight: 4.5
    evidence:
      - thread_id: "thread-uuid-1"
        count: 12
```

### 29.6 访问策略

```python
class FileAccessStrategy:
    """文件访问策略"""

    def get_context_files(self, query: str, time_range: str = None) -> List[str]:
        """根据查询获取上下文文件"""
        # 1. L3 核心层：始终加载索引
        files = ["L3-core/index.yaml", "L3-core/knowledge-graph.yaml"]

        # 2. L1 活跃层：根据时间范围加载
        if time_range and time_range == "recent":
            files.append("L1-active/index.yaml")
            active_threads = self._match_active_threads(query)
            files.extend(active_threads)

        # 3. L2 归档层：仅在明确指定时加载摘要
        # 不自动加载，减少上下文

        return files

    def get_file(self, file_ref: str) -> str:
        """获取指定文件内容"""
        if file_ref.startswith("@file original:"):
            filename = file_ref.replace("@file original:", "")
            return self._decompress_original(filename)
        elif file_ref.startswith("@file summary:"):
            filename = file_ref.replace("@file summary:", "")
            return self._read_summary(filename)
        else:
            return self._read_summary_or_original(file_ref)
```

### 29.7 Compact（压缩）机制

```python
class CompactService:
    """信息压缩服务"""

    async def run_daily_compact(self):
        """每日压缩任务"""
        # 1. 查找需要降级的话题
        candidates = await self._find_L1_candidates()  # > 30天

        for thread in candidates:
            # 2. 生成摘要
            summary = await self._generate_summary(thread)

            # 3. 写入 L2 摘要文件
            await self._write_summary(thread, summary)

            # 4. 压缩原始文件
            await self._compress_original(thread)

            # 5. 更新索引
            await self._update_index(thread, "L2")

            # 6. 删除 L1 文件
            await self._remove_L1_file(thread)
```

### 29.8 API 设计

```yaml
/api/v1/files/context:
  get:
    summary: 获取上下文文件列表

/api/v1/files/{file_path}:
  get:
    summary: 获取文件内容
    parameters:
      - name: prefer
        in: header
        enum: [summary, original]
        default: summary

/api/v1/files/compact:
  post:
    summary: 手动触发压缩
```

### 29.9 查询命令

```
@file <path>              # 查看文件
@file original:<name>     # 查看原文（解压）
@file summary:<name>      # 查看摘要
@recent                   # 查看最近活跃话题
@archive                  # 查看归档话题列表
@compact <thread_id>      # 手动压缩话题
```

### 29.10 配置项

```yaml
file_system:
  root: ".knowledge/"

  layers:
    L1_active:
      retention_days: 30
      max_files: 100

    L2_archived:
      retention_days: 180
      max_summary_length: 500
      compress_original: true

    L3_core:
      permanent: true

  compact:
    schedule: "0 2 * * *"
    batch_size: 50
```

---

## 30. 多实例动态伸缩架构（扩展方案）

### 30.1 概述

当系统消息量增长、单实例处理能力不足时，可启用多 nullclaw 实例协作架构。

**设计原则**：
- 默认单实例运行，保持简单
- 基于队列深度自动伸缩
- 群亲和性路由，保证上下文连贯
- 共享存储层，确保数据一致

### 30.2 架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                    动态实例伸缩架构                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  触发条件：队列深度 > 阈值 → 自动扩容                           │
│            队列深度 < 阈值 → 自动缩容                           │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   消息路由层                             │   │
│  │  规则: 群亲和性路由 (同一群 → 同一实例)                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                      │
│  │ nullclaw │  │ nullclaw │  │ nullclaw │  ← 动态伸缩          │
│  │ 实例 A   │  │ 实例 B   │  │ 实例 C   │                      │
│  │ (群1,2)  │  │ (群3,4)  │  │ (群5,6)  │                      │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘                      │
│       │             │             │                             │
│       └─────────────┼─────────────┘                             │
│                     ▼                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                共享存储层                                │   │
│  │  SQLite/PostgreSQL + Redis缓存(多实例时)                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 30.3 核心问题：消息链割裂

**问题描述**：同一话题的消息如果被分发到不同实例，可能导致上下文割裂。

```
场景：微信群讨论"Redis集群部署"

时间线消息流：
┌──────────────────────────────────────────────────────────────────┐
│  09:00 张三: 我们需要部署 Redis 集群                              │
│  09:05 李四: 建议用 3主3从                                        │
│  09:10 王五: 我来准备部署脚本                                      │
└──────────────────────────────────────────────────────────────────┘

问题：如果这些消息被分发到不同实例：

实例A 处理 09:00 → 创建话题 "Redis集群部署"
实例B 处理 09:05 → 可能创建新话题 "Redis架构建议" ❌ 割裂！
实例C 处理 09:10 → 可能创建新话题 "部署脚本准备" ❌ 割裂！
```

### 30.4 解决方案：群亲和性路由

**核心思想**：同一群的消息始终路由到同一实例

```python
# 路由算法
def route_message(message, instances):
    """
    消息路由：群亲和性

    Args:
        message: 消息对象，包含 room_id
        instances: 可用实例列表

    Returns:
        目标实例
    """
    # 规则1: 群亲和性（同一群 → 同一实例）
    room_id = message.room_id
    instance_index = hash(room_id) % len(instances)
    return instances[instance_index]
```

**优势**：
- 同一群的消息天然相关，路由到同一实例
- 避免话题割裂问题
- 实现简单

**注意**：
- 热门群可能导致单实例过载（可通过子分区解决）
- 实例增减时需要重新分配（一致性哈希）

### 30.5 共享上下文层

所有实例共享同一存储层，确保话题信息不割裂：

```yaml
shared_context:
  database:
    type: "postgresql"  # 或 sqlite（单文件共享）
    connection_pool: 20

  cache:
    type: "redis"
    # 话题状态缓存
    # 活摘要缓存
    # 消息链索引

  message_queue:
    type: "celery+redis"
    # 处理队列
```

### 30.6 动态伸缩策略

```yaml
autoscaling:
  enabled: true

  metrics:
    queue_depth_threshold: 100  # 队列深度阈值
    cpu_threshold: 80           # CPU 使用率阈值

  rules:
    scale_up:
      trigger: "queue_depth > 100 for 2min"
      action: "add 1 instance"
      max_instances: 5

    scale_down:
      trigger: "queue_depth < 20 for 10min"
      action: "remove 1 instance"
      min_instances: 1

  cooldown:
    scale_up: 60s    # 扩容冷却时间
    scale_down: 300s # 缩容冷却时间
```

### 30.7 实例协调

```
┌─────────────────────────────────────────────────────────────────┐
│                   实例协调机制                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐                                               │
│  │ 协调器      │ ← 单点，负责实例生命周期管理                   │
│  │ Coordinator │                                               │
│  └──────┬──────┘                                               │
│         │                                                       │
│         ├──→ 实例注册/注销                                      │
│         ├──→ 负载监控                                           │
│         ├──→ 路由表更新                                         │
│         └──→ 健康检查                                           │
│                                                                 │
│  实例池：                                                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                      │
│  │ Worker A │  │ Worker B │  │ Worker C │                      │
│  │ 群1,2,3  │  │ 群4,5,6  │  │ 群7,8,9  │                      │
│  └──────────┘  └──────────┘  └──────────┘                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 30.8 实现时机

| 阶段 | 实例数 | 说明 |
|------|--------|------|
| **初期** | 1 | 默认单实例，保持简单 |
| **成长期** | 1-3 | 消息量增长，按需扩容 |
| **成熟期** | 3-10 | 高并发场景，多实例并行 |

**触发条件**：
- 队列深度持续超过阈值
- 消息处理延迟超过 SLA
- CPU/内存使用率持续过高

### 30.9 迁移路径

```
单实例 (当前)
    │
    ├── 阶段1: 添加路由层（预留接口）
    │
    ├── 阶段2: 引入共享缓存层
    │
    ├── 阶段3: 实现动态伸缩
    │
    └── 多实例 (未来)
```

---

## 31. CLI 命令规范（能力暴露层）

### 31.1 设计理念

**核心理念**：将系统所有能力通过 CLI 命令暴露，nullclaw 可以通过 `rf help` 查询命令，然后自动编排调用。

```
┌─────────────────────────────────────────────────────────────────┐
│                    能力暴露架构                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   RippleFlow 平台                        │   │
│  │                                                         │   │
│  │  暴露方式：                                              │   │
│  │  ├── REST API（HTTP 接口）                              │   │
│  │  └── CLI 命令（Shell 接口）← nullclaw 调用              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              ↑                                  │
│                              │ rf help / rf <command>           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   nullclaw                               │   │
│  │                                                         │   │
│  │  工作流程：                                              │   │
│  │  1. rf help → 查询可用命令                              │   │
│  │  2. rf <command> --help → 查询命令详情                  │   │
│  │  3. rf <command> [args] → 执行操作                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 31.2 命令结构

```
rf <resource> <action> [options]

资源(resource)：threads, search, todos, sensitive, notifications, ...
动作(action)：list, get, create, update, delete, ...
选项(options)：--filter, --output, --format, ...
```

### 31.3 全局选项

```
--help, -h          显示帮助信息
--output, -o        输出格式：json | table | yaml（默认 table）
--quiet, -q         静默模式，只输出结果
--verbose, -v       详细输出，包含调试信息
--config, -c        指定配置文件路径
--profile, -p       指定环境配置（dev | prod）
```

### 31.4 命令索引

| 命令组 | 说明 | 示例 |
|--------|------|------|
| `rf auth` | 认证与会话 | `rf auth login`, `rf auth whoami` |
| `rf threads` | 话题线索 | `rf threads list`, `rf threads search` |
| `rf search` | 搜索与问答 | `rf search "Redis配置"` |
| `rf qa` | 智能问答 | `rf qa "如何配置连接池"` |
| `rf todos` | 个人待办 | `rf todos list`, `rf todos add` |
| `rf actions` | 任务待办（群聊） | `rf actions list`, `rf actions confirm` |
| `rf sensitive` | 敏感授权 | `rf sensitive pending`, `rf sensitive decide` |
| `rf reference` | 参考信息 | `rf reference list`, `rf reference get` |
| `rf notifications` | 通知管理 | `rf notifications list`, `rf notifications read` |
| `rf subscriptions` | 订阅管理 | `rf subscriptions add`, `rf subscriptions list` |
| `rf contribution` | 贡献统计 | `rf contribution me`, `rf contribution leaderboard` |
| `rf collaboration` | 协作网络 | `rf collaboration network`, `rf collaboration experts` |
| `rf files` | 文件系统 | `rf files list`, `rf files get` |
| `rf import` | 消息导入 | `rf import wechat`, `rf import status` |
| `rf admin` | 管理操作 | `rf admin whitelist`, `rf admin categories` |
| `rf butler` | AI 管家 | `rf butler digest`, `rf butler health` |

### 31.5 详细命令定义

#### 31.5.1 认证命令 (rf auth)

```
rf auth login [--sso]
  登录系统
  --sso    使用 SSO 登录（默认）

rf auth logout
  登出系统

rf auth whoami
  显示当前用户信息

rf auth status
  显示登录状态
```

#### 31.5.2 话题命令 (rf threads)

```
rf threads list [options]
  列出话题线索
  --category <cat>    按类别过滤（tech_decision, qa_faq, ...）
  --domain <domain>   按四大类过滤（knowledge, action, event, collaboration）
  --status <status>   按状态过滤（active, resolved, archived）
  --room <room_id>    按群组过滤
  --from <date>       起始日期
  --to <date>         结束日期
  --page <n>          页码（默认 1）
  --size <n>          每页数量（默认 20）

rf threads get <thread_id>
  获取话题详情

rf threads search <query> [options]
  搜索话题
  --category <cat>    限定类别
  --domain <domain>   限定四大类
  --ignore-window     忽略时间窗口

rf threads summary <thread_id> [options]
  查看/修改话题摘要
  --modify            修改摘要模式
  --content <text>    新摘要内容（修改时必填）
  --reason <text>     修改原因

rf threads history <thread_id>
  查看摘要历史版本

rf threads modifications <thread_id>
  查看修改记录
```

#### 31.5.3 搜索问答命令 (rf search, rf qa)

```
rf search <query> [options]
  全文搜索
  --category <cat>    限定类别
  --domain <domain>   限定四大类
  --from <date>       起始日期
  --to <date>         结束日期
  --size <n>          结果数量（默认 10）

rf qa <question> [options]
  智能问答
  --category <cat>    限定类别
  --ignore-window     忽略时间窗口

rf qa feedback <thread_id> [options]
  提交问答反馈
  --helpful <yes|no>  是否有帮助
  --rating <1-5>      评分
  --comment <text>    备注
```

#### 31.5.4 待办命令 (rf todos, rf actions)

```
rf todos list [options]
  列出个人待办
  --status <status>   按状态过滤（open, done）
  --due-before <date> 截止日期之前
  --overdue           仅显示过期
  --include-collab    包含作为协作者的待办

rf todos add <title> [options]
  创建个人待办
  --description <text> 描述
  --due <date>         截止日期
  --priority <level>   优先级（high, medium, low）
  --tags <tags>        标签（逗号分隔）
  --collaborators <ids> 协作者（逗号分隔）

rf todos get <todo_id>
  获取待办详情

rf todos update <todo_id> [options]
  更新待办
  --title <text>       标题
  --description <text> 描述
  --due <date>         截止日期
  --priority <level>   优先级
  --tags <tags>        标签

rf todos complete <todo_id> [options]
  标记完成
  --note <text>        完成备注

rf todos reopen <todo_id>
  重新打开

rf todos delete <todo_id>
  删除待办

rf todos stats
  待办统计

--- 群聊任务待办 ---

rf actions list [options]
  列出群聊任务
  --assignee <user>   按负责人过滤
  --status <status>   按状态过滤

rf actions confirm <id> [options]
  确认隐性承诺
  --assignee <user>   指派给谁
  --due <date>        截止时间
  --note <text>       备注

rf actions dismiss <id> [options]
  忽略隐性承诺
  --reason <text>     忽略原因
```

#### 31.5.5 敏感授权命令 (rf sensitive)

```
rf sensitive pending [options]
  列出待授权内容
  --room <room_id>    按群组过滤

rf sensitive get <auth_id>
  获取授权详情

rf sensitive decide <auth_id> [options]
  提交决策
  --decision <decision> 决策（approve | reject | desensitize）
  --note <text>         备注
  --desensitized <text> 脱敏内容（desensitize 时必填）

rf sensitive nudge <auth_id>
  提醒当事人处理

rf sensitive batch-authorize [options]
  批量授权
  --ids <ids>         授权 ID 列表（逗号分隔）
  --decision <decision> 决策
```

#### 31.5.6 参考信息命令 (rf reference)

```
rf reference list [options]
  列出参考信息
  --env <env>         环境过滤（dev, test, prod）
  --keyword <kw>      关键词搜索

rf reference get <item_id>
  获取参考信息详情

rf reference deprecate <item_id> [options]
  标记废弃
  --reason <text>     废弃原因
```

#### 31.5.7 通知命令 (rf notifications)

```
rf notifications list [options]
  列出通知
  --unread            仅显示未读

rf notifications read <notification_id>
  标记已读

rf notifications read-all
  全部标记已读

rf notifications poll [options]
  轮询新通知
  --since <timestamp> 上次检查时间
```

#### 31.5.8 订阅命令 (rf subscriptions)

```
rf subscriptions list [options]
  列出我的订阅
  --type <type>       订阅类型（thread, category, keyword, user）

rf subscriptions add [options]
  添加订阅
  --type <type>       订阅类型
  --target <id>       订阅目标
  --notify <method>   通知方式（in_app, email）

rf subscriptions remove <subscription_id>
  取消订阅

rf subscriptions trending [options]
  热门订阅
  --type <type>       订阅类型
  --limit <n>         数量限制
```

#### 31.5.9 贡献统计命令 (rf contribution)

```
rf contribution me [options]
  我的贡献统计
  --period <period>   统计周期（week, month, year）

rf contribution leaderboard [options]
  贡献排行
  --period <period>   统计周期
  --limit <n>         数量限制
```

#### 31.5.10 协作网络命令 (rf collaboration)

```
rf collaboration network [options]
  协作网络图谱
  --room <room_id>    限定群组
  --from <date>       起始日期
  --to <date>         结束日期
  --min-weight <n>    最小关系权重

rf collaboration experts [options]
  领域专家
  --domain <domain>   知识领域
  --category <cat>    二级分类
  --limit <n>         数量限制

rf collaboration user-stats <user_id> [options]
  用户协作统计
```

#### 31.5.11 文件系统命令 (rf files)

```
rf files list [options]
  列出文件
  --layer <layer>     层级（L1, L2, L3）
  --search <query>    搜索内容

rf files get <file_path> [options]
  获取文件内容
  --prefer <type>     优先返回（summary | original）

rf files context [options]
  获取上下文文件列表
  --query <query>     查询内容
  --layer <layer>     指定层级

rf files compact [options]
  手动压缩
  --thread <id>       指定话题
  --force             强制压缩
```

#### 31.5.12 消息导入命令 (rf import)

```
rf import wechat [options]
  微信消息导入
  --file <path>       导入文件
  --room <room_id>    目标群组
  --format <format>   文件格式
  --reprocess         重新处理已存在消息

rf import status [options]
  导入任务状态
  --job <job_id>      任务 ID

rf import formats
  支持的导入格式
```

#### 31.5.13 管理命令 (rf admin)

```
rf admin whitelist list [options]
  列出白名单
  --active            仅显示激活用户

rf admin whitelist add <user_id> [options]
  添加白名单
  --name <name>       显示名称
  --email <email>     邮箱
  --role <role>       角色（member, admin）

rf admin whitelist update <user_id> [options]
  更新白名单
  --role <role>       角色
  --active <yes|no>   激活状态

rf admin whitelist remove <user_id>
  移除白名单

rf admin categories list
  列出信息类别

rf admin categories add [options]
  新增类别
  --code <code>       类别代码
  --name <name>       显示名称
  --triggers <hints>  触发提示（逗号分隔）

rf admin sensitive escalate [options]
  敏感授权升级
  --days <n>          超过 N 天未处理（默认 7）

rf admin cleanup [options]
  数据清理
  --dry-run           仅预览，不执行
```

#### 31.5.14 AI 管家命令 (rf butler)

```
rf butler digest [options]
  生成并推送快报
  --room <room_id>    目标群组
  --type <type>       快报类型（daily, weekly）

rf butler health
  系统健康报告

rf butler tasks [options]
  管家任务历史
  --status <status>   状态过滤
  --limit <n>         数量限制

rf butler experience [options]
  管家经验库
  --category <cat>    类别过滤

rf butler proposals [options]
  L3 权限提案
  --status <status>   状态过滤

rf butler approve <proposal_id> [options]
  批准提案
  --note <text>       审批备注

rf butler reject <proposal_id> [options]
  拒绝提案
  --reason <text>     拒绝原因
```

### 31.6 Help 系统

#### 31.6.1 顶层帮助

```
$ rf help

RippleFlow 群聊知识库系统

用法: rf <command> [subcommand] [options]

命令:
  auth          认证与会话
  threads       话题线索管理
  search        全文搜索
  qa            智能问答
  todos         个人待办管理
  actions       群聊任务管理
  sensitive     敏感授权处理
  reference     参考信息查看
  notifications 通知管理
  subscriptions 订阅管理
  contribution  贡献统计
  collaboration 协作网络
  files         文件系统
  import        消息导入
  admin         管理操作
  butler        AI 管家服务

全局选项:
  --help, -h     显示帮助
  --output, -o   输出格式 (json|table|yaml)
  --quiet, -q    静默模式
  --verbose, -v  详细输出

使用 "rf <command> --help" 查看命令详情
使用 "rf <command> <subcommand> --help" 查看子命令详情
```

#### 31.6.2 命令帮助

```
$ rf threads list --help

rf threads list - 列出话题线索

用法:
  rf threads list [options]

选项:
  --category <cat>    按类别过滤
                      可选值: tech_decision, qa_faq, bug_incident,
                              reference_data, action_item, discussion_notes,
                              knowledge_share, env_config, project_update

  --domain <domain>   按四大类过滤
                      可选值: knowledge, action, event, collaboration

  --status <status>   按状态过滤
                      可选值: active, resolved, archived, merged

  --room <room_id>    按群组过滤

  --from <date>       起始日期 (格式: YYYY-MM-DD)

  --to <date>         结束日期 (格式: YYYY-MM-DD)

  --page <n>          页码 (默认: 1)

  --size <n>          每页数量 (默认: 20, 最大: 100)

示例:
  rf threads list
  rf threads list --category qa_faq --size 50
  rf threads list --domain knowledge --from 2026-01-01
  rf threads list --status active -o json
```

### 31.7 nullclaw 调用示例

```bash
# nullclaw 查询帮助
$ rf help

# 查询具体命令
$ rf threads search --help

# 执行搜索
$ rf threads search "Redis配置" --category qa_faq -o json

# 创建待办
$ rf todos add "完成部署文档" --due 2026-03-10 --priority high

# 处理敏感授权
$ rf sensitive pending -o json
$ rf sensitive decide <auth_id> --decision approve

# 生成日报
$ rf butler digest --room <room_id> --type daily
```

### 31.8 CLI 与 API 对应关系

| CLI 命令 | API 端点 | 说明 |
|----------|----------|------|
| `rf threads list` | `GET /api/v1/threads` | 列出话题 |
| `rf threads get` | `GET /api/v1/threads/{id}` | 获取详情 |
| `rf threads search` | `GET /api/v1/search` | 搜索 |
| `rf qa` | `POST /api/v1/qa` | 问答 |
| `rf todos list` | `GET /api/v1/todos` | 列出待办 |
| `rf todos add` | `POST /api/v1/todos` | 创建待办 |
| `rf sensitive pending` | `GET /api/v1/sensitive/pending` | 待授权列表 |
| `rf sensitive decide` | `POST /api/v1/sensitive/{id}/decide` | 提交决策 |
| ... | ... | ... |

### 31.9 实现说明

```python
# CLI 实现结构
rippleflow/
├── cli/
│   ├── __init__.py
│   ├── main.py           # 入口，注册所有命令
│   ├── auth.py           # 认证命令
│   ├── threads.py        # 话题命令
│   ├── search.py         # 搜索命令
│   ├── todos.py          # 待办命令
│   ├── sensitive.py      # 敏感命令
│   ├── notifications.py  # 通知命令
│   ├── admin.py          # 管理命令
│   └── utils.py          # 工具函数
└── ...

# 使用 click 库实现
import click

@click.group()
def rf():
    """RippleFlow 群聊知识库系统"""
    pass

@rf.group()
def threads():
    """话题线索管理"""
    pass

@threads.command()
@click.option('--category', help='按类别过滤')
@click.option('--status', help='按状态过滤')
@click.option('--page', default=1, help='页码')
@click.option('--size', default=20, help='每页数量')
@click.option('--output', '-o', type=click.Choice(['json', 'table', 'yaml']))
def list(category, status, page, size, output):
    """列出话题线索"""
    # 调用 API 服务
    result = api_client.get('/api/v1/threads', params={
        'category': category,
        'status': status,
        'page': page,
        'size': size
    })
    # 格式化输出
    formatter.output(result, format=output)
```

### 31.10 输出格式规范

#### 31.10.1 格式选择

```bash
# 默认：人类可读的表格格式
rf threads list

# JSON 格式：供程序解析（nullclaw 使用）
rf threads list -o json

# YAML 格式：配置文件友好
rf threads list -o yaml
```

#### 31.10.2 JSON 输出规范

**通用响应结构**：

```json
{
  "success": true,
  "data": { ... },
  "meta": {
    "timestamp": "2026-03-03T10:30:00Z",
    "version": "1.0"
  }
}
```

**列表响应结构**：

```json
{
  "success": true,
  "data": {
    "items": [...],
    "pagination": {
      "page": 1,
      "size": 20,
      "total": 156,
      "total_pages": 8
    }
  }
}
```

**错误响应结构**：

```json
{
  "success": false,
  "error": {
    "code": "RESOURCE_NOT_FOUND",
    "message": "话题不存在",
    "details": {
      "resource": "thread",
      "id": "abc-123"
    }
  }
}
```

#### 31.10.3 各命令输出示例

##### rf threads list

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "550e8400-e29b-41d4-a716-446655440001",
        "title": "Redis 连接池配置方案",
        "category": "qa_faq",
        "status": "active",
        "room": {
          "id": "room-001",
          "name": "技术讨论群"
        },
        "summary": "推荐使用 lettuce 连接池...",
        "confidence": 0.92,
        "message_count": 12,
        "created_at": "2026-03-01T14:30:00Z",
        "last_message_at": "2026-03-02T09:15:00Z"
      }
    ],
    "pagination": {
      "page": 1,
      "size": 20,
      "total": 156,
      "total_pages": 8
    }
  }
}
```

##### rf threads get

```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440001",
    "title": "Redis 连接池配置方案",
    "category": "qa_faq",
    "info_domain": "knowledge",
    "status": "active",
    "room": {
      "id": "room-001",
      "name": "技术讨论群"
    },
    "summary": "推荐使用 lettuce 连接池，配置参数：\n- maxTotal: 100\n- maxIdle: 50\n- minIdle: 10\n- timeout: 3000ms",
    "summary_version": 3,
    "confidence": 0.92,
    "participants": [
      {"user_id": "user-001", "display_name": "张三"},
      {"user_id": "user-002", "display_name": "李四"}
    ],
    "messages": [
      {
        "id": "msg-001",
        "sender": "张三",
        "content": "Redis 连接池怎么配置？",
        "timestamp": "2026-03-01T14:30:00Z"
      }
    ],
    "action_items": [],
    "related_threads": [],
    "created_at": "2026-03-01T14:30:00Z",
    "updated_at": "2026-03-02T09:15:00Z"
  }
}
```

##### rf threads search

```json
{
  "success": true,
  "data": {
    "query": "Redis配置",
    "items": [
      {
        "id": "550e8400-e29b-41d4-a716-446655440001",
        "title": "Redis 连接池配置方案",
        "category": "qa_faq",
        "summary_snippet": "...推荐使用 lettuce 连接池...",
        "relevance_score": 0.95,
        "room_name": "技术讨论群"
      }
    ],
    "total": 5,
    "search_time_ms": 23
  }
}
```

##### rf qa

```json
{
  "success": true,
  "data": {
    "question": "如何配置 Redis 连接池",
    "answer": "根据群内讨论，推荐使用 lettuce 连接池，主要配置参数如下：\n\n1. maxTotal: 100（最大连接数）\n2. maxIdle: 50（最大空闲连接）\n3. minIdle: 10（最小空闲连接）\n4. timeout: 3000ms（超时时间）\n\n示例代码见话题详情。",
    "sources": [
      {
        "thread_id": "550e8400-e29b-41d4-a716-446655440001",
        "title": "Redis 连接池配置方案",
        "relevance": 0.95
      }
    ],
    "confidence": 0.88,
    "thread_id": "550e8400-e29b-41d4-a716-446655440001"
  }
}
```

##### rf todos list

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "todo-001",
        "title": "完成部署文档",
        "status": "open",
        "priority": "high",
        "due_date": "2026-03-10",
        "days_until_due": 7,
        "thread": {
          "id": "thread-001",
          "title": "部署流程讨论"
        },
        "created_at": "2026-03-03T10:00:00Z"
      }
    ],
    "summary": {
      "total": 5,
      "open": 3,
      "in_progress": 1,
      "overdue": 1
    }
  }
}
```

##### rf todos add

```json
{
  "success": true,
  "data": {
    "id": "todo-002",
    "title": "完成部署文档",
    "status": "open",
    "priority": "high",
    "due_date": "2026-03-10",
    "created_at": "2026-03-03T10:30:00Z"
  },
  "message": "待办创建成功"
}
```

##### rf sensitive pending

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "auth-001",
        "thread_id": "thread-001",
        "thread_title": "数据库连接配置",
        "detected_type": "password",
        "detected_at": "2026-03-02T15:00:00Z",
        "pending_days": 1,
        "required_approvals": 2,
        "current_approvals": 0,
        "approvers": [
          {"user_id": "user-001", "display_name": "张三", "status": "pending"},
          {"user_id": "user-002", "display_name": "李四", "status": "pending"}
        ]
      }
    ],
    "total": 3,
    "escalation_candidates": 1
  }
}
```

##### rf sensitive decide

```json
{
  "success": true,
  "data": {
    "auth_id": "auth-001",
    "decision": "approve",
    "decided_at": "2026-03-03T10:30:00Z",
    "overall_status": "pending",
    "remaining_approvals": 1
  },
  "message": "决策已记录"
}
```

##### rf butler digest

```json
{
  "success": true,
  "data": {
    "digest_id": "digest-001",
    "type": "daily",
    "room_id": "room-001",
    "period": {
      "from": "2026-03-02T00:00:00Z",
      "to": "2026-03-02T23:59:59Z"
    },
    "content": "## 每日快报 (2026-03-02)\n\n### 热门话题\n1. Redis 连接池配置方案 (12 条消息)\n2. ...\n\n### 新增待办\n- 完成部署文档 (张三, 截止: 03-10)\n\n### 问答精选\nQ: Redis 连接池怎么配置？\nA: 推荐使用 lettuce...",
    "sent_at": "2026-03-03T09:00:00Z",
    "recipient_count": 25
  }
}
```

##### rf butler health

```json
{
  "success": true,
  "data": {
    "status": "healthy",
    "checks": {
      "database": {"status": "ok", "latency_ms": 5},
      "llm": {"status": "ok", "latency_ms": 120},
      "cache": {"status": "ok", "latency_ms": 1}
    },
    "metrics": {
      "threads_total": 1523,
      "threads_active": 89,
      "messages_total": 45678,
      "pending_actions": 12,
      "pending_sensitive": 3
    },
    "period_stats": {
      "threads_today": 5,
      "qa_today": 12,
      "actions_completed_today": 3
    }
  }
}
```

##### rf collaboration network

```json
{
  "success": true,
  "data": {
    "nodes": [
      {"id": "user-001", "name": "张三", "weight": 45},
      {"id": "user-002", "name": "李四", "weight": 38}
    ],
    "edges": [
      {
        "source": "user-001",
        "target": "user-002",
        "weight": 12,
        "types": ["reply", "mention"]
      }
    ],
    "period": {
      "from": "2026-02-01",
      "to": "2026-03-03"
    },
    "stats": {
      "total_interactions": 156,
      "avg_interactions_per_user": 8.2
    }
  }
}
```

##### rf import wechat

```json
{
  "success": true,
  "data": {
    "job_id": "import-001",
    "status": "processing",
    "file": "chat_history_20260303.json",
    "room_id": "room-001",
    "progress": {
      "total": 1000,
      "processed": 450,
      "imported": 420,
      "skipped": 30,
      "percentage": 45
    },
    "started_at": "2026-03-03T10:00:00Z",
    "estimated_completion": "2026-03-03T10:15:00Z"
  }
}
```

##### rf admin whitelist list

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "ldap_user_id": "zhangsan",
        "display_name": "张三",
        "email": "zhangsan@example.com",
        "role": "member",
        "is_active": true,
        "added_at": "2026-01-15T08:00:00Z",
        "added_by": "admin"
      }
    ],
    "total": 25,
    "admins": 3,
    "members": 22
  }
}
```

#### 31.10.4 Table 输出格式

**默认表格格式**（人类可读）：

```
$ rf threads list --category qa_faq

ID          TITLE                        CATEGORY   STATUS   ROOM         MESSAGES
─────────────────────────────────────────────────────────────────────────────────────
550e8400... Redis 连接池配置方案         qa_faq     active   技术讨论群   12
6ba7b810... Docker 网络配置问题          qa_faq     active   运维群       8
3f2e8d90... 如何调试 Kafka 消费延迟      qa_faq     resolved 技术讨论群   15

共 3 条 (第 1 页，共 1 页)
```

**详细表格格式**（`--verbose`）：

```
$ rf threads get 550e8400-e29b-41d4-a716-446655440001

话题详情
────────────────────────────────────────────────────────────
ID:           550e8400-e29b-41d4-a716-446655440001
标题:         Redis 连接池配置方案
类别:         qa_faq (知识库)
状态:         active
置信度:       92%
创建时间:     2026-03-01 14:30:00
最后消息:     2026-03-02 09:15:00

摘要:
  推荐使用 lettuce 连接池，配置参数：
  - maxTotal: 100
  - maxIdle: 50
  - minIdle: 10
  - timeout: 3000ms

参与者: 张三, 李四, 王五
消息数: 12
待办项: 0
```

#### 31.10.5 YAML 输出格式

```yaml
$ rf threads list -o yaml

success: true
data:
  items:
    - id: 550e8400-e29b-41d4-a716-446655440001
      title: Redis 连接池配置方案
      category: qa_faq
      status: active
      room:
        id: room-001
        name: 技术讨论群
      message_count: 12
  pagination:
    page: 1
    size: 20
    total: 156
```

### 31.11 错误码规范

#### 31.11.1 错误码结构

```
错误码格式: <类别>_<具体错误>

类别:
- AUTH      认证相关
- RESOURCE  资源相关
- VALIDATE  参数验证
- BUSINESS  业务逻辑
- SYSTEM    系统错误
```

#### 31.11.2 标准错误码列表

| 错误码 | HTTP 状态码 | 说明 | 场景 |
|--------|-------------|------|------|
| `AUTH_UNAUTHORIZED` | 401 | 未登录 | Token 无效或过期 |
| `AUTH_FORBIDDEN` | 403 | 无权限 | 非白名单用户 |
| `AUTH_TOKEN_EXPIRED` | 401 | Token 过期 | 需要重新登录 |
| `AUTH_SSO_FAILED` | 401 | SSO 登录失败 | LDAP 认证失败 |
| `RESOURCE_NOT_FOUND` | 404 | 资源不存在 | 话题/待办/用户不存在 |
| `RESOURCE_DELETED` | 410 | 资源已删除 | 话题已归档删除 |
| `RESOURCE_CONFLICT` | 409 | 资源冲突 | 重复创建 |
| `VALIDATE_MISSING_PARAM` | 400 | 缺少参数 | 必填参数未提供 |
| `VALIDATE_INVALID_PARAM` | 400 | 参数无效 | 参数格式/值错误 |
| `VALIDATE_OUT_OF_RANGE` | 400 | 参数超出范围 | page/size 超限 |
| `BUSINESS_SENSITIVE_PENDING` | 403 | 敏感内容待授权 | 话题未完成授权 |
| `BUSINESS_NOT_PARTICIPANT` | 403 | 非话题参与者 | 无权修改话题 |
| `BUSINESS_ACTION_COMPLETED` | 409 | 任务已完成 | 重复操作已完成任务 |
| `BUSINESS_ESCALATION_REQUIRED` | 403 | 需要升级处理 | 敏感授权超时 |
| `SYSTEM_DATABASE_ERROR` | 500 | 数据库错误 | 连接/查询失败 |
| `SYSTEM_LLM_ERROR` | 503 | LLM 服务错误 | 模型调用失败 |
| `SYSTEM_RATE_LIMITED` | 429 | 请求频率限制 | 超过限流阈值 |
| `SYSTEM_MAINTENANCE` | 503 | 系统维护中 | 服务不可用 |

#### 31.11.3 错误响应示例

**参数验证错误**：

```json
{
  "success": false,
  "error": {
    "code": "VALIDATE_INVALID_PARAM",
    "message": "参数格式错误",
    "details": {
      "field": "category",
      "value": "invalid_cat",
      "allowed": ["tech_decision", "qa_faq", "bug_incident", ...]
    }
  }
}
```

**资源不存在错误**：

```json
{
  "success": false,
  "error": {
    "code": "RESOURCE_NOT_FOUND",
    "message": "话题不存在",
    "details": {
      "resource": "thread",
      "id": "550e8400-e29b-41d4-a716-446655440099"
    }
  }
}
```

**业务逻辑错误**：

```json
{
  "success": false,
  "error": {
    "code": "BUSINESS_SENSITIVE_PENDING",
    "message": "话题包含敏感内容，等待授权",
    "details": {
      "thread_id": "550e8400-e29b-41d4-a716-446655440001",
      "pending_authorizations": 2,
      "can_view": false
    }
  }
}
```

**系统错误**：

```json
{
  "success": false,
  "error": {
    "code": "SYSTEM_LLM_ERROR",
    "message": "LLM 服务暂时不可用",
    "details": {
      "provider": "zhipu",
      "model": "glm-4-plus",
      "retry_after": 30
    }
  }
}
```

#### 31.11.4 错误处理最佳实践

```bash
# 检查命令执行结果
$ rf threads get invalid-id
Error: RESOURCE_NOT_FOUND - 话题不存在

# JSON 格式下解析错误
$ rf threads get invalid-id -o json
{"success": false, "error": {"code": "RESOURCE_NOT_FOUND", ...}}

# 检查退出码
$ rf threads get invalid-id
$ echo $?
1
```

### 31.12 退出码规范

#### 31.12.1 标准退出码

| 退出码 | 含义 | 说明 |
|--------|------|------|
| 0 | 成功 | 命令执行成功 |
| 1 | 一般错误 | 未分类错误 |
| 2 | 参数错误 | 命令参数无效 |
| 3 | 认证错误 | 未登录或 Token 无效 |
| 4 | 权限错误 | 无操作权限 |
| 5 | 资源错误 | 资源不存在或已删除 |
| 6 | 业务错误 | 业务逻辑约束冲突 |
| 7 | 系统错误 | 服务不可用 |
| 8 | 网络错误 | 连接超时或失败 |
| 130 | 用户中断 | Ctrl+C 中断 |

#### 31.12.2 退出码映射表

| 错误码类别 | 退出码 |
|------------|--------|
| `AUTH_*` | 3 |
| `RESOURCE_*` | 5 |
| `VALIDATE_*` | 2 |
| `BUSINESS_*` | 6 |
| `SYSTEM_*` | 7 |

#### 31.12.3 脚本集成示例

```bash
#!/bin/bash
# nullclaw Routine 脚本示例

# 执行命令并检查退出码
rf threads search "Redis配置" -o json > /tmp/result.json
exit_code=$?

case $exit_code in
  0)
    # 成功，处理结果
    cat /tmp/result.json | jq '.data.items[]'
    ;;
  3)
    # 认证错误，尝试重新登录
    rf auth login --sso
    ;;
  7)
    # 系统错误，等待重试
    sleep 30
    # 重试逻辑...
    ;;
  *)
    # 其他错误，记录日志
    echo "命令执行失败: exit code $exit_code" >&2
    ;;
esac
```

### 31.13 完整命令参数规范

#### 31.13.1 参数类型

| 类型 | 格式 | 示例 |
|------|------|------|
| `string` | 文本 | `--title "部署文档"` |
| `integer` | 整数 | `--size 50` |
| `float` | 浮点数 | `--min-weight 0.5` |
| `boolean` | 布尔值 | `--verbose`, `--no-cache` |
| `date` | 日期 | `--due 2026-03-10` |
| `datetime` | 日期时间 | `--from "2026-03-01T00:00:00Z"` |
| `enum` | 枚举值 | `--status active` |
| `list` | 列表 | `--tags tag1,tag2,tag3` |
| `path` | 文件路径 | `--file ./data.json` |

#### 31.13.2 通用分页参数

```
--page <n>          页码（从 1 开始）
--size <n>          每页数量（默认 20，最大 100）
--cursor <token>    游标分页（替代 page/size）
--no-pagination     禁用分页，返回全部
```

#### 31.13.3 通用过滤参数

```
--from <datetime>   起始时间
--to <datetime>     结束时间
--room <room_id>    群组过滤
--user <user_id>    用户过滤
--status <status>   状态过滤
--category <cat>    类别过滤
```

#### 31.13.4 通用输出参数

```
-o, --output <format>     输出格式：json | table | yaml
-f, --fields <fields>     指定输出字段（逗号分隔）
--no-header               表格输出不显示表头
--no-footer               表格输出不显示统计行
--wrap                    表格输出自动换行
--width <n>               表格输出宽度
```

### 31.14 命令完整参数速查表

#### rf threads list

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `--category` | enum | - | 类别过滤 |
| `--domain` | enum | - | 四大类过滤 |
| `--status` | enum | - | 状态过滤 |
| `--room` | string | - | 群组 ID |
| `--from` | date | - | 起始日期 |
| `--to` | date | - | 结束日期 |
| `--page` | int | 1 | 页码 |
| `--size` | int | 20 | 每页数量 |
| `--sort` | string | `-last_message_at` | 排序字段 |
| `-o` | enum | table | 输出格式 |

#### rf threads search

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `<query>` | string | - | 搜索关键词（必填） |
| `--category` | enum | - | 类别过滤 |
| `--domain` | enum | - | 四大类过滤 |
| `--room` | string | - | 群组过滤 |
| `--from` | date | - | 起始日期 |
| `--to` | date | - | 结束日期 |
| `--ignore-window` | flag | - | 忽略时间窗口 |
| `--size` | int | 10 | 结果数量 |
| `-o` | enum | table | 输出格式 |

#### rf qa

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `<question>` | string | - | 问题（必填） |
| `--category` | enum | - | 类别限定 |
| `--ignore-window` | flag | - | 忽略时间窗口 |
| `--no-summary` | flag | - | 不生成摘要 |
| `-o` | enum | json | 输出格式 |

#### rf todos list

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `--status` | enum | - | 状态过滤（open, in_progress, done, cancelled） |
| `--due-before` | date | - | 截止日期之前 |
| `--due-after` | date | - | 截止日期之后 |
| `--overdue` | flag | - | 仅显示过期 |
| `--priority` | enum | - | 优先级过滤 |
| `--include-collab` | flag | - | 包含协作者待办 |
| `--page` | int | 1 | 页码 |
| `--size` | int | 20 | 每页数量 |
| `-o` | enum | table | 输出格式 |

#### rf todos add

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `<title>` | string | - | 待办标题（必填） |
| `--description` | string | - | 详细描述 |
| `--due` | date | - | 截止日期 |
| `--priority` | enum | medium | 优先级（high, medium, low） |
| `--tags` | list | - | 标签（逗号分隔） |
| `--collaborators` | list | - | 协作者（逗号分隔） |
| `--thread` | string | - | 关联话题 ID |
| `-o` | enum | json | 输出格式 |

#### rf sensitive pending

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `--room` | string | - | 群组过滤 |
| `--days` | int | - | 等待天数过滤 |
| `--escalation-candidates` | flag | - | 仅显示升级候选 |
| `-o` | enum | table | 输出格式 |

#### rf sensitive decide

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `<auth_id>` | string | - | 授权 ID（必填） |
| `--decision` | enum | - | 决策（approve, reject, desensitize）|
| `--note` | string | - | 备注 |
| `--desensitized` | string | - | 脱敏内容（desensitize 时必填） |
| `-o` | enum | json | 输出格式 |

#### rf butler digest

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `--room` | string | - | 目标群组 ID（必填） |
| `--type` | enum | daily | 快报类型（daily, weekly） |
| `--date` | date | 今天 | 快报日期 |
| `--dry-run` | flag | - | 仅生成不发送 |
| `-o` | enum | json | 输出格式 |

#### rf import wechat

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `--file` | path | - | 导入文件路径（必填） |
| `--room` | string | - | 目标群组 ID |
| `--format` | enum | auto | 文件格式（auto, json, csv） |
| `--encoding` | string | utf-8 | 文件编码 |
| `--reprocess` | flag | - | 重新处理已存在消息 |
| `--dry-run` | flag | - | 预览模式 |
| `-o` | enum | json | 输出格式 |

---

## 32. nullclaw 安全机制（security 模块）

### 32.1 概述

nullclaw 提供完整的安全机制，包括配对验证、审计日志、频率限制等能力。

| 能力 | 说明 | 配置项 |
|------|------|--------|
| **Pairing** | 新设备配对验证 | `security.pairing` |
| **Audit** | 操作审计日志 | `security.audit` |
| **Rate Limit** | 频率限制 | `security.rate_limit` |

### 32.2 配对验证（Pairing）

新设备首次连接时需要输入配对码：

```
┌─────────────────────────────────────────────────────────────────┐
│                    配对验证流程                                  │
│                                                                 │
│  新设备连接                                                      │
│      │                                                          │
│      ▼                                                          │
│  ┌─────────────┐                                                │
│  │ 显示配对码   │  ← 6位数字，5分钟有效                          │
│  │ XXXXXX      │                                                │
│  └─────────────┘                                                │
│      │                                                          │
│      ▼ 用户输入配对码                                            │
│  ┌─────────────┐                                                │
│  │ 验证配对码   │  ← 最多尝试 3 次                               │
│  └─────────────┘                                                │
│      │                                                          │
│      ├── 成功 → 设备已授权                                       │
│      └── 失败 → 拒绝连接                                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 32.3 审计日志（Audit）

记录所有敏感操作：

| 事件类型 | 说明 |
|----------|------|
| `tool_call` | 工具调用记录 |
| `routine_create` | Routine 创建 |
| `routine_modify` | Routine 修改 |
| `proposal_submit` | 提案提交 |
| `memory_modify` | Memory 修改 |
| `cost_exceeded` | 成本超限 |

**审计日志配置**：

```json
{
  "audit": {
    "log_path": ".rippleflow/logs/audit.log",
    "retention_days": 365,
    "events": ["tool_call", "routine_create", "proposal_submit"]
  }
}
```

### 32.4 频率限制（Rate Limit）

防止系统被滥用：

```json
{
  "rate_limit": {
    "enabled": true,
    "requests_per_minute": 60,
    "burst": 10
  }
}
```

### 32.5 完整安全配置示例

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
      ]
    },

    "rate_limit": {
      "enabled": true,
      "requests_per_minute": 60,
      "burst": 10
    }
  }
}
```

---

## 33. FAQ 知识库架构（群聊知识沉淀）

> 完整产品需求见 `docs/群聊知识沉淀与FAQ智能演进系统_PRD.md`

### 33.1 架构定位

FAQ 知识库遵循**机制与策略分离**原则：

| 层次 | 负责方 | 职责 |
|------|--------|------|
| **存储机制** | RippleFlow 平台 | `faq_*` 表存储 + `/api/v1/faq/*` REST API |
| **生成策略** | nullclaw AI 管家 | 决定何时生成、如何组织章节、何时更新/合并 |
| **审核机制** | RippleFlow 平台 | `review_status` 状态机 + 审核 API |
| **审核决策** | 管理员（人工） | 确认/驳回 nullclaw 生成的 FAQ 草稿 |

### 33.2 数据模型

```
faq_documents（每群一份）
    └── faq_sections（动态章节树，nullclaw 维护）
            └── faq_items（最小问答单元）
                    ├── question, answer, question_variants
                    ├── source_threads[]（溯源到原始 thread_id）
                    ├── confidence（AI 置信度）
                    ├── review_status: pending | confirmed | rejected
                    └── view_count, helpful_count

faq_versions（变更历史）
    └── item_id, version, change_type, change_by, change_reason
```

### 33.3 数据流

```
qa_faq 类话题线索完成 Stage 0-4
    ↓ 事件推送至 nullclaw
nullclaw 决策 → 调用 POST /api/v1/faq/items（pending）
    ↓ 管理员审核
review_status=confirmed → 对普通用户可见

用户问答时：
    阶段1：FAQ 精确匹配（LLM 评分 > 0.9）→ 直接返回 FAQ
    阶段2：FAQ 语义匹配（0.7-0.9）→ 返回 FAQ + 确认提示
    阶段3：全文检索 + LLM 综合回答（兜底）
```

> **注意**：相似度判断由 LLM 直接评分（非向量 embedding），符合"不使用向量检索"架构约束。

### 33.4 nullclaw 知识运营 Routine

| Routine | 触发时机 | 职责 |
|---------|----------|------|
| Routine A | 每日 02:00 | 热点话题 FAQ 化 |
| Routine B | 每周一 09:00 | FAQ 质量提升 |
| Routine C | 每月 1 日 | 知识盲区发现 |
| Routine D | 某问题被问第 3 次 | 实时拦截重复问题 |

---

## 34. nullclaw 依赖管理（P0-2）

### 34.1 依赖关系概述

RippleFlow 平台与 nullclaw 之间存在**单向推送依赖**：平台流水线（Stage 0-4）结束后，通过 HTTP POST 将事件推送至 nullclaw 网关；nullclaw 通过 `rf` CLI 命令（HTTP API）调用平台能力。

```
RippleFlow Platform                nullclaw Agent
─────────────────                  ─────────────────
流水线事件推送 ──────────────────► 事件接收（webhook）
                                   │
RF API ◄────────────────────────── rf CLI 调用（rf threads, rf qa, ...）
```

**平台对 nullclaw 的依赖**：仅事件推送（Fire-and-Forget），不等待响应。
**nullclaw 对平台的依赖**：读写 API、CLI 命令，需要平台正常运行。

### 34.2 SLA 目标

| 指标 | 目标值 | 说明 |
|------|--------|------|
| 事件推送成功率 | ≥ 99% | nullclaw 在线时；离线时进入本地队列 |
| 推送 P99 延迟 | ≤ 500ms | HTTP POST 超时上限 |
| 推送重试窗口 | 24 小时 | 超过后告警管理员 |
| nullclaw 不可用最大影响 | 无损平台核心功能 | 摘要更新延迟，不影响消息存储/问答 |
| RF API 对 nullclaw 可用性 | 99.9% | nullclaw CLI 依赖平台 |

### 34.3 事件推送策略（RippleFlow → nullclaw）

```
Stage 4 完成
     │
     ▼
POST {NULLCLAW_GATEWAY}/webhook/rippleflow
     │
     ├── 成功 (2xx)
     │       └── 记录日志，继续
     │
     └── 失败 (连接超时 / 非 2xx)
             │
             ▼
         写入本地待处理队列（nullclaw_pending_events 表）
         status = 'pending', retry_count = 0
```

#### 重试策略

| 重试次数 | 间隔 | 说明 |
|----------|------|------|
| 第 1 次 | 立即 | 瞬时抖动 |
| 第 2 次 | 30 秒 | 指数退避 |
| 第 3 次 | 5 分钟 | 指数退避 |
| 第 4 次 | 30 分钟 | 长间隔 |
| 第 5 次（最终） | 2 小时 | 最大重试 |
| 超过 24 小时未投递 | — | 告警管理员，status → 'expired' |

#### nullclaw_pending_events 表（DDL 补充）

```sql
-- PostgreSQL
CREATE TABLE nullclaw_pending_events (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type  VARCHAR(50) NOT NULL,          -- message_processed | thread_updated
    payload     JSONB NOT NULL,
    status      VARCHAR(20) DEFAULT 'pending'
                CHECK (status IN ('pending','delivered','failed','expired')),
    retry_count INTEGER DEFAULT 0,
    next_retry_at TIMESTAMPTZ DEFAULT NOW(),
    last_error  TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    delivered_at TIMESTAMPTZ
);
CREATE INDEX idx_pending_events_retry ON nullclaw_pending_events (next_retry_at)
    WHERE status = 'pending';
```

### 34.4 nullclaw 不可用时的降级模式（最小可用模式）

当 nullclaw 不可用时，RippleFlow 平台核心功能**完全不受影响**：

| 功能 | nullclaw 可用 | nullclaw 不可用 | 降级说明 |
|------|---------------|-----------------|----------|
| 消息接收与存储 | ✅ | ✅ | 无依赖 |
| Stage 0–4 流水线 | ✅ | ✅ | 无依赖 |
| FAQ 问答（Q&A） | ✅ | ✅ | 平台全文检索兜底 |
| 敏感信息授权 | ✅ | ✅ | 无依赖 |
| 摘要更新（Stage 5） | ✅ | ⚠️ 延迟 | 事件进入待处理队列 |
| 每日摘要推送 | ✅ | ⚠️ 跳过 | nullclaw cron 不执行 |
| FAQ 自动生成 | ✅ | ⚠️ 延迟 | nullclaw Routine 不执行 |
| 知识图谱更新 | ✅ | ⚠️ 延迟 | nullclaw Routine 不执行 |

**最小可用模式**：即使 nullclaw 完全不可用，平台仍可提供消息存储、检索、问答、敏感授权等核心服务。管理员可手动触发摘要更新：`rf butler digest --manual`。

### 34.5 nullclaw 调用平台的超时/重试策略

nullclaw 通过 `rf` CLI 命令调用平台 API，超时策略由 nullclaw 侧配置：

```yaml
# nullclaw 配置（供参考，实际由 nullclaw 维护）
rippleflow_api:
  base_url: "http://rippleflow:8000"
  timeout: 30s                    # 单次请求超时
  retry:
    max_attempts: 3
    backoff: exponential           # 1s → 2s → 4s
    retry_on: [429, 500, 502, 503, 504]
  circuit_breaker:
    threshold: 5                   # 连续 5 次失败开启熔断
    half_open_after: 60s           # 60s 后探测是否恢复
```

### 34.6 健康检查端点

```
GET /health/nullclaw     # 平台检查 nullclaw 是否可达
GET /health/pending      # 待处理事件队列状态
```

响应示例：
```json
{
  "nullclaw": {
    "status": "degraded",
    "last_success": "2026-03-05T08:30:00Z",
    "pending_events": 47,
    "oldest_pending_age_minutes": 23
  }
}
```

### 34.7 监控与告警

| 指标 | 告警阈值 | 告警对象 |
|------|----------|----------|
| `nullclaw_pending_events_total` | ≥ 100 | 管理员 |
| `nullclaw_oldest_pending_age_minutes` | ≥ 60 | 管理员 |
| `nullclaw_delivery_failures_total` (5min) | ≥ 10 | 管理员 |
| `nullclaw_circuit_breaker_open` | = 1 | 管理员 |

---

## 35. LLM 调用成本优化（P1-1）

### 35.1 成本分析

```
单条消息处理 token 估算（当前基准）：
- Stage 0 敏感检测：  ~400 tokens
- Stage 1 噪声过滤：  ~200 tokens
- Stage 2 分类：      ~500 tokens
- Stage 3 话题匹配：  ~800 tokens
- Stage 4 结构化提取：~600 tokens
合计：~2500 tokens/消息

10人团队，每日500条消息：
- 每日消耗：1,250,000 tokens
- 每月消耗：37,500,000 tokens
```

### 35.2 优化策略一：Stage 1 规则前置过滤

在 Stage 1 LLM 调用前，先执行轻量规则判断，命中规则直接跳过 LLM：

| 规则 | 判定 | 说明 |
|------|------|------|
| 内容长度 < 5 字符 | 噪声 | 过短消息 |
| 纯表情/符号 | 噪声 | 无文字内容 |
| 黑名单短回复（ok/收到/好的/👍/+1 等） | 噪声 | 常见无价值回复 |
| 内容长度 > 200 字符 | 非噪声 | 较长消息一般有价值 |

**预计效果**：减少 30-40% 的 Stage 1 LLM 调用。

### 35.3 优化策略二：Stage 2 批量分类

将积压消息批量合并为单次 LLM 调用（最多 10 条/批次），而非每条独立调用：

```
触发条件：
- 积压队列 ≥ 3 条，等待批量
- 等待超过 2 秒，强制触发（防止延迟积压）

批量处理流程：
单条进入队列 → 等待聚合（最多2s）→ 批量LLM分类 → 结果拆分回写

预计效果：减少 40-60% 的 Stage 2 LLM 调用次数
```

批量分类 Prompt 见 `06_llm_prompt_templates.md §22`。

### 35.4 优化策略三：精细化模型选择

在 §13.3 基础上，按消息特征动态选择模型：

| 场景 | 选用模型 | 条件 |
|------|----------|------|
| Stage 1 短消息噪声检测 | `glm-4-flash` | 内容长度 ≤ 50 字符，且规则无法确定 |
| Stage 2 单一明显类别 | `glm-4-flash` | 含强特征关键词（如"#部署"、"@张三 待办"） |
| Stage 2 多类别模糊 | `glm-4-air` | 无明显关键词，需语义理解 |
| Stage 3 高置信度匹配 | `glm-4-air` | 相同 group_id 近7天已有相似话题 |
| Stage 3 新话题判断 | `glm-4-plus` | 无历史相似话题，需准确分析 |
| Q&A 关键词提取 | `glm-4-flash` | 简单提取任务 |

> Stage 0 敏感检测严禁降级（见 §13.3）。

### 35.5 优化效果预估

| 策略 | 预计节省 |
|------|----------|
| 规则前置过滤（Stage 1） | -15% |
| 批量处理（Stage 2） | -25% |
| 精细化模型选择 | -15% |
| 合计 | **~55%** |

### 35.6 监控补充指标

```yaml
新增监控指标（在 §13.5 基础上）：
  - stage1_rule_filter_total{result}     # 规则命中次数（noise/non_noise）
  - stage2_batch_size_histogram          # 每次批量的消息数分布
  - llm_cost_estimated_tokens{stage}    # 各阶段 token 消耗估算
```

---

## 36. 消息处理可靠性 - 死信队列（P1-2）

### 36.1 当前问题

```
当前内存队列模式（小型部署）的潜在风险：
- 进程重启时队列中的消息丢失
- LLM 调用超时导致消息卡死
- 无法人工重试特定失败消息
- 管理员对处理失败无感知
```

### 36.2 失败消息处理流程

```
Stage 0–4 任意阶段失败
         │
         ├── 可重试错误（LLM 超时/429/503）
         │       └── 指数退避重试（最多3次）
         │               ├── 重试成功 → 继续流水线
         │               └── 3次耗尽 → 写入 failed_messages（DLQ）
         │
         └── 不可重试错误（内容解析失败/业务规则冲突）
                 └── 直接写入 failed_messages（DLQ）
                         └── 推送管理员告警

管理员操作（Web Dashboard）：
  [重新处理] → 消息重新入队（高优先级）
  [跳过]     → status → 'skipped'，不再处理
  [人工标记] → 管理员手动填写处理结果
```

### 36.3 failed_messages 表（DDL 见 §数据库）

| 字段 | 说明 |
|------|------|
| `message_id` | 关联原始消息 |
| `failed_stage` | 失败所在阶段（stage0/stage1/.../stage4） |
| `error_type` | 错误分类（llm_timeout/llm_error/parse_error/business_error） |
| `error_detail` | 错误详情 |
| `retry_count` | 已重试次数 |
| `status` | 待处理/重试中/已跳过/已处理 |
| `resolved_by` | 管理员 ID |

### 36.4 管理监控看板（Web Dashboard 新增页面）

```
消息处理监控看板：
┌──────────────────────────────────────────────┐
│  待处理: 123  处理中: 5  今日成功: 456        │
│  今日失败: 2  平均处理时长: 2.3s              │
├──────────────────────────────────────────────┤
│  失败消息列表（死信队列）                      │
│  ┌──────────┬──────────┬──────┬────────────┐ │
│  │ 消息ID   │ 失败阶段 │ 原因 │   操作      │ │
│  ├──────────┼──────────┼──────┼────────────┤ │
│  │ msg_001  │ Stage2   │ 超时 │ [重试][跳过]│ │
│  │ msg_002  │ Stage4   │ 解析 │ [重试][跳过]│ │
│  └──────────┴──────────┴──────┴────────────┘ │
└──────────────────────────────────────────────┘
```

### 36.5 API 端点（新增）

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/v1/admin/dlq` | GET | 获取死信队列列表 |
| `/api/v1/admin/dlq/{id}/retry` | POST | 重新处理失败消息 |
| `/api/v1/admin/dlq/{id}/skip` | POST | 跳过失败消息 |

---

## 37. 数据归档策略（P2-1）

### 37.1 三级存储架构

```
L1 热数据（0-90天）
  存储：主数据库（PostgreSQL/SQLite）
  访问：实时查询，完整索引
  规则：全部消息和话题线索

L2 温数据（90天-2年）
  存储：归档分区表（或独立归档库）
  访问：可接受延迟（秒级）
  规则：activity_status = 'inactive'，无近期查看/修改
  保留：摘要字段，删除完整消息体（可恢复）

L3 冷数据（2年以上）
  存储：对象存储（MinIO/S3），Gzip 压缩
  访问：需管理员手动申请恢复
  元数据：数据库保留标题+摘要用于检索
```

### 37.2 归档触发规则

| 条件 | 动作 | 说明 |
|------|------|------|
| 话题线索超 90 天无新消息 | L1 → L2 | 非活跃话题 |
| 话题类别为 tech_decision/reference_data | 不归档 | 永久保留决策类数据 |
| 用户收藏的话题（is_favorite=true） | 不归档 | 尊重用户标记 |
| L2 数据超 2 年 | L2 → L3 | 压缩归档 |

> **注意**：归档逻辑由 nullclaw Routine 定期执行（每月 1 日），
> 不在平台核心流水线中。

### 37.3 归档状态字段

`topic_threads` 表新增：
- `archive_status`：`active` | `archived_l2` | `archived_l3`
- `archived_at`：归档时间
- `archive_path`：L3 对象存储路径（L3 时填写）

`messages` 表新增：
- `archive_status`：`active` | `archived`
- `content_archived`：BOOLEAN，内容是否已从 DB 删除（归档到 L3 后）

---

## 38. 敏感授权分级机制（P1-3）

### 38.1 当前机制问题

原设计采用"全员授权 + 7天升级管理员"的统一策略，对所有敏感内容一视同仁。评审发现以下问题：

1. **7天周期过长**：创业团队节奏快，当事人可能忘记讨论上下文
2. **一票否决过严**：误操作拒绝导致重要信息永久丢失
3. **缺乏分级**：轻微敏感（薪资范围讨论）与高度敏感（离职谈判）处理相同

### 38.2 三级敏感策略

| 级别 | 典型内容 | 授权阈值 | 升级时间 | 默认处理 |
|------|----------|----------|----------|----------|
| **L1 轻微敏感** | 薪资范围讨论、一般绩效反馈 | 任一当事人授权（≥1人） | 3 天 | 脱敏后入库 |
| **L2 中等敏感** | 具体薪资数字、晋升决策 | > 50% 当事人授权 | 5 天 | 等待授权 |
| **L3 高度敏感** | 离职谈判、纪律处分、法律纠纷 | 全部当事人授权 | 7 天 | 严格等待，永不自动处理 |

### 38.3 级别判定（Stage 0 扩展）

Stage 0 敏感检测在确认敏感后，同时输出 `sensitivity_level`：

```
Stage 0 LLM 输出（扩展）：
{
  "is_sensitive": true,
  "sensitive_types": ["hr", "privacy"],
  "sensitivity_level": "L2",
  "sensitive_summary": "涉及具体薪资数字和晋升决策",
  "stakeholder_ids": ["zhangsan", "lisi"]
}
```

判定规则（LLM 依据此规则给出建议，管理员可覆盖）：
- 含具体人员姓名 + 薪资/绩效数字 → L2
- 含法律术语/离职/仲裁/纠纷 → L3
- 仅含薪资范围/级别讨论（无具体数字）→ L1

### 38.4 授权通过条件

```python
def check_authorization_threshold(decisions: dict, threshold: float) -> bool:
    total = len(decisions)
    authorized = sum(1 for d in decisions.values() if d["status"] == "authorize")
    if threshold == 0.0:      # L1：任一授权
        return authorized >= 1
    elif threshold == 0.5:    # L2：多数授权
        return authorized / total > 0.5
    else:                     # L3：全员授权（threshold=1.0）
        return authorized == total
```

### 38.5 L1 智能脱敏示例

L1 级别，任一当事人授权后，平台自动脱敏入库：

```
原文：「李四这次绩效 C，工资调整 -10%，请注意沟通方式」
脱敏：「某员工本次绩效评级较低，薪资有所调整，提醒关注沟通方式」
保留价值：团队了解"近期有绩效调整"，不暴露具体人员和数字
```

### 38.6 DDL 变更

`sensitive_authorizations` 表新增字段（见 §数据库 DDL P1-3 补充）：
- `sensitivity_level VARCHAR(10)`：L1/L2/L3
- `auth_threshold REAL`：授权通过阈值（0.0/0.5/1.0）

`escalation_after` 字段含义变化：
- 原固定 7 天 → 由 sensitivity_level 决定（L1=3天, L2=5天, L3=7天）
- Stage 0 写入时自动设置对应值

---

**END OF DOCUMENT**