# 微信群对接 + 增量更新设计文档

## 概述

| 项目 | 值 |
|------|------|
| 创建日期 | 2026-03-03 |
| 状态 | 已确认 |
| 版本 | v1.0 |

### 需求背景

RippleFlow 需要对接微信群，支持：
1. **Wechaty 实时同步**：使用小号 + 只读模式同步消息
2. **批量导入增量更新**：手动上传文件，按时间戳增量导入
3. **混合架构**：实时通道优先，批量导入兜底

---

## 架构设计

### 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    微信消息接入架构                              │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                实时通道 (Wechaty)                        │   │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │   │
│  │  │ 小号登录    │───→│ 只收消息    │───→│ 推送到队列  │  │   │
│  │  │ iPad协议    │    │ 不主动发送  │    │ 处理流水线  │  │   │
│  │  └─────────────┘    └─────────────┘    └─────────────┘  │   │
│  │         ⚠️ 有风险但只读模式风险较低                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼ 断开时自动切换                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                批量导入通道（增量更新）                   │   │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │   │
│  │  │ 上传文件    │───→│ 时间戳过滤  │───→│ 去重入库    │  │   │
│  │  │ 多格式解析  │    │ 只导入新增  │    │ 补齐缺失    │  │   │
│  │  └─────────────┘    └─────────────┘    └─────────────┘  │   │
│  │         ✅ 稳定可靠，作为兜底方案                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                   同步状态追踪                           │   │
│  │  - 记录每个群的最后同步时间                               │   │
│  │  - 追踪实时通道在线状态                                   │   │
│  │  - 支持断点续传                                           │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 数据流

```
Wechaty 实时消息                      批量导入文件
      │                                    │
      ▼                                    ▼
┌─────────────┐                    ┌─────────────┐
│ WechatSync  │                    │ Incremental │
│ Adapter     │                    │ Importer    │
└──────┬──────┘                    └──────┬──────┘
       │                                  │
       └──────────────┬───────────────────┘
                      ▼
              ┌─────────────┐
              │ 去重检查    │
              │ (时间戳+哈希)│
              └──────┬──────┘
                     ▼
              ┌─────────────┐
              │ 消息处理    │
              │ 流水线      │
              │ (Stage 0-5) │
              └──────┬──────┘
                     ▼
              ┌─────────────┐
              │ 更新同步状态 │
              └─────────────┘
```

---

## 核心模块设计

### 1. Wechaty 实时同步服务

```python
# wechat_sync_service.py
from wechaty import Wechaty, Message
from typing import Optional

class WechatSyncService:
    """微信实时同步服务（只读模式）"""

    def __init__(self):
        self.bot: Optional[Wechaty] = None
        self.sync_mode = "readonly"  # 只读模式，不主动发送
        self.monitored_rooms: set[str] = set()

    async def start(self, room_ids: list[str]):
        """启动同步（使用小号）"""
        self.bot = WechatyBuilder.build(
            puppet="wechaty-puppet-service",
            token=settings.WECHATY_TOKEN
        )

        self.monitored_rooms = set(room_ids)

        # 注册消息监听
        self.bot.on("message", self._on_message)
        self.bot.on("login", self._on_login)
        self.bot.on("logout", self._on_logout)

        await self.bot.start()

    async def _on_login(self, user):
        """登录成功回调"""
        await self._update_realtime_status("online")
        logger.info(f"Wechaty logged in as {user}")

    async def _on_logout(self, user):
        """登出回调"""
        await self._update_realtime_status("offline")
        logger.warning(f"Wechaty logged out: {user}")

    async def _on_message(self, message: Message):
        """消息回调（只收不发）"""
        try:
            # 只处理群消息
            room = message.room()
            if not room:
                return

            room_id = room.room_id

            # 只处理监控的群
            if room_id not in self.monitored_rooms:
                return

            # 转换为统一格式
            unified = await self._normalize_message(message)

            # 推送到处理队列
            await message_queue.push(unified)

            # 更新同步状态
            await self._update_sync_status(unified)

        except Exception as e:
            logger.error(f"Error processing message: {e}")

    async def _normalize_message(self, message: Message) -> UnifiedMessage:
        """将 Wechaty 消息转换为统一格式"""
        room = message.room()
        talker = message.talker()

        return UnifiedMessage(
            platform="wechat",
            platform_message_id=message.message_id(),
            platform_room_id=room.room_id if room else "",
            sender_id=talker.contact_id,
            sender_name=await talker.name(),
            room_id=await self._get_internal_room_id(room.room_id),
            room_name=await room.topic() if room else "",
            content=await message.text(),
            content_type=self._map_message_type(message.type()),
            sent_at=message.date(),
            received_at=datetime.now(tz=timezone.utc),
            reply_to=None,
            mentions=[m.contact_id for m in await message.mention_list()],
            extra={"wechaty_type": message.type()}
        )

    async def stop(self):
        """停止同步"""
        if self.bot:
            await self.bot.stop()
            self.bot = None
            await self._update_realtime_status("offline")
```

### 2. 增量导入服务

