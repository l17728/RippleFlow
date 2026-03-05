# RippleFlow 分阶段实施路线

> **背景**：RippleFlow 系统设计完整，按完整规模（75 张表、138 个 API 端点、26 个 Protocol）
> 分阶段实施以控制交付风险，确保每个阶段都能独立运行、产生价值。
>
> **团队配置**：200+ 用户，7-8 名工程师维护
> **更新时间**：2026-03-05（v0.8 同步）

---

## 总览

```
Phase 0 → Phase 1 → Phase 2 → Phase 3
  MVP       核心功能    管家自动化    全功能
  ~6周       ~12周       ~16周        ~24周

每个 Phase 可独立部署、独立验收、对用户产生真实价值
```

---

## Phase 0：最小可用版本（MVP）

**目标**：让团队能用，建立信任，验证核心价值假设。

**核心假设验证**：
- "群聊消息自动入库"是否真的有用？
- 用户愿意通过搜索/问答代替重复提问吗？

### 包含功能

| 模块 | 表 | API 端点 |
|------|----|----------|
| 消息接收 + Stage 0-2（分类） | messages, topic_threads | POST /webhook/message |
| 全文检索 | — | GET /api/v1/threads/search |
| FAQ 问答（基础） | faq_items, faq_sessions | GET /api/v1/qa, GET /api/v1/faq |
| 用户白名单 | user_whitelist | — |
| Web Dashboard（只读） | — | 浏览 + 搜索 |

**不包含**：待办、敏感授权、管家、通知推送、知识图谱

**技术栈**：SQLite + FastAPI + 最简 Vue 3 页面

**验收标准**：
- [ ] 消息入库延迟 < 3s（P99）
- [ ] 全文检索返回 < 1s
- [ ] 100 条消息/天基线场景稳定运行 1 周
- [ ] 至少 3 个团队成员主动使用搜索/问答

---

## Phase 1：核心功能完整版

**目标**：覆盖日常工作流，成为团队信息基础设施。

**新增假设验证**：
- 敏感信息分级授权机制是否流畅？
- 待办跟踪是否真的帮助任务不遗漏？

### 新增功能

