# 群聊知识沉淀与 FAQ 智能演进系统 - 产品需求文档 (PRD)

> **文档版本**: v1.2
> **创建日期**: 2026-03-04
> **更新日期**: 2026-03-04
> **作者**: Product Team
> **状态**: 评审中

---

## 1. 文档概述

### 1.1 文档目的

本文档定义"群聊知识沉淀与 FAQ 智能演进系统"的产品需求。该系统是 RippleFlow 知识平台的核心功能模块，通过 nullclaw AI 管家将分散的群聊讨论转化为结构化、可查询、持续演进的知识资产。

### 1.2 范围说明

本文档覆盖：
- 用户侧：本地问答存储、FAQ 浏览、知识搜索
- 服务侧：FAQ 自动生成、文档智能演进、内容审核
- AI 侧：nullclaw 知识挖掘策略、触发机制、自省优化

不在本文档范围内：
- 消息接收与处理流水线（见 `01_system_architecture.md` §3）
- 敏感内容授权机制（见 `01_system_architecture.md` §6）
- AI 管家完整架构（见 `08_ai_butler_architecture.md`）

### 1.3 术语定义

| 术语 | 定义 |
|------|------|
| **nullclaw** | 后台 AI 管家，负责知识挖掘、FAQ 生成与文档演进的所有策略决策 |
| **RippleFlow** | 知识平台（机制层），提供 REST API、数据库、消息管道，不含业务逻辑 |
| **FAQ 文档** | 以 `qa_faq` 类别存储的结构化问答集合，随时间自动演进 |
| **话题线索** | RippleFlow 中一次有意义讨论的聚合单元（`topic_threads` 表） |
| **本地缓存** | 用户客户端存储的个人问答历史，不上传服务器 |
| **知识沉淀** | 将非结构化聊天记录转化为 9 类结构化知识的过程 |
| **内容溯源** | 每条 FAQ 答案关联到原始 `thread_id`，可追溯至聊天记录 |

---

## 2. 需求背景与问题陈述

### 2.1 现状痛点

用户在浏览群聊时频繁遭遇：

1. **上下文缺失**：看到讨论片段缺乏前置背景，无法理解问题本质（如"这个方案用 Raft 还是 Paxos"）
2. **信息过载**：群聊内容庞杂，有价值的技术决策、解决方案被淹没在日常闲聊中
3. **重复提问**：相同问题多次被问，每次都需要有经验的人重新解答，浪费团队精力
4. **知识流失**：离职成员的经验、历史决策的背景、踩坑教训无法沉淀复用
5. **检索困难**：现有搜索返回原始消息片段，缺乏经过提炼的结构化答案

### 2.2 典型场景

> **场景 A（新成员入职）**：新成员加入技术群，看到"换成 Drizzle ORM 了"，不知道为什么换、换之前是什么、踩了什么坑。现在需要在 RippleFlow 搜索"ORM 选型"，立即看到结构化的决策记录和背景。
>
> **场景 B（重复问题）**：群里第 15 次有人问"Redis 连接池怎么配置"，现在 FAQ 文档中已有完整答案，机器人直接引用并附上来源链接。
>
> **场景 C（知识发现）**：nullclaw 发现近一周"内存泄漏"相关讨论激增，自动整理成故障排查指南并推送给相关成员。

### 2.3 与现有功能的关系

RippleFlow 已有的能力（不重复建设）：

| 现有能力 | 已支持 | 本模块扩展点 |
|----------|--------|------------|
| 消息分类（9 类） | ✅ | FAQ 专项深化 `qa_faq` 类 |
| 话题线索聚合 | ✅ | 基于线索生成 FAQ |
| 自然语言问答 | ✅ | 答案来源由原始消息扩展为 FAQ 文档 |
| 当事人修改 | ✅ | 管理员审核 FAQ 内容 |
| AI 管家调度 | ✅ | 新增 FAQ 生成、演进 Routine |

---

## 3. 产品目标

### 3.1 愿景

构建一个**自进化的群聊知识库**：让每一次有价值的讨论自动沉淀为可查询的结构化知识，让团队内任何问题都能在秒级内获得有依据的答案。

### 3.2 核心目标（按优先级）

