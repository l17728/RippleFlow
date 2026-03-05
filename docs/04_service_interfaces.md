# 04 服务层接口定义（Python Protocol）

本文档定义系统各服务模块的 Python `Protocol` 接口，
所有实现类必须满足这些接口，便于单元测试中 mock 替换。

---

## 0. 公共类型定义

```python
# rippleflow/domain/types.py
from __future__ import annotations
from dataclasses import dataclass, field
from datetime import datetime, date
from typing import Any, Optional
from uuid import UUID
from enum import Enum


class CategoryType(str, Enum):
    TECH_DECISION    = "tech_decision"
    QA_FAQ           = "qa_faq"
    BUG_INCIDENT     = "bug_incident"
    REFERENCE_DATA   = "reference_data"
    ACTION_ITEM      = "action_item"
    DISCUSSION_NOTES = "discussion_notes"
    KNOWLEDGE_SHARE  = "knowledge_share"
    ENV_CONFIG       = "env_config"
    PROJECT_UPDATE   = "project_update"


class ThreadStatus(str, Enum):
    ACTIVE   = "active"
    RESOLVED = "resolved"
    ARCHIVED = "archived"
    MERGED   = "merged"


class MessageProcessingStatus(str, Enum):
    PENDING              = "pending"
    PROCESSING           = "processing"
    CLASSIFIED           = "classified"
    FAILED               = "failed"
    SKIPPED              = "skipped"
    SENSITIVE_PENDING    = "sensitive_pending"
    SENSITIVE_REJECTED   = "sensitive_rejected"


class SensitiveDecision(str, Enum):
    PENDING      = "pending"
    AUTHORIZE    = "authorize"
    REJECT       = "reject"
    DESENSITIZE  = "desensitize"


class SensitiveOverallStatus(str, Enum):
    PENDING                 = "pending"
    AUTHORIZED              = "authorized"
    REJECTED                = "rejected"
    PENDING_DESENSITIZATION = "pending_desensitization"


# ── 值对象 ────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class UserId:
    value: str   # LDAP user ID


@dataclass(frozen=True)
class RoomId:
    value: str   # external room ID


@dataclass
class InboundMessageDTO:
    external_msg_id: str
    room_external_id: str
    sender_external_id: str
    sender_display_name: str
    content: str
    content_type: str       # 'text'|'image'|'file'|'audio'|'video'|'code'
    sent_at: datetime
    attachments: list[dict] = field(default_factory=list)
    mentions: list[str]     = field(default_factory=list)
    reply_to_msg_id: Optional[str] = None
    thread_root_msg_id: Optional[str] = None
    is_imported: bool = False
    import_batch_id: Optional[str] = None


@dataclass
class ClassificationResult:
    category: str
    confidence: float   # 0.0 – 1.0


@dataclass
class NoiseCheckResult:
    is_noise: bool
    reason: Optional[str] = None


@dataclass
class SensitiveCheckResult:
    is_sensitive: bool
    sensitive_types: list[str] = field(default_factory=list)
    sensitive_summary: Optional[str] = None
    stakeholder_ids: list[str] = field(default_factory=list)


@dataclass
class ThreadMatchResult:
    action: str            # 'extend' | 'create' | 'extend_and_create'
    thread_id: Optional[UUID] = None
    new_title: Optional[str] = None
    confidence: float = 0.0


@dataclass
class SummaryUpdateResult:
    updated_summary: str
    updated_structured_data: dict
    updated_tags: list[str]
    status_change: Optional[str] = None
    has_conflict: bool = False
    conflict_description: Optional[str] = None


@dataclass
class SearchHit:
    thread_id: UUID
    title: str
    category: str
    summary_excerpt: str
    tags: list[str]
    last_message_at: Optional[datetime]
    rank: float


@dataclass
class QAResult:
    answer: str
    sources: list[SearchHit]
    keywords_used: list[str]
    no_result: bool = False


@dataclass
class ThreadModificationDTO:
    field_modified: str
    new_value: str
    reason: str


@dataclass
class SensitiveDecisionDTO:
    decision: SensitiveDecision
    note: Optional[str] = None
    desensitized_content: Optional[str] = None
```

---

## 1. MessageService

```python
# rippleflow/services/interfaces/message_service.py
from typing import Protocol
from uuid import UUID
from ..domain.types import InboundMessageDTO, MessageProcessingStatus


class IMessageService(Protocol):

    async def ingest(self, dto: InboundMessageDTO) -> UUID:
        """
        接收来自 Webhook 的消息，存入 DB，入 Celery 处理队列。
        返回内部 message_id。

        执行顺序：
        1. 查询 chat_users WHERE user_external_id=dto.sender_external_id：
           - GAP-7 修复：若 is_bot=True，写入 messages（processing_status='skipped',
             is_bot_message=True），立即返回，不入 Celery 队列，不经过任何 Stage。
             机器人消息保留完整历史记录，但不进入知识库处理。
        2. 查询 messages WHERE external_msg_id=dto.external_msg_id：
           - GAP-8 修复：使用 INSERT ... ON CONFLICT (external_msg_id) DO NOTHING RETURNING id
             解决并发双推竞争条件，幂等处理，返回已有 ID。
        3. 写入 messages（processing_status='pending'）
        4. 将 message_id 入 Celery 处理队列（IProcessingPipelineService.run()）
        """
        ...

    async def get_by_id(self, message_id: UUID) -> dict:
        """返回消息详情（含处理状态）"""
        ...

    async def get_context(
        self,
        room_external_id: str,
        before_msg_id: UUID,
        limit: int = 5,
    ) -> list[dict]:
        """
        获取指定消息之前的 N 条上下文消息（同群组，按 sent_at 降序）。
        用于 Stage 2 分类时提供上下文。
        """
        ...

    async def update_status(
        self,
        message_id: UUID,
        status: MessageProcessingStatus,
        error: str | None = None,
    ) -> None:
        """更新消息处理状态"""
        ...

    async def import_history_batch(
        self,
        messages: list[InboundMessageDTO],
        batch_id: str,
    ) -> dict[str, int]:
        """
        批量导入历史消息。
        返回 {'total': N, 'inserted': M, 'skipped': K}
        """
        ...
```

---

## 2. ProcessingPipelineService

```python
# rippleflow/services/interfaces/processing_service.py
from typing import Protocol
from uuid import UUID
from ..domain.types import (
    SensitiveCheckResult, NoiseCheckResult,
    ClassificationResult, ThreadMatchResult, SummaryUpdateResult,
)


class IProcessingPipelineService(Protocol):

    async def run(self, message_id: UUID, start_stage: int = 0) -> str:
        """
        执行 Stage 0–4 共 5 阶段流水线（Stage 5 摘要更新已移交 nullclaw）。
        完成后向 nullclaw 发送事件通知（HTTP POST，支持多线索 payload，见 GAP-5 修复）。
        返回最终状态字符串：
          'skipped_noise' | 'sensitive_pending' | 'classified' | 'failed'

        参数：
          start_stage: 从哪个阶段开始执行（默认 0=Stage0）。
                       GAP-1 修复：敏感授权通过后重入时传入 start_stage=1，
                       跳过 Stage0 避免重复触发敏感检测死循环。

        执行逻辑（多分类场景，GAP-3 修复）：
          Stage 0 (if start_stage<=0): 敏感检测
          Stage 1 (if start_stage<=1): 噪声过滤
            - GAP-2 修复：若 messages.pipeline_start_stage=1（敏感授权重入），
              Stage1 的 Prompt 追加上下文："本消息已由当事人授权入库，请重点
              判断知识价值，而非因'HR/人事类信息'理由过滤"。
          Stage 2: 分类（返回所有 confidence>=0.6 的类别）
          Stage 3+4: 对每个分类分别执行（for category in results）：
            - stage3_match_thread(message_id, category)
            - stage4_extract_structured(message_id, thread_id, category)
            - 若 category='action_item'：自动调用 IPersonalTodoService.sync_from_action_item()
              （GAP-3 修复：Pipeline 显式依赖 PersonalTodoService）
          完成后：
            - 统一调用 ISubscriptionService.publish_event()（GAP-16 修复：见下方说明）
            - 统一调用 notify_nullclaw()（多线索格式，GAP-5 修复）

        GAP-16 修复（keyword通知时序）：
          publish_event() 不在 Stage4 完成后立即调用。
          正确顺序：notify_nullclaw() → nullclaw 完成 Stage5（摘要写回）→
          由 nullclaw 通过 POST /internal/subscriptions/publish 触发 publish_event()。
          这确保用户点击通知时，线索摘要已就绪。
          对于 is_new_thread=True 的情况，摘要生成完毕才应推送 new_thread 通知。
        """
        ...

    async def stage0_sensitive_check(
        self, message_id: UUID
    ) -> SensitiveCheckResult:
        """
        阶段 0：GLM-4-Plus 判断消息是否含敏感内容。
        敏感则创建 sensitive_authorizations 记录，
        通知当事人，返回 is_sensitive=True，流水线中止。
        """
        ...

    async def stage1_noise_filter(
        self, message_id: UUID
    ) -> NoiseCheckResult:
        """阶段 1：GLM-4-Plus 判断消息是否为噪声"""
        ...

    async def stage2_classify(
        self, message_id: UUID
    ) -> list[ClassificationResult]:
        """
        阶段 2：GLM-4-Plus 多类别分类。
        返回 confidence >= 0.6 的所有类别（可多个）。
        """
        ...

    async def stage3_match_thread(
        self,
        message_id: UUID,
        category: str,
    ) -> ThreadMatchResult:
        """
        阶段 3：全文检索候选线索 + GLM-4-Plus 判断归属。
        时间窗口由 category_definitions.search_window_days 控制。
        """
        ...

    async def stage4_extract_structured(
        self,
        message_id: UUID,
        thread_id: UUID,
        category: str,
    ) -> dict:
        """
        阶段 4：按类别提取结构化字段 + 更新 stakeholder_ids。
        返回提取的结构化数据 dict。
        """
        ...

    async def stage5_update_summary(
        self,
        thread_id: UUID,
        new_message_id: UUID,
    ) -> SummaryUpdateResult:
        """
        ⚠️ 已移交 nullclaw 执行，此接口不再由平台流水线调用。
        保留定义供 nullclaw 通过 PUT /api/v1/threads/{id}/summary 写回结果时使用。
        阶段 5：增量摘要更新。
        输入：现有摘要 + 新消息内容。
        旧摘要自动归档到 thread_summary_history。
        漂移检测：追加冲突说明（Append-Only）。
        """
        ...

    # ── 死信队列（P1-2）──────────────────────────────────────────────────────

    async def move_to_dlq(
        self,
        message_id: UUID,
        failed_stage: str,
        error_type: str,
        error_detail: str,
        retry_count: int,
    ) -> None:
        """消息重试耗尽后写入 failed_messages 死信队列，并推送管理员告警"""
        ...

    async def list_failed_messages(
        self,
        status: str = "pending",
        page: int = 1,
        size: int = 20,
    ) -> tuple[list[dict], int]:
        """获取死信队列列表（管理员 Dashboard 使用）"""
        ...

    async def retry_failed_message(
        self,
        failed_id: UUID,
        operator_id: str,
    ) -> None:
        """管理员触发重新处理：消息重新入高优先级队列，status → 'retrying'"""
        ...

    async def skip_failed_message(
        self,
        failed_id: UUID,
        operator_id: str,
        note: str = "",
    ) -> None:
        """管理员跳过失败消息：status → 'skipped'，不再处理"""
        ...
```

