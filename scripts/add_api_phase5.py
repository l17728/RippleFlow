"""Phase 5: 追加新需求的 API 端点和 Schema 到 03_api_reference.yaml"""

import yaml

with open('D:/RippleFlow/docs/03_api_reference.yaml', 'r', encoding='utf-8') as f:
    doc = yaml.safe_load(f)

# ── New Schemas ──────────────────────────────────────────────────────────────

new_schemas = {
    # Presence
    "UserPresence": {
        "type": "object",
        "properties": {
            "user_id":        {"type": "string"},
            "status":         {"type": "string", "enum": ["online", "idle", "offline"]},
            "last_heartbeat": {"type": "string", "format": "date-time", "nullable": True},
            "client_info":    {"type": "object"},
            "updated_at":     {"type": "string", "format": "date-time"},
        }
    },
    "QueuedNotification": {
        "type": "object",
        "properties": {
            "id":           {"type": "string", "format": "uuid"},
            "user_id":      {"type": "string"},
            "event_type":   {"type": "string"},
            "payload":      {"type": "object"},
            "priority":     {"type": "integer", "description": "1=高优先级, 5=低优先级"},
            "expires_at":   {"type": "string", "format": "date-time", "nullable": True},
            "delivered_at": {"type": "string", "format": "date-time", "nullable": True},
            "created_at":   {"type": "string", "format": "date-time"},
        }
    },
    # Extensions
    "SoftExtension": {
        "type": "object",
        "properties": {
            "id":           {"type": "string", "format": "uuid"},
            "ext_type":     {"type": "string", "enum": ["category", "task_type", "label"]},
            "ext_key":      {"type": "string"},
            "display_name": {"type": "string"},
            "description":  {"type": "string", "nullable": True},
            "parent_key":   {"type": "string", "nullable": True},
            "risk_level":   {"type": "string", "enum": ["low", "high"]},
            "status":       {"type": "string", "enum": ["pending", "active", "disabled"]},
            "proposed_by":  {"type": "string"},
            "approved_by":  {"type": "string", "nullable": True},
            "approved_at":  {"type": "string", "format": "date-time", "nullable": True},
            "config":       {"type": "object"},
            "created_at":   {"type": "string", "format": "date-time"},
        }
    },
    "HardExtension": {
        "type": "object",
        "properties": {
            "id":          {"type": "string", "format": "uuid"},
            "name":        {"type": "string"},
            "ext_track":   {"type": "string", "enum": ["event_hook", "nullclaw_script"]},
            "hook_events": {"type": "array", "items": {"type": "string"}},
            "webhook_url": {"type": "string", "nullable": True},
            "script_path": {"type": "string", "nullable": True},
            "version":     {"type": "string"},
            "status":      {"type": "string", "enum": ["pending", "active", "disabled"]},
            "approved_by": {"type": "string", "nullable": True},
            "config":      {"type": "object"},
            "created_at":  {"type": "string", "format": "date-time"},
        }
    },
    "ExtensionInvocationLog": {
        "type": "object",
        "properties": {
            "id":             {"type": "string", "format": "uuid"},
            "extension_id":   {"type": "string", "format": "uuid"},
            "hook_event":     {"type": "string", "nullable": True},
            "input_payload":  {"type": "object"},
            "output_payload": {"type": "object"},
            "status":         {"type": "string", "enum": ["success", "failed", "timeout"]},
            "duration_ms":    {"type": "integer", "nullable": True},
            "created_at":     {"type": "string", "format": "date-time"},
        }
    },
    # Workflows
    "WorkflowTemplate": {
        "type": "object",
        "properties": {
            "id":              {"type": "string", "format": "uuid"},
            "name":            {"type": "string"},
            "trigger_pattern": {"type": "string", "nullable": True},
            "trigger_regex":   {"type": "string", "nullable": True},
            "steps":           {"type": "array", "items": {"type": "object"}},
            "learned_from":    {"type": "array", "items": {"type": "string"}},
            "style_notes":     {"type": "string", "nullable": True},
            "trust_level":     {"type": "string", "enum": ["supervised", "autonomous"]},
            "trust_score":     {"type": "number", "minimum": 0, "maximum": 1},
            "used_count":      {"type": "integer"},
            "success_count":   {"type": "integer"},
            "created_by":      {"type": "string"},
            "created_at":      {"type": "string", "format": "date-time"},
            "updated_at":      {"type": "string", "format": "date-time"},
        }
    },
    "WorkflowInstance": {
        "type": "object",
        "properties": {
            "id":                  {"type": "string", "format": "uuid"},
            "template_id":         {"type": "string", "format": "uuid", "nullable": True},
            "trigger_thread_id":   {"type": "string", "format": "uuid", "nullable": True},
            "trigger_message_id":  {"type": "string", "format": "uuid", "nullable": True},
            "status":              {"type": "string", "enum": ["pending_approval", "running", "completed", "cancelled", "failed"]},
            "approved_by":         {"type": "string", "nullable": True},
            "approval_expires_at": {"type": "string", "format": "date-time", "nullable": True},
            "context":             {"type": "object"},
            "execution_log":       {"type": "array", "items": {"type": "object"}},
            "cancelled_reason":    {"type": "string", "nullable": True},
            "created_at":          {"type": "string", "format": "date-time"},
            "completed_at":        {"type": "string", "format": "date-time", "nullable": True},
        }
    },
    "TaskDelegate": {
        "type": "object",
        "properties": {
            "id":               {"type": "string", "format": "uuid"},
            "source_thread_id": {"type": "string", "format": "uuid", "nullable": True},
            "target_user_id":   {"type": "string"},
            "target_group_id":  {"type": "string", "nullable": True},
            "task_description": {"type": "string"},
            "delegated_by":     {"type": "string"},
            "status":           {"type": "string", "enum": ["pending", "accepted", "rejected", "completed"]},
            "due_at":           {"type": "string", "format": "date-time", "nullable": True},
            "created_at":       {"type": "string", "format": "date-time"},
        }
    },
    # Custom Fields
    "CustomFieldDefinition": {
        "type": "object",
        "properties": {
            "id":           {"type": "string", "format": "uuid"},
            "entity_type":  {"type": "string", "enum": ["thread", "todo", "faq_item", "workflow"]},
            "group_id":     {"type": "string", "nullable": True},
            "field_key":    {"type": "string"},
            "field_name":   {"type": "string"},
            "field_type":   {"type": "string", "enum": ["text", "number", "date", "select", "boolean"]},
            "options":      {"type": "array", "items": {"type": "string"}},
            "suggested_by": {"type": "string", "nullable": True},
            "adopted_by":   {"type": "string", "nullable": True},
            "adopted_at":   {"type": "string", "format": "date-time", "nullable": True},
            "usage_count":  {"type": "integer"},
            "created_at":   {"type": "string", "format": "date-time"},
        }
    },
    "CustomFieldValue": {
        "type": "object",
        "properties": {
            "entity_type": {"type": "string"},
            "entity_id":   {"type": "string", "format": "uuid"},
            "field_id":    {"type": "string", "format": "uuid"},
            "value":       {"type": "string", "nullable": True},
            "set_by":      {"type": "string"},
            "set_at":      {"type": "string", "format": "date-time"},
        }
    },
}

