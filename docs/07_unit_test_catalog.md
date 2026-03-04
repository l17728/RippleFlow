# 07 单元测试目录（UT Catalog）

本文档定义 RippleFlow 所有服务层的单元测试用例。
测试目标是 `IXxxService` 的**具体实现类**，通过 mock 隔离外部依赖（DB、LLM、聊天工具 API）。

> 与 `05_e2e_test_catalog.md` 的分工：
> - 单元测试（本文档）：验证业务规则、状态机、权限判断、数据转换逻辑
> - E2E 测试（05）：验证 HTTP 接口、完整请求链路、前端交互

---

## 1. 测试框架与工具约定

### 1.1 工具栈

```python
# pyproject.toml 测试依赖
[tool.pytest.ini_options]
asyncio_mode = "auto"           # 所有 async test 自动处理，无需装饰器

[tool.coverage.run]
source = ["rippleflow/services"]
omit = ["*/interfaces/*"]       # Protocol 定义不计入覆盖率
```

```
pytest >= 8.0
pytest-asyncio >= 0.23
pytest-cov >= 5.0
unittest.mock（标准库，AsyncMock 用于 async 依赖）
freezegun >= 1.4      # 时间冻结，用于测试 24h 限流、JWT 过期
```

### 1.2 Mock 约定

| 需要 Mock 的依赖 | 使用方式 |
|-----------------|---------|
| 数据库仓储（Repository） | `AsyncMock` + 直接设定返回值 |
| `ILLMService` | `AsyncMock`，按用例 patch 返回 `SensitiveCheckResult` 等 |
| `INotificationService` | `AsyncMock`，断言 call_count / call_args |
| `IChatToolService` | `AsyncMock` |
| `IMessageService`（流水线依赖） | `AsyncMock` |
| Redis 队列 | `AsyncMock`（仅断言入队调用，不测 Celery 内部） |
| 当前时间 | `freezegun.freeze_time` |
| JWT 签发/验证 | 直接调用真实逻辑（无外部 IO），不 mock |

### 1.3 命名规范

```
tests/unit/
  conftest.py
  services/
    test_message_service.py
    test_pipeline_service.py
    test_thread_service.py
    test_search_service.py
    test_sensitive_service.py
    test_auth_service.py
    test_notification_service.py
    test_admin_service.py
  llm/
    test_llm_json_parser.py
    test_llm_response_parsers.py
    test_llm_fallback.py
```

测试函数命名：`test_<方法>_<条件>_<期望结果>`
例：`test_submit_decision_one_reject_returns_rejected_status`

### 1.4 覆盖率目标

| 模块 | 目标行覆盖率 |
|------|------------|
| `services/impl/` | ≥ 85% |
| `domain/` (类型、异常) | ≥ 95% |
| `infra/llm/` (Prompt 解析) | ≥ 90% |
| 总体 | ≥ 80% |

---

## 2. 共用 Fixtures（conftest.py）

```python
# tests/unit/conftest.py
import pytest
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4
from rippleflow.domain.types import (
    InboundMessageDTO, SensitiveCheckResult, NoiseCheckResult,
    ClassificationResult, ThreadMatchResult, SummaryUpdateResult,
    UserId, SensitiveDecision, SensitiveDecisionDTO,
)

# ── 固定 UUID，保证测试输出稳定可读 ────────────────────────────────

MSG_ID       = UUID("00000000-0000-0000-0000-000000000001")
THREAD_ID    = UUID("00000000-0000-0000-0000-000000000002")
AUTH_ID      = UUID("00000000-0000-0000-0000-000000000003")
NOTIF_ID     = UUID("00000000-0000-0000-0000-000000000004")

USER_ALICE   = UserId("alice")
USER_BOB     = UserId("bob")
USER_ADMIN   = UserId("admin")

# ── 消息 DTO 工厂 ──────────────────────────────────────────────────

@pytest.fixture
def make_dto():
    """返回一个工厂函数，允许按需覆盖字段。"""
    def _factory(**overrides) -> InboundMessageDTO:
        defaults = dict(
            external_msg_id = "ext-001",
            room_external_id = "room-001",
            sender_external_id = "alice_ext",
            sender_display_name = "Alice",
            content = "我们决定用 Redis 做会话缓存，放弃 JWT 无状态方案。",
            content_type = "text",
            sent_at = datetime(2026, 2, 28, 10, 0, 0, tzinfo=timezone.utc),
            attachments = [],
            mentions = [],
        )
        return InboundMessageDTO(**{**defaults, **overrides})
    return _factory

# ── Mock 服务工厂 ──────────────────────────────────────────────────

@pytest.fixture
def mock_llm():
    svc = AsyncMock()
    # 默认返回值（各测试按需 override）
    svc.check_sensitive.return_value = SensitiveCheckResult(
        is_sensitive=False, sensitive_types=[], sensitive_summary=None, stakeholder_ids=[]
    )
    svc.check_noise.return_value = NoiseCheckResult(is_noise=False)
    svc.classify.return_value = [ClassificationResult(category="tech_decision", confidence=0.92)]
    svc.match_thread.return_value = ThreadMatchResult(
        action="create", thread_id=None, new_title="Redis 会话缓存选型", confidence=0.85
    )
    svc.extract_structured.return_value = {"decision": "使用 Redis", "status": "accepted"}
    svc.update_summary.return_value = SummaryUpdateResult(
        updated_summary="团队决定使用 Redis 做会话缓存。",
        updated_structured_data={},
        updated_tags=["Redis", "会话缓存"],
        status_change=None,
        has_conflict=False,
        conflict_description=None,
    )
    svc.extract_search_keywords.return_value = ["Redis", "会话", "缓存"]
    svc.synthesize_answer.return_value = "根据知识库记录，团队决定使用 Redis 做会话缓存。[来源：Redis 选型决策]"
    return svc

@pytest.fixture
def mock_notify():
    svc = AsyncMock()
    svc.send.return_value = NOTIF_ID
    svc.send_bulk.return_value = [NOTIF_ID]
    return svc

@pytest.fixture
def mock_message_svc():
    svc = AsyncMock()
    svc.get_by_id.return_value = {
        "id": MSG_ID,
        "content": "我们决定用 Redis 做会话缓存。",
        "sender_ldap_id": "alice",
        "sender_display_name": "Alice",
        "room_external_id": "room-001",
        "mentions": [],
        "sent_at": datetime(2026, 2, 28, 10, 0, 0, tzinfo=timezone.utc),
        "processing_status": "pending",
    }
    svc.get_context.return_value = []
    return svc

@pytest.fixture
def mock_thread_svc():
    svc = AsyncMock()
    svc.create.return_value = THREAD_ID
    svc.is_stakeholder.return_value = True
    return svc

@pytest.fixture
def mock_search_svc():
    from rippleflow.domain.types import SearchHit
    svc = AsyncMock()
    svc.find_candidate_threads.return_value = []
    svc.full_text_search.return_value = ([], 0)
    return svc

@pytest.fixture
def mock_chat_tool():
    svc = AsyncMock()
    svc.send_reply.return_value = "chat-msg-001"
    return svc
```

---

## 3. MessageService

### TC-MSG-01：ingest 正常消息，返回 UUID 并入队

```python
# tests/unit/services/test_message_service.py

async def test_ingest_new_message_returns_uuid_and_enqueues(make_dto):
    # Arrange
    repo = AsyncMock()
    repo.find_by_external_id.return_value = None  # 未存在
    repo.save.return_value = MSG_ID
    queue = AsyncMock()
    svc = MessageServiceImpl(repo=repo, queue=queue)

    # Act
    result = await svc.ingest(make_dto())

    # Assert
    assert result == MSG_ID
    repo.save.assert_awaited_once()
    queue.enqueue.assert_awaited_once_with(str(MSG_ID))
```

### TC-MSG-02：ingest 重复 external_msg_id，幂等返回已有 ID，不再入队

```python
async def test_ingest_duplicate_external_id_returns_existing_id(make_dto):
    repo = AsyncMock()
    repo.find_by_external_id.return_value = {"id": MSG_ID}  # 已存在
    queue = AsyncMock()
    svc = MessageServiceImpl(repo=repo, queue=queue)

    result = await svc.ingest(make_dto())

    assert result == MSG_ID
    repo.save.assert_not_awaited()         # 不重复写入
    queue.enqueue.assert_not_awaited()     # 不重复入队
```

### TC-MSG-03：get_context 返回同群组指定消息之前 N 条，按 sent_at 降序

```python
async def test_get_context_returns_n_messages_before_target():
    repo = AsyncMock()
    earlier = [{"id": uuid4(), "sent_at": datetime(2026, 2, 28, 9, i, 0)} for i in range(5)]
    repo.get_before.return_value = earlier
    svc = MessageServiceImpl(repo=repo, queue=AsyncMock())

    result = await svc.get_context("room-001", MSG_ID, limit=5)

    assert len(result) == 5
    repo.get_before.assert_awaited_once_with("room-001", MSG_ID, limit=5)
```

### TC-MSG-04：import_history_batch 跳过 external_msg_id 重复项

```python
async def test_import_history_batch_skips_duplicates(make_dto):
    existing_ids = {"ext-001", "ext-002"}
    repo = AsyncMock()
    repo.get_existing_external_ids.return_value = existing_ids
    repo.bulk_save.return_value = 3  # 实际写入数
    svc = MessageServiceImpl(repo=repo, queue=AsyncMock())

    dtos = [make_dto(external_msg_id=f"ext-{i:03d}") for i in range(5)]
    result = await svc.import_history_batch(dtos, batch_id="batch-1")

    assert result["total"] == 5
    assert result["skipped"] == 2
    assert result["inserted"] == 3
```

### TC-MSG-05：update_status 记录 error 字段

```python
async def test_update_status_saves_error_text():
    repo = AsyncMock()
    svc = MessageServiceImpl(repo=repo, queue=AsyncMock())

    await svc.update_status(
        MSG_ID,
        MessageProcessingStatus.FAILED,
        error="LLM timeout after 3 retries",
    )

    repo.update_status.assert_awaited_once_with(
        MSG_ID,
        "failed",
        error="LLM timeout after 3 retries",
    )
```

---

## 4. ProcessingPipelineService

### TC-PIPE-01：完整流水线，噪声消息在 Stage 1 返回 skipped_noise

```python
# tests/unit/services/test_pipeline_service.py

async def test_run_noise_message_returns_skipped_noise(mock_llm, mock_message_svc):
    mock_llm.check_sensitive.return_value = SensitiveCheckResult(
        is_sensitive=False, sensitive_types=[], sensitive_summary=None, stakeholder_ids=[]
    )
    mock_llm.check_noise.return_value = NoiseCheckResult(is_noise=True, reason="纯感叹")
    svc = ProcessingPipelineServiceImpl(
        message_svc=mock_message_svc, llm=mock_llm,
        thread_svc=AsyncMock(), sensitive_svc=AsyncMock(),
        notify_svc=AsyncMock(), search_svc=AsyncMock(),
    )

    result = await svc.run(MSG_ID)

    assert result == "skipped_noise"
    mock_llm.check_noise.assert_awaited_once()
    mock_llm.classify.assert_not_awaited()     # Stage 2 不执行
    mock_message_svc.update_status.assert_awaited_with(MSG_ID, MessageProcessingStatus.SKIPPED)
```

