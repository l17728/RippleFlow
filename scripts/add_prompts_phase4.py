"""Phase 4B: 追加 §23 PRD生成Prompt + §24 工作流学习Prompt 到 06_llm_prompt_templates.md"""

prompt_additions = '''

---

## §23 PRD 生成 Prompt（管家自省→需求上报）

**触发场景：** 管家在自省中发现平台能力缺口，生成结构化 PRD 上报给管理员和开发团队。

```python
BUTLER_PRD_GENERATION_PROMPT = """
你是 RippleFlow 平台的 AI 管家 nullclaw，正在进行月度/周度自省。
你发现了一个平台能力缺口，需要生成一份结构化的 PRD 提案。

## 发现的问题

{problem_description}

## 支撑数据

{supporting_data}

## 相关话题/记录

{related_thread_ids}

---

请生成一份符合 rippleflow_prd_v1 标准格式的 PRD：

# {prd_title}

**提案来源**: nullclaw 自省 | **发现时间**: {current_date}
**优先级**: [P0/P1/P2，根据影响范围和紧迫性判断] | **影响范围**: [平台/管家/客户端]
**关联话题**: {related_thread_ids}

## 背景与问题描述

[2-4句描述现象，附上量化数据]

## 用户需求（User Story 格式）

As a [用户角色], I want [具体功能], So that [解决的问题/带来的价值].

（列出 2-3 个核心 User Story）

## 功能设计方案

### 方案描述
[简要描述实现思路]

### 涉及的接口/数据库变更
[列出需要新增或修改的 API / 表 / 字段]

### 对现有功能的影响
[兼容性分析]

## 验收标准

- [ ] [可验证的指标 1]
- [ ] [可验证的指标 2]
- [ ] [可验证的指标 3]

## 技术影响评估

- **涉及文件**: [具体文件路径]
- **工作量估算**: [S/M/L/XL]
- **风险**: [风险点和缓解措施]

---

注意事项：
1. 优先级判断标准：
   P0 = 影响核心功能/数据安全
   P1 = 影响用户效率/重要流程
   P2 = 体验改进/非核心功能
2. 保持客观，用数据说话，不要夸大问题
3. 方案要符合「机制/策略分离」原则，平台只提供机制
4. 若问题有多个解决方案，列出权衡对比
"""
```

**调用示例：**

```python
# 召回率自省触发 PRD 生成
if avg_recall < 0.8:
    prd = llm.call(
        BUTLER_PRD_GENERATION_PROMPT.format(
            prd_title="检索召回率优化",
            problem_description=f"过去 30 天检索召回率均值 {avg_recall:.2%}，低于目标阈值 0.80",
            supporting_data=f"评估样本：100 条查询\n"
                           f"当前召回率：{avg_recall:.2%}\n"
                           f"当前精确率：{avg_precision:.2%}\n"
                           f"主要缺失：{improvement_notes}",
            related_thread_ids=",".join(related_threads),
            current_date=today,
        )
    )
    butler_service.create_proposal(
        title="检索召回率优化",
        prd_content=prd,
        prd_format="rippleflow_prd_v1",
        notify_devs=True,
    )
```

**输出约束：**
- 严格按 rippleflow_prd_v1 格式输出，不得省略任何章节
- 优先级必须给出明确判断，不能写「待定」
- 验收标准必须是可量化/可验证的，不能是「功能正常」
- 总长度建议 400-800 字，避免过于冗长

---

## §24 工作流学习 Prompt（管家从消息流抽象模板）

**触发场景：** 管家识别到用户重复处理的事件模式，将其抽象为可复用的工作流模板。

```python
WORKFLOW_LEARNING_PROMPT = """
你是 RippleFlow 平台的 AI 管家 nullclaw，正在从消息历史中学习工作流模式。

## 观察到的重复行为

以下是用户处理同类事件的历史记录（{case_count} 次）：

{historical_cases}

## 最新触发消息

{trigger_message}

## 知识图谱上下文

相关人员：{persons}
相关资源：{resources}
相关话题历史：{related_threads}

---

请分析以上信息，提取可复用的工作流模板：

### 1. 触发条件识别

trigger_pattern: [用自然语言描述触发条件，尽量通用]
trigger_regex: [可选，辅助匹配的正则表达式，若无则为 null]

### 2. 工作流步骤（JSON 格式）

```json
[
  {
    "step": 1,
    "action": "notify_user|create_todo|cross_delegate|send_summary|update_thread",
    "description": "步骤描述",
    "target": "目标用户/群组（可选）",
    "template": "消息模板（可选，用 {变量} 表示动态内容）",
    "due_offset_days": 3
  }
]
```

可用 action 类型：
- notify_user: 通知指定用户
- create_todo: 创建待办事项
- cross_delegate: 跨群任务分发
- send_summary: 发送摘要
- update_thread: 更新话题信息

### 3. 用户风格偏好（style_notes）

[从历史案例中总结用户的处理风格偏好，例如：
 - 通知话术风格（正式/简洁/详细）
 - 时间安排偏好（due_offset_days 倾向）
 - 沟通方式（直接告知/征询意见）
 - 是否喜欢附带背景信息]

### 4. 信任级别建议

trust_level: supervised | autonomous
trust_score: 0（初始值，从0开始积累）

建议 supervised（初始），原因：
- 这是新学习的模板，尚未经过验证
- 若该场景敏感度高，建议长期保持 supervised

### 5. 执行前检查清单

[列出执行该工作流前，管家应该确认的事项]

---

注意事项：
1. steps 必须是具体可执行的操作，不能是抽象描述
2. trigger_pattern 要尽量通用，覆盖同类场景的变体
3. style_notes 要记录具体细节，如「用户喜欢在通知前加一句背景说明」
4. 不要过度自动化：初始 trust_level 始终为 supervised
5. 若历史案例少于 3 次，在 style_notes 中注明「样本量不足，需持续观察」
"""
```

**调用示例：**

```python
# 识别到第 3 次重复处理模式时触发
if pattern_count >= 3:
    template_json = llm.call(
        WORKFLOW_LEARNING_PROMPT.format(
            case_count=pattern_count,
            historical_cases=format_cases(historical_cases),
            trigger_message=current_message.content,
            persons=extract_persons(context),
            resources=extract_resources(context),
            related_threads=format_threads(related_threads),
        )
    )
    workflow_service.create_template(
        name=template_json["name"],
        trigger_pattern=template_json["trigger_pattern"],
        steps=template_json["steps"],
        style_notes=template_json["style_notes"],
        learned_from=[c.thread_id for c in historical_cases],
    )
```

**输出约束：**
- steps 必须是合法的 JSON 数组，action 必须是可用类型之一
- style_notes 必须包含至少 2 条具体的风格偏好
- 不得建议 trust_level=autonomous（初始必须 supervised）
- trigger_pattern 长度不超过 200 字，保持简洁通用
'''

with open('D:/RippleFlow/docs/06_llm_prompt_templates.md', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.rstrip() + '\n' + prompt_additions

with open('D:/RippleFlow/docs/06_llm_prompt_templates.md', 'w', encoding='utf-8') as f:
    f.write(content)

print('06_llm_prompt_templates.md updated - §23 and §24 added')
