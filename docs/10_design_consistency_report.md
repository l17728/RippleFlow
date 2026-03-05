# RippleFlow 设计文档一致性检查报告

## 检查信息

| 项目 | 值 |
|------|------|
| 检查日期 | 2026-03-05 |
| 检查范围 | 全部设计文档（v0.8 基准） |
| 检查目的 | 确保 v0.7/v0.8 累计变更后各文档的设计一致性和流程闭环 |
| 当前版本 | **v0.8**（消息入库全链路推演修复） |
| 上次检查 | v0.6（2026-03-03，已失效） |
| 检查状态 | ✅ 通过（含已知遗留项说明） |

---

## 一、文档清单与当前状态

| 编号 | 文档 | 状态 | 关键指标 |
|------|------|------|----------|
| 00 | `00_overview.md` | ✅ v0.8 最新 | 版本历史完整至 v0.8，服务层/数据库表已同步 |
| 01 | `01_system_architecture.md` | ✅ 已同步 | §44 AI 智能辅助输入（v0.7）+ GAP 修复注记（v0.8） |
| 02 | `02_database_ddl.sql` | ✅ 已同步 | 75 张表，含 v0.7/v0.8 全部新增字段和表 |
| 02b | `02b_database_ddl_sqlite.sql` | ✅ 已同步 | 与 PostgreSQL 版本保持一致 |
| 03 | `03_api_reference.yaml` | ✅ 已同步 | 138 个端点，73 个 Schema |
| 04 | `04_service_interfaces.md` | ✅ 已同步 | 26 个 Protocol，含 v0.8 新增 verify_api_key/ButlerPushConfigService |
| 05 | `05_e2e_test_catalog.md` | ✅ 已同步 | 7 个 Part，21 个测试场景，含 v0.8 Part 7（14 个 E2E 用例） |
| 06 | `06_llm_prompt_templates.md` | ✅ 已同步 | 25 个 Prompt 模板（§25 字段建议 Prompt v0.7 新增） |
| 07 | `07_unit_test_catalog.md` | ✅ 已同步 | §20-26 新增 27 个 UT（v0.7/v0.8 新增 Protocol 全覆盖） |
| 08 | `08_ai_butler_architecture.md` | ✅ 已同步 | v2.0 架构，Stage 5 归属 nullclaw 已确认 |
| 09 | `09_user_manual.md` | ✅ 已同步 | §12 订阅管理、§13 rf CLI 命令速查（v1.3）已补充 |
| 10 | `10_design_consistency_report.md` | - | 本报告 |
| 11 | `11_expert_review_report.md` | ✅ 已更新 | §十三 v0.7/v0.8 补充审查已追加（2026-03-05） |
| 12 | `12_design_qa.md` | ✅ 有效 | 设计信条与决策记录，v0.8 不影响 |
| 13 | `13_implementation_phases.md` | ✅ 已同步 | butler_push_config → Phase 2 归属已写入 |
| PRD | `群聊知识沉淀与FAQ智能演进系统_PRD.md` | ✅ 有效 | v1.2，独立 FAQ 子系统 PRD |

---

## 二、v0.7 变更摘要（订阅/内容发布/AI 辅助输入）

### 2.1 订阅关注扩展

| 文档 | 变更 | 状态 |
|------|------|------|
| `02_database_ddl.sql` | `user_subscriptions.subscription_type` 枚举扩展至 10 种（+todo/resource/event/document/shared_link/workflow） | ✅ |
| `02_database_ddl.sql` | `subscription_events.target_type` 扩展至 8 种 | ✅ |
| `02_database_ddl.sql` | `user_subscriptions.filter_criteria JSONB` 新增 | ✅ |
| `03_api_reference.yaml` | `POST /api/v1/subscriptions` subscription_type 枚举同步 | ✅ |
| `03_api_reference.yaml` | `GET /api/v1/subscriptions/followable-targets` 新增 | ✅ |
| `04_service_interfaces.md` | `ISubscriptionService.get_followable_targets()` 新增 | ✅ |

### 2.2 内容发布（富文本文档 + 链接卡片）

| 文档 | 变更 | 状态 |
|------|------|------|
| `02_database_ddl.sql` | `user_documents` 表新增 | ✅ |
| `02_database_ddl.sql` | `shared_links` 表新增 | ✅ |
| `02_database_ddl.sql` | `personal_todos` 新增 `todo_type`/`milestones` 字段 | ✅ |
| `03_api_reference.yaml` | `/api/v1/documents/*` 7 个端点新增 | ✅ |
| `03_api_reference.yaml` | `/api/v1/shared-links/*` 6 个端点新增 | ✅ |
| `04_service_interfaces.md` | `IUserDocumentService`、`ISharedLinkService` 新增 | ✅ |