### TC-PIPE-02：Stage 0 检测到敏感内容，流水线中止，返回 sensitive_pending

```python
async def test_run_sensitive_message_stops_at_stage0(mock_llm, mock_message_svc):
    mock_llm.check_sensitive.return_value = SensitiveCheckResult(
        is_sensitive=True,
        sensitive_types=["hr"],
        sensitive_summary="涉及绩效数据",
        stakeholder_ids=["alice", "bob"],
    )
    sensitive_svc = AsyncMock()
    sensitive_svc.create_authorization.return_value = AUTH_ID
    svc = ProcessingPipelineServiceImpl(
        message_svc=mock_message_svc, llm=mock_llm,
        thread_svc=AsyncMock(), sensitive_svc=sensitive_svc,
        notify_svc=AsyncMock(), search_svc=AsyncMock(),
    )

    result = await svc.run(MSG_ID)

    assert result == "sensitive_pending"
    sensitive_svc.create_authorization.assert_awaited_once()
    mock_llm.check_noise.assert_not_awaited()  # Stage 1 不执行
```

### TC-PIPE-03：完整流水线正常完成，返回 classified，并创建新线索

```python
async def test_run_full_pipeline_creates_new_thread(mock_llm, mock_message_svc):
    mock_llm.match_thread.return_value = ThreadMatchResult(
        action="create", thread_id=None, new_title="Redis 选型", confidence=0.88
    )
    thread_svc = AsyncMock()
    thread_svc.create.return_value = THREAD_ID
    svc = ProcessingPipelineServiceImpl(
        message_svc=mock_message_svc, llm=mock_llm,
        thread_svc=thread_svc, sensitive_svc=AsyncMock(),
        notify_svc=AsyncMock(), search_svc=AsyncMock(),
    )

    result = await svc.run(MSG_ID)

    assert result == "classified"
    thread_svc.create.assert_awaited_once()
    thread_svc.extend.assert_not_awaited()
```

### TC-PIPE-04：Stage 3 返回 extend，消息关联到已有线索

```python
async def test_run_pipeline_extends_existing_thread(mock_llm, mock_message_svc):
    mock_llm.match_thread.return_value = ThreadMatchResult(
        action="extend", thread_id=THREAD_ID, new_title=None, confidence=0.91
    )
    thread_svc = AsyncMock()
    svc = ProcessingPipelineServiceImpl(
        message_svc=mock_message_svc, llm=mock_llm,
        thread_svc=thread_svc, sensitive_svc=AsyncMock(),
        notify_svc=AsyncMock(), search_svc=AsyncMock(),
    )

    await svc.run(MSG_ID)

    thread_svc.extend.assert_awaited_once()
    thread_svc.create.assert_not_awaited()
```

### TC-PIPE-05：Stage 2 分类结果为空（全低置信度），流水线跳过后续阶段

```python
async def test_run_no_category_above_threshold_skips_downstream(mock_llm, mock_message_svc):
    mock_llm.classify.return_value = []  # 无类别达到 0.6
    thread_svc = AsyncMock()
    svc = ProcessingPipelineServiceImpl(
        message_svc=mock_message_svc, llm=mock_llm,
        thread_svc=thread_svc, sensitive_svc=AsyncMock(),
        notify_svc=AsyncMock(), search_svc=AsyncMock(),
    )

    result = await svc.run(MSG_ID)

    # 无法分类时标记为 skipped，不创建线索
    assert result == "skipped_noise"
    thread_svc.create.assert_not_awaited()
    thread_svc.extend.assert_not_awaited()
```

### TC-PIPE-06：摘要更新检测到冲突，通知当事人（nullclaw 侧逻辑）

> **注意**：Stage 5 摘要更新已移交 nullclaw，本用例测试平台侧的冲突通知触发（`notify_svc.send_bulk`），
> 实际摘要更新决策由 nullclaw 做出，平台只负责存储更新结果和发送通知。

```python
async def test_stage5_conflict_notifies_stakeholders(mock_llm, mock_message_svc):
    mock_llm.update_summary.return_value = SummaryUpdateResult(
        updated_summary="旧结论已被推翻，现改用 Memcached。",
        updated_structured_data={},
        updated_tags=["Memcached"],
        status_change=None,
        has_conflict=True,
        conflict_description="原决策使用 Redis，新消息改为 Memcached",
    )
    thread_repo = AsyncMock()
    thread_repo.get_by_id.return_value = {
        "id": THREAD_ID,
        "summary": "使用 Redis",
        "stakeholder_ids": ["alice", "bob"],
        "structured_data": {},
        "tags": ["Redis"],
    }
    notify_svc = AsyncMock()
    svc = ProcessingPipelineServiceImpl(
        message_svc=mock_message_svc, llm=mock_llm,
        thread_svc=AsyncMock(), sensitive_svc=AsyncMock(),
        notify_svc=notify_svc, search_svc=AsyncMock(),
        thread_repo=thread_repo,
    )

    await svc.stage5_update_summary(THREAD_ID, MSG_ID)

    # 冲突时通知所有当事人
    notify_svc.send_bulk.assert_awaited_once()
    call_kwargs = notify_svc.send_bulk.call_args
    recipients = call_kwargs.kwargs.get("recipient_ids") or call_kwargs.args[0]
    assert len(recipients) == 2
```

### TC-PIPE-07：LLM 调用抛出异常，流水线返回 failed，不影响其他消息

```python
async def test_run_llm_error_returns_failed_status(mock_llm, mock_message_svc):
    from rippleflow.domain.exceptions import LLMServiceError
    mock_llm.check_sensitive.side_effect = LLMServiceError("all models unavailable")
    svc = ProcessingPipelineServiceImpl(
        message_svc=mock_message_svc, llm=mock_llm,
        thread_svc=AsyncMock(), sensitive_svc=AsyncMock(),
        notify_svc=AsyncMock(), search_svc=AsyncMock(),
    )

    result = await svc.run(MSG_ID)

    assert result == "failed"
    mock_message_svc.update_status.assert_awaited_with(
        MSG_ID,
        MessageProcessingStatus.FAILED,
        error=pytest.approx(mock_llm.check_sensitive.side_effect.args[0], rel=0),
    )
```

---

## 5. ThreadService

### TC-THREAD-01：当事人修改摘要，触发 SyncToChatWorker

```python
# tests/unit/services/test_thread_service.py

async def test_apply_modification_by_stakeholder_enqueues_sync():
    repo = AsyncMock()
    repo.get_by_id.return_value = {
        "id": THREAD_ID,
        "summary": "旧摘要",
        "stakeholder_ids": ["alice"],
    }
    sync_queue = AsyncMock()
    svc = ThreadServiceImpl(repo=repo, sync_queue=sync_queue)

    dto = ThreadModificationDTO(
        field_modified="summary",
        new_value="新摘要：已确认使用 Redis。",
        reason="更新了正式决策",
    )
    await svc.apply_modification(THREAD_ID, USER_ALICE, dto)

    repo.save_modification.assert_awaited_once()
    repo.update_summary.assert_awaited_once_with(THREAD_ID, "新摘要：已确认使用 Redis。")
    sync_queue.enqueue.assert_awaited_once_with(str(THREAD_ID))
```

### TC-THREAD-02：非当事人修改，抛 ForbiddenError

```python
async def test_apply_modification_by_non_stakeholder_raises_forbidden():
    from rippleflow.domain.exceptions import ForbiddenError
    repo = AsyncMock()
    repo.get_by_id.return_value = {
        "id": THREAD_ID,
        "summary": "旧摘要",
        "stakeholder_ids": ["alice"],  # bob 不在其中
    }
    svc = ThreadServiceImpl(repo=repo, sync_queue=AsyncMock())

    with pytest.raises(ForbiddenError):
        await svc.apply_modification(
            THREAD_ID,
            USER_BOB,
            ThreadModificationDTO(field_modified="summary", new_value="x", reason="y"),
        )
```

### TC-THREAD-03：list_threads 时间窗口过滤，action_item 只返回 30 天内

```python
async def test_list_threads_filters_by_category_time_window():
    from datetime import timedelta
    now = datetime(2026, 2, 28, tzinfo=timezone.utc)
    old_thread = {"id": uuid4(), "category": "action_item", "last_message_at": now - timedelta(days=45)}
    new_thread = {"id": uuid4(), "category": "action_item", "last_message_at": now - timedelta(days=10)}

    repo = AsyncMock()
    repo.list_with_window.return_value = ([new_thread], 1)
    cat_repo = AsyncMock()
    cat_repo.get_window_days.return_value = 30  # action_item = 30 天

    svc = ThreadServiceImpl(repo=repo, cat_repo=cat_repo, sync_queue=AsyncMock())
    items, total = await svc.list_threads(category="action_item")

    assert total == 1
    # 验证传入的时间窗口参数
    call_args = repo.list_with_window.call_args
    window_days = call_args.kwargs.get("window_days") or call_args.args[2]
    assert window_days == 30
```

### TC-THREAD-04：ignore_window=True 时，tech_decision 不受永久有效限制过滤

```python
async def test_list_threads_ignores_window_when_flag_set():
    repo = AsyncMock()
    repo.list_all.return_value = ([{"id": uuid4(), "category": "tech_decision"}], 1)
    svc = ThreadServiceImpl(repo=repo, cat_repo=AsyncMock(), sync_queue=AsyncMock())

    items, total = await svc.list_threads(category="tech_decision", ignore_window=True)

    repo.list_all.assert_awaited_once()
    repo.list_with_window.assert_not_awaited()
```

### TC-THREAD-05：get_by_id 填充 is_stakeholder 标志

```python
async def test_get_by_id_sets_is_stakeholder_for_current_user():
    repo = AsyncMock()
    repo.get_by_id.return_value = {
        "id": THREAD_ID,
        "title": "Redis 选型",
        "stakeholder_ids": ["alice", "charlie"],
    }
    svc = ThreadServiceImpl(repo=repo, cat_repo=AsyncMock(), sync_queue=AsyncMock())

    result = await svc.get_by_id(THREAD_ID, current_user=USER_ALICE)

    assert result["is_stakeholder"] is True

    result2 = await svc.get_by_id(THREAD_ID, current_user=USER_BOB)
    assert result2["is_stakeholder"] is False
```

---

## 6. SearchService

### TC-SEARCH-01：answer_question 整合 LLM 关键词提取和答案综合

