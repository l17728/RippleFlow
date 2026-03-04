# 06 LLM Prompt 模板库

本文档定义 RippleFlow 所有 GLM-4-Plus API 调用的 Prompt 模板、参数配置及输出解析规范。
开发时直接参照本文档实现 `LLMServiceImpl`（对应 `04_service_interfaces.md` 中的 `ILLMService`）。

---

## 1. 通用约定

### 1.1 模型与降级策略

```python
# rippleflow/infra/llm/model_config.py

MODEL_CHAIN = [
    "glm-4-plus",    # 首选：质量最高
    "glm-4-air",     # 一级降级：速度/成本平衡
    "glm-4-flash",   # 二级降级：基础可用
]

# 各 Stage 对模型质量的最低要求
MODEL_REQUIREMENTS = {
    "stage0_sensitive":    "glm-4-plus",   # 误判有法律风险，不允许降级
    "stage1_noise":        "glm-4-flash",  # 简单任务，全链路可用
    "stage2_classify":     "glm-4-air",    # 分类精度重要，允许一级降级
    "stage3_match_thread": "glm-4-air",    # 语义理解，允许一级降级
    "stage4_extract":      "glm-4-air",    # 结构化提取，允许一级降级
    "stage5_summary":      "glm-4-plus",   # 摘要更新由 nullclaw 执行，模型要求同此
    "qa_keywords":         "glm-4-flash",  # 简单关键词提取
    "qa_synthesize":       "glm-4-plus",   # 问答质量是核心体验
    "meeting_notes":       "glm-4-air",    # 纪要按需生成，允许一级降级
}
```

### 1.2 通用调用参数

| 场景 | temperature | max_tokens | top_p |
|------|------------|------------|-------|
| JSON 结构化输出（Stage 0–5，关键词提取） | 0.1 | 800 | 0.7 |
| 问答答案综合 | 0.3 | 1200 | 0.9 |
| 纪要生成 | 0.2 | 2000 | 0.8 |

> **重要**：所有要求 JSON 输出的调用，在 system prompt 末尾均追加：
> `"你的输出必须是合法的 JSON，不要包含 markdown 代码块标记（```）、注释或任何其他文字。"`

### 1.3 JSON 解析规范

```python
# rippleflow/infra/llm/json_parser.py
import json, re

def parse_llm_json(raw: str) -> dict | list:
    """
    容错解析 LLM 输出的 JSON。
    LLM 偶尔会在 JSON 外包裹 ```json ... ``` 或输出前置说明文字。
    """
    # 1. 去除 markdown 代码块
    text = re.sub(r"```(?:json)?\s*|\s*```", "", raw).strip()
    # 2. 提取第一个完整的 JSON 对象或数组
    match = re.search(r"(\{[\s\S]*\}|\[[\s\S]*\])", text)
    if not match:
        raise ValueError(f"LLM 输出无法解析为 JSON: {raw[:200]}")
    return json.loads(match.group(1))
```

### 1.4 重试与降级逻辑

```python
async def call_with_fallback(
    stage: str,
    messages: list[dict],
    temperature: float,
    max_tokens: int,
) -> str:
    min_model = MODEL_REQUIREMENTS[stage]
    start_idx = MODEL_CHAIN.index(min_model)

    for model in MODEL_CHAIN[start_idx:]:
        for attempt in range(3):  # 每个模型最多重试 3 次
            try:
                return await _call_glm(model, messages, temperature, max_tokens)
            except RateLimitError:
                await asyncio.sleep(2 ** attempt)
            except APIError as e:
                if e.status_code >= 500:
                    await asyncio.sleep(1)
                else:
                    raise  # 4xx 不重试
    raise LLMServiceError(f"Stage {stage} 所有模型均不可用")
```

---

## 2. Stage 0：敏感内容检测

**对应接口**：`ILLMService.check_sensitive`
**触发时机**：消息入队后，处理流水线第一步

### 2.1 System Prompt

```
你是一个企业信息安全审查助手，负责判断聊天消息是否包含需要当事人明确授权才可存入团队知识库的敏感内容。

敏感类型定义：
- privacy：涉及个人隐私，包括手机号、家庭状况、健康/病情、个人经济情况、私人感情等
- hr：涉及人事敏感信息，包括薪资数字、绩效评级结果、晋升/降职/离职决策、员工投诉、PIP（绩效改进计划）等
- dispute：涉及责任归属争议或团队冲突，包括项目事故责任界定、团队矛盾、客户投诉对内定责等

不属于敏感的内容（不要误判）：
- 技术方案讨论、代码 review、架构决策
- 需求变更、Bug 修复过程
- 项目进度同步、版本发布
- 一般性的批评建议（如"这个方案有问题"）
- 薪资范围/市场行情的泛泛讨论（非特定个人薪资）

判断标准：仅当消息明确涉及特定个人的隐私/人事/争议信息时，才标记为敏感。模糊内容倾向于不敏感（保守原则）。

你的输出必须是合法的 JSON，不要包含 markdown 代码块标记（```）、注释或任何其他文字。
```

### 2.2 User Prompt 模板

```python
def build_sensitive_prompt(
    content: str,
    sender_name: str,
    mentions: list[str],
) -> str:
    mentions_str = "、".join(mentions) if mentions else "无"
    return f"""发送人：{sender_name}
@提及人员：{mentions_str}
消息内容：
{content}

请判断该消息是否包含敏感内容，输出以下 JSON：
{{
  "is_sensitive": true 或 false,
  "sensitive_types": [],
  "sensitive_summary": "",
  "stakeholder_ids": []
}}

字段说明：
- sensitive_types：敏感类型列表，可多选 ["privacy", "hr", "dispute"]，is_sensitive=false 时为空数组
- sensitive_summary：一句话描述敏感原因，is_sensitive=false 时为空字符串
- stakeholder_ids：当事人的 LDAP ID，从发送人和@提及人员中识别，is_sensitive=false 时为空数组"""
```

### 2.3 输出解析

```python
def parse_sensitive_result(raw: str, sender_id: str) -> SensitiveCheckResult:
    data = parse_llm_json(raw)
    result = SensitiveCheckResult(
        is_sensitive=bool(data.get("is_sensitive", False)),
        sensitive_types=data.get("sensitive_types", []),
        sensitive_summary=data.get("sensitive_summary") or None,
        stakeholder_ids=data.get("stakeholder_ids", []),
    )
    # 安全兜底：敏感时确保发送人在当事人列表中
    if result.is_sensitive and sender_id not in result.stakeholder_ids:
        result.stakeholder_ids.append(sender_id)
    return result
```

### 2.4 典型示例

**输入**：
```
发送人：张三
@提及人员：李四
消息内容：
李四这次绩效 C，HR 说可能要走 PIP 流程了
```

**期望输出**：
```json
{
  "is_sensitive": true,
  "sensitive_types": ["hr"],
  "sensitive_summary": "涉及特定员工（李四）的绩效评级和潜在人事处理流程",
  "stakeholder_ids": ["lisi", "zhangsan"]
}
```

---

## 3. Stage 1：噪声过滤

**对应接口**：`ILLMService.check_noise`
**触发时机**：Stage 0 通过后

### 3.1 System Prompt

```
你是一个企业知识库价值筛选助手，判断一条聊天消息是否值得存入团队知识库。

【无价值 / 噪声】示例：
- 纯情绪或感叹词：「哈哈」「666」「牛」「棒」「加油」
- 无实质内容的确认：「好的」「收到」「OK」「嗯」「明白了」「知道了」「+1」
- 随意寒暄：「在吗」「今天天气真好」「中午吃什么」「快下班了」
- 表情或单字：「👍」「😂」「？」「！」
- 纯转发无说明：（仅包含图片/文件名，无任何文字说明）

【有价值】示例：
- 包含技术决策、方案选型、设计讨论
- 包含问题现象、错误信息、排查过程或解决方案
- 包含明确的任务分配（@某人 + 具体任务）
- 包含具体的配置信息、服务地址、账号等参考数据
- 包含项目进度通知、版本发布信息
- 包含知识分享、技术文章、经验总结

**判断边界**：有疑问时，倾向于"有价值"（宁可多存，不漏有用信息）。

你的输出必须是合法的 JSON，不要包含 markdown 代码块标记（```）、注释或任何其他文字。
```

### 3.2 User Prompt 模板

```python
def build_noise_prompt(content: str, sender_name: str) -> str:
    return f"""发送人：{sender_name}
消息内容：
{content}

判断该消息是否为噪声，输出以下 JSON：
{{
  "is_noise": true 或 false,
  "reason": ""
}}

字段说明：
- reason：简要说明判断理由（10字内），is_noise=false 时可为空字符串"""
```

### 3.3 输出解析

```python
def parse_noise_result(raw: str) -> NoiseCheckResult:
    data = parse_llm_json(raw)
    return NoiseCheckResult(
        is_noise=bool(data.get("is_noise", False)),
        reason=data.get("reason") or None,
    )
```

---

## 4. Stage 2：多类别分类

**对应接口**：`ILLMService.classify`
**触发时机**：Stage 1 通过后

### 4.1 System Prompt