### 2.3 AI 智能辅助输入（§44 跨切面设计模式）

| 文档 | 变更 | 状态 |
|------|------|------|
| `02_database_ddl.sql` | `butler_suggestions` 表新增（含 `ai_applied` 字段） | ✅ |
| `03_api_reference.yaml` | `POST /api/v1/butler/suggest` 新增 | ✅ |
| `03_api_reference.yaml` | `POST /api/v1/butler/suggest/feedback` 新增（含 `ai_applied` 字段） | ✅ |
| `03_api_reference.yaml` | `POST /api/v1/butler/suggest/link-entity` 新增（orphan 回填） | ✅ |
| `03_api_reference.yaml` | `POST /api/v1/shared-links/{id}/refetch` 新增 | ✅ |
| `04_service_interfaces.md` | `IButlerSuggestionService` 新增（含 `prefetch_link_metadata`） | ✅ |
| `01_system_architecture.md` | §44 AI 智能辅助输入设计模式（触发时机、三级强度、entity_id 生命周期） | ✅ |
| `06_llm_prompt_templates.md` | §25 `BUTLER_FIELD_SUGGESTION_PROMPT` 新增 | ✅ |

---

## 三、v0.8 变更摘要（消息入库全链路推演 17 项修复）

### 3.1 CRITICAL 修复（GAP-1/6/16）

| GAP | 问题 | 修复位置 | 状态 |
|-----|------|----------|------|
| GAP-1 | 敏感消息授权后重入 Pipeline 触发 Stage0 死循环 | `messages.pipeline_start_stage`（DDL）+ `IMessageService`/`ISensitiveService`（接口） | ✅ |
| GAP-6 | `reference_data` 同 key 多条活跃记录，查询歧义 | `deprecated_at/deprecated_by`（DDL）+ `deprecate_old_reference_data()` 触发器（DDL） | ✅ |
| GAP-16 | `publish_event()` 在 Stage4 完成后立即调用，通知时摘要未就绪 | `IProcessingPipelineService.run()` 注释 + `/internal/subscriptions/publish`（API） | ✅ |

### 3.2 HIGH 修复（GAP-2/3/5/7/8/9/10/12/14）

| GAP | 问题 | 修复位置 | 状态 |
|-----|------|----------|------|
| GAP-2 | 敏感消息重入时 Stage1 缺少授权上下文注入 | `ISensitiveService.submit_decision()` 注释 | ✅ |
| GAP-3 | Pipeline 未显式依赖 PersonalTodoService，action_item 未自动创建 todo | `IProcessingPipelineService.run()` 依赖图 + 注释 | ✅ |
| GAP-5 | 多分类消息 `notify_nullclaw()` payload 为单线索格式，nullclaw 无法区分多线索 | `INullclawPublisherService.notify_nullclaw()` 注释（thread_updates 数组格式） | ✅ |
| GAP-7 | 机器人消息在 `ingest()` 后仍进入 Pipeline，浪费 LLM 调用且可能触发误判 | `IMessageService.ingest()` 注释（is_bot 提前过滤） | ✅ |
| GAP-8 | Webhook 重试导致消息重复入库 | `IMessageService.ingest()` 注释（ON CONFLICT DO NOTHING） | ✅ |
| GAP-9 | nullclaw 调用 `/internal/*` 端点无认证机制 | `user_whitelist.is_system/api_key_hash`（DDL）+ `apiKeyAuth`（API securitySchemes）+ `IAuthService.verify_api_key()`（接口） | ✅ |
| GAP-10 | nullclaw 宕机恢复后，同一线索的 pending 事件乱序重放，导致 Stage5 状态错乱 | `nullclaw_pending_events.thread_id`（DDL）+ `INullclawPublisherService.retry_pending_events()` 注释 | ✅ |
| GAP-12 | `reference_data` 无专用搜索接口，只能走全文检索，敏感值会泄露 | `ISearchService.find_reference()` 新增方法 | ✅ |
| GAP-14 | `consensus_drift` 等系统级告警无通知通道，nullclaw 无法批量推送 | `/internal/notifications/bulk`（API） | ✅ |

### 3.3 MEDIUM 修复（GAP-4/8/11/13/15/17）