```python
# tests/unit/services/test_search_service.py

async def test_answer_question_calls_keywords_then_search_then_synthesize(mock_llm):
    from rippleflow.domain.types import SearchHit
    hits = [
        SearchHit(
            thread_id=THREAD_ID, title="Redis 选型决策",
            category="tech_decision", summary_excerpt="使用 Redis",
            tags=["Redis"], last_message_at=None, rank=0.9,
        )
    ]
    search_repo = AsyncMock()
    search_repo.full_text_search.return_value = (hits, 1)
    mock_llm.extract_search_keywords.return_value = ["Redis", "选型"]
    mock_llm.synthesize_answer.return_value = "答案：使用 Redis。"

    svc = SearchServiceImpl(repo=search_repo, llm=mock_llm)
    result = await svc.answer_question("Redis 选型决策是什么")

    assert result.answer == "答案：使用 Redis。"
    assert len(result.sources) == 1
    assert result.keywords_used == ["Redis", "选型"]
    assert result.no_result is False
    mock_llm.extract_search_keywords.assert_awaited_once_with("Redis 选型决策是什么")
    mock_llm.synthesize_answer.assert_awaited_once()
```

### TC-SEARCH-02：全文检索无结果，返回 no_result=True，不调用 synthesize_answer

```python
async def test_answer_question_no_results_returns_no_result_flag(mock_llm):
    search_repo = AsyncMock()
    search_repo.full_text_search.return_value = ([], 0)
    mock_llm.extract_search_keywords.return_value = ["Redis"]

    svc = SearchServiceImpl(repo=search_repo, llm=mock_llm)
    result = await svc.answer_question("Redis 怎么配置")

    assert result.no_result is True
    assert result.answer == ""
    mock_llm.synthesize_answer.assert_not_awaited()
```

### TC-SEARCH-03：find_candidate_threads 传入正确的 category 和时间窗口

```python
async def test_find_candidate_threads_uses_category_window():
    search_repo = AsyncMock()
    search_repo.search_in_category.return_value = []
    cat_repo = AsyncMock()
    cat_repo.get_window_days.return_value = 90

    svc = SearchServiceImpl(repo=search_repo, llm=AsyncMock(), cat_repo=cat_repo)
    await svc.find_candidate_threads("Redis 超时", "qa_faq", limit=5)

    search_repo.search_in_category.assert_awaited_once()
    call_kwargs = search_repo.search_in_category.call_args.kwargs
    assert call_kwargs["category"] == "qa_faq"
    assert call_kwargs["window_days"] == 90
    assert call_kwargs["limit"] == 5
```

---

## 7. SensitiveService

这是业务规则最密集的服务，重点测试授权状态机。

### TC-SENS-01：create_authorization 为每位当事人创建 pending 记录，并推送通知

```python
# tests/unit/services/test_sensitive_service.py

async def test_create_authorization_sets_all_decisions_pending(mock_notify):
    repo = AsyncMock()
    repo.create.return_value = AUTH_ID
    svc = SensitiveServiceImpl(repo=repo, notify_svc=mock_notify, msg_queue=AsyncMock())

    check_result = SensitiveCheckResult(
        is_sensitive=True,
        sensitive_types=["hr"],
        sensitive_summary="涉及绩效",
        stakeholder_ids=["alice", "bob"],
    )
    auth_id = await svc.create_authorization(MSG_ID, check_result)

    assert auth_id == AUTH_ID
    saved = repo.create.call_args.kwargs
    assert saved["decisions"] == {
        "alice": {"status": "pending", "decided_at": None, "note": None},
        "bob":   {"status": "pending", "decided_at": None, "note": None},
    }
    # 通知两位当事人
    mock_notify.send_bulk.assert_awaited_once()
    recipients = mock_notify.send_bulk.call_args.args[0]  # 或 kwargs
    assert set(u.value for u in recipients) == {"alice", "bob"}
```

### TC-SENS-02：所有当事人授权后，overall_status 变为 authorized，消息重入队列

```python
async def test_submit_decision_all_authorized_triggers_requeue(mock_notify):
    repo = AsyncMock()
    repo.get_by_id.return_value = {
        "id": AUTH_ID,
        "message_id": MSG_ID,
        "decisions": {
            "alice": {"status": "pending"},
            "bob":   {"status": "authorize"},  # bob 已授权
        },
        "overall_status": "pending",
        "last_nudge_at": None,
    }
    repo.update_decision.return_value = None
    msg_queue = AsyncMock()
    svc = SensitiveServiceImpl(repo=repo, notify_svc=mock_notify, msg_queue=msg_queue)

    result = await svc.submit_decision(
        AUTH_ID,
        USER_ALICE,
        SensitiveDecisionDTO(decision=SensitiveDecision.AUTHORIZE),
    )

    assert result["overall_status"] == "authorized"
    assert result["pending_count"] == 0
    msg_queue.enqueue.assert_awaited_once_with(str(MSG_ID))
```

### TC-SENS-03：任一当事人拒绝，overall_status 立即变为 rejected，消息永不入队

```python
async def test_submit_decision_one_reject_returns_rejected_never_requeues(mock_notify):
    repo = AsyncMock()
    repo.get_by_id.return_value = {
        "id": AUTH_ID,
        "message_id": MSG_ID,
        "decisions": {
            "alice": {"status": "pending"},
            "bob":   {"status": "authorize"},
        },
        "overall_status": "pending",
        "last_nudge_at": None,
    }
    msg_queue = AsyncMock()
    svc = SensitiveServiceImpl(repo=repo, notify_svc=mock_notify, msg_queue=msg_queue)

    result = await svc.submit_decision(
        AUTH_ID,
        USER_ALICE,
        SensitiveDecisionDTO(decision=SensitiveDecision.REJECT, note="不同意公开"),
    )

    assert result["overall_status"] == "rejected"
    msg_queue.enqueue.assert_not_awaited()
```

### TC-SENS-04：已拒绝的授权再次提交，抛 ConflictError（最终态不可更改）

```python
async def test_submit_decision_after_reject_raises_conflict():
    from rippleflow.domain.exceptions import ConflictError
    repo = AsyncMock()
    repo.get_by_id.return_value = {
        "id": AUTH_ID,
        "message_id": MSG_ID,
        "decisions": {"alice": {"status": "reject"}},
        "overall_status": "rejected",
        "last_nudge_at": None,
    }
    svc = SensitiveServiceImpl(repo=repo, notify_svc=AsyncMock(), msg_queue=AsyncMock())

    with pytest.raises(ConflictError, match="已拒绝"):
        await svc.submit_decision(
            AUTH_ID,
            USER_ALICE,
            SensitiveDecisionDTO(decision=SensitiveDecision.AUTHORIZE),
        )
```

### TC-SENS-05：nudge 在 24 小时内重复触发，抛 TooManyRequestsError

```python
from freezegun import freeze_time

async def test_nudge_within_24h_raises_too_many_requests():
    from rippleflow.domain.exceptions import TooManyRequestsError
    repo = AsyncMock()
    repo.get_by_id.return_value = {
        "id": AUTH_ID,
        "decisions": {"alice": {"status": "pending"}, "bob": {"status": "authorize"}},
        "overall_status": "pending",
        "last_nudge_at": datetime(2026, 2, 28, 9, 0, 0, tzinfo=timezone.utc),
    }
    svc = SensitiveServiceImpl(repo=repo, notify_svc=AsyncMock(), msg_queue=AsyncMock())

    with freeze_time("2026-02-28 20:00:00"):  # 11 小时后，仍在 24h 内
        with pytest.raises(TooManyRequestsError, match="24 小时"):
            await svc.nudge_stakeholders(AUTH_ID, USER_BOB)
```

### TC-SENS-06：nudge 超过 24 小时后可再次触发，仅通知未表态者

```python
async def test_nudge_after_24h_notifies_only_pending_stakeholders():
    repo = AsyncMock()
    repo.get_by_id.return_value = {
        "id": AUTH_ID,
        "decisions": {
            "alice": {"status": "pending"},
            "bob":   {"status": "authorize"},  # bob 已授权，不再提醒
            "carol": {"status": "pending"},
        },
        "overall_status": "pending",
        "last_nudge_at": datetime(2026, 2, 27, 8, 0, 0, tzinfo=timezone.utc),  # 昨天
    }
    notify_svc = AsyncMock()
    notify_svc.send_bulk.return_value = [uuid4(), uuid4()]
    svc = SensitiveServiceImpl(repo=repo, notify_svc=notify_svc, msg_queue=AsyncMock())

    with freeze_time("2026-02-28 10:00:00"):  # 26 小时后
        count = await svc.nudge_stakeholders(AUTH_ID, USER_ALICE)

    assert count == 2  # alice + carol
    recipients = notify_svc.send_bulk.call_args.args[0]
    assert set(u.value for u in recipients) == {"alice", "carol"}
```

### TC-SENS-07：send_daily_reminders 按提醒节奏发送，跳过过早的记录

```python
async def test_send_daily_reminders_respects_schedule():
    # Arrange：三条记录，分别在 1/2/8 天前创建，提醒节奏 1/3/7/14...
    now = datetime(2026, 2, 28, tzinfo=timezone.utc)
    pending_auths = [
        {"id": uuid4(), "decisions": {"alice": {"status": "pending"}},
         "created_at": now - timedelta(days=1),  "reminder_count": 0},  # 应提醒（第1天）
        {"id": uuid4(), "decisions": {"bob":   {"status": "pending"}},
         "created_at": now - timedelta(days=2),  "reminder_count": 1},  # 不应提醒（第3天才到）
        {"id": uuid4(), "decisions": {"carol": {"status": "pending"}},
         "created_at": now - timedelta(days=8),  "reminder_count": 2},  # 应提醒（7天节奏）
    ]
    repo = AsyncMock()
    repo.get_all_pending.return_value = pending_auths
    notify_svc = AsyncMock()
    notify_svc.send_bulk.return_value = []
    svc = SensitiveServiceImpl(repo=repo, notify_svc=notify_svc, msg_queue=AsyncMock())

    with freeze_time("2026-02-28"):
        result = await svc.send_daily_reminders()

    assert notify_svc.send_bulk.call_count == 2   # 两条记录触发提醒
    assert result["notified_users"] >= 2
    assert result["total_pending"] == 3
```

---

## 8. AuthService

### TC-AUTH-01：verify_jwt 正常 Token，返回正确 payload

```python
# tests/unit/services/test_auth_service.py

def test_verify_jwt_valid_token_returns_payload():
    svc = AuthServiceImpl(secret="test-secret", algorithm="HS256", ttl_hours=24)
    payload = {"user_id": "alice", "display_name": "Alice", "role": "member"}
    token = svc.issue_jwt(payload)

    result = svc.verify_jwt(token)

    assert result["user_id"] == "alice"
    assert result["role"] == "member"
```

### TC-AUTH-02：verify_jwt 过期 Token，抛 TokenExpiredError