---

## 3. ThreadService

```python
# rippleflow/services/interfaces/thread_service.py
from typing import Protocol
from uuid import UUID
from ..domain.types import (
    CategoryType, ThreadStatus,
    ThreadModificationDTO, UserId,
)


class IThreadService(Protocol):

    async def get_by_id(self, thread_id: UUID) -> dict:
        """返回话题线索详情，含 is_stakeholder 标志（当前用户）"""
        ...

    async def list_threads(
        self,
        category: str | None = None,
        status: ThreadStatus | None = None,
        query: str | None = None,
        ignore_window: bool = False,
        page: int = 1,
        size: int = 20,
    ) -> tuple[list[dict], int]:
        """
        分页查询话题线索。
        query 触发数据库全文检索（SQLite FTS5 或 PostgreSQL tsvector）。
        ignore_window=False 时按类别的 search_window_days 过滤。
        返回 (items, total)。
        """
        ...

    async def create(
        self,
        title: str,
        category: str,
        summary: str,
        structured_data: dict,
        source_message_id: UUID,
    ) -> UUID:
        """创建新话题线索，返回 thread_id"""
        ...

    async def extend(
        self,
        thread_id: UUID,
        message_id: UUID,
        relevance_score: float,
        contribution: str,
    ) -> None:
        """将消息关联到已有线索，更新 message_count / last_message_at"""
        ...

    async def apply_modification(
        self,
        thread_id: UUID,
        user_id: UserId,
        dto: ThreadModificationDTO,
    ) -> dict:
        """
        当事人修改线索。
        1. 验证 user_id 在 stakeholder_ids 中。
        2. 记录 thread_modifications。
        3. 更新 topic_threads（触发 trigger 自动归档历史摘要）。
        4. 异步触发 SyncToChatWorker。
        抛出 PermissionError 若非当事人。
        """
        ...

    async def get_summary_history(
        self, thread_id: UUID
    ) -> list[dict]:
        """返回历史摘要版本（降序）"""
        ...

    async def get_modifications(
        self, thread_id: UUID
    ) -> list[dict]:
        """返回当事人修改记录"""
        ...

    async def is_stakeholder(
        self,
        thread_id: UUID,
        user_id: UserId,
    ) -> bool:
        """判断用户是否为线索的当事人"""
        ...
```

---

## 4. SearchService

```python
# rippleflow/services/interfaces/search_service.py
from typing import Protocol
from ..domain.types import SearchHit, QAResult


class ISearchService(Protocol):

    async def full_text_search(
        self,
        query: str,
        categories: list[str] | None = None,
        date_from: str | None = None,
        date_to: str | None = None,
        ignore_window: bool = False,
        page: int = 1,
        size: int = 20,
    ) -> tuple[list[SearchHit], int]:
        """
        数据库全文检索。
        - SQLite: FTS5 匹配 title + summary
        - PostgreSQL: pg_trgm / tsvector 匹配 title + summary + tags
        按 category 的 search_window_days 时间过滤（ignore_window=False）。
        返回 (hits, total)。
        """
        ...

    async def answer_question(
        self,
        question: str,
        categories: list[str] | None = None,
        ignore_window: bool = False,
    ) -> QAResult:
        """
        LLM 问答流程：
        1. GLM-4-Plus 提取检索关键词。
        2. full_text_search 召回 Top-10 线索。
        3. 将摘要列表传入 GLM-4-Plus 生成综合答案。
        4. 返回答案 + 来源线索列表。
        """
        ...

    async def find_candidate_threads(
        self,
        query: str,
        category: str,
        limit: int = 5,
        ignore_window: bool = False,
    ) -> list[SearchHit]:
        """
        Stage 3 内部使用：为消息寻找候选话题线索。
        仅在指定 category 内检索，受时间窗口限制。
        """
        ...

    async def find_reference(
        self,
        query: str,
        resource_type: str | None = None,
        environment: str | None = None,
        service_name: str | None = None,
        include_deprecated: bool = False,
        limit: int = 10,
    ) -> list[dict]:
        """
        GAP-12 修复：查询 reference_data_items，供机器人意图路由（reference intent）使用。

        查询逻辑：
        - 全文搜索 reference_data_items 的 label + value（PostgreSQL 全文检索）
        - 可选过滤：resource_type（'ip'|'url'|'endpoint'|...）、environment、service_name
        - include_deprecated=False（默认）：只返回 is_deprecated=False 的记录
        - is_sensitive=True 的记录：只返回 label，不返回 value（GAP-13 修复）
          （在 body 字段说明"此数据敏感，请到 Dashboard 查看完整内容"）

        返回：[{
            id, resource_type, label, value_or_redacted,
            environment, service_name, is_sensitive,
            is_deprecated, deprecated_at, thread_id
        }]
        """
        ...
```

---

## 5. SensitiveService

```python
# rippleflow/services/interfaces/sensitive_service.py
from typing import Protocol
from uuid import UUID
from ..domain.types import (
    SensitiveCheckResult, SensitiveDecision,
    SensitiveDecisionDTO, UserId,
)


class ISensitiveService(Protocol):

    async def detect(
        self,
        message_id: UUID,
        content: str,
        sender_id: str,
        mentions: list[str],
    ) -> SensitiveCheckResult:
        """
        GLM-4-Plus 敏感内容检测。
        检测 ['privacy', 'hr', 'dispute'] 三类。
        返回敏感类型、说明、当事人列表。
        """
        ...

    async def create_authorization(
        self,
        message_id: UUID,
        result: SensitiveCheckResult,
    ) -> UUID:
        """
        创建 sensitive_authorizations 记录（所有当事人 status=pending）。
        发送 App 内通知给每位当事人。
        返回 auth_id。
        """
        ...

    async def get_pending_for_user(
        self, user_id: UserId
    ) -> list[dict]:
        """获取该用户待处理的敏感授权列表"""
        ...

    async def get_by_id(
        self,
        auth_id: UUID,
        requesting_user: UserId,
    ) -> dict:
        """
        获取敏感授权详情（含完整消息内容）。
        仅当事人可访问，否则抛 PermissionError。
        """
        ...

    async def submit_decision(
        self,
        auth_id: UUID,
        user_id: UserId,
        dto: SensitiveDecisionDTO,
    ) -> dict:
        """
        记录当事人决策，更新 decisions JSONB。
        重新计算 overall_status。
        已 reject 的无法更改（抛 ConflictError）。

        若 overall_status 变为 'authorized'（GAP-1/2 修复）：
          1. UPDATE messages SET pipeline_start_stage=1 WHERE id=message_id
             （pipeline_start_stage=1 表示跳过 Stage0，直接从 Stage1 开始）
          2. Stage1（噪声过滤）的 LLM Prompt 中注入授权上下文（GAP-2 修复）：
             Prompt 前缀追加："本消息已由所有当事人授权入库处理，
             请基于知识价值判断，不要因其涉及人事/薪资/HR信息而过滤。"
             实现方式：将 is_authorized=True 传入 Stage1 的 Prompt 构建函数，
             由 ILLMService.check_noise() 接受可选的 context_hint 参数。
          3. messages.processing_status = 'pending'
          4. 入 Celery 队列：IProcessingPipelineService.run(message_id, start_stage=1)

        若 overall_status 变为 'rejected'：
          messages.processing_status = 'sensitive_rejected'，不入队。

        返回 {overall_status, pending_count}。
        """
        ...

    async def nudge_stakeholders(
        self,
        auth_id: UUID,
        requesting_user: UserId,
    ) -> int:
        """
        向其他尚未表态的当事人发 App 内通知。
        24 小时内只能触发一次（抛 TooManyRequestsError）。
        返回发送通知数量。
        """
        ...

    async def admin_override(
        self,
        auth_id: UUID,
        action: str,
        reason: str,
        target_user: str | None = None,
    ) -> dict:
        """
        管理员强制介入（remove_stakeholder / force_authorize / force_reject）。
        写入 admin_overrides 审计日志。
        """
        ...

    async def send_daily_reminders(self) -> dict[str, int]:
        """
        发送敏感授权每日提醒。
        按提醒节奏（1/3/7/14/30 天，之后每 30 天）发送提醒。
        返回 {notified_users: N, total_pending: M}。

        注：由 nullclaw cron 定时调度，不再使用 Celery Beat。
        """
        ...
```

---

## 6. AuthService

```python
# rippleflow/services/interfaces/auth_service.py
from typing import Protocol
from ..domain.types import UserId


class IAuthService(Protocol):

    async def verify_ldap_token(self, sso_token: str) -> dict:
        """
        验证 SSO Token，从企业 LDAP 获取用户信息。
        返回 {ldap_user_id, display_name, email}。
        抛 AuthenticationError 若 Token 无效。
        """
        ...

    async def check_whitelist(self, ldap_user_id: str) -> dict:
        """
        检查用户是否在白名单中且 is_active=True。
        返回白名单条目 {ldap_user_id, display_name, role}。
        抛 ForbiddenError 若不在白名单。
        """
        ...

    def issue_jwt(self, user_info: dict) -> str:
        """签发 JWT（payload: user_id, display_name, role, exp）"""
        ...

    def verify_jwt(self, token: str) -> dict:
        """
        验证 JWT，返回 payload。
        抛 TokenExpiredError / InvalidTokenError。
        """
        ...

    async def get_current_user(self, token: str) -> dict:
        """组合 verify_jwt + check_whitelist，返回当前用户信息"""
        ...

    async def verify_api_key(self, authorization_header: str) -> dict:
        """
        验证系统级 API Key（供内部 /internal/* 端点使用）。GAP-9 修复。

        参数：authorization_header 为 HTTP Header 原始值，格式：
          "ApiKey <plaintext_key>"

        验证逻辑：
          1. 解析 header，提取 plaintext_key
          2. 计算 SHA-256(plaintext_key)
          3. 在 user_whitelist 中查询：
             WHERE api_key_hash = sha256_hex AND is_system = TRUE AND is_active = TRUE
          4. 命中 → 返回 {"user_id": ..., "role": "system", "display_name": "nullclaw"}
          5. 未命中 → 抛 AuthenticationError("Invalid API key")

        注：API Key 仅在部署时生成一次，存储其哈希值（不存明文）。
            plaintext_key 通过安全配置（如 .env 或 k8s secret）注入 nullclaw 环境变量。
        """
        ...
```

---

## 7. NotificationService

```python
# rippleflow/services/interfaces/notification_service.py
from typing import Protocol
from uuid import UUID
from ..domain.types import UserId


class INotificationService(Protocol):

    async def send(
        self,
        recipient_id: UserId,
        type: str,
        title: str,
        body: str | None = None,
        action_url: str | None = None,
        related_id: UUID | None = None,
        related_type: str | None = None,
    ) -> UUID:
        """创建 App 内通知，返回 notification_id"""
        ...

    async def send_bulk(
        self,
        recipient_ids: list[UserId],
        type: str,
        title: str,
        body: str | None = None,
        action_url: str | None = None,
    ) -> list[UUID]:
        """批量发送相同通知给多个用户"""
        ...

    async def list_for_user(
        self,
        user_id: UserId,
        unread_only: bool = False,
        page: int = 1,
        size: int = 50,
    ) -> tuple[list[dict], int, int]:
        """
        返回 (notifications, total, unread_count)
        """
        ...

    async def mark_read(
        self,
        notification_id: UUID,
        user_id: UserId,
    ) -> None:
        """标记单条通知已读（验证归属）"""
        ...

    async def mark_all_read(self, user_id: UserId) -> int:
        """标记所有通知已读，返回更新数量"""
        ...

    async def get_unread_count(self, user_id: UserId) -> int:
        ...
```