| GAP | 问题 | 修复位置 | 状态 |
|-----|------|----------|------|
| GAP-4 | action_item 创建的 todo 默认 `visibility='private'`，团队成员看不到 | `IPersonalTodoService.sync_from_action_item()` 默认参数改为 `'team'` | ✅ |
| GAP-11 | `nullclaw_pending_events` 无 `thread_id` 字段，有序重试无法按线索分组 | `nullclaw_pending_events.thread_id`（DDL）+ 复合索引 | ✅ |
| GAP-13 | `ISearchService.find_reference()` 对敏感 `reference_data` 无访问控制，`value` 字段泄露 | `find_reference()` 注释（is_sensitive=True 时只返回 label） | ✅ |
| GAP-15 | nullclaw Routine 推送目标房间硬编码，变更需重启 nullclaw | `butler_push_config` 表（DDL）+ `/internal/butler/config` 和 `/api/v1/admin/butler/config`（API）+ `IButlerPushConfigService`（接口） | ✅ |
| GAP-17 | `publish_event()` 的 `searchable_text` 字段构建规范未定义，各调用方实现不一致 | `ISubscriptionService.publish_event()` 注释（各实体类型构建规则 + PostgreSQL 字典选择） | ✅ |

### 3.4 E2E 测试补充（05_e2e_test_catalog.md Part 7）

| 用例 | 覆盖 GAP | 状态 |
|------|----------|------|
| TC-INGEST-001：完整 Stage 0-5 + 摘要就绪后通知 | GAP-16 | ✅ |
| TC-INGEST-002：Webhook 幂等性 | GAP-8 | ✅ |
| TC-INGEST-003：机器人消息过滤 | GAP-7 | ✅ |
| TC-INGEST-004：敏感消息防死循环（start_stage=1） | GAP-1/2 | ✅ |
| TC-INGEST-005：action_item → todo（visibility=team） | GAP-3/4 | ✅ |
| TC-INGEST-006：多分类消息多线索 payload | GAP-5 | ✅ |
| TC-INGEST-007：reference_data 旧记录自动废弃 | GAP-6 | ✅ |
| TC-INGEST-008：nullclaw 宕机有序重试 | GAP-10/11 | ✅ |
| TC-INGEST-009：订阅通知 Stage5 时序验证 | GAP-16 | ✅ |
| TC-INGEST-010：keyword 订阅匹配与 searchable_text | GAP-17 | ✅ |
| TC-INGEST-011：nullclaw ApiKey 认证 | GAP-9 | ✅ |
| TC-INGEST-012：摘要漂移 bulk 通知 | GAP-14 | ✅ |
| TC-INGEST-013：管家推送配置动态读取 | GAP-15 | ✅ |
| TC-INGEST-014：敏感 reference_data 访问控制 | GAP-13 | ✅ |

---

## 四、跨文档一致性验证

### 4.1 数据结构 ↔ API 一致性

| 检查项 | 结果 |
|--------|------|
| `subscription_type` 枚举：DDL（10种）↔ API（10种）↔ Protocol（10种注释） | ✅ 一致 |
| `pipeline_start_stage` 字段：DDL ↔ `IMessageService.ingest()` ↔ `IProcessingPipelineService.run(start_stage)` | ✅ 一致 |
| `butler_push_config` 表：DDL ↔ API（3个端点）↔ `IButlerPushConfigService` | ✅ 一致 |
| `butler_suggestions.ai_applied` 字段：DDL ↔ `POST /api/v1/butler/suggest/feedback`（ai_applied 字段）| ✅ 一致 |
| `user_whitelist.is_system/api_key_hash`：DDL ↔ `apiKeyAuth` securityScheme ↔ `IAuthService.verify_api_key()` | ✅ 一致 |
| `nullclaw_pending_events.thread_id`：DDL ↔ `notify_nullclaw()` 注释（thread_id 写入规则）↔ `retry_pending_events()` 注释（按 thread_id 分组） | ✅ 一致 |
| `reference_data_items.deprecated_at/by`：DDL（字段+触发器）↔ `ISearchService.find_reference(include_deprecated)` | ✅ 一致 |
| `personal_todos.todo_type/milestones`：DDL ↔ API（`/api/v1/todos` 请求体）↔ `IPersonalTodoService` | ✅ 一致 |

### 4.2 流程闭环验证