```python
def test_verify_jwt_expired_token_raises_token_expired():
    from rippleflow.domain.exceptions import TokenExpiredError
    svc = AuthServiceImpl(secret="test-secret", algorithm="HS256", ttl_hours=1)
    payload = {"user_id": "alice", "role": "member"}

    with freeze_time("2026-02-27 10:00:00"):
        token = svc.issue_jwt(payload)

    with freeze_time("2026-02-28 12:00:00"):  # 26 小时后
        with pytest.raises(TokenExpiredError):
            svc.verify_jwt(token)
```

### TC-AUTH-03：verify_jwt 篡改签名，抛 InvalidTokenError

```python
def test_verify_jwt_tampered_token_raises_invalid():
    from rippleflow.domain.exceptions import InvalidTokenError
    svc = AuthServiceImpl(secret="test-secret", algorithm="HS256", ttl_hours=24)
    token = svc.issue_jwt({"user_id": "alice", "role": "member"})
    tampered = token[:-4] + "xxxx"

    with pytest.raises(InvalidTokenError):
        svc.verify_jwt(tampered)
```

### TC-AUTH-04：check_whitelist 用户不在白名单，抛 ForbiddenError

```python
async def test_check_whitelist_missing_user_raises_forbidden():
    from rippleflow.domain.exceptions import ForbiddenError
    repo = AsyncMock()
    repo.get_by_ldap_id.return_value = None
    svc = AuthServiceImpl(whitelist_repo=repo, secret="s", algorithm="HS256", ttl_hours=24)

    with pytest.raises(ForbiddenError, match="白名单"):
        await svc.check_whitelist("unknown_user")
```

### TC-AUTH-05：check_whitelist 用户 is_active=False（已离职），抛 ForbiddenError

```python
async def test_check_whitelist_inactive_user_raises_forbidden():
    from rippleflow.domain.exceptions import ForbiddenError
    repo = AsyncMock()
    repo.get_by_ldap_id.return_value = {
        "ldap_user_id": "alice", "role": "member", "is_active": False
    }
    svc = AuthServiceImpl(whitelist_repo=repo, secret="s", algorithm="HS256", ttl_hours=24)

    with pytest.raises(ForbiddenError, match="已停用"):
        await svc.check_whitelist("alice")
```

### TC-AUTH-06：get_current_user 组合验证 JWT 和白名单

```python
async def test_get_current_user_returns_combined_info():
    repo = AsyncMock()
    repo.get_by_ldap_id.return_value = {
        "ldap_user_id": "alice", "display_name": "Alice", "role": "admin", "is_active": True
    }
    svc = AuthServiceImpl(whitelist_repo=repo, secret="test-secret", algorithm="HS256", ttl_hours=24)
    token = svc.issue_jwt({"user_id": "alice", "display_name": "Alice", "role": "admin"})

    result = await svc.get_current_user(token)

    assert result["user_id"] == "alice"
    assert result["role"] == "admin"
```

---

## 9. LLMService（Prompt 解析层）

这组测试覆盖 `infra/llm/` 目录，不需要真实 API 调用，全部用 mock 替换网络层。

### TC-LLM-01：parse_llm_json 正常 JSON 字符串

```python
# tests/unit/llm/test_llm_json_parser.py
from rippleflow.infra.llm.json_parser import parse_llm_json

def test_parse_llm_json_clean_object():
    raw = '{"is_noise": false, "reason": ""}'
    result = parse_llm_json(raw)
    assert result == {"is_noise": False, "reason": ""}

def test_parse_llm_json_clean_array():
    raw = '[{"category": "tech_decision", "confidence": 0.92}]'
    result = parse_llm_json(raw)
    assert result[0]["category"] == "tech_decision"
```

### TC-LLM-02：parse_llm_json 去除 markdown 代码块包装

```python
def test_parse_llm_json_strips_markdown_code_fence():
    raw = '```json\n{"is_noise": true}\n```'
    result = parse_llm_json(raw)
    assert result["is_noise"] is True

def test_parse_llm_json_strips_code_fence_without_language():
    raw = '```\n{"key": "value"}\n```'
    result = parse_llm_json(raw)
    assert result["key"] == "value"
```

### TC-LLM-03：parse_llm_json 提取前置说明文字后的 JSON

```python
def test_parse_llm_json_extracts_json_after_preamble():
    raw = '好的，以下是分析结果：\n\n{"is_sensitive": false, "sensitive_types": []}'
    result = parse_llm_json(raw)
    assert result["is_sensitive"] is False
```

### TC-LLM-04：parse_llm_json 无法解析时抛 ValueError

```python
def test_parse_llm_json_raises_on_unparseable():
    with pytest.raises(ValueError, match="无法解析"):
        parse_llm_json("这不是 JSON 内容")
```

### TC-LLM-05：parse_sensitive_result 兜底追加 sender_id

```python
from rippleflow.infra.llm.response_parsers import parse_sensitive_result

def test_parse_sensitive_result_adds_sender_if_missing():
    raw = '{"is_sensitive": true, "sensitive_types": ["hr"], "sensitive_summary": "涉及绩效", "stakeholder_ids": ["bob"]}'
    result = parse_sensitive_result(raw, sender_id="alice")
    assert "alice" in result.stakeholder_ids
    assert "bob" in result.stakeholder_ids

def test_parse_sensitive_result_not_sensitive_empty_lists():
    raw = '{"is_sensitive": false, "sensitive_types": [], "sensitive_summary": "", "stakeholder_ids": []}'
    result = parse_sensitive_result(raw, sender_id="alice")
    assert result.is_sensitive is False
    assert result.stakeholder_ids == []
```

### TC-LLM-06：parse_classify_result 过滤低置信度

```python
from rippleflow.infra.llm.response_parsers import parse_classify_result

def test_parse_classify_result_filters_below_threshold():
    raw = '[{"category": "tech_decision", "confidence": 0.92}, {"category": "qa_faq", "confidence": 0.45}]'
    result = parse_classify_result(raw)
    assert len(result) == 1
    assert result[0].category == "tech_decision"

def test_parse_classify_result_empty_array():
    result = parse_classify_result("[]")
    assert result == []

def test_parse_classify_result_returns_sorted_by_confidence():
    raw = '[{"category": "qa_faq", "confidence": 0.75}, {"category": "tech_decision", "confidence": 0.95}]'
    result = parse_classify_result(raw)
    assert result[0].category == "tech_decision"  # 高置信度排前
```

### TC-LLM-07：parse_match_thread_result extend 缺少 thread_id，降级为 create

```python
from rippleflow.infra.llm.response_parsers import parse_match_thread_result

def test_parse_match_thread_result_extend_without_thread_id_fallbacks_to_create():
    raw = '{"action": "extend", "thread_id": null, "new_title": null, "confidence": 0.8}'
    result = parse_match_thread_result(raw)
    assert result.action == "create"  # 降级
    assert result.thread_id is None
```

### TC-LLM-08：call_with_fallback 首选模型失败，自动切换到次级模型

```python
# tests/unit/llm/test_llm_fallback.py
from unittest.mock import AsyncMock, patch

async def test_call_with_fallback_switches_to_secondary_model():
    call_count = {"glm-4-plus": 0, "glm-4-air": 0}

    async def mock_call(model, messages, temperature, max_tokens):
        call_count[model] = call_count.get(model, 0) + 1
        if model == "glm-4-plus":
            raise APIError(status_code=503, message="Service unavailable")
        return '{"is_noise": false}'

    with patch("rippleflow.infra.llm.client._call_glm", side_effect=mock_call):
        from rippleflow.infra.llm.fallback import call_with_fallback
        result = await call_with_fallback(
            stage="stage1_noise",  # 允许降级到 flash
            messages=[{"role": "user", "content": "test"}],
            temperature=0.1,
            max_tokens=200,
        )

    assert result == '{"is_noise": false}'
    # glm-4-plus 尝试了（并失败），glm-4-air 或 flash 成功
    assert call_count.get("glm-4-plus", 0) > 0
```

### TC-LLM-09：stage0 不允许降级，glm-4-plus 不可用时直接抛 LLMServiceError

```python
async def test_call_with_fallback_stage0_no_degradation():
    from rippleflow.domain.exceptions import LLMServiceError

    async def always_fail(model, messages, temperature, max_tokens):
        raise APIError(status_code=503, message="unavailable")

    with patch("rippleflow.infra.llm.client._call_glm", side_effect=always_fail):
        from rippleflow.infra.llm.fallback import call_with_fallback
        with pytest.raises(LLMServiceError):
            await call_with_fallback(
                stage="stage0_sensitive",  # 必须 glm-4-plus，不降级
                messages=[],
                temperature=0.1,
                max_tokens=400,
            )
```

---

## 10. NotificationService

### TC-NOTIF-01：mark_read 验证通知归属，非本人调用抛 ForbiddenError

```python
# tests/unit/services/test_notification_service.py

async def test_mark_read_by_wrong_user_raises_forbidden():
    from rippleflow.domain.exceptions import ForbiddenError
    repo = AsyncMock()
    repo.get_by_id.return_value = {
        "id": NOTIF_ID,
        "recipient_id": "alice",  # 属于 alice
        "is_read": False,
    }
    svc = NotificationServiceImpl(repo=repo)

    with pytest.raises(ForbiddenError):
        await svc.mark_read(NOTIF_ID, user_id=USER_BOB)  # bob 无权操作
```

### TC-NOTIF-02：mark_all_read 返回更新数量

```python
async def test_mark_all_read_returns_count():
    repo = AsyncMock()
    repo.mark_all_read.return_value = 7
    svc = NotificationServiceImpl(repo=repo)

    count = await svc.mark_all_read(USER_ALICE)

    assert count == 7
    repo.mark_all_read.assert_awaited_once_with("alice")
```

### TC-NOTIF-03：list_for_user unread_only=True，只返回未读通知

```python
async def test_list_for_user_unread_only_filters_correctly():
    repo = AsyncMock()
    repo.list_for_user.return_value = ([{"id": NOTIF_ID, "is_read": False}], 1, 1)
    svc = NotificationServiceImpl(repo=repo)

    notifications, total, unread_count = await svc.list_for_user(
        USER_ALICE, unread_only=True
    )

    assert total == 1
    assert unread_count == 1
    call_kwargs = repo.list_for_user.call_args.kwargs
    assert call_kwargs.get("unread_only") is True
```

---

## 11. AdminService

### TC-ADMIN-01：add_to_whitelist 已存在活跃用户，抛 ConflictError

```python
# tests/unit/services/test_admin_service.py

async def test_add_to_whitelist_existing_active_user_raises_conflict():
    from rippleflow.domain.exceptions import ConflictError
    repo = AsyncMock()
    repo.get_by_ldap_id.return_value = {
        "ldap_user_id": "alice", "is_active": True
    }
    svc = AdminServiceImpl(whitelist_repo=repo, notify_svc=AsyncMock())

    with pytest.raises(ConflictError, match="已在白名单"):
        await svc.add_to_whitelist(
            ldap_user_id="alice", display_name="Alice",
            email=None, role="member", added_by="admin",
        )
```

