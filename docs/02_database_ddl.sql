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
    scheduled_at    TIMESTAMPTZ NOT NULL,
    executed_at     TIMESTAMPTZ,
    target_room_id  UUID REFERENCES chat_rooms(id) ON DELETE SET NULL,
    target_user_ids TEXT[],  -- ldap_user_id[]
    payload         JSONB NOT NULL DEFAULT '{}',
    result          JSONB,
    error           TEXT,
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
-- END OF DDL
-- =============================================================