| 优先级 | 目标 | 衡量方式 |
|--------|------|----------|
| P0 | 重复问题命中率提升 | FAQ 命中率 > 70%（12 周内） |
| P0 | 知识可溯源 | 100% FAQ 答案关联原始 thread |
| P1 | 减少重复解答 | 群聊重复问题减少 > 40% |
| P1 | 用户认可度 | 问答采纳率 > 80% |
| P2 | 自动化程度 | FAQ 更新无需人工干预 > 80% |

### 3.3 设计原则

1. **机制与策略分离**：RippleFlow 提供 FAQ 存储和查询 API，nullclaw 负责何时生成、如何组织
2. **可溯源优先**：每条内容必须可追溯到原始群聊，不生成无根据的内容
3. **人工可介入**：AI 生成的内容均可由管理员审核、修正、驳回
4. **渐进演进**：FAQ 从无到有，从粗到细，不追求一次完美

---

## 4. 功能需求

### 4.1 功能一：本地问答存储与浏览

#### 4.1.1 需求描述

为用户提供个人化的问答历史管理功能。用户在群聊中触发问答后，可将结果保存到本地（客户端存储），支持离线查看和检索。

#### 4.1.2 功能详述

| 功能点 | 优先级 | 需求描述 |
|--------|--------|----------|
| **问答捕获** | P0 | 用户选中消息或话题触发 AI 问答，系统自动将"问题+上下文摘要+AI 答案+来源链接"整理为一条记录 |
| **本地存储** | P0 | 以 JSON 格式存储在用户设备本地（Web: IndexedDB，移动端: SQLite），按群聊、时间、标签分类 |
| **离线浏览** | P0 | 用户可随时查看本地历史问答，无需联网 |
| **关键词搜索** | P1 | 本地全文搜索，支持按群聊、标签、时间范围筛选 |
| **云端同步** | P1 | 可选功能：用户主动开启后同步到服务端个人空间，多设备共享 |
| **导出功能** | P2 | 支持导出为 Markdown / PDF 格式 |

#### 4.1.3 数据结构（本地缓存单条记录）

```json
{
  "id": "local_qa_001",
  "created_at": "2026-03-04T10:30:00Z",
  "source": {
    "group_name": "技术讨论群",
    "thread_id": "thread_abc123",
    "thread_url": "https://rippleflow.internal/threads/abc123"
  },
  "question": "Redis 连接池怎么配置合适的大小？",
  "context_summary": "团队在讨论生产环境 Redis 连接数告警，当前配置为 maxPoolSize=10",
  "answer": "一般建议 maxPoolSize = CPU核心数 × 2，但需结合...",
  "answer_source": "faq",
  "tags": ["redis", "配置", "性能"],
  "saved_by_user": true,
  "synced_to_cloud": false
}
```

#### 4.1.4 用户流程

```
用户在群聊中遇到不理解的内容
    ↓
选中消息 → 点击"解释此内容" / 直接提问
    ↓
系统查询：FAQ 文档中是否有现成答案？
    ├─ 有 → 直接返回 FAQ 答案（标注来源）
    └─ 无 → nullclaw 实时分析上下文 + 生成答案
    ↓
展示答案（含来源链接）+ 提示"保存到我的知识库？"
    ↓
用户确认 → 保存到本地（若开启同步则同步云端）
    ↓
用户可在"我的知识库"中随时离线查看
```

---

### 4.2 功能二：FAQ 文档智能演进系统

#### 4.2.1 需求描述

在服务端构建基于 `qa_faq` 类别的动态 FAQ 文档体系。该文档随着群聊内容的积累自动完善，最终形成覆盖团队核心知识领域的结构化知识库。

#### 4.2.2 FAQ 文档结构设计

每个群聊维护一份 FAQ 文档，结构如下：

```
群聊 FAQ 文档（以群为单位）
├── metadata
│   ├── group_id: "group_tech_001"
│   ├── version: 47
│   ├── last_updated: "2026-03-04T08:00:00Z"
│   └── total_qa_count: 156
│
├── sections（动态章节，由 nullclaw 维护）
│   ├── section_id: "env_config"
│   │   ├── title: "环境配置"
│   │   ├── qa_items: [...]
│   │   └── sub_sections: ["redis", "docker", "nginx"]
│   └── section_id: "arch_decision"
│       ├── title: "架构决策"
│       └── qa_items: [...]
│
└── qa_items（最小单元）
    ├── id: "qa_20260304_001"
    ├── question: "Redis 连接池配置多大合适？"
    ├── answer: "..."
    ├── source_threads: ["thread_abc", "thread_xyz"]
    ├── confidence: 0.92
    ├── review_status: "confirmed"  // pending | confirmed | rejected
    ├── created_at: "2026-03-01"
    └── updated_at: "2026-03-04"
```