### TC-ADMIN-02：add_to_whitelist 已存在但 is_active=False，重新激活

```python
async def test_add_to_whitelist_inactive_user_reactivates():
    repo = AsyncMock()
    repo.get_by_ldap_id.return_value = {
        "ldap_user_id": "alice", "is_active": False
    }
    repo.reactivate.return_value = {"ldap_user_id": "alice", "is_active": True}
    svc = AdminServiceImpl(whitelist_repo=repo, notify_svc=AsyncMock())

    result = await svc.add_to_whitelist(
        ldap_user_id="alice", display_name="Alice",
        email=None, role="member", added_by="admin",
    )

    repo.reactivate.assert_awaited_once_with("alice")
    repo.create.assert_not_awaited()
```

### TC-ADMIN-03：remove_from_whitelist 不允许管理员移除自己

```python
async def test_remove_from_whitelist_self_removal_raises_validation():
    from rippleflow.domain.exceptions import ValidationError
    repo = AsyncMock()
    svc = AdminServiceImpl(whitelist_repo=repo, notify_svc=AsyncMock())

    with pytest.raises(ValidationError, match="自身"):
        await svc.remove_from_whitelist(ldap_user_id="admin", operator="admin")
```

### TC-ADMIN-04：update_whitelist_entry 不允许修改自身 role

```python
async def test_update_whitelist_cannot_change_own_role():
    from rippleflow.domain.exceptions import ValidationError
    repo = AsyncMock()
    repo.get_by_ldap_id.return_value = {"ldap_user_id": "admin", "role": "admin", "is_active": True}
    svc = AdminServiceImpl(whitelist_repo=repo, notify_svc=AsyncMock())

    with pytest.raises(ValidationError, match="role"):
        await svc.update_whitelist_entry(
            ldap_user_id="admin",
            updates={"role": "member"},
            operator="admin",
        )
```

### TC-ADMIN-05：create_category code 重复，抛 ConflictError

```python
async def test_create_category_duplicate_code_raises_conflict():
    from rippleflow.domain.exceptions import ConflictError
    repo = AsyncMock()
    repo.get_by_code.return_value = {"code": "my_custom_cat"}  # 已存在
    svc = AdminServiceImpl(whitelist_repo=AsyncMock(), cat_repo=repo, notify_svc=AsyncMock())

    with pytest.raises(ConflictError, match="已存在"):
        await svc.create_category(
            code="my_custom_cat",
            display_name="我的自定义类别",
            trigger_hints=["关键词1"],
        )
```

---

## 12. ChatToolService

这组测试覆盖 `infra/chat_tool/` 目录，通过 mock `httpx.AsyncClient` 隔离真实 HTTP 调用。
实现类向 `POST {CHAT_TOOL_API}/send` 发送请求，失败时统一抛 `ChatToolError`。

### TC-CHAT-01：send_reply 成功，返回聊天工具消息 ID

```python
# tests/unit/chat_tool/test_chat_tool_service.py
import pytest
from unittest.mock import AsyncMock, MagicMock, patch

pytestmark = pytest.mark.asyncio


async def test_send_reply_success_returns_chat_msg_id():
    from rippleflow.infra.chat_tool.service import ChatToolServiceImpl

    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {"msg_id": "ext-msg-abc123"}
    mock_response.raise_for_status = MagicMock()  # 不抛异常

    with patch("httpx.AsyncClient.post", new=AsyncMock(return_value=mock_response)):
        svc = ChatToolServiceImpl(base_url="http://chat-tool.internal", api_key="test-key")
        result = await svc.send_reply(
            room_external_id="room-dev-001",
            content="已收到，正在处理",
            reply_to_msg_id="orig-msg-xyz",
        )

    assert result == "ext-msg-abc123"
```

### TC-CHAT-02：send_reply HTTP 失败（非 2xx），抛 ChatToolError

```python
async def test_send_reply_http_error_raises_chat_tool_error():
    from rippleflow.infra.chat_tool.service import ChatToolServiceImpl
    from rippleflow.domain.exceptions import ChatToolError
    import httpx

    mock_response = MagicMock()
    mock_response.status_code = 503
    mock_response.raise_for_status.side_effect = httpx.HTTPStatusError(
        message="Service Unavailable",
        request=MagicMock(),
        response=mock_response,
    )

    with patch("httpx.AsyncClient.post", new=AsyncMock(return_value=mock_response)):
        svc = ChatToolServiceImpl(base_url="http://chat-tool.internal", api_key="test-key")
        with pytest.raises(ChatToolError, match="发送失败"):
            await svc.send_reply(
                room_external_id="room-dev-001",
                content="消息内容",
            )
```

### TC-CHAT-03：send_card_reply 成功，返回聊天工具消息 ID

```python
async def test_send_card_reply_success_returns_chat_msg_id():
    from rippleflow.infra.chat_tool.service import ChatToolServiceImpl

    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {"msg_id": "ext-card-msg-456"}
    mock_response.raise_for_status = MagicMock()

    with patch("httpx.AsyncClient.post", new=AsyncMock(return_value=mock_response)) as mock_post:
        svc = ChatToolServiceImpl(base_url="http://chat-tool.internal", api_key="test-key")
        result = await svc.send_card_reply(
            room_external_id="room-dev-001",
            title="搜索结果",
            body="找到 3 条相关记录",
            source_text="Redis 连接超时问题",
            action_url="http://rippleflow.internal/threads/thread-uuid-001",
        )

    assert result == "ext-card-msg-456"
    # 验证请求体包含卡片字段
    call_kwargs = mock_post.call_args.kwargs
    payload = call_kwargs.get("json") or mock_post.call_args.args[1] if mock_post.call_args.args else {}
    assert payload.get("content_type") == "card" or "title" in str(mock_post.call_args)
```

### TC-CHAT-04：网络连接超时，抛 ChatToolError

```python
async def test_send_reply_network_timeout_raises_chat_tool_error():
    from rippleflow.infra.chat_tool.service import ChatToolServiceImpl
    from rippleflow.domain.exceptions import ChatToolError
    import httpx

    with patch(
        "httpx.AsyncClient.post",
        new=AsyncMock(side_effect=httpx.TimeoutException("Connection timed out")),
    ):
        svc = ChatToolServiceImpl(base_url="http://chat-tool.internal", api_key="test-key")
        with pytest.raises(ChatToolError):
            await svc.send_reply(
                room_external_id="room-dev-001",
                content="超时测试消息",
            )
```

---

## 13. BotAdapterService

这组测试覆盖 `services/bot_adapter_service.py`，通过 mock LLMService 和其他服务隔离外部依赖。

### TC-BOT-01：recognize_intent 正确识别搜索意图

```python
# tests/unit/services/test_bot_adapter_service.py
import pytest
from unittest.mock import AsyncMock, MagicMock

pytestmark = pytest.mark.asyncio


async def test_recognize_intent_search():
    from rippleflow.services.bot_adapter_service_impl import BotAdapterServiceImpl
    from rippleflow.services.interfaces.bot_adapter_service import BotIntent

    mock_llm = AsyncMock()
    mock_llm.call.return_value = '''
    {
        "intent": "search",
        "confidence": 0.95,
        "entities": {
            "keywords": ["Redis", "连接池", "配置"],
            "time_range": null,
            "environment": null
        }
    }
    '''

    svc = BotAdapterServiceImpl(llm_service=mock_llm, auth_svc=AsyncMock())
    result = await svc.recognize_intent("Redis 连接池怎么配置")

    assert result.intent == "search"
    assert result.confidence > 0.9
    assert "Redis" in result.entities.get("keywords", [])
```

### TC-BOT-02：recognize_intent 正确识别待办意图

```python
async def test_recognize_intent_action_items():
    from rippleflow.services.bot_adapter_service_impl import BotAdapterServiceImpl

    mock_llm = AsyncMock()
    mock_llm.call.return_value = '''
    {
        "intent": "action_items",
        "confidence": 0.98,
        "entities": {
            "assignee": "self"
        }
    }
    '''

    svc = BotAdapterServiceImpl(llm_service=mock_llm, auth_svc=AsyncMock())
    result = await svc.recognize_intent("我有什么待办")

    assert result.intent == "action_items"
```

### TC-BOT-03：recognize_intent 正确识别参考数据意图

```python
async def test_recognize_intent_reference():
    from rippleflow.services.bot_adapter_service_impl import BotAdapterServiceImpl

    mock_llm = AsyncMock()
    mock_llm.call.return_value = '''
    {
        "intent": "reference",
        "confidence": 0.92,
        "entities": {
            "keywords": ["Redis", "地址"],
            "environment": "prod"
        }
    }
    '''

    svc = BotAdapterServiceImpl(llm_service=mock_llm, auth_svc=AsyncMock())
    result = await svc.recognize_intent("prod 环境的 Redis 地址是多少")

    assert result.intent == "reference"
    assert result.entities.get("environment") == "prod"
```

### TC-BOT-04：recognize_intent 正确识别纪要生成意图

```python
async def test_recognize_intent_summarize():
    from rippleflow.services.bot_adapter_service_impl import BotAdapterServiceImpl

    mock_llm = AsyncMock()
    mock_llm.call.return_value = '''
    {
        "intent": "summarize",
        "confidence": 0.90,
        "entities": {
            "time_range": {"from": "today_start", "to": "now"},
            "room_hint": "产品群"
        }
    }
    '''

    svc = BotAdapterServiceImpl(llm_service=mock_llm, auth_svc=AsyncMock())
    result = await svc.recognize_intent("生成今天产品群的会议纪要")

    assert result.intent == "summarize"
    assert result.entities.get("room_hint") == "产品群"
```

### TC-BOT-05：recognize_intent 无法识别时返回 unknown

```python
async def test_recognize_intent_unknown():
    from rippleflow.services.bot_adapter_service_impl import BotAdapterServiceImpl

    mock_llm = AsyncMock()
    mock_llm.call.return_value = '''
    {
        "intent": "unknown",
        "confidence": 0.3,
        "entities": {}
    }
    '''

    svc = BotAdapterServiceImpl(llm_service=mock_llm, auth_svc=AsyncMock())
    result = await svc.recognize_intent("随便说点什么")

    assert result.intent == "unknown"
    assert result.confidence < 0.5
```

### TC-BOT-06：handle_query 非白名单用户抛 ForbiddenError