---

## 8. AdminService

```python
# rippleflow/services/interfaces/admin_service.py
from typing import Protocol
from uuid import UUID


class IAdminService(Protocol):

    # ── 白名单管理 ──────────────────────────────────────────────────
    async def list_whitelist(
        self,
        query: str | None = None,
        role: str | None = None,
        include_inactive: bool = False,
    ) -> list[dict]: ...

    async def add_to_whitelist(
        self,
        ldap_user_id: str,
        display_name: str,
        email: str | None,
        role: str,
        added_by: str,
        notes: str | None = None,
    ) -> dict:
        """
        添加用户到白名单。
        若已存在且 is_active=False，则重新激活。
        抛 ConflictError 若已在白名单。
        """
        ...

    async def update_whitelist_entry(
        self,
        ldap_user_id: str,
        updates: dict,
        operator: str,
    ) -> dict:
        """更新白名单条目。不允许管理员修改自己的 role。"""
        ...

    async def remove_from_whitelist(
        self,
        ldap_user_id: str,
        operator: str,
    ) -> None:
        """软删除（is_active=False）。不允许移除自己。"""
        ...

    # ── 类别管理 ────────────────────────────────────────────────────
    async def list_categories(self) -> list[dict]: ...

    async def create_category(
        self,
        code: str,
        display_name: str,
        trigger_hints: list[str],
        description: str | None = None,
        search_window_days: int | None = None,
    ) -> dict:
        """
        新增自定义类别。
        新类别创建后自动生效：后续消息分类时会包含此类别。
        抛 ConflictError 若 code 已存在。
        """
        ...

    async def update_category(
        self,
        category_id: UUID,
        updates: dict,
    ) -> dict:
        """
        内置类别不可修改 code 和 is_builtin。
        修改 trigger_hints 后下一次分类即生效。
        """
        ...

    # ── 统计 ────────────────────────────────────────────────────────
    async def get_system_stats(self) -> dict: ...
```

---

## 9. LLMService

```python
# rippleflow/services/interfaces/llm_service.py
from typing import Protocol
from ..domain.types import (
    NoiseCheckResult, SensitiveCheckResult,
    ClassificationResult, ThreadMatchResult,
    SummaryUpdateResult,
)


class ILLMService(Protocol):
    """
    封装所有 GLM-4-Plus API 调用。
    实现类处理重试、降级（glm-4-plus → glm-4-air → glm-4-flash）、
    错误标准化。
    """

    async def check_noise(
        self,
        content: str,
        sender_name: str,
    ) -> NoiseCheckResult:
        """Prompt: Stage 1 噪声过滤"""
        ...

    async def check_sensitive(
        self,
        content: str,
        sender_name: str,
        mentions: list[str],
    ) -> SensitiveCheckResult:
        """Prompt: Stage 0 敏感内容检测"""
        ...

    async def classify(
        self,
        content: str,
        sender_name: str,
        context_messages: list[dict],
        available_categories: list[dict],
    ) -> list[ClassificationResult]:
        """Prompt: Stage 2 多类别分类"""
        ...

    async def match_thread(
        self,
        content: str,
        category: str,
        candidate_threads: list[dict],
        time_gap_days: int | None,
    ) -> ThreadMatchResult:
        """Prompt: Stage 3 话题线索匹配"""
        ...

    async def extract_structured(
        self,
        content: str,
        category: str,
        existing_structured_data: dict,
    ) -> dict:
        """Prompt: Stage 4 结构化字段提取"""
        ...

    async def update_summary(
        self,
        current_summary: str,
        current_structured: dict,
        new_messages: list[dict],
        category: str,
    ) -> SummaryUpdateResult:
        """
        ⚠️ 已移交 nullclaw 执行。
        此 Prompt 由 nullclaw 侧调用 LLM，不在平台 ILLMService 中执行。
        Prompt 模板见 06_llm_prompt_templates.md §7。
        """
        ...

    async def extract_search_keywords(
        self,
        question: str,
    ) -> list[str]:
        """提取搜索关键词（用于全文检索）"""
        ...

    async def synthesize_answer(
        self,
        question: str,
        context_summaries: list[dict],
    ) -> str:
        """基于摘要列表合成问答答案"""
        ...

    async def generate_meeting_notes(
        self,
        messages: list[dict],
        title_hint: str | None,
    ) -> dict:
        """生成结构化纪要（议题/参与人/决策/待办/悬而未决）"""
        ...
```

---

## 10. ChatToolService

```python
# rippleflow/services/interfaces/chat_tool_service.py
from typing import Protocol


class IChatToolService(Protocol):
    """
    与自研聊天工具的集成接口。
    RippleFlow 只能通过此服务「回复」特定消息，不能主动发群。
    """

    async def send_reply(
        self,
        room_external_id: str,
        content: str,
        reply_to_msg_id: str | None = None,
        sender_display_id: str | None = None,
        content_type: str = "text",
    ) -> str:
        """
        向聊天工具发送消息。
        sender_display_id 非空时，消息冠以该用户 ID 展示（修改同步时使用）。
        返回聊天工具的 message_id。
        抛 ChatToolError 若发送失败。
        """
        ...

    async def send_card_reply(
        self,
        room_external_id: str,
        title: str,
        body: str,
        source_text: str,
        action_url: str,
        reply_to_msg_id: str | None = None,
    ) -> str:
        """
        发送富卡片消息（搜索结果/摘要展示）。
        """
        ...
```

---

## 11. BotAdapterService

```python
# rippleflow/services/interfaces/bot_adapter_service.py
from typing import Protocol
from dataclasses import dataclass


@dataclass
class BotIntent:
    """意图识别结果"""
    intent: str  # search | action_items | reference | summarize | unknown
    confidence: float
    entities: dict  # {keywords, time_range, environment, ...}


@dataclass
class BotQueryContext:
    """机器人查询上下文"""
    query: str
    user_id: str  # ldap_user_id
    room_id: str  # 群组 external_id
    reply_to_msg_id: str | None = None


@dataclass
class BotResponse:
    """机器人响应"""
    intent: str
    response_type: str  # text | card | list | error
    content: str | dict | list
    suggestions: list[str] | None = None
    error_message: str | None = None


class IBotAdapterService(Protocol):
    """
    聊天机器人适配服务。
    负责意图识别、权限验证、请求路由、响应格式化。
    """

    async def recognize_intent(
        self,
        query: str,
    ) -> BotIntent:
        """
        使用 LLM 识别用户意图。
        返回意图类型和提取的实体。
        """
        ...

    async def handle_query(
        self,
        context: BotQueryContext,
    ) -> BotResponse:
        """
        处理机器人查询的主入口。
        流程：意图识别 → 权限验证 → 路由到对应 Service → 格式化响应。
        """
        ...

    async def format_search_response(
        self,
        qa_result: dict,
        user_id: str,
    ) -> BotResponse:
        """
        将 QA 结果格式化为群聊卡片消息。
        """
        ...

    async def format_action_items_response(
        self,
        threads: list[dict],
        user_id: str,
    ) -> BotResponse:
        """
        将待办列表格式化为群聊消息。
        """
        ...

    async def format_reference_response(
        self,
        items: list[dict],
        user_id: str,
    ) -> BotResponse:
        """
        将参考数据格式化为群聊消息。
        """
        ...

    async def format_summarize_response(
        self,
        result: dict,
        user_id: str,
    ) -> BotResponse:
        """
        将纪要生成结果格式化为群聊卡片。
        """
        ...
```

---

## 12. FeedbackService

```python
# rippleflow/services/interfaces/feedback_service.py
from typing import Protocol
from dataclasses import dataclass


@dataclass
class QAFeedback:
    """问答反馈"""
    id: str
    user_id: str
    question: str
    answer: str
    is_helpful: bool
    rating: int | None
    comment: str | None
    source_thread_ids: list[str]
    created_at: str


@dataclass
class FeedbackStats:
    """反馈统计"""
    total_feedback: int
    helpful_count: int
    not_helpful_count: int
    avg_rating: float | None
    helpful_rate: float


class IFeedbackService(Protocol):
    """
    问答反馈服务。
    收集用户对问答结果的评价，支持系统优化。
    """

    async def submit_qa_feedback(
        self,
        user_id: str,
        question: str,
        answer: str,
        is_helpful: bool,
        rating: int | None = None,
        comment: str | None = None,
        source_thread_ids: list[str] | None = None,
    ) -> QAFeedback:
        """
        提交问答反馈。
        """
        ...

    async def get_feedback_stats(
        self,
        from_date: str | None = None,
        to_date: str | None = None,
    ) -> FeedbackStats:
        """
        获取反馈统计数据。
        """
        ...

    async def get_recent_feedback(
        self,
        limit: int = 50,
        is_helpful: bool | None = None,
    ) -> list[QAFeedback]:
        """
        获取最近的反馈列表。
        """
        ...

    async def get_low_rated_qa_pairs(
        self,
        threshold: float = 3.0,
        limit: int = 20,
    ) -> list[dict]:
        """
        获取低分问答对，用于优化分析。
        """
        ...
```

---

## 13. AIButlerService