```python
# incremental_import_service.py
import hashlib
from datetime import datetime

class IncrementalImportService:
    """增量导入服务"""

    async def import_incremental(
        self,
        room_id: str,
        file_path: str,
        format: str,
        options: dict = None
    ) -> ImportResult:
        """
        增量导入消息

        Args:
            room_id: 目标群组ID
            file_path: 导入文件路径
            format: 文件格式 (wechat_txt | json | csv | wechat_db)
            options: 导入选项
        """
        options = options or {}

        # 1. 获取最后同步时间
        last_sync = await self._get_last_sync_time(room_id)

        # 2. 解析文件
        parser = self._get_parser(format)
        messages = await parser.parse(file_path)

        # 3. 时间戳过滤：只保留新消息
        new_messages = [
            m for m in messages
            if m.sent_at > last_sync
        ]

        logger.info(f"Filtered {len(new_messages)} new messages out of {len(messages)}")

        # 4. 去重检查（发送者+时间+内容哈希）
        deduped = await self._deduplicate(room_id, new_messages)

        # 5. 批量处理
        result = await self._batch_process(room_id, deduped)

        # 6. 更新同步状态
        if result.processed > 0:
            last_message = max(messages, key=lambda m: m.sent_at)
            await self._update_sync_status(
                room_id,
                last_message.sent_at,
                last_message.platform_message_id
            )

        return result

    async def _deduplicate(
        self,
        room_id: str,
        messages: list[UnifiedMessage]
    ) -> list[UnifiedMessage]:
        """
        去重：发送者+时间+内容哈希
        """
        deduped = []

        for msg in messages:
            # 生成消息哈希
            hash_key = self._make_message_hash(msg)

            # 检查是否已存在
            exists = await self._check_message_exists(room_id, hash_key)

            if not exists:
                deduped.append(msg)
            else:
                logger.debug(f"Skipping duplicate message: {hash_key[:8]}")

        return deduped

    def _make_message_hash(self, msg: UnifiedMessage) -> str:
        """生成消息唯一哈希"""
        # 发送者 + 时间戳(精确到秒) + 内容
        content = f"{msg.sender_id}|{int(msg.sent_at.timestamp())}|{msg.content}"
        return hashlib.sha256(content.encode()).hexdigest()

    async def _check_message_exists(self, room_id: str, hash_key: str) -> bool:
        """检查消息是否已存在"""
        # 查询数据库
        exists = await db.fetchval("""
            SELECT EXISTS(
                SELECT 1 FROM messages
                WHERE room_id = $1
                AND content_hash = $2
            )
        """, room_id, hash_key)
        return exists

    async def _get_last_sync_time(self, room_id: str) -> datetime:
        """获取最后同步时间"""
        result = await db.fetchrow("""
            SELECT last_sync_time
            FROM wechat_sync_status
            WHERE room_id = $1
        """, room_id)

        if result and result["last_sync_time"]:
            return result["last_sync_time"]

        # 默认返回 30 天前
        return datetime.now(tz=timezone.utc) - timedelta(days=30)
```

### 3. 同步状态管理

```python
# sync_status_service.py
class SyncStatusService:
    """同步状态管理服务"""

    async def get_sync_status(self, room_id: str = None) -> dict:
        """获取同步状态"""
        if room_id:
            return await self._get_room_sync_status(room_id)
        return await self._get_all_sync_status()

    async def update_realtime_status(
        self,
        status: str,  # online | offline | error
        error_message: str = None
    ):
        """更新实时通道状态"""
        await db.execute("""
            UPDATE wechat_sync_status
            SET realtime_status = $1,
                realtime_last_heartbeat = NOW(),
                realtime_error = $2,
                updated_at = NOW()
            WHERE sync_mode IN ('realtime', 'hybrid')
        """, status, error_message)

    async def update_batch_sync(
        self,
        room_id: str,
        last_sync_time: datetime,
        last_message_id: str,
        imported_count: int,
        skipped_count: int
    ):
        """更新批量同步状态"""
        await db.execute("""
            INSERT INTO wechat_sync_status (room_id, last_sync_time, last_message_id, total_imported, total_skipped)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (room_id) DO UPDATE SET
                last_sync_time = EXCLUDED.last_sync_time,
                last_message_id = EXCLUDED.last_message_id,
                total_imported = wechat_sync_status.total_imported + EXCLUDED.total_imported,
                total_skipped = wechat_sync_status.total_skipped + EXCLUDED.total_skipped,
                updated_at = NOW()
        """, room_id, last_sync_time, last_message_id, imported_count, skipped_count)
```

---

## 数据库设计

### 微信同步状态表