```python
async def test_handle_query_non_whitelisted_user():
    from rippleflow.services.bot_adapter_service_impl import BotAdapterServiceImpl
    from rippleflow.domain.exceptions import ForbiddenError
    from rippleflow.services.interfaces.bot_adapter_service import BotQueryContext

    mock_auth = AsyncMock()
    mock_auth.is_whitelisted.return_value = False

    svc = BotAdapterServiceImpl(
        llm_service=AsyncMock(),
        auth_svc=mock_auth,
        search_svc=AsyncMock(),
        thread_svc=AsyncMock(),
    )

    context = BotQueryContext(
        query="测试查询",
        user_id="non_whitelisted_user",
        room_id="room_dev",
    )

    with pytest.raises(ForbiddenError, match="白名单"):
        await svc.handle_query(context)
```

### TC-BOT-07：handle_query 搜索结果按用户权限过滤

```python
async def test_handle_query_filters_by_user_permission():
    from rippleflow.services.bot_adapter_service_impl import BotAdapterServiceImpl
    from rippleflow.services.interfaces.bot_adapter_service import BotQueryContext, BotIntent

    mock_auth = AsyncMock()
    mock_auth.is_whitelisted.return_value = True

    mock_llm = AsyncMock()
    mock_llm.call.return_value = '{"intent": "search", "confidence": 0.95, "entities": {"keywords": ["测试"]}}'

    # 模拟搜索返回 2 条结果，其中 1 条用户无权访问
    mock_search = AsyncMock()
    mock_search.answer_question.return_value = {
        "answer": "找到 1 条相关记录",
        "sources": [
            {"thread_id": "public-thread", "title": "公开话题"},
        ],
    }

    svc = BotAdapterServiceImpl(
        llm_service=mock_llm,
        auth_svc=mock_auth,
        search_svc=mock_search,
        thread_svc=AsyncMock(),
    )

    context = BotQueryContext(
        query="测试查询",
        user_id="test_member",
        room_id="room_dev",
    )

    result = await svc.handle_query(context)
    assert result.intent == "search"
    # 验证搜索服务被调用时传入了正确的 user_id
    mock_search.answer_question.assert_called_once()
```

### TC-BOT-08：format_search_response 返回群聊卡片格式

```python
async def test_format_search_response():
    from rippleflow.services.bot_adapter_service_impl import BotAdapterServiceImpl

    svc = BotAdapterServiceImpl(
        llm_service=AsyncMock(),
        auth_svc=AsyncMock(),
        search_svc=AsyncMock(),
        thread_svc=AsyncMock(),
    )

    qa_result = {
        "answer": "Redis 连接池建议使用 Lettuce",
        "sources": [
            {"thread_id": "t1", "title": "Redis 配置", "category": "tech_decision"},
        ],
    }

    result = await svc.format_search_response(qa_result, "test_user")

    assert result.response_type in ["card", "list"]
    assert result.intent == "search"
    assert result.suggestions is not None
    assert len(result.suggestions) > 0
```

---

## 14. FeedbackService

这组测试覆盖 `services/feedback_service.py`，负责问答反馈收集。

### TC-FB-01：submit_qa_feedback 成功存储反馈

```python
# tests/unit/services/test_feedback_service.py
import pytest
from unittest.mock import AsyncMock, MagicMock

pytestmark = pytest.mark.asyncio


async def test_submit_qa_feedback_success():
    from rippleflow.services.feedback_service_impl import FeedbackServiceImpl

    mock_db = AsyncMock()
    mock_db.execute.return_value = MagicMock()

    svc = FeedbackServiceImpl(db=mock_db)
    result = await svc.submit_qa_feedback(
        user_id="test_user",
        question="Redis 连接池怎么配置",
        answer="建议使用 Lettuce...",
        is_helpful=True,
        rating=5,
    )

    assert result.user_id == "test_user"
    assert result.is_helpful == True
    assert result.rating == 5
```

### TC-FB-02：submit_qa_feedback 记录评分和备注

```python
async def test_submit_qa_feedback_with_comment():
    from rippleflow.services.feedback_service_impl import FeedbackServiceImpl

    mock_db = AsyncMock()
    svc = FeedbackServiceImpl(db=mock_db)

    result = await svc.submit_qa_feedback(
        user_id="test_user",
        question="Redis 连接池怎么配置",
        answer="建议使用 Lettuce...",
        is_helpful=False,
        rating=2,
        comment="答案过于笼统",
    )

    assert result.is_helpful == False
    assert result.comment == "答案过于笼统"
```

### TC-FB-03：get_feedback_stats 计算满意度比例

```python
async def test_get_feedback_stats():
    from rippleflow.services.feedback_service_impl import FeedbackServiceImpl

    mock_db = AsyncMock()
    mock_db.fetch_one.return_value = {
        "total_feedback": 100,
        "helpful_count": 85,
        "not_helpful_count": 15,
        "avg_rating": 4.2,
    }

    svc = FeedbackServiceImpl(db=mock_db)
    result = await svc.get_feedback_stats()

    assert result.total_feedback == 100
    assert result.helpful_rate == 0.85
```

### TC-FB-04：get_low_rated_qa_pairs 返回低分问答

```python
async def test_get_low_rated_qa_pairs():
    from rippleflow.services.feedback_service_impl import FeedbackServiceImpl

    mock_db = AsyncMock()
    mock_db.fetch_all.return_value = [
        {"question": "Q1", "answer": "A1", "avg_rating": 2.5},
        {"question": "Q2", "answer": "A2", "avg_rating": 3.0},
    ]

    svc = FeedbackServiceImpl(db=mock_db)
    result = await svc.get_low_rated_qa_pairs(threshold=3.0)

    assert len(result) == 2
```

---

## 15. AIButlerService

这组测试覆盖 `services/ai_butler_service.py`，负责 AI 管家的主动运营功能。

### TC-BUT-01：generate_weekly_digest 生成完整快报

```python
# tests/unit/services/test_ai_butler_service.py
import pytest
from unittest.mock import AsyncMock, MagicMock

pytestmark = pytest.mark.asyncio


async def test_generate_weekly_digest():
    from rippleflow.services.ai_butler_service_impl import AIButlerServiceImpl

    mock_llm = AsyncMock()
    mock_llm.call.return_value = '''
    {
      "title": "本周知识沉淀",
      "summary": "本周新增 23 条话题线索",
      "hot_discussions": [{"title": "Redis 配置", "message_count": 12}],
      "new_decisions": [],
      "due_action_items": [],
      "trends": {}
    }
    '''

    mock_thread_svc = AsyncMock()
    mock_thread_svc.count_threads.return_value = 23

    svc = AIButlerServiceImpl(
        llm_service=mock_llm,
        thread_service=mock_thread_svc,
    )
    result = await svc.generate_weekly_digest()

    assert result.summary is not None
    assert result.hot_discussions is not None
```

### TC-BUT-02：check_action_items_due 返回即将到期待办

```python
async def test_check_action_items_due():
    from rippleflow.services.ai_butler_service_impl import AIButlerServiceImpl

    mock_thread_svc = AsyncMock()
    mock_thread_svc.find_due_action_items.return_value = [
        {"thread_id": "t1", "task": "配置 Redis", "due_date": "2026-03-02"},
    ]

    svc = AIButlerServiceImpl(
        llm_service=AsyncMock(),
        thread_service=mock_thread_svc,
    )
    result = await svc.check_action_items_due(days_ahead=1)

    assert len(result) == 1
    assert result[0]["task"] == "配置 Redis"
```

### TC-BUT-03：generate_health_report 返回健康评分

```python
async def test_generate_health_report():
    from rippleflow.services.ai_butler_service_impl import AIButlerServiceImpl

    mock_thread_svc = AsyncMock()
    mock_thread_svc.count_threads.return_value = 100
    mock_thread_svc.count_orphan_threads.return_value = 5

    mock_feedback_svc = AsyncMock()
    mock_feedback_svc.get_feedback_stats.return_value = MagicMock(
        helpful_rate=0.85, avg_rating=4.2
    )

    svc = AIButlerServiceImpl(
        llm_service=AsyncMock(),
        thread_service=mock_thread_svc,
        feedback_service=mock_feedback_svc,
    )
    result = await svc.generate_health_report()

    assert result.overall_score > 0
    assert result.overall_score <= 100
    assert result.metrics is not None
```

### TC-BUT-04：detect_orphan_threads 返回孤儿线索 ID

```python
async def test_detect_orphan_threads():
    from rippleflow.services.ai_butler_service_impl import AIButlerServiceImpl

    mock_thread_svc = AsyncMock()
    mock_thread_svc.find_orphan_threads.return_value = ["t1", "t2", "t3"]

    svc = AIButlerServiceImpl(
        llm_service=AsyncMock(),
        thread_service=mock_thread_svc,
    )
    result = await svc.detect_orphan_threads()

    assert len(result) == 3
```

### TC-BUT-05：self_learning 更新经验知识库

```python
async def test_self_learning():
    from rippleflow.services.ai_butler_service_impl import AIButlerServiceImpl

    mock_llm = AsyncMock()
    mock_llm.call.return_value = '''
    {
      "experience_update": {
        "category": "usage_pattern",
        "key": "peak_query_time",
        "value": {"hour": 10, "day_of_week": "Monday"},
        "confidence": 0.85
      }
    }
    '''

    mock_db = AsyncMock()

    svc = AIButlerServiceImpl(
        llm_service=mock_llm,
        db=mock_db,
        thread_service=AsyncMock(),
        feedback_service=AsyncMock(),
    )
    result = await svc.self_learning()

    assert result is not None
```

### TC-BUT-06：update_butler_experience 置信度更新

```python
async def test_update_butler_experience():
    from rippleflow.services.ai_butler_service_impl import AIButlerServiceImpl

    mock_db = AsyncMock()

    svc = AIButlerServiceImpl(
        llm_service=AsyncMock(),
        db=mock_db,
    )
    await svc.update_butler_experience(
        category="usage_pattern",
        key="common_question_type",
        value={"type": "Redis 配置", "frequency": "high"},
        confidence=0.9,
    )

    mock_db.execute.assert_called_once()
```

---

## 17. SubscriptionService

这组测试覆盖 `services/subscription_service.py`，负责订阅/关注管理。

### TC-SUB-01：subscribe 创建订阅

```python
# tests/unit/services/test_subscription_service.py
import pytest
from unittest.mock import AsyncMock

pytestmark = pytest.mark.asyncio


async def test_subscribe():
    from rippleflow.services.subscription_service_impl import SubscriptionServiceImpl

    mock_db = AsyncMock()
    mock_db.execute.return_value = AsyncMock()

    svc = SubscriptionServiceImpl(db=mock_db)
    result = await svc.subscribe(
        user_id="alice",
        subscription_type="user",
        target_id="bob",
        notification_types=["in_app"],
    )

    assert result.user_id == "alice"
    assert result.subscription_type == "user"
```

### TC-SUB-02：unsubscribe 取消订阅