```python
# rippleflow/services/interfaces/ai_butler_service.py
from typing import Protocol
from dataclasses import dataclass


@dataclass
class WeeklyDigest:
    """每周快报"""
    period: dict  # {from, to}
    summary: dict  # 统计摘要
    hot_discussions: list[dict]
    new_decisions: list[dict]
    due_action_items: list[dict]
    generated_at: str


@dataclass
class HealthReport:
    """健康报告"""
    overall_score: float
    metrics: dict
    recommendations: list[str]
    generated_at: str


@dataclass
class ButlerTask:
    """管家任务"""
    id: str
    task_type: str
    status: str
    scheduled_at: str
    executed_at: str | None
    target_room_id: str | None
    target_user_ids: list[str]
    payload: dict
    result: dict | None
    error: str | None


class IAIButlerService(Protocol):
    """
    AI 管家服务。
    负责主动运营知识库，包括快报生成、提醒推送、健康监控等。

    注：定时调度由 nullclaw cron 负责，此服务提供 CLI 命令供 nullclaw 调用。
    """

    async def generate_weekly_digest(
        self,
        from_date: str | None = None,
        to_date: str | None = None,
    ) -> WeeklyDigest:
        """
        生成每周知识快报。
        统计本周新增知识、热门讨论、即将到期待办等。
        """
        ...

    async def push_weekly_digest(
        self,
        room_id: str,
        digest: WeeklyDigest | None = None,
    ) -> str:
        """
        推送每周快报到指定群。
        返回推送的消息 ID。
        """
        ...

    async def check_action_items_due(
        self,
        days_ahead: int = 1,
    ) -> list[dict]:
        """
        检查即将到期的待办。
        返回需要提醒的待办列表。
        """
        ...

    async def push_action_item_reminders(
        self,
        room_id: str,
        action_items: list[dict],
    ) -> None:
        """
        推送待办到期提醒到群。
        """
        ...

    async def generate_health_report(
        self,
    ) -> HealthReport:
        """
        生成知识库健康报告。
        评估知识覆盖率、问答质量、用户活跃度等。
        """
        ...

    async def detect_orphan_threads(
        self,
    ) -> list[str]:
        """
        检测孤儿线索（无关联消息的线索）。
        返回孤儿线索 ID 列表。
        """
        ...

    async def analyze_feedback_patterns(
        self,
        days: int = 30,
    ) -> dict:
        """
        分析反馈模式。
        识别常见问题类型、低分答案原因等。
        """
        ...

    async def self_learning(
        self,
    ) -> dict:
        """
        管家自主学习。
        分析使用数据，更新经验知识库。
        """
        ...

    async def get_butler_experience(
        self,
        category: str | None = None,
    ) -> list[dict]:
        """
        获取管家经验知识库。
        """
        ...

    async def update_butler_experience(
        self,
        category: str,
        key: str,
        value: dict,
        confidence: float = 1.0,
    ) -> None:
        """
        更新管家经验知识库。
        """
        ...

    async def create_scheduled_task(
        self,
        task_type: str,
        scheduled_at: str,
        payload: dict,
        target_room_id: str | None = None,
        target_user_ids: list[str] | None = None,
    ) -> ButlerTask:
        """
        创建定时任务。
        """
        ...

    async def get_pending_tasks(
        self,
    ) -> list[ButlerTask]:
        """
        获取待执行的管家任务。
        """
        ...

    async def execute_task(
        self,
        task_id: str,
    ) -> ButlerTask:
        """
        执行管家任务。
        """
        ...

    async def notify_nullclaw(
        self,
        event_type: str,
        payload: dict,
    ) -> bool:
        """推送事件到 nullclaw（Fire-and-Forget，不阻塞主流程）

        RippleFlow 平台在业务操作完成后，通过此方法推送事件到 nullclaw。
        返回推送是否成功（True=直接投递成功，False=已进入待处理队列）。

        支持的事件类型及 Payload 格式（D-03 修复：多线索消息拆分为 N 条记录）：

        - message_processed（单线索消息，Stage 0-4 完成）：
            {
              "event_type": "message_processed",
              "thread_id": "<UUID>",
              "category": "<category>",
              "new_message_ids": ["<UUID>"],
              "is_new_thread": true | false
            }
          降级时写入 1 条 pending_event，thread_id = payload["thread_id"]，batch_id = NULL。

        - message_processed（多线索消息，D-03 修复）：
          当消息归属多个 category（各自生成 topic_thread），notify_nullclaw() 内部将其
          **拆分为 N 次独立调用**（每个 thread 一次），每次 payload 均为单线索格式：
            {
              "event_type": "message_processed",
              "thread_id": "<UUID>",          # 本线索 ID
              "category": "<cat>",
              "new_message_ids": ["<UUID>"],
              "is_new_thread": true | false
            }
          降级时写入 N 条 pending_event，各自 thread_id 独立，共享同一 batch_id（UUID）。
          **优势**：每个线索的事件有序性完全独立保证，不存在 thread_updates[0] 与
          thread_updates[1] 之间的重试竞态问题（D-03 问题根因消除）。

        - thread_updated：
            {"event_type": "thread_updated", "thread_id": "<UUID>", "update_type": "summary" | "status"}

        - sensitive_resolved：
            {"event_type": "sensitive_resolved", "message_id": "<UUID>", "authorized": true}

        **降级行为（P0-2，D-03 修复后）**：
        推送失败时（连接超时 / 非 2xx），事件写入 nullclaw_pending_events 表：
          - 单线索事件：写入 1 条，thread_id = payload["thread_id"]，batch_id = NULL
          - 多线索消息拆分后的每条：thread_id 独立，batch_id 相同（同一 uuid4()）
          - 其他事件（如 sensitive_resolved）：thread_id = NULL，batch_id = NULL
        后台 RetryWorker 按指数退避重试（最多 5 次，24 小时内）。
        不抛出异常——nullclaw 不可用不影响平台核心流程。

        **超时设置**：HTTP POST 超时 500ms，不等待 nullclaw 处理结果。
        """
        ...

    async def list_pending_events(
        self,
        status: str = "pending",
        limit: int = 100,
    ) -> list[dict]:
        """获取待处理事件队列状态（运维/健康检查使用）"""
        ...

    async def retry_pending_events(self) -> int:
        """后台 RetryWorker 调用：重试到期的待处理事件，返回本次成功投递数量

        重试策略（指数退避）：
        retry_count=0 → 立即重试
        retry_count=1 → 30s 后
        retry_count=2 → 5min 后
        retry_count=3 → 30min 后
        retry_count=4 → 2h 后
        retry_count≥5 → status → 'expired'，告警管理员

        **有序重试保证（GAP-10 修复）**：
        同一 thread_id 的 pending 事件必须按 created_at ASC 顺序逐一投递，
        前一条未成功前不投递后续同 thread_id 的事件（利用 idx_pending_events_thread 索引）。
        实现示例：
          SELECT * FROM nullclaw_pending_events
          WHERE status='pending' AND next_retry_at <= NOW()
          ORDER BY thread_id NULLS LAST, created_at ASC;
          -- 按 thread_id 分组，每个 thread_id 只取 min(created_at) 那条处理
          -- thread_id IS NULL 的事件（如 sensitive_resolved）不受此限制，并行重试。
        """
        ...
```

---

## 附录 A. 异常类型定义

```python
# rippleflow/domain/exceptions.py

class RippleFlowError(Exception):
    """基础异常"""

class AuthenticationError(RippleFlowError):
    """LDAP/Token 验证失败"""

class ForbiddenError(RippleFlowError):
    """权限不足（非白名单 / 非当事人）"""

class NotFoundError(RippleFlowError):
    """资源不存在"""

class ConflictError(RippleFlowError):
    """状态冲突（如已授权重复授权）"""

class ValidationError(RippleFlowError):
    """业务规则校验失败"""

class TooManyRequestsError(RippleFlowError):
    """频率限制（如 nudge 24小时限制）"""

class LLMServiceError(RippleFlowError):
    """LLM API 调用失败（重试耗尽后）"""

class ChatToolError(RippleFlowError):
    """聊天工具 API 调用失败"""

class BotAuthError(RippleFlowError):
    """机器人认证失败"""

class IntentRecognitionError(RippleFlowError):
    """意图识别失败"""

class TokenExpiredError(AuthenticationError):
    """JWT 已过期"""

class InvalidTokenError(AuthenticationError):
    """JWT 无效"""
```

---

## 附录 B. 接口依赖关系图（v0.5）

```
ProcessingPipelineService
    ├── MessageService          (Stage 0/1/2/3/4/5 读取消息)
    ├── LLMService              (各阶段 LLM 调用)
    ├── ThreadService           (创建/扩展线索)
    ├── SensitiveService        (Stage 0 检测 + 授权管理)
    └── NotificationService     (发送 App 内通知)

SearchService
    └── LLMService              (关键词提取 + 答案综合)

ThreadService
    ├── SensitiveService        (当事人验证)
    └── ChatToolService         (修改同步到群，用户确认后)

AdminService
    └── NotificationService     (操作结果通知)

SensitiveService
    ├── NotificationService     (授权提醒)
    └── MessageService          (授权通过后重入队列)

BotAdapterService
    ├── LLMService              (意图识别)
    ├── SearchService           (搜索/问答)
    ├── ThreadService           (待办查询/纪要生成)
    ├── AuthService             (用户权限验证)
    └── ChatToolService         (发送回复到群)

FeedbackService
    └── NotificationService     (反馈感谢通知)

AIButlerService
    ├── LLMService              (快报生成/分析)
    ├── ThreadService           (数据统计)
    ├── NotificationService     (提醒推送)
    ├── FeedbackService         (反馈分析)
    ├── ChatToolService         (群聊推送)
    └── AuthService             (权限验证)

SubscriptionService
    ├── NotificationService     (订阅事件通知)
    └── AuthService             (用户验证)

PersonalTodoService
    ├── NotificationService     (待办提醒、协作者通知)
    ├── SubscriptionService     (发布待办时通知关注者)
    ├── ThreadService           (从 action_item 转换)
    └── AuthService             (权限验证)
```

---

## 14. SubscriptionService

```python
# rippleflow/services/interfaces/subscription_service.py
from typing import Protocol
from dataclasses import dataclass


@dataclass
class Subscription:
    """订阅记录"""
    id: str
    user_id: str
    subscription_type: str
    # 'user' | 'thread' | 'category' | 'keyword'
    # | 'todo' | 'resource' | 'event' | 'document' | 'shared_link' | 'workflow'
    target_id: str
    target_name: str | None
    notification_types: list[str]
    is_active: bool
    created_at: str
    updated_at: str


class ISubscriptionService(Protocol):
    """
    订阅/关注服务。
    支持用户关注人、话题、类别、关键词，并在相关事件发生时推送通知。
    """

    async def subscribe(
        self,
        user_id: str,
        subscription_type: str,
        target_id: str,
        notification_types: list[str] | None = None,
        filter_criteria: dict | None = None,
    ) -> Subscription:
        """创建订阅。filter_criteria 可选：{"author":"zhangsan"} 或 {"tags":["redis"]}"""
        ...

    async def unsubscribe(self, subscription_id: str, user_id: str) -> None:
        """取消订阅。"""
        ...

    async def get_user_subscriptions(
        self,
        user_id: str,
        subscription_type: str | None = None,
    ) -> list[Subscription]:
        """获取用户的订阅列表。"""
        ...

    async def get_subscribers(
        self,
        subscription_type: str,
        target_id: str,
    ) -> list[str]:
        """获取某对象的订阅者列表。"""
        ...

    async def publish_event(
        self,
        event_type: str,
        actor_id: str | None,
        target_type: str,
        target_id: str,
        payload: dict | None = None,
    ) -> list[str]:
        """
        发布订阅事件，通知相关订阅者。
        返回值：被通知到的 user_id 列表（已生成 queued_notifications）。

        事件分发逻辑：
        1. 直接订阅匹配：subscription_type=target_type，target_id=target_id
           → 精确匹配订阅者
        2. 用户订阅匹配：subscription_type='user'，target_id=actor_id
           → 所有关注了该作者的订阅者
        3. 类别订阅匹配：subscription_type='category'，target_id=payload.get('category')
           → 订阅了该内容类别的用户
        4. 关键词订阅匹配（异步，非阻塞）：
           → 提交到后台任务队列，由 KeywordMatcher Worker 处理：
              SELECT user_id, target_id as keyword
              FROM user_subscriptions
              WHERE subscription_type='keyword' AND is_active=TRUE;
              对每个 keyword 做 PostgreSQL 全文匹配：
              to_tsvector('chinese', payload_text) @@ plainto_tsquery('chinese', keyword)
              命中则生成 subscription_events(event_type='keyword_matched')
              再走普通通知分发流程。
           注：关键词匹配覆盖 user_documents/shared_links/topic_threads，
              由 payload 中的 searchable_text 字段提供匹配文本。

        **searchable_text 构建规范（GAP-17 修复）**：
        各调用方在传入 payload 时须包含 searchable_text，构建规则如下：
        - topic_thread：
            searchable_text = f"{thread.title} {thread.summary} {message.content}"
            （summary 可能为 None，跳过空字段）
        - user_document：
            searchable_text = f"{doc.title} {doc.summary or ''} {doc.content[:500]}"
            （content 截取前 500 字防止过长）
        - shared_link：
            searchable_text = f"{link.title or ''} {link.description or ''} {link.url}"
        - todo/action_item：
            searchable_text = f"{todo.title} {todo.description or ''}"
        关键词匹配使用 PostgreSQL：
            to_tsvector('simple', searchable_text) @@ plainto_tsquery('simple', keyword)
        注：使用 'simple' 字典（非 'chinese'），以兼容无中文插件的标准 PostgreSQL 部署。
            中文支持需安装 zhparser 扩展后改用 'chinese' 字典。

        filter_criteria 过滤：匹配到订阅者后，再检查 filter_criteria 是否与 payload 相符，
        不符合的订阅者静默跳过（不生成通知）。
        """
        ...

    async def get_followable_targets(
        self,
        entity_type: str,
        query: str,
        limit: int = 10,
    ) -> list[dict]:
        """
        搜索可关注的对象，供前端订阅选择器使用。

        entity_type 对应的查询逻辑：
        - 'user'        → ldap_users 表，模糊匹配 display_name/username
        - 'thread'      → topic_threads 表，模糊匹配 title/summary
        - 'todo'        → personal_todos 表，visibility ≠ 'private'，模糊匹配 title
        - 'document'    → user_documents 表，已发布，模糊匹配 title
        - 'shared_link' → shared_links 表，模糊匹配 title/url
        - 'workflow'    → workflow_templates 表，模糊匹配 name
        - 'category'    → 枚举返回9大内置类别（query过滤名称）
        - 'keyword'     → 返回已有高频关键词（来自 butler_suggestions 采纳记录 + 历史标签），
                         同时支持用户输入新关键词（query 不匹配任何已有词时，返回 query 本身作为候选）

        返回：[{"id": ..., "name": ..., "type": ..., "description": ..., "subscriber_count": ...}]
        """
        ...
```