#### 4.2.3 文档演进模型

```
触发源：新话题线索分类为 qa_faq / 用户主动查询 / nullclaw 定期批处理
    ↓
nullclaw 分析阶段：
    ├─ 提取问题与答案
    ├─ 计算与现有 FAQ 的相似度
    └─ 判断：新问题？补充答案？修正已有答案？
    ↓
操作决策：
    ├─ 命中现有 FAQ → 补充信息 / 更新置信度
    ├─ 相似问题聚合 → 合并为更通用的问答对
    ├─ 全新话题 → 创建新问题，归入现有或新章节
    └─ 答案与新信息矛盾 → 标记为"待审核"，通知管理员
    ↓
写入 RippleFlow API → 更新 FAQ 存储
    ↓
定期重构（每周）：合并重复、优化章节结构、清理低质量内容
```

#### 4.2.4 功能详述

| 功能点 | 优先级 | 需求描述 |
|--------|--------|----------|
| **FAQ 自动生成** | P0 | nullclaw 分析 `qa_faq` 类话题线索，自动提取问答对，写入 FAQ 文档 |
| **增量更新** | P0 | 新聊天内容触发相关 FAQ 增量更新，旧答案根据新信息修正 |
| **内容溯源** | P0 | 每条答案标注来源 `thread_id` 列表，用户可点击查看原始讨论 |
| **动态章节管理** | P1 | 章节目录非固定，由 nullclaw 根据内容聚类自动维护，相似主题合并 |
| **人工审核** | P1 | 管理员可审核（确认/修正/驳回）AI 生成的 FAQ 条目，设置状态标记 |
| **版本控制** | P1 | 记录每次 FAQ 更新的变更内容、触发原因、操作者（人工/AI），支持回滚 |
| **多维度索引** | P1 | 按主题、热度（被查询次数）、更新时间、审核状态多维度浏览 |
| **关联推荐** | P2 | 查看某 FAQ 条目时，推荐相关上下游知识点 |
| **相似问题聚合** | P2 | 自动识别语义相似的重复问题，合并为标准问答对，保留变体问法 |

#### 4.2.5 文档演进阶段示例

**阶段一：初始（第 1-2 周）**
```
📚 技术群知识库 (FAQ: 12 条)
├── 环境配置 (5)
│   ├── 如何配置 Redis 连接池？
│   └── Docker 镜像拉取失败怎么办？ ...
└── 开发规范 (7)
    └── PR 提交规范是什么？ ...
```

**阶段二：成长（第 1-3 月）**
```
📚 技术群知识库 (FAQ: 89 条)
├── 环境配置 (23)
│   ├── Redis 配置 (8)
│   ├── Docker 相关 (9)
│   └── Nginx 配置 (6)
├── 架构决策 (15)
│   └── ORM 选型：为什么选 SQLAlchemy ...
├── 故障排查 (31)
└── 开发规范 (20)
```

**阶段三：成熟（6 个月+）**
```
📚 技术群知识库 (FAQ: 400+ 条)
├── 新人入职指南
├── 环境配置 (全量)
├── 架构设计与决策
├── 故障排查手册
├── 性能优化
├── 安全规范
├── 最佳实践
└── 常见问题速查
```

---

### 4.3 功能三：nullclaw 主动知识运营

#### 4.3.1 需求描述

nullclaw 不只是被动响应用户查询，还会主动发现、整理和推送有价值的知识，形成知识运营闭环。

#### 4.3.2 主动知识挖掘 Routine

nullclaw 维护以下定期执行的 Routine：

**Routine A：热点话题 FAQ 化**
```
触发：每日 02:00（低峰期）
逻辑：
  1. 查询过去 7 天被搜索 3 次以上但 FAQ 中无答案的话题
  2. 找到对应的 qa_faq 类型话题线索
  3. 生成 FAQ 草稿，status=pending，等待审核
  4. 通知管理员："发现 N 个高频问题待整理为 FAQ"
```