```python
async def test_unsubscribe():
    from rippleflow.services.subscription_service_impl import SubscriptionServiceImpl
    from rippleflow.domain.exceptions import ForbiddenError

    mock_db = AsyncMock()
    mock_db.fetch_one.return_value = {"user_id": "alice"}  # 订阅属于 alice

    svc = SubscriptionServiceImpl(db=mock_db)
    await svc.unsubscribe(subscription_id="sub-123", user_id="alice")

    mock_db.execute.assert_called_once()
```

### TC-SUB-03：get_subscribers 获取订阅者列表

```python
async def test_get_subscribers():
    from rippleflow.services.subscription_service_impl import SubscriptionServiceImpl

    mock_db = AsyncMock()
    mock_db.fetch_all.return_value = [
        {"user_id": "alice"},
        {"user_id": "bob"},
    ]

    svc = SubscriptionServiceImpl(db=mock_db)
    result = await svc.get_subscribers(
        subscription_type="user",
        target_id="charlie",
    )

    assert len(result) == 2
    assert "alice" in result
```

### TC-SUB-04：publish_event 发布事件通知订阅者

```python
async def test_publish_event():
    from rippleflow.services.subscription_service_impl import SubscriptionServiceImpl

    mock_db = AsyncMock()
    mock_db.fetch_all.return_value = [{"user_id": "alice"}, {"user_id": "bob"}]

    mock_notify = AsyncMock()

    svc = SubscriptionServiceImpl(db=mock_db, notify_svc=mock_notify)
    result = await svc.publish_event(
        event_type="user_todo_created",
        actor_id="charlie",
        target_type="user",
        target_id="charlie",
        payload={"todo_title": "完成文档"},
    )

    assert len(result) == 2
```

---

## 18. PersonalTodoService

这组测试覆盖 `services/personal_todo_service.py`，负责个人待办管理。

### TC-TODO-01：create_todo 创建待办

```python
# tests/unit/services/test_personal_todo_service.py
import pytest
from unittest.mock import AsyncMock
from datetime import date

pytestmark = pytest.mark.asyncio


async def test_create_todo():
    from rippleflow.services.personal_todo_service_impl import PersonalTodoServiceImpl

    mock_db = AsyncMock()
    mock_db.execute.return_value = AsyncMock()

    svc = PersonalTodoServiceImpl(db=mock_db, notify_svc=AsyncMock())
    result = await svc.create_todo(
        user_id="alice",
        title="完成配置文档",
        priority="high",
        due_date=date(2026, 3, 10),
    )

    assert result.title == "完成配置文档"
    assert result.status == "pending"
```

### TC-TODO-02：create_from_group_message 从群聊消息创建待办

```python
async def test_create_from_group_message():
    from rippleflow.services.personal_todo_service_impl import PersonalTodoServiceImpl

    mock_db = AsyncMock()
    mock_notify = AsyncMock()

    svc = PersonalTodoServiceImpl(db=mock_db, notify_svc=mock_notify)
    result = await svc.create_from_group_message(
        message_id="msg-123",
        room_id="room-dev",
        extracted_task={
            "title": "配置 Redis",
            "assignees": [{"user_id": "alice", "role": "responsible"}],
            "due_date": "2026-03-10",
            "priority": "high",
            "task_elements": {"resources": ["服务器"]},
            "missing_elements": [],
        },
    )

    assert len(result) == 1
    assert result[0].title == "配置 Redis"
```

### TC-TODO-03：confirm_task_elements 确认任务要素

```python
async def test_confirm_task_elements():
    from rippleflow.services.personal_todo_service_impl import PersonalTodoServiceImpl

    mock_db = AsyncMock()
    mock_db.fetch_one.return_value = {
        "id": "todo-123",
        "elements_status": "needs_confirmation",
        "missing_elements": ["due_date", "resources"],
    }
    mock_db.execute.return_value = AsyncMock()

    svc = PersonalTodoServiceImpl(db=mock_db)
    result = await svc.confirm_task_elements(
        todo_id="todo-123",
        user_id="alice",
        confirmed_elements={
            "due_date": "2026-03-15",
            "resources": ["服务器A", "服务器B"],
        },
    )

    assert result.elements_status == "complete"
```

### TC-TODO-04：list_todos 获取待办列表

```python
async def test_list_todos():
    from rippleflow.services.personal_todo_service_impl import PersonalTodoServiceImpl

    mock_db = AsyncMock()
    mock_db.fetch_all.return_value = [
        {"id": "todo-1", "title": "任务1", "status": "pending"},
        {"id": "todo-2", "title": "任务2", "status": "pending"},
    ]
    mock_db.fetch_one.return_value = {"total": 2, "overdue": 0}

    svc = PersonalTodoServiceImpl(db=mock_db)
    items, total, overdue = await svc.list_todos(user_id="alice", status="pending")

    assert len(items) == 2
    assert total == 2
```

### TC-TODO-05：complete_todo 完成待办

```python
async def test_complete_todo():
    from rippleflow.services.personal_todo_service_impl import PersonalTodoServiceImpl

    mock_db = AsyncMock()
    mock_db.fetch_one.return_value = {
        "id": "todo-123",
        "user_id": "alice",
        "status": "pending",
    }
    mock_db.execute.return_value = AsyncMock()

    svc = PersonalTodoServiceImpl(db=mock_db, notify_svc=AsyncMock())
    result = await svc.complete_todo(
        todo_id="todo-123",
        user_id="alice",
        comment="已完成配置",
    )

    assert result.status == "completed"
```

### TC-TODO-06：get_stats 获取待办统计

```python
async def test_get_stats():
    from rippleflow.services.personal_todo_service_impl import PersonalTodoServiceImpl

    mock_db = AsyncMock()
    mock_db.fetch_one.return_value = {
        "total": 10,
        "pending": 5,
        "in_progress": 2,
        "completed": 3,
        "overdue": 1,
        "due_today": 2,
        "due_this_week": 4,
    }

    svc = PersonalTodoServiceImpl(db=mock_db)
    result = await svc.get_stats(user_id="alice")

    assert result.total == 10
    assert result.overdue == 1
```

---

## 19. FaqService（FAQ 知识库管理）

> **归属**：`FaqService` 是 RippleFlow 平台层提供的 FAQ CRUD 接口，供 nullclaw 调用写入和查询 FAQ 条目。
> nullclaw 的生成策略逻辑不在本目录测试范围内。

### 测试前置条件

```python
@pytest.fixture
async def mock_faq_repo():
    repo = AsyncMock()
    repo.get_item.return_value = {
        "id": "faq-001",
        "section_id": "sec-001",
        "question": "Redis 连接池怎么配置？",
        "answer": "建议 maxPoolSize = CPU核心数 × 2",
        "source_threads": ["thread-abc"],
        "confidence": 0.9,
        "review_status": "confirmed",
    }
    return repo
```

### TC-FAQ-01：创建 FAQ 条目，默认 pending 状态

```python
async def test_create_faq_item_defaults_to_pending(mock_faq_repo):
    svc = FaqServiceImpl(faq_repo=mock_faq_repo)
    result = await svc.create_item(
        section_id="sec-001",
        question="如何配置 Nginx 反向代理？",
        answer="使用 proxy_pass 指令...",
        source_threads=["thread-xyz"],
        created_by="nullclaw",
    )
    assert result.review_status == "pending"
    assert result.created_by == "nullclaw"
```

### TC-FAQ-02：管理员审核通过，状态变更为 confirmed

```python
async def test_review_faq_item_confirmed(mock_faq_repo, mock_admin_user):
    svc = FaqServiceImpl(faq_repo=mock_faq_repo)
    result = await svc.review_item(
        item_id="faq-001",
        reviewer_id=mock_admin_user.id,
        action="confirm",
    )
    assert result.review_status == "confirmed"
    assert result.reviewed_by == mock_admin_user.id
    assert result.reviewed_at is not None
```

### TC-FAQ-03：管理员驳回，状态变更为 rejected

```python
async def test_review_faq_item_rejected(mock_faq_repo, mock_admin_user):
    svc = FaqServiceImpl(faq_repo=mock_faq_repo)
    result = await svc.review_item(
        item_id="faq-001",
        reviewer_id=mock_admin_user.id,
        action="reject",
        reason="答案已过期，Redis 连接池推荐方式已更新",
    )
    assert result.review_status == "rejected"
```

### TC-FAQ-04：普通用户只能查看 confirmed 条目

```python
async def test_get_items_regular_user_sees_only_confirmed(mock_faq_repo):
    mock_faq_repo.list_items.return_value = [
        {"id": "faq-001", "review_status": "confirmed"},
        {"id": "faq-002", "review_status": "pending"},
    ]
    svc = FaqServiceImpl(faq_repo=mock_faq_repo)
    result = await svc.list_items(group_id="group-001", caller_role="member")
    # 普通成员只能看到 confirmed 条目
    assert all(item["review_status"] == "confirmed" for item in result)
```

### TC-FAQ-05：管理员可查看全部条目（含 pending）

```python
async def test_get_items_admin_sees_all(mock_faq_repo):
    mock_faq_repo.list_items.return_value = [
        {"id": "faq-001", "review_status": "confirmed"},
        {"id": "faq-002", "review_status": "pending"},
    ]
    svc = FaqServiceImpl(faq_repo=mock_faq_repo)
    result = await svc.list_items(group_id="group-001", caller_role="admin")
    assert len(result) == 2
```

### TC-FAQ-06：更新 FAQ 条目，自动创建版本记录

```python
async def test_update_faq_item_creates_version(mock_faq_repo, mock_version_repo):
    svc = FaqServiceImpl(faq_repo=mock_faq_repo, version_repo=mock_version_repo)
    await svc.update_item(
        item_id="faq-001",
        answer="更新后的答案：建议 maxPoolSize = vCPU × 2 + 2",
        change_by="nullclaw",
        change_reason="根据新的性能测试数据更新推荐值",
    )
    # 必须创建版本快照
    mock_version_repo.create.assert_awaited_once()
    call_kwargs = mock_version_repo.create.call_args.kwargs
    assert call_kwargs["change_type"] == "updated"
    assert call_kwargs["change_by"] == "nullclaw"
```

### TC-FAQ-07：合并重复条目，保留所有 source_threads

```python
async def test_merge_faq_items_combines_source_threads(mock_faq_repo):
    mock_faq_repo.get_item.side_effect = [
        {"id": "faq-001", "source_threads": ["thread-a"]},
        {"id": "faq-002", "source_threads": ["thread-b", "thread-c"]},
    ]
    svc = FaqServiceImpl(faq_repo=mock_faq_repo)
    merged = await svc.merge_items(
        source_ids=["faq-001", "faq-002"],
        target={"question": "标准化问题", "answer": "合并后答案"},
        merge_by="nullclaw",
    )
    # 合并后应包含所有来源线索
    assert set(merged.source_threads) == {"thread-a", "thread-b", "thread-c"}
```

### TC-FAQ-08：用户反馈"答案有误"，helpful_count 不增加

