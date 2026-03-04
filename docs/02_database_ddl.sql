-- =============================================================
-- RippleFlow Database DDL
-- PostgreSQL >= 15
-- Extensions: uuid-ossp, pg_trgm, unaccent
-- =============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "unaccent";

-- =============================================================
-- ENUM TYPES
-- =============================================================

CREATE TYPE category_type AS ENUM (
    'tech_decision',     -- 技术决策
    'qa_faq',            -- 问题解答
    'bug_incident',      -- 故障案例
    'reference_data',    -- 参考信息
    'action_item',       -- 任务待办
    'discussion_notes',  -- 讨论纪要
    'knowledge_share',   -- 知识分享
    'env_config',        -- 环境配置
    'project_update'     -- 项目动态
);

CREATE TYPE thread_status AS ENUM (
    'active',     -- 进行中
    'resolved',   -- 已解决/已完成
    'archived',   -- 已归档
    'merged'      -- 已合并到其他线索
);

CREATE TYPE message_processing_status AS ENUM (
    'pending',              -- 待处理
    'processing',           -- 处理中
    'classified',           -- 已完成分类归档
    'failed',               -- 处理失败
    'skipped',              -- 噪声，跳过
    'sensitive_pending',    -- 敏感内容，待授权
    'sensitive_rejected'    -- 敏感内容，已拒绝
);

CREATE TYPE sensitive_overall_status AS ENUM (
    'pending',                  -- 等待所有当事人表态
    'authorized',               -- 全部明确授权
    'rejected',                 -- 至少一人拒绝
    'pending_desensitization'   -- 等待确认脱敏版本
);

CREATE TYPE action_item_status AS ENUM (
    'open',
    'in_progress',
    'done',
    'cancelled'
);

CREATE TYPE incident_status AS ENUM (
    'open',
    'investigating',
    'mitigated',
    'resolved'
);

CREATE TYPE notification_type AS ENUM (
    'sensitive_pending',    -- 有敏感内容待授权
    'thread_modified',      -- 你参与的话题被修改
    'consensus_drift',      -- 话题有后续讨论/冲突
    'action_item_assigned', -- 有任务指派给你
    'reminder'              -- 提醒
);

-- =============================================================
-- TABLE: chat_rooms
-- 聊天群组（来自自研聊天工具）
-- =============================================================

CREATE TABLE chat_rooms (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_external_id VARCHAR(255) UNIQUE NOT NULL,
    room_name        VARCHAR(500)        NOT NULL,
    room_type        VARCHAR(50)         NOT NULL DEFAULT 'group',
    is_active        BOOLEAN             NOT NULL DEFAULT true,
    created_at       TIMESTAMPTZ         NOT NULL DEFAULT NOW(),
    metadata         JSONB               NOT NULL DEFAULT '{}'
);

CREATE INDEX idx_rooms_external ON chat_rooms(room_external_id);

-- =============================================================
-- TABLE: chat_users
-- 聊天工具用户（来自自研聊天工具，ldap_user_id 为关联键）
-- =============================================================