---

## 15. PersonalTodoService

```python
# rippleflow/services/interfaces/personal_todo_service.py
from typing import Protocol
from dataclasses import dataclass
from datetime import date, time


@dataclass
class PersonalTodo:
    """个人待办"""
    id: str
    user_id: str
    title: str
    description: str | None
    status: str  # 'pending' | 'in_progress' | 'completed' | 'cancelled'
    priority: str  # 'low' | 'medium' | 'high' | 'urgent'
    due_date: date | None
    due_time: time | None
    visibility: str  # 'private' | 'followers' | 'team' | 'public'
    tags: list[str]
    category: str | None
    reminder_enabled: bool
    created_at: str
    updated_at: str


@dataclass
class TodoStats:
    """待办统计"""
    total: int
    pending: int
    in_progress: int
    completed: int
    overdue: int
    due_today: int
    due_this_week: int


class IPersonalTodoService(Protocol):
    """
    个人待办服务。
    支持用户管理自己的待办事项，并可发布给关注者查看。
    支持从群聊消息自动识别任务并创建待办。
    """

    async def create_todo(
        self,
        user_id: str,
        title: str,
        description: str | None = None,
        priority: str = 'medium',
        due_date: date | None = None,
        visibility: str = 'private',
        tags: list[str] | None = None,
        participant_ids: list[dict] | None = None,
        # [{"user_id": "alice", "role": "responsible"}, ...]
        task_elements: dict | None = None,
    ) -> PersonalTodo:
        """创建待办事项。"""
        ...

    async def create_from_group_message(
        self,
        message_id: str,
        room_id: str,
        extracted_task: dict,
    ) -> list[PersonalTodo]:
        """
        从群聊消息创建待办。
        extracted_task 由 LLM 从消息中提取：
        {
            "title": "配置 Redis 集群",
            "assignees": [{"user_id": "alice", "role": "responsible"}],
            "due_date": "2026-03-10",
            "priority": "high",
            "task_elements": {
                "resources": ["服务器"],
                "dependencies": ["DBA审批"],
                "deliverables": ["配置文档"]
            },
            "missing_elements": ["due_date", "resources"]
        }
        返回创建的待办列表（可能多条，每个责任人一条）。
        """
        ...

    async def update_todo(self, todo_id: str, user_id: str, **updates) -> PersonalTodo:
        """更新待办事项。"""
        ...

    async def delete_todo(self, todo_id: str, user_id: str) -> None:
        """删除待办事项。"""
        ...

    async def list_todos(
        self,
        user_id: str,
        status: str | None = None,
        include_participated: bool = False,
    ) -> tuple[list[PersonalTodo], int, int]:
        """获取用户的待办列表。返回 (列表, 总数, 过期数)。"""
        ...

    async def complete_todo(
        self,
        todo_id: str,
        user_id: str,
        comment: str | None = None,
    ) -> PersonalTodo:
        """标记待办完成。"""
        ...

    async def confirm_task_elements(
        self,
        todo_id: str,
        user_id: str,
        confirmed_elements: dict,
    ) -> PersonalTodo:
        """
        确认/补充任务要素。
        用户对管家询问的缺失要素进行确认。
        """
        ...

    async def get_todos_needing_confirmation(
        self,
        user_id: str,
    ) -> list[PersonalTodo]:
        """获取需要用户确认要素的待办列表。"""
        ...

    async def add_participant(
        self,
        todo_id: str,
        user_id: str,
        participant_user_id: str,
        role: str = 'informed',
    ) -> None:
        """添加任务参与人。"""
        ...

    async def get_user_public_todos(
        self,
        viewer_id: str,
        target_user_id: str,
    ) -> tuple[list[PersonalTodo], int]:
        """获取某用户的公开待办。"""
        ...

    async def get_stats(self, user_id: str) -> TodoStats:
        """获取待办统计。"""
        ...

    async def check_reminders(self) -> list[dict]:
        """检查需要提醒的待办。由 nullclaw cron 定时调用。"""
        ...

    async def sync_from_action_item(
        self,
        thread_id: str,
        default_visibility: str = 'team',
    ) -> list[PersonalTodo]:
        """
        从知识库中的 action_item 同步到个人待办。
        当群聊中的 action_item 被识别后，由 IProcessingPipelineService.run() 在 Stage 4
        完成后自动调用（GAP-3 修复：Pipeline 显式调用点）。

        执行逻辑：
        1. 读取 topic_threads.structured_data（category='action_item'）
           提取 assignee（可能多人）、due_date、priority、task 描述
        2. 对每个 assignee 调用 create_todo()：
           - user_id = assignee（ldap_user_id）
           - title = structured_data.task
           - due_date = structured_data.due_date（若未识别，置 None）
           - priority = structured_data.priority（默认 'medium'）
           - visibility = default_visibility（GAP-4 修复：默认 'team' 而非 'private'）
             从群聊识别的任务应对发布者和团队可见；可由 IProcessingPipelineService
             根据群组配置覆盖（如群组设定为 'team' 或 'followers'）
           - source_type = 'action_item'
           - source_id = thread_id
        3. create_todo() 内部：
           - 写入 personal_todos
           - 调用 INotificationService.send(type='action_item_assigned')，通知被指派人
           - 若 visibility != 'private'，调用 ISubscriptionService.publish_event()
             但注意 GAP-16 修复：此 publish_event() 不触发 keyword 通知，
             keyword 通知由 nullclaw Stage5 完成后通过 /internal/subscriptions/publish 触发
        4. 返回已创建的 PersonalTodo 列表
        """
        ...
```

---

## 附录 C. 接口依赖关系图（v0.6 更新）

```
ProcessingPipelineService
    ├── MessageService         (Stage 0-4 读写消息状态，幂等入库)
    ├── LLMService             (各 Stage 的 LLM 调用)
    ├── ThreadService          (Stage 3 创建/匹配线索)
    ├── SensitiveService       (Stage 0 敏感检测 + 授权管理)
    ├── NotificationService    (Stage 0 敏感通知)
    ├── PersonalTodoService    (GAP-3修复：Stage 4 action_item → 自动创建待办)
    └── NullclawPublisherService (Stage 4 完成后 notify_nullclaw，多线索 payload)

BotAdapterService
    ├── LLMService
    ├── SearchService
    ├── ThreadService
    ├── AuthService
    └── ChatToolService

AIButlerService
    ├── LLMService
    ├── ThreadService
    ├── NotificationService
    ├── FeedbackService
    ├── PersonalTodoService      ← 新增
    ├── SubscriptionService      ← 新增
    └── AuthService

SubscriptionService
    ├── NotificationService
    └── AuthService

PersonalTodoService
    ├── NotificationService
    ├── SubscriptionService
    └── AuthService

LogService
    ├── NotificationService
    └── AIButlerService

ExceptionNotificationService
    ├── LogService
    ├── NotificationService
    └── AIButlerService
```

---

## 16. LogService（日志服务）

```python
class LogEntry(TypedDict):
    """日志条目"""
    id: str                      # 日志 ID
    timestamp: str               # ISO8601 时间戳
    level: str                   # DEBUG | INFO | WARNING | ERROR | CRITICAL
    category: str                # api_access | business | llm | exception | audit | client
    service: str                 # 服务名称
    message: str                 # 日志消息
    details: dict                # 详细信息
    request_id: str | None       # 请求 ID
    user_id: str | None          # 用户 ID
    session_id: str | None       # 会话 ID
    client_ip: str | None        # 客户端 IP
    duration_ms: int | None      # 耗时（毫秒）
    exception_type: str | None   # 异常类型
    stack_trace: str | None      # 堆栈信息


class ExceptionEvent(TypedDict):
    """异常事件"""
    id: str
    timestamp: str
    severity: str                # critical | error | warning
    exception_type: str
    exception_message: str
    stack_trace: str
    context: dict
    request_id: str | None
    user_id: str | None
    affected_count: int          # 影响次数
    first_occurred: str
    last_occurred: str
    status: str                  # new | acknowledged | resolved


class ILogService(Protocol):
    """
    日志服务。
    负责日志采集、存储、查询和异常检测。
    """

    async def write_log(
        self,
        level: str,
        category: str,
        service: str,
        message: str,
        details: dict | None = None,
        request_id: str | None = None,
        user_id: str | None = None,
    ) -> str:
        """
        写入日志条目。
        返回日志 ID。
        """
        ...

    async def write_exception(
        self,
        exception: Exception,
        context: dict | None = None,
        request_id: str | None = None,
        user_id: str | None = None,
    ) -> str:
        """
        写入异常日志。
        自动提取异常类型、消息和堆栈。
        返回日志 ID。
        """
        ...

    async def search_logs(
        self,
        start_time: str,
        end_time: str,
        level: str | None = None,
        category: str | None = None,
        service: str | None = None,
        request_id: str | None = None,
        user_id: str | None = None,
        keyword: str | None = None,
        page: int = 1,
        size: int = 50,
    ) -> tuple[list[LogEntry], int]:
        """
        搜索日志。
        返回 (日志列表, 总数)。
        """
        ...

    async def get_exception_events(
        self,
        status: str | None = None,
        severity: str | None = None,
        since: str | None = None,
    ) -> list[ExceptionEvent]:
        """
        获取异常事件列表。
        用于异常监控面板。
        """
        ...

    async def acknowledge_exception(
        self,
        exception_id: str,
        acknowledged_by: str,
        note: str | None = None,
    ) -> None:
        """
        确认异常（标记为已知）。
        """
        ...

    async def resolve_exception(
        self,
        exception_id: str,
        resolved_by: str,
        resolution: str,
    ) -> None:
        """
        解决异常（标记为已修复）。
        """
        ...

    async def get_log_statistics(
        self,
        start_time: str,
        end_time: str,
        group_by: str = 'category',  # category | level | service | hour
    ) -> dict:
        """
        获取日志统计。
        用于监控面板。
        """
        ...
```

---

## 17. ExceptionNotificationService（异常通知服务）

