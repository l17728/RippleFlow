# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RippleFlow is a group chat knowledge base system that transforms chat history into a queryable, living knowledge base. The architecture separates **mechanism** (RippleFlow platform) from **strategy** (nullclaw AI agent).

```
RippleFlow Platform (mechanism)     nullclaw Agent (strategy)
─────────────────────────────      ─────────────────────────
• REST API + CLI commands          • Routine scripts
• Database (SQLite/PostgreSQL)     • LLM decision-making
• Message processing pipeline       • Self-reflection & learning
• No business logic               • All intelligent behavior
```

## Repository Structure

```
RippleFlow/
├── docs/                    # Architecture & API documentation
│   ├── 00_overview.md       # Start here - system overview
│   ├── 01_system_architecture.md
│   ├── 02_database_ddl.sql  # PostgreSQL schema
│   ├── 02b_database_ddl_sqlite.sql
│   ├── 03_api_reference.yaml
│   ├── 04_service_interfaces.md
│   ├── 08_ai_butler_architecture.md
│   └── plans/
│       └── nullclaw-integration-config.md  # nullclaw integration
│
├── nullclaw-main/           # nullclaw AI agent runtime (Zig)
│   ├── CLAUDE.md            # Zig build/test commands
│   └── src/                 # nullclaw source code
│
└── AGENTS.md                # Agent development guidelines
```

## Key Documents to Read

| Document | Purpose |
|----------|---------|
| `docs/00_overview.md` | System overview, core value proposition |
| `docs/01_system_architecture.md` | Architecture, data flow, deployment |
| `docs/plans/nullclaw-integration-config.md` | nullclaw integration design |
| `nullclaw-main/CLAUDE.md` | Zig build commands and conventions |

## CLI Commands (RippleFlow Platform)

The `rf` CLI is the primary interface for nullclaw to interact with RippleFlow:

```bash
rf help                           # List all commands
rf <command> --help               # Command details
rf threads list --category qa_faq # List threads
rf threads search "Redis配置"      # Search threads
rf qa "如何配置连接池"             # Smart Q&A
rf todos list --overdue           # List overdue todos
rf sensitive pending              # Pending authorizations
rf butler digest --type daily     # Generate daily digest
```

## nullclaw Build Commands

See `nullclaw-main/CLAUDE.md` for complete details. Essential commands:

```bash
cd nullclaw-main

# Build (requires Zig 0.15.2)
zig build                           # dev build
zig build -Doptimize=ReleaseSmall   # release (< 1 MB)

# Test
zig build test --summary all         # run all tests

# Format
zig fmt src/                         # format source
```

## Architecture Principles

1. **Strategy/Mechanism Separation**: RippleFlow exposes capabilities via CLI/API; nullclaw decides when/how to use them.

2. **nullclaw Native Capabilities** (use these, don't reinvent):
   - `channels` - Event reception (replaces custom event bus)
   - `memory` - Three-layer memory with auto-compaction
   - `cron` - Scheduled task execution (replaces Celery Beat)
   - `tools` - shell_execute, http_request, file_read/write
   - `security` - Pairing verification, audit logging
   - `autonomy` - Self-control and cost management

3. **Event Flow**: RippleFlow → HTTP POST → nullclaw gateway → channels → Agent processing

## Tech Stack

| Component | Technology |
|-----------|------------|
| Platform API | FastAPI (Python) |
| Database | SQLite (light) or PostgreSQL (high-concurrency) |
| AI Agent | nullclaw (Zig 0.15.2) |
| LLM | GLM-4-Plus (Zhipu AI) |
| Frontend | Vue 3 |
| Cache | Memory cache or Redis (optional) |

## Development Workflow

1. **Read documentation first**: Start with `docs/00_overview.md`
2. **nullclaw changes**: Follow `nullclaw-main/CLAUDE.md` conventions
3. **API changes**: Update `docs/03_api_reference.yaml`
4. **Database changes**: Update both `02_database_ddl.sql` and `02b_database_ddl_sqlite.sql`
5. **Commit**: Use conventional commits (feat:, docs:, refactor:, etc.)

## Information Categories (9 built-in)

`tech_decision`, `qa_faq`, `bug_incident`, `reference_data`, `action_item`, `discussion_notes`, `knowledge_share`, `env_config`, `project_update`

## Language

- **与用户交流**：默认使用中文（简体）回复，除非涉及纯英文代码或文档
- Documentation is primarily in Chinese. Code comments and API names in English.

## Workflow（工作流约定）

- **收到"继续"时**：先用 `TaskList` 检查未完成任务，或查看最近 `git log --oneline -5` 了解进度，直接接续未完成的工作，无需询问
- **多步骤任务**：每完成一个子任务后立即 commit（`feat:/fix:/docs:` 前缀），再继续下一个，确保中断后工作不丢失
- **任务追踪**：对于 3 步以上的任务使用 TaskCreate/TaskUpdate 拆分子任务并跟踪进度