doc['components']['schemas'].update(new_schemas)

# ── New Paths ─────────────────────────────────────────────────────────────────

new_paths = {
    # ── Presence ─────────────────────────────────────────────────────────────
    "/api/v1/presence/heartbeat": {
        "post": {
            "tags": ["presence"],
            "summary": "客户端心跳",
            "description": "每 30 秒调用一次。更新在线状态，返回缓存的待推送通知列表（并标记为已送达）。",
            "security": [{"cookieAuth": []}],
            "requestBody": {
                "required": False,
                "content": {"application/json": {"schema": {
                    "type": "object",
                    "properties": {"client_info": {"type": "object", "description": "设备/版本信息"}},
                }}}
            },
            "responses": {
                "200": {
                    "description": "心跳成功，返回待推送通知",
                    "content": {"application/json": {"schema": {
                        "type": "object",
                        "properties": {
                            "status": {"type": "string", "enum": ["online"]},
                            "notifications": {"type": "array", "items": {"$ref": "#/components/schemas/QueuedNotification"}},
                            "notification_count": {"type": "integer"},
                        }
                    }}}
                }
            }
        }
    },
    "/api/v1/presence/status/{user_id}": {
        "get": {
            "tags": ["presence"],
            "summary": "查询用户在线状态",
            "security": [{"cookieAuth": []}],
            "parameters": [{"in": "path", "name": "user_id", "required": True, "schema": {"type": "string"}}],
            "responses": {
                "200": {
                    "description": "用户在线状态",
                    "content": {"application/json": {"schema": {"$ref": "#/components/schemas/UserPresence"}}}
                }
            }
        }
    },
    "/api/v1/presence/online": {
        "get": {
            "tags": ["presence"],
            "summary": "获取在线用户列表（管理员/管家）",
            "security": [{"cookieAuth": []}],
            "parameters": [
                {"in": "query", "name": "group_id", "schema": {"type": "string"}, "description": "按群组过滤"},
            ],
            "responses": {
                "200": {
                    "description": "当前在线用户列表",
                    "content": {"application/json": {"schema": {
                        "type": "object",
                        "properties": {
                            "users": {"type": "array", "items": {"$ref": "#/components/schemas/UserPresence"}},
                            "total": {"type": "integer"},
                        }
                    }}}
                }
            }
        }
    },

    # ── Soft Extensions ───────────────────────────────────────────────────────
    "/api/v1/extensions/definitions": {
        "get": {
            "tags": ["extensions"],
            "summary": "列出软能力扩展定义",
            "security": [{"cookieAuth": []}],
            "parameters": [
                {"in": "query", "name": "status", "schema": {"type": "string", "enum": ["pending", "active", "disabled"]}},
                {"in": "query", "name": "ext_type", "schema": {"type": "string", "enum": ["category", "task_type", "label"]}},
            ],
            "responses": {
                "200": {"description": "软扩展列表", "content": {"application/json": {"schema": {
                    "type": "object",
                    "properties": {"items": {"type": "array", "items": {"$ref": "#/components/schemas/SoftExtension"}}}
                }}}}
            }
        },
        "post": {
            "tags": ["extensions"],
            "summary": "提议新软能力扩展",
            "description": "低风险（子分类/标签）直接生效；高风险（一级分类/触发规则修改）进入 pending 等待管理员审核。",
            "security": [{"cookieAuth": []}],
            "requestBody": {
                "required": True,
                "content": {"application/json": {"schema": {
                    "type": "object",
                    "required": ["ext_type", "ext_key", "display_name"],
                    "properties": {
                        "ext_type":     {"type": "string", "enum": ["category", "task_type", "label"]},
                        "ext_key":      {"type": "string"},
                        "display_name": {"type": "string"},
                        "description":  {"type": "string"},
                        "parent_key":   {"type": "string"},
                        "config":       {"type": "object"},
                        "proposed_by":  {"type": "string", "default": "nullclaw"},
                    }
                }}}
            },
            "responses": {
                "201": {"description": "扩展已创建", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/SoftExtension"}}}}
            }
        }
    },
    "/api/v1/extensions/definitions/{id}/approve": {
        "post": {
            "tags": ["extensions"],
            "summary": "管理员审核通过高风险软扩展",
            "security": [{"cookieAuth": []}],
            "parameters": [{"in": "path", "name": "id", "required": True, "schema": {"type": "string", "format": "uuid"}}],
            "responses": {
                "200": {"description": "扩展已激活", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/SoftExtension"}}}}
            }
        }
    },
    "/api/v1/extensions/definitions/{id}/disable": {
        "post": {
            "tags": ["extensions"],
            "summary": "禁用软能力扩展",
            "security": [{"cookieAuth": []}],
            "parameters": [{"in": "path", "name": "id", "required": True, "schema": {"type": "string", "format": "uuid"}}],
            "responses": {
                "200": {"description": "扩展已禁用", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/SoftExtension"}}}}
            }
        }
    },

    # ── Hard Extensions ───────────────────────────────────────────────────────
    "/api/v1/extensions/registry": {
        "get": {
            "tags": ["extensions"],
            "summary": "列出硬能力扩展注册表",
            "security": [{"cookieAuth": []}],
            "parameters": [
                {"in": "query", "name": "ext_track", "schema": {"type": "string", "enum": ["event_hook", "nullclaw_script"]}},
                {"in": "query", "name": "status", "schema": {"type": "string", "enum": ["pending", "active", "disabled"]}},
            ],
            "responses": {
                "200": {"description": "硬扩展列表", "content": {"application/json": {"schema": {
                    "type": "object",
                    "properties": {"items": {"type": "array", "items": {"$ref": "#/components/schemas/HardExtension"}}}
                }}}}
            }
        },
        "post": {
            "tags": ["extensions"],
            "summary": "注册硬能力扩展（提交后待管理员审核）",
            "security": [{"cookieAuth": []}],
            "requestBody": {
                "required": True,
                "content": {"application/json": {"schema": {
                    "type": "object",
                    "required": ["name", "ext_track"],
                    "properties": {
                        "name":        {"type": "string"},
                        "ext_track":   {"type": "string", "enum": ["event_hook", "nullclaw_script"]},
                        "hook_events": {"type": "array", "items": {"type": "string"}},
                        "webhook_url": {"type": "string"},
                        "script_path": {"type": "string"},
                        "version":     {"type": "string", "default": "1.0.0"},
                        "config":      {"type": "object"},
                    }
                }}}
            },
            "responses": {
                "201": {"description": "插件已注册（status=pending）", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/HardExtension"}}}}
            }
        }
    },
    "/api/v1/extensions/registry/{id}/approve": {
        "post": {
            "tags": ["extensions"],
            "summary": "管理员激活硬能力扩展",
            "security": [{"cookieAuth": []}],
            "parameters": [{"in": "path", "name": "id", "required": True, "schema": {"type": "string", "format": "uuid"}}],
            "responses": {
                "200": {"description": "插件已激活", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/HardExtension"}}}}
            }
        }
    },
    "/api/v1/extensions/registry/{id}/logs": {
        "get": {
            "tags": ["extensions"],
            "summary": "获取插件调用日志",
            "security": [{"cookieAuth": []}],
            "parameters": [
                {"in": "path", "name": "id", "required": True, "schema": {"type": "string", "format": "uuid"}},
                {"in": "query", "name": "limit", "schema": {"type": "integer", "default": 50}},
            ],
            "responses": {
                "200": {"description": "调用日志列表", "content": {"application/json": {"schema": {
                    "type": "object",
                    "properties": {"items": {"type": "array", "items": {"$ref": "#/components/schemas/ExtensionInvocationLog"}}}
                }}}}
            }
        }
    },

    # ── Workflows ─────────────────────────────────────────────────────────────
    "/api/v1/workflows/templates": {
        "get": {
            "tags": ["workflows"],
            "summary": "列出工作流模板",
            "security": [{"cookieAuth": []}],
            "parameters": [
                {"in": "query", "name": "trust_level", "schema": {"type": "string", "enum": ["supervised", "autonomous"]}},
                {"in": "query", "name": "page", "schema": {"type": "integer", "default": 1}},
                {"in": "query", "name": "size", "schema": {"type": "integer", "default": 20}},
            ],
            "responses": {
                "200": {"description": "工作流模板列表", "content": {"application/json": {"schema": {
                    "type": "object",
                    "properties": {
                        "items": {"type": "array", "items": {"$ref": "#/components/schemas/WorkflowTemplate"}},
                        "total": {"type": "integer"},
                    }
                }}}}
            }
        },
        "post": {
            "tags": ["workflows"],
            "summary": "创建工作流模板（管家学习后调用）",
            "security": [{"cookieAuth": []}],
            "requestBody": {
                "required": True,
                "content": {"application/json": {"schema": {
                    "type": "object",
                    "required": ["name", "trigger_pattern", "steps"],
                    "properties": {
                        "name":            {"type": "string"},
                        "trigger_pattern": {"type": "string"},
                        "trigger_regex":   {"type": "string"},
                        "steps":           {"type": "array", "items": {"type": "object"}},
                        "style_notes":     {"type": "string"},
                        "learned_from":    {"type": "array", "items": {"type": "string"}},
                    }
                }}}
            },
            "responses": {
                "201": {"description": "模板已创建", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/WorkflowTemplate"}}}}
            }
        }
    },
    "/api/v1/workflows/templates/{id}": {
        "put": {
            "tags": ["workflows"],
            "summary": "更新工作流模板（风格/信任度）",
            "security": [{"cookieAuth": []}],
            "parameters": [{"in": "path", "name": "id", "required": True, "schema": {"type": "string", "format": "uuid"}}],
            "requestBody": {
                "required": True,
                "content": {"application/json": {"schema": {
                    "type": "object",
                    "properties": {
                        "style_notes": {"type": "string"},
                        "trust_level": {"type": "string", "enum": ["supervised", "autonomous"]},
                        "trust_score": {"type": "number", "minimum": 0, "maximum": 1},
                    }
                }}}
            },
            "responses": {
                "200": {"description": "模板已更新", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/WorkflowTemplate"}}}}
            }
        }
    },
    "/api/v1/workflows/instances": {
        "get": {
            "tags": ["workflows"],
            "summary": "列出工作流实例",
            "security": [{"cookieAuth": []}],
            "parameters": [
                {"in": "query", "name": "status", "schema": {"type": "string", "enum": ["pending_approval", "running", "completed", "cancelled", "failed"]}},
                {"in": "query", "name": "user_id", "schema": {"type": "string"}},
                {"in": "query", "name": "page", "schema": {"type": "integer", "default": 1}},
                {"in": "query", "name": "size", "schema": {"type": "integer", "default": 20}},
            ],
            "responses": {
                "200": {"description": "工作流实例列表", "content": {"application/json": {"schema": {
                    "type": "object",
                    "properties": {
                        "items": {"type": "array", "items": {"$ref": "#/components/schemas/WorkflowInstance"}},
                        "total": {"type": "integer"},
                    }
                }}}}
            }
        }
    },
    "/api/v1/workflows/instances/{id}/approve": {
        "post": {
            "tags": ["workflows"],
            "summary": "用户批准工作流执行（supervised 模式）",
            "security": [{"cookieAuth": []}],
            "parameters": [{"in": "path", "name": "id", "required": True, "schema": {"type": "string", "format": "uuid"}}],
            "responses": {
                "200": {"description": "工作流开始执行", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/WorkflowInstance"}}}}
            }
        }
    },
    "/api/v1/workflows/instances/{id}/cancel": {
        "post": {
            "tags": ["workflows"],
            "summary": "取消工作流实例",
            "security": [{"cookieAuth": []}],
            "parameters": [{"in": "path", "name": "id", "required": True, "schema": {"type": "string", "format": "uuid"}}],
            "requestBody": {
                "required": False,
                "content": {"application/json": {"schema": {
                    "type": "object",
                    "properties": {
                        "reason":       {"type": "string"},
                        "cancelled_by": {"type": "string", "description": "user_handled=用户已自行处理（触发管家学习）"},
                    }
                }}}
            },
            "responses": {
                "200": {"description": "工作流已取消", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/WorkflowInstance"}}}}
            }
        }
    },

    # ── Task Delegation ───────────────────────────────────────────────────────
    "/api/v1/tasks/delegate": {
        "post": {
            "tags": ["workflows"],
            "summary": "创建跨群任务分发",
            "security": [{"cookieAuth": []}],
            "requestBody": {
                "required": True,
                "content": {"application/json": {"schema": {
                    "type": "object",
                    "required": ["target_user_id", "task_description"],
                    "properties": {
                        "source_thread_id": {"type": "string", "format": "uuid"},
                        "target_user_id":   {"type": "string"},
                        "target_group_id":  {"type": "string"},
                        "task_description": {"type": "string"},
                        "due_at":           {"type": "string", "format": "date-time"},
                        "delegated_by":     {"type": "string", "default": "nullclaw"},
                    }
                }}}
            },
            "responses": {
                "201": {"description": "任务已分发", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/TaskDelegate"}}}}
            }
        }
    },
    "/api/v1/tasks/delegate/{id}": {
        "put": {
            "tags": ["workflows"],
            "summary": "更新任务分发状态（目标用户接受/拒绝/完成）",
            "security": [{"cookieAuth": []}],
            "parameters": [{"in": "path", "name": "id", "required": True, "schema": {"type": "string", "format": "uuid"}}],
            "requestBody": {
                "required": True,
                "content": {"application/json": {"schema": {
                    "type": "object",
                    "required": ["status"],
                    "properties": {
                        "status": {"type": "string", "enum": ["accepted", "rejected", "completed"]},
                    }
                }}}
            },
            "responses": {
                "200": {"description": "状态已更新", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/TaskDelegate"}}}}
            }
        }
    },

    # ── Custom Fields ─────────────────────────────────────────────────────────
    "/api/v1/custom-fields": {
        "get": {
            "tags": ["custom-fields"],
            "summary": "列出自定义字段定义",
            "security": [{"cookieAuth": []}],
            "parameters": [
                {"in": "query", "name": "entity_type", "schema": {"type": "string", "enum": ["thread", "todo", "faq_item", "workflow"]}},
                {"in": "query", "name": "group_id", "schema": {"type": "string"}},
                {"in": "query", "name": "include_suggestions", "schema": {"type": "boolean", "default": True}},
            ],
            "responses": {
                "200": {"description": "自定义字段定义列表", "content": {"application/json": {"schema": {
                    "type": "object",
                    "properties": {"items": {"type": "array", "items": {"$ref": "#/components/schemas/CustomFieldDefinition"}}}
                }}}}
            }
        },
        "post": {
            "tags": ["custom-fields"],
            "summary": "定义新自定义字段",
            "description": "suggested_by=nullclaw 时进入推荐状态，等待用户采纳；suggested_by=user_id 时直接生效。",
            "security": [{"cookieAuth": []}],
            "requestBody": {
                "required": True,
                "content": {"application/json": {"schema": {
                    "type": "object",
                    "required": ["entity_type", "field_key", "field_name", "field_type"],
                    "properties": {
                        "entity_type":  {"type": "string", "enum": ["thread", "todo", "faq_item", "workflow"]},
                        "field_key":    {"type": "string"},
                        "field_name":   {"type": "string"},
                        "field_type":   {"type": "string", "enum": ["text", "number", "date", "select", "boolean"]},
                        "group_id":     {"type": "string"},
                        "options":      {"type": "array", "items": {"type": "string"}, "description": "select 类型的选项"},
                        "suggested_by": {"type": "string"},
                    }
                }}}
            },
            "responses": {
                "201": {"description": "字段已定义", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/CustomFieldDefinition"}}}}
            }
        }
    },
    "/api/v1/custom-fields/{id}/adopt": {
        "post": {
            "tags": ["custom-fields"],
            "summary": "用户采纳管家推荐的字段",
            "security": [{"cookieAuth": []}],
            "parameters": [{"in": "path", "name": "id", "required": True, "schema": {"type": "string", "format": "uuid"}}],
            "responses": {
                "200": {"description": "字段已采纳", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/CustomFieldDefinition"}}}}
            }
        }
    },
    "/api/v1/{entity_type}/{entity_id}/custom-fields": {
        "get": {
            "tags": ["custom-fields"],
            "summary": "获取实体的自定义字段值",
            "security": [{"cookieAuth": []}],
            "parameters": [
                {"in": "path", "name": "entity_type", "required": True, "schema": {"type": "string", "enum": ["thread", "todo", "faq_item", "workflow"]}},
                {"in": "path", "name": "entity_id", "required": True, "schema": {"type": "string", "format": "uuid"}},
            ],
            "responses": {
                "200": {"description": "自定义字段值列表", "content": {"application/json": {"schema": {
                    "type": "object",
                    "properties": {"items": {"type": "array", "items": {"$ref": "#/components/schemas/CustomFieldValue"}}}
                }}}}
            }
        },
        "put": {
            "tags": ["custom-fields"],
            "summary": "设置实体的自定义字段值",
            "security": [{"cookieAuth": []}],
            "parameters": [
                {"in": "path", "name": "entity_type", "required": True, "schema": {"type": "string", "enum": ["thread", "todo", "faq_item", "workflow"]}},
                {"in": "path", "name": "entity_id", "required": True, "schema": {"type": "string", "format": "uuid"}},
            ],
            "requestBody": {
                "required": True,
                "content": {"application/json": {"schema": {
                    "type": "object",
                    "required": ["field_id", "value"],
                    "properties": {
                        "field_id": {"type": "string", "format": "uuid"},
                        "value":    {"type": "string"},
                    }
                }}}
            },
            "responses": {
                "200": {"description": "字段值已设置", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/CustomFieldValue"}}}}
            }
        }
    },
}

doc['paths'].update(new_paths)

# Add new tags
existing_tags = [t['name'] for t in doc.get('tags', [])]
for tag_name, tag_desc in [
    ("presence", "用户在线状态与离线消息推送"),
    ("extensions", "平台扩展机制（软能力/硬能力）"),
    ("workflows", "AI管家工作流托管与跨群任务分发"),
    ("custom-fields", "跟踪项自定义属性"),
]:
    if tag_name not in existing_tags:
        doc.setdefault('tags', []).append({"name": tag_name, "description": tag_desc})

with open('D:/RippleFlow/docs/03_api_reference.yaml', 'w', encoding='utf-8') as f:
    yaml.dump(doc, f, allow_unicode=True, default_flow_style=False, sort_keys=False)

print('03_api_reference.yaml updated')

# Validate
with open('D:/RippleFlow/docs/03_api_reference.yaml', 'r', encoding='utf-8') as f:
    doc2 = yaml.safe_load(f)
print(f'Paths: {len(doc2["paths"])} | Schemas: {len(doc2["components"]["schemas"])}')
