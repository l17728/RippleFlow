"""Phase 2: 追加 4 个新 Protocol 到 04_service_interfaces.md"""

content = """

---

## 17. IPresenceService

```python
# rippleflow/services/interfaces/presence_service.py
from typing import Protocol
from datetime import datetime

class IPresenceService(Protocol):
    \"\"\"用户在线状态与离线消息队列服务（需求2+4）

    平台通过 Heartbeat API 维护用户在线状态，
    并在用户上线时批量推送缓存的离线通知。
    \"\"\"

    async def heartbeat(
        self,
        user_id: str,
        client_info: dict | None = None,
    ) -> list[dict]:
        \"\"\"处理客户端心跳

        1. 更新 user_presence（status=online, last_heartbeat=NOW()）
        2. 查询 queued_notifications WHERE delivered_at IS NULL
           ORDER BY priority, created_at LIMIT 50
        3. 标记 delivered_at=NOW()
        4. 触发 on_user_online Event Hook（如有注册）

        返回：待推送的通知列表
        \"\"\"
        ...

    async def mark_offline(self, user_id: str) -> None:
        \"\"\"将超过60秒未心跳的用户标记为离线（后台定时任务调用）\"\"\"
        ...

    async def get_status(self, user_id: str) -> dict:
        \"\"\"获取用户在线状态（online/idle/offline）\"\"\"
        ...

    async def get_online_users(
        self,
        group_id: str | None = None,
    ) -> list[dict]:
        \"\"\"获取当前在线用户列表（管理员/管家使用）\"\"\"
        ...

    async def enqueue_notification(
        self,
        user_id: str,
        event_type: str,
        payload: dict,
        priority: int = 5,
        expires_at: datetime | None = None,
    ) -> str:
        \"\"\"向指定用户的离线队列写入通知

        用户在线时：尝试直接推送（通过 App 内通知）
        用户离线时：写入 queued_notifications，等待下次 Heartbeat

        priority 建议值：
        - 1: mention / 敏感授权到期提醒
        - 3: 工作流待审批 / 待办到期
        - 5: 每日摘要 / FAQ 质量告警

        返回 queued_notification.id
        \"\"\"
        ...

    async def get_queue(
        self,
        user_id: str,
        undelivered_only: bool = True,
        limit: int = 50,
    ) -> list[dict]:
        \"\"\"获取用户的通知队列（主要供 Heartbeat 内部使用）\"\"\"
        ...
```

---

## 18. IWorkflowService

```python
# rippleflow/services/interfaces/workflow_service.py
from typing import Protocol
from uuid import UUID

class IWorkflowService(Protocol):
    \"\"\"工作流托管服务（需求3）

    平台提供工作流模板存储和实例执行的机制层；
    nullclaw 负责触发条件识别、模板学习和执行决策（策略层）。
    \"\"\"

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
        \"\"\"创建工作流模板（nullclaw 学习后调用）

        steps 格式示例：
        [
          {"step": 1, "action": "notify_user",   "target": "@user", "template": "..."},
          {"step": 2, "action": "create_todo",   "assignee": "...", "due_offset_days": 3},
          {"step": 3, "action": "cross_delegate", "target_group": "...", "task": "..."}
        ]
        \"\"\"
        ...

    async def list_templates(
        self,
        trust_level: str | None = None,    # supervised | autonomous
        page: int = 1,
        size: int = 20,
    ) -> tuple[list[dict], int]:
        \"\"\"列出工作流模板\"\"\"
        ...

    async def update_template(
        self,
        template_id: UUID,
        style_notes: str | None = None,
        trust_level: str | None = None,
        trust_score: float | None = None,
    ) -> dict:
        \"\"\"更新工作流模板（管家学习后更新风格/信任度）\"\"\"
        ...

    # ── 工作流实例 ────────────────────────────────────────────────

    async def create_instance(
        self,
        template_id: UUID,
        trigger_thread_id: UUID | None,
        trigger_message_id: UUID | None,
        context: dict,
    ) -> dict:
        \"\"\"创建工作流实例

        trust_level=supervised → status=pending_approval，推送用户审批通知
        trust_level=autonomous → status=running，立即执行
        \"\"\"
        ...

    async def approve_instance(
        self,
        instance_id: UUID,
        approver_id: str,
    ) -> dict:
        \"\"\"用户批准工作流执行（supervised 模式）

        status → running，执行步骤列表
        \"\"\"
        ...

    async def cancel_instance(
        self,
        instance_id: UUID,
        cancelled_by: str,
        reason: str = "",
    ) -> dict:
        \"\"\"取消工作流实例（用户取消或用户已自行处理）

        status → cancelled
        若 cancelled_by = 'user_handled'：管家从中学习处理方式
        \"\"\"
        ...

    async def list_instances(
        self,
        status: str | None = None,
        user_id: str | None = None,
        page: int = 1,
        size: int = 20,
    ) -> tuple[list[dict], int]:
        \"\"\"列出工作流实例（管理员/用户查看）\"\"\"
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
        \"\"\"创建跨群任务分发记录，推送通知给目标用户\"\"\"
        ...

    async def update_delegate_status(
        self,
        delegate_id: UUID,
        status: str,                    # accepted | rejected | completed
        user_id: str,
    ) -> dict:
        \"\"\"目标用户更新任务接受/完成状态\"\"\"
        ...
```

---

## 19. IExtensionService

```python
# rippleflow/services/interfaces/extension_service.py
from typing import Protocol
from uuid import UUID

class IExtensionService(Protocol):
    \"\"\"扩展机制服务（需求1）

    管理软能力扩展（分类/任务类型扩展）和
    硬能力扩展（Event Hook / nullclaw 脚本）的注册与调用。
    \"\"\"

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
        \"\"\"提议软能力扩展

        risk_level=low（子分类/标签）→ status 直接设为 active，异步通知管理员
        risk_level=high（新一级分类/修改触发规则）→ status=pending，等待管理员审核
        \"\"\"
        ...

    async def approve_soft_extension(
        self,
        extension_id: UUID,
        approved_by: str,
    ) -> dict:
        \"\"\"管理员审核通过高风险软扩展\"\"\"
        ...

    async def list_soft_extensions(
        self,
        status: str | None = None,
        ext_type: str | None = None,
    ) -> list[dict]:
        \"\"\"列出软能力扩展定义\"\"\"
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
        \"\"\"注册硬能力扩展（提交后 status=pending，必须管理员审核才能激活）\"\"\"
        ...

    async def approve_extension(
        self,
        extension_id: UUID,
        approved_by: str,
    ) -> dict:
        \"\"\"管理员激活硬能力扩展\"\"\"
        ...

    async def fire_hook(
        self,
        hook_event: str,
        payload: dict,
    ) -> list[dict]:
        \"\"\"平台内部调用：触发注册了该事件的所有 active event_hook 扩展

        按 extension_registry 中 hook_events 匹配，
        HTTP POST 到 webhook_url，超时 3s，记录 invocation_log
        返回各扩展的调用结果
        \"\"\"
        ...

    async def get_invocation_logs(
        self,
        extension_id: UUID,
        limit: int = 50,
    ) -> list[dict]:
        \"\"\"获取插件调用日志（管理员/审计使用）\"\"\"
        ...
```

---

## 20. ICustomFieldService

```python
# rippleflow/services/interfaces/custom_field_service.py
from typing import Protocol
from uuid import UUID

class ICustomFieldService(Protocol):
    \"\"\"跟踪项自定义属性服务（需求8）

    用户或管家可为话题/待办/FAQ/工作流定义自定义属性字段，
    管家可推荐适合的字段定义，采纳后系统记忆并复用。
    \"\"\"

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
        \"\"\"定义新的自定义字段

        suggested_by=nullclaw → 推荐状态，等待用户采纳（adopted_by 非空时正式生效）
        suggested_by=user_id  → 直接生效，同时供管家学习复用
        \"\"\"
        ...

    async def adopt_suggestion(
        self,
        field_id: UUID,
        adopted_by: str,
    ) -> dict:
        \"\"\"用户采纳管家推荐的字段定义\"\"\"
        ...

    async def suggest_fields(
        self,
        entity_type: str,
        entity_id: UUID,
        context: dict | None = None,
    ) -> list[dict]:
        \"\"\"管家推荐适合当前实体的自定义字段

        基于历史 usage_count 和 context（话题类别/参与人等）推荐。
        \"\"\"
        ...

    async def set_value(
        self,
        entity_type: str,
        entity_id: UUID,
        field_id: UUID,
        value: str,
        set_by: str,
    ) -> None:
        \"\"\"设置实体的自定义字段值\"\"\"
        ...

    async def get_values(
        self,
        entity_type: str,
        entity_id: UUID,
    ) -> list[dict]:
        \"\"\"获取实体的所有自定义字段值\"\"\"
        ...

    async def list_definitions(
        self,
        entity_type: str,
        group_id: str | None = None,
        include_suggestions: bool = True,
    ) -> list[dict]:
        \"\"\"列出可用的自定义字段定义（已采纳 + 管家推荐）\"\"\"
        ...
```

---

## 服务依赖图（更新）

```
IPresenceService
    ├── INotificationService（推送 App 内通知）
    └── IExtensionService（触发 on_user_online Hook）

IWorkflowService
    ├── IPresenceService（推送工作流审批通知）
    ├── INotificationService（跨群任务通知）
    └── knowledge_nodes/edges（上下文补全，直接 DB 访问）

IExtensionService
    ├── INotificationService（审核通知）
    └── extension_invocation_logs（调用记录）

ICustomFieldService
    ├── IWorkflowService（为工作流推荐字段）
    └── IPresenceService（推荐时通知用户）
```
"""

with open('D:/RippleFlow/docs/04_service_interfaces.md', 'a', encoding='utf-8') as f:
    f.write(content)
print('done')