**Routine B：FAQ 质量提升**
```
触发：每周一 09:00
逻辑：
  1. 找出用户反馈"答案不准确"的 FAQ 条目
  2. 查找相关的新话题线索（是否有更新的信息）
  3. 生成修订建议，提交管理员审核
  4. 合并近 7 天新产生的重复问题
```

**Routine C：知识盲区发现**
```
触发：每月 1 日
逻辑：
  1. 分析近一月查询中"无命中"的问题
  2. 聚类，识别知识库缺失的主题领域
  3. 生成"知识盲区报告"推送给管理员
  4. 建议相关话题线索作为内容来源
```

**Routine D：FAQ 推送（主动触达）**
```
触发：检测到某问题被问第 3 次时
逻辑：
  1. FAQ 中是否已有该问题的答案？
     ├─ 有 → 机器人直接回复 FAQ 链接
     └─ 无 → 标记为"高优先级待整理"，当日完成 FAQ 化
```

#### 4.3.3 nullclaw 使用的平台 API

nullclaw 通过以下 RippleFlow API 实现 FAQ 运营（工具调用）：

| 操作 | API | 说明 |
|------|-----|------|
| 查询待处理线索 | `GET /api/v1/threads?category=qa_faq&status=processed` | 获取已处理的问答线索 |
| 搜索相似问题 | `GET /api/v1/search?q=...&category=qa_faq` | 查找相关已有内容 |
| 写入 FAQ 草稿 | `POST /api/v1/faq/items` | 提交新 FAQ 条目（pending 状态） |
| 更新 FAQ 内容 | `PUT /api/v1/faq/items/{id}` | 修订现有答案 |
| 合并 FAQ 条目 | `POST /api/v1/faq/items/merge` | 合并重复问题 |
| 推送知识报告 | `POST /api/v1/butler/notify` | 向管理员发送运营报告 |

---

### 4.4 功能四：FAQ 查询与展示

#### 4.4.1 Web Dashboard 集成

在 RippleFlow Web Dashboard 新增 **FAQ 知识库** 模块：

| 界面元素 | 说明 |
|----------|------|
| 章节目录 | 左侧树形导航，展示动态章节结构 |
| 问答列表 | 右侧展示选中章节的 FAQ 条目 |
| 搜索框 | 全文搜索 FAQ 内容，高亮匹配关键词 |
| 来源链接 | 每条答案底部显示"来源：N 条相关讨论"，点击跳转 |
| 状态标记 | `已确认` / `待审核` / `已过期` 标签 |
| 反馈按钮 | "答案有误" / "有帮助" 用户反馈入口 |
| 管理员视图 | 显示审核队列，支持一键确认/编辑/驳回 |

#### 4.4.2 聊天机器人集成

机器人在群内问答时优先引用 FAQ 内容：

```
用户：@机器人 Redis 连接池怎么配置

机器人：📚 根据知识库 FAQ：

Redis 连接池大小建议设置为 CPU 核心数 × 2，
生产环境建议配置：
  maxPoolSize: 20
  minPoolSize: 5
  idleTimeout: 30000

📎 来源：[3月1日技术群讨论](链接) | [Redis 最佳实践](链接)
❓ 答案有误？ → 回复"反馈"
```

#### 4.4.3 问答接口扩展

现有 `/api/v1/qa` 接口新增 FAQ 优先逻辑：

```
收到问答请求
    ↓
阶段 1：FAQ 精确匹配（向量相似度 > 0.9）
    ├─ 命中 → 直接返回 FAQ 答案（标注 source: faq）
    └─ 未命中 →
阶段 2：FAQ 模糊匹配（0.7 < 相似度 < 0.9）
    ├─ 命中 → 返回 FAQ 答案 + "是否为您要找的问题？"
    └─ 未命中 →
阶段 3：全文检索 + LLM 综合回答（原有逻辑）
    └─ 返回答案 + 标记"该问题暂无 FAQ，是否建议整理？"
```

> **注意**：RippleFlow 不使用语义向量数据库。此处"相似度"由 LLM 直接判断（将问题和 FAQ 条目列表一起送入 LLM 进行相关性评分），而非 embedding 向量检索。

---

## 5. 非功能需求

### 5.1 性能需求