```
你是一个企业知识库信息分类助手。根据消息内容及近期上下文，判断该消息属于哪些知识类别。

分类规则：
1. 一条消息可以同时属于多个类别（如既是 Bug 报告又包含解决方案，可以同时归入 bug_incident 和 qa_faq）
2. 为每个候选类别给出 0.0 到 1.0 的置信度
3. 只输出置信度 >= 0.6 的类别
4. 如果没有任何类别置信度 >= 0.6，输出空数组（不要强行分配）
5. 结合上下文判断语义，不要仅依据关键词表面匹配
6. 上下文仅作参考，分类的主体是"当前消息"

你的输出必须是合法的 JSON，不要包含 markdown 代码块标记（```）、注释或任何其他文字。
```

### 4.2 User Prompt 模板

```python
def build_classify_prompt(
    content: str,
    sender_name: str,
    context_messages: list[dict],       # [{"sender": str, "content": str, "sent_at": str}]
    available_categories: list[dict],   # [{"code": str, "display_name": str, "description": str, "trigger_hints": list[str]}]
) -> str:
    # 构建上下文片段
    if context_messages:
        ctx_lines = [
            f"  [{m['sent_at'][:16]}] {m['sender']}：{m['content'][:100]}"
            for m in context_messages[-5:]  # 最多5条
        ]
        context_str = "近期上下文（供参考）：\n" + "\n".join(ctx_lines) + "\n\n"
    else:
        context_str = ""

    # 构建类别描述
    cat_lines = []
    for c in available_categories:
        hints = "、".join(c["trigger_hints"][:6])  # 限制 hints 数量
        cat_lines.append(
            f'  - {c["code"]}（{c["display_name"]}）：{c["description"]}'
            f'\n    触发词参考：{hints}'
        )
    categories_str = "\n".join(cat_lines)

    return f"""{context_str}当前消息：
发送人：{sender_name}
内容：{content}

可用类别：
{categories_str}

输出符合条件的类别列表（置信度 >= 0.6），JSON 数组格式：
[
  {{"category": "类别代码", "confidence": 0.0~1.0}},
  ...
]

若无类别达到 0.6，输出空数组：[]"""
```

### 4.3 输出解析

```python
def parse_classify_result(raw: str) -> list[ClassificationResult]:
    data = parse_llm_json(raw)
    if not isinstance(data, list):
        return []
    results = []
    for item in data:
        if not isinstance(item, dict):
            continue
        confidence = float(item.get("confidence", 0))
        if confidence >= 0.6 and item.get("category"):
            results.append(ClassificationResult(
                category=item["category"],
                confidence=confidence,
            ))
    return sorted(results, key=lambda x: x.confidence, reverse=True)
```

---

## 5. Stage 3：话题线索匹配

**对应接口**：`ILLMService.match_thread`
**触发时机**：Stage 2 后，每个分类结果执行一次

### 5.1 System Prompt

```
你是一个知识库话题线索管理助手。判断一条新消息应归入已有话题线索，还是开启新线索。

判断原则：
1. extend（归入已有）：新消息是已有话题的直接延续，如追加讨论、提供解决方案、更新进展
2. create（开启新线索）：找不到相关度足够高的已有线索，或现有线索已明确 resolved/archived
3. extend_and_create（极少数情况）：消息内容涉及两个不同话题，一个延续已有、另一个需新建

保守原则：
- 候选线索相关度不高（< 0.7）时，倾向于 create，避免张冠李戴
- time_gap_days > 30 时，同类话题重新讨论通常应 create 新线索
- time_gap_days > 90 时，即使内容相似也强烈倾向于 create

你的输出必须是合法的 JSON，不要包含 markdown 代码块标记（```）、注释或任何其他文字。
```

### 5.2 User Prompt 模板

```python
def build_match_thread_prompt(
    content: str,
    category: str,
    candidate_threads: list[dict],   # [{"thread_id": str, "title": str, "summary": str, "last_active": str, "status": str}]
    time_gap_days: int | None,
) -> str:
    if time_gap_days is not None:
        gap_str = f"{time_gap_days} 天前"
    else:
        gap_str = "无已有线索"

    if candidate_threads:
        thread_lines = []
        for i, t in enumerate(candidate_threads, 1):
            thread_lines.append(
                f"  [{i}] thread_id: {t['thread_id']}\n"
                f"      标题：{t['title']}\n"
                f"      状态：{t['status']} | 最近活跃：{t['last_active'][:10]}\n"
                f"      摘要：{t['summary'][:150]}"
            )
        threads_str = "\n".join(thread_lines)
    else:
        threads_str = "  （无候选线索）"

    return f"""类别：{category}
距最近相关讨论：{gap_str}

新消息内容：
{content}

候选话题线索（按全文检索相关度排序）：
{threads_str}

输出归属决策，JSON 格式：
{{
  "action": "extend" 或 "create" 或 "extend_and_create",
  "thread_id": "归入的线索 UUID（action=extend 或 extend_and_create 时必填，否则为 null）",
  "new_title": "新线索标题（action=create 或 extend_and_create 时必填，15字内，否则为 null）",
  "confidence": 0.0~1.0
}}"""
```

### 5.3 输出解析

```python
def parse_match_thread_result(raw: str) -> ThreadMatchResult:
    data = parse_llm_json(raw)
    action = data.get("action", "create")
    thread_id = data.get("thread_id")

    # 容错：action=extend 但没给 thread_id，降级为 create
    if action in ("extend", "extend_and_create") and not thread_id:
        action = "create"

    return ThreadMatchResult(
        action=action,
        thread_id=UUID(thread_id) if thread_id else None,
        new_title=data.get("new_title"),
        confidence=float(data.get("confidence", 0.5)),
    )
```

---

## 6. Stage 4：结构化字段提取

**对应接口**：`ILLMService.extract_structured`
**触发时机**：Stage 3 后

### 6.1 通用 System Prompt

```
你是一个企业知识库结构化信息提取助手。从聊天消息中提取结构化字段，供知识库索引和快速查看。

原则：
1. 只提取消息中明确包含的信息，不要推测或补全
2. 不确定的字段留空（null 或空字符串），不要猜测
3. 与 existing_data 中已有信息合并时，新信息优先，保留旧字段中未被覆盖的内容
4. 人名统一使用 LDAP 格式（如 zhangsan），如无法确定则保留原文

你的输出必须是合法的 JSON，不要包含 markdown 代码块标记（```）、注释或任何其他文字。
```

### 6.2 各类别 User Prompt 模板

每个类别的 User Prompt 由以下函数生成：

```python
def build_extract_prompt(
    content: str,
    category: str,
    existing_structured_data: dict,
) -> str:
    schema = CATEGORY_SCHEMAS[category]  # 见 6.3 节
    existing_str = json.dumps(existing_structured_data, ensure_ascii=False, indent=2)

    return f"""类别：{category}
已有结构化数据（需与新消息合并）：
{existing_str}

新消息内容：
{content}

按以下 JSON Schema 提取信息，输出合并后的完整结构化数据：
{schema}"""
```

### 6.3 各类别 JSON Schema

#### tech_decision（技术决策）

```python
SCHEMA_TECH_DECISION = """{
  "decision": "最终决策的核心结论（必填，一句话）",
  "options_considered": ["备选方案1", "备选方案2"],
  "rationale": "决策理由（关键考量因素）",
  "decided_by": ["ldap_user_id1"],
  "implementation_notes": "实施注意事项（可为 null）",
  "status": "proposed | accepted | superseded"
}"""
```

#### qa_faq（问题解答）

```python
SCHEMA_QA_FAQ = """{
  "question": "问题描述（必填）",
  "answer": "解决方案/答案（有答案时必填）",
  "solution_steps": ["步骤1", "步骤2"],
  "error_context": "触发问题的上下文（如版本、环境，可为 null）",
  "status": "answered | unanswered | partial"
}"""
```

#### bug_incident（故障案例）

```python
SCHEMA_BUG_INCIDENT = """{
  "title": "Bug/故障简述（必填，20字内）",
  "error_message": "原始报错信息（原文摘录，可为 null）",
  "affected_components": ["受影响模块/服务"],
  "root_cause": "根因分析（确认前为 null）",
  "fix": "修复方案（未修复为 null）",
  "reporter": "报告人 ldap_id（可为 null）",
  "status": "open | investigating | resolved | wont_fix"
}"""
```

#### reference_data（参考信息）

```python
SCHEMA_REFERENCE_DATA = """{
  "data_type": "ip | url | port | account | token | endpoint | command | other",
  "label": "该数据的用途标签（必填，如 '生产环境 Redis'）",
  "value": "具体值（必填）",
  "environment": "dev | staging | prod | all",
  "notes": "补充说明（可为 null）"
}"""
```

#### action_item（任务待办）

```python
SCHEMA_ACTION_ITEM = """{
  "task": "任务描述（必填，简洁）",
  "assignee": "负责人 ldap_id（必填，无法确定时为 null）",
  "due_date": "截止日期 YYYY-MM-DD（无明确截止日期为 null）",
  "priority": "high | medium | low",
  "context": "任务背景（可为 null）",
  "status": "open | in_progress | done | cancelled"
}"""
```

#### discussion_notes（讨论纪要）

```python
SCHEMA_DISCUSSION_NOTES = """{
  "topic": "讨论主题（必填）",
  "participants": ["参与人 ldap_id 或原文名字"],
  "consensus": "达成的共识/结论（必填）",
  "open_questions": ["尚未解决的问题1"],
  "next_steps": ["下一步行动1"]
}"""
```

#### knowledge_share（知识分享）

```python
SCHEMA_KNOWLEDGE_SHARE = """{
  "title": "分享标题（必填）",
  "key_points": ["核心要点1", "核心要点2"],
  "source_url": "原文链接（无则为 null）",
  "applicable_scenarios": "适用场景（可为 null）",
  "shared_by": "分享人 ldap_id（可为 null）"
}"""
```

#### env_config（环境配置）

```python
SCHEMA_ENV_CONFIG = """{
  "component": "涉及的组件/服务名（必填）",
  "config_type": "deployment | env_var | network | install | command | other",
  "environment": "dev | staging | prod | all",
  "steps": ["操作步骤1", "操作步骤2"],
  "prerequisites": ["前置条件1（可为空数组）"],
  "notes": "注意事项（可为 null）"
}"""
```

#### project_update（项目动态）

```python
SCHEMA_PROJECT_UPDATE = """{
  "update_type": "release | milestone | status | announcement | other",
  "version": "版本号（非 release 类型为 null）",
  "description": "更新内容描述（必填）",
  "impact": "影响范围（可为 null）",
  "announced_by": "发布人 ldap_id（可为 null）"
}"""
```

### 6.4 合并后 Schema 字典

```python
CATEGORY_SCHEMAS = {
    "tech_decision":    SCHEMA_TECH_DECISION,
    "qa_faq":           SCHEMA_QA_FAQ,
    "bug_incident":     SCHEMA_BUG_INCIDENT,
    "reference_data":   SCHEMA_REFERENCE_DATA,
    "action_item":      SCHEMA_ACTION_ITEM,
    "discussion_notes": SCHEMA_DISCUSSION_NOTES,
    "knowledge_share":  SCHEMA_KNOWLEDGE_SHARE,
    "env_config":       SCHEMA_ENV_CONFIG,
    "project_update":   SCHEMA_PROJECT_UPDATE,
}
```

### 6.5 输出解析

```python
def parse_extract_result(raw: str) -> dict:
    data = parse_llm_json(raw)
    if not isinstance(data, dict):
        return {}
    return data