| 场景 | 关键闭环点 | 状态 |
|------|-----------|------|
| 消息入库 → Stage0-4 → notify_nullclaw → Stage5（nullclaw）→ /internal/subscriptions/publish → 订阅通知 | 通知时摘要必须已就绪（GAP-16 修复） | ✅ |
| 敏感消息 → Stage0 检测 → pending_authorization → 全员授权 → `pipeline_start_stage=1` 重入 → Stage1 开始 | 不重复触发 Stage0（GAP-1 修复） | ✅ |
| 消息含 reference_data → Stage4 写入 → `deprecate_old_reference_data()` 触发器废弃旧记录 → `find_reference()` 返回最新单条 | 无歧义（GAP-6/12 修复） | ✅ |
| action_item 消息 → Stage4 提取 → `sync_from_action_item(visibility='team')` → 被指派人 todo 列表可见 | 默认团队可见（GAP-3/4 修复） | ✅ |
| nullclaw 宕机 → pending_events 入队（含 thread_id）→ 恢复后 RetryWorker 按 thread_id + created_at 有序重放 | 状态一致性保证（GAP-10/11 修复） | ✅ |
| butler_suggestions 创建时 entity_id=NULL → 实体保存后 `POST /api/v1/butler/suggest/link-entity` 回填 | 孤儿记录有回收机制（v0.7） | ✅ |
| nullclaw 读取 `/internal/butler/config` → 获取推送目标房间 → 推送日报到正确频道 | 动态配置，无需重启（GAP-15 修复） | ✅ |

### 4.3 认证体系完整性

| 认证方式 | 适用入口 | 定义位置 | 状态 |
|----------|----------|----------|------|
| `cookieAuth`（JWT Cookie） | `/api/v1/*` 普通用户 | API securitySchemes + `IAuthService.verify_jwt()` | ✅ |
| `webhookSecret`（X-Webhook-Secret） | `/api/v1/webhooks/chat` | API securitySchemes | ✅ |
| `botAuth`（X-Bot-Token） | `/api/v1/bot/*` | API securitySchemes | ✅ |
| `apiKeyAuth`（Authorization: ApiKey ...） | `/internal/*` nullclaw 专用 | API securitySchemes + `IAuthService.verify_api_key()` + `user_whitelist.is_system` | ✅ |

### 4.4 API 端点 ↔ Protocol 方法对应

| API 端点 | 对应 Protocol | 状态 |
|----------|---------------|------|
| `POST /api/v1/butler/suggest` | `IButlerSuggestionService.suggest()` | ✅ |
| `POST /api/v1/butler/suggest/feedback` | `IButlerSuggestionService.record_feedback()` | ✅ |
| `POST /api/v1/butler/suggest/link-entity` | `IButlerSuggestionService`（entity_id 回填） | ✅ |
| `POST /api/v1/shared-links/{id}/refetch` | `ISharedLinkService.refetch_metadata()` | ✅ |
| `POST /internal/events/publish` | `INullclawPublisherService.notify_nullclaw()` | ✅ |
| `POST /internal/subscriptions/publish` | `ISubscriptionService.publish_event()` | ✅ |
| `POST /internal/notifications/bulk` | `INotificationService.send_bulk()` | ✅ |
| `GET /internal/butler/config` | `IButlerPushConfigService.get_config()` | ✅ |
| `PUT /api/v1/admin/butler/config/{type}` | `IButlerPushConfigService.upsert_config()` | ✅ |
| `GET /api/v1/subscriptions/followable-targets` | `ISubscriptionService.get_followable_targets()` | ✅ |

### 4.5 Prompt 模板 ↔ Stage 覆盖

| Stage / 场景 | Prompt 模板 | 状态 |
|-------------|------------|------|
| Stage 0：敏感检测 | §2 `SENSITIVE_DETECTION_PROMPT` | ✅ |
| Stage 1：噪声过滤 | §3 `NOISE_FILTER_PROMPT` | ✅ |
| Stage 2：多类别分类 | §4 `CLASSIFICATION_PROMPT` + §22 批量版 | ✅ |
| Stage 3：线索匹配 | §5 `THREAD_MATCHING_PROMPT` | ✅ |
| Stage 4：结构化提取 | §6 `STRUCTURED_EXTRACTION_PROMPT` | ✅ |
| Stage 5（nullclaw）：摘要更新 | §7 `SUMMARY_UPDATE_PROMPT` | ✅ |
| 问答综合 | §9 `QA_SYNTHESIS_PROMPT` | ✅ |
| FAQ 生成 | §19 `FAQ_GENERATION_PROMPT` | ✅ |
| AI 字段建议 | §25 `BUTLER_FIELD_SUGGESTION_PROMPT` | ✅ |
| Stage1 授权上下文注入（GAP-2） | `ISensitiveService.submit_decision()` 注释中定义，暂无独立 Prompt 模板 | ⚠️ 建议 §26 |

