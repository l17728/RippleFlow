-- =============================================================
-- RippleFlow Database DDL - SQLite Version
-- SQLite >= 3.38 (支持 JSON 函数)
-- 推荐启用 WAL 模式以支持并发读
-- =============================================================

-- 启用 WAL 模式和外键约束
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;

-- =============================================================
-- ENUM 值定义（作为注释参考，实际通过 CHECK 约束实现）
-- =============================================================

-- category_type: tech_decision, qa_faq, bug_incident, reference_data,
--                action_item, discussion_notes, knowledge_share,
--                env_config, project_update

-- thread_status: active, resolved, archived, merged

-- message_processing_status: pending, processing, classified, failed,
--                            skipped, sensitive_pending, sensitive_rejected

-- sensitive_overall_status: pending, authorized, rejected,
--                           pending_desensitization

-- action_item_status: open, in_progress, done, cancelled

-- incident_status: open, investigating, mitigated, resolved

-- notification_type: sensitive_pending, thread_modified, consensus_drift,
--                   action_item_assigned, reminder

-- =============================================================
-- TABLE: chat_rooms
-- 聊天群组（来自自研聊天工具）
-- =============================================================

CREATE TABLE chat_rooms (
    id               TEXT PRIMARY KEY,  -- UUID 格式: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    room_external_id TEXT UNIQUE NOT NULL,
    room_name        TEXT NOT NULL,
    room_type        TEXT NOT NULL DEFAULT 'group',
    is_active        INTEGER NOT NULL DEFAULT 1,  -- 0=false, 1=true
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),  -- ISO8601
    metadata         TEXT NOT NULL DEFAULT '{}'  -- JSON 对象
);

CREATE INDEX idx_rooms_external ON chat_rooms(room_external_id);

-- =============================================================
-- TABLE: chat_users
-- 聊天工具用户（来自自研聊天工具，ldap_user_id 为关联键）
-- =============================================================

CREATE TABLE chat_users (
    id               TEXT PRIMARY KEY,
    user_external_id TEXT UNIQUE NOT NULL,
    ldap_user_id     TEXT,
    display_name     TEXT NOT NULL,
    email            TEXT,
    is_bot           INTEGER NOT NULL DEFAULT 0,
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_chat_users_ldap ON chat_users(ldap_user_id);
CREATE INDEX idx_chat_users_external ON chat_users(user_external_id);

-- =============================================================
-- TABLE: user_whitelist
-- 系统访问白名单（唯一权限控制表）
-- =============================================================

CREATE TABLE user_whitelist (
    ldap_user_id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    email        TEXT,
    role         TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('member', 'admin')),
    added_by     TEXT,
    added_at     TEXT NOT NULL DEFAULT (datetime('now')),
    is_active    INTEGER NOT NULL DEFAULT 1,
    notes        TEXT
);

CREATE INDEX idx_whitelist_active ON user_whitelist(is_active);

-- =============================================================
-- TABLE: category_definitions
-- 信息类别定义（9 个默认 + 管理员可新增）
-- =============================================================

