"""Phase 6: 追加 §43 nullclaw Watchdog 监控架构 到 01_system_architecture.md"""

watchdog_section = """

---

## §43 nullclaw Watchdog 监控架构

### 43.1 设计原则

nullclaw 是平台的"大脑"，其可靠性直接影响信息平权的实现。
Watchdog 作为独立进程，专职负责 nullclaw 的健康保障，与 nullclaw 本身解耦。

```
可靠性分层：
  Watchdog（进程级保障）   ← 负责：监控、杀死、重启
       ↕
  nullclaw_pending_events  ← 负责：事件不丢失（应用级补偿）
       ↕
  nullclaw（业务执行层）   ← 负责：正常业务处理
```

### 43.2 Watchdog 架构

```
┌─────────────────────────────────────────────────────────────┐
│  nullclaw Watchdog（独立进程）                               │
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │  健康检测    │    │  故障决策    │    │  重启控制    │  │
│  │              │    │              │    │              │  │
│  │ • 进程存在?  │→   │ • 超时判断   │→   │ • 优雅停止   │  │
│  │ • 心跳响应?  │    │ • 连续失败N次│    │ • 强制 kill  │  │
│  │ • 内存/CPU   │    │ • 触发重启   │    │ • 重新拉起   │  │
│  │ • 响应延迟   │    │              │    │ • 等待就绪   │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  告警与记录                                          │   │
│  │  • 重启事件写入 watchdog_events 表                   │   │
│  │  • 连续重启 > 3次 → 告警管理员                      │   │
│  │  • 重启超过阈值 → 触发平台降级模式                  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 43.3 健康检测策略

Watchdog 采用多维度检测，避免误判：

| 检测维度 | 方法 | 失败标准 |
|----------|------|----------|
| 进程存活 | OS 进程表检查 | PID 不存在 |
| 心跳响应 | HTTP GET /health（nullclaw 内置） | 3s 超时无响应 |
| 功能可用 | 定期发送探针消息，检查是否处理 | 60s 内无回应 |
| 资源状态 | 内存 / CPU 使用率 | 内存 > 90% 持续 5min |

**检测频率：**
- 进程存活：每 5 秒
- 心跳响应：每 15 秒
- 功能可用（探针）：每 2 分钟
- 资源状态：每 30 秒

**重启决策（任一满足即触发）：**
- 进程不存在
- 心跳连续失败 3 次（45 秒无响应）
- 功能探针失败 1 次（2 分钟无处理）
- 内存 > 90% 持续 5 分钟

### 43.4 重启流程

```
检测到故障
  1. 记录 watchdog_events（fault_type, detected_at）
  2. 尝试优雅停止（SIGTERM → 等待 10s）
  3. 若进程仍存在 → SIGKILL
  4. 等待 2s 确保端口释放
  5. 拉起新 nullclaw 实例
  6. 等待 /health 返回 200（最多 30s）
  7. 更新 watchdog_events（restarted_at, duration_ms）
  8. 若等待超时 → 告警，进入下一次重试

连续重启保护（防止重启风暴）：
  重启间隔：1s → 5s → 30s → 5min（指数退避）
  连续重启 > 3次（5分钟内）→ 告警管理员 + 平台进入降级模式
```

### 43.5 与 nullclaw_pending_events 的协同

Watchdog 重启期间（平均 < 60s），平台正常处理消息，但事件通知暂缓：

```
nullclaw 重启中：
  平台收到消息
    → Stage 0-4 正常处理（平台自治，不依赖 nullclaw）
    → INotificationService.notify_nullclaw() 失败
        → 写入 nullclaw_pending_events（state=pending）

nullclaw 重启成功：
  → Watchdog 调用 POST /api/v1/internal/nullclaw/ready
  → 平台触发 INotificationService.retry_pending_events()
  → nullclaw 批量处理积压的 pending_events（优先级队列）
  → 补偿完成后恢复正常流转
```

**保证：**
- 消息不丢（平台侧已入库）
- 知识库更新不丢（Stage 0-4 不受影响）
- 推送/通知可能有 < 60s 延迟（重启期间）
- 重启后自动补偿，最终一致

### 43.6 Watchdog DDL

```sql
-- PostgreSQL
CREATE TABLE watchdog_events (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    fault_type      VARCHAR(50) NOT NULL,
        -- process_missing | heartbeat_timeout | probe_timeout
        -- memory_exceeded | manual_restart
    fault_detail    TEXT,
    detected_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    kill_sent_at    TIMESTAMPTZ,
    restarted_at    TIMESTAMPTZ,
    ready_at        TIMESTAMPTZ,
    duration_ms     INTEGER,              -- 从故障检测到就绪的总时长
    restart_count   INTEGER DEFAULT 1,   -- 本次累计重启次数
    alert_sent      BOOLEAN DEFAULT FALSE
);

CREATE INDEX idx_watchdog_events_time ON watchdog_events (detected_at DESC);
CREATE INDEX idx_watchdog_events_alert ON watchdog_events (alert_sent)
    WHERE alert_sent = FALSE;
```

### 43.7 Watchdog API（内部接口）

```
POST /api/v1/internal/nullclaw/ready    Watchdog 通知平台 nullclaw 已就绪
GET  /api/v1/internal/watchdog/status   查询 Watchdog 当前状态（管理员）
GET  /api/v1/internal/watchdog/events   查询重启历史（管理员）
```

### 43.8 降级模式

当 Watchdog 判断 nullclaw 无法正常恢复时（连续重启 > 3 次），平台进入降级模式：

| 功能 | 正常模式 | 降级模式 |
|------|----------|----------|
| 消息入库 | ✅ | ✅（不受影响） |
| FAQ 查询 | ✅ | ✅（不受影响） |
| 待办管理 | ✅ | ✅（不受影响） |
| 摘要更新 | nullclaw 执行 | ⏸ 暂停，积压 |
| 主动推送 | nullclaw 执行 | ⏸ 暂停，积压 |
| 工作流执行 | nullclaw 执行 | ⏸ 暂停，待恢复 |
| 每日摘要 | nullclaw 发送 | ⏸ 跳过本次 |

> 降级期间，平台核心知识库功能不受影响；管家侧的主动服务暂停，
> nullclaw 恢复后通过 pending_events 补偿。
"""

with open('D:/RippleFlow/docs/01_system_architecture.md', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.rstrip()
if content.endswith('**END OF DOCUMENT**'):
    content = content[:-len('**END OF DOCUMENT**')].rstrip()

content += watchdog_section + '\n\n---\n\n**END OF DOCUMENT**\n'

with open('D:/RippleFlow/docs/01_system_architecture.md', 'w', encoding='utf-8') as f:
    f.write(content)

print('01_system_architecture.md updated - §43 Watchdog added')