| 指标 | 要求 | 实现方式 |
|------|------|----------|
| FAQ 查询响应 | < 200ms | FAQ 内容缓存到内存，PostgreSQL 全文索引 |
| 问答接口响应 | < 3s（LLM 生成） / < 500ms（FAQ 命中） | FAQ 优先，LLM 兜底 |
| FAQ 增量更新延迟 | < 1 小时（高频问题 < 10 分钟） | nullclaw 事件驱动 + 定时批处理 |
| 本地存储容量 | 默认 100MB，可配置 | IndexedDB / SQLite，支持按时间清理 |
| 并发问答请求 | 50 QPS | 缓存 + 连接池 |

### 5.2 安全与隐私

1. **本地数据隔离**：本地缓存的问答数据默认不上传服务器，用户主动开启云同步后才同步
2. **敏感信息过滤**：FAQ 生成前经过 Stage 0 敏感检测，含密码/Token/个人信息的内容不生成 FAQ
3. **权限控制**：FAQ 文档按群聊维度权限隔离，仅白名单用户可访问对应群的 FAQ
4. **审核前不公开**：默认只有审核通过（`confirmed`）的 FAQ 对普通用户展示；`pending` 仅管理员可见

### 5.3 可用性

1. **离线可用**：本地问答库完全离线可用
2. **降级方案**：FAQ 服务不可用时，自动降级为原有全文检索 + LLM 问答
3. **数据一致性**：FAQ 更新使用乐观锁，避免并发修改冲突
4. **人工覆盖**：任何 AI 生成内容均可被人工内容覆盖，人工优先级高于 AI

### 5.4 可维护性

1. **完整审计日志**：每次 FAQ 变更（创建/修改/合并/驳回）记录操作者、时间、原因
2. **版本回滚**：支持将 FAQ 回滚到任意历史版本
3. **nullclaw 可观测**：知识挖掘 Routine 的执行日志、决策理由均可查询

---

## 6. 技术架构

### 6.1 与 RippleFlow 现有架构的集成

本模块**完全复用**现有 RippleFlow 基础设施，**不引入新的基础组件**：

```
现有架构                      本模块扩展点
─────────────────────         ──────────────────────────────
messages 表                   无变化（输入来源）
topic_threads 表              无变化（qa_faq 类线索为输入）
PostgreSQL 全文索引           FAQ 内容使用同一索引机制
LLM 调用（GLM-4-Plus）       FAQ 生成、相似度判断
nullclaw channels             接收 qa_faq 类线索事件
nullclaw cron                 驱动 Routine A/B/C/D
nullclaw memory               存储 FAQ 运营经验
REST API（FastAPI）           新增 /api/v1/faq/* 端点
```

### 6.2 新增数据表

**`faq_documents`**：FAQ 文档元数据（每群一条）

