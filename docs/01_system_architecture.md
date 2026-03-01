# 01 系统架构设计文档

## 1. 技术栈

| 层次 | 技术选型 | 版本 | 说明 |
|------|----------|------|------|
| Web 框架 | FastAPI | ≥ 0.111 | 异步，自动生成 OpenAPI 文档 |
| 任务队列 | Celery + Redis | Celery 5.x | 异步处理消息流水线 |
| 数据库 | PostgreSQL | ≥ 15 | 含 pg_trgm 全文检索扩展 |
| 缓存 | Redis | ≥ 7.0 | 会话、搜索结果、热点数据 |
| LLM | 公司内部部署 | — | 全中文场景优化，无 API 调用成本 |
| 部署 | Docker Compose | — | 开发/生产一致环境 |
| 认证 | python-ldap3 + JWT | — | LDAP 鉴权 + 无状态 Token |
| 前端 | Vue 3 + TypeScript | — | Web Dashboard |
| E2E 测试 | Playwright | ≥ 1.44 | 自动化 UI 测试 |

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
│  Service Layer      │  │  Redis           │  │  LLM API             │
│                     │  │                  │  │                      │
│  MessageService     │  │  - Celery 队列    │  │  (公司内部部署)       │
│  ThreadService      │  │  - 会话 Token     │  │                      │
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
│  Celery Workers (独立进程)                                            │
│                                                                     │
│  ProcessingPipeline      消息 6 阶段处理（Stage 0–5）                │
│  SummaryUpdateWorker     增量摘要更新                                │
│  NotificationWorker      App 内通知推送                              │
│  ReminderScheduler       敏感授权每日提醒（Celery Beat）              │
│  SyncToChatWorker        修改结果同步至聊天群（用户确认后）            │
│  EscalationWorker        敏感授权超时升级（新增）                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. 消息处理流水线（6 Stages）

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
│  Stage 5: 增量摘要更新                                           │
│                                                                 │
│  输入：现有摘要 + 新消息                                          │
│  LLM 输出：更新摘要 + 状态变化 + 是否漂移                         │
│  旧摘要存 thread_summary_history                                │
│  漂移检测：追加说明（Append-Only），通知原决策当事人              │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
                      存储完成，可检索
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
        ├── 创建 sensitive_authorizations 记录
        ├── decisions = {每位当事人: "pending"}
        ├── escalation_after = 7 days  ← 新增
        └── 异步推送 App 内通知给每位当事人
                  │
              当事人操作
         ┌────────┼────────┐
         ▼        ▼        ▼
      拒绝      授权     脱敏后授权
         │        │        │
         ▼        ▼        ▼
    立即拒绝   更新decisions  保存脱敏版本
    永不处理   检查是否全部授权  待全部确认
                  │
              全部明确授权
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
│  1. 通知管理员：「以下敏感授权已超过 7 天未处理，请介入」          │
│  2. 通知当事人：「授权请求即将升级至管理员处理」                   │
│  3. 记录 escalated_at、escalated_to                             │
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
  db:         # PostgreSQL 15
  redis:      # Redis 7
  api:        # FastAPI（uvicorn，多进程）
  worker:     # Celery Worker（消息处理流水线）
  beat:       # Celery Beat（定时提醒任务）
  frontend:   # Vue 3 静态文件（Nginx）
```

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

### 10.2 内部服务接口（Python Protocol）

见 `04_service_interfaces.md`

### 10.3 前端 REST API

见 `03_api_reference.yaml`（OpenAPI 3.0）

---

## 11. AI 管家数据流

AI 管家是 RippleFlow 的"运营大脑"，负责主动推送和知识库健康维护。

### 11.1 每周知识快报流程

```
Celery Beat (每周一 9:00)
        │
        ▼
AIButlerService.generate_weekly_digest()
        │
        ├── 1. 统计上周数据
        │       ├── 新增话题线索数量（按类别）
        │       ├── 热门讨论 Top 5（按消息数）
        │       ├── 新增技术决策
        │       └── 即将到期待办
        │
        ├── 2. LLM 生成快报文案
        │       输入：统计数据
        │       输出：结构化快报内容
        │
        ├── 3. 推送到主群
        │       调用 ChatToolService.send_card_reply()
        │       格式：卡片消息
        │
        └── 4. 记录推送历史
                写入 butler_tasks 表
```

### 11.2 待办到期提醒流程

```
Celery Beat (每日 9:00)
        │
        ▼
AIButlerService.check_action_items_due()
        │
        ├── 1. 查询即将到期待办
        │       WHERE due_date IN (NOW, NOW + 1 day)
        │       AND status != 'done'
        │
        ├── 2. 按被分配者分组
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

## 12. AI 管家主动服务清单

| 服务名称 | 触发条件 | 推送渠道 | 频率 |
|----------|----------|----------|------|
| 每周知识快报 | 定时（周一 9:00） | 主群推送 | 每周 |
| 待办到期提醒 | due_date - 1 天 | 群聊@提醒 | 每日检查 |
| 敏感授权状态更新 | 授权状态变化 | App 通知 + 群聊 | 实时 |
| 问答反馈请求 | 问答完成后 | Dashboard 提示 | 实时 |
| 知识库健康报告 | 每月 1 日 | Dashboard + 管理员 | 每月 |
| 孤儿线索检测 | 线索无关联消息 | 管理员通知 | 每周 |
| 摘要质量预警 | AI 置信度 < 0.6 | 当事人通知 | 实时 |