CREATE TABLE category_definitions (
    id                 TEXT PRIMARY KEY,
    code               TEXT UNIQUE NOT NULL,
    display_name       TEXT NOT NULL,
    description        TEXT,
    trigger_hints      TEXT NOT NULL DEFAULT '[]',  -- JSON 数组
    search_window_days INTEGER,
    is_active          INTEGER NOT NULL DEFAULT 1,
    is_builtin         INTEGER NOT NULL DEFAULT 0,
    sort_order         INTEGER NOT NULL DEFAULT 0,
    created_at         TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at         TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_catdef_active ON category_definitions(is_active);

-- 插入默认 9 类
INSERT INTO category_definitions
    (id, code, display_name, description, trigger_hints, search_window_days, is_builtin, sort_order)
VALUES
('00000000-0000-0000-0000-000000000001', 'tech_decision', '技术决策',
 '架构选型、技术方案确认、设计决策及其背后的理由',
 '["决定","方案","选型","采用","改用","弃用","ADR","tradeoff","我们决定","达成共识"]',
 NULL, 1, 1),

('00000000-0000-0000-0000-000000000002', 'qa_faq', '问题解答',
 '技术问答、排查方法，问题-答案对自动沉淀为 FAQ',
 '["怎么","如何","为什么","是什么","anyone know","报错","解决方法","原因是","fix"]',
 90, 1, 2),

('00000000-0000-0000-0000-000000000003', 'bug_incident', '故障案例',
 'Bug 报告、线上故障、根因分析及解决过程',
 '["bug","报错","异常","crash","故障","崩了","不行了","排查","修复","postmortem"]',
 90, 1, 3),

('00000000-0000-0000-0000-000000000004', 'reference_data', '参考信息',
 '团队共用的 IP、URL、端口、服务地址、账号名等参考数据',
 '["地址","ip","url","端口","入口","账号","域名","endpoint","服务器"]',
 NULL, 1, 4),

('00000000-0000-0000-0000-000000000005', 'action_item', '任务待办',
 '有明确负责人的任务指派、待办项',
 '["你来","负责","记得","TODO","action item","截止","deadline","@人名 + 动作"]',
 30, 1, 5),

('00000000-0000-0000-0000-000000000006', 'discussion_notes', '讨论纪要',
 '多人讨论的关键结论、共识记录、会议纪要',
 '["讨论","总结","纪要","共识","结论","standup","会议","sync","retro"]',
 90, 1, 6),

('00000000-0000-0000-0000-000000000007', 'knowledge_share', '知识分享',
 '技术文章推荐、经验分享、TIL、最佳实践',
 '["分享","推荐","TIL","今天学到","技巧","tip","pro tip","经验","记录一下"]',
 180, 1, 7),

('00000000-0000-0000-0000-000000000008', 'env_config', '环境配置',
 '开发/测试/生产环境配置、部署步骤、环境搭建说明',
 '["配置","部署","setup","env","环境变量","dockerfile","安装","搭建","怎么跑起来"]',
 NULL, 1, 8),

('00000000-0000-0000-0000-000000000009', 'project_update', '项目动态',
 '版本发布、里程碑、项目状态更新',
 '["上线","发布","release","v1","版本","里程碑","milestone","完成了","shipped"]',
 180, 1, 9);

-- =============================================================
-- TABLE: messages
-- 原始消息（不可变，永久保留出处）
-- =============================================================

CREATE TABLE messages (
    id                 TEXT PRIMARY KEY,
    room_id            TEXT NOT NULL REFERENCES chat_rooms(id),
    sender_external_id TEXT NOT NULL,
    content            TEXT NOT NULL,
    msg_timestamp      TEXT NOT NULL,  -- ISO8601
    msg_type           TEXT NOT NULL DEFAULT 'text',
    reply_to_msg_id    TEXT,
    platform_msg_id    TEXT,
    raw_metadata       TEXT DEFAULT '{}',  -- JSON
    created_at         TEXT NOT NULL DEFAULT (datetime('now')),

    UNIQUE(room_id, platform_msg_id)
);

CREATE INDEX idx_messages_room ON messages(room_id);
CREATE INDEX idx_messages_sender ON messages(sender_external_id);
CREATE INDEX idx_messages_timestamp ON messages(msg_timestamp);
CREATE INDEX idx_messages_reply ON messages(reply_to_msg_id);

-- 全文搜索索引 (FTS5)
CREATE VIRTUAL TABLE messages_fts USING fts5(
    content,
    content='messages',
    content_rowid='rowid',
    tokenize='unicode61'
);

-- 触发器：插入时同步到 FTS
CREATE TRIGGER messages_ai AFTER INSERT ON messages BEGIN
    INSERT INTO messages_fts(rowid, content) VALUES (NEW.rowid, NEW.content);
END;

CREATE TRIGGER messages_ad AFTER DELETE ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content)
    VALUES('delete', OLD.rowid, OLD.content);
