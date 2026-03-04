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
        重复消息（external_msg_id 相同）幂等处理，直接返回已有 ID。
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

    async def run(self, message_id: UUID) -> str:
        """
        执行完整的 6 阶段流水线。
        返回最终状态字符串：
          'skipped_noise' | 'sensitive_pending' | 'classified' | 'failed'
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
        阶段 5：增量摘要更新。
        输入：现有摘要 + 新消息内容。
        旧摘要自动归档到 thread_summary_history。
        漂移检测：追加冲突说明（Append-Only）。
        """
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
        若 overall_status 变为 authorized：消息重入处理队列。
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
        """Prompt: Stage 5 增量摘要更新"""
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
        """
        推送事件到 nullclaw。
        RippleFlow 平台在业务操作完成后，通过此方法推送事件到 nullclaw。
        返回推送是否成功。

        支持的事件类型：
        - message.received: 新消息入库
        - thread.created: 新话题线索创建
        - thread.updated: 话题线索更新
        - todo.created: 待办创建
        - todo.completed: 待办完成
        - sensitive.detected: 敏感内容检测
        - sensitive.authorized: 敏感授权完成
        - user.query: 用户发起问答
        - user.feedback: 用户提交反馈
        """
        ...
```

---

## 14. 异常类型

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

## 13. 接口依赖关系图

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
    subscription_type: str  # 'user' | 'thread' | 'category' | 'keyword'
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
    ) -> Subscription:
        """创建订阅。"""
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
        """发布订阅事件，通知相关订阅者。"""
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
    ) -> list[PersonalTodo]:
        """
        从知识库中的 action_item 同步到个人待办。
        当群聊中的 action_item 被识别后，自动为责任人创建待办。
        """
        ...
```

---

## 16. 接口依赖关系图（更新）

```
ProcessingPipelineService
    ├── MessageService
    ├── LLMService
    ├── ThreadService
    ├── SensitiveService
    └── NotificationService

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
```