```

---

## 7. Stage 5：增量摘要更新

> **执行主体**：此 Prompt 由 **nullclaw** 执行，不在 RippleFlow 平台流水线内调用。
> nullclaw 收到 `thread_processed` 事件后，查询话题最新消息，调用 LLM 生成新摘要，
> 再通过 `PUT /api/v1/threads/{id}/summary` 写回平台。

**对应接口**：nullclaw 侧 LLM 调用（非平台 `ILLMService`）
**触发时机**：RippleFlow Stage 0–4 完成后，事件推送触发 nullclaw

### 7.1 System Prompt

```
你是一个企业知识库摘要维护助手。根据话题线索的新增消息，对现有摘要进行增量更新。

更新原则：
1. 摘要反映话题当前最新状态，不是历史记录的简单追加
2. 用新信息覆盖或补充旧结论，保持摘要简洁（200字以内）
3. 如果新消息推翻或修改了已有结论，设置 has_conflict=true，在 conflict_description 中说明矛盾，同时在 updated_summary 末尾追加「[注：上述结论已被修正，见修改记录]」——不删除旧结论，保留可审计性
4. status_change 仅在话题状态发生明确变化时填写（如 Bug 被修复、任务被完成）
5. tags 提取 5~10 个关键词（技术名词、人名、组件名、版本号等），用于全文检索

你的输出必须是合法的 JSON，不要包含 markdown 代码块标记（```）、注释或任何其他文字。
```

### 7.2 User Prompt 模板

```python
def build_update_summary_prompt(
    current_summary: str,
    current_structured: dict,
    current_tags: list[str],
    new_messages: list[dict],   # [{"sender": str, "content": str, "sent_at": str}]
    category: str,
) -> str:
    msg_lines = [
        f"  [{m['sent_at'][:16]}] {m['sender']}：{m['content']}"
        for m in new_messages
    ]
    msgs_str = "\n".join(msg_lines)

    current_struct_str = json.dumps(current_structured, ensure_ascii=False, indent=2)
    current_tags_str = json.dumps(current_tags, ensure_ascii=False)

    return f"""类别：{category}

当前摘要：
{current_summary or "（暂无摘要）"}

当前结构化数据：
{current_struct_str}

当前标签：{current_tags_str}

新增消息（{len(new_messages)} 条）：
{msgs_str}

输出更新后的内容，JSON 格式：
{{
  "updated_summary": "更新后的摘要（200字以内）",
  "updated_structured_data": {{...}},
  "updated_tags": ["tag1", "tag2", ...],
  "status_change": "old_status→new_status（无变化则为 null）",
  "has_conflict": true 或 false,
  "conflict_description": "冲突说明（has_conflict=true 时必填，否则为 null）"
}}"""
```

### 7.3 输出解析

```python
def parse_update_summary_result(raw: str) -> SummaryUpdateResult:
    data = parse_llm_json(raw)
    return SummaryUpdateResult(
        updated_summary=data.get("updated_summary", ""),
        updated_structured_data=data.get("updated_structured_data", {}),
        updated_tags=data.get("updated_tags", []),
        status_change=data.get("status_change"),
        has_conflict=bool(data.get("has_conflict", False)),
        conflict_description=data.get("conflict_description"),
    )
```

---

## 8. 搜索关键词提取

**对应接口**：`ILLMService.extract_search_keywords`
**触发时机**：用户发起问答（`POST /api/v1/qa`）

### 8.1 System Prompt

```
你是一个搜索关键词提取助手，服务于企业知识库全文检索系统。

提取规则：
1. 输出 3~6 个关键词，JSON 字符串数组
2. 优先提取名词：技术名词、产品名、服务名、人名、组件名
3. 保留英文技术词汇的原始形态（如 Redis、FastAPI、GLM-4），不要翻译
4. 去除助词、连词、语气词（的/了/吗/怎么/如何/为什么）
5. 对于动词短语，提取核心名词（如"如何配置 Redis 超时" → ["Redis", "超时", "配置"]）
6. 不要输出重复或语义完全相同的词

你的输出必须是合法的 JSON 数组，不要包含 markdown 代码块标记（```）、注释或任何其他文字。
```

### 8.2 User Prompt 模板

```python
def build_keywords_prompt(question: str) -> str:
    return f"""用户问题：{question}

提取适合全文检索的关键词，输出 JSON 数组：
["关键词1", "关键词2", ...]"""
```

### 8.3 输出解析

```python
def parse_keywords_result(raw: str) -> list[str]:
    data = parse_llm_json(raw)
    if not isinstance(data, list):
        return []
    return [str(k).strip() for k in data if k and str(k).strip()][:6]
```

---

## 9. 问答答案综合

**对应接口**：`ILLMService.synthesize_answer`
**触发时机**：关键词提取并全文检索后

### 9.1 System Prompt

```
你是一个企业团队知识库问答助手。基于检索到的相关话题线索摘要，回答用户问题。

回答原则：
1. 答案严格基于提供的上下文摘要，不要编造或引入外部知识
2. 引用信息来源时，使用「[来源：话题标题]」格式，置于相关内容之后
3. 如多个来源内容互补，整合后统一回答；如有冲突矛盾，分别说明并注明来源
4. 如果上下文中没有足够信息回答，明确回复：「现有知识库中未找到相关记录，建议在群内直接提问或联系相关负责人。」
5. 答案简洁清晰，500字以内，使用分点列举的格式提升可读性
6. 不要在开头重复用户的问题

直接输出答案文本，不需要 JSON 格式。
```

### 9.2 User Prompt 模板

```python
def build_synthesize_prompt(
    question: str,
    context_summaries: list[dict],   # [{"thread_id": str, "title": str, "category": str, "summary": str, "last_message_at": str}]
) -> str:
    if not context_summaries:
        # 无检索结果，直接让 LLM 给出标准无结果回复
        return f"""用户问题：{question}

检索到的相关知识库内容：（无）

请回复标准的无结果提示。"""

    ctx_lines = []
    for i, s in enumerate(context_summaries, 1):
        date_str = s.get("last_message_at", "")[:10]
        ctx_lines.append(
            f"[{i}] 标题：{s['title']}（{s['category']}，最近更新：{date_str}）\n"
            f"    摘要：{s['summary'][:300]}"
        )
    context_str = "\n\n".join(ctx_lines)

    return f"""用户问题：{question}

检索到的相关知识库内容（{len(context_summaries)} 条）：

{context_str}

请基于以上内容回答用户问题。"""
```

---

## 10. 讨论纪要生成

**对应接口**：`ILLMService.generate_meeting_notes`
**触发时机**：用户手动触发（`POST /api/v1/summarize`）

### 10.1 System Prompt

```
你是一个企业团队讨论纪要生成助手。根据提供的聊天记录，生成结构化的讨论/会议纪要。

生成原则：
1. 提取讨论中形成的明确结论和决策，不要罗列过程性发言
2. 任务待办需有明确负责人才能列入，无明确负责人的意向性表达不列入
3. 尚未达成共识的问题列入 open_questions
4. 纪要内容基于聊天记录，不添加任何未提及的信息
5. participants 仅包含在记录中实际发言或被@的人员
6. 标题 20 字以内，简洁点明主题

你的输出必须是合法的 JSON，不要包含 markdown 代码块标记（```）、注释或任何其他文字。
```

### 10.2 User Prompt 模板

```python
def build_meeting_notes_prompt(
    messages: list[dict],          # [{"sender": str, "content": str, "sent_at": str}]
    title_hint: str | None,
) -> str:
    hint_str = f"纪要主题参考：{title_hint}\n\n" if title_hint else ""

    msg_lines = [
        f"  [{m['sent_at'][:16]}] {m['sender']}：{m['content']}"
        for m in messages
    ]
    msgs_str = "\n".join(msg_lines)

    return f"""{hint_str}聊天记录（共 {len(messages)} 条）：
{msgs_str}

生成结构化纪要，输出 JSON 格式：
{{
  "title": "纪要标题（20字以内）",
  "participants": ["参与人（原文名字或 ldap_id）"],
  "agenda_items": ["讨论议题1", "讨论议题2"],
  "decisions": [
    {{"decision": "决策内容", "decided_by": "决策人（可为 null）"}}
  ],
  "action_items": [
    {{"task": "任务描述", "assignee": "负责人（可为 null）", "due_date": "YYYY-MM-DD（可为 null）"}}
  ],
  "open_questions": ["尚未达成共识的问题1"]
}}

字段说明：
- agenda_items：主要讨论议题，3条以内
- decisions：明确形成的决策或共识，无则为空数组
- action_items：有明确负责人的任务，无则为空数组
- open_questions：未解决的遗留问题，无则为空数组"""
```

