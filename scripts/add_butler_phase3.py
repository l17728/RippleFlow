"""Phase 3: 更新 08_ai_butler_architecture.md - 新增工作流托管/学习机制/跨群任务分发章节"""

butler_additions = """

---

## §工作流托管与自动化执行

### 工作流学习机制

管家通过持续观察消息流，识别用户重复处理的事件模式，并将其抽象为工作流模板：

```
感知阶段：监听消息流中的触发信号
  ├── 关键词匹配（trigger_pattern）
  ├── 正则模式识别（trigger_regex）
  └── 语义理解（LLM 辅助识别结构化事件）

抽象阶段：从历史处理案例中提取模板
  ├── 查询 knowledge_nodes/edges 找同主题历史
  ├── 提取处理步骤序列（steps JSON）
  ├── 总结用户风格偏好（style_notes）
  └── 调用 IWorkflowService.create_template()

信任积累阶段：
  ├── 初始 trust_level=supervised，trust_score=0
  ├── 每次成功执行 trust_score += 0.1
  └── 达到升级条件时提议切换 autonomous 模式
```

### Supervised / Autonomous 双模式

**Supervised 模式（谨慎执行）：**

管家识别触发条件 → 生成执行计划 → 展示给用户 → 等待用户批准 → 执行

适用场景：
- 新学习的工作流（trust_score < 0.85）
- 涉及跨群通知或对外沟通的任务
- 用户明确要求"每次都让我确认"的场景

**Autonomous 模式（自主执行）：**

管家识别触发条件 → 直接执行 → 记录 execution_log → 事后通知用户

触发升级条件（任一满足）：
1. 用户显式授权："以后直接帮我处理这类任务"
2. 自动升级：`success_count ≥ 3 AND trust_score ≥ 0.85`（提议后用户未拒绝）

**用户已处理场景的学习：**

```python
# 管家检测到触发条件，但用户已自行处理
cancel_instance(
    instance_id=...,
    cancelled_by="user_handled",
    reason="用户已在 15:32 通知了相关人员"
)
# 平台触发管家学习：
#   → 提取用户处理话术 → 更新 style_notes
#   → trust_score += 0.05（方向正确，细节需改进）
```

### 工作流上下文补全策略

管家在执行工作流前，利用知识图谱丰富上下文：

```python
# context 补全流程
context = {
    "trigger_message": message_id,
    "persons": [],        # 从 knowledge_nodes(type=person) 提取
    "resources": [],      # 从 knowledge_nodes(type=resource) 提取
    "related_threads": [] # 通过 knowledge_edges 找关联话题
}

# 信息不对齐检测
current_stakeholders = extract_stakeholders(current_message)
historical_stakeholders = query_knowledge_edges(thread_id)
if missing := historical_stakeholders - current_stakeholders:
    execution_log.append({
        "warning": f"可能遗漏相关人员: {missing}",
        "action": "已推送提醒给相关人员"
    })
```

---

## §跨群任务分发

### 分发决策逻辑

管家识别以下场景时触发跨群任务分发：

| 场景 | 触发信号 | 分发行为 |
|------|----------|----------|
| 技术问题需要其他组处理 | "这个需要 XX 组来做" | delegate_task 到对应负责人 |
| 资源申请需要另一群审批 | "请帮我审批一下" | delegate_task + 附带背景材料 |
| 跟进事项跨越多个群组 | 待办涉及不同 group_id | 分别 delegate 给各群负责人 |

### 分发记录与状态跟踪

```
任务分发
  → IWorkflowService.delegate_task()
  → 写入 task_delegates（status=pending）
  → 推送通知给目标用户（enqueue_notification，priority=3）

状态更新
  → 目标用户 update_delegate_status(accepted/rejected/completed)
  → 管家收到状态变更 Event Hook
  → 同步更新原始话题的 knowledge_nodes 状态属性
  → 若 rejected → 重新分配或通知原始发起人
```

### 管家分发风格约束（style_notes 示例）

```
工作风格记忆：
- 分发任务时附带足够背景（不要只转发一句话）
- 设置合理 due_at（根据对方工作量估算，不要压迫式）
- 用户不喜欢频繁打扰：同一人同一天不超过 2 次分发
- 跨群时尊重对方群的工作节奏（避开早会时段）
```

---

## §PRD 需求发现与上报

### 管家自省→需求发现流程

管家在自省周期中识别平台能力缺口，自动生成结构化 PRD：

```
触发场景：
  1. 召回率自省（Routine C）：Recall < 0.8 → 检索能力改进 PRD
  2. 工作流执行失败（连续 3 次）→ 流水线可靠性 PRD
  3. 用户频繁请求平台不支持的操作 → 新功能需求 PRD
  4. 日常自省发现系统性问题 → 架构改进 PRD

生成流程：
  nullclaw 检测到触发条件
    → 用 §23 PRD 生成 Prompt 调用 LLM
    → 生成 rippleflow_prd_v1 格式文档
    → IButlerService.create_proposal(
          title=...,
          prd_content=prd_markdown,
          prd_format="rippleflow_prd_v1",
          notify_devs=True
      )
    → 平台推送通知给管理员 + 开发团队
```

### PRD 标准格式（rippleflow_prd_v1）

```markdown
# [需求标题]

**提案来源**: nullclaw 自省 | **发现时间**: {date}
**优先级**: P0/P1/P2 | **影响范围**: 平台/管家/客户端
**关联话题**: {thread_ids}

## 背景与问题描述
（现象描述 + 数据佐证）

## 用户需求（User Story 格式）
As a [用户角色], I want [功能], So that [价值].

## 功能设计方案
（接口/数据库/UI 变更方案）

## 验收标准
- [ ] 指标 1
- [ ] 指标 2

## 技术影响评估
（涉及文件 / 工作量估算 / 风险）
```

---

## §检索自省与信息修正

### 召回率自省（Routine C）

每月第一天执行，评估当前检索策略质量：

```python
# Routine C 伪代码
samples = search_logs.random_sample(100, date_range="last_30_days")
for query in samples:
    index_result = search_by_index(query.text)
    fullscan_result = search_fullscan(query.text)   # 无索引限制的基准
    recall = len(index_result & fullscan_result) / len(fullscan_result)

avg_recall = mean(all_recalls)
if avg_recall < 0.8:
    notes = llm_analyze("索引覆盖不足：缺少以下类型查询的索引...")
    recall_evaluations.insert(recall_rate=avg_recall, improvement_notes=notes)
    create_prd(title="检索召回率优化", priority="P1")
```

### 信息增量修正

管家在处理新消息时，识别对历史信息的修正并同步更新：

```
澄清消息处理
  → Stage 4 识别 event_type=correction
  → thread_modifications 记录（old_value / new_value / reason）
  → knowledge_nodes.attributes JSONB merge 更新
  → 通过 knowledge_edges 找关联话题（相似主题/同一项目）
  → 检查关联话题是否需要同步修正
  → 推送变更通知给相关订阅人（enqueue_notification）

自省问题：
  「这条修正消息改变了什么？影响了哪些已有结论？
   哪些人需要知道这个更新？」
```

"""

with open('D:/RippleFlow/docs/08_ai_butler_architecture.md', 'r', encoding='utf-8') as f:
    content = f.read()

# Insert before the version history section
version_marker = '## 版本历史'
if version_marker in content:
    idx = content.rfind(version_marker)
    content = content[:idx] + butler_additions.lstrip('\n') + '\n\n' + content[idx:]
else:
    content = content.rstrip() + butler_additions

with open('D:/RippleFlow/docs/08_ai_butler_architecture.md', 'w', encoding='utf-8') as f:
    f.write(content)

print('08_ai_butler_architecture.md updated - workflow/cross-group/PRD/recall sections added')