END;

CREATE TRIGGER messages_au AFTER UPDATE ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content)
    VALUES('delete', OLD.rowid, OLD.content);
    INSERT INTO messages_fts(rowid, content) VALUES (NEW.rowid, NEW.content);
END;

-- =============================================================
-- TABLE: topic_threads
-- 话题线索（有价值的信息聚合单元）
-- =============================================================

CREATE TABLE topic_threads (
    id               TEXT PRIMARY KEY,
    room_id          TEXT NOT NULL REFERENCES chat_rooms(id),
    title            TEXT NOT NULL,
    category         TEXT NOT NULL CHECK (
        category IN ('tech_decision', 'qa_faq', 'bug_incident', 'reference_data',
                     'action_item', 'discussion_notes', 'knowledge_share',
                     'env_config', 'project_update')
    ),
    status           TEXT NOT NULL DEFAULT 'active' CHECK (
        status IN ('active', 'resolved', 'archived', 'merged')
    ),
    summary          TEXT,
    summary_version  INTEGER DEFAULT 1,
    summary_updated_at TEXT,
    confidence       REAL DEFAULT 0.8,
    is_duplicate     INTEGER DEFAULT 0,
    merged_into_id   TEXT REFERENCES topic_threads(id),
    info_domain      TEXT CHECK (
        info_domain IN ('knowledge', 'action', 'event', 'collaboration')
    ),
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at       TEXT NOT NULL DEFAULT (datetime('now')),
    created_by       TEXT,
    last_message_at  TEXT
);

CREATE INDEX idx_threads_room ON topic_threads(room_id);
CREATE INDEX idx_threads_category ON topic_threads(category);
CREATE INDEX idx_threads_status ON topic_threads(status);
CREATE INDEX idx_threads_info_domain ON topic_threads(info_domain);
CREATE INDEX idx_threads_created ON topic_threads(created_at);

-- 全文搜索索引 (FTS5)
CREATE VIRTUAL TABLE topic_threads_fts USING fts5(
    title, summary,
    content='topic_threads',
    content_rowid='rowid',
    tokenize='unicode61'
);

-- 触发器
CREATE TRIGGER threads_ai AFTER INSERT ON topic_threads BEGIN
    INSERT INTO topic_threads_fts(rowid, title, summary)
    VALUES (NEW.rowid, NEW.title, COALESCE(NEW.summary, ''));
END;

CREATE TRIGGER threads_ad AFTER DELETE ON topic_threads BEGIN
    INSERT INTO topic_threads_fts(topic_threads_fts, rowid, title, summary)
    VALUES('delete', OLD.rowid, OLD.title, COALESCE(OLD.summary, ''));
END;

CREATE TRIGGER threads_au AFTER UPDATE ON topic_threads BEGIN
    INSERT INTO topic_threads_fts(topic_threads_fts, rowid, title, summary)
    VALUES('delete', OLD.rowid, OLD.title, COALESCE(OLD.summary, ''));
    INSERT INTO topic_threads_fts(rowid, title, summary)
    VALUES (NEW.rowid, NEW.title, COALESCE(NEW.summary, ''));
END;

-- =============================================================
-- TABLE: message_thread_links
-- 消息与话题线索的关联（多对多）
-- =============================================================

CREATE TABLE message_thread_links (
    id              TEXT PRIMARY KEY,
    message_id      TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    thread_id       TEXT NOT NULL REFERENCES topic_threads(id) ON DELETE CASCADE,
    contribution    TEXT CHECK (
        contribution IN ('thread_start', 'key_point', 'followup', 'resolution', 'noise')
    ),
    relevance_score REAL DEFAULT 0.5,
    linked_at       TEXT NOT NULL DEFAULT (datetime('now')),
    linked_by       TEXT,  -- 'llm' | 'manual'

    UNIQUE(message_id, thread_id)
);

CREATE INDEX idx_mtl_message ON message_thread_links(message_id);
CREATE INDEX idx_mtl_thread ON message_thread_links(thread_id);