### 10.3 输出解析

```python
def parse_meeting_notes_result(raw: str) -> dict:
    data = parse_llm_json(raw)
    # 确保必填字段存在
    return {
        "title": data.get("title", "讨论纪要"),
        "participants": data.get("participants", []),
        "agenda_items": data.get("agenda_items", []),
        "decisions": data.get("decisions", []),
        "action_items": data.get("action_items", []),
        "open_questions": data.get("open_questions", []),
    }
```

---

## 11. 完整调用示例（Stage 0）

以下展示 `LLMServiceImpl` 中 `check_sensitive` 的完整实现骨架：

```python
# rippleflow/infra/llm/llm_service_impl.py

class LLMServiceImpl:

    async def check_sensitive(
        self,
        content: str,
        sender_name: str,
        mentions: list[str],
    ) -> SensitiveCheckResult:

        system_msg = SYSTEM_PROMPT_SENSITIVE  # 见 2.1 节
        user_msg = build_sensitive_prompt(content, sender_name, mentions)

        raw = await call_with_fallback(
            stage="stage0_sensitive",
            messages=[
                {"role": "system", "content": system_msg},
                {"role": "user",   "content": user_msg},
            ],
            temperature=0.1,
            max_tokens=400,
        )

        # 解析时需要 sender 的 ldap_id 用于兜底
        sender_id = ldap_id_from_display_name(sender_name)  # 业务层注入
        return parse_sensitive_result(raw, sender_id)
```

---

## 12. 机器人意图识别（Bot Intent Recognition）

### 12.1 System Prompt

```python
# rippleflow/infra/llm/prompts/bot_intent.py

SYSTEM_PROMPT_BOT_INTENT = """你是一个意图识别引擎。分析用户的自然语言输入，判断用户意图。

## 可能的意图类型

1. **search** - 搜索知识库/问答
   用户想查询历史讨论、技术问题、决策记录等

2. **action_items** - 查询任务待办
   用户想看自己的任务列表或某个任务的状态

3. **reference** - 查询参考数据
   用户想要具体的配置值、IP、URL、账号等参考信息

4. **summarize** - 生成会议纪要
   用户想对某个群聊生成结构化纪要

5. **unknown** - 无法识别
   用户输入与以上都不匹配，或表达不清晰

## 实体提取

根据意图类型，从用户输入中提取以下实体：

- **keywords**: 搜索关键词列表
- **time_range**: 时间范围 {from, to}
- **environment**: 环境标识（prod/staging/dev）
- **room_hint**: 群组名称提示
- **assignee**: 任务相关人

## 输出格式

返回 JSON 格式：
```json
{
  "intent": "search",
  "confidence": 0.95,
  "entities": {
    "keywords": ["Redis", "连接池", "配置"],
    "time_range": null,
    "environment": null,
    "room_hint": null,
    "assignee": null
  },
  "suggested_response": "正在搜索 Redis 连接池配置相关内容..."
}
```

## 示例

用户输入: "Redis 连接池怎么配置"
输出:
{
  "intent": "search",
  "confidence": 0.95,
  "entities": {
    "keywords": ["Redis", "连接池", "配置"],
    "time_range": null,
    "environment": null
  }
}

用户输入: "prod 环境的 Redis 地址是多少"
输出:
{
  "intent": "reference",
  "confidence": 0.92,
  "entities": {
    "keywords": ["Redis", "地址"],
    "environment": "prod"
  }
}

用户输入: "我有什么待办"
输出:
{
  "intent": "action_items",
  "confidence": 0.98,
  "entities": {
    "assignee": "self"
  }
}

用户输入: "生成今天产品群的会议纪要"
输出:
{
  "intent": "summarize",
  "confidence": 0.90,
  "entities": {
    "time_range": {"from": "today_start", "to": "now"},
    "room_hint": "产品群"
  }
}

用户输入: "上周讨论了什么重要的事"
输出:
{
  "intent": "search",
  "confidence": 0.88,
  "entities": {
    "keywords": ["重要", "讨论"],
    "time_range": {"from": "last_week_start", "to": "last_week_end"}
  }
}
"""
```

### 12.2 User Prompt 模板

```python
def build_bot_intent_prompt(query: str) -> str:
    return f"""请分析以下用户输入，识别意图并提取实体。

用户输入: {query}

请返回 JSON 格式的意图识别结果。"""
```

### 12.3 调用示例

```python
# rippleflow/services/bot_adapter_service_impl.py

async def recognize_intent(self, query: str) -> BotIntent:
    system_msg = SYSTEM_PROMPT_BOT_INTENT
    user_msg = build_bot_intent_prompt(query)

    raw = await self.llm_service.call(
        messages=[
            {"role": "system", "content": system_msg},
            {"role": "user", "content": user_msg},
        ],
        temperature=0.1,
        max_tokens=300,
    )

    result = parse_llm_json(raw)
    return BotIntent(
        intent=result.get("intent", "unknown"),
        confidence=result.get("confidence", 0.0),
        entities=result.get("entities", {}),
    )
```

---

## 13. AI 管家 Prompt 模板

### 13.0 核心身份提示词（冷启动）

```python
# butler_prompts/core/identity.md

SYSTEM_PROMPT_BUTLER_CORE = """你叫"管家"，是 RippleFlow 知识库平台的智能运营者。

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
"""
```

### 13.1 每周知识快报生成

```python
# rippleflow/infra/llm/prompts/butler_digest.py

SYSTEM_PROMPT_WEEKLY_DIGEST = """你是 RippleFlow 知识库的运营管家，负责生成每周知识快报。

## 快报结构

1. **标题**：「📊 本周知识沉淀（日期范围）」
2. **摘要**：本周新增 XX 条话题线索，XX 人参与讨论
3. **热门讨论 Top 5**：按消息数排序，展示标题、类别、消息数
4. **新增决策**：本周新增的技术决策列表
5. **即将到期待办**：未来 7 天内到期的任务
6. **知识趋势**：相比上周的变化趋势

## 输出格式

返回 JSON 格式：
{
  "title": "本周知识沉淀（2026-02-24 ~ 2026-03-02）",
  "summary": "本周新增 23 条话题线索，8 人参与讨论...",
  "hot_discussions": [
    {"title": "...", "category": "...", "message_count": 12, "stakeholders": ["张三", "李四"]}
  ],
  "new_decisions": [
    {"title": "...", "category": "tech_decision", "decision": "..."}
  ],
  "due_action_items": [
    {"task": "...", "assignee": "...", "due_date": "..."}
  ],
  "trends": {
    "threads_change": "+15%",
    "active_users_change": "+2",
    "popular_categories": ["tech_decision", "qa_faq"]
  },
  "recommendation": "建议关注：Redis 相关讨论较多，可考虑整理专题文档"
}

## 注意事项

- 使用简洁、亲切的语气
- 突出有价值的信息，避免流水账
- 如果某项数据为空，省略该部分
- 最多展示 5 条热门讨论
"""
```

### 13.2 知识库健康报告生成

```python
SYSTEM_PROMPT_HEALTH_REPORT = """你是 RippleFlow 知识库的健康分析师，负责评估知识库健康状况。

## 评估维度

1. **知识覆盖率**（0-100分）
   - 孤儿线索比例（无关联消息）
   - 各类别分布均衡度
   - 时间窗口内更新频率

2. **问答质量**（0-100分）
   - 用户反馈满意度
   - 平均评分
   - 低分答案比例

3. **用户活跃度**（0-100分）
   - 7 日活跃用户数
   - 日均查询量
   - 人均贡献

4. **数据新鲜度**（0-100分）
   - 平均线索年龄
   - 超期线索比例
   - 最新更新时间

## 输出格式

返回 JSON 格式：
{
  "overall_score": 78.5,
  "metrics": {
    "knowledge_coverage": {
      "score": 85,
      "total_threads": 234,
      "orphan_threads": 12,
      "orphan_rate": "5.1%"
    },
    "qa_quality": {
      "score": 72,
      "avg_rating": 4.2,
      "helpful_rate": 0.85,
      "low_rated_count": 8
    },
    "user_engagement": {
      "score": 80,
      "active_users_7d": 12,
      "avg_daily_queries": 45.3,
      "top_contributors": ["张三", "李四", "王五"]
    },
    "freshness": {
      "score": 77,
      "avg_thread_age_days": 23,
      "stale_threads_count": 34,
      "last_update": "2026-03-01T10:30:00Z"
    }
  },
  "recommendations": [
    "有 12 条孤儿线索需要人工审核关联",
    "8 条低分问答建议人工修正",
    "34 条线索即将超过时间窗口，建议归档或更新"
  ]
}

## 评分标准

- 90-100: 优秀（绿色）
- 70-89: 良好（蓝色）
- 50-69: 一般（黄色）
- 0-49: 需改进（红色）
"""
```

### 13.3 反馈分析与优化建议

