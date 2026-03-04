"""Phase 1 DDL additions - 新增12张表 + ALTER 2张"""

pg_additions = """

-- =============================================================
-- 用户在线状态（需求2+4）
-- =============================================================

CREATE TABLE user_presence (
    user_id        VARCHAR(255) PRIMARY KEY,
    status         VARCHAR(20) NOT NULL DEFAULT 'offline'
                   CHECK (status IN ('online','idle','offline')),
    last_heartbeat TIMESTAMPTZ,
    client_info    JSONB NOT NULL DEFAULT '{}',
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE user_presence IS '用户在线状态：客户端每30秒心跳，60秒未收到则标记离线';

-- =============================================================
-- 离线消息队列（需求2）
-- =============================================================

CREATE TABLE queued_notifications (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id      VARCHAR(255) NOT NULL,
    event_type   VARCHAR(50) NOT NULL,
    payload      JSONB NOT NULL DEFAULT '{}',
    priority     INTEGER NOT NULL DEFAULT 5,
    expires_at   TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_queued_notif_user ON queued_notifications (user_id, priority)
    WHERE delivered_at IS NULL;
CREATE INDEX idx_queued_notif_expired ON queued_notifications (expires_at)
    WHERE delivered_at IS NULL AND expires_at IS NOT NULL;

COMMENT ON TABLE queued_notifications IS '离线消息队列：用户离线时缓存通知，上线后 Heartbeat 触发批量推送';

-- =============================================================
-- 软能力扩展定义（需求1A）
-- =============================================================

CREATE TABLE extension_definitions (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ext_type     VARCHAR(30) NOT NULL
                 CHECK (ext_type IN ('category','task_type','label')),
    ext_key      VARCHAR(100) NOT NULL UNIQUE,
    display_name VARCHAR(200) NOT NULL,
    description  TEXT,
    parent_key   VARCHAR(100),
    risk_level   VARCHAR(10) NOT NULL DEFAULT 'low'
                 CHECK (risk_level IN ('low','high')),
    status       VARCHAR(20) NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending','active','disabled')),
    proposed_by  VARCHAR(255) NOT NULL DEFAULT 'nullclaw',
    approved_by  VARCHAR(255),
    approved_at  TIMESTAMPTZ,
    config       JSONB NOT NULL DEFAULT '{}',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ext_def_status ON extension_definitions (status, ext_type);

COMMENT ON TABLE extension_definitions IS '软能力扩展定义：管家提议新分类/任务类型，低风险直接生效，高风险管理员审核';

-- =============================================================
-- 硬能力扩展注册表（需求1B）
-- =============================================================

CREATE TABLE extension_registry (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name         VARCHAR(200) NOT NULL UNIQUE,
    ext_track    VARCHAR(30) NOT NULL
                 CHECK (ext_track IN ('event_hook','nullclaw_script')),
    hook_events  TEXT[] NOT NULL DEFAULT '{}',
    webhook_url  TEXT,
    script_path  TEXT,
    version      VARCHAR(50) NOT NULL DEFAULT '1.0.0',
    status       VARCHAR(20) NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending','active','disabled')),
    approved_by  VARCHAR(255),
    config       JSONB NOT NULL DEFAULT '{}',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE extension_invocation_logs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    extension_id    UUID NOT NULL REFERENCES extension_registry(id) ON DELETE CASCADE,
    hook_event      VARCHAR(100),
    input_payload   JSONB NOT NULL DEFAULT '{}',
    output_payload  JSONB NOT NULL DEFAULT '{}',
    status          VARCHAR(20) NOT NULL
                    CHECK (status IN ('success','failed','timeout')),
    duration_ms     INTEGER,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ext_invoke_ext ON extension_invocation_logs (extension_id, created_at DESC);
CREATE INDEX idx_ext_invoke_failed ON extension_invocation_logs (status, created_at DESC)
    WHERE status != 'success';

COMMENT ON TABLE extension_registry IS '硬能力扩展注册：Event Hook 或 nullclaw 脚本，均需管理员审核';
COMMENT ON TABLE extension_invocation_logs IS '插件调用日志：每次 Hook 触发记录，用于审计和调试';

-- =============================================================
-- 工作流模板与实例（需求3）
-- =============================================================

CREATE TABLE workflow_templates (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(200) NOT NULL,
    trigger_pattern TEXT,
    trigger_regex   TEXT,
    steps           JSONB NOT NULL DEFAULT '[]',
    learned_from    TEXT[] NOT NULL DEFAULT '{}',
    style_notes     TEXT,
    trust_level     VARCHAR(20) NOT NULL DEFAULT 'supervised'
                    CHECK (trust_level IN ('supervised','autonomous')),
    trust_score     REAL NOT NULL DEFAULT 0
                    CHECK (trust_score BETWEEN 0 AND 1),
    used_count      INTEGER NOT NULL DEFAULT 0,
    success_count   INTEGER NOT NULL DEFAULT 0,
    created_by      VARCHAR(255) NOT NULL DEFAULT 'nullclaw',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE workflow_instances (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    template_id         UUID REFERENCES workflow_templates(id) ON DELETE SET NULL,
    trigger_thread_id   UUID REFERENCES topic_threads(id) ON DELETE SET NULL,
    trigger_message_id  UUID REFERENCES messages(id) ON DELETE SET NULL,
    status              VARCHAR(30) NOT NULL DEFAULT 'pending_approval'
                        CHECK (status IN ('pending_approval','running','completed','cancelled','failed')),
    approved_by         VARCHAR(255),
    approval_expires_at TIMESTAMPTZ,
    context             JSONB NOT NULL DEFAULT '{}',
    execution_log       JSONB NOT NULL DEFAULT '[]',
    cancelled_reason    TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at        TIMESTAMPTZ
);

CREATE INDEX idx_wf_instance_status ON workflow_instances (status, created_at DESC);
CREATE INDEX idx_wf_instance_approval ON workflow_instances (approval_expires_at)
    WHERE status = 'pending_approval';

CREATE TABLE task_delegates (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    source_thread_id UUID REFERENCES topic_threads(id) ON DELETE SET NULL,
    target_user_id   VARCHAR(255) NOT NULL,
    target_group_id  VARCHAR(255),
    task_description TEXT NOT NULL,
    delegated_by     VARCHAR(255) NOT NULL DEFAULT 'nullclaw',
    status           VARCHAR(20) NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending','accepted','rejected','completed')),
    due_at           TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_task_delegate_target ON task_delegates (target_user_id, status);

COMMENT ON TABLE workflow_templates IS '工作流模板：管家从消息流学习抽象，包含触发条件和执行步骤';
COMMENT ON TABLE workflow_instances IS '工作流实例：每次触发创建，supervised 模式需用户审批';
COMMENT ON TABLE task_delegates IS '跨群任务分发：管家将任务分发给其他群成员，跟踪状态';

-- =============================================================
-- 检索记录与召回率自省（需求7）
-- =============================================================

CREATE TABLE search_logs (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    query        TEXT NOT NULL,
    query_type   VARCHAR(30) NOT NULL
                 CHECK (query_type IN ('fts','kg_traverse','qa','faq','combined')),
    result_ids   TEXT[] NOT NULL DEFAULT '{}',
    result_count INTEGER NOT NULL DEFAULT 0,
    user_id      VARCHAR(255),
    group_id     VARCHAR(255),
    latency_ms   INTEGER,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_search_logs_user ON search_logs (user_id, created_at DESC);
CREATE INDEX idx_search_logs_type ON search_logs (query_type, created_at DESC);

CREATE TABLE recall_evaluations (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    evaluated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    query_sample      TEXT NOT NULL,
    index_results     TEXT[] NOT NULL DEFAULT '{}',
    fullscan_results  TEXT[] NOT NULL DEFAULT '{}',
    recall_rate       REAL,
    precision_rate    REAL,
    improvement_notes TEXT
);

COMMENT ON TABLE search_logs IS '检索日志：记录每次查询，用于召回率自省和检索策略优化';
COMMENT ON TABLE recall_evaluations IS '召回率评估：每月 nullclaw Routine C 对比索引检索 vs 全文扫描';

-- =============================================================
-- 跟踪项自定义属性（需求8）
-- =============================================================

CREATE TABLE custom_field_definitions (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    entity_type  VARCHAR(30) NOT NULL
                 CHECK (entity_type IN ('thread','todo','faq_item','workflow')),
    group_id     VARCHAR(255),
    field_key    VARCHAR(100) NOT NULL,
    field_name   VARCHAR(200) NOT NULL,
    field_type   VARCHAR(20) NOT NULL
                 CHECK (field_type IN ('text','number','date','select','boolean')),
    options      JSONB NOT NULL DEFAULT '[]',
    suggested_by VARCHAR(255),
    adopted_by   VARCHAR(255),
    adopted_at   TIMESTAMPTZ,
    usage_count  INTEGER NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (entity_type, group_id, field_key)
);

CREATE TABLE custom_field_values (
    entity_type VARCHAR(30) NOT NULL,
    entity_id   UUID NOT NULL,
    field_id    UUID NOT NULL REFERENCES custom_field_definitions(id) ON DELETE CASCADE,
    value       TEXT,
    set_by      VARCHAR(255),
    set_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (entity_type, entity_id, field_id)
);

CREATE INDEX idx_custom_field_entity ON custom_field_values (entity_type, entity_id);

COMMENT ON TABLE custom_field_definitions IS '自定义字段定义：用户或管家定义，管家可推荐，采纳后系统记忆复用';
COMMENT ON TABLE custom_field_values IS '自定义字段值：各实体的自定义属性值';

-- =============================================================
-- butler_proposals 补充 PRD 字段（需求6）
-- =============================================================

ALTER TABLE butler_proposals
    ADD COLUMN prd_content  TEXT,
    ADD COLUMN prd_format   VARCHAR(50) DEFAULT 'rippleflow_prd_v1',
    ADD COLUMN notify_devs  BOOLEAN NOT NULL DEFAULT TRUE;

COMMENT ON COLUMN butler_proposals.prd_content IS 'PRD markdown 全文，由管家自省生成，上报给管理员和开发团队';
COMMENT ON COLUMN butler_proposals.notify_devs IS '是否通知 claw 开发团队';
"""