```sql
CREATE TABLE faq_documents (
    id          TEXT PRIMARY KEY,
    group_id    TEXT NOT NULL UNIQUE,
    version     INTEGER DEFAULT 0,
    qa_count    INTEGER DEFAULT 0,
    updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**`faq_sections`**：FAQ 章节（动态维护）

```sql
CREATE TABLE faq_sections (
    id          TEXT PRIMARY KEY,
    doc_id      TEXT REFERENCES faq_documents(id),
    parent_id   TEXT,                          -- 支持子章节
    title       TEXT NOT NULL,
    sort_order  INTEGER DEFAULT 0,
    created_by  TEXT DEFAULT 'nullclaw',
    updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**`faq_items`**：FAQ 问答条目

```sql
CREATE TABLE faq_items (
    id              TEXT PRIMARY KEY,
    section_id      TEXT REFERENCES faq_sections(id),
    question        TEXT NOT NULL,
    answer          TEXT NOT NULL,
    question_variants TEXT[],                  -- 相似问法
    source_threads  TEXT[],                    -- 关联 thread_id 列表
    confidence      REAL DEFAULT 0.8,          -- AI 置信度
    view_count      INTEGER DEFAULT 0,         -- 被查询次数
    helpful_count   INTEGER DEFAULT 0,         -- 用户反馈"有帮助"
    review_status   TEXT DEFAULT 'pending',    -- pending|confirmed|rejected
    reviewed_by     TEXT,
    reviewed_at     TIMESTAMP,
    created_by      TEXT DEFAULT 'nullclaw',
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_faq_items_section ON faq_items(section_id);
CREATE INDEX idx_faq_items_status ON faq_items(review_status);
```

**`faq_versions`**：变更历史

```sql
CREATE TABLE faq_versions (
    id          TEXT PRIMARY KEY,
    item_id     TEXT REFERENCES faq_items(id),
    version     INTEGER NOT NULL,
    question    TEXT,
    answer      TEXT,
    change_type TEXT,   -- created|updated|merged|reviewed
    change_by   TEXT,
    change_reason TEXT,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 6.3 新增 API 端点（概览）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/faq/{group_id}` | 获取群 FAQ 文档结构 |
| GET | `/api/v1/faq/{group_id}/items` | 分页获取 FAQ 条目 |
| GET | `/api/v1/faq/{group_id}/search` | FAQ 全文搜索 |
| POST | `/api/v1/faq/items` | 创建 FAQ 条目（nullclaw 调用） |
| PUT | `/api/v1/faq/items/{id}` | 更新 FAQ 条目 |
| POST | `/api/v1/faq/items/{id}/review` | 审核 FAQ 条目（管理员） |
| POST | `/api/v1/faq/items/merge` | 合并重复条目 |
| GET | `/api/v1/faq/items/{id}/versions` | 查看变更历史 |
| POST | `/api/v1/faq/items/{id}/feedback` | 用户反馈 |

### 6.4 系统数据流

```
群聊消息
    ↓
RippleFlow 消息处理流水线（Stage 0–5）
    ↓
分类为 qa_faq 的话题线索
    ↓ HTTP POST（事件推送）
nullclaw channels（接收事件）
    ↓
nullclaw 决策：
    ├─ 实时处理：高频/紧急问题 → 立即生成 FAQ 草稿
    └─ 批处理：Routine A/B 定时执行
    ↓
调用 POST /api/v1/faq/items
    ↓
FAQ 存储（PostgreSQL faq_items 表）
    ↓
管理员审核（Web Dashboard）
    ↓
状态更新为 confirmed → 对用户可见
    ↓
用户查询时：GET /api/v1/faq/{group_id}/search 优先命中
```

---

## 7. 里程碑规划

### 阶段一：MVP — FAQ 基础存储（第 1–3 周）

**目标**：nullclaw 能生成 FAQ，用户能查看

- [ ] 新增 `faq_documents`、`faq_sections`、`faq_items` 数据表（DDL）
- [ ] 实现 `POST /api/v1/faq/items` 接口（nullclaw 写入）
- [ ] 实现 `GET /api/v1/faq/{group_id}` 接口（结构查询）
- [ ] nullclaw 编写 Routine A（热点话题 FAQ 化），接入 channels 事件
- [ ] Web Dashboard 新增 FAQ 基础展示页（只读）

**验收标准**：部署 2 周后，技术群产生 > 20 条 FAQ 草稿

---

### 阶段二：核心功能 — 审核与搜索（第 4–7 周）

**目标**：FAQ 可被查询命中，管理员可审核

- [ ] 实现 `POST /api/v1/faq/items/{id}/review` 审核接口
- [ ] FAQ 全文搜索接口 `GET /api/v1/faq/{group_id}/search`
- [ ] `/api/v1/qa` 问答接口集成 FAQ 优先逻辑
- [ ] 聊天机器人问答引用 FAQ 来源
- [ ] Web Dashboard 管理员审核队列界面
- [ ] `faq_versions` 版本记录

**验收标准**：问答请求中 FAQ 命中率 > 40%，管理员审核耗时 < 1 分钟/条

---

### 阶段三：智能化 — 自动演进（第 8–12 周）

**目标**：FAQ 质量自动提升，减少人工干预

- [ ] nullclaw Routine B（FAQ 质量提升）上线
- [ ] nullclaw Routine C（知识盲区发现）上线
- [ ] FAQ 章节动态管理（nullclaw 自动维护章节结构）
- [ ] 相似问题自动聚合（`POST /api/v1/faq/items/merge`）
- [ ] 用户反馈机制（"有帮助" / "答案有误"）
- [ ] 本地问答缓存功能（Web 端 IndexedDB）

**验收标准**：FAQ 自动化更新占比 > 60%，重复问题减少 > 30%

---

### 阶段四：完善 — 精细化运营（持续迭代）

- [ ] nullclaw Routine D（重复问题实时拦截）
- [ ] 多维度 FAQ 索引与推荐
- [ ] 本地缓存云端同步
- [ ] FAQ 数据分析仪表盘
- [ ] 关联知识点推荐

---

## 8. 成功指标 (KPI)

### 8.1 用户侧指标（12 周目标）

| 指标 | 目标值 | 测量方式 |
|------|--------|----------|
| 问答 FAQ 命中率 | > 70% | 问答请求中返回 FAQ 答案的比例 |
| 用户认可率 | > 80% | "有帮助"反馈 / 总反馈数 |
| 重复问题减少 | > 40% | 对比引入前同类问题月频次 |
| FAQ 本地保存率 | > 50% | 触发问答后选择保存的比例 |

### 8.2 内容质量指标

| 指标 | 目标值 | 测量方式 |
|------|--------|----------|
| FAQ 准确率 | > 90% | 管理员确认通过的比例 |
| FAQ 覆盖增长 | 每周 +10 条有效 FAQ | 审核通过的新增条目数 |
| 平均审核时延 | < 24 小时 | 从 pending 到 confirmed 的时间 |
| 自动化更新率 | > 60% | 无需人工介入的更新比例 |

### 8.3 系统侧指标

| 指标 | 目标值 |
|------|--------|
| FAQ 查询 P99 延迟 | < 500ms |
| nullclaw Routine 执行成功率 | > 99% |
| FAQ 更新延迟（高频问题） | < 10 分钟 |

---

## 9. 风险与应对

| 风险 | 概率 | 影响 | 应对措施 |
|------|------|------|----------|
| AI 生成内容不准确 | 中 | 高 | 默认 pending 状态，人工审核后才对外展示；用户反馈机制快速发现问题 |
| FAQ 内容过时（信息已变更） | 高 | 中 | Routine B 定期检查，关联 thread 更新时标记 FAQ 为"待复核" |
| 敏感信息泄露进入 FAQ | 低 | 高 | Stage 0 敏感检测强制执行，FAQ 生成前再次过滤 |
| 章节结构混乱 | 中 | 低 | 章节合并规则保守，人工可随时调整结构 |
| nullclaw 生成频率过高 | 低 | 中 | Routine 执行频率限制，API 调用频率限制（rate limit） |
| 用户对 AI 内容信任度低 | 中 | 中 | 所有 AI 内容标注"AI 生成"标签，经管理员确认后去除标签 |

---

## 10. 附录

### 10.1 与现有信息分类体系的对应

本模块重点处理 `qa_faq` 类别，同时可从其他类别提炼 FAQ：

| 信息类别 | FAQ 关联方式 |
|----------|------------|
| `qa_faq` | 主要来源，直接转化 |
| `bug_incident` | 故障排查类 FAQ（"如何解决 XX 报错"） |
| `tech_decision` | 架构决策类 FAQ（"为什么选择 XX 方案"） |
| `env_config` | 配置类 FAQ（"如何配置 XX"） |
| `knowledge_share` | 知识科普类 FAQ（"XX 是什么"） |
| `reference_data` | 不生成 FAQ（数据类，直接查询） |
| `action_item` | 不生成 FAQ（任务类，非问答场景） |

### 10.2 参考文档

| 文档 | 说明 |
|------|------|
| `docs/00_overview.md` | 系统总览、信息分类体系 |
| `docs/01_system_architecture.md` | 消息流水线、nullclaw 集成架构 |
| `docs/03_api_reference.yaml` | 完整 API 规范（FAQ 接口待补充） |
| `docs/06_llm_prompt_templates.md` | FAQ 生成相关 Prompt 模板（待补充） |
| `docs/08_ai_butler_architecture.md` | nullclaw Routine 开发规范 |

### 10.3 修订历史

| 版本 | 日期 | 修改内容 | 作者 |
|------|------|----------|------|
| v1.0 | 2026-03-04 | 初始版本 | Product Team |
| v1.1 | 2026-03-04 | 补充技术架构细节，修正向量检索误用，增加 nullclaw Routine 设计 | Claude |
| v1.2 | 2026-03-04 | 增加数据表设计、API 概览、KPI 细化、风险矩阵、信息类别对应关系 | Claude |

---

**文档结束**

---

*本 PRD 定义了群聊知识沉淀系统的完整需求。所有功能均基于 RippleFlow 现有基础设施扩展，不引入新的基础组件。nullclaw 负责全部 AI 策略，RippleFlow 提供数据存储与 API 接口。*