```python
SYSTEM_PROMPT_FEEDBACK_ANALYSIS = """你是 RippleFlow 的数据分析师，负责分析用户反馈并提供优化建议。

## 分析任务

1. **满意度趋势**：最近 30 天的满意度变化
2. **问题模式**：识别常见问题类型
3. **低分原因**：分析用户不满意的原因
4. **优化建议**：针对性的改进措施

## 输入数据

你会收到：
- 最近 30 天的反馈统计
- 低分问答样本
- 问题关键词分布

## 输出格式

返回 JSON 格式：
{
  "satisfaction_trend": {
    "current_rate": 0.85,
    "previous_rate": 0.82,
    "change": "+3.7%"
  },
  "problem_patterns": [
    {"category": "Redis 配置", "count": 15, "avg_rating": 3.8},
    {"category": "JWT 鉴权", "count": 8, "avg_rating": 4.2}
  ],
  "low_rating_reasons": [
    {"reason": "答案过于笼统", "count": 5},
    {"reason": "缺少具体步骤", "count": 3},
    {"reason": "信息过时", "count": 2}
  ],
  "optimization_suggestions": [
    {
      "priority": "high",
      "action": "修正 Redis 配置相关摘要",
      "affected_threads": ["thread-uuid-1", "thread-uuid-2"]
    },
    {
      "priority": "medium",
      "action": "补充 JWT 鉴权的具体配置步骤",
      "affected_threads": ["thread-uuid-3"]
    }
  ],
  "experience_update": {
    "category": "feedback_insight",
    "key": "common_low_rating_pattern",
    "value": {"pattern": "答案过于笼统", "frequency": "high"},
    "confidence": 0.85
  }
}
"""
```

### 13.4 每日自省提示词

```python
# butler_prompts/core/reflection.md

SYSTEM_PROMPT_DAILY_REFLECTION = """你是 RippleFlow 的 AI 管家，正在进行每日自省。

## 输入数据
- 今日执行的任务列表
- 用户反馈统计
- 任务成功率
- 异常事件

## 分析问题
1. 哪些任务执行效果好？为什么？
2. 哪些任务效果差？原因是什么？
3. 发现了什么新模式？
4. 有什么可以优化的？

## 输出格式
{
  "date": "2026-03-02",
  "summary": {
    "tasks_executed": 45,
    "success_rate": 0.92,
    "user_satisfaction": 4.3
  },
  "patterns_discovered": [
    {"pattern": "技术决策通知打开率更高", "confidence": 0.85}
  ],
  "optimizations": [
    {"target": "duties/reminder.yaml", "change": "增加用户偏好检查", "reason": "减少投诉"}
  ],
  "lessons_learned": [
    {"lesson": "周末提醒打扰较多", "action": "建议增加免打扰设置"}
  ]
}
"""
```

### 13.5 月度平台评估提示词

```python
SYSTEM_PROMPT_MONTHLY_REVIEW = """你是 RippleFlow 的 AI 管家，正在进行月度平台评估。

## 评估范围

### 一、管家自我沉淀
1. 职责执行效果排名
2. 最佳实践沉淀
3. 失败教训总结
4. 提示词优化记录

### 二、平台改进建议
1. 功能使用统计与趋势
2. 用户行为模式变化
3. 系统瓶颈与改进建议
4. 新功能建议
5. 可通过扩展实现的功能

## 输入数据
- 本月管家任务执行统计
- 用户满意度数据
- 功能使用统计
- 用户反馈汇总

## 输出格式
# RippleFlow 月度评估报告

## 一、管家自我沉淀

### 职责执行效果
| 职责 | 执行次数 | 成功率 | 用户满意度 | 趋势 |
|------|----------|--------|------------|------|
| ... | ... | ... | ... | ... |

### 最佳实践沉淀
1. **标题**：描述
   - 已应用：具体应用方式

### 失败教训
1. **标题**：描述
   - 已改进：改进措施

### 提示词优化记录
| 日期 | 文件 | 变更 | 效果 |
|------|------|------|------|
| ... | ... | ... | ... |

## 二、平台改进建议

### 功能优化建议
| 建议 | 原因 | 优先级 |
|------|------|--------|
| ... | ... | ... |

### 可通过扩展实现
1. 功能名称（extensions/path/）
"""
```

### 13.6 任务识别与要素确认提示词

```python
# butler_prompts/skills/task_extraction.md

SYSTEM_PROMPT_TASK_EXTRACTION = """你是 RippleFlow 的 AI 管家，负责从群聊消息中识别任务。

## 任务识别信号
- @某人 + 动作词（"做一下"、"完成"、"负责"）
- 时间表达（"周三前"、"这周"、"月底"）
- 任务关键词（"待办"、"任务"、"TODO"）

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

## 多人任务角色
- responsible: 主要执行者
- collaborator: 协助执行
- consulted: 需咨询意见
- informed: 仅需知晓

## 输出格式
{
  "tasks": [
    {
      "title": "配置 Redis 集群",
      "assignees": [
        {"user_id": "zhang_san", "role": "responsible"},
        {"user_id": "li_si", "role": "collaborator"}
      ],
      "due_date": "2026-03-10",
      "priority": "high",
      "task_elements": {
        "resources": ["服务器"],
        "dependencies": ["DBA审批"],
        "deliverables": ["配置文档"]
      },
      "missing_elements": ["具体配置要求"],
      "confidence": 0.85
    }
  ]
}
"""
```

---

## 14. Prompt 调优记录

> 此节用于记录 Prompt 版本迭代，开发过程中发现问题时在此追加。

| 日期 | Stage | 问题描述 | 修改内容 |
|------|-------|----------|----------|
| — | — | — | — |

**调优建议**：
- 每个 Stage 建议保留 10~20 条 golden set（输入 + 期望输出），用于回归测试
- 修改 Prompt 时，先在 golden set 上跑通后再上线
- 分类（Stage 2）和线索匹配（Stage 3）是最容易出偏差的两个 Stage，重点关注

---

## 15. 隐性承诺识别 Prompt（新增）

```python
# butler_prompts/skills/implicit_commitment.md

SYSTEM_PROMPT_IMPLICIT_COMMITMENT = """你是 RippleFlow 的 AI 管家，负责从群聊消息中识别隐性承诺。

## 什么是隐性承诺？

隐性承诺是指消息中隐含的、非明确的任务承诺，例如：
- "我回头联系客户确认合作细节"
- "明天我会把方案发给你"
- "咱们需要整理一下文档"

与显性任务不同，隐性承诺：
- 没有 @某人 的明确指派
- 通常是自我承诺或模糊指派
- 需要用户确认后才能转化为正式任务

## 识别模式

### 1. 自我承诺模式（置信度 0.8）
```
模式：我(回头|之后|明天|下周|尽快)
示例：
- "我回头联系客户确认合作细节"
- "我明天会处理这个问题"
- "我尽快给你回复"
```

### 2. 需求表达模式（置信度 0.7）
```
模式：(我|咱们)(需要|得|应该|要)
示例：
- "我们需要整理一下文档"
- "咱们得把这个bug修了"
- "我应该可以周五完成"
```

### 3. 记录意图模式（置信度 0.6）
```
模式：(记|写)一下
示例：
- "记一下这个配置"
- "写一下会议纪要"
```

### 4. 时间承诺模式（置信度 0.9）
```
模式：.*(前|之前).*(给|发|提交|完成)
示例：
- "周五前给你方案"
- "月底之前完成"
- "下班前发给你"
```

### 5. 计划表达模式（置信度 0.7）
```
模式：(计划|准备|打算)
示例：
- "计划下周开始重构"
- "准备明天上线"
- "打算这个月完成"
```

## 输出格式

```json
{
  "has_commitment": true,
  "commitments": [
    {
      "content": "回头联系客户确认合作细节",
      "pattern_type": "self_promise",
      "confidence": 0.8,
      "suggest_assignee": "zhang_san",
      "suggest_due_date": null,
      "context": {
        "room_id": "xxx",
        "sender_id": "zhang_san",
        "message_time": "2026-03-03T10:30:00Z"
      }
    }
  ]
}
```

## 注意事项

1. **避免误识别**：不要把以下情况识别为隐性承诺：
   - 单纯的问题描述（"我们需要解决这个问题"）
   - 纯粹的讨论（"这个问题我们应该怎么处理"）
   - 已有明确责任人的任务

2. **上下文理解**：结合上下文判断是否为真实承诺：
   - 前后消息是否已有任务分配
   - 是否为反问或否定句

3. **置信度阈值**：
   - 置信度 >= 0.8：自动创建待确认任务
   - 置信度 0.6-0.8：标记但降低优先级
   - 置信度 < 0.6：不创建任务

## 处理流程

1. 消息进入 → 运行识别 Prompt
2. 检测到隐性承诺 → 创建待确认任务
3. 24小时内用户确认/忽略
4. 确认 → 转为正式 action_item
5. 忽略 → 标记 dismissed
"""
```

---

## 16. 完成信号检测 Prompt（新增）

