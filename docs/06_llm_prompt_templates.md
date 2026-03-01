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
    "stage5_summary":      "glm-4-plus",   # 摘要质量直接影响问答，优先高质量
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

**对应接口**：`ILLMService.update_summary`
**触发时机**：Stage 4 后（或独立的 SummaryUpdateWorker 定时执行）

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
你是一个搜索关键词提取助手，服务于企业知识库全文检索系统（PostgreSQL tsvector）。

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

## 13. AI 管家 Prompt（Weekly Digest & Health Report）

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
