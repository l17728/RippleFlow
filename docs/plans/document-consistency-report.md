# RippleFlow 文档一致性检查报告

## 检查日期：2026-03-03

## 一、需要重构的设计

### 1.1 事件总线 → nullclaw channels

| 文件 | 位置 | 原设计 | 重构方案 |
|------|------|--------|----------|
| `08_ai_butler_architecture.md` | §2.1, line 62 | 事件总线 (Event Bus) | 删除，改用 nullclaw channels |
| `08_ai_butler_architecture.md` | §3.2, line 212-243 | 触发框架 triggers.md | 保留，但说明由 nullclaw 接收事件 |

**具体改动**：
- 删除"事件总线 (Event Bus)"架构图
- 修改感知层说明，改为"通过 nullclaw channels 接收事件"
- 新增 RippleFlow 平台事件推送机制说明

### 1.2 Celery Beat → nullclaw cron

| 文件 | 位置 | 原设计 | 重构方案 |
|------|------|--------|----------|
| `01_system_architecture.md` | line 183 | ReminderScheduler (Celery Beat) | 删除，由 nullclaw cron 调度 |
| `01_system_architecture.md` | line 448 | beat: Celery Beat | 删除 |
| `01_system_architecture.md` | §11, line 484, 510 | Celery Beat 调度流程图 | 改为 nullclaw cron |
| `04_service_interfaces.md` | line 563 | Celery Beat 定时任务调用 | 改为 nullclaw 调用 |
| `09_user_manual.md` | line 641, 741 | Celery Beat 参与者 | 改为 nullclaw cron |
| `10_user_manual_kimi.md` | line 641, 741 | Celery Beat 参与者 | 改为 nullclaw cron |

**具体改动**：
- 删除 Celery Beat 相关配置和流程
- 修改流程图，使用 nullclaw cron 作为调度者
- 更新服务接口说明

### 1.3 Redis 依赖调整

| 文件 | 位置 | 原设计 | 重构方案 |
|------|------|--------|----------|
| `01_system_architecture.md` | docker-compose | redis 服务（必需） | 改为可选，仅用于缓存 |
| `00_overview.md` | 技术栈 | Redis（消息队列+缓存） | 改为可选，仅用于缓存 |

**具体改动**：
- Redis 从必需改为可选
- 说明无 Redis 时使用内存缓存

---

## 二、需要补充的内容

### 2.1 事件推送接口（新增）

**文件**：`03_api_reference.yaml`

需要新增 RippleFlow 平台向 nullclaw 推送事件的接口：

```yaml
# 内部接口（RippleFlow → nullclaw）
POST /internal/events/publish:
  summary: 发布事件到 nullclaw
  description: |
    RippleFlow 平台在业务操作完成后，通过此接口推送事件到 nullclaw。
    此接口仅供内部服务调用，不对外暴露。
  requestBody:
    content:
      application/json:
        schema:
          type: object
          required: [event, payload]
          properties:
            event:
              type: string
              enum:
                - message.received
                - thread.created
                - thread.updated
                - todo.created
                - todo.completed
                - sensitive.detected
                - sensitive.authorized
                - user.query
                - user.feedback
            timestamp:
              type: string
              format: date-time
            payload:
              type: object
```

### 2.2 服务接口调整（更新）

**文件**：`04_service_interfaces.md`

需要删除的接口：
- `ButlerScheduler` - 由 nullclaw 调度替代

需要修改的接口：
- `AIButlerService` - 删除 `send_daily_reminders()` 等定时任务方法
- 新增 `notify_nullclaw()` 方法

### 2.3 Memory 架构扩展（更新）

**文件**：`08_ai_butler_architecture.md`

需要补充 nullclaw memory 三层架构说明：
- L1 活跃层配置
- L2 归档层配置
- L3 核心层配置
- 自动压缩机制

### 2.4 多 Agent 架构（新增）

**文件**：`08_ai_butler_architecture.md`

需要补充多 Agent 协作架构：
- rippleflow_butler（主管家）
- rippleflow_qa（问答专家）
- rippleflow_analyst（分析专家）
- rippleflow_coordinator（协调专家）

### 2.5 安全机制补充（更新）

**文件**：`01_system_architecture.md`

需要补充 nullclaw security 能力：
- 配对验证机制
- 审计日志
- 频率限制

### 2.6 自主控制机制（新增）

**文件**：`08_ai_butler_architecture.md`

需要补充 autonomy 模块说明：
- 自主等级定义
- 成本控制
- 确认要求
- 自省策略

---

## 三、文档修改优先级

| 优先级 | 文件 | 修改类型 | 工作量 |
|--------|------|----------|--------|
| P0 | `08_ai_butler_architecture.md` | 重构 + 补充 | 大 |
| P0 | `01_system_architecture.md` | 重构 + 补充 | 中 |
| P1 | `04_service_interfaces.md` | 重构 | 小 |
| P1 | `03_api_reference.yaml` | 补充 | 小 |
| P2 | `09_user_manual.md` | 更新流程图 | 小 |
| P2 | `10_user_manual_kimi.md` | 更新流程图 | 小 |
| P2 | `00_overview.md` | 更新技术栈说明 | 小 |

---

## 四、建议执行顺序

1. **Phase 1**：重构核心架构文档
   - 更新 `08_ai_butler_architecture.md`
   - 更新 `01_system_architecture.md`

2. **Phase 2**：更新接口定义
   - 更新 `04_service_interfaces.md`
   - 更新 `03_api_reference.yaml`

3. **Phase 3**：更新用户文档
   - 更新 `09_user_manual.md`
   - 更新 `10_user_manual_kimi.md`
   - 更新 `00_overview.md`

---

## 五、验收标准

- [ ] 所有文档不再包含"事件总线"设计
- [ ] 所有文档不再包含"Celery Beat"依赖
- [ ] Redis 标注为可选
- [ ] 新增事件推送接口定义
- [ ] 补充 nullclaw 原生能力说明
- [ ] 文档间引用保持一致