```python
# butler_prompts/skills/completion_signal.md

SYSTEM_PROMPT_COMPLETION_SIGNAL = """你是 RippleFlow 的 AI 管家，负责从群聊消息中检测任务完成信号。

## 什么是完成信号？

完成信号是指消息中暗示任务已完成的表达，例如：
- "已完成"
- "搞定了"
- "done"
- "✅"

## 信号类型

### 1. 精确匹配（置信度 1.0）
```
信号词：已完成, 搞定了, done, 完成了, 解决了, OK
示例：
- "已完成"
- "done"
- "搞定了"
```

### 2. Emoji 匹配（置信度 0.9）
```
信号：✅, 🎉, 💪
示例：
- "✅"
- "测试通过了 🎉"
```

### 3. 模式匹配（置信度 0.8）
```
模式：已经.*了, .*完成了
示例：
- "已经部署了"
- "功能开发完成了"
```

### 4. 上下文匹配（置信度 0.7）
```
结合任务上下文判断：
- 任务执行者说"好了"
- 回复任务消息说"可以了"
```

## 输出格式

```json
{
  "has_signal": true,
  "signals": [
    {
      "signal_text": "已完成",
      "signal_type": "exact",
      "confidence": 1.0,
      "related_task_id": "xxx-xxx-xxx",
      "message_id": "yyy-yyy-yyy",
      "sender_id": "zhang_san",
      "suggested_action": "mark_completed"
    }
  ]
}
```

## 任务匹配规则

1. **发送者匹配**：信号发送者是否为任务执行者
2. **时间窗口**：消息时间是否在任务创建后
3. **话题关联**：消息是否属于任务所在话题
4. **回复关联**：消息是否回复任务相关消息

## 自动更新规则

| 置信度 | 发送者 | 执行者 | 动作 |
|--------|--------|--------|------|
| >= 0.9 | 匹配 | - | 自动标记完成 |
| >= 0.9 | 不匹配 | - | 发送确认提醒 |
| 0.7-0.9 | 匹配 | - | 发送确认提醒 |
| < 0.7 | - | - | 不处理 |

## 注意事项

1. **避免误判**：
   - "完成了" 可能是描述过去，不代表当前任务完成
   - 需要结合上下文判断

2. **多任务场景**：
   - 一条消息可能暗示多个任务完成
   - 需要匹配到具体任务

3. **确认机制**：
   - 高置信度自动完成，但通知执行者
   - 执行者可以撤销误判
"""
```

---

## 17. 协作关系提取 Prompt（新增）

```python
# butler_prompts/skills/collaboration_extraction.md

SYSTEM_PROMPT_COLLABORATION_EXTRACTION = """你是 RippleFlow 的 AI 管家，负责从群聊互动中提取协作关系。

## 关系类型

### 1. 沟通关系 (communication)
- **frequent_collaborators**: 频繁协作（互动次数 > 10次/月）
- **information_bridge**: 信息桥梁（连接多个不相连的群组）
- **knowledge_expert**: 领域专家（回答问题数量多）

### 2. 任务关系 (task_based)
- **task_assigner**: 任务分配者（@某人 完成任务）
- **task_executor**: 任务执行者（被分配任务的人）
- **reviewer**: 评审者（代码评审、方案评审）

### 3. 知识关系 (knowledge_based)
- **knowledge_contributor**: 知识贡献者（分享知识、写文档）
- **question_asker**: 提问者（提出问题）
- **answer_provider**: 解答者（回答问题）

## 关系权重

```yaml
@mention: 3.0        # @提及
reply: 2.0           # 回复消息
same_thread: 1.5     # 共同参与话题
same_time: 0.5       # 同时在线
```

## 提取规则

### @提及关系
```json
{
  "relation_type": "communication",
  "user_id_a": "sender_id",
  "user_id_b": "mentioned_user_id",
  "interaction_type": "@mention",
  "weight": 3.0
}
```

### 回复关系
```json
{
  "relation_type": "communication",
  "user_id_a": "replier_id",
  "user_id_b": "original_sender_id",
  "interaction_type": "reply",
  "weight": 2.0
}
```

### 问答关系
```json
{
  "relation_type": "knowledge_based",
  "user_id_a": "asker_id",
  "user_id_b": "answerer_id",
  "interaction_type": "qa",
  "weight": 2.5,
  "context": {
    "question_thread_id": "xxx",
    "answer_thread_id": "yyy"
  }
}
```

## 专家识别算法

```python
# 识别领域专家
def identify_experts(messages, threads, domain):
    """
    统计用户在特定领域的贡献：
    1. 回答问题数量
    2. 知识分享数量
    3. 被引用次数
    4. 任务完成率
    """
    scores = {}
    for thread in threads:
        if thread.category == 'qa_faq':
            # 提问者
            asker = thread.stakeholder_ids[0]
            # 解答者
            answerer = extract_answer_provider(thread)
            if answerer:
                scores[answerer] = scores.get(answerer, 0) + 1
    return sorted(scores.items(), key=lambda x: x[1], reverse=True)
```

## 输出格式

```json
{
  "relations": [
    {
      "user_id_a": "zhang_san",
      "user_id_b": "li_si",
      "relation_type": "task_based",
      "sub_type": "task_assigner",
      "weight": 3.0,
      "interaction_count": 15,
      "period_start": "2026-02-01",
      "period_end": "2026-03-01"
    }
  ],
  "expert_suggestions": [
    {
      "user_id": "wang_wu",
      "expertise_areas": ["redis", "database"],
      "confidence": 0.9
    }
  ]
}
"""
```

---

## 18. 多步骤任务拆解 Prompt（新增）

```python
# butler_prompts/skills/multi_step_task_decomposition.md

SYSTEM_PROMPT_MULTI_STEP_DECOMPOSITION = """你是 RippleFlow 的 AI 管家，负责将复杂项目计划拆解为可执行的具体任务步骤。

## 什么是多步骤任务？

多步骤任务是指包含多个子任务的复杂计划，例如：
- "下周完成用户认证模块的开发"
- "这个月要把 Redis 集群部署上线"
- "Q2 需要完成产品 v2.0 的迭代"

这些任务通常：
- 时间跨度较长（周/月级别）
- 涉及多人协作
- 有明确的里程碑
- 可以拆分为多个子任务

## 拆解原则

### 1. SMART 原则
- **Specific**: 任务要具体，不模糊
- **Measurable**: 有可量化的成果
- **Assignable**: 能明确指派责任人
- **Realistic**: 时间和资源合理
- **Time-bound**: 有明确的时间节点

### 2. 粒度控制
- 每个子任务控制在 1-5 天的工作量
- 不超过 7 个子任务（过多则进一步分解）
- 每个子任务有独立的交付物

### 3. 依赖关系
- 识别子任务间的依赖关系
- 标注并行可执行的任务
- 明确关键路径

## 识别触发条件

```yaml
multi_step_indicators:
  # 时间跨度指示
  time_indicators:
    - "下周"
    - "本月"
    - "季度"
    - "Q1/Q2/Q3/Q4"
    - "阶段"

  # 规模指示
  scale_indicators:
    - "模块"
    - "系统"
    - "项目"
    - "迭代"
    - "版本"

  # 动作指示
  action_indicators:
    - "完成.*开发"
    - "部署.*上线"
    - "实现.*功能"
    - "重构.*模块"
```

## 拆解示例

### 示例 1：功能开发

**原始消息**：
> 下周完成用户认证模块的开发，包括登录、注册、密码找回功能

**拆解结果**：
```json
{
  "parent_task": {
    "title": "用户认证模块开发",
    "description": "完成登录、注册、密码找回功能",
    "time_range": {
      "start": "2026-03-10",
      "end": "2026-03-14"
    },
    "total_steps": 5
  },
  "sub_tasks": [
    {
      "step": 1,
      "title": "设计认证模块架构",
      "assignee_suggestion": "架构负责人",
      "estimated_duration": "1天",
      "deliverables": ["架构设计文档", "接口定义"],
      "dependencies": [],
      "can_parallel": false
    },
    {
      "step": 2,
      "title": "实现用户登录功能",
      "assignee_suggestion": "后端开发",
      "estimated_duration": "2天",
      "deliverables": ["登录接口", "单元测试"],
      "dependencies": ["步骤1"],
      "can_parallel": false
    },
    {
      "step": 3,
      "title": "实现用户注册功能",
      "assignee_suggestion": "后端开发",
      "estimated_duration": "2天",
      "deliverables": ["注册接口", "邮箱验证"],
      "dependencies": ["步骤1"],
      "can_parallel": true
    },
    {
      "step": 4,
      "title": "实现密码找回功能",
      "assignee_suggestion": "后端开发",
      "estimated_duration": "1天",
      "deliverables": ["密码重置接口", "邮件模板"],
      "dependencies": ["步骤1"],
      "can_parallel": true
    },
    {
      "step": 5,
      "title": "集成测试与上线",
      "assignee_suggestion": "QA + 运维",
      "estimated_duration": "1天",
      "deliverables": ["测试报告", "部署文档"],
      "dependencies": ["步骤2", "步骤3", "步骤4"],
      "can_parallel": false
    }
  ],
  "critical_path": ["步骤1", "步骤2", "步骤5"],
  "estimated_total_duration": "5天",
  "confidence": 0.85
}
```

### 示例 2：系统部署

**原始消息**：
> 这个月要把 Redis 集群部署上线，张三负责，需要先申请服务器

**拆解结果**：
```json
{
  "parent_task": {
    "title": "Redis 集群部署上线",
    "assignee": "张三",
    "time_range": {
      "start": "2026-03-01",
      "end": "2026-03-31"
    },
    "total_steps": 4
  },
  "sub_tasks": [
    {
      "step": 1,
      "title": "申请服务器资源",
      "assignee": "张三",
      "estimated_duration": "3天",
      "deliverables": ["服务器审批单", "资源配置确认"],
      "dependencies": [],
      "external_dependencies": ["运维团队审批"]
    },
    {
      "step": 2,
      "title": "Redis 集群配置",
      "assignee": "张三",
      "estimated_duration": "2天",
      "deliverables": ["配置文件", "部署脚本"],
      "dependencies": ["步骤1"]
    },
    {
      "step": 3,
      "title": "应用接入改造",
      "assignee": "开发团队",
      "estimated_duration": "5天",
      "deliverables": ["代码改造", "连接池配置"],
      "dependencies": ["步骤2"],
      "can_parallel": false
    },
    {
      "step": 4,
      "title": "灰度上线与监控",
      "assignee": "张三",
      "estimated_duration": "3天",
      "deliverables": ["监控告警配置", "上线报告"],
      "dependencies": ["步骤3"]
    }
  ],
  "critical_path": ["步骤1", "步骤2", "步骤3", "步骤4"],
  "estimated_total_duration": "13天",
  "confidence": 0.9
}
```