CREATE TABLE chat_users (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_external_id VARCHAR(255) UNIQUE NOT NULL, -- 聊天工具内部 ID
    ldap_user_id     VARCHAR(255),                 -- LDAP 用户 ID（关联白名单）
    display_name     VARCHAR(255)        NOT NULL,
    email            VARCHAR(255),
    is_bot           BOOLEAN             NOT NULL DEFAULT false,
    created_at       TIMESTAMPTZ         NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ         NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_chat_users_ldap ON chat_users(ldap_user_id);
CREATE INDEX idx_chat_users_external ON chat_users(user_external_id);

-- =============================================================
-- TABLE: user_whitelist
-- 系统访问白名单（唯一权限控制表）
-- =============================================================

CREATE TABLE user_whitelist (
    ldap_user_id VARCHAR(255) PRIMARY KEY,
    display_name VARCHAR(255)       NOT NULL,
    email        VARCHAR(255),
    role         VARCHAR(50)        NOT NULL DEFAULT 'member', -- 'member' | 'admin'
    added_by     VARCHAR(255),                                 -- 操作者 ldap_user_id
    added_at     TIMESTAMPTZ        NOT NULL DEFAULT NOW(),
    is_active    BOOLEAN            NOT NULL DEFAULT true,
    notes        TEXT
);

CREATE INDEX idx_whitelist_active ON user_whitelist(is_active) WHERE is_active = true;

-- =============================================================
-- TABLE: category_definitions
-- 信息类别定义（9 个默认 + 管理员可新增）
-- =============================================================

CREATE TABLE category_definitions (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code          VARCHAR(100) UNIQUE NOT NULL, -- 对应 category_type 枚举或扩展值
    display_name  VARCHAR(200)        NOT NULL,
    description   TEXT,
    trigger_hints TEXT[]              NOT NULL DEFAULT '{}', -- 给 LLM 的触发提示
    -- 时间窗口（天数，NULL = 永久有效）
    search_window_days INTEGER,
    is_active      BOOLEAN            NOT NULL DEFAULT true,
    is_builtin     BOOLEAN            NOT NULL DEFAULT false, -- 内置 9 类不可删除
    sort_order     INTEGER            NOT NULL DEFAULT 0,
    created_at     TIMESTAMPTZ        NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ        NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_catdef_active ON category_definitions(is_active) WHERE is_active = true;

-- 插入默认 9 类
INSERT INTO category_definitions
    (code, display_name, description, trigger_hints, search_window_days, is_builtin, sort_order)
VALUES
('tech_decision', '技术决策',
 '架构选型、技术方案确认、设计决策及其背后的理由',
 ARRAY['决定','方案','选型','采用','改用','弃用','ADR','tradeoff','我们决定','达成共识'],
 NULL, true, 1),

('qa_faq', '问题解答',
 '技术问答、排查方法，问题-答案对自动沉淀为 FAQ',
 ARRAY['怎么','如何','为什么','是什么','anyone know','报错','解决方法','原因是','fix'],
 90, true, 2),

('bug_incident', '故障案例',
 'Bug 报告、线上故障、根因分析及解决过程',
 ARRAY['bug','报错','异常','crash','故障','崩了','不行了','排查','修复','postmortem'],
 90, true, 3),

('reference_data', '参考信息',
 '团队共用的 IP、URL、端口、服务地址、账号名等参考数据',
 ARRAY['地址','ip','url','端口','入口','账号','域名','endpoint','服务器'],
 NULL, true, 4),

('action_item', '任务待办',
 '有明确负责人的任务指派、待办项',
 ARRAY['你来','负责','记得','TODO','action item','截止','deadline','@人名 + 动作'],
 30, true, 5),

('discussion_notes', '讨论纪要',
 '多人讨论的关键结论、共识记录、会议纪要',
 ARRAY['讨论','总结','纪要','共识','结论','standup','会议','sync','retro'],
 90, true, 6),

('knowledge_share', '知识分享',
 '技术文章推荐、经验分享、TIL、最佳实践',
 ARRAY['分享','推荐','TIL','今天学到','技巧','tip','pro tip','经验','记录一下'],
 180, true, 7),

('env_config', '环境配置',
 '开发/测试/生产环境配置、部署步骤、环境搭建说明',
 ARRAY['配置','部署','setup','env','环境变量','dockerfile','安装','搭建','怎么跑起来'],
 NULL, true, 8),

('project_update', '项目动态',
 '版本发布、里程碑、项目状态更新',
 ARRAY['上线','发布','release','v1','版本','里程碑','milestone','完成了','shipped'],
 180, true, 9);

-- =============================================================
-- TABLE: messages
-- 原始消息（不可变，永久保留出处）
-- =============================================================

CREATE TABLE messages (
    id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    external_msg_id      VARCHAR(255) UNIQUE NOT NULL,
    room_id              UUID REFERENCES chat_rooms(id) ON DELETE SET NULL,
    sender_id            UUID REFERENCES chat_users(id) ON DELETE SET NULL,

    -- 内容
    content              TEXT                NOT NULL,
    content_type         VARCHAR(50)         NOT NULL DEFAULT 'text',
    -- 'text' | 'image' | 'file' | 'audio' | 'video' | 'code'
    mentions             JSONB               NOT NULL DEFAULT '[]',
    -- [{user_external_id, display_name}]
    attachments          JSONB               NOT NULL DEFAULT '[]',
    -- [{type, url, name, size_bytes}]

    -- 聊天工具内的回复/线索结构
    reply_to_msg_id      VARCHAR(255),       -- 被回复的消息 external_msg_id
    thread_root_msg_id   VARCHAR(255),       -- 会话线索根消息 external_msg_id

    -- 时间戳
    sent_at              TIMESTAMPTZ         NOT NULL,
    ingested_at          TIMESTAMPTZ         NOT NULL DEFAULT NOW(),

    -- 处理状态
    processing_status    message_processing_status NOT NULL DEFAULT 'pending',
    processed_at         TIMESTAMPTZ,
    processing_attempts  INTEGER             NOT NULL DEFAULT 0,
    processing_error     TEXT,

    -- LLM 处理结果（原始，供调试）
    is_noise             BOOLEAN,
    noise_reason         VARCHAR(500),
    classification_raw   JSONB,              -- LLM 原始输出

    -- 历史数据标记
    is_imported          BOOLEAN             NOT NULL DEFAULT false,
    import_batch_id      VARCHAR(255),

    metadata             JSONB               NOT NULL DEFAULT '{}'
);

CREATE INDEX idx_messages_room_sent   ON messages(room_id, sent_at DESC);
CREATE INDEX idx_messages_status      ON messages(processing_status)
    WHERE processing_status IN ('pending', 'processing', 'failed', 'sensitive_pending');
CREATE INDEX idx_messages_sent_at     ON messages(sent_at DESC);
CREATE INDEX idx_messages_external    ON messages(external_msg_id);
CREATE INDEX idx_messages_import      ON messages(import_batch_id) WHERE import_batch_id IS NOT NULL;

-- =============================================================
-- TABLE: topic_threads
-- 话题线索（核心数据结构，活摘要）
-- =============================================================

CREATE TABLE topic_threads (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- 身份
    title               VARCHAR(500)     NOT NULL,
    category            VARCHAR(100)     NOT NULL, -- 对应 category_definitions.code
    status              thread_status    NOT NULL DEFAULT 'active',

    -- 活摘要（每次有新消息时由 LLM 更新）
    summary             TEXT             NOT NULL,
    summary_version     INTEGER          NOT NULL DEFAULT 1,
    summary_updated_at  TIMESTAMPTZ      NOT NULL DEFAULT NOW(),

    -- 结构化提取数据（按 category 填充不同字段）
    structured_data     JSONB            NOT NULL DEFAULT '{}',
    /*
    tech_decision: {
      decision: str,
      alternatives: [str],
      rationale: str,
      decision_makers: [ldap_user_id],
      pending_revision: {proposed_change, raised_by, raised_at} | null
    }
    qa_faq: {
      question: str,
      answer: str,
      confidence: float,
      sources: [url]
    }
    bug_incident: {
      error_message: str,
      affected_service: str,
      environment: str,
      root_cause: str | null,
      resolution: str | null,
      status: incident_status,
      reported_by: ldap_user_id
    }
    reference_data: {
      items: [{resource_type, label, value, environment, service_name}]
    }
    action_item: {
      task: str,
      assignee: ldap_user_id,
      assigner: ldap_user_id,
      due_date: date | null,
      priority: 'high'|'medium'|'low',
      status: action_item_status
    }
    discussion_notes: {
      agenda: str,
      participants: [ldap_user_id],
      key_points: [str],
      decisions: [str],
      action_items: [str],
      open_questions: [str]
    }
    knowledge_share: {
      topic: str,
      content_summary: str,
      sources: [url],
      tech_tags: [str]
    }
    env_config: {
      environment: str,
      service: str,
      steps: [str],
      config_values: {key: value},
      version: str | null
    }
    project_update: {
      project: str,
      update_type: 'release'|'milestone'|'status'|'personnel',
      version: str | null,
      what_changed: str,
      current_status: str
    }
    */

    -- 标签与索引
    tags                TEXT[]           NOT NULL DEFAULT '{}',
    mentioned_services  TEXT[]           NOT NULL DEFAULT '{}',
    mentioned_techs     TEXT[]           NOT NULL DEFAULT '{}',

    -- 当事人（有权修改此线索的用户）
    stakeholder_ids     TEXT[]           NOT NULL DEFAULT '{}', -- ldap_user_id[]

    -- 来源追踪
    source_room_ids     UUID[]           NOT NULL DEFAULT '{}',
    primary_room_id     UUID             REFERENCES chat_rooms(id) ON DELETE SET NULL,
    message_count       INTEGER          NOT NULL DEFAULT 0,
    first_message_at    TIMESTAMPTZ,
    last_message_at     TIMESTAMPTZ,

    -- 关联其他线索
    related_thread_ids  UUID[]           NOT NULL DEFAULT '{}',
    merged_into_id      UUID             REFERENCES topic_threads(id) ON DELETE SET NULL,

    -- 修改信息
    last_modified_by    VARCHAR(255),    -- ldap_user_id
    last_modified_at    TIMESTAMPTZ,

    -- 全文检索向量（自动维护，包含 structured_data 关键字段）
    search_vector       TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('simple',
            coalesce(title, '')   || ' ' ||
            coalesce(summary, '') || ' ' ||
            coalesce(array_to_string(tags, ' '), '') || ' ' ||
            coalesce(array_to_string(mentioned_services, ' '), '') || ' ' ||
            coalesce(array_to_string(mentioned_techs, ' '), '') || ' ' ||
            -- 从 structured_data 提取关键文本
            coalesce(structured_data->>'decision', '') || ' ' ||
            coalesce(structured_data->>'answer', '') || ' ' ||
            coalesce(structured_data->>'error_message', '') || ' ' ||
            coalesce(structured_data->>'task', '') || ' ' ||
            coalesce(structured_data->>'agenda', '') || ' ' ||
            coalesce(structured_data->>'question', '') || ' ' ||
            coalesce(structured_data->>'root_cause', '') || ' ' ||
            coalesce(structured_data->>'resolution', '')
        )
    ) STORED,

    created_at          TIMESTAMPTZ      NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ      NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_threads_category      ON topic_threads(category);
CREATE INDEX idx_threads_status        ON topic_threads(status);
CREATE INDEX idx_threads_last_msg      ON topic_threads(last_message_at DESC);
CREATE INDEX idx_threads_search        ON topic_threads USING gin(search_vector);
CREATE INDEX idx_threads_tags          ON topic_threads USING gin(tags);
CREATE INDEX idx_threads_services      ON topic_threads USING gin(mentioned_services);
CREATE INDEX idx_threads_techs         ON topic_threads USING gin(mentioned_techs);
CREATE INDEX idx_threads_title_trgm    ON topic_threads USING gin(title gin_trgm_ops);
CREATE INDEX idx_threads_stakeholders  ON topic_threads USING gin(stakeholder_ids);

-- =============================================================
-- TABLE: message_thread_links
-- 消息与话题线索的多对多关联
-- =============================================================

CREATE TABLE message_thread_links (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id      UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    thread_id       UUID NOT NULL REFERENCES topic_threads(id) ON DELETE CASCADE,
    relevance_score FLOAT NOT NULL DEFAULT 1.0, -- 0-1
    contribution    VARCHAR(100) NOT NULL DEFAULT 'extended',
    -- 'created' | 'extended' | 'resolved' | 'updated' | 'context'
    linked_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(message_id, thread_id)
);

CREATE INDEX idx_mtl_message ON message_thread_links(message_id);
CREATE INDEX idx_mtl_thread  ON message_thread_links(thread_id, linked_at DESC);

-- =============================================================
-- TABLE: thread_summary_history
-- 摘要历史（审计 + 溯源，Append-Only）
-- =============================================================

CREATE TABLE thread_summary_history (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    thread_id       UUID        NOT NULL REFERENCES topic_threads(id) ON DELETE CASCADE,
    version         INTEGER     NOT NULL,
    summary         TEXT        NOT NULL,
    structured_data JSONB       NOT NULL DEFAULT '{}',
    change_reason   VARCHAR(500),   -- 'new_messages' | 'stakeholder_edit' | 'admin_edit'
    trigger_msg_ids UUID[]      NOT NULL DEFAULT '{}',
    changed_by      VARCHAR(255),   -- ldap_user_id，NULL 表示系统自动
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(thread_id, version)
);

CREATE INDEX idx_summary_hist_thread ON thread_summary_history(thread_id, version DESC);

-- =============================================================
-- TABLE: thread_modifications
-- 当事人手动修改记录（审计 + 群同步追踪）
-- =============================================================

CREATE TABLE thread_modifications (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    thread_id           UUID        NOT NULL REFERENCES topic_threads(id) ON DELETE CASCADE,
    modified_by         VARCHAR(255) NOT NULL, -- ldap_user_id
    modified_by_name    VARCHAR(255) NOT NULL,

    -- 修改内容
    field_modified      VARCHAR(100) NOT NULL, -- 'summary' | 'structured_data' | 'tags' | 'status'
    value_before        TEXT,
    value_after         TEXT,
    modification_reason TEXT        NOT NULL,

    -- 群同步
    synced_to_chat      BOOLEAN     NOT NULL DEFAULT false,
    sync_room_id        VARCHAR(255),           -- 聊天工具群 ID
    sync_message_id     VARCHAR(255),           -- 群中的消息 ID
    synced_at           TIMESTAMPTZ,
    sync_error          TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_modifications_thread ON thread_modifications(thread_id, created_at DESC);
CREATE INDEX idx_modifications_user   ON thread_modifications(modified_by);
CREATE INDEX idx_modifications_unsync ON thread_modifications(synced_to_chat)
    WHERE synced_to_chat = false;

-- =============================================================
-- TABLE: reference_data_items
-- 参考信息特化表（IP/URL 等一等公民）
-- =============================================================

CREATE TABLE reference_data_items (
    id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    thread_id     UUID         REFERENCES topic_threads(id) ON DELETE SET NULL,
    message_id    UUID         REFERENCES messages(id) ON DELETE SET NULL,

    resource_type VARCHAR(100) NOT NULL,
    -- 'ip' | 'url' | 'endpoint' | 'domain' | 'account' | 'port' | 'other'
    label         VARCHAR(500) NOT NULL,    -- 可读名称，如「测试环境」
    value         TEXT,                    -- 实际值（is_sensitive=true 时为空）
    is_sensitive  BOOLEAN      NOT NULL DEFAULT false,
    environment   VARCHAR(100),            -- 'prod' | 'staging' | 'dev' | 'local'
    service_name  VARCHAR(255),
    description   TEXT,
    is_deprecated BOOLEAN      NOT NULL DEFAULT false,
    deprecated_at TIMESTAMPTZ,
    deprecated_by VARCHAR(255),           -- ldap_user_id

    shared_by     VARCHAR(255),           -- ldap_user_id
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refdata_type        ON reference_data_items(resource_type);
CREATE INDEX idx_refdata_environment ON reference_data_items(environment);
CREATE INDEX idx_refdata_service     ON reference_data_items(service_name);
CREATE INDEX idx_refdata_active      ON reference_data_items(is_deprecated)
    WHERE is_deprecated = false;
CREATE INDEX idx_refdata_label_trgm  ON reference_data_items
    USING gin(label gin_trgm_ops);

-- =============================================================
-- TABLE: sensitive_authorizations
-- 敏感内容授权管理
-- =============================================================

CREATE TABLE sensitive_authorizations (
    id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id            UUID        NOT NULL REFERENCES messages(id) ON DELETE CASCADE,

    -- 敏感内容描述
    sensitive_types       TEXT[]      NOT NULL DEFAULT '{}',
    -- ['privacy', 'hr', 'dispute']
    sensitive_summary     TEXT        NOT NULL, -- LLM 解释为何敏感

    -- 当事人与决策
    decisions             JSONB       NOT NULL DEFAULT '{}',
    /*
    {
      "ldap_user_id": {
        "status": "pending"|"authorize"|"reject"|"desensitize",
        "decided_at": "ISO8601" | null,
        "note": "str | null"   // 脱敏说明
      }
    }
    */

    overall_status        sensitive_overall_status NOT NULL DEFAULT 'pending',
    rejected_by           VARCHAR(255),  -- ldap_user_id，第一个拒绝者
    rejected_at           TIMESTAMPTZ,
    authorized_at         TIMESTAMPTZ,   -- 最后一人授权时间

    -- 脱敏版本（有人选 desensitize 时生成）
    desensitized_content  TEXT,

    -- 管理员介入记录
    admin_overrides       JSONB        NOT NULL DEFAULT '[]',
    /*
    [{
      "admin_id": "ldap_user_id",
      "action": "remove_stakeholder"|"force_authorize"|"force_reject",
      "target_user": "ldap_user_id" | null,
      "reason": "str",
      "at": "ISO8601"
    }]
    */

    -- 提醒追踪与升级
    reminder_count        INTEGER      NOT NULL DEFAULT 0,
    last_reminder_at      TIMESTAMPTZ,

    -- 升级机制（7天后升级管理员）
    escalation_after      INTERVAL     NOT NULL DEFAULT INTERVAL '7 days',
    escalated_at          TIMESTAMPTZ,
    escalated_to          VARCHAR(255), -- 处理升级的管理员 ldap_user_id

    created_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sensitive_message     ON sensitive_authorizations(message_id);
CREATE INDEX idx_sensitive_status      ON sensitive_authorizations(overall_status)
    WHERE overall_status = 'pending';
CREATE INDEX idx_sensitive_reminder    ON sensitive_authorizations(last_reminder_at)
    WHERE overall_status = 'pending';
CREATE INDEX idx_sensitive_escalation  ON sensitive_authorizations(created_at, overall_status)
    WHERE overall_status = 'pending';  -- 用于升级检查

-- =============================================================
-- TABLE: notifications
-- App 内通知（不推送到群）
-- =============================================================

CREATE TABLE notifications (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    recipient_id    VARCHAR(255) NOT NULL, -- ldap_user_id
    type            notification_type NOT NULL,
    title           VARCHAR(500) NOT NULL,
    body            TEXT,
    action_url      VARCHAR(1000),          -- 点击跳转路径
    related_id      UUID,                   -- 关联对象 ID（thread/sensitive/etc）
    related_type    VARCHAR(100),           -- 关联对象类型
    is_read         BOOLEAN      NOT NULL DEFAULT false,
    read_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_recipient ON notifications(recipient_id, is_read, created_at DESC);
CREATE INDEX idx_notifications_unread    ON notifications(recipient_id)
    WHERE is_read = false;

-- =============================================================
-- TABLE: processing_jobs
-- 异步处理任务状态追踪
-- =============================================================

CREATE TABLE processing_jobs (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_type     VARCHAR(100) NOT NULL,
    -- 'classify_message' | 'update_summary' | 'sync_to_chat'
    -- 'send_reminder' | 'import_history'
    status       VARCHAR(50)  NOT NULL DEFAULT 'queued',
    -- 'queued' | 'running' | 'done' | 'failed'
    payload      JSONB        NOT NULL DEFAULT '{}',
    result       JSONB,
    error        TEXT,
    retry_count  INTEGER      NOT NULL DEFAULT 0,
    started_at   TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_jobs_status ON processing_jobs(status)
    WHERE status IN ('queued', 'running');
CREATE INDEX idx_jobs_type   ON processing_jobs(job_type, created_at DESC);

-- =============================================================
-- TABLE: qa_feedback
-- 问答反馈收集
-- =============================================================

CREATE TABLE qa_feedback (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         VARCHAR(255) NOT NULL,  -- ldap_user_id
    question        TEXT NOT NULL,
    answer          TEXT NOT NULL,
    is_helpful      BOOLEAN NOT NULL,
    rating          INTEGER,  -- 1-5 分，可选
    comment         TEXT,
    sources         JSONB NOT NULL DEFAULT '[]',  -- 关联的 thread_id 列表
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_qa_feedback_user ON qa_feedback(user_id, created_at DESC);
CREATE INDEX idx_qa_feedback_helpful ON qa_feedback(is_helpful);
CREATE INDEX idx_qa_feedback_rating ON qa_feedback(rating) WHERE rating IS NOT NULL;

-- =============================================================
-- TABLE: butler_tasks
-- AI 管家任务记录
-- =============================================================

CREATE TABLE butler_tasks (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_type       VARCHAR(100) NOT NULL,
    -- 'weekly_digest' | 'action_item_reminder' | 'health_report'
    -- 'sensitive_status_update' | 'feedback_request'
    status          VARCHAR(50) NOT NULL DEFAULT 'pending',
    -- 'pending' | 'completed' | 'failed'
    permission_level INT NOT NULL DEFAULT 0,    -- 权限层级 0-3
    scheduled_at    TIMESTAMPTZ NOT NULL,
    executed_at     TIMESTAMPTZ,
    target_room_id  UUID REFERENCES chat_rooms(id) ON DELETE SET NULL,
    target_user_ids TEXT[],  -- ldap_user_id[]
    payload         JSONB NOT NULL DEFAULT '{}',
    result          JSONB,
    error           TEXT,
    report_reviewed BOOLEAN NOT NULL DEFAULT FALSE,  -- 汇报是否已审核
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_butler_tasks_type ON butler_tasks(task_type, scheduled_at DESC);
CREATE INDEX idx_butler_tasks_status ON butler_tasks(status)
    WHERE status = 'pending';
CREATE INDEX idx_butler_tasks_scheduled ON butler_tasks(scheduled_at)
    WHERE status = 'pending';

-- =============================================================
-- TABLE: butler_experience
-- AI 管家经验知识库
-- =============================================================

CREATE TABLE butler_experience (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category        VARCHAR(100) NOT NULL,
    -- 'usage_pattern' | 'feedback_insight' | 'optimization_tip'
    key             VARCHAR(255) NOT NULL,
    value           JSONB NOT NULL,
    confidence      FLOAT NOT NULL DEFAULT 1.0,  -- 学习置信度
    sample_count    INTEGER NOT NULL DEFAULT 1,  -- 样本数量
    last_updated    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(category, key)
);

CREATE INDEX idx_butler_experience_category ON butler_experience(category);

-- =============================================================
-- TABLE: butler_proposals
-- AI 管家 L3 权限提案（需管理员审批）
-- =============================================================

CREATE TABLE butler_proposals (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_type       VARCHAR(100) NOT NULL,
    -- 'modify_config' | 'access_sensitive' | 'high_freq_push' | 'custom_script'
    reasoning       TEXT NOT NULL,               -- 发起原因
    expected_impact TEXT NOT NULL,               -- 预期影响
    risk_assessment TEXT,                        -- 风险评估
    payload         JSONB NOT NULL DEFAULT '{}', -- 拟执行内容
    status          VARCHAR(50) NOT NULL DEFAULT 'pending',
    -- 'pending' | 'approved' | 'rejected' | 'executed' | 'cancelled'
    proposed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_by     VARCHAR(255),                -- 审核人 ldap_user_id
    reviewed_at     TIMESTAMPTZ,
    review_comment  TEXT,
    executed_at     TIMESTAMPTZ,
    execution_result JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_butler_proposals_status ON butler_proposals(status)
    WHERE status IN ('pending', 'approved');
CREATE INDEX idx_butler_proposals_proposed ON butler_proposals(proposed_at DESC);

-- =============================================================
-- TABLE: user_contribution_stats
-- 用户贡献统计（物化视图或定期更新）
-- =============================================================

CREATE TABLE user_contribution_stats (
    user_id             VARCHAR(255) PRIMARY KEY,  -- ldap_user_id
    display_name        VARCHAR(255) NOT NULL,

    -- 参与统计
    threads_participated INTEGER NOT NULL DEFAULT 0,
    messages_count       INTEGER NOT NULL DEFAULT 0,

    -- 贡献统计
    summaries_edited     INTEGER NOT NULL DEFAULT 0,
    decisions_made       INTEGER NOT NULL DEFAULT 0,

    -- 问答统计
    questions_asked      INTEGER NOT NULL DEFAULT 0,
    answers_viewed       INTEGER NOT NULL DEFAULT 0,  -- 其问答被查看次数

    -- 反馈统计
    feedback_submitted   INTEGER NOT NULL DEFAULT 0,
    avg_rating_received  FLOAT,  -- 其问答的平均评分

    -- 排名
    weekly_rank          INTEGER,
    monthly_rank         INTEGER,

    last_updated         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_contribution_weekly_rank ON user_contribution_stats(weekly_rank)
    WHERE weekly_rank IS NOT NULL;
CREATE INDEX idx_contribution_monthly_rank ON user_contribution_stats(monthly_rank)
    WHERE monthly_rank IS NOT NULL;

-- =============================================================
-- TABLE: user_subscriptions
-- 用户订阅/关注记录
-- =============================================================

CREATE TABLE user_subscriptions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         VARCHAR(255) NOT NULL,          -- 订阅者 ldap_user_id
    subscription_type VARCHAR(50) NOT NULL,         -- 'user' | 'thread' | 'category' | 'keyword'
    target_id       VARCHAR(255) NOT NULL,          -- 被订阅对象 ID
    -- user: ldap_user_id
    -- thread: thread UUID
    -- category: category code
    -- keyword: 关键词文本
    notification_types TEXT[] NOT NULL DEFAULT ARRAY['in_app'],
    -- 'in_app' | 'email' | 'push' 的组合
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(user_id, subscription_type, target_id)
);

CREATE INDEX idx_subscriptions_user ON user_subscriptions(user_id, is_active);
CREATE INDEX idx_subscriptions_target ON user_subscriptions(subscription_type, target_id, is_active);
CREATE INDEX idx_subscriptions_type ON user_subscriptions(subscription_type);

-- =============================================================
-- TABLE: personal_todos
-- 个人待办事项（可从群聊 action_item 自动生成）
-- =============================================================

CREATE TABLE personal_todos (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         VARCHAR(255) NOT NULL,          -- 责任人 ldap_user_id
    title           VARCHAR(500) NOT NULL,          -- 待办标题
    description     TEXT,                           -- 详细描述
    status          VARCHAR(50) NOT NULL DEFAULT 'pending',
    -- 'pending' | 'in_progress' | 'completed' | 'cancelled' | 'blocked'
    priority        VARCHAR(20) NOT NULL DEFAULT 'medium',
    -- 'low' | 'medium' | 'high' | 'urgent'
    due_date        DATE,                           -- 截止日期
    due_time        TIME,                           -- 截止时间（可选）
    -- 可见性与发布
    visibility      VARCHAR(20) NOT NULL DEFAULT 'private',
    -- 'private' | 'followers' | 'team' | 'public'
    published_at    TIMESTAMPTZ,                    -- 发布时间
    -- 来源追踪
    source_type     VARCHAR(50),                    -- 来源类型
    -- 'manual' | 'group_task' | 'action_item' | 'meeting' | 'import'
    source_id       UUID,                           -- 来源 ID（如 thread_id）
    source_room_id  UUID REFERENCES chat_rooms(id) ON DELETE SET NULL, -- 来源群组
    source_message_id UUID REFERENCES messages(id) ON DELETE SET NULL, -- 来源消息
    -- 任务要素（从群聊提取或管家补充）
    task_elements   JSONB NOT NULL DEFAULT '{}',
    -- {
    --   "resources": ["服务器", "测试环境"],
    --   "dependencies": ["DBA审批"],
    --   "deliverables": ["配置文档", "上线报告"],
    --   "location": "会议室A",
    --   "estimated_hours": 4,
    --   "completion_criteria": "..."
    -- }
    elements_status VARCHAR(20) NOT NULL DEFAULT 'complete',
    -- 'complete' | 'incomplete' | 'needs_confirmation'
    missing_elements TEXT[],                        -- 缺失的要素列表
    -- 标签与分类
    tags            TEXT[] DEFAULT '{}',
    category        VARCHAR(100),                   -- 用户自定义分类
    -- 提醒设置
    reminder_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    reminder_minutes_before INTEGER DEFAULT 30,
    reminded_at     TIMESTAMPTZ,
    -- 完成信息
    completed_at    TIMESTAMPTZ,
    completed_by    VARCHAR(255),                   -- 完成人（可代办）
    completion_note TEXT,                           -- 完成备注
    -- 审计
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_personal_todos_user ON personal_todos(user_id, status, due_date);
CREATE INDEX idx_personal_todos_status ON personal_todos(status) WHERE status IN ('pending', 'in_progress', 'blocked');
CREATE INDEX idx_personal_todos_due ON personal_todos(due_date) WHERE due_date IS NOT NULL AND status NOT IN ('completed', 'cancelled');
CREATE INDEX idx_personal_todos_source ON personal_todos(source_type, source_id) WHERE source_id IS NOT NULL;
CREATE INDEX idx_personal_todos_elements_status ON personal_todos(elements_status) WHERE elements_status = 'needs_confirmation';

-- =============================================================
-- TABLE: todo_participants
-- 任务参与人（多人任务场景）
-- =============================================================

CREATE TABLE todo_participants (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    todo_id         UUID NOT NULL REFERENCES personal_todos(id) ON DELETE CASCADE,
    user_id         VARCHAR(255) NOT NULL,          -- 参与人 ldap_user_id
    role            VARCHAR(20) NOT NULL,           -- 'owner' | 'responsible' | 'consulted' | 'informed'
    -- owner: 任务所有者（通常是责任人）
    -- responsible: 执行者
    -- consulted: 需咨询的人
    -- informed: 需通知的人
    can_edit        BOOLEAN NOT NULL DEFAULT FALSE, -- 是否可编辑
    can_complete    BOOLEAN NOT NULL DEFAULT FALSE, -- 是否可标记完成
    notified        BOOLEAN NOT NULL DEFAULT FALSE, -- 是否已通知
    confirmed_at    TIMESTAMPTZ,                    -- 确认时间
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(todo_id, user_id)
);

CREATE INDEX idx_todo_participants_user ON todo_participants(user_id);
CREATE INDEX idx_todo_participants_todo ON todo_participants(todo_id);

-- =============================================================
-- TABLE: todo_history
-- 待办历史记录（状态变更、编辑等）
-- =============================================================

CREATE TABLE todo_history (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    todo_id         UUID NOT NULL REFERENCES personal_todos(id) ON DELETE CASCADE,
    action          VARCHAR(50) NOT NULL,           -- 'created' | 'updated' | 'status_changed' | 'completed' | 'commented'
    old_value       JSONB,
    new_value       JSONB,
    changed_by      VARCHAR(255) NOT NULL,          -- 操作人
    comment         TEXT,                           -- 备注
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_todo_history_todo ON todo_history(todo_id, created_at DESC);

-- =============================================================
-- TABLE: subscription_events
-- 订阅事件日志（用于通知触发）
-- =============================================================

CREATE TABLE subscription_events (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type      VARCHAR(100) NOT NULL,
    -- 'thread_updated' | 'thread_new_message' | 'user_contribution' | 'category_new_thread'
    actor_id        VARCHAR(255),                   -- 触发事件的用户
    target_type     VARCHAR(50) NOT NULL,           -- 'thread' | 'user' | 'category'
    target_id       VARCHAR(255) NOT NULL,          -- 目标对象 ID
    payload         JSONB NOT NULL DEFAULT '{}',    -- 事件详情
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_subscription_events_target ON subscription_events(target_type, target_id, created_at DESC);
CREATE INDEX idx_subscription_events_type ON subscription_events(event_type, created_at DESC);

-- =============================================================
-- TRIGGERS: updated_at 自动维护
-- =============================================================

CREATE OR REPLACE FUNCTION fn_update_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_chat_users_updated_at
    BEFORE UPDATE ON chat_users
    FOR EACH ROW EXECUTE FUNCTION fn_update_updated_at();

CREATE TRIGGER trg_catdef_updated_at
    BEFORE UPDATE ON category_definitions
    FOR EACH ROW EXECUTE FUNCTION fn_update_updated_at();

CREATE TRIGGER trg_threads_updated_at
    BEFORE UPDATE ON topic_threads
    FOR EACH ROW EXECUTE FUNCTION fn_update_updated_at();

CREATE TRIGGER trg_refdata_updated_at
    BEFORE UPDATE ON reference_data_items
    FOR EACH ROW EXECUTE FUNCTION fn_update_updated_at();

CREATE TRIGGER trg_sensitive_updated_at
    BEFORE UPDATE ON sensitive_authorizations
    FOR EACH ROW EXECUTE FUNCTION fn_update_updated_at();

-- =============================================================
-- TRIGGER: 摘要更新时自动归档历史
-- =============================================================

CREATE OR REPLACE FUNCTION fn_archive_summary_on_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.summary IS DISTINCT FROM NEW.summary THEN
        INSERT INTO thread_summary_history
            (thread_id, version, summary, structured_data, change_reason, changed_by)
        VALUES
            (OLD.id, OLD.summary_version, OLD.summary,
             OLD.structured_data, 'auto_update', NEW.last_modified_by);

        NEW.summary_version = OLD.summary_version + 1;
        NEW.summary_updated_at = NOW();
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_archive_summary
    BEFORE UPDATE ON topic_threads
    FOR EACH ROW EXECUTE FUNCTION fn_archive_summary_on_update();

-- =============================================================
-- TABLE: butler_interaction_logs
-- AI 管家交互日志（用于交互学习）
-- =============================================================

CREATE TABLE butler_interaction_logs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id      UUID,                           -- 会话 ID（可关联多个交互）
    user_id         VARCHAR(255) NOT NULL,          -- 用户 ldap_user_id
    interaction_type VARCHAR(100) NOT NULL,         -- 交互类型
    -- 'query' | 'feedback' | 'preference_change' | 'correction' | 'recommendation_accept' | 'recommendation_reject'
    input           JSONB NOT NULL,                 -- 用户输入
    output          JSONB,                          -- 管家输出
    context         JSONB DEFAULT '{}',             -- 上下文信息
    -- {
    --   "thread_ids": ["uuid1", "uuid2"],
    --   "categories": ["tech_decision"],
    --   "room_id": "uuid"
    -- }
    user_satisfaction INTEGER,                      -- 用户满意度 1-5
    feedback_text   TEXT,                           -- 用户反馈文本
    learned_pattern JSONB,                          -- 学习到的模式
    -- {
    --   "pattern_type": "preference",
    --   "pattern_key": "preferred_reminder_time",
    --   "pattern_value": "morning",
    --   "confidence": 0.85
    -- }
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_butler_interaction_user ON butler_interaction_logs(user_id, created_at DESC);
CREATE INDEX idx_butler_interaction_type ON butler_interaction_logs(interaction_type);
CREATE INDEX idx_butler_interaction_session ON butler_interaction_logs(session_id);
CREATE INDEX idx_butler_interaction_satisfaction ON butler_interaction_logs(user_satisfaction) WHERE user_satisfaction IS NOT NULL;

-- =============================================================
-- TABLE: butler_reflections
-- AI 管家自省记录
-- =============================================================

CREATE TABLE butler_reflections (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reflection_type VARCHAR(50) NOT NULL,           -- 'daily' | 'weekly' | 'monthly'
    period_start    DATE NOT NULL,
    period_end      DATE NOT NULL,
    summary         JSONB NOT NULL,                 -- 自省摘要
    -- {
    --   "tasks_executed": 45,
    --   "success_rate": 0.92,
    --   "user_satisfaction": 4.3,
    --   "top_performed_duties": ["reminder", "digest"],
    --   "under_performed_duties": ["recommendation"]
    -- }
    patterns        JSONB DEFAULT '[]',             -- 发现的模式
    -- [
    --   {"pattern": "技术决策通知打开率更高", "confidence": 0.85, "sample_size": 120}
    -- ]
    optimizations   JSONB DEFAULT '[]',             -- 优化建议
    -- [
    --   {"target": "duties/reminder.yaml", "change": "增加用户偏好检查", "reason": "减少投诉"}
    -- ]
    lessons_learned JSONB DEFAULT '[]',             -- 经验教训
    -- [
    --   {"lesson": "周末提醒打扰较多", "action": "建议增加免打扰设置", "priority": "medium"}
    -- ]
    prompt_updates  JSONB DEFAULT '[]',             -- 提示词更新记录
    -- [
    --   {"file": "skills/task_extraction.md", "version_before": "1.0", "version_after": "1.1", "reason": "提升任务识别准确率"}
    -- ]
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(reflection_type, period_start, period_end)
);

CREATE INDEX idx_butler_reflections_type ON butler_reflections(reflection_type, period_start DESC);

-- =============================================================
-- TABLE: butler_action_logs
-- AI 管家操作审计日志（L1-L2 权限操作）
-- =============================================================

CREATE TABLE butler_action_logs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id         UUID REFERENCES butler_tasks(id) ON DELETE SET NULL,
    permission_level INT NOT NULL,                  -- 0-3，对应 L0-L3
    action_type     VARCHAR(100) NOT NULL,          -- 操作类型
    -- 'send_notification' | 'create_todo' | 'update_summary' | 'send_digest' | ...
    target_type     VARCHAR(50),                    -- 目标类型
    -- 'thread' | 'user' | 'room' | 'todo' | 'notification'
    target_id       VARCHAR(255),                   -- 目标 ID
    payload         JSONB NOT NULL DEFAULT '{}',    -- 操作参数
    result          JSONB,                          -- 执行结果
    -- {"success": true, "affected_count": 5, "details": "..."}
    error_message   TEXT,                           -- 错误信息（失败时）
    duration_ms     INTEGER,                        -- 执行耗时（毫秒）
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_butler_action_task ON butler_action_logs(task_id);
CREATE INDEX idx_butler_action_type ON butler_action_logs(action_type, created_at DESC);
CREATE INDEX idx_butler_action_target ON butler_action_logs(target_type, target_id) WHERE target_type IS NOT NULL;

-- =============================================================
-- VIEW: v_pending_sensitive
-- 管理员用：查看所有待处理敏感条目
-- =============================================================

CREATE OR REPLACE VIEW v_pending_sensitive AS
SELECT
    sa.id,
    sa.message_id,
    m.content,
    m.sent_at,
    cr.room_name,
    sa.sensitive_types,
    sa.sensitive_summary,
    sa.decisions,
    sa.reminder_count,
    sa.created_at,
    EXTRACT(EPOCH FROM (NOW() - sa.created_at)) / 86400 AS days_pending
FROM sensitive_authorizations sa
JOIN messages m ON m.id = sa.message_id
LEFT JOIN chat_rooms cr ON cr.id = m.room_id
WHERE sa.overall_status = 'pending'
ORDER BY sa.created_at;

-- =============================================================
-- VIEW: v_open_action_items
-- 未完成的任务待办
-- =============================================================

CREATE OR REPLACE VIEW v_open_action_items AS
SELECT
    t.id AS thread_id,
    t.title,
    t.structured_data->>'task'       AS task,
    t.structured_data->>'assignee'   AS assignee,
    t.structured_data->>'due_date'   AS due_date,
    t.structured_data->>'priority'   AS priority,
    t.last_message_at,
    t.primary_room_id
FROM topic_threads t
WHERE t.category = 'action_item'
  AND t.status = 'active'
  AND (t.structured_data->>'status') IN ('open', 'in_progress')
ORDER BY t.structured_data->>'priority' DESC, t.last_message_at;

-- =============================================================
-- SECTION 15: 全局索引表
-- 团队活动全景视图索引
-- =============================================================

CREATE TABLE global_activity_index (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    activity_type   VARCHAR(50) NOT NULL,   -- thread | task | decision | reference
    activity_id     UUID NOT NULL,          -- 关联的话题/待办/决策ID
    title           VARCHAR(500),
    summary         TEXT,
    category        VARCHAR(50),
    importance      INTEGER DEFAULT 0,       -- 重要性评分 0-100
    participants    JSONB DEFAULT '[]',      -- 参与者列表 [{user_id, display_name}]
    keywords        JSONB DEFAULT '[]',      -- 关键词
    occurred_at     TIMESTAMPTZ NOT NULL,
    room_id         VARCHAR(100),
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_global_activity_time ON global_activity_index(occurred_at DESC);
CREATE INDEX idx_global_activity_type ON global_activity_index(activity_type);
CREATE INDEX idx_global_activity_importance ON global_activity_index(importance DESC);
CREATE INDEX idx_global_activity_keywords ON global_activity_index USING GIN(keywords);
CREATE INDEX idx_global_activity_room ON global_activity_index(room_id);

COMMENT ON TABLE global_activity_index IS '全局索引：团队活动全景视图';

-- =============================================================
-- SECTION 16: 知识图谱表（Schemaless）
-- 尽力而为的知识索引
-- =============================================================

CREATE TABLE knowledge_nodes (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    node_type       VARCHAR(50) NOT NULL,   -- person | team | topic | event | thing
    node_key        VARCHAR(500) NOT NULL,  -- 唯一标识
    display_name    VARCHAR(500),           -- 显示名称
    attributes      JSONB DEFAULT '{}',     -- 任意属性
    source_count    INTEGER DEFAULT 0,      -- 来源证据数量
    confidence      FLOAT DEFAULT 0.5,      -- 置信度
    first_seen_at   TIMESTAMPTZ NOT NULL,
    last_seen_at    TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(node_type, node_key)
);

CREATE TABLE knowledge_edges (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    source_id       UUID NOT NULL REFERENCES knowledge_nodes(id) ON DELETE CASCADE,
    target_id       UUID NOT NULL REFERENCES knowledge_nodes(id) ON DELETE CASCADE,
    edge_type       VARCHAR(100) NOT NULL,  -- 关系类型（动态）
    attributes      JSONB DEFAULT '{}',     -- 关系属性
    evidence        JSONB DEFAULT '[]',     -- 证据来源 [{thread_id, message_id, text}]
    weight          FLOAT DEFAULT 1.0,      -- 关系强度
    confidence      FLOAT DEFAULT 0.5,      -- 置信度
    first_seen_at   TIMESTAMPTZ NOT NULL,
    last_seen_at    TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(source_id, target_id, edge_type)
);

CREATE INDEX idx_node_type ON knowledge_nodes(node_type);
CREATE INDEX idx_node_key ON knowledge_nodes(node_key);
CREATE INDEX idx_node_attrs ON knowledge_nodes USING GIN(attributes);
CREATE INDEX idx_node_search ON knowledge_nodes
    USING GIN(to_tsvector('simple', coalesce(display_name, '') || ' ' || coalesce(node_key, '')));

CREATE INDEX idx_edge_source ON knowledge_edges(source_id);
CREATE INDEX idx_edge_target ON knowledge_edges(target_id);
CREATE INDEX idx_edge_type ON knowledge_edges(edge_type);
CREATE INDEX idx_edge_attrs ON knowledge_edges USING GIN(attributes);

COMMENT ON TABLE knowledge_nodes IS '知识图谱节点：Schemaless 实体存储';
COMMENT ON TABLE knowledge_edges IS '知识图谱边：Schemaless 关系存储';

-- =============================================================
-- SECTION 17: 用户行为分析表
-- =============================================================

CREATE TABLE user_behavior_logs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         VARCHAR(255) NOT NULL,
    behavior_type   VARCHAR(100) NOT NULL,  -- search | view | create | complete | subscribe
    target_type     VARCHAR(100),           -- thread | todo | reference
    target_id       UUID,
    context         JSONB DEFAULT '{}',
    session_id      UUID,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE user_behavior_patterns (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         VARCHAR(255) NOT NULL UNIQUE,
    active_hours    JSONB DEFAULT '{}',     -- {"9": 15, "10": 32, ...}
    search_patterns JSONB DEFAULT '{}',     -- {"tech": 20, "faq": 15}
    topic_interests JSONB DEFAULT '{}',     -- {"Redis": 10, "支付": 8}
    avg_response_time_hours FLOAT,
    completion_rate FLOAT DEFAULT 0,
    contribution_score INTEGER DEFAULT 0,
    last_updated    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_behavior_user ON user_behavior_logs(user_id, created_at DESC);
CREATE INDEX idx_behavior_type ON user_behavior_logs(behavior_type);
CREATE INDEX idx_behavior_session ON user_behavior_logs(session_id);

COMMENT ON TABLE user_behavior_logs IS '用户行为日志';
COMMENT ON TABLE user_behavior_patterns IS '用户行为模式聚合';

-- =============================================================
-- SECTION 18: 热点分析表
-- =============================================================

CREATE TABLE topic_heat_scores (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    thread_id       UUID NOT NULL REFERENCES topic_threads(id) ON DELETE CASCADE,
    score_date      DATE NOT NULL,

    -- 热度因子
    message_count   INTEGER DEFAULT 0,
    participant_count INTEGER DEFAULT 0,
    mention_count   INTEGER DEFAULT 0,
    view_count      INTEGER DEFAULT 0,
    action_count    INTEGER DEFAULT 0,
    recency_score   FLOAT DEFAULT 0,
    importance_score FLOAT DEFAULT 0,

    -- 综合热度
    heat_score      FLOAT DEFAULT 0,
    heat_rank       INTEGER,

    calculated_at   TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(thread_id, score_date)
);

CREATE TABLE user_activity_stats (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         VARCHAR(255) NOT NULL UNIQUE,

    -- 活跃度指标
    messages_count      INTEGER DEFAULT 0,
    threads_created     INTEGER DEFAULT 0,
    threads_participated INTEGER DEFAULT 0,
    decisions_made      INTEGER DEFAULT 0,
    questions_asked     INTEGER DEFAULT 0,
    questions_answered  INTEGER DEFAULT 0,

    -- 贡献度指标
    todos_created       INTEGER DEFAULT 0,
    todos_completed     INTEGER DEFAULT 0,
    references_added    INTEGER DEFAULT 0,
    summaries_edited    INTEGER DEFAULT 0,
    feedback_given      INTEGER DEFAULT 0,

    -- 质量指标
    avg_response_time   FLOAT,
    completion_rate     FLOAT DEFAULT 0,
    helpful_rate        FLOAT,

    -- 综合分数
    activity_score      INTEGER DEFAULT 0,
    contribution_score  INTEGER DEFAULT 0,

    -- 时间维度
    period_start        DATE,
    period_end          DATE,
    last_updated        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_heat_score ON topic_heat_scores(score_date, heat_score DESC);
CREATE INDEX idx_heat_thread ON topic_heat_scores(thread_id);
CREATE INDEX idx_user_activity_score ON user_activity_stats(activity_score DESC);
CREATE INDEX idx_user_contrib_score ON user_activity_stats(contribution_score DESC);

COMMENT ON TABLE topic_heat_scores IS '话题热度评分（每日计算）';
COMMENT ON TABLE user_activity_stats IS '用户活跃度与贡献度统计';

-- =============================================================
-- SECTION 19: 话题状态视图
-- =============================================================

CREATE OR REPLACE VIEW topic_status_view AS
SELECT
    t.id,
    t.title,
    t.category,
    t.last_message_at,
    t.stakeholder_ids,

    -- 判断状态
    CASE
        -- 进行中：最近7天有消息
        WHEN t.last_message_at > NOW() - INTERVAL '7 days' THEN 'active'
        -- 有未完成待办
        WHEN EXISTS (
            SELECT 1 FROM action_items a
            WHERE a.thread_id = t.id AND a.status != 'done'
        ) THEN 'active'

        -- 待关注：7-30天无消息
        WHEN t.last_message_at BETWEEN NOW() - INTERVAL '30 days' AND NOW() - INTERVAL '7 days' THEN 'needs_attention'
        -- 敏感授权待处理
        WHEN EXISTS (
            SELECT 1 FROM sensitive_authorizations s
            WHERE s.message_id IN (
                SELECT m.id FROM messages m
                WHERE m.thread_id = t.id
            ) AND s.overall_status = 'pending'
        ) THEN 'needs_attention'

        -- 未闭环：问答无确认答案
        WHEN t.category = 'qa_faq' AND NOT EXISTS (
            SELECT 1 FROM thread_modifications m
            WHERE m.thread_id = t.id AND m.modification_type = 'answer_confirmed'
        ) THEN 'open_loop'
        -- 决策后有待办未完成
        WHEN t.category = 'tech_decision' AND EXISTS (
            SELECT 1 FROM action_items a
            WHERE a.thread_id = t.id AND a.status != 'done'
        ) THEN 'open_loop'

        -- 已结束
        ELSE 'closed'
    END AS status,

    -- 未闭环原因
    CASE
        WHEN t.category = 'qa_faq' AND NOT EXISTS (
            SELECT 1 FROM thread_modifications m
            WHERE m.thread_id = t.id AND m.modification_type = 'answer_confirmed'
        ) THEN 'pending_answer'
        WHEN t.category = 'tech_decision' AND EXISTS (
            SELECT 1 FROM action_items a
            WHERE a.thread_id = t.id AND a.status != 'done'
        ) THEN 'pending_action'
        ELSE NULL
    END AS open_loop_reason

FROM topic_threads t;

COMMENT ON VIEW topic_status_view IS '话题状态视图：active/needs_attention/open_loop/closed';

-- =============================================================
-- SECTION 20: 瓶颈记录表
-- =============================================================

CREATE TABLE bottleneck_records (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    thread_id       UUID REFERENCES topic_threads(id),

    bottleneck_type VARCHAR(50) NOT NULL,  -- todo_overdue | resource_missing | person_blocked | stale_progress | sensitive_pending | qa_unanswered
    severity        VARCHAR(20) NOT NULL,  -- high | medium | low
    description     TEXT NOT NULL,

    blocked_items   JSONB DEFAULT '[]',    -- 被阻塞的项目ID列表 [{id, type, title}]
    impact_scope    JSONB DEFAULT '{}',    -- 影响范围 {affected_users, affected_todos}

    suggested_action TEXT,                 -- 建议行动
    assigned_to     VARCHAR(255),          -- 分配给谁处理
    resolved_at     TIMESTAMPTZ,           -- 解决时间
    resolution      TEXT,                  -- 解决说明

    first_detected  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_updated    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_bottleneck_thread ON bottleneck_records(thread_id);
CREATE INDEX idx_bottleneck_type ON bottleneck_records(bottleneck_type);
CREATE INDEX idx_bottleneck_severity ON bottleneck_records(severity);
CREATE INDEX idx_bottleneck_unresolved ON bottleneck_records(severity, first_detected) WHERE resolved_at IS NULL;

COMMENT ON TABLE bottleneck_records IS '瓶颈记录：自动识别和跟踪系统中的阻塞点';

-- =============================================================
-- SECTION 21: 支持关系表
-- =============================================================

CREATE TABLE support_relations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    thread_id       UUID REFERENCES topic_threads(id),

    supporter_id    VARCHAR(255) NOT NULL,  -- 提供支持的人
    supported_id    VARCHAR(255),           -- 被支持的人（可选）
    support_type    VARCHAR(100),           -- 技术 | 资源 | 人力 | 决策
    support_context TEXT,                   -- 支持内容描述

    status          VARCHAR(50) DEFAULT 'pending', -- pending | fulfilled | blocked
    fulfilled_at    TIMESTAMPTZ,

    evidence_text   TEXT,                   -- 原始消息文本
    message_id      UUID REFERENCES messages(id),

    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_support_thread ON support_relations(thread_id);
CREATE INDEX idx_support_supporter ON support_relations(supporter_id);
CREATE INDEX idx_support_supported ON support_relations(supported_id);
CREATE INDEX idx_support_status ON support_relations(status);
CREATE INDEX idx_support_type ON support_relations(support_type);

COMMENT ON TABLE support_relations IS '支持关系：记录人与人之间的协作支持关系';

-- =============================================================
-- SECTION 22: Routine 脚本版本历史
-- =============================================================

CREATE TABLE routine_versions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    routine_id      VARCHAR(100) NOT NULL,  -- routine 标识
    version         INTEGER NOT NULL DEFAULT 1,
    script_path     VARCHAR(500) NOT NULL,  -- 脚本文件路径
    script_content  TEXT NOT NULL,          -- 脚本内容快照
    change_summary  TEXT,                   -- 变更说明
    changed_by      VARCHAR(255),           -- 修改者（可以是管家）
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(routine_id, version)
);

CREATE INDEX idx_routine_versions ON routine_versions(routine_id, version DESC);

COMMENT ON TABLE routine_versions IS 'Routine脚本版本历史：记录所有routine的变更历史';

-- =============================================================
-- SECTION 23: 管家工具调用日志
-- =============================================================

CREATE TABLE butler_tool_calls (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id      UUID,                   -- 会话ID
    routine_id      VARCHAR(100),           -- 触发的 routine（如有）

    tool_name       VARCHAR(100) NOT NULL,  -- 工具名称
    tool_input      JSONB NOT NULL,         -- 输入参数
    tool_output     JSONB,                  -- 输出结果
    success         BOOLEAN DEFAULT true,
    error_message   TEXT,                   -- 错误信息（如有）

    duration_ms     INTEGER,                -- 执行耗时
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_tool_session ON butler_tool_calls(session_id);
CREATE INDEX idx_tool_routine ON butler_tool_calls(routine_id);
CREATE INDEX idx_tool_name ON butler_tool_calls(tool_name, created_at DESC);
CREATE INDEX idx_tool_failed ON butler_tool_calls(tool_name) WHERE success = false;

COMMENT ON TABLE butler_tool_calls IS '管家工具调用日志：记录Agent所有工具调用';

-- =============================================================
-- SECTION 24: 多平台适配器表
-- =============================================================

-- 平台群组映射表
CREATE TABLE platform_rooms (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    platform        VARCHAR(50) NOT NULL,   -- wechat | feishu | dingtalk | custom
    platform_room_id VARCHAR(255) NOT NULL,
    room_id         UUID REFERENCES chat_rooms(id),

    room_name       VARCHAR(500),
    room_type       VARCHAR(50),            -- group | private

    -- 同步状态
    sync_enabled    BOOLEAN DEFAULT true,
    last_sync_at    TIMESTAMPTZ,
    last_message_id VARCHAR(500),

    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(platform, platform_room_id)
);

-- 平台用户映射表
CREATE TABLE platform_users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    platform        VARCHAR(50) NOT NULL,
    platform_user_id VARCHAR(255) NOT NULL,
    user_id         UUID REFERENCES chat_users(id),

    display_name    VARCHAR(500),
    avatar_url      VARCHAR(1000),

    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(platform, platform_user_id)
);

CREATE INDEX idx_platform_rooms ON platform_rooms(platform, platform_room_id);
CREATE INDEX idx_platform_rooms_sync ON platform_rooms(platform, sync_enabled) WHERE sync_enabled = true;
CREATE INDEX idx_platform_users ON platform_users(platform, platform_user_id);

COMMENT ON TABLE platform_rooms IS '平台群组映射：多平台群组与系统群组的对应关系';
COMMENT ON TABLE platform_users IS '平台用户映射：多平台用户与系统用户的对应关系';

-- =============================================================
-- SECTION 25: 批量导入表
-- =============================================================

-- 导入任务表
CREATE TABLE import_jobs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    platform        VARCHAR(50) NOT NULL,   -- wechat | feishu | dingtalk | custom
    room_id         VARCHAR(255) NOT NULL,  -- 目标群组ID

    -- 文件信息
    file_name       VARCHAR(500),
    file_path       VARCHAR(1000),
    file_size       BIGINT,
    file_format     VARCHAR(50),            -- wechat_txt | json | csv | ...

    -- 进度信息
    total_count     INTEGER DEFAULT 0,
    processed_count INTEGER DEFAULT 0,
    failed_count    INTEGER DEFAULT 0,
    skipped_count   INTEGER DEFAULT 0,

    -- 状态
    status          VARCHAR(50) DEFAULT 'pending',  -- pending | parsing | processing | completed | failed | cancelled

    -- 时间范围
    time_range_start TIMESTAMPTZ,
    time_range_end   TIMESTAMPTZ,

    -- 导入选项
    options         JSONB DEFAULT '{}',
    -- {
    --   "time_scale": 1.0,        -- 时间加速因子
    --   "skip_noise": true,       -- 跳过噪声消息
    --   "batch_size": 100,        -- 批处理大小
    --   "reprocess": false        -- 是否重新处理已存在的消息
    -- }

    -- 结果统计
    result_summary  JSONB DEFAULT '{}',
    -- {
    --   "threads_created": 15,
    --   "threads_updated": 8,
    --   "action_items_created": 5,
    --   "decisions_created": 3,
    --   "errors": [...]
    -- }

    -- 时间信息
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    created_by      VARCHAR(255) NOT NULL
);

-- 导入消息记录表
CREATE TABLE import_message_logs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id          UUID NOT NULL REFERENCES import_jobs(id) ON DELETE CASCADE,

    -- 消息信息
    platform_message_id VARCHAR(500),
    sender_id       VARCHAR(255),
    sender_name     VARCHAR(255),
    content_preview TEXT,
    sent_at         TIMESTAMPTZ,

    -- 处理结果
    status          VARCHAR(50) NOT NULL,  -- pending | processed | skipped | failed
    message_id      UUID REFERENCES messages(id),
    thread_id       UUID REFERENCES topic_threads(id),
    error_message   TEXT,

    processed_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_import_status ON import_jobs(status, created_at DESC);
CREATE INDEX idx_import_room ON import_jobs(room_id);
CREATE INDEX idx_import_platform ON import_jobs(platform);
CREATE INDEX idx_import_msg_job ON import_message_logs(job_id, status);
CREATE INDEX idx_import_msg_status ON import_message_logs(status);

COMMENT ON TABLE import_jobs IS '批量导入任务：跟踪导入进度和结果';
COMMENT ON TABLE import_message_logs IS '导入消息记录：追踪每条消息的导入状态';

-- =============================================================
-- SECTION 13: 微信同步状态
-- =============================================================

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

COMMENT ON TABLE wechat_sync_status IS '微信同步状态：追踪每个群的同步进度和状态';

-- 为消息表添加内容哈希字段（用于去重）
ALTER TABLE messages ADD COLUMN IF NOT EXISTS content_hash VARCHAR(64);
CREATE INDEX IF NOT EXISTS idx_messages_content_hash ON messages(room_id, content_hash);

COMMENT ON COLUMN messages.content_hash IS '消息内容哈希（SHA256），用于增量导入去重';

-- =============================================================
-- SECTION 14: 四大类信息分类架构
-- =============================================================

-- 四大类定义表（顶层分类）
CREATE TABLE info_domains (
    code            VARCHAR(50) PRIMARY KEY,
    display_name    VARCHAR(100) NOT NULL,
    description     TEXT,
    icon            VARCHAR(50),
    color           VARCHAR(20),
    sort_order      INTEGER
);

INSERT INTO info_domains VALUES
('knowledge', '知识库', 'FAQ、经验总结、术语规则、外部资源', 'book', 'blue', 1),
('action', '任务与待办', '显性任务、隐性承诺、多步骤事项', 'check-circle', 'green', 2),
('event', '事件与线索', '项目里程碑、问题处理全过程、决策过程', 'git-branch', 'purple', 3),
('collaboration', '协作网络', '沟通关系、任务关系、知识关系', 'users', 'orange', 4);

COMMENT ON TABLE info_domains IS '四大类信息域：系统顶层分类标准';

-- 为 category_definitions 添加 domain 映射
ALTER TABLE category_definitions ADD COLUMN IF NOT EXISTS info_domain VARCHAR(50) REFERENCES info_domains(code);

UPDATE category_definitions SET info_domain = 'knowledge'
WHERE code IN ('qa_faq', 'knowledge_share', 'reference_data', 'env_config');

UPDATE category_definitions SET info_domain = 'action'
WHERE code = 'action_item';

UPDATE category_definitions SET info_domain = 'event'
WHERE code IN ('tech_decision', 'bug_incident', 'project_update', 'discussion_notes');

-- 为 topic_threads 添加 info_domain 字段
ALTER TABLE topic_threads ADD COLUMN IF NOT EXISTS info_domain VARCHAR(50) REFERENCES info_domains(code);

-- 触发器：自动根据 category 设置 info_domain
CREATE OR REPLACE FUNCTION fn_set_info_domain()
RETURNS TRIGGER AS $$
BEGIN
    NEW.info_domain := (SELECT info_domain FROM category_definitions WHERE code = NEW.category);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_set_info_domain
    BEFORE INSERT ON topic_threads
    FOR EACH ROW
    EXECUTE FUNCTION fn_set_info_domain();

-- 更新现有数据的 info_domain
UPDATE topic_threads t SET info_domain = cd.info_domain
FROM category_definitions cd
WHERE t.category = cd.code AND t.info_domain IS NULL;

CREATE INDEX idx_threads_info_domain ON topic_threads(info_domain);

-- =============================================================
-- SECTION 15: 任务待办增强
-- =============================================================

-- action_items 表增强
ALTER TABLE action_items ADD COLUMN IF NOT EXISTS source_type VARCHAR(50) DEFAULT 'explicit';
-- explicit: 显性任务 | implicit: 隐性承诺 | multi_step: 多步骤拆解

ALTER TABLE action_items ADD COLUMN IF NOT EXISTS commitment_status VARCHAR(50);
-- identified: 已识别待确认 | confirmed: 已确认 | dismissed: 已忽略

COMMENT ON COLUMN action_items.source_type IS '任务来源类型：explicit显性|implicit隐性承诺|multi_step多步骤';
COMMENT ON COLUMN action_items.commitment_status IS '隐性承诺状态：identified待确认|confirmed已确认|dismissed已忽略';

-- 完成信号检测配置表
CREATE TABLE completion_signals (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    signal_text     VARCHAR(100) NOT NULL UNIQUE,
    signal_type     VARCHAR(50) NOT NULL,  -- exact | pattern | emoji
    confidence      FLOAT DEFAULT 1.0,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO completion_signals (signal_text, signal_type, confidence) VALUES
('已完成', 'exact', 1.0),
('搞定了', 'exact', 1.0),
('done', 'exact', 1.0),
('✅', 'emoji', 0.9),
('完成了', 'exact', 1.0),
('解决了', 'exact', 0.9),
('OK', 'exact', 0.7),
('好的', 'exact', 0.6);

COMMENT ON TABLE completion_signals IS '完成信号配置：用于自动检测任务完成';

-- 隐性承诺识别模式配置表
CREATE TABLE implicit_commitment_patterns (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pattern_regex   VARCHAR(500) NOT NULL,
    description     TEXT,
    confidence      FLOAT DEFAULT 0.8,
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO implicit_commitment_patterns (pattern_regex, description, confidence) VALUES
('我(回头|之后|明天|下周|尽快)', '自我承诺模式', 0.8),
('(我|咱们)(需要|得|应该|要)', '需求表达模式', 0.7),
('(记|写)一下', '记录意图模式', 0.6),
('.*(前|之前).*(给|发|提交|完成)', '时间承诺模式', 0.9),
('(计划|准备|打算)', '计划表达模式', 0.7);

COMMENT ON TABLE implicit_commitment_patterns IS '隐性承诺识别模式：用于从聊天中识别隐含的承诺';

-- =============================================================
-- SECTION 16: 状态变迁追踪
-- =============================================================

-- 线索状态变迁表
CREATE TABLE thread_state_transitions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    thread_id       UUID NOT NULL REFERENCES topic_threads(id) ON DELETE CASCADE,
    from_status     VARCHAR(50),
    to_status       VARCHAR(50) NOT NULL,
    triggered_by    VARCHAR(255),           -- 触发者 ldap_user_id
    trigger_message_id UUID REFERENCES messages(id),
    transition_type VARCHAR(50),            -- manual | auto_detected | timeout | signal_detected
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_thread_transitions ON thread_state_transitions(thread_id, created_at);
CREATE INDEX idx_transitions_by_user ON thread_state_transitions(triggered_by);

COMMENT ON TABLE thread_state_transitions IS '线索状态变迁：记录话题线索的完整生命周期';

-- =============================================================
-- SECTION 17: 协作网络
-- =============================================================

-- 协作关系表
CREATE TABLE collaboration_relations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    relation_type   VARCHAR(50) NOT NULL,
    -- communication: frequent_collaborators, information_bridge, knowledge_expert
    -- task_based: task_assigner, task_executor, reviewer
    -- knowledge_based: knowledge_contributor, question_asker, answer_provider
    user_id_a       VARCHAR(255) NOT NULL,  -- 源用户 ldap_user_id
    user_id_b       VARCHAR(255) NOT NULL,  -- 目标用户 ldap_user_id
    weight          FLOAT DEFAULT 1.0,
    thread_id       UUID REFERENCES topic_threads(id),
    room_id         UUID REFERENCES chat_rooms(id),
    period_start    TIMESTAMPTZ,
    period_end      TIMESTAMPTZ,
    interaction_count INTEGER DEFAULT 1,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(relation_type, user_id_a, user_id_b, period_start)
);

CREATE INDEX idx_collab_users ON collaboration_relations(user_id_a, user_id_b);
CREATE INDEX idx_collab_type ON collaboration_relations(relation_type);
CREATE INDEX idx_collab_room ON collaboration_relations(room_id);
CREATE INDEX idx_collab_thread ON collaboration_relations(thread_id);

COMMENT ON TABLE collaboration_relations IS '协作关系：人与人之间的沟通、任务、知识关系网络';

-- 关系权重配置
CREATE TABLE relation_weights (
    interaction_type    VARCHAR(100) PRIMARY KEY,
    weight              FLOAT NOT NULL,
    description         TEXT
);

INSERT INTO relation_weights VALUES
('@mention', 3.0, '@提及'),
('reply', 2.0, '回复消息'),
('same_thread', 1.5, '共同参与话题'),
('same_time', 0.5, '同时在线');

COMMENT ON TABLE relation_weights IS '关系权重配置：用于计算协作关系强度';

-- 用户协作统计视图
CREATE VIEW user_collaboration_stats AS
SELECT
    user_id_a,
    user_id_b,
    relation_type,
    SUM(interaction_count) AS total_interactions,
    SUM(weight) AS total_weight,
    COUNT(DISTINCT thread_id) AS shared_threads,
    COUNT(DISTINCT room_id) AS shared_rooms
FROM collaboration_relations
GROUP BY user_id_a, user_id_b, relation_type;

COMMENT ON VIEW user_collaboration_stats IS '用户协作统计：汇总用户间的协作关系';

-- =============================================================
-- SECTION 18: 文件系统分级索引与存储
-- =============================================================

-- 文件索引表
CREATE TABLE file_index (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    thread_id       UUID REFERENCES topic_threads(id) ON DELETE CASCADE,

    -- 文件路径
    file_path       VARCHAR(1000) NOT NULL UNIQUE,
    file_name       VARCHAR(500) NOT NULL,

    -- 层级
    layer           VARCHAR(20) NOT NULL,  -- L1 | L2 | L3

    -- 文件类型
    file_type       VARCHAR(50) NOT NULL,  -- thread | summary | original | graph | index

    -- 文件状态
    status          VARCHAR(50) DEFAULT 'active',  -- active | archived | compacted

    -- 存储信息
    file_size       BIGINT,                 -- 原始文件大小
    compressed_size BIGINT,                 -- 压缩后大小
    checksum        VARCHAR(128),           -- 文件校验和

    -- 时间信息
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    last_access_at  TIMESTAMPTZ DEFAULT NOW(),
    compacted_at    TIMESTAMPTZ,

    -- 元数据
    metadata        JSONB DEFAULT '{}'
);

CREATE INDEX idx_file_thread ON file_index(thread_id);
CREATE INDEX idx_file_layer ON file_index(layer);
CREATE INDEX idx_file_type ON file_index(file_type);
CREATE INDEX idx_file_status ON file_index(status);

COMMENT ON TABLE file_index IS '文件索引：追踪知识库文件的位置和状态';

-- Compact 任务表
CREATE TABLE compact_jobs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- 任务类型
    compact_type    VARCHAR(50) NOT NULL,  -- L1_to_L2 | L2_to_L3

    -- 关联话题
    thread_ids      UUID[] NOT NULL,

    -- 任务状态
    status          VARCHAR(50) DEFAULT 'pending',  -- pending | processing | completed | failed

    -- 处理结果
    total_count     INTEGER DEFAULT 0,
    processed_count INTEGER DEFAULT 0,
    failed_count    INTEGER DEFAULT 0,

    -- 结果详情
    result          JSONB DEFAULT '{}',

    -- 时间信息
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    created_by      VARCHAR(255)
);

CREATE INDEX idx_compact_status ON compact_jobs(status, created_at DESC);
CREATE INDEX idx_compact_type ON compact_jobs(compact_type);

COMMENT ON TABLE compact_jobs IS '压缩任务：追踪信息降级和摘要生成任务';

-- Compact 配置表
CREATE TABLE compact_config (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- 配置名称
    name            VARCHAR(100) NOT NULL UNIQUE,

    -- 触发条件
    trigger_condition JSONB NOT NULL,
    -- {
    --   "field": "last_message_at",
    --   "operator": ">",
    --   "value": "30 days"
    -- }

    -- 执行动作
    actions         JSONB NOT NULL,
    -- [
    --   {"name": "generate_summary", "enabled": true},
    --   {"name": "compress_original", "enabled": true}
    -- ]

    -- 调度
    schedule        VARCHAR(100),  -- cron 表达式

    -- 状态
    is_active       BOOLEAN DEFAULT true,

    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO compact_config (name, trigger_condition, actions, schedule) VALUES
('L1_to_L2',
 '{"field": "last_message_at", "operator": ">", "value": "30 days"}',
 '[{"name": "generate_summary"}, {"name": "compress_original"}, {"name": "update_index"}]',
 '0 2 * * *'),

('L2_to_L3',
 '{"field": "last_access_at", "operator": ">", "value": "180 days"}',
 '[{"name": "extract_entities"}, {"name": "update_decision_log"}]',
 '0 3 * * 0');

COMMENT ON TABLE compact_config IS '压缩配置：定义信息降级规则';

-- 文件访问日志表
CREATE TABLE file_access_logs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    file_id         UUID REFERENCES file_index(id) ON DELETE SET NULL,

    -- 访问者
    accessed_by     VARCHAR(255),           -- ldap_user_id 或 'system'

    -- 访问方式
    access_type     VARCHAR(50) NOT NULL,  -- read | query | compact

    -- 访问上下文
    context         JSONB DEFAULT '{}',

    accessed_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_file_access_file ON file_access_logs(file_id);
CREATE INDEX idx_file_access_time ON file_access_logs(accessed_at DESC);

COMMENT ON TABLE file_access_logs IS '文件访问日志：记录文件访问行为，用于访问频率统计';

-- =============================================================
-- FAQ 知识库系统（群聊知识沉淀）
-- =============================================================

-- FAQ 文档元数据（每群一份）
CREATE TABLE faq_documents (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id        VARCHAR(255) NOT NULL UNIQUE,   -- chat_rooms.room_id
    version         INTEGER DEFAULT 0,               -- 更新版本号
    qa_count        INTEGER DEFAULT 0,               -- 已确认的 FAQ 条目数
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE faq_documents IS 'FAQ 文档元数据：每个群聊对应一份，由 nullclaw 维护';

-- FAQ 章节（动态维护，由 nullclaw 自动调整结构）
CREATE TABLE faq_sections (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    doc_id          UUID NOT NULL REFERENCES faq_documents(id) ON DELETE CASCADE,
    parent_id       UUID REFERENCES faq_sections(id) ON DELETE CASCADE,
    title           VARCHAR(200) NOT NULL,
    sort_order      INTEGER DEFAULT 0,
    created_by      VARCHAR(255) DEFAULT 'nullclaw',
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_faq_sections_doc ON faq_sections(doc_id);
CREATE INDEX idx_faq_sections_parent ON faq_sections(parent_id);

COMMENT ON TABLE faq_sections IS 'FAQ 章节：目录结构由 nullclaw 根据内容聚类自动维护';

-- FAQ 问答条目
CREATE TABLE faq_items (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    section_id          UUID REFERENCES faq_sections(id) ON DELETE SET NULL,
    doc_id              UUID NOT NULL REFERENCES faq_documents(id) ON DELETE CASCADE,
    question            TEXT NOT NULL,
    answer              TEXT NOT NULL,
    question_variants   TEXT[] DEFAULT '{}',
    source_threads      UUID[] DEFAULT '{}',         -- 关联 topic_threads.id 列表
    confidence          REAL DEFAULT 0.8,            -- AI 生成置信度 (0-1)
    quality_score       REAL DEFAULT NULL,           -- 综合质量分 (0-1)，NULL=未评估
    view_count          INTEGER DEFAULT 0,
    helpful_count       INTEGER DEFAULT 0,
    unhelpful_count     INTEGER DEFAULT 0,
    -- 审核状态
    review_status       VARCHAR(20) DEFAULT 'pending'
                        CHECK (review_status IN ('pending', 'confirmed', 'rejected')),
    reviewed_by         VARCHAR(255),
    reviewed_at         TIMESTAMPTZ,
    -- 质量状态（独立于审核状态，运行时动态变化）
    quality_status      VARCHAR(20) DEFAULT 'normal'
                        CHECK (quality_status IN (
                            'normal',       -- 正常
                            'suspicious',   -- 疑似有误（自动触发：unhelpful_count >= 2）
                            'quarantined',  -- 已隔离（暂时对普通用户不可见，等待核查）
                            'stale'         -- 内容可能过期（超过 staleness_days 无更新）
                        )),
    quality_flagged_at  TIMESTAMPTZ,                 -- 进入 suspicious/quarantined 的时间
    quality_flagged_by  VARCHAR(255),                -- 触发源：'auto_rule' | user_id
    staleness_days      INTEGER DEFAULT 90,          -- 超过多少天未更新触发 stale 检测
    created_by          VARCHAR(255) DEFAULT 'nullclaw',
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_faq_items_doc ON faq_items(doc_id);
CREATE INDEX idx_faq_items_section ON faq_items(section_id);
CREATE INDEX idx_faq_items_status ON faq_items(review_status);
CREATE INDEX idx_faq_items_quality ON faq_items(quality_status) WHERE quality_status != 'normal';
CREATE INDEX idx_faq_items_search ON faq_items
    USING GIN(to_tsvector('simple', question || ' ' || answer));
-- question_variants 全文索引（支持变体问法命中）
CREATE INDEX idx_faq_items_variants ON faq_items USING GIN(question_variants);

COMMENT ON TABLE faq_items IS 'FAQ 问答条目：review_status 控制发布，quality_status 控制质量告警';
COMMENT ON COLUMN faq_items.quality_score IS '综合质量分 = confirmed_ratio * 0.4 + helpful_ratio * 0.4 + (1-staleness_ratio) * 0.2';
COMMENT ON COLUMN faq_items.quality_status IS 'suspicious: unhelpful>=2 自动触发; quarantined: 管理员或规则隔离; stale: 超期未更新';

-- FAQ 质量告警记录
-- 每次质量状态变更时写入，供管理员审查和 nullclaw Routine B 分析
CREATE TABLE faq_quality_alerts (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    item_id         UUID NOT NULL REFERENCES faq_items(id) ON DELETE CASCADE,
    alert_type      VARCHAR(50) NOT NULL
                    CHECK (alert_type IN (
                        'unhelpful_threshold',   -- unhelpful_count 触达阈值
                        'zero_helpful_30d',      -- 30天内 helpful_count=0 且有浏览
                        'stale_content',         -- 内容超期未更新
                        'conflict_detected',     -- nullclaw 检测到与新消息冲突
                        'manual_flag'            -- 管理员手工标记
                    )),
    triggered_by    VARCHAR(255),                -- 'auto_rule' | user_id | 'nullclaw'
    detail          JSONB DEFAULT '{}',          -- 告警时的上下文快照（如 unhelpful_count 值）
    status          VARCHAR(20) DEFAULT 'open'
                    CHECK (status IN ('open', 'resolved', 'dismissed')),
    resolved_by     VARCHAR(255),
    resolved_at     TIMESTAMPTZ,
    resolution_note TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_faq_alerts_item ON faq_quality_alerts(item_id);
CREATE INDEX idx_faq_alerts_open ON faq_quality_alerts(status, created_at DESC) WHERE status = 'open';

COMMENT ON TABLE faq_quality_alerts IS 'FAQ 质量告警：自动规则或手工触发，管理员处理后关闭';

-- FAQ 变更历史（版本控制）
CREATE TABLE faq_versions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    item_id         UUID NOT NULL REFERENCES faq_items(id) ON DELETE CASCADE,
    version         INTEGER NOT NULL,
    question        TEXT,
    answer          TEXT,
    change_type     VARCHAR(50) NOT NULL
                    CHECK (change_type IN ('created', 'updated', 'merged', 'reviewed', 'rejected')),
    change_by       VARCHAR(255),
    change_reason   TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_faq_versions_item ON faq_versions(item_id, version DESC);

COMMENT ON TABLE faq_versions IS 'FAQ 变更历史：记录每次修改，支持回滚';

-- =============================================================
-- END OF DDL
-- =============================================================

-- =============================================================
-- nullclaw 依赖管理（P0-2）
-- =============================================================

-- nullclaw 待处理事件队列（RippleFlow → nullclaw 推送失败时暂存）
CREATE TABLE nullclaw_pending_events (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type      VARCHAR(50) NOT NULL
                    CHECK (event_type IN ('message_processed', 'thread_updated', 'sensitive_resolved')),
    payload         JSONB NOT NULL DEFAULT '{}',
    status          VARCHAR(20) NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'delivered', 'failed', 'expired')),
    retry_count     INTEGER NOT NULL DEFAULT 0,
    next_retry_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_error      TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delivered_at    TIMESTAMPTZ
);

CREATE INDEX idx_pending_events_retry ON nullclaw_pending_events (next_retry_at)
    WHERE status = 'pending';
CREATE INDEX idx_pending_events_status ON nullclaw_pending_events (status, created_at DESC);

COMMENT ON TABLE nullclaw_pending_events IS 'nullclaw 事件推送待处理队列：推送失败时暂存，后台重试';

-- =============================================================
-- 消息处理死信队列（P1-2）
-- =============================================================

CREATE TABLE failed_messages (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id      UUID REFERENCES messages(id) ON DELETE SET NULL,
    failed_stage    VARCHAR(20) NOT NULL
                    CHECK (failed_stage IN ('stage0','stage1','stage2','stage3','stage4')),
    error_type      VARCHAR(50) NOT NULL
                    CHECK (error_type IN ('llm_timeout','llm_error','parse_error','business_error','unknown')),
    error_detail    TEXT,
    retry_count     INTEGER NOT NULL DEFAULT 0,
    status          VARCHAR(20) NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','retrying','resolved','skipped')),
    resolved_by     VARCHAR(255),
    resolved_at     TIMESTAMPTZ,
    resolution_note TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_failed_messages_status ON failed_messages (status, created_at DESC);
CREATE INDEX idx_failed_messages_message ON failed_messages (message_id);

COMMENT ON TABLE failed_messages IS '消息处理死信队列：3次重试耗尽后写入，供管理员人工处理';

-- =============================================================
-- 数据归档字段（P2-1）
-- =============================================================

-- topic_threads 归档状态
ALTER TABLE topic_threads
    ADD COLUMN archive_status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (archive_status IN ('active','archived_l2','archived_l3')),
    ADD COLUMN archived_at    TIMESTAMPTZ,
    ADD COLUMN archive_path   TEXT;

CREATE INDEX idx_threads_archive ON topic_threads (archive_status, last_message_at)
    WHERE archive_status = 'active';

-- messages 归档状态
ALTER TABLE messages
    ADD COLUMN archive_status   VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (archive_status IN ('active','archived')),
    ADD COLUMN content_archived BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX idx_messages_archive ON messages (archive_status)
    WHERE archive_status = 'archived';

COMMENT ON COLUMN topic_threads.archive_status IS 'L1=active，L2=archived_l2，L3=archived_l3';
COMMENT ON COLUMN messages.content_archived IS 'TRUE表示消息正文已移至对象存储，DB仅保留元数据';

-- =============================================================
-- 敏感授权分级机制（P1-3）
-- =============================================================

-- 为 sensitive_authorizations 添加敏感级别字段
ALTER TABLE sensitive_authorizations
    ADD COLUMN sensitivity_level VARCHAR(10) NOT NULL DEFAULT 'L3'
        CHECK (sensitivity_level IN ('L1', 'L2', 'L3')),
    ADD COLUMN auth_threshold    REAL NOT NULL DEFAULT 1.0;
    -- L1=0.0（任一授权即可）, L2=0.5（>50%）, L3=1.0（全员）

COMMENT ON COLUMN sensitive_authorizations.sensitivity_level IS
    'L1轻微（任一授权+脱敏入库）/ L2中等（>50%授权）/ L3高度（全员授权）';
COMMENT ON COLUMN sensitive_authorizations.auth_threshold IS
    '授权通过阈值：0.0=任一, 0.5=多数, 1.0=全员';


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