```python
class NotificationChannel(TypedDict):
    """通知通道配置"""
    type: str                    # email | webhook
    enabled: bool
    recipients: list[str]        # Email 地址列表 或 Webhook URL
    template: str                # 模板名称
    cooldown_seconds: int        # 冷却时间（同一异常）


class IExceptionNotificationService(Protocol):
    """
    异常通知服务。
    负责检测异常并通知 AI 管家，由 AI 管家决定通知渠道。
    """

    async def detect_exceptions(self) -> list[ExceptionEvent]:
        """
        检测新异常。
        基于预定义规则检测异常事件。
        返回需要处理的异常列表。
        """
        ...

    async def notify_butler(
        self,
        exception: ExceptionEvent,
    ) -> None:
        """
        通知 AI 管家有新异常。
        AI 管家根据异常严重程度决定通知策略。
        """
        ...

    async def send_email_notification(
        self,
        exception: ExceptionEvent,
        recipients: list[str],
    ) -> bool:
        """
        发送 Email 通知给管理员。
        返回是否发送成功。
        """
        ...

    async def send_webhook_notification(
        self,
        exception: ExceptionEvent,
        webhook_url: str,
    ) -> bool:
        """
        发送 Webhook 通知给 nullclaw 自动开发团队。
        返回是否发送成功。
        """
        ...

    async def get_notification_history(
        self,
        exception_id: str,
    ) -> list[dict]:
        """
        获取异常的通知历史。
        """
        ...

    async def should_notify(
        self,
        exception: ExceptionEvent,
        channel: NotificationChannel,
    ) -> bool:
        """
        判断是否应该发送通知。
        检查冷却时间、已确认状态等。
        """
        ...
```

---

## 18. ButlerPushConfigService（管家推送配置服务）

```python
# rippleflow/services/interfaces/butler_push_config_service.py
from typing import Protocol
from uuid import UUID


class IButlerPushConfigService(Protocol):
    """
    管家推送配置服务（GAP-15 修复）。

    nullclaw 在 Routine 执行前通过此服务读取推送目标配置，
    管理员通过 Admin API 更新配置，无需重启服务。

    解决的问题：nullclaw 原来硬编码推送目标房间 ID，
    部署环境变化时需要修改代码并重新部署 nullclaw。
    通过此服务，nullclaw 动态读取配置，管理员可在运行时调整。
    """

    async def get_config(
        self,
        group_id: str = "default",
        config_type: str | None = None,
    ) -> list[dict]:
        """
        获取推送配置列表（nullclaw Routine 开始前调用）。

        返回格式：
        [
          {
            "config_type": "daily_digest_room",
            "target_room_id": "general",
            "target_room_name": "综合频道",
            "enabled": True,
            "schedule": "0 9 * * 1-5",
            "custom_prompt": None
          },
          ...
        ]
        仅返回 enabled=True 的配置项。
        """
        ...

    async def upsert_config(
        self,
        group_id: str,
        config_type: str,
        target_room_id: str,
        target_room_name: str | None = None,
        enabled: bool = True,
        schedule: str | None = None,
        custom_prompt: str | None = None,
        updated_by: str = "admin",
    ) -> dict:
        """
        创建或更新推送配置（管理员调用）。
        使用 INSERT ... ON CONFLICT (group_id, config_type) DO UPDATE 语义。
        返回更新后的配置项。
        """
        ...

    async def disable_config(self, group_id: str, config_type: str) -> None:
        """禁用某类推送（临时关闭日报等）"""
        ...
```

---

## 附录 D. 配置项定义

```python
class LogConfig(TypedDict):
    """日志配置"""
    level: str                   # DEBUG | INFO | WARNING | ERROR | CRITICAL
    format: str                  # json | text
    path: str                    # 日志文件路径
    max_file_size_mb: int        # 单文件最大大小
    max_backup_count: int        # 备份文件数量
    retention_days: int          # 保留天数

    # 分类配置
    categories: dict[str, dict]  # 各分类的具体配置

    # 异常检测
    exception_detection: dict

    # 通知配置
    notification: "NotificationConfig"


class NotificationConfig(TypedDict):
    """通知配置"""
    # Email 配置
    email: dict[str, Any]
    # 管理员邮箱列表
    admin_emails: list[str]
    # SMTP 配置
    smtp: dict[str, str]

    # Webhook 配置
    webhook: dict[str, Any]
    # nullclaw 开发团队 Webhook
    dev_channel_webhook: str

    # 冷却时间
    cooldown_seconds: int
```

---

## 附录 E. 接口依赖关系图（v0.7 最终版）

```
LogService
    ├── NotificationService
    └── AIButlerService

ExceptionNotificationService
    ├── LogService
    ├── NotificationService
    └── AIButlerService

AIButlerService
    ├── LogService              ← 新增
    ├── ExceptionNotificationService  ← 新增
    ├── LLMService
    ├── ThreadService
    ├── NotificationService
    ├── FeedbackService
    ├── PersonalTodoService
    ├── SubscriptionService
    └── AuthService
```

---

## 19. FaqService（FAQ 知识库服务）

> **归属**：RippleFlow 平台层，提供 FAQ CRUD + 审核 + 搜索接口
> **调用方**：nullclaw（写入/更新）+ Web Dashboard（查询）+ BotAdapterService（问答引用）
> **职责**：仅提供存储与查询机制，不含生成策略（策略由 nullclaw 决定）

```python
from typing import Protocol, TypedDict
from uuid import UUID
from datetime import datetime


class FaqItemDTO(TypedDict):
    """FAQ 条目数据传输对象"""
    id: UUID
    section_id: UUID
    question: str
    answer: str
    question_variants: list[str]          # 相似问法
    source_threads: list[str]             # 来源 thread_id 列表
    confidence: float                     # AI 置信度 (0-1)
    view_count: int
    helpful_count: int
    review_status: str                    # pending | confirmed | rejected
    reviewed_by: str | None
    reviewed_at: datetime | None
    created_by: str                       # 'nullclaw' | user_id
    created_at: datetime
    updated_at: datetime


class FaqSectionDTO(TypedDict):
    """FAQ 章节数据传输对象"""
    id: UUID
    doc_id: UUID
    parent_id: UUID | None
    title: str
    sort_order: int
    items: list[FaqItemDTO]              # 该章节下的条目


class FaqDocumentDTO(TypedDict):
    """FAQ 文档（每群一份）"""
    id: UUID
    group_id: str
    version: int
    qa_count: int
    updated_at: datetime
    sections: list[FaqSectionDTO]


class FaqVersionDTO(TypedDict):
    """FAQ 变更历史条目"""
    id: UUID
    item_id: UUID
    version: int
    question: str
    answer: str
    change_type: str                      # created | updated | merged | reviewed | rejected
    change_by: str
    change_reason: str | None
    created_at: datetime


class IFaqService(Protocol):
    """FAQ 知识库服务接口
    
    RippleFlow 平台提供 FAQ 存储和查询机制，所有 AI 生成策略由 nullclaw 在外部决定。
    nullclaw 通过调用本接口的 create_item / update_item / merge_items 写入 FAQ 内容。
    """

    # ── 文档与章节 ─────────────────────────────────────────────────────────

    async def get_document(
        self,
        group_id: str,
        caller_role: str = "member",      # member | admin
    ) -> FaqDocumentDTO:
        """获取群 FAQ 文档（章节树 + 基本统计）
        
        member 只能看到 review_status=confirmed 的条目。
        admin 可见全部状态条目（pending/confirmed/rejected）。
        """
        ...

    async def ensure_section(
        self,
        doc_id: UUID,
        title: str,
        parent_id: UUID | None = None,
    ) -> UUID:
        """获取或创建指定标题的章节，返回 section_id
        
        若已存在同标题章节则直接返回，不重复创建。
        nullclaw 在写入 FAQ 前调用以确定归属章节。
        """
        ...

    # ── FAQ 条目 CRUD ───────────────────────────────────────────────────────

    async def create_item(
        self,
        section_id: UUID,
        question: str,
        answer: str,
        source_threads: list[str],
        created_by: str = "nullclaw",
        question_variants: list[str] | None = None,
        confidence: float = 0.8,
    ) -> FaqItemDTO:
        """创建 FAQ 条目，默认 review_status=pending
        
        写入后自动创建 faq_versions 初始快照（change_type=created）。
        """
        ...

    async def get_item(
        self,
        item_id: UUID,
        caller_role: str = "member",
    ) -> FaqItemDTO:
        """获取单条 FAQ 条目
        
        member 只能获取 confirmed 状态条目，否则抛 PermissionError。
        """
        ...

    async def update_item(
        self,
        item_id: UUID,
        question: str | None = None,
        answer: str | None = None,
        question_variants: list[str] | None = None,
        source_threads: list[str] | None = None,
        confidence: float | None = None,
        change_by: str = "nullclaw",
        change_reason: str = "",
    ) -> FaqItemDTO:
        """更新 FAQ 条目，自动创建版本快照（change_type=updated）"""
        ...

    async def merge_items(
        self,
        source_ids: list[UUID],
        target: dict,                     # {question, answer, question_variants}
        merge_by: str = "nullclaw",
        merge_reason: str = "",
    ) -> FaqItemDTO:
        """合并多条重复 FAQ，保留所有 source_threads，删除原始条目"""
        ...

    # ── 审核 ────────────────────────────────────────────────────────────────

    async def review_item(
        self,
        item_id: UUID,
        reviewer_id: str,
        action: str,                      # confirm | reject
        reason: str = "",
    ) -> FaqItemDTO:
        """管理员审核 FAQ 条目
        
        confirm: review_status → confirmed，对普通用户可见
        reject:  review_status → rejected，从普通用户视图隐藏
        自动创建 faq_versions 快照（change_type=reviewed/rejected）。
        """
        ...

    async def list_pending_review(
        self,
        group_id: str,
        page: int = 1,
        size: int = 20,
    ) -> tuple[list[FaqItemDTO], int]:
        """获取待审核 FAQ 队列（仅管理员调用）"""
        ...

    # ── 搜索与查询 ──────────────────────────────────────────────────────────

    async def list_items(
        self,
        group_id: str,
        section_id: UUID | None = None,
        caller_role: str = "member",
        page: int = 1,
        size: int = 20,
        sort_by: str = "view_count",      # view_count | updated_at | confidence
    ) -> tuple[list[FaqItemDTO], int]:
        """分页获取 FAQ 条目，member 只见 confirmed"""
        ...

    async def search(
        self,
        group_id: str,
        query: str,
        caller_role: str = "member",
        limit: int = 10,
    ) -> list[FaqItemDTO]:
        """FAQ 全文搜索，使用 PostgreSQL tsvector / SQLite FTS5
        
        返回按相关度排序的结果，member 只见 confirmed 条目。
        """
        ...

    # ── 反馈与统计 ──────────────────────────────────────────────────────────

    async def submit_feedback(
        self,
        item_id: UUID,
        user_id: str,
        feedback_type: str,               # helpful | unhelpful
        comment: str = "",
    ) -> None:
        """提交用户反馈，更新 helpful_count / view_count"""
        ...

    async def increment_view_count(
        self,
        item_id: UUID,
    ) -> None:
        """查看 FAQ 条目时调用，递增 view_count"""
        ...

    # ── 版本历史 ────────────────────────────────────────────────────────────

    async def get_versions(
        self,
        item_id: UUID,
    ) -> list[FaqVersionDTO]:
        """获取 FAQ 条目的完整变更历史，按版本号降序"""
        ...

    # ── 质量保障（P0-1）──────────────────────────────────────────────────────

    async def quarantine_item(
        self,
        item_id: UUID,
        operator_id: str,
        action: str,                      # quarantine | restore
        reason: str = "",
    ) -> FaqItemDTO:
        """隔离或恢复 FAQ 条目

        quarantine: quality_status → quarantined，对普通用户不可见
        restore:    quality_status → normal，恢复可见
        自动创建 faq_versions 快照（change_type=quality_quarantine/quality_restore）。
        仅管理员可调用；nullclaw 不得直接调用。
        """
        ...

    async def list_alerts(
        self,
        group_id: str,
        status: str = "open",             # open | resolved | dismissed | all
        alert_type: str | None = None,
        page: int = 1,
        size: int = 20,
    ) -> tuple[list[FaqQualityAlertDTO], int]:
        """获取 FAQ 质量告警列表（仅管理员调用）

        告警由平台自动触发，条件：
        - unhelpful_threshold：unhelpful_count ≥ 2，quality_status → suspicious
        - zero_helpful_30d：30天内有查看但 helpful_count=0
        - stale_content：staleness_days 天内未更新（默认90天）
        - conflict_detected：nullclaw 检测到与其他条目语义冲突
        - manual_flag：管理员或 nullclaw 手动标记
        """
        ...

    async def resolve_alert(
        self,
        alert_id: UUID,
        resolver_id: str,
        action: str,                      # resolve_update | quarantine | reject | dismiss
        resolution_note: str = "",
    ) -> FaqQualityAlertDTO:
        """处理质量告警

        resolve_update: 条目已更新，告警 → resolved，quality_status → normal
        quarantine:     条目隔离，告警 → resolved，调用 quarantine_item
        reject:         条目废弃（review_status → rejected），告警 → resolved
        dismiss:        忽略告警，告警 → dismissed，quality_status 不变
        """
        ...
```