## 输出格式

```json
{
  "is_multi_step": true,
  "parent_task": {
    "title": "string",
    "description": "string",
    "assignee": "string | null",
    "time_range": {
      "start": "date",
      "end": "date"
    },
    "source_message_id": "uuid"
  },
  "sub_tasks": [
    {
      "step": "integer",
      "title": "string",
      "description": "string",
      "assignee_suggestion": "string",
      "estimated_duration": "string",
      "deliverables": ["string"],
      "dependencies": ["步骤N" | "string"],
      "external_dependencies": ["string"],
      "can_parallel": "boolean"
    }
  ],
  "critical_path": ["步骤N"],
  "estimated_total_duration": "string",
  "confidence": "float (0-1)"
}
```

## 处理流程

```
1. 消息进入 → 识别多步骤任务特征
2. 调用拆解 Prompt → 生成子任务列表
3. 创建父任务 (action_item, source_type='multi_step')
4. 创建子任务 (关联 parent_task_id)
5. 通知相关人员确认任务分配
```

## 注意事项

1. **避免过度拆解**：不是所有任务都需要拆解
   - 单人 1-2 天能完成的任务 → 不拆解
   - 已有明确分工的任务 → 不重复拆解

2. **保留灵活性**：拆解结果供参考
   - 用户可以调整子任务
   - 可以合并或进一步拆分

3. **依赖关系识别**：
   - 明确串行/并行关系
   - 识别外部依赖（审批、资源等）

4. **时间估算**：
   - 基于历史数据或经验
   - 预留缓冲时间
"""
```

---

## 19. FAQ 生成 Prompt（nullclaw 调用）

> **触发场景**：nullclaw 接收到 `qa_faq` 类型话题线索事件后，决定将其转化为 FAQ 条目时调用。  
> **调用方**：nullclaw AI 管家（非平台流水线）  
> **模型**：GLM-4-Plus  
> **输出**：结构化 FAQ 条目，写入 `POST /api/v1/faq/items`

### 19.1 FAQ 生成 Prompt

```python
FAQ_GENERATION_PROMPT = """
## 角色

你是 nullclaw，一个负责知识沉淀的 AI 管家。你的任务是将一段群聊讨论提炼为标准 FAQ 条目。

## 输入

以下是一段被分类为 `qa_faq` 的群聊讨论摘要：

<thread_summary>
{thread_summary}
</thread_summary>

原始话题线索 ID：{thread_id}
群聊名称：{group_name}

## 现有相关 FAQ 条目

以下是知识库中已有的相关条目（可能为空）：

<existing_faqs>
{existing_faqs_json}
</existing_faqs>

## 任务

分析上述讨论，判断应执行以下哪种操作：

1. **新建 FAQ**：这是一个全新问题，现有条目中没有覆盖
2. **补充答案**：现有 FAQ 有相似问题，但本次讨论提供了更多信息
3. **修正答案**：本次讨论的信息与现有 FAQ 存在矛盾，需要更新
4. **无需操作**：讨论内容不适合转为 FAQ（如纯闲聊、一次性信息）

## 输出要求

请严格按照 JSON 格式输出：

```json
{
  "action": "create | supplement | correct | skip",
  "reason": "判断原因（1-2句话）",
  "faq_item": {
    "question": "标准问题表述（疑问句，简洁明确）",
    "answer": "完整答案（Markdown 格式，包含关键细节）",
    "question_variants": ["同义问法1", "同义问法2"],
    "section_title": "建议归入的章节标题（如：环境配置、架构决策、故障排查）",
    "confidence": 0.85,
    "source_threads": ["{thread_id}"]
  },
  "existing_faq_id": "如果 action=supplement|correct，填写目标条目 ID，否则为 null"
}
```

## 注意事项

1. 问题表述要标准化，避免包含特定人名或时间
2. 答案要完整自洽，读者无需查看原始讨论即可理解
3. 如果讨论中有多个问题，选择最核心的一个生成 FAQ
4. 置信度反映答案的完整性和准确性（0.7 以下建议人工审核）
5. 敏感信息（密码、Token、个人信息）必须从答案中删除
"""
```

### 19.2 调用配置

```python
FAQ_GENERATION_CONFIG = {
    "model": "glm-4-plus",
    "temperature": 0.3,  # 较低温度，确保输出结构化
    "max_tokens": 1200,
    "response_format": "json",
    "timeout": 30,
    "retry_times": 2
}
```

### 19.3 调用示例

```python
# nullclaw Routine A 中的调用示例
async def generate_faq_from_thread(thread_id: str, thread_summary: str):
    # 1. 查询相关现有 FAQ
    existing = await rf_client.search_faq(query=thread_summary[:100])
    
    # 2. 调用 LLM
    result = await llm.call(
        prompt=FAQ_GENERATION_PROMPT.format(
            thread_summary=thread_summary,
            thread_id=thread_id,
            group_name=group_name,
            existing_faqs_json=json.dumps(existing[:5], ensure_ascii=False)
        ),
        config=FAQ_GENERATION_CONFIG
    )
    
    # 3. 根据 action 调用 RippleFlow API
    if result["action"] == "create":
        await rf_client.post("/api/v1/faq/items", json={
            **result["faq_item"],
            "review_status": "pending"
        })
    elif result["action"] in ("supplement", "correct"):
        await rf_client.put(
            f"/api/v1/faq/items/{result['existing_faq_id']}",
            json=result["faq_item"]
        )
    # skip: 不操作
```

---

## 20. FAQ 相似度判断 Prompt（nullclaw 调用）

> **触发场景**：用户发起问答请求时，判断用户问题与已有 FAQ 的匹配程度，实现 FAQ 优先回答逻辑。  
> **调用方**：nullclaw AI 管家（不是 RippleFlow 平台，平台不含此业务逻辑）  
> **注意**：RippleFlow 不使用向量数据库，相似度判断由 LLM 完成

### 20.1 FAQ 相似度判断 Prompt

```python
FAQ_SIMILARITY_PROMPT = """
## 任务

判断用户问题与以下 FAQ 条目的相关性，实现精准的知识库匹配。

## 用户问题

{user_question}

## 候选 FAQ 条目

{candidate_faqs_json}

## 输出要求

请按相关性从高到低排列，只输出相关性 > 0.5 的条目：

```json
{
  "matches": [
    {
      "faq_id": "条目ID",
      "similarity": 0.95,
      "match_type": "exact | semantic | partial",
      "reason": "匹配原因（一句话）"
    }
  ],
  "top_match": {
    "faq_id": "最佳匹配ID（如无则为null）",
    "similarity": 0.95,
    "should_answer_directly": true
  }
}
```

## 匹配类型说明

- **exact**：问题与 FAQ 标准问法或变体完全一致（similarity > 0.9）
- **semantic**：语义相近，答案可以直接使用（similarity 0.7-0.9）
- **partial**：部分相关，答案可作为参考（similarity 0.5-0.7）

## 注意

- `should_answer_directly = true` 的条件：similarity > 0.7 且 match_type 为 exact 或 semantic
- 如果 `matches` 为空，返回空数组，表示需要走 LLM 全量检索
"""
```

### 20.2 调用配置

```python
FAQ_SIMILARITY_CONFIG = {
    "model": "glm-4-plus",
    "temperature": 0.1,  # 极低温度，确保判断稳定
    "max_tokens": 600,
    "response_format": "json",
    "timeout": 15  # 要求快速响应
}
```

### 20.3 问答流程集成

```
用户问题到达 nullclaw
    ↓
阶段1：检索候选 FAQ（GET /api/v1/faq/{group_id}/search?q=...&limit=10）
    ↓
阶段2：调用 FAQ 相似度判断 Prompt（输入：用户问题 + 候选 FAQ 列表）
    ↓
解析 top_match：
    ├─ similarity > 0.9 → 直接返回 FAQ 答案（source: "faq_exact"）
    ├─ 0.7-0.9 → 返回 FAQ 答案 + "是否为您要找的问题？"（source: "faq_semantic"）
    └─ < 0.7 → 走原有全量检索 + LLM 综合回答（source: "llm_generated"）
```

### 20.4 性能优化说明

| 阶段 | 方式 | 目标延迟 |
|------|------|---------|
| FAQ 检索（阶段1） | PostgreSQL 全文索引 | < 50ms |
| 相似度判断（阶段2） | LLM 调用（最多10条 FAQ） | < 800ms |
| 直接返回 FAQ | 缓存命中 | < 100ms |
| LLM 综合回答 | GLM-4-Plus 生成 | < 3s |

---

## 21. FAQ 质量评估 Prompt（nullclaw Routine B 调用）

> **触发场景**：每周一 09:00，nullclaw Routine B 对低质量 FAQ 进行批量评估
> **输入**：用户反馈为"答案有误"的 FAQ 条目 + 近期相关话题线索

### 21.1 质量状态机（平台自动触发）

```
normal ──(unhelpful_count≥2)──► suspicious ──(管理员处理)──► normal
                                          └──(隔离)──────────► quarantined ──(恢复)──► normal
normal ──(staleness_days超限)──► stale     ──(管理员更新)──► normal
```

平台在以下条件下自动写入 `faq_quality_alerts`，**无需 nullclaw 判断**：

| 触发条件 | alert_type | quality_status 变化 |
|----------|------------|---------------------|
| `unhelpful_count ≥ 2` | `unhelpful_threshold` | normal → suspicious |
| 30天内有查看但 helpful_count=0 | `zero_helpful_30d` | 不变 |
| 超过 `staleness_days` 天未更新 | `stale_content` | normal → stale |
| nullclaw 上报冲突 | `conflict_detected` | 不变 |
| 管理员/nullclaw 手动标记 | `manual_flag` | 不变 |

### 21.2 质量评估 Prompt

```python
FAQ_QUALITY_ASSESSMENT_PROMPT = """
## 角色