```python
async def test_faq_unhelpful_feedback_no_helpful_increment(mock_faq_repo):
    svc = FaqServiceImpl(faq_repo=mock_faq_repo)
    await svc.submit_feedback(
        item_id="faq-001",
        user_id="alice",
        feedback_type="unhelpful",
        comment="Redis 版本升级后配置方式已变更",
    )
    # helpful_count 不应增加
    update_call = mock_faq_repo.update_counters.call_args.kwargs
    assert update_call.get("helpful_increment", 0) == 0
```

### TC-FAQ-09：FAQ 全文搜索，返回按热度排序的结果

```python
async def test_search_faq_returns_sorted_by_view_count(mock_faq_repo):
    mock_faq_repo.search.return_value = [
        {"id": "faq-003", "question": "Redis持久化", "view_count": 50},
        {"id": "faq-001", "question": "Redis连接池", "view_count": 120},
    ]
    svc = FaqServiceImpl(faq_repo=mock_faq_repo)
    result = await svc.search(group_id="group-001", query="Redis", sort_by="view_count")
    # 按 view_count 降序
    assert result[0]["id"] == "faq-001"
```

---

## 20. 附录：测试用例索引

| ID | 服务 | 方法 | 测试场景 | 覆盖业务规则 |
|----|------|------|----------|-------------|
| TC-MSG-01 | MessageService | ingest | 正常入库并入队 | 基础流程 |
| TC-MSG-02 | MessageService | ingest | 重复 external_msg_id | 幂等性 |
| TC-MSG-03 | MessageService | get_context | 返回前 N 条 | 上下文顺序 |
| TC-MSG-04 | MessageService | import_history_batch | 跳过重复项 | 批导去重 |
| TC-MSG-05 | MessageService | update_status | 记录 error 字段 | 失败溯源 |
| TC-PIPE-01 | Pipeline | run | 噪声消息 Stage 1 中止 | Stage 中止逻辑 |
| TC-PIPE-02 | Pipeline | run | 敏感消息 Stage 0 中止 | 敏感流程触发 |
| TC-PIPE-03 | Pipeline | run | 完整流水线创建新线索 | 正常路径 |
| TC-PIPE-04 | Pipeline | run | 扩展已有线索 | Thread 归属 |
| TC-PIPE-05 | Pipeline | run | 无类别达阈值跳过 | 分类兜底 |
| TC-PIPE-06 | Pipeline | stage5 | 冲突通知当事人 | Append-Only 冲突 |
| TC-PIPE-07 | Pipeline | run | LLM 异常返回 failed | 容错隔离 |
| TC-THREAD-01 | ThreadService | apply_modification | 当事人修改触发同步 | 修改权限+同步 |
| TC-THREAD-02 | ThreadService | apply_modification | 非当事人抛错 | 权限控制 |
| TC-THREAD-03 | ThreadService | list_threads | 时间窗口过滤 | 滑窗逻辑 |
| TC-THREAD-04 | ThreadService | list_threads | ignore_window 旁路 | 窗口旁路 |
| TC-THREAD-05 | ThreadService | get_by_id | is_stakeholder 标志 | 当事人判断 |
| TC-SEARCH-01 | SearchService | answer_question | 完整问答链路 | LLM 协同 |
| TC-SEARCH-02 | SearchService | answer_question | 无结果不调 LLM | 空结果优化 |
| TC-SEARCH-03 | SearchService | find_candidate_threads | 时间窗口传递 | Stage 3 支撑 |
| TC-SENS-01 | SensitiveService | create_authorization | decisions 初始化 | 状态机初始 |
| TC-SENS-02 | SensitiveService | submit_decision | 全授权重入队列 | 状态机转移 |
| TC-SENS-03 | SensitiveService | submit_decision | 任一拒绝即结束 | 拒绝语义 |
| TC-SENS-04 | SensitiveService | submit_decision | 已拒绝再提交抛错 | 最终态保护 |
| TC-SENS-05 | SensitiveService | nudge_stakeholders | 24h 内限频 | 提醒限流 |
| TC-SENS-06 | SensitiveService | nudge_stakeholders | 超 24h 仅通知 pending | 过滤已表态 |
| TC-SENS-07 | SensitiveService | send_daily_reminders | 节奏过滤 | 提醒调度 |
| TC-AUTH-01 | AuthService | verify_jwt | 正常解码 | JWT 基础 |
| TC-AUTH-02 | AuthService | verify_jwt | 过期抛错 | Token 过期 |
| TC-AUTH-03 | AuthService | verify_jwt | 篡改抛错 | Token 完整性 |
| TC-AUTH-04 | AuthService | check_whitelist | 不存在抛错 | 白名单基础 |
| TC-AUTH-05 | AuthService | check_whitelist | inactive 抛错 | 软删除处理 |
| TC-AUTH-06 | AuthService | get_current_user | 组合验证 | 完整认证链 |
| TC-LLM-01~04 | JSONParser | parse_llm_json | 各种输入格式 | 容错解析 |
| TC-LLM-05 | ResponseParser | parse_sensitive_result | 兜底追加 sender | 安全保障 |
| TC-LLM-06 | ResponseParser | parse_classify_result | 阈值过滤+排序 | 分类质量 |
| TC-LLM-07 | ResponseParser | parse_match_thread_result | 降级为 create | 数据一致性 |
| TC-LLM-08 | Fallback | call_with_fallback | 自动切换次级模型 | 降级策略 |
| TC-LLM-09 | Fallback | call_with_fallback | stage0 禁止降级 | 敏感检测保障 |
| TC-NOTIF-01 | NotificationService | mark_read | 非归属用户抛错 | 通知隔离 |
| TC-NOTIF-02 | NotificationService | mark_all_read | 返回数量 | 基础功能 |
| TC-NOTIF-03 | NotificationService | list_for_user | unread_only 过滤 | 查询过滤 |
| TC-ADMIN-01 | AdminService | add_to_whitelist | 活跃用户重复添加 | 唯一性 |
| TC-ADMIN-02 | AdminService | add_to_whitelist | inactive 重新激活 | 软删除复活 |
| TC-ADMIN-03 | AdminService | remove_from_whitelist | 禁止自我移除 | 自毁保护 |
| TC-ADMIN-04 | AdminService | update_whitelist_entry | 禁止修改自身 role | 权限保护 |
| TC-ADMIN-05 | AdminService | create_category | code 重复抛错 | 唯一性 |
| TC-CHAT-01 | ChatToolService | send_reply | 成功返回 chat_msg_id | 基础集成 |
| TC-CHAT-02 | ChatToolService | send_reply | HTTP 非 2xx 抛 ChatToolError | HTTP 错误处理 |
| TC-CHAT-03 | ChatToolService | send_card_reply | 成功返回 chat_msg_id | 卡片消息 |
| TC-CHAT-04 | ChatToolService | send_reply | 网络超时抛 ChatToolError | 超时容错 |
| TC-BOT-01 | BotAdapterService | recognize_intent | 搜索意图识别 | 意图解析 |
| TC-BOT-02 | BotAdapterService | recognize_intent | 待办意图识别 | 意图解析 |
| TC-BOT-03 | BotAdapterService | recognize_intent | 参考数据意图识别 | 意图解析 |
| TC-BOT-04 | BotAdapterService | recognize_intent | 纪要生成意图识别 | 意图解析 |
| TC-BOT-05 | BotAdapterService | recognize_intent | 未知意图返回 unknown | 兜底处理 |
| TC-BOT-06 | BotAdapterService | handle_query | 非白名单用户抛 ForbiddenError | 权限验证 |
| TC-BOT-07 | BotAdapterService | handle_query | 搜索结果按用户权限过滤 | 数据隔离 |
| TC-BOT-08 | BotAdapterService | format_search_response | 返回群聊卡片格式 | 响应格式化 |
| TC-FB-01 | FeedbackService | submit_qa_feedback | 成功存储反馈 | 基础功能 |
| TC-FB-02 | FeedbackService | submit_qa_feedback | 记录评分和备注 | 完整反馈 |
| TC-FB-03 | FeedbackService | get_feedback_stats | 计算满意度比例 | 统计计算 |
| TC-FB-04 | FeedbackService | get_low_rated_qa_pairs | 返回低分问答 | 优化支撑 |
| TC-BUT-01 | AIButlerService | generate_weekly_digest | 生成完整快报 | 快报生成 |
| TC-BUT-02 | AIButlerService | check_action_items_due | 返回即将到期待办 | 到期检测 |
| TC-BUT-03 | AIButlerService | generate_health_report | 返回健康评分 | 健康评估 |
| TC-BUT-04 | AIButlerService | detect_orphan_threads | 返回孤儿线索 ID | 孤儿检测 |
| TC-BUT-05 | AIButlerService | self_learning | 更新经验知识库 | 自主学习 |
| TC-BUT-06 | AIButlerService | update_butler_experience | 置信度更新 | 经验累积 |
| TC-SUB-01 | SubscriptionService | subscribe | 创建订阅 | 订阅管理 |
| TC-SUB-02 | SubscriptionService | unsubscribe | 取消订阅 | 订阅管理 |
| TC-SUB-03 | SubscriptionService | get_subscribers | 获取订阅者列表 | 订阅查询 |
| TC-SUB-04 | SubscriptionService | publish_event | 发布事件通知订阅者 | 事件通知 |
| TC-TODO-01 | PersonalTodoService | create_todo | 创建待办 | 待办管理 |
| TC-TODO-02 | PersonalTodoService | create_from_group_message | 从群聊消息创建待办 | 任务识别 |
| TC-TODO-03 | PersonalTodoService | confirm_task_elements | 确认任务要素 | 要素确认 |
| TC-TODO-04 | PersonalTodoService | list_todos | 获取待办列表 | 待办查询 |
| TC-TODO-05 | PersonalTodoService | complete_todo | 完成待办 | 状态更新 |
| TC-TODO-06 | PersonalTodoService | get_stats | 获取待办统计 | 统计计算 |
| TC-FAQ-01 | FaqService | create_item | 创建条目默认 pending | 状态初始化 |
| TC-FAQ-02 | FaqService | review_item | 审核通过变更 confirmed | 审核流程 |
| TC-FAQ-03 | FaqService | review_item | 驳回变更 rejected | 审核流程 |
| TC-FAQ-04 | FaqService | list_items | 普通用户只见 confirmed | 权限过滤 |
| TC-FAQ-05 | FaqService | list_items | 管理员见全部 | 权限过滤 |
| TC-FAQ-06 | FaqService | update_item | 更新自动创建版本快照 | 版本控制 |
| TC-FAQ-07 | FaqService | merge_items | 合并保留所有 source_threads | 数据完整性 |
| TC-FAQ-08 | FaqService | submit_feedback | unhelpful 不增加 helpful_count | 计数逻辑 |
| TC-FAQ-09 | FaqService | search | 按 view_count 排序 | 搜索排序 |