-- =============================================================
-- TABLE: action_items
-- 待办任务
-- =============================================================

CREATE TABLE action_items (
    id              TEXT PRIMARY KEY,
    thread_id       TEXT REFERENCES topic_threads(id) ON DELETE SET NULL,
    description     TEXT NOT NULL,
    assignee_ldap   TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'open' CHECK (
        status IN ('open', 'in_progress', 'done', 'cancelled')
    ),
    due_date        TEXT,  -- ISO8601 date
    priority        TEXT CHECK (priority IN ('high', 'medium', 'low')),
    source_type     TEXT DEFAULT 'explicit' CHECK (
        source_type IN ('explicit', 'implicit', 'multi_step')
    ),
    commitment_status TEXT CHECK (
        commitment_status IN ('identified', 'confirmed', 'dismissed')
    ),
    completed_at    TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now')),
    created_by      TEXT
);

CREATE INDEX idx_action_thread ON action_items(thread_id);
CREATE INDEX idx_action_assignee ON action_items(assignee_ldap);
CREATE INDEX idx_action_status ON action_items(status);
CREATE INDEX idx_action_due ON action_items(due_date);

-- =============================================================
-- TABLE: completion_signals
-- 完成信号配置（用于自动检测任务完成）
-- =============================================================

CREATE TABLE completion_signals (
    id           TEXT PRIMARY KEY,
    signal_text  TEXT NOT NULL UNIQUE,
    signal_type  TEXT NOT NULL CHECK (signal_type IN ('exact', 'pattern', 'emoji')),
    confidence   REAL DEFAULT 1.0,
    is_active    INTEGER DEFAULT 1
);

INSERT INTO completion_signals (id, signal_text, signal_type, confidence) VALUES
('00000000-0000-0000-0000-000000000101', '已完成', 'exact', 1.0),
('00000000-0000-0000-0000-000000000102', '搞定了', 'exact', 1.0),
('00000000-0000-0000-0000-000000000103', 'done', 'exact', 1.0),
('00000000-0000-0000-0000-000000000104', '✅', 'emoji', 0.9),
('00000000-0000-0000-0000-000000000105', '完成了', 'exact', 1.0),
('00000000-0000-0000-0000-000000000106', '解决了', 'exact', 0.9);

-- =============================================================
-- TABLE: implicit_commitment_patterns
-- 隐性承诺识别规则
-- =============================================================

