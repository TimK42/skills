# Backlog MD — Pure File-Based Task Management

A lightweight, file-based backlog management skill for OpenClaw. No GitHub, no API calls — just plain Markdown files.

## Features

- **Pure file-based** — All tasks stored in `memory/backlog.md`
- **No external dependencies** — No API calls, no GitHub Issues
- **Sequential numbering** — Automatic BK-XXX task IDs
- **Priority system** — P0 (urgent) to P3 (nice-to-have)
- **Three states** — Deferred → In Progress → Archived

## Installation

### Option 1: Manual Install (Recommended)

```bash
# The skill is already installed at:
~/.openclaw/workspace/skills/backlog-md/

# Restart your gateway to activate:
openclaw gateway restart
```

### Option 2: Install via CLI (if published to ClawHub)

```bash
openclaw skills install backlog-md
```

## Usage

### Add to Backlog (放 backlog)

```
You:  "這個放 backlog — 修 image model"
Agent: "已記 BK-003 | 修 image model — P2"
```

### Show Backlog (show backlog)

```
You:  "我的 backlog 有什麼？"
Agent: Lists all Deferred + In Progress tasks, sorted by priority
```

### Start Task (做 BK-XXX)

```
You:  "做 BK-003"
Agent: Moves task from Deferred → In Progress, begins execution
```

### Complete Task (done BK-XXX)

```
You:  "BK-003 done"
Agent: Moves task from In Progress → Archived with completion date
```

## File Structure

```
skills/backlog-md/
├── SKILL.md          # Core workflow instructions (loaded by OpenClaw)
└── README.md         # This file — installation and usage guide

memory/backlog.md     # Active backlog data (created automatically)
```

## Backlog File Format

Tasks are stored in `memory/backlog.md` with three sections:

```markdown
# Backlog — memory/backlog.md

## Deferred (待處理)
- **BK-XXX** | [Task title]
  - Added: YYYY-MM-DD | Priority: P0-P3

## In Progress (進行中)
- **BK-XXX** | [Task title] — Started: YYYY-MM-DD (P2)

## Archived (已完成)
- **BK-XXX** | [Task title] — Added: YYYY-MM-DD | Done: YYYY-MM-DD
```

## Priority Guide

| Priority | Meaning | Example |
|----------|---------|---------|
| **P0** | Urgent — Blocker | System down, critical bug |
| **P1** | Important — Should fix | Missing feature, major UX issue |
| **P2** | Normal — Nice to have | Enhancement, optimization |
| **P3** | Low — When convenient | Cosmetic, documentation |

## Rules

1. **Only read/write `memory/backlog.md`** — Never GitHub, never other files
2. **Sequential numbering** — Always use next available BK-XXX number
3. **Priority estimation** — Assign P0-P3 when creating tasks
4. **File auto-creation** — If `memory/backlog.md` doesn't exist, create it with template

## Comparison: Backlog MD vs Other Solutions

| Feature | Backlog MD | GitHub Issues | OpenViking | Mem0 |
|---------|-----------|---------------|------------|------|
| **Storage** | Local Markdown | GitHub API | SQLite + LLM | Cloud API |
| **Token Cost** | Zero | API calls | Moderate (LLM) | High (API) |
| **Setup** | None (built-in) | Create repo | Install service | Configure API |
| **Privacy** | 100% local | Public/GitHub | Local | Cloud-dependent |
| **Best For** | Personal agents | Team projects | Research | Multi-app |

## License

MIT — Free for personal or commercial use.