| 模块 | 新增表 | 新增 API |
|------|--------|---------|
| 完整流水线 Stage 3-4（实体提取、知识图谱） | knowledge_nodes, knowledge_edges | — |
| 待办管理（创建、提醒、完成） | todos | /api/v1/todos/* |
| 敏感信息授权（L1/L2/L3 分级） | sensitive_authorizations | /api/v1/sensitive/* |
| 基础通知推送 | notifications | /api/v1/notifications/* |
| 用户在线状态 + 离线消息队列 | user_presence, queued_notifications | /api/v1/presence/* |
| nullclaw 基础接入（摘要更新 + 每日推送） | nullclaw_pending_events | — |
| **nullclaw Watchdog** | watchdog_events | /api/v1/internal/watchdog/* |
| FAQ 质量保障 | faq_quality_alerts | /api/v1/faq/alerts/* |

**技术升级**：SQLite → PostgreSQL（如并发需要）

**验收标准**：
- [ ] 敏感授权流程 E2E 测试通过
- [ ] 待办创建→提醒→完成闭环测试通过
- [ ] nullclaw 宕机后 Watchdog 60s 内自动恢复
- [ ] 用户上线后 Heartbeat 推送延迟 < 5s
- [ ] 7-8 名工程师完成运维培训

---

## Phase 2：管家智能化

**目标**：让管家从"被动工具"变成"主动运营者"。

**新增假设验证**：
- 工作流学习机制是否能真正减少人工重复操作？
- 跨群信息推送是否帮助"信息平权"？

### 新增功能

| 模块 | 新增表 | 新增 API |
|------|--------|---------|
| 工作流托管（supervised 模式） | workflow_templates, workflow_instances | /api/v1/workflows/* |
| 跨群任务分发 | task_delegates | /api/v1/tasks/delegate/* |
| 管家 PRD 上报 | butler_proposals（扩展字段） | — |
| 软能力扩展（分类/任务类型） | extension_definitions | /api/v1/extensions/definitions/* |
| 自定义属性 | custom_field_definitions, custom_field_values | /api/v1/custom-fields/* |
| 检索召回率自省 | search_logs, recall_evaluations | — |
| **内容发布 - 富文本文档** | user_documents | /api/v1/documents/* |
| **内容发布 - 外部链接卡片** | shared_links | /api/v1/shared-links/* |
| **AI 智能辅助输入全系统集成** | — | 前端逐步接入 §44 设计模式 |
| **管家推送配置**（v0.8） | butler_push_config | /internal/butler/config, /api/v1/admin/butler/config/* |

**工程重点**：
- §24 工作流学习 Prompt 调优
- §25 字段建议 Prompt 调优与采纳率自省
- nullclaw Routine 框架完善（Routine A/B/C）
- 插件机制第一个实际插件交付验证

**验收标准**：
- [ ] 工作流模板学习：3 次重复触发后自动提议模板
- [ ] supervised 工作流审批流程 < 2 分钟响应
- [ ] 管家首次输出 PRD（月度评估触发）
- [ ] 召回率 Routine C 完整运行一次
- [ ] 至少 1 个 event_hook 类型插件上线

---

## Phase 3：全功能完整版

**目标**：系统能力全面开放，管家达到自主运营水平。

### 新增功能

| 模块 | 新增内容 |
|------|---------|
| 工作流 autonomous 模式 | 经过 Phase 2 验证后，高信任模板开启自主执行 |
| 硬能力扩展完整机制 | extension_registry 全面启用，外部团队可接入插件 |
| 数据归档策略（L1/L2/L3） | 冷热数据分层，降低存储成本 |
| 消息 DLQ（死信队列） | failed_messages 表，管理员处理异常消息 |
| 高级分析 Dashboard | 团队协作网络图、瓶颈热力图 |
| nullclaw Script 插件生态 | claw 团队维护的插件库开放 |

**验收标准**：
- [ ] autonomous 工作流执行成功率 > 90%
- [ ] 插件注册→审核→激活全流程 < 1 个工作日
- [ ] 数据归档正常运行（L1→L2 按时间窗口执行）
- [ ] DLQ 运营流程建立，异常消息 SLA 内处理

---

## 各阶段依赖关系

```
Phase 0（必须先完成）
  ↓
Phase 1（平台基础设施，是 Phase 2 的前提）
  ↓
Phase 2（管家智能化，是 Phase 3 autonomous 的前提）
  ↓
Phase 3（全功能，可拆分独立交付）
```

**可并行的工作**：
- Phase 2 开发期间，Phase 3 的数据归档、DLQ 可以并行设计和测试
- Watchdog 在 Phase 1 就必须交付（不可推迟）

---

## 表的分阶段归属

| 表 | Phase | 说明 |
|----|-------|------|
| messages, topic_threads | 0 | 核心必须 |
| user_whitelist, category_definitions | 0 | 配置必须 |
| faq_items, faq_sessions | 0 | MVP 价值核心 |
| knowledge_nodes, knowledge_edges | 1 | 图谱支撑实体提取 |
| todos | 1 | 任务跟踪 |
| sensitive_authorizations | 1 | 敏感信息合规 |
| notifications, user_presence, queued_notifications | 1 | 推送基础设施 |
| nullclaw_pending_events（含 thread_id 有序重试字段）, watchdog_events | 1 | 可靠性基础（v0.8：thread_id 保证同线索事件有序重放） |
| faq_quality_alerts | 1 | FAQ 质量闭环 |
| user_subscriptions（扩展类型） | 1 | 订阅类型枚举扩展（新增6种） |
| butler_suggestions | 1 | AI 智能辅助输入基础设施，全系统复用 |
| workflow_templates, workflow_instances, task_delegates | 2 | 管家自动化 |
| extension_definitions | 2 | 软扩展 |
| search_logs, recall_evaluations | 2 | 召回率自省 |
| custom_field_definitions, custom_field_values | 2 | 自定义属性 |
| butler_proposals（PRD扩展字段） | 2 | PRD上报 |
| user_documents | 2 | 内容发布 - 系统内富文本文档 |
| shared_links | 2 | 内容发布 - 外部链接分享卡片 |
| butler_push_config | 2 | 管家推送目标配置（Routine 日报/周报/告警推送房间动态配置） |
| extension_registry, extension_invocation_logs | 3 | 硬扩展生态 |
| failed_messages | 3 | DLQ |
| archive_status（字段） | 3 | 数据归档 |

---

## 风险与缓解

| 风险 | 出现阶段 | 缓解措施 |
|------|----------|----------|
| LLM 分类准确率不达预期 | Phase 0 | 提前准备手工标注数据集，准备回退规则 |
| nullclaw 不稳定影响体验 | Phase 1 | Watchdog 是 P0 交付项，不可推迟 |
| 工作流学习样本不足 | Phase 2 | 降低触发阈值（2次触发即提议），人工辅助创建初始模板 |
| 插件安全审核延迟 | Phase 3 | 建立快速审核通道，提前制定插件安全规范 |
| 团队对自动化工作流的信任不足 | Phase 2 | 从低风险场景入手，保持 supervised 模式充分时间再升 autonomous |

---

*本文档随实际进度持续更新。各阶段具体时间节点和资源分配在 Sprint 规划会议中确定。*