```sql
-- 微信同步状态表
CREATE TABLE wechat_sync_status (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_id         UUID NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,

    -- 同步模式
    sync_mode       VARCHAR(50) DEFAULT 'batch',
    -- realtime: 仅实时同步
    -- batch: 仅批量导入
    -- hybrid: 混合模式（实时优先，批量兜底）

    -- 实时同步状态
    realtime_status VARCHAR(50),  -- online | offline | error
    realtime_last_heartbeat TIMESTAMPTZ,
    realtime_error  TEXT,

    -- 批量同步状态
    last_sync_time  TIMESTAMPTZ,
    last_message_id VARCHAR(500),
    last_message_hash VARCHAR(64),  -- SHA256 内容哈希

    -- 统计
    total_imported  BIGINT DEFAULT 0,
    total_skipped   BIGINT DEFAULT 0,
    total_failed    BIGINT DEFAULT 0,

    -- 时间
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(room_id)
);

CREATE INDEX idx_wechat_sync_room ON wechat_sync_status(room_id);
CREATE INDEX idx_wechat_sync_mode ON wechat_sync_status(sync_mode);
CREATE INDEX idx_wechat_sync_realtime ON wechat_sync_status(realtime_status);

-- 为消息表添加内容哈希字段（用于去重）
ALTER TABLE messages ADD COLUMN IF NOT EXISTS content_hash VARCHAR(64);
CREATE INDEX IF NOT EXISTS idx_messages_content_hash ON messages(room_id, content_hash);
```

---

## API 设计

### 微信同步 API

```yaml
# 微信同步管理
/api/v1/wechat:
  endpoints:
    # 启动实时同步
    - path: /sync/start
      method: POST
      summary: 启动 Wechaty 实时同步
      auth: admin
      request:
        body:
          room_ids:
            type: array
            items: { type: string }
            description: 要监控的群组ID列表
          mode:
            type: string
            enum: [readonly, full]
            default: readonly
            description: 只读模式不发送消息，风险更低
      response:
        status: started
        monitored_rooms: int

    # 停止实时同步
    - path: /sync/stop
      method: POST
      summary: 停止实时同步
      auth: admin
      response:
        status: stopped

    # 获取同步状态
    - path: /sync/status
      method: GET
      summary: 获取同步状态
      response:
        realtime_status: online | offline | error
        rooms:
          - room_id: string
            room_name: string
            sync_mode: realtime | batch | hybrid
            last_sync_time: datetime
            realtime_status: string
            total_imported: int

    # 增量导入
    - path: /import/incremental
      method: POST
      summary: 增量导入微信消息
      request:
        content-type: multipart/form-data
        body:
          file:
            type: binary
            description: 导入文件
          room_id:
            type: string
            description: 目标群组ID
          format:
            type: string
            enum: [wechat_txt, json, csv, wechat_db]
            description: 文件格式
      response:
        job_id: string
        total_count: int
        new_count: int
        skipped_count: int
        failed_count: int

    # 支持的导入格式
    - path: /import/formats
      method: GET
      summary: 获取支持的导入格式
      response:
        formats:
          - id: wechat_txt
            name: 微信文本格式
            description: 微信导出的文本格式
            example: |
              张三 2026/3/1 10:30:00
              这是一条消息
          - id: wechat_db
            name: 微信数据库
            description: PC微信本地数据库
          - id: json
            name: JSON格式
            description: 通用JSON格式
          - id: csv
            name: CSV格式
            description: 通用CSV格式
```

---

## 风险控制

### 风险矩阵

| 风险 | 等级 | 缓解措施 |
|------|------|----------|
| 小号封号 | 🟡 中 | 只读模式、低频拉取、使用老号、风险隔离 |
| 实时通道断开 | 🟡 中 | 自动检测、告警通知、批量导入兜底 |
| 消息重复导入 | 🟢 低 | 时间戳+哈希双重去重 |
| 数据丢失 | 🟢 低 | 批量导入兜底、断点续传、状态追踪 |
| 消息顺序错误 | 🟢 低 | 时序重放引擎保证顺序 |

### 降级策略

```
实时通道状态检测（每 5 分钟）
      │
      ├── online → 正常运行
      │
      ├── offline > 10min → 发送告警
      │                    → 标记需要批量补齐
      │
      └── error → 记录错误
                → 尝试重启
                → 3次失败后禁用
```

---

## 实现计划

### Phase 1: 增量导入基础（优先）

1. 实现增量导入服务
2. 添加消息去重逻辑
3. 创建同步状态表
4. 实现同步状态管理

**预计工时**: 3 天

### Phase 2: Wechaty 集成

1. 集成 Wechaty SDK
2. 实现只读模式监听
3. 消息格式转换
4. 错误处理与重连

**预计工时**: 5 天

### Phase 3: 混合模式

1. 实现双通道切换
2. 状态监控告警
3. 断点续传
4. 管理界面

**预计工时**: 3 天

---

## 配置项

```yaml
# config.yaml
wechat:
  # Wechaty 配置
  wechaty:
    enabled: false
    puppet: "wechaty-puppet-service"
    token: "${WECHATY_TOKEN}"
    mode: "readonly"  # readonly | full
    heartbeat_interval: 300  # 5 分钟

  # 同步配置
  sync:
    default_mode: "batch"  # realtime | batch | hybrid
    dedup_window: 86400  # 去重窗口：24小时
    max_retry: 3

  # 导入配置
  import:
    max_file_size: 100MB
    supported_formats:
      - wechat_txt
      - wechat_db
      - json
      - csv
```

---

**文档版本**: v1.0
**创建时间**: 2026-03-03
**状态**: 已确认