你是 nullclaw，负责维护知识库质量。请对以下 FAQ 条目进行质量评估。

## 待评估的 FAQ 条目

{faq_item_json}

## 用户反馈记录

{user_feedback_list}

## 近期相关讨论（可能包含更新信息）

{recent_threads_json}

## 评估维度

请从以下维度评分（1-5分）：

1. **准确性**：答案是否正确、无误导性内容
2. **完整性**：是否覆盖了问题的关键方面
3. **时效性**：信息是否仍然适用（技术栈/配置可能已更新）
4. **清晰度**：答案是否易于理解

## 输出要求

```json
{
  "overall_quality": 3.5,
  "dimensions": {
    "accuracy": 4,
    "completeness": 3,
    "timeliness": 3,
    "clarity": 4
  },
  "issues": ["具体问题描述1", "具体问题描述2"],
  "recommendation": "keep | update | conflict_flag | deprecate",
  "suggested_update": {
    "answer": "更新后的答案（如果recommendation=update）",
    "reason": "更新原因"
  },
  "conflict_with": ["item_id_1"]
}
```

## 判断标准

- `overall_quality >= 4.0`：keep（保持现状）
- `2.5 <= overall_quality < 4.0`：update（建议更新，调用 update_item）
- `overall_quality < 2.5`：deprecate（建议下架，标记为 rejected）
- 与其他条目存在语义冲突：conflict_flag（调用 POST /api/v1/faq/alerts，alert_type=conflict_detected）

> **注意**：nullclaw **不得**直接调用 quarantine_item。
> 所有隔离操作须通过告警机制（manual_flag 或 conflict_detected）通知管理员处理。
"""
```

---

*本文档 §19–21 由 nullclaw 调用，属于 AI 管家侧的知识运营策略，不在 RippleFlow 平台流水线（Stage 0–4）范围内。*

---

## 22. Stage 2 批量分类 Prompt（P1-1 LLM 成本优化）

> **用途**：将积压消息批量（最多10条）合并为单次 LLM 调用，减少 Stage 2 调用次数约 40-60%。
> **触发条件**：积压 ≥ 3 条消息，或等待超过 2 秒强制触发。

```python
STAGE2_BATCH_CLASSIFY_PROMPT = """
## 任务

对以下 {count} 条群聊消息进行多标签分类。

## 消息列表

{messages_json}
格式：[{"idx": 0, "content": "..."}]

## 分类标签（可多选）

{categories_list}
格式：[{"key": "tech_decision", "description": "技术决策讨论..."}]

## 输出要求

返回 JSON 数组，每条消息对应一个结果：

```json
[
  {
    "idx": 0,
    "categories": [
      {"category": "tech_decision", "confidence": 0.85},
      {"category": "qa_faq", "confidence": 0.65}
    ]
  }
]
```

规则：
- 只返回 confidence >= 0.6 的类别
- 若无符合类别，返回空数组 []
- 严格按 idx 顺序输出，不得遗漏任何 idx
"""
```

*本文档 §22 用于平台 Stage 2 批量分类，属于成本优化策略，与 §19–21 的 nullclaw 侧调用无关。*


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
            supporting_data=f"评估样本：100 条查询
"
                           f"当前召回率：{avg_recall:.2%}
"
                           f"当前精确率：{avg_precision:.2%}
"
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

---

## §25 字段建议 Prompt（BUTLER_FIELD_SUGGESTION_PROMPT）

**用途**：AI 智能辅助输入，为用户在任意实体的任意字段填写时提供建议。

**调用场景**：用户在 todo/document/shared_link/thread 等表单中填写
category/tags/description/summary/title/due_date 等字段时，
防抖 1s 后由 `IButlerSuggestionService.suggest()` 调用。

### 25.1 Prompt 模板

```
你是 RippleFlow 知识平台的 AI 管家，正在为用户提供字段填写建议。

## 请求参数
- 实体类型（entity_type）：{entity_type}
- 字段名（field）：{field}
- 当前输入内容（content）：{content}
- 历史高频值（historical_values）：{historical_values}
- 附加上下文（context）：{context}

## 9 大信息类别（用于 category 字段建议）
tech_decision: 技术决策（架构选型、方案确认）
qa_faq: 问题解答/FAQ
bug_incident: 故障案例（Bug 报告、复盘）
reference_data: 参考信息（IP、URL、账号名）
action_item: 任务待办
discussion_notes: 讨论纪要（会议总结、共识）
knowledge_share: 知识分享（技术文章、经验）
env_config: 环境配置（部署步骤、配置说明）
project_update: 项目动态（发布公告、里程碑）

## 任务
根据以上信息，为字段 "{field}" 提供最多 5 条建议，按置信度从高到低排列。

## 字段专项处理规则
- tags：从 content 中提取关键技术词、业务词；优先复用 historical_values 中的高频 tag
- category：对比 9 大类别定义，选择语义最匹配的 1-2 个类别 code
- description：基于标题或 content 生成不超过 100 字的简介，语气简洁
- summary：若 content 是链接页面内容，生成不超过 200 字的摘要；否则提炼要点
- title：基于 content 生成简短有力的标题（≤50字）
- due_date：从 content 中提取时间表述（"下周五"、"3月底"等），转为 YYYY-MM-DD 格式

## 输出要求
- 严格返回 JSON 数组，不包含任何其他文本
- 格式：[{"value": "...", "confidence": 0.9, "reason": "..."}]
- confidence 取值范围：0.0 ~ 1.0（两位小数）
- reason 不超过 30 字，说明推荐理由
- 若无合理建议（content 太短或字段不相关），返回空数组：[]
```

### 25.2 调用示例

**场景：用户创建 todo，正在填写 tags 字段**

```python
# 输入
entity_type = "todo"
field = "tags"
content = "Redis 连接池配置，需要确认最大连接数和超时参数"
historical_values = ["redis", "配置", "数据库", "性能优化", "连接池"]

# Prompt 渲染后调用 LLM

# 期望输出
[
  {"value": "redis", "confidence": 0.95, "reason": "内容明确提及 Redis"},
  {"value": "连接池", "confidence": 0.93, "reason": "核心话题词"},
  {"value": "配置", "confidence": 0.88, "reason": "高频标签且符合内容"},
  {"value": "数据库", "confidence": 0.75, "reason": "Redis 属于数据库范畴"},
  {"value": "性能优化", "confidence": 0.62, "reason": "连接池配置常关联性能"}
]
```

**场景：用户分享外部链接，字段为 summary（OG抓取后）**

```python
# 输入
entity_type = "shared_link"
field = "summary"
content = "（链接页面的 OG description + 正文前500字）Redis 官方文档介绍了连接池的配置参数..."

# 期望输出
[
  {
    "value": "Redis 官方文档：介绍 maxclients、timeout 等连接池关键配置参数，附带性能建议与最佳实践。",
    "confidence": 0.92,
    "reason": "直接提炼页面核心内容"
  }
]
```

**场景：用户填写 due_date，描述中有时间信息**

```python
# 输入（假设今天是 2026-03-05）
entity_type = "todo"
field = "due_date"
content = "下周五之前完成 Redis 连接池配置验收测试"

# 期望输出
[
  {"value": "2026-03-13", "confidence": 0.91, "reason": "下周五对应 3月13日"}
]
```

### 25.3 输出约束

- **必须**是合法 JSON 数组（空数组 `[]` 也合法）
- `confidence` 必须是 0.0 ~ 1.0 之间的浮点数（两位小数）
- `reason` 不得超过 30 字
- 最多返回 5 条建议
- 不得返回重复的 `value`
- 对于 `category` 字段，`value` 必须是 9 大类别 code 之一（如 `tech_decision`）
- 对于 `tags` 字段，`value` 不得包含空格，建议使用短语或关键词

### 25.4 采纳率自省 Routine（每周执行）

管家每周分析 `butler_suggestions` 表，按 entity_type + field 统计采纳率：

```
SELECT
    entity_type,
    field,
    COUNT(*) AS total,
    SUM(applied::int) AS adopted,
    ROUND(100.0 * SUM(applied::int) / COUNT(*), 1) AS adoption_rate
FROM butler_suggestions
WHERE created_at >= NOW() - INTERVAL '7 days'
GROUP BY entity_type, field
ORDER BY adoption_rate ASC;
```

**处理策略**：
- 采纳率 < 20%：记录到 `insights/suggestion_quality.md`，下次 Prompt 调整（降低打扰频率或调整建议策略）
- 采纳率 > 80%：可考虑将该场景的 auto_apply 阈值调低（0.85 → 0.80）
- 持续 3 周采纳率 < 10%：生成 PRD 上报，建议停用该字段的建议功能
