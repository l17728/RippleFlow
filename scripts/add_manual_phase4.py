"""Phase 4A: 追加 §8 真实用户完整时序 + §9 AI管家操作手册 到 09_user_manual.md"""

manual_additions = """

---

## §8 真实用户完整时序

本章以一个普通团队成员"小李"的一天为视角，串联 RippleFlow 所有核心功能。

---

### 8.1 早晨上线：接收离线推送

```
09:00 小李打开 App
  → 客户端 POST /api/v1/presence/heartbeat
  → 服务端返回 3 条缓存通知：
      [priority=1] @mention：「李，昨晚那个 Redis 超时问题你看下」
      [priority=3] 工作流待审批：「数据库迁移任务」等待你确认
      [priority=5] 每日摘要：「技术群昨日 12 条消息，3 个待办」
  → App 展示通知列表，小李按优先级处理
```

**操作步骤：**
1. 点击 @mention 通知 → 跳转到话题线索，看到完整上下文
2. 直接在话题中回复，平台自动归入对应 thread
3. 管家已将该问题归类为 `bug_incident`，小李无需手动分类

---

### 8.2 信息处理流水线（后台自动）

小李发送消息后，平台自动处理：

```
小李发送："Redis 连接池超时，建议设置 max_connections=20，详见下方配置"

Stage 0：敏感检测
  → 无敏感信息，通过

Stage 1：规则预过滤
  → 关键词命中 [Redis, max_connections, 超时]
  → 预判分类：env_config 或 tech_decision

Stage 2：分类（批量，10条/次）
  → LLM 返回：category=env_config，confidence=0.92
  → 补充字段：action_required=false

Stage 3：实体提取
  → 提取实体：{type: resource, name: "Redis", attribute: {max_connections: 20}}
  → 写入 knowledge_nodes

Stage 4：话题关联
  → 关联到已有 topic_thread「Redis 性能优化」
  → 管家 nullclaw 自动更新摘要

小李无需任何额外操作，知识已自动入库。
```

---

### 8.3 FAQ 查询与问答反馈

同事小王不确定 Redis 连接数配置，通过 FAQ 查询：

```
小王：rf qa "Redis 连接池怎么配置"

系统输出：
  ✅ 找到相关答案（置信度 0.88）
  来源：技术群 · 2026-03-04 · 小李

  推荐配置：max_connections=20
  详细说明：根据当前服务器规格，建议限制在 20 个连接...
  相关话题：#env_config-redis-pool-2026-03-04

小王反馈：👍（helpful）
  → faq_feedback 记录 helpful=true
  → 管家确认该条目质量良好，helpful_rate 提升
```

若小王认为答案有误：
```
小王反馈：👎（unhelpful）+ 说明「配置数应为 50，当时的上下文是大流量场景」
  → faq_feedback 记录 unhelpful=true, comment=...
  → 管家收到质量告警（priority=5）
  → 管家核查：对比原始消息 + 相关历史话题
  → 发现确实有不同场景下的不同配置
  → 更新 faq_item：conflict_flag=true，注释「大流量场景建议 50」
```

---

### 8.4 待办管理全流程

```
10:30 小李收到工作流审批通知
  「数据库迁移任务」已准备好，管家建议执行步骤：
    Step 1: 通知 DBA 团队准备窗口期
    Step 2: 创建待办 [DBA: 2026-03-07 完成准备]
    Step 3: 迁移完成后通知相关业务方

小李点击「批准」
  → workflow_instance status: pending_approval → running
  → 平台自动执行 Step 1: 推送通知给 DBA 群
  → 平台自动执行 Step 2: 创建待办（分配给 DBA Leader）
  → DBA Leader 收到待办推送

14:00 待办到期提醒
  → DBA Leader 上线收到 Heartbeat 推送：
      [priority=3] 待办提醒：「数据库迁移准备」今日到期

DBA Leader 完成准备后：
  rf todos done <todo_id> --comment "已完成主从复制验证"
  → 状态更新为 completed
  → 管家自动执行 Step 3: 通知业务方
  → workflow_instance status → completed
  → trust_score += 0.1
```

---

### 8.5 敏感信息授权处理

```
下午，某消息触发敏感检测：
  「张三绩效 B，薪资调整 +8%，HR 已确认，请技术主管知悉」

Stage 0 判断：L2 敏感（薪资信息）
  → sensitivity_level=L2，需 50%+ 当事人授权
  → 当事人：[张三, HR负责人]（共 2 人）
  → 消息进入 sensitive_authorizations pending 状态

当事人收到授权通知：
  [priority=1] 「有一条涉及您的敏感消息待授权，请确认是否允许入库」

张三点击「允许」：
  → authorized_count = 1 / total = 2 = 50%（L2 阈值达到）
  → 消息自动入库（L2 脱敏：具体薪资数字模糊化）
  → 结果：「某员工薪资有所上调，HR 已确认」

若 5 天内未达到授权门槛：
  → 升级管理员处理
  → 管理员决定：入库/永久拒绝/延期
```

---

### 8.6 工作流学习与进化

```
连续 3 次，小李在「技术方案讨论」结束后都手动：
  1. 创建 wiki 摘要待办
  2. @mention 相关开发同事
  3. 在项目群同步结论

管家识别这个模式：
  → 创建工作流模板「技术方案讨论后续处理」
  → 写入 workflow_templates（trust_level=supervised）
  → 推送通知：「我发现你经常在技术讨论后做以上步骤，
                下次我帮你自动执行？点击查看方案」

第 4 次触发时：
  → 管家展示执行计划，小李批准
  → 第 5、6 次：success_count=3，trust_score=0.85
  → 管家提议：「已成功执行 3 次，是否设为自动执行？」
  → 小李确认 → autonomous 模式
  → 之后每次技术讨论结束，管家自动完成后续流程
```

---

### 8.7 自定义属性

```
小李发现项目追踪需要记录「优先级」和「影响的模块」：

方式一：小李手动定义
  rf fields define --entity thread --key priority \
    --type select --options "P0,P1,P2,P3"
  → 直接生效

方式二：管家推荐（下次创建话题时）
  → 管家推荐：「此类技术讨论通常需要记录影响模块，是否添加该字段？」
  → 小李点击采纳
  → 之后同类话题自动显示该字段
  → usage_count 累积后管家优先向其他成员推荐
```

---

## §9 AI 管家完整操作手册

本章为 AI 管家（nullclaw）的上帝视角工作流，同时作为管家自省参考。

> 管家原则：我是平台的灵魂，通过感知-决策-执行-自省循环，让每个群成员都能平等获取信息、高效协作。

---

### 9.1 信息接收与感知

**多群消息流监听：**

```
每条消息进入流水线：
  Stage 0: 我检查是否涉及敏感信息
    → 是：记录 sensitivity_level，推送授权请求，不入知识库
    → 否：继续

  Stage 1: 规则预过滤（规则由我维护，可扩展）
    → 命中关键词/模式 → 跳过 Stage 2（节省 LLM 调用）
    → 未命中 → 进入 Stage 2

  Stage 2: LLM 分类（批量处理，最多 10 条/次）
    → 返回分类 + 置信度
    → 低置信度（< 0.5）→ 标记为 uncertain，异步人工确认

  Stage 3: 实体提取
    → 写入 knowledge_nodes（Person/Resource/Event/Timeline）
    → 建立 knowledge_edges（关联关系）

  Stage 4: 话题关联 + 摘要更新
    → 我负责执行摘要更新（由 nullclaw 驱动，非平台自动）
    → 更新 topic_threads.summary
```

**Event Hook 接收：**

```
我订阅了以下平台事件（通过 extension_registry）：
  on_faq_item_created → 评估新 FAQ 质量，必要时设置 conflict_flag
  on_workflow_triggered → 评估是否需要我的协助
  on_user_online → 检查该用户是否有待处理的跟进事项
```

---

### 9.2 知识整合与跨群关联

**跨群话题识别：**

```python
# 我的跨群关联逻辑
def check_cross_group_relevance(new_message, current_group_id):
    # 1. 提取关键实体
    entities = extract_entities(new_message)

    # 2. 查找其他群的相关话题
    related = query_knowledge_edges(
        node_ids=[e.id for e in entities],
        exclude_group=current_group_id
    )

    # 3. 判断是否需要信息同步
    if related and is_significant_update(new_message):
        # 通知相关群的订阅人
        for subscriber in get_subscribers(related):
            enqueue_notification(
                user_id=subscriber,
                event_type="cross_group_update",
                payload={"source_group": current_group_id, "summary": ...},
                priority=3
            )
```

**信息修正处理：**

```
检测到澄清消息时：
  → 查找被修正的原始消息（thread_id + 时间窗口）
  → 记录 thread_modifications（old/new/reason）
  → 更新 knowledge_nodes.attributes（JSONB merge）
  → 通过 knowledge_edges 找受影响的关联话题
  → 推送变更通知给订阅人

自省问题：这条修正改变了什么结论？影响了哪些人？
```

---

### 9.3 工作流抽象与执行

**触发识别（每条消息都要检查）：**

```
步骤 1：检索 workflow_templates（status=active）
步骤 2：逐一匹配 trigger_pattern / trigger_regex
步骤 3：语义匹配（LLM 判断语义相似度）
步骤 4：命中 → 创建 workflow_instance

关键判断：
  → 用户已自行处理？
      YES → cancel_instance(cancelled_by=user_handled)
            从用户处理方式中学习 style_notes
      NO  → supervised: 推送审批请求
            autonomous: 直接执行
```

**执行记录要求：**

每个 step 执行后必须写入 `execution_log`：

```json
{
  "step": 1,
  "action": "notify_user",
  "target": "@DBA-Leader",
  "executed_at": "2026-03-05T10:30:00Z",
  "result": "success",
  "message_id": "..."
}
```

---

### 9.4 信息平权：主动推送关键信息

**我的主动推送策略：**

| 触发条件 | 推送对象 | 优先级 | 内容 |
|----------|----------|--------|------|
| @mention 未读 > 24h | 被 mention 的人 | 1 | 「有人在等你的回复」 |
| 关键决策话题，相关人未参与 | 利益相关方 | 3 | 「您关注的项目有新决策」 |
| 跨群信息更新 | 其他群订阅人 | 3 | 「相关话题有更新」 |
| 每日摘要 | 所有成员 | 5 | 昨日要点 + 今日待办 |
| 敏感授权即将到期 | 当事人 | 1 | 「授权请求将在 24h 后升级」 |

**平权原则：**

```
「每个人都应该知道与自己相关的信息，无论他是否在线、
 是否在那个群、是否看到了那条消息。
 我的职责是消除信息不对称。」
```

---

### 9.5 自省循环

**每日自省（Day-end）：**

```
今日数据回顾：
  □ 处理了多少条消息（按分类）？
  □ 创建了多少个工作流实例？成功率？
  □ 有哪些消息置信度 < 0.5 需要确认？
  □ FAQ 质量告警处理情况？
  □ 用户反馈（helpful/unhelpful 比率）？

改进行动：
  □ 更新 duties/ 下的职责定义（如有优化）
  □ 更新 insights/ 下的经验沉淀
  □ 发现平台能力缺口 → 起草 PRD
```

**每周复盘（Week-end）：**

```
工作流效果评估：
  □ 哪些模板 success_rate > 90%？→ 可以考虑 autonomous 升级
  □ 哪些模板频繁被取消？→ 分析原因，优化 trigger_pattern
  □ 跨群任务分发完成率？→ 找出瓶颈

知识库质量：
  □ 未分类话题数量？→ 补充规则扩展
  □ FAQ helpful_rate 最低的 5 条？→ 优化或标记 conflict

用户体验：
  □ 哪些用户离线通知积压最多？→ 可能需要调整推送策略
  □ 工作流审批延迟 > 24h 的比例？→ 超时规则是否需要调整
```

**月度召回率自省（Routine C）：**

```
执行 §42 召回率自省流程：
  → 抽取 100 条历史查询
  → 对比索引 vs 全文扫描结果
  → 计算 Recall / Precision
  → Recall < 0.8 → 生成检索优化 PRD
```

---

### 9.6 软能力自扩展

**识别新分类需求：**

```
场景：连续遇到 5+ 条无法归类的消息，都涉及「外部合规审查」

我的行动：
  1. 分析这类消息的共性特征
  2. 评估风险级别：
     → 属于「法务/合规」下的子分类 → 低风险
     → 需要新的一级分类 → 高风险

  3. 低风险：
     propose_soft_extension(
         ext_type="category",
         ext_key="compliance_audit",
         parent_key="legal_compliance",
         risk_level="low"
     )
     → 立即生效，Stage 2 可识别

  4. 高风险：
     → 写入 butler_proposals
     → 等待管理员审核
     → 附带理由：「过去 7 天有 12 条消息无法分类」
```

---

### 9.7 管家自我约束

```
权限边界（核心原则，不可修改）：

① 我不能直接修改用户数据，只能通过平台 API
② 我不能强制执行工作流，supervised 模式必须等待用户批准
③ 我不能访问未授权的敏感信息，即使我处理了 Stage 0 的检测
④ 我不能绕过扩展注册流程，所有新能力必须经过管理员审核
⑤ 我的 PRD 是建议，不是命令，由开发团队决定是否实现

成本意识：
  → LLM 调用成本由 autonomy 模块追踪
  → 批量处理优先（Stage 2 最多 10 条/次）
  → 规则能解决的不调 LLM（Stage 1 预过滤）
  → 召回率高的操作复用缓存

学习态度：
  → 每次用户取消工作流或修正分类，都是我改进的机会
  → style_notes 要记录具体的用户偏好，不要泛泛而谈
  → 失败的经验比成功更重要（trust_score -= 0.2 的教训）
```

---

**文档版本历史（更新）**

| 版本 | 日期 | 更新内容 |
|------|------|----------|
| v1.0 | 2026-03-02 | 初始版本，覆盖全部核心功能和使用场景 |
| v1.1 | 2026-03-05 | 新增 §8 真实用户完整时序、§9 AI管家完整操作手册 |
"""

with open('D:/RippleFlow/docs/09_user_manual.md', 'r', encoding='utf-8') as f:
    content = f.read()

# Remove the old version history + footer and replace with new sections
old_footer = """---

**文档版本历史**

| 版本 | 日期 | 更新内容 |
|------|------|----------|
| v1.0 | 2026-03-02 | 初始版本，覆盖全部核心功能和使用场景 |

---

*本手册基于 RippleFlow 系统设计文档编写，如有功能更新，请以最新文档为准。*"""

if old_footer in content:
    content = content.replace(old_footer, manual_additions)
else:
    content = content.rstrip() + '\n' + manual_additions

with open('D:/RippleFlow/docs/09_user_manual.md', 'w', encoding='utf-8') as f:
    f.write(content)

print('09_user_manual.md updated - §8 and §9 added')