sqlite_additions = """

-- =============================================================
-- 用户在线状态（需求2+4）
-- =============================================================

CREATE TABLE user_presence (
    user_id        TEXT PRIMARY KEY,
    status         TEXT NOT NULL DEFAULT 'offline'
                   CHECK (status IN ('online','idle','offline')),
    last_heartbeat TEXT,
    client_info    TEXT NOT NULL DEFAULT '{}',
    updated_at     TEXT NOT NULL DEFAULT (datetime('now'))
);

-- =============================================================
-- 离线消息队列（需求2）
-- =============================================================

CREATE TABLE queued_notifications (
    id           TEXT PRIMARY KEY,
    user_id      TEXT NOT NULL,
    event_type   TEXT NOT NULL,
    payload      TEXT NOT NULL DEFAULT '{}',
    priority     INTEGER NOT NULL DEFAULT 5,
    expires_at   TEXT,
    delivered_at TEXT,
    created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_queued_notif_user ON queued_notifications (user_id, priority)
    WHERE delivered_at IS NULL;

-- =============================================================
-- 软能力扩展定义（需求1A）
-- =============================================================

CREATE TABLE extension_definitions (
    id           TEXT PRIMARY KEY,
    ext_type     TEXT NOT NULL CHECK (ext_type IN ('category','task_type','label')),
    ext_key      TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    description  TEXT,
    parent_key   TEXT,
    risk_level   TEXT NOT NULL DEFAULT 'low' CHECK (risk_level IN ('low','high')),
    status       TEXT NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending','active','disabled')),
    proposed_by  TEXT NOT NULL DEFAULT 'nullclaw',
    approved_by  TEXT,
    approved_at  TEXT,
    config       TEXT NOT NULL DEFAULT '{}',
    created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

-- =============================================================
-- 硬能力扩展注册表（需求1B）
-- =============================================================

CREATE TABLE extension_registry (
    id           TEXT PRIMARY KEY,
    name         TEXT NOT NULL UNIQUE,
    ext_track    TEXT NOT NULL CHECK (ext_track IN ('event_hook','nullclaw_script')),
    hook_events  TEXT NOT NULL DEFAULT '[]',
    webhook_url  TEXT,
    script_path  TEXT,
    version      TEXT NOT NULL DEFAULT '1.0.0',
    status       TEXT NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending','active','disabled')),
    approved_by  TEXT,
    config       TEXT NOT NULL DEFAULT '{}',
    created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE extension_invocation_logs (
    id              TEXT PRIMARY KEY,
    extension_id    TEXT NOT NULL REFERENCES extension_registry(id) ON DELETE CASCADE,
    hook_event      TEXT,
    input_payload   TEXT NOT NULL DEFAULT '{}',
    output_payload  TEXT NOT NULL DEFAULT '{}',
    status          TEXT NOT NULL CHECK (status IN ('success','failed','timeout')),
    duration_ms     INTEGER,
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

-- =============================================================
-- 工作流模板与实例（需求3）
-- =============================================================

CREATE TABLE workflow_templates (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    trigger_pattern TEXT,
    trigger_regex   TEXT,
    steps           TEXT NOT NULL DEFAULT '[]',
    learned_from    TEXT NOT NULL DEFAULT '[]',
    style_notes     TEXT,
    trust_level     TEXT NOT NULL DEFAULT 'supervised'
                    CHECK (trust_level IN ('supervised','autonomous')),
    trust_score     REAL NOT NULL DEFAULT 0
                    CHECK (trust_score BETWEEN 0 AND 1),
    used_count      INTEGER NOT NULL DEFAULT 0,
    success_count   INTEGER NOT NULL DEFAULT 0,
    created_by      TEXT NOT NULL DEFAULT 'nullclaw',
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE workflow_instances (
    id                  TEXT PRIMARY KEY,
    template_id         TEXT REFERENCES workflow_templates(id) ON DELETE SET NULL,
    trigger_thread_id   TEXT REFERENCES topic_threads(id) ON DELETE SET NULL,
    trigger_message_id  TEXT REFERENCES messages(id) ON DELETE SET NULL,
    status              TEXT NOT NULL DEFAULT 'pending_approval'
                        CHECK (status IN ('pending_approval','running','completed','cancelled','failed')),
    approved_by         TEXT,
    approval_expires_at TEXT,
    context             TEXT NOT NULL DEFAULT '{}',
    execution_log       TEXT NOT NULL DEFAULT '[]',
    cancelled_reason    TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    completed_at        TEXT
);

CREATE INDEX idx_wf_instance_status ON workflow_instances (status, created_at DESC);

CREATE TABLE task_delegates (
    id               TEXT PRIMARY KEY,
    source_thread_id TEXT REFERENCES topic_threads(id) ON DELETE SET NULL,
    target_user_id   TEXT NOT NULL,
    target_group_id  TEXT,
    task_description TEXT NOT NULL,
    delegated_by     TEXT NOT NULL DEFAULT 'nullclaw',
    status           TEXT NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending','accepted','rejected','completed')),
    due_at           TEXT,
    created_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

-- =============================================================
-- 检索记录与召回率自省（需求7）
-- =============================================================

CREATE TABLE search_logs (
    id           TEXT PRIMARY KEY,
    query        TEXT NOT NULL,
    query_type   TEXT NOT NULL
                 CHECK (query_type IN ('fts','kg_traverse','qa','faq','combined')),
    result_ids   TEXT NOT NULL DEFAULT '[]',
    result_count INTEGER NOT NULL DEFAULT 0,
    user_id      TEXT,
    group_id     TEXT,
    latency_ms   INTEGER,
    created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE recall_evaluations (
    id                TEXT PRIMARY KEY,
    evaluated_at      TEXT NOT NULL DEFAULT (datetime('now')),
    query_sample      TEXT NOT NULL,
    index_results     TEXT NOT NULL DEFAULT '[]',
    fullscan_results  TEXT NOT NULL DEFAULT '[]',
    recall_rate       REAL,
    precision_rate    REAL,
    improvement_notes TEXT
);

-- =============================================================
-- 跟踪项自定义属性（需求8）
-- =============================================================

CREATE TABLE custom_field_definitions (
    id           TEXT PRIMARY KEY,
    entity_type  TEXT NOT NULL CHECK (entity_type IN ('thread','todo','faq_item','workflow')),
    group_id     TEXT,
    field_key    TEXT NOT NULL,
    field_name   TEXT NOT NULL,
    field_type   TEXT NOT NULL CHECK (field_type IN ('text','number','date','select','boolean')),
    options      TEXT NOT NULL DEFAULT '[]',
    suggested_by TEXT,
    adopted_by   TEXT,
    adopted_at   TEXT,
    usage_count  INTEGER NOT NULL DEFAULT 0,
    created_at   TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (entity_type, group_id, field_key)
);

CREATE TABLE custom_field_values (
    entity_type TEXT NOT NULL,
    entity_id   TEXT NOT NULL,
    field_id    TEXT NOT NULL REFERENCES custom_field_definitions(id) ON DELETE CASCADE,
    value       TEXT,
    set_by      TEXT,
    set_at      TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (entity_type, entity_id, field_id)
);

-- butler_proposals PRD 字段（SQLite 通过迁移脚本处理）
-- 目标新增列：prd_content TEXT, prd_format TEXT DEFAULT 'rippleflow_prd_v1', notify_devs INTEGER DEFAULT 1
"""

with open('D:/RippleFlow/docs/02_database_ddl.sql', 'a', encoding='utf-8') as f:
    f.write(pg_additions)
print('PostgreSQL DDL done')

with open('D:/RippleFlow/docs/02b_database_ddl_sqlite.sql', 'a', encoding='utf-8') as f:
    f.write(sqlite_additions)
print('SQLite DDL done')