### 接口约束说明

| 约束 | 说明 |
|------|------|
| **权限隔离** | member 只能读取 `confirmed` 且 `quality_status != quarantined` 的条目 |
| **版本快照** | `create_item`、`update_item`、`review_item`、`merge_items`、`quarantine_item` 均自动写入 `faq_versions` |
| **nullclaw 权限** | nullclaw 持有 `bot_token`，可调用 `create_item`、`update_item`、`merge_items`；**不可**直接调用 `quarantine_item` |
| **审核前不公开** | 默认 `pending`，管理员 `confirm` 后才对普通用户可见 |
| **无向量检索** | `search` 方法使用全文检索（PostgreSQL FTS / SQLite FTS5），不使用 embedding |
| **质量告警触发** | 平台自动监测（unhelpful/stale/conflict），告警写入 `faq_quality_alerts`，推送管理员 |

---

## 附录 F. 接口依赖关系图（含 FaqService）

```
FaqService
    └── (纯存储层，无外部依赖)

BotAdapterService
    ├── FaqService          ← 新增（机器人问答优先引用 FAQ）
    ├── SearchService
    ├── LLMService
    ├── PersonalTodoService
    └── AuthService

AIButlerService（nullclaw 通过 HTTP 调用平台 API，非直接依赖）
    ├── POST /api/v1/faq/items        ← 写入 FAQ
    ├── PUT  /api/v1/faq/items/{id}   ← 更新 FAQ
    ├── POST /api/v1/faq/items/merge  ← 合并 FAQ
    └── GET  /api/v1/faq/{group_id}/search ← 查询现有 FAQ
```


---

## 20. IPresenceService

```python
# rippleflow/services/interfaces/presence_service.py
from typing import Protocol
from datetime import datetime

class IPresenceService(Protocol):
    """用户在线状态与离线消息队列服务（需求2+4）

    平台通过 Heartbeat API 维护用户在线状态，
    并在用户上线时批量推送缓存的离线通知。
    """

    async def heartbeat(
        self,
        user_id: str,
        client_info: dict | None = None,
    ) -> list[dict]:
        """处理客户端心跳

        1. 更新 user_presence（status=online, last_heartbeat=NOW()）
        2. 查询 queued_notifications WHERE delivered_at IS NULL
           ORDER BY priority, created_at LIMIT 50
        3. 标记 delivered_at=NOW()
        4. 触发 on_user_online Event Hook（如有注册）

        返回：待推送的通知列表
        """
        ...

    async def mark_offline(self, user_id: str) -> None:
        """将超过60秒未心跳的用户标记为离线（后台定时任务调用）"""
        ...

    async def get_status(self, user_id: str) -> dict:
        """获取用户在线状态（online/idle/offline）"""
        ...

    async def get_online_users(
        self,
        group_id: str | None = None,
    ) -> list[dict]:
        """获取当前在线用户列表（管理员/管家使用）"""
        ...

    async def enqueue_notification(
        self,
        user_id: str,
        event_type: str,
        payload: dict,
        priority: int = 5,
        expires_at: datetime | None = None,
    ) -> str:
        """向指定用户的离线队列写入通知

        用户在线时：尝试直接推送（通过 App 内通知）
        用户离线时：写入 queued_notifications，等待下次 Heartbeat

        priority 建议值：
        - 1: mention / 敏感授权到期提醒
        - 3: 工作流待审批 / 待办到期
        - 5: 每日摘要 / FAQ 质量告警

        返回 queued_notification.id
        """
        ...

    async def get_queue(
        self,
        user_id: str,
        undelivered_only: bool = True,
        limit: int = 50,
    ) -> list[dict]:
        """获取用户的通知队列（主要供 Heartbeat 内部使用）"""
        ...
```

---

## 21. IWorkflowService

```python
# rippleflow/services/interfaces/workflow_service.py
from typing import Protocol
from uuid import UUID

class IWorkflowService(Protocol):
    """工作流托管服务（需求3）

    平台提供工作流模板存储和实例执行的机制层；
    nullclaw 负责触发条件识别、模板学习和执行决策（策略层）。
    """

    # ── 工作流模板 ────────────────────────────────────────────────

    async def create_template(
        self,
        name: str,
        trigger_pattern: str,
        steps: list[dict],
        trigger_regex: str | None = None,
        style_notes: str | None = None,
        learned_from: list[str] | None = None,
    ) -> dict:
        """创建工作流模板（nullclaw 学习后调用）

        steps 格式示例：
        [
          {"step": 1, "action": "notify_user",   "target": "@user", "template": "..."},
          {"step": 2, "action": "create_todo",   "assignee": "...", "due_offset_days": 3},
          {"step": 3, "action": "cross_delegate", "target_group": "...", "task": "..."}
        ]
        """
        ...

    async def list_templates(
        self,
        trust_level: str | None = None,    # supervised | autonomous
        page: int = 1,
        size: int = 20,
    ) -> tuple[list[dict], int]:
        """列出工作流模板"""
        ...

    async def update_template(
        self,
        template_id: UUID,
        style_notes: str | None = None,
        trust_level: str | None = None,
        trust_score: float | None = None,
    ) -> dict:
        """更新工作流模板（管家学习后更新风格/信任度）"""
        ...

    # ── 工作流实例 ────────────────────────────────────────────────

    async def create_instance(
        self,
        template_id: UUID,
        trigger_thread_id: UUID | None,
        trigger_message_id: UUID | None,
        context: dict,
    ) -> dict:
        """创建工作流实例

        trust_level=supervised → status=pending_approval，推送用户审批通知
        trust_level=autonomous → status=running，立即执行
        """
        ...

    async def approve_instance(
        self,
        instance_id: UUID,
        approver_id: str,
    ) -> dict:
        """用户批准工作流执行（supervised 模式）

        status → running，执行步骤列表
        """
        ...

    async def cancel_instance(
        self,
        instance_id: UUID,
        cancelled_by: str,
        reason: str = "",
    ) -> dict:
        """取消工作流实例（用户取消或用户已自行处理）

        status → cancelled
        若 cancelled_by = 'user_handled'：管家从中学习处理方式
        """
        ...

    async def list_instances(
        self,
        status: str | None = None,
        user_id: str | None = None,
        page: int = 1,
        size: int = 20,
    ) -> tuple[list[dict], int]:
        """列出工作流实例（管理员/用户查看）"""
        ...

    # ── 跨群任务分发 ──────────────────────────────────────────────

    async def delegate_task(
        self,
        source_thread_id: UUID | None,
        target_user_id: str,
        task_description: str,
        target_group_id: str | None = None,
        due_at: str | None = None,
        delegated_by: str = "nullclaw",
    ) -> dict:
        """创建跨群任务分发记录，推送通知给目标用户"""
        ...

    async def update_delegate_status(
        self,
        delegate_id: UUID,
        status: str,                    # accepted | rejected | completed
        user_id: str,
    ) -> dict:
        """目标用户更新任务接受/完成状态"""
        ...
```

---

## 22. IExtensionService

```python
# rippleflow/services/interfaces/extension_service.py
from typing import Protocol
from uuid import UUID

class IExtensionService(Protocol):
    """扩展机制服务（需求1）

    管理软能力扩展（分类/任务类型扩展）和
    硬能力扩展（Event Hook / nullclaw 脚本）的注册与调用。
    """

    # ── 软能力扩展（分类/任务类型）───────────────────────────────

    async def propose_soft_extension(
        self,
        ext_type: str,                  # category | task_type | label
        ext_key: str,
        display_name: str,
        description: str | None = None,
        parent_key: str | None = None,
        config: dict | None = None,
        proposed_by: str = "nullclaw",
    ) -> dict:
        """提议软能力扩展

        risk_level=low（子分类/标签）→ status 直接设为 active，异步通知管理员
        risk_level=high（新一级分类/修改触发规则）→ status=pending，等待管理员审核
        """
        ...

    async def approve_soft_extension(
        self,
        extension_id: UUID,
        approved_by: str,
    ) -> dict:
        """管理员审核通过高风险软扩展"""
        ...

    async def list_soft_extensions(
        self,
        status: str | None = None,
        ext_type: str | None = None,
    ) -> list[dict]:
        """列出软能力扩展定义"""
        ...

    # ── 硬能力扩展（Event Hook / nullclaw Script）─────────────────

    async def register_extension(
        self,
        name: str,
        ext_track: str,                 # event_hook | nullclaw_script
        hook_events: list[str] | None = None,
        webhook_url: str | None = None,
        script_path: str | None = None,
        version: str = "1.0.0",
        config: dict | None = None,
    ) -> dict:
        """注册硬能力扩展（提交后 status=pending，必须管理员审核才能激活）"""
        ...

    async def approve_extension(
        self,
        extension_id: UUID,
        approved_by: str,
    ) -> dict:
        """管理员激活硬能力扩展"""
        ...

    async def fire_hook(
        self,
        hook_event: str,
        payload: dict,
    ) -> list[dict]:
        """平台内部调用：触发注册了该事件的所有 active event_hook 扩展

        按 extension_registry 中 hook_events 匹配，
        HTTP POST 到 webhook_url，超时 3s，记录 invocation_log
        返回各扩展的调用结果
        """
        ...

    async def get_invocation_logs(
        self,
        extension_id: UUID,
        limit: int = 50,
    ) -> list[dict]:
        """获取插件调用日志（管理员/审计使用）"""
        ...
```

---

## 23. ICustomFieldService

```python
# rippleflow/services/interfaces/custom_field_service.py
from typing import Protocol
from uuid import UUID

class ICustomFieldService(Protocol):
    """跟踪项自定义属性服务（需求8）

    用户或管家可为话题/待办/FAQ/工作流定义自定义属性字段，
    管家可推荐适合的字段定义，采纳后系统记忆并复用。
    """

    async def define_field(
        self,
        entity_type: str,               # thread | todo | faq_item | workflow
        field_key: str,
        field_name: str,
        field_type: str,                # text | number | date | select | boolean
        group_id: str | None = None,
        options: list[str] | None = None,   # select 类型的选项
        suggested_by: str | None = None,
    ) -> dict:
        """定义新的自定义字段

        suggested_by=nullclaw → 推荐状态，等待用户采纳（adopted_by 非空时正式生效）
        suggested_by=user_id  → 直接生效，同时供管家学习复用
        """
        ...

    async def adopt_suggestion(
        self,
        field_id: UUID,
        adopted_by: str,
    ) -> dict:
        """用户采纳管家推荐的字段定义"""
        ...

    async def suggest_fields(
        self,
        entity_type: str,
        entity_id: UUID,
        context: dict | None = None,
    ) -> list[dict]:
        """管家推荐适合当前实体的自定义字段

        基于历史 usage_count 和 context（话题类别/参与人等）推荐。
        """
        ...

    async def set_value(
        self,
        entity_type: str,
        entity_id: UUID,
        field_id: UUID,
        value: str,
        set_by: str,
    ) -> None:
        """设置实体的自定义字段值"""
        ...

    async def get_values(
        self,
        entity_type: str,
        entity_id: UUID,
    ) -> list[dict]:
        """获取实体的所有自定义字段值"""
        ...

    async def list_definitions(
        self,
        entity_type: str,
        group_id: str | None = None,
        include_suggestions: bool = True,
    ) -> list[dict]:
        """列出可用的自定义字段定义（已采纳 + 管家推荐）"""
        ...
```

---
---

## 24. IUserDocumentService

```python
# rippleflow/services/interfaces/user_document_service.py
from typing import Protocol
from dataclasses import dataclass
from uuid import UUID


@dataclass
class UserDocument:
    """用户发布的富文本文档"""
    id: UUID
    title: str
    content: str | None            # Markdown 富文本
    summary: str | None            # AI 生成摘要（<=200字）
    author_id: str
    group_id: str | None
    category: str | None
    tags: list[str]
    visibility: str                # 'private' | 'followers' | 'team' | 'public'
    published_at: str | None       # None = 草稿
    view_count: int
    butler_suggested_category: str | None
    butler_suggested_tags: list[str]
    source_thread_id: UUID | None
    created_at: str
    updated_at: str


class IUserDocumentService(Protocol):
    """
    用户文档服务。
    管理系统内富文本文档的创建、编辑、发布和访问控制。
    创建/更新时自动触发管家字段建议（通过 IButlerSuggestionService）。
    发布时触发订阅推送（通过 ISubscriptionService.publish_event）。
    """

    async def create_document(
        self,
        author_id: str,
        title: str,
        content: str | None = None,
        visibility: str = 'team',
        group_id: str | None = None,
    ) -> UserDocument:
        """创建文档草稿。"""
        ...

    async def update_document(
        self,
        document_id: UUID,
        user_id: str,
        title: str | None = None,
        content: str | None = None,
        category: str | None = None,
        tags: list[str] | None = None,
        visibility: str | None = None,
    ) -> UserDocument:
        """更新文档内容或元数据，仅作者可操作。"""
        ...

    async def publish_document(
        self,
        document_id: UUID,
        user_id: str,
    ) -> UserDocument:
        """发布文档（草稿→已发布），触发订阅者推送。"""
        ...

    async def get_document(
        self, document_id: UUID, viewer_id: str
    ) -> UserDocument | None:
        """获取文档详情，检查访问权限。"""
        ...

    async def delete_document(
        self, document_id: UUID, user_id: str
    ) -> None:
        """删除文档，仅作者或管理员可操作。"""
        ...

    async def list_documents(
        self,
        viewer_id: str,
        author_id: str | None = None,
        group_id: str | None = None,
        category: str | None = None,
        published_only: bool = True,
        limit: int = 20,
        offset: int = 0,
    ) -> list[UserDocument]:
        """列出可访问的文档，支持多维度过滤。"""
        ...

    async def generate_summary(
        self, document_id: UUID
    ) -> str:
        """调用 LLM 为文档生成摘要并更新 summary 字段。"""
        ...
```

---

## 25. ISharedLinkService

```python
# rippleflow/services/interfaces/shared_link_service.py
from typing import Protocol
from dataclasses import dataclass
from uuid import UUID


@dataclass
class SharedLink:
    """外部链接分享卡片"""
    id: UUID
    url: str
    title: str | None
    description: str | None
    site_name: str | None
    favicon_url: str | None
    preview_image: str | None
    shared_by: str
    group_id: str | None
    category: str | None
    tags: list[str]
    visibility: str
    butler_suggested_category: str | None
    butler_suggested_tags: list[str]
    butler_summary: str | None
    metadata_fetched_at: str | None
    fetch_status: str              # 'pending' | 'success' | 'failed' | 'skipped'
    view_count: int
    created_at: str
    updated_at: str


class ISharedLinkService(Protocol):
    """
    外部链接分享服务。
    创建后异步抓取 OG 元数据，管家自动生成分类/标签/摘要建议。
    """

    async def create_shared_link(
        self,
        user_id: str,
        url: str,
        group_id: str | None = None,
        visibility: str = 'team',
    ) -> SharedLink:
        """
        创建链接卡片。
        返回时元数据可能尚未抓取（fetch_status='pending'）。
        后台异步任务负责抓取 OG 数据并更新 fetch_status。
        """
        ...

    async def update_shared_link(
        self,
        link_id: UUID,
        user_id: str,
        title: str | None = None,
        description: str | None = None,
        category: str | None = None,
        tags: list[str] | None = None,
        visibility: str | None = None,
    ) -> SharedLink:
        """手动更新链接元数据或分类/标签，仅创建者可操作。"""
        ...

    async def delete_shared_link(
        self, link_id: UUID, user_id: str
    ) -> None:
        """删除链接卡片。"""
        ...

    async def get_shared_link(
        self, link_id: UUID, viewer_id: str
    ) -> SharedLink | None:
        """获取链接卡片详情，记录访问次数。"""
        ...

    async def list_shared_links(
        self,
        viewer_id: str,
        shared_by: str | None = None,
        group_id: str | None = None,
        category: str | None = None,
        limit: int = 20,
        offset: int = 0,
    ) -> list[SharedLink]:
        """列出可访问的链接卡片。"""
        ...

    async def fetch_og_metadata(
        self, link_id: UUID
    ) -> dict:
        """
        抓取链接的 OG 元数据并更新数据库。
        返回：{title, description, site_name, favicon_url, preview_image}
        超时或失败时 fetch_status -> 'failed'，仍可手动填写元数据。
        """
        ...
```

---

## 26. IButlerSuggestionService

```python
# rippleflow/services/interfaces/butler_suggestion_service.py
from typing import Protocol
from dataclasses import dataclass
from uuid import UUID


@dataclass
class SuggestionItem:
    value: str
    confidence: float     # 0.0 ~ 1.0
    reason: str           # <= 30


@dataclass
class SuggestionResult:
    suggestion_id: UUID
    suggestions: list[SuggestionItem]
    common_values: list[str]


class IButlerSuggestionService(Protocol):
    """
    AI 智能辅助输入服务（跨切面设计模式）。

    用户在任意实体的任意字段填写时，通过此服务获取管家建议。
    设计原则：
    - 防抖 1s 后触发（由客户端控制）
    - 响应时限 < 2s，超时返回空列表
    - 三级强度：confidence > 0.9 (auto_apply) | 0.7-0.9 (highlight) | <0.7 (list)
    - 采纳反馈 -> 每周 Routine 分析 -> 优化 Prompt
    """

    async def suggest(
        self,
        user_id: str,
        entity_type: str,
        field: str,
        content: str,
        entity_id: UUID | None = None,
        context: dict | None = None,
    ) -> SuggestionResult:
        """为指定实体字段的输入提供智能建议，< 2s 响应。"""
        ...

    async def record_feedback(
        self,
        suggestion_id: UUID,
        applied: bool,
        applied_value: str | None = None,
        ai_applied: bool = False,
    ) -> None:
        """
        记录用户对建议的采纳情况，供 Routine 分析采纳率。

        调用时机：
        1. 用户主动确认建议（highlight 模式点击"采纳"）
           → applied=True, applied_value=建议值
        2. 用户忽略建议（切换字段/提交时未采纳）
           → applied=False, applied_value=None
        3. auto_apply 隐式反馈（实体保存时，业务层自动触发）：
           → applied=True, applied_value=字段最终值, ai_applied=True
           业务层伪代码：
               async def on_entity_saved(entity_type, entity_id, final_fields):
                   pending = await butler_svc.list_pending_suggestions(
                       user_id, entity_type, entity_id_or_none=None
                   )
                   for s in pending:
                       field_value = final_fields.get(s.field)
                       auto = any(item.confidence > 0.9 for item in s.suggestions)
                       await butler_svc.record_feedback(
                           s.id, applied=True, applied_value=field_value, ai_applied=auto
                       )
                       await butler_svc.link_entity(s.id, entity_id)
        """
        ...

    async def link_entity(
        self,
        suggestion_id: UUID,
        entity_id: UUID,
    ) -> None:
        """
        将创建时 entity_id=NULL 的建议记录回填 entity_id。
        在实体保存成功后由业务层调用，避免孤儿记录。
        UPDATE butler_suggestions SET entity_id=$entity_id
        WHERE id=$suggestion_id AND entity_id IS NULL;
        """
        ...

    async def list_pending_suggestions(
        self,
        user_id: str,
        entity_type: str,
        entity_id: UUID | None = None,
        created_after: datetime | None = None,
    ) -> list[SuggestionResult]:
        """
        查询某用户在特定实体类型下还未关联 entity_id（创建中）的建议记录。
        用于实体保存时批量回填 entity_id 并自动发送 auto_apply 反馈。
        默认只返回最近 1 小时内的记录（created_after 控制）。
        """
        ...

    async def get_common_tags(
        self,
        entity_type: str,
        group_id: str | None = None,
        limit: int = 20,
    ) -> list[dict]:
        """获取历史高频标签，辅助前端标签选择器。返回：[{tag, usage_count}]"""
        ...

    async def prefetch_link_metadata(self, url: str) -> dict:
        """
        抓取外部链接 OG 元数据：{title, description, site_name, favicon_url, preview_image}
        超时（5s）或失败时返回空 dict（降级为人工填写）。
        抓取结果的 fetch_status 由 ISharedLinkService 更新：
          - 成功 → fetch_status='success', metadata_fetched_at=NOW()
          - 超时/失败 → fetch_status='failed'
          失败后用户可在卡片编辑页手动填写标题/描述，
          也可通过 POST /api/v1/shared-links/{id}/refetch 触发重新抓取。
        """
        ...
```

---

## 附录 G. 服务依赖图（v0.7 更新）

```
IPresenceService
    |-- INotificationService
    |-- IExtensionService

IWorkflowService
    |-- IPresenceService
    |-- INotificationService
    |-- knowledge_nodes/edges

IExtensionService
    |-- INotificationService
    |-- extension_invocation_logs

ICustomFieldService
    |-- IWorkflowService
    |-- IPresenceService

IUserDocumentService
    |-- ISubscriptionService
    |-- IButlerSuggestionService

ISharedLinkService
    |-- ISubscriptionService
    |-- IButlerSuggestionService

IButlerSuggestionService
    |-- butler_suggestions
```
