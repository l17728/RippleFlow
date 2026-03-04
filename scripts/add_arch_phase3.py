"""Phase 3: 追加 §39-42 到 01_system_architecture.md"""

arch_additions = """

---

## §39 扩展机制架构

### 39.1 整体设计原则

RippleFlow 提供两种扩展轨道，平台核心代码零侵入：

```
扩展类型        触发方式                    审核要求
─────────────────────────────────────────────────────
软能力扩展      LLM 分类流水线（复用现有）   低风险自动，高风险管理员
硬能力扩展      Event Hook / nullclaw 脚本   必须管理员审核
```

### 39.2 软能力扩展（Soft Extension）

扩展现有分类体系和任务种类，无需修改平台代码，直接由 Stage 2 LLM 识别。

**风险分级策略：**

| 操作类型 | 风险 | 生效方式 |
|----------|------|----------|
| 新增子分类/标签（现有分类下） | 低 | 直接 active，异步通知管理员 |
| 修改分类描述/关键词权重 | 低 | 直接 active，异步通知管理员 |
| 新增一级分类 | 高 | status=pending，写入 butler_proposals |
| 修改 Stage 2 触发规则 | 高 | status=pending，管理员审核后平台重载配置 |

**生命周期：**

```
nullclaw 识别新分类需求
  → propose_soft_extension(ext_type, ext_key, risk_level)
      → low: status=active，Stage2 立即可识别，推送管理员通知
      → high: status=pending，写 butler_proposals，等管理员 approve
  → 管理员 approve_soft_extension()
      → status=active
  → 管理员 disable: status=disabled，Stage2 不再识别
```

**存储：** `extension_definitions` 表（详见 §DDL Phase 1）

### 39.3 硬能力扩展（Hard Extension）— 双轨制

**Track 1：Platform Event Hooks（平台侧 Webhook）**

平台在流水线关键节点向注册服务发送 Webhook：

```
Hook 事件节点：
  on_message_received     Stage 0 之前（收到消息即触发）
  on_stage_completed      每个 Stage 完成（携带 stage_result）
  on_thread_created       新话题线索创建
  on_faq_item_created     FAQ 条目入库
  on_todo_created         待办创建
  on_user_online          用户上线（Heartbeat 触发）
  on_workflow_triggered   工作流触发
```

调用流程：
```
平台触发 hook_event
  → 查询 extension_registry WHERE hook_event IN hook_events AND status=active
  → 并发 HTTP POST webhook_url（超时 3s，非阻塞）
  → 记录 extension_invocation_logs（success/failed/timeout）
  → 返回各扩展响应列表
```

**Track 2：nullclaw Extension Scripts（管家侧）**

沿用 `extensions/` 目录，注册到 `extension_registry` 表进行版本管理。

管家在 Routine 或消息处理中调用注册的脚本，平台负责记录调用审计。

**共同约束：**
- 所有硬能力扩展提交后 status=pending，**必须管理员审核**才能激活
- 所有调用均写入 `extension_invocation_logs`，可随时审计
- 可随时 disable 回滚，平台核心流程不受影响

**存储：** `extension_registry` + `extension_invocation_logs` 表

### 39.4 扩展 API 端点

```
软能力扩展：
  GET  /api/v1/extensions/definitions           列出软扩展定义
  POST /api/v1/extensions/definitions           提议新扩展
  POST /api/v1/extensions/definitions/{id}/approve   管理员审核
  POST /api/v1/extensions/definitions/{id}/disable   禁用

硬能力扩展：
  GET  /api/v1/extensions/registry              插件注册表
  POST /api/v1/extensions/registry              注册插件（提交待审核）
  POST /api/v1/extensions/registry/{id}/approve 管理员激活
  GET  /api/v1/extensions/registry/{id}/logs    调用日志
```

---

## §40 用户在线状态与离线消息推送

### 40.1 在线状态检测

采用客户端主动 Heartbeat 方案：

```
客户端每 30 秒 POST /api/v1/presence/heartbeat
  → 更新 user_presence（status=online, last_heartbeat=NOW()）
  → 查询 queued_notifications（delivered_at IS NULL, LIMIT 50）
  → 批量返回待推送通知
  → 标记 delivered_at=NOW()
  → 触发 on_user_online Event Hook

后台定时任务（每 60 秒）：
  → 查询 last_heartbeat < NOW() - 60s
  → mark_offline()，status=offline
```

状态机：

```
            +--------+   Heartbeat   +---------+
            | offline| ──────────── >|  online |
            +--------+               +---------+
                 ^                       |
                 |  60s 无心跳           |  30~59s 无心跳
                 |                       v
                 |                   +--------+
                 +------------------ |  idle  |
                                     +--------+
```

**存储：** `user_presence` 表

### 40.2 离线消息队列

通知优先级定义：

| Priority | 场景 |
|----------|------|
| 1 | @mention / 敏感授权到期提醒 |
| 3 | 工作流待审批 / 待办到期 |
| 5 | 每日摘要 / FAQ 质量告警 |

队列写入逻辑（`enqueue_notification`）：
- 用户在线：直接推送（通过 App 内通知）
- 用户离线：写入 `queued_notifications`，等待下次 Heartbeat

**存储：** `queued_notifications` 表（`idx_queued_notif_user` 索引按 user_id+priority 覆盖）

### 40.3 在线状态 API 端点

```
POST /api/v1/presence/heartbeat              心跳（返回缓存通知列表）
GET  /api/v1/presence/status/{user_id}       查询用户在线状态
GET  /api/v1/presence/online                 在线用户列表（管理员/管家）
GET  /api/v1/presence/queue                  获取待推送队列
```

---

## §41 AI 管家工作流托管

### 41.1 工作流学习机制

管家从消息流中识别重复处理模式，抽象为可复用的工作流模板：

```
消息流分析
  → nullclaw 识别触发条件（trigger_pattern）
  → 匹配历史处理案例（knowledge_nodes/edges）
  → 提取处理步骤（steps: JSONB 数组）
  → 调用 create_template() 写入 workflow_templates
  → 默认 trust_level=supervised，trust_score=0
```

**Steps 格式示例：**

```json
[
  {"step": 1, "action": "notify_user",   "target": "@user",  "template": "..."},
  {"step": 2, "action": "create_todo",   "assignee": "...",  "due_offset_days": 3},
  {"step": 3, "action": "cross_delegate","target_group": "...","task": "..."}
]
```

### 41.2 工作流执行模式

**Supervised 模式（默认）：**

```
触发条件满足
  → create_instance()（status=pending_approval）
  → enqueue_notification(priority=3, event_type=workflow_approval)
  → 用户收到 Heartbeat 推送
  → 用户 approve_instance() → status=running → 执行 steps
  → 用户 cancel_instance() → status=cancelled
      → cancelled_by=user_handled → 管家学习用户处理方式
```

**Autonomous 模式（需授权）：**

```
触发条件满足
  → create_instance()（status=running）
  → 立即执行 steps，记录 execution_log
```

**信任度升级双轨触发：**

| 轨道 | 条件 | 行为 |
|------|------|------|
| 显式授权 | 用户说"以后直接帮我处理这类任务" | 立即升级 trust_level=autonomous |
| 自动升级 | success_count ≥ 3 AND trust_score ≥ 0.85 | 管家提议升级，推送通知用户可随时关闭 |

**trust_score 更新规则：**
- 用户批准并成功执行：`trust_score += 0.1`
- 用户取消并自行处理：`trust_score += 0.05`（说明管家方向正确但时机/方式需改进）
- 执行失败：`trust_score -= 0.2`

### 41.3 跨群任务分发

管家可将任务分发给其他群组成员：

```
nullclaw 识别需要协调的任务
  → delegate_task(target_user_id, task_description, target_group_id)
  → 创建 task_delegates 记录（status=pending）
  → enqueue_notification(target_user_id, event_type=task_delegated, priority=3)
  → 目标用户上线收到推送
  → 用户 update_delegate_status(status=accepted/rejected/completed)
```

**存储：** `workflow_templates` + `workflow_instances` + `task_delegates` 表

### 41.4 知识图谱辅助上下文补全

利用现有 `knowledge_nodes/edges` 表：

```
工作流触发时
  → 查询 topic_threads → knowledge_edges 找同主题历史话题
  → 提取 Person/Resource/Timeline 节点补全 context JSONB
  → 对比当前 stakeholder_ids 与历史相关人员
      → 信息不对齐 → 在 execution_log 中记录差异
```

### 41.5 工作流 API 端点

```
GET  /api/v1/workflows/templates              工作流模板列表
POST /api/v1/workflows/templates              创建模板（管家学习后）
PUT  /api/v1/workflows/templates/{id}         更新模板（风格/信任度）
GET  /api/v1/workflows/instances              执行历史
POST /api/v1/workflows/instances/{id}/approve 用户批准执行
POST /api/v1/workflows/instances/{id}/cancel  用户取消
POST /api/v1/tasks/delegate                   跨群任务分发
PUT  /api/v1/tasks/delegate/{id}              更新任务状态
```

---

## §42 检索召回率自省

### 42.1 检索记录

所有查询自动写入 `search_logs` 表：

```python
# 每次检索（FTS / KG 遍历 / QA / FAQ）完成后
search_logs.insert(
    query       = user_query,
    query_type  = "fts" | "kg_traverse" | "qa" | "faq" | "combined",
    result_ids  = [retrieved_ids],
    result_count = len(results),
    latency_ms  = elapsed,
)
```

### 42.2 召回率自省（Routine C，每月执行）

```
nullclaw Routine C 触发（每月第一天）
  → 从 search_logs 随机抽取 100 条历史查询
  → 用当前索引重新检索 → index_results
  → 用全文扫描（不限索引）检索同样查询 → fullscan_results（基准）
  → 计算 Recall = |index ∩ fullscan| / |fullscan|
  → 计算 Precision = |index ∩ fullscan| / |index|
  → 写入 recall_evaluations
  → 若 Recall < 0.8
      → 管家分析改进方向（improvement_notes）
      → 生成 PRD 上报（§43 PRD 格式）
```

**阈值参考：**

| 指标 | 目标 | 告警阈值 |
|------|------|----------|
| Recall | ≥ 0.85 | < 0.80 |
| Precision | ≥ 0.70 | < 0.60 |
| 平均延迟 | ≤ 500ms | > 1000ms |

### 42.3 信息增量修正回溯

利用现有 `thread_modifications` + `knowledge_nodes/edges` 表：

```
消息澄清了前序信息
  → Stage 4 识别修正事件（event_type=correction）
  → thread_modifications 记录（原值/新值/修正原因）
  → 更新 knowledge_nodes.attributes (JSONB merge)
  → 通过 knowledge_edges 找关联话题
      → 检查关联话题是否需要同步修正
      → 推送给相关人员（enqueue_notification）
```

### 42.4 自定义属性（Custom Fields）

用户或管家可为各类实体定义自定义字段：

```
字段定义来源：
  用户定义 → 直接生效（suggested_by=user_id, adopted_by=user_id）
  管家推荐 → status=suggested（suggested_by=nullclaw）
           → 用户 adopt_suggestion() → 正式生效，记忆复用

管家推荐策略（suggest_fields）：
  → 查询 custom_field_definitions WHERE usage_count > 0
  → 按 entity_type + context（话题类别/参与人）排序
  → 返回 Top 5 推荐字段
```

**字段类型：** `text | number | date | select | boolean`

**支持实体：** `thread | todo | faq_item | workflow`

**存储：** `custom_field_definitions` + `custom_field_values` 表

---

**END OF DOCUMENT**
"""

# Remove the old END OF DOCUMENT marker and append new content
with open('D:/RippleFlow/docs/01_system_architecture.md', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace the last END OF DOCUMENT with new sections
content = content.rstrip()
if content.endswith('**END OF DOCUMENT**'):
    content = content[:-len('**END OF DOCUMENT**')].rstrip()

content += arch_additions

with open('D:/RippleFlow/docs/01_system_architecture.md', 'w', encoding='utf-8') as f:
    f.write(content)

print('01_system_architecture.md updated - §39-42 added')