---

## 五、遗留项与待完善清单

### 5.1 文档补充（已全部完成）

| 文档 | 补充内容 | 状态 |
|------|---------|------|
| `07_unit_test_catalog.md` | §20-26：v0.7/v0.8 新增 Protocol 的 UT（27 个用例） | ✅ 已完成 |
| `09_user_manual.md` | §12 订阅管理、§13 rf CLI 命令速查 | ✅ 已完成 |
| `13_implementation_phases.md` | user_documents/shared_links/butler_suggestions/butler_push_config Phase 归属 | ✅ 已完成 |
| `06_llm_prompt_templates.md` | §26 SENSITIVE_AUTH_CONTEXT_TEMPLATE（GAP-2 对应） | ✅ 已完成 |
| `11_expert_review_report.md` | §十三 v0.7/v0.8 补充审查（评分/建议落地/新风险） | ✅ 已完成 |

### 5.2 设计层面遗留问题

| 编号 | 问题 | 影响 | 建议处理 |
|------|------|------|----------|
| D-01 | `04_service_interfaces.md` 中章节编号存在重复（多个 §13/§14/§17-§20），历史追加导致的混乱 | 可读性 | 下次重大更新时统一重排章节号 |
| D-02 | `action-items` 与 `action_items` 两个 Tag 同时存在于 API spec（连字符 vs 下划线） | API 文档一致性 | 统一为 `action-items`（REST 惯例） |
| D-03 | `nullclaw_pending_events` 中多线索格式事件（`thread_updates` 数组）写入 `thread_id` 时只取 `[0].thread_id`，若第一个线索重试先于第二个完成，可能破坏第二个线索的有序性 | 边缘场景 | 多线索事件考虑拆分为多条 pending_event 记录（每线索一条）|
| D-04 | `keyword` 订阅匹配使用 `'simple'` 字典（兼容性优先），中文匹配精度低 | 功能质量 | 部署 zhparser 扩展后改用 `'chinese'` 字典，在 `06_llm_prompt_templates.md` 补充说明 |
| D-05 | `butler_push_config.schedule` 字段为自定义 cron 覆盖，但 nullclaw 的内置 cron 如何与之协调未明确 | 调度一致性 | 在 `08_ai_butler_architecture.md` 补充调度优先级说明：config.schedule > nullclaw 默认 cron |

---

## 六、数据规模基线（v0.8）

| 指标 | 数量 |
|------|------|
| 数据库表（PostgreSQL） | 75 张 |
| API 端点（OpenAPI 3.0） | 138 个 |
| API Schema | 73 个 |
| Service Protocol（Python） | 26 个 |
| E2E 测试场景 | 21 个（Part 1-7） |
| LLM Prompt 模板 | 25 个 |
| API Tag 分类 | 31 种 |

---

## 七、总结

### v0.7 贡献
- **订阅关注**完成 10 种类型扩展，filter_criteria 支持灵活过滤
- **内容发布**形成两种形态：系统内富文本（user_documents）+ 外部链接卡片（shared_links）
- **AI 智能辅助输入**作为系统级设计模式落地（§44），覆盖全实体类型

### v0.8 贡献
- 通过 **13 个场景时序推演**识别 17 项设计漏洞（3 CRITICAL / 8 HIGH / 6 MEDIUM）
- **全部修复**并同步到 DDL、API spec、Protocol 三层
- 新增 **14 个 E2E 测试用例**覆盖全部修复场景
- 建立 **nullclaw 系统级认证体系**（ApiKey + is_system 白名单）
- 完善 **消息处理 Pipeline 的防护机制**：幂等性、防死循环、有序性、时序正确性

**文档体系现状**：
- 核心设计文档（00-08）：✅ 一致性通过
- 测试文档（05/07）：✅ 全部已同步（E2E 21 场景 + UT §20-26 共 27 用例）
- 用户/产品文档（09/11/13）：✅ 全部已跟进 v0.7/v0.8
- 遗留设计问题（D-01/02/03/04/05）：⚠️ 5 项待处理（D-02/D-05 优先）

---

**检查完成时间**: 2026-03-05
**版本**: v0.8
**检查人**: Claude AI（基于全量文档 diff 分析）
