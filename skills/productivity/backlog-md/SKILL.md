---
name: backlog-md
description: Manage deferred tasks via memory/backlog.md. Pure file-based, no GitHub. Use when user says "backlog", "show backlog", or references BK-XXX tasks.
---

# Backlog Skill

Manage deferred tasks using a single file: `memory/backlog.md`.
**No GitHub. No API calls. Pure local files.**

## When to Activate

Activate when the user:
- Says "backlog" or "待辦" (Chinese)
- References a task by ID: "BK-003"
- Says "show backlog", "my backlog", or "我的 backlog 有什麼"

## File Location

**Always read/write from:** `memory/backlog.md` (relative to workspace)
- Workspace: `/Users/tim_openclaw/.openclaw/workspace/memory/backlog.md`
- **Do NOT** search GitHub Issues
- **Do NOT** guess from context or daily notes

## Workflow

### 1. Add to Backlog (放 backlog)

When user says "put this in backlog" or similar:

1. Read `memory/backlog.md` (create if missing)
2. Find next available BK-XXX number (max existing + 1)
3. Append to `## Deferred` section:

```markdown
- **BK-XXX** | [Task title]
  - Added: YYYY-MM-DD | Priority: P0-P3 (estimate)
```

4. Reply with confirmation: "已記 BK-XXX — [brief description]"

### 2. Show Backlog (show backlog)

When user asks to see their backlog:

1. Read `memory/backlog.md`
2. List only `## Deferred` + `## In Progress` sections
3. Sort by priority (P0 > P1 > P2 > P3)
4. Show format:

```markdown
## Deferred (待處理)
- **BK-001** | [title] — Added: YYYY-MM-DD (P2)

## In Progress (進行中)
- **BK-003** | [title] — Started: YYYY-MM-DD (P1)
```

### 3. Start Task (做 BK-XXX)

When user says "do BK-XXX" or similar:

1. Read `memory/backlog.md`
2. Move the task from `## Deferred` to `## In Progress`
3. Add `Started: YYYY-MM-DD` line
4. Begin executing the task

### 4. Complete Task (done BK-XXX)

When user says "BK-XXX is done" or similar:

1. Read `memory/backlog.md`
2. Move the task from `## In Progress` to `## Archived`
3. Add `Done: YYYY-MM-DD` line

## File Template (create if missing)

```markdown
# Backlog — memory/backlog.md

## Deferred (待處理)
_(empty)_

## In Progress (進行中)
_(empty)_

## Archived (已完成)
_(empty)_
```

## Rules

- **Only read/write `memory/backlog.md`** — never GitHub, never other files
- **BK-XXX numbering is sequential** — always use next available number
- **Priority estimation:** P0 (urgent) > P1 (important) > P2 (normal) > P3 (nice-to-have)
- **If file doesn't exist:** Create it with the template above, then add the task