CREATE TABLE implicit_commitment_patterns (
    id            TEXT PRIMARY KEY,
    pattern_regex TEXT NOT NULL,
    description   TEXT,
    confidence    REAL DEFAULT 0.8,
    is_active     INTEGER DEFAULT 1,
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO implicit_commitment_patterns (id, pattern_regex, description, confidence) VALUES
('00000000-0000-0000-0000-000000000201', '我(回头|之后|明天|下周|尽快)', '自我承诺模式', 0.8),
('00000000-0000-0000-0000-000000000202', '(我|咱们)(需要|得|应该|要)', '需求表达模式', 0.7),
('00000000-0000-0000-0000-000000000203', '(记|写)一下', '记录意图模式', 0.6),
('00000000-0000-0000-0000-000000000204', '.*(前|之前).*(给|发|提交|完成)', '时间承诺模式', 0.9),
('00000000-0000-0000-0000-000000000205', '(计划|准备|打算)', '计划表达模式', 0.7);

-- =============================================================
-- TABLE: sensitive_contents
-- 敏感内容检测记录
-- =============================================================

CREATE TABLE sensitive_contents (
    id              TEXT PRIMARY KEY,
    message_id      TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    detected_type   TEXT NOT NULL,  -- password, api_key, personal_info, etc.
    detected_at     TEXT NOT NULL DEFAULT (datetime('now')),
    detector_version TEXT,
    snippet_hash    TEXT,  -- 不存储原文，只存 hash
    snippet_start   INTEGER,
    snippet_end     INTEGER
);

CREATE INDEX idx_sensitive_message ON sensitive_contents(message_id);

-- =============================================================
-- TABLE: sensitive_authorizations
-- 敏感内容授权记录
-- =============================================================

CREATE TABLE sensitive_authorizations (
    id               TEXT PRIMARY KEY,
    content_id       TEXT NOT NULL REFERENCES sensitive_contents(id) ON DELETE CASCADE,
    ldap_user_id     TEXT NOT NULL,
    decision         TEXT CHECK (decision IN ('approved', 'rejected')),
    decided_at       TEXT NOT NULL DEFAULT (datetime('now')),
    desensitized_version TEXT,
    notes            TEXT,

    UNIQUE(content_id, ldap_user_id)
);

CREATE INDEX idx_sens_auth_content ON sensitive_authorizations(content_id);
CREATE INDEX idx_sens_auth_user ON sensitive_authorizations(ldap_user_id);

-- =============================================================
-- TABLE: sensitive_threads
-- 话题线索敏感状态汇总
-- =============================================================

CREATE TABLE sensitive_threads (
    id               TEXT PRIMARY KEY,
    thread_id        TEXT NOT NULL REFERENCES topic_threads(id) ON DELETE CASCADE,
    overall_status   TEXT NOT NULL DEFAULT 'pending' CHECK (
        overall_status IN ('pending', 'authorized', 'rejected', 'pending_desensitization')
    ),
    pending_since    TEXT NOT NULL DEFAULT (datetime('now')),
    resolved_at      TEXT,
    escalation_level INTEGER DEFAULT 0,

    UNIQUE(thread_id)
);

CREATE INDEX idx_sens_thread_status ON sensitive_threads(overall_status);

-- =============================================================
-- TABLE: thread_state_transitions
-- 线索状态变迁追踪
-- =============================================================

CREATE TABLE thread_state_transitions (
    id               TEXT PRIMARY KEY,
    thread_id        TEXT NOT NULL REFERENCES topic_threads(id) ON DELETE CASCADE,
    from_status      TEXT,
    to_status        TEXT NOT NULL,
    triggered_by     TEXT,
    trigger_message_id TEXT REFERENCES messages(id),
    transition_type  TEXT CHECK (
        transition_type IN ('manual', 'auto_detected', 'timeout', 'signal_detected')
    ),
    notes            TEXT,
    created_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_thread_transitions ON thread_state_transitions(thread_id, created_at);

-- =============================================================
-- TABLE: collaboration_relations
-- 协作关系网络
-- =============================================================

CREATE TABLE collaboration_relations (
    id                TEXT PRIMARY KEY,
    relation_type     TEXT NOT NULL,
    user_id_a         TEXT NOT NULL,
    user_id_b         TEXT NOT NULL,
    weight            REAL DEFAULT 1.0,
    thread_id         TEXT REFERENCES topic_threads(id),
    room_id           TEXT REFERENCES chat_rooms(id),
    period_start      TEXT,
    period_end        TEXT,
    interaction_count INTEGER DEFAULT 1,
    created_at        TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at        TEXT NOT NULL DEFAULT (datetime('now')),

    UNIQUE(relation_type, user_id_a, user_id_b, period_start)
);

CREATE INDEX idx_collab_users ON collaboration_relations(user_id_a, user_id_b);
CREATE INDEX idx_collab_type ON collaboration_relations(relation_type);
CREATE INDEX idx_collab_room ON collaboration_relations(room_id);
CREATE INDEX idx_collab_thread ON collaboration_relations(thread_id);

-- =============================================================
-- TABLE: relation_weights
-- 协作关系权重配置
-- =============================================================

CREATE TABLE relation_weights (
    interaction_type TEXT PRIMARY KEY,
    weight           REAL NOT NULL,
    description      TEXT
);

INSERT INTO relation_weights (interaction_type, weight, description) VALUES
('@mention', 3.0, '@提及'),
('reply', 2.0, '回复消息'),
('same_thread', 1.5, '共同参与话题'),
('same_time', 0.5, '同时在线');

-- =============================================================
-- TABLE: info_domains
-- 四大类信息域（系统顶层分类标准）
-- =============================================================

CREATE TABLE info_domains (
    code         TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    description  TEXT,
    icon         TEXT,
    color        TEXT,
    sort_order   INTEGER
);

INSERT INTO info_domains (code, display_name, description, icon, color, sort_order) VALUES
('knowledge', '知识库', 'FAQ、经验总结、术语规则、外部资源', 'book', 'blue', 1),
('action', '任务与待办', '显性任务、隐性承诺、多步骤事项', 'check-circle', 'green', 2),
('event', '事件与线索', '项目里程碑、问题处理全过程、决策过程', 'git-branch', 'purple', 3),
('collaboration', '协作网络', '沟通关系、任务关系、知识关系', 'users', 'orange', 4);

-- =============================================================
-- TABLE: notifications
-- 用户通知
-- =============================================================

CREATE TABLE notifications (
    id            TEXT PRIMARY KEY,
    ldap_user_id  TEXT NOT NULL,
    type          TEXT NOT NULL CHECK (
        type IN ('sensitive_pending', 'thread_modified', 'consensus_drift',
                 'action_item_assigned', 'reminder')
    ),
    title         TEXT NOT NULL,
    content       TEXT,
    related_thread_id TEXT REFERENCES topic_threads(id),
    related_action_id TEXT REFERENCES action_items(id),
    is_read       INTEGER DEFAULT 0,
    created_at    TEXT NOT NULL DEFAULT (datetime('now')),
    read_at       TEXT
);

CREATE INDEX idx_notifications_user ON notifications(ldap_user_id);
CREATE INDEX idx_notifications_read ON notifications(ldap_user_id, is_read);

-- =============================================================
-- TABLE: user_subscriptions
-- 用户订阅关注
-- =============================================================

CREATE TABLE user_subscriptions (
    id              TEXT PRIMARY KEY,
    ldap_user_id    TEXT NOT NULL,
    subscription_type TEXT NOT NULL CHECK (
        subscription_type IN ('thread', 'category', 'keyword', 'user')
    ),
    target_id       TEXT NOT NULL,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),

    UNIQUE(ldap_user_id, subscription_type, target_id)
);

CREATE INDEX idx_subscriptions_user ON user_subscriptions(ldap_user_id);
CREATE INDEX idx_subscriptions_target ON user_subscriptions(target_id);

-- =============================================================
-- TABLE: qa_feedback
-- 问答反馈
-- =============================================================

CREATE TABLE qa_feedback (
    id              TEXT PRIMARY KEY,
    thread_id       TEXT NOT NULL REFERENCES topic_threads(id),
    question_text   TEXT NOT NULL,
    answer_text     TEXT NOT NULL,
    user_ldap_id    TEXT NOT NULL,
    rating          INTEGER CHECK (rating >= 1 AND rating <= 5),
    feedback_text   TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_qa_thread ON qa_feedback(thread_id);
CREATE INDEX idx_qa_user ON qa_feedback(user_ldap_id);

-- =============================================================
-- TABLE: user_contributions
-- 用户贡献统计
-- =============================================================

CREATE TABLE user_contributions (
    id                   TEXT PRIMARY KEY,
    ldap_user_id         TEXT NOT NULL,
    period_start         TEXT NOT NULL,  -- 统计周期起始
    period_type          TEXT NOT NULL CHECK (period_type IN ('day', 'week', 'month')),
    questions_asked      INTEGER DEFAULT 0,
    questions_answered   INTEGER DEFAULT 0,
    knowledge_shared     INTEGER DEFAULT 0,
    action_items_created INTEGER DEFAULT 0,
    action_items_done    INTEGER DEFAULT 0,
    helpful_votes        INTEGER DEFAULT 0,

    UNIQUE(ldap_user_id, period_start, period_type)
);

CREATE INDEX idx_contrib_user ON user_contributions(ldap_user_id);
CREATE INDEX idx_contrib_period ON user_contributions(period_start, period_type);

-- =============================================================
-- TABLE: platform_users
-- 多平台用户绑定
-- =============================================================

CREATE TABLE platform_users (
    id               TEXT PRIMARY KEY,
    ldap_user_id     TEXT NOT NULL,
    platform         TEXT NOT NULL,  -- 'wechat', 'dingtalk', 'lark', 'slack'
    platform_user_id TEXT NOT NULL,
    display_name     TEXT,
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),

    UNIQUE(platform, platform_user_id)
);

CREATE INDEX idx_platform_users ON platform_users(platform, platform_user_id);
CREATE INDEX idx_platform_ldap ON platform_users(ldap_user_id);

-- =============================================================
-- TABLE: import_batches
-- 批量导入批次记录
-- =============================================================

CREATE TABLE import_batches (
    id              TEXT PRIMARY KEY,
    room_id         TEXT REFERENCES chat_rooms(id),
    platform        TEXT NOT NULL,
    file_name       TEXT,
    file_hash       TEXT,
    total_messages  INTEGER DEFAULT 0,
    imported_count  INTEGER DEFAULT 0,
    skipped_count   INTEGER DEFAULT 0,
    error_count     INTEGER DEFAULT 0,
    status          TEXT NOT NULL DEFAULT 'pending' CHECK (
        status IN ('pending', 'processing', 'completed', 'failed')
    ),
    started_at      TEXT,
    completed_at    TEXT,
    error_details   TEXT,  -- JSON
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    created_by      TEXT
);

CREATE INDEX idx_import_room ON import_batches(room_id);
CREATE INDEX idx_import_status ON import_batches(status);

-- =============================================================
-- TABLE: processing_queue
-- 消息处理队列
-- =============================================================

CREATE TABLE processing_queue (
    id           TEXT PRIMARY KEY,
    message_id   TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    stage        TEXT NOT NULL CHECK (
        stage IN ('pending', 'classifying', 'linking', 'completed', 'failed')
    ),
    attempts     INTEGER DEFAULT 0,
    last_error   TEXT,
    created_at   TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at   TEXT NOT NULL DEFAULT (datetime('now')),
    locked_until TEXT,

    UNIQUE(message_id)
);

CREATE INDEX idx_queue_stage ON processing_queue(stage);
CREATE INDEX idx_queue_locked ON processing_queue(locked_until);

-- =============================================================
-- TABLE: app_settings
-- 系统设置（键值对）
-- =============================================================

CREATE TABLE app_settings (
    key         TEXT PRIMARY KEY,
    value       TEXT NOT NULL,
    updated_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_by  TEXT
);

-- 初始化设置
INSERT INTO app_settings (key, value) VALUES
('schema_version', '1.0.0'),
('llm_model', 'glm-4-plus'),
('system_prompt_version', '1');
-- 注：系统不使用向量检索，无 embedding_model 配置

-- =============================================================
-- VIEWS: 常用查询视图
-- =============================================================

-- 活跃话题视图
CREATE VIEW v_active_threads AS
SELECT
    t.id,
    t.title,
    t.category,
    t.status,
    t.summary,
    t.confidence,
    t.info_domain,
    r.room_name,
    t.created_at,
    t.last_message_at,
    (SELECT COUNT(*) FROM message_thread_links mtl WHERE mtl.thread_id = t.id) AS message_count,
    (SELECT COUNT(*) FROM action_items ai WHERE ai.thread_id = t.id AND ai.status != 'done') AS pending_actions
FROM topic_threads t
JOIN chat_rooms r ON t.room_id = r.id
WHERE t.status = 'active'
ORDER BY t.last_message_at DESC;

-- 用户待办视图
CREATE VIEW v_user_todos AS
SELECT
    a.id,
    a.description,
    a.status,
    a.due_date,
    a.priority,
    t.title AS thread_title,
    r.room_name,
    a.created_at
FROM action_items a
LEFT JOIN topic_threads t ON a.thread_id = t.id
LEFT JOIN chat_rooms r ON t.room_id = r.id
WHERE a.status IN ('open', 'in_progress')
ORDER BY
    CASE a.priority WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END,
    a.due_date ASC;

-- 协作网络视图
CREATE VIEW v_collaboration_summary AS
SELECT
    cr.relation_type,
    u.display_name AS user_a_name,
    v.display_name AS user_b_name,
    cr.weight,
    cr.interaction_count
FROM collaboration_relations cr
JOIN chat_users u ON cr.user_id_a = u.ldap_user_id
JOIN chat_users v ON cr.user_id_b = v.ldap_user_id
ORDER BY cr.weight DESC;

-- =============================================================
-- FAQ 知识库系统（群聊知识沉淀）
-- =============================================================

CREATE TABLE faq_documents (
    id              TEXT PRIMARY KEY,                -- UUID 字符串
    group_id        TEXT NOT NULL UNIQUE,
    version         INTEGER DEFAULT 0,
    qa_count        INTEGER DEFAULT 0,
    created_at      TEXT DEFAULT (datetime('now')),
    updated_at      TEXT DEFAULT (datetime('now'))
);

CREATE TABLE faq_sections (
    id              TEXT PRIMARY KEY,
    doc_id          TEXT NOT NULL REFERENCES faq_documents(id) ON DELETE CASCADE,
    parent_id       TEXT REFERENCES faq_sections(id) ON DELETE CASCADE,
    title           TEXT NOT NULL,
    sort_order      INTEGER DEFAULT 0,
    created_by      TEXT DEFAULT 'nullclaw',
    updated_at      TEXT DEFAULT (datetime('now'))
);

CREATE INDEX idx_faq_sections_doc ON faq_sections(doc_id);
CREATE INDEX idx_faq_sections_parent ON faq_sections(parent_id);

CREATE TABLE faq_items (
    id              TEXT PRIMARY KEY,
    section_id      TEXT REFERENCES faq_sections(id) ON DELETE SET NULL,
    doc_id          TEXT NOT NULL REFERENCES faq_documents(id) ON DELETE CASCADE,
    question        TEXT NOT NULL,
    answer          TEXT NOT NULL,
    question_variants TEXT DEFAULT '[]',             -- JSON 数组
    source_threads  TEXT DEFAULT '[]',               -- JSON 数组（topic_threads.id）
    confidence      REAL DEFAULT 0.8,
    view_count      INTEGER DEFAULT 0,
    helpful_count   INTEGER DEFAULT 0,
    unhelpful_count INTEGER DEFAULT 0,
    review_status   TEXT DEFAULT 'pending'
                    CHECK (review_status IN ('pending', 'confirmed', 'rejected')),
    reviewed_by     TEXT,
    reviewed_at     TEXT,
    created_by      TEXT DEFAULT 'nullclaw',
    created_at      TEXT DEFAULT (datetime('now')),
    updated_at      TEXT DEFAULT (datetime('now'))
);

CREATE INDEX idx_faq_items_doc ON faq_items(doc_id);
CREATE INDEX idx_faq_items_section ON faq_items(section_id);
CREATE INDEX idx_faq_items_status ON faq_items(review_status);

CREATE TABLE faq_versions (
    id              TEXT PRIMARY KEY,
    item_id         TEXT NOT NULL REFERENCES faq_items(id) ON DELETE CASCADE,
    version         INTEGER NOT NULL,
    question        TEXT,
    answer          TEXT,
    change_type     TEXT NOT NULL
                    CHECK (change_type IN ('created', 'updated', 'merged', 'reviewed', 'rejected')),
    change_by       TEXT,
    change_reason   TEXT,
    created_at      TEXT DEFAULT (datetime('now'))
);

CREATE INDEX idx_faq_versions_item ON faq_versions(item_id, version DESC);

-- =============================================================
-- END OF DDL
-- =============================================================