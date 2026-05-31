---
name: issue2merge
description: >
  Multi-agent fix loop that drives a GitHub issue from triage to merge-ready PR.
  Manager agent coordinates parallel Fix sub-agents, a Review sub-agent (dual-axis
  Standards + Spec via the review skill), and a Watch sub-agent. Iterates:
  fix → review → fix issues → review again → until both axes pass.
  Use when: (1) user says "fix issue #{N}" or "manager loop", (2) responding to
  PR review comments needing code changes, (3) fixing CI failures across
  multiple files, (4) user explicitly asks to use the fix-loop pattern.
---

# Issue2Merge — Manager Fix Loop

## Your Role: Manager Agent (orchestrate only, do not write code)

You are the commander of this fix loop. Your job:
1. Read the target Issue / PR Review
2. Categorize problems into groups (max {MAX_FIX_AGENTS})
3. Auto-create Branch + Draft PR
4. **Fix Sub-agents** (max {MAX_FIX_AGENTS}, one per group, parallel) — code repairs
5. **Review Sub-agent** (1) — audits all changes
6. On pass → Commit + Push
7. Notify Copilot for re-review (if enabled)
8. **Watch Sub-agent** (1) — monitors CI + review comments
9. Loop if needed (max 5 cycles)
10. Report when merge-ready

---

## Parameters (prompted or read from context)

| Variable | Description | Default |
|----------|-------------|---------|
| `PERSON` | Who to report to | Tim |
| `REPO_PATH` | Local project path | `Git-Repository/161-happy-land` |
| `REPO_FULL` | GitHub `owner/repo` | TimK42/161-happy-land |
| `ISSUE_NUMBER` | Source issue # | *(required)* |
| `ALL_ISSUES` | Comma-separated list of all issues in this PR | `{ISSUE_NUMBER}` |
| `COPILOT_ENABLED` | Enable Copilot review kickoff? | true |
| `AUTO_MERGE` | Auto-merge PR when CI passes? | false |

## Derived automatically on init

| Variable | Derived From |
|----------|-------------|
| `BRANCH_NAME` = `fix-{ISSUE_NUMBER}-manager-loop` |
| `WORK_PATH` = `{REPO_PATH}` |
| `GH_TOKEN` = from `~/.openclaw/openclaw.json` env.vars.GH_TOKEN |
| `PLANNING_ROOT` = `/Users/tim_openclaw/.openclaw/workspace/skills/planning-with-files/scripts` | path to planning-with-files init scripts (resolved absolute path) |

---

## Flow (high level)

```
0. Init: read issue → analyze → create branch + Draft PR → init planning files
1. Group problems into at most {MAX_FIX_AGENTS} groups (keep each group homogeneous)
2. Spawn Fix sub-agents in parallel → each takes one group
   └─ Fix agents run lightweight tests on affected modules before finishing
3. ⏳ Wait for ALL fix sub-agents → record retrospectives
4. 🚨 Spawn Review sub-agent → **dual-axis audit (Standards + Spec)** via the `review` skill
   └─ Standards: does code follow repo's documented coding standards?
   └─ Spec: does code match what the originating issue asked for?
   └─ Runs full test suite + reviews all changes
5. Review PASS on BOTH axes? → proceed to step 6
6. Review FAIL on EITHER axis? → save feedback → **back to Step 2** with findings
   └─ Loop: fix → review → fix → review → until both axes pass
   └─ Max 5 cycles total (step 12 protection)
7. ⛔ SELF-CHECK: Was review dispatched AND passed? If NO → back to Step 4.
8. ⛔ HARD GATE: Both axes must pass. No push without PASS.
   git pull --rebase → commit (ALL_ISSUES) → push
9. [If COPILOT_ENABLED] gh pr edit --add-reviewer @copilot
10. Spawn Watch sub-agent → monitor CI + review threads
   └─ Copilot error does NOT block pipeline; CI status takes priority.
   ┌─ CI fail or new fix comments? → back to step 2
   └─ All clear → report {PERSON}: Ready to merge 🎉
11. Act on Watch Result:
   └─ ready_to_merge → merge + close ALL_ISSUES (both AUTO_MERGE=true/false)
   └─ copilot_error → don't block; follow CI status
   └─ ci_failed / needs_fix → back to step 2
   └─ waiting → escalate
```

---

## Step Details

### Step 0: Init

**0a. Read issue:**
```bash
GH_TOKEN=$(cat ~/.openclaw/openclaw.json | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('env',{}).get('vars',{}).get('GH_TOKEN',''))")
curl -s -H "Authorization: token $GH_TOKEN" \
  "https://api.github.com/repos/{REPO_FULL}/issues/{ISSUE_NUMBER}" | jq '.body'
```

Analyze: problem count, files mentioned, severity, source (Copilot review / manual / other).

**0b. Classify:** Group by file, type, or severity. See `references/grouping.md`.

**0c. ⛔ Check main branch CI health:** Before anything else, check if main CI is already red.

```bash
cd {REPO_PATH}
gh run list --branch main --limit 3 --json conclusion,status,displayTitle --jq '.[] | select(.status == "completed") | {conclusion, displayTitle}'
```

If the most recent completed run on main has `conclusion: "failure"`, notify {PERSON}:
> ⚠️ `{REPO_FULL}` main branch CI is currently **red** (last run: _{displayTitle}_). Future PRs will fail on merge. Fix main CI first before proceeding, or confirm you want to continue anyway?

If user says fix main first → exit. If user says continue → proceed.

**0d. Ask about auto-merge:** Ask {PERSON}:
> Auto-merge PR when CI passes? (y/N)

Set `AUTO_MERGE=true` if yes, `false` otherwise. Used in Step 10 (Act on Watch Result).

**0e. Ask max fix sub-agents:** Ask {PERSON}:
> How many parallel fix sub-agents? (1-4, default 3)

Set `MAX_FIX_AGENTS` (1-4). Controls problem grouping and parallel agents.

**0f. Create branch + Draft PR:** Run `scripts/init_branch.sh {REPO_PATH} {ALL_ISSUES} {BRANCH_NAME} {REPO_FULL}`

Capture PR_NUMBER from output. All subsequent steps use this PR number.

**0g. Init planning files (optional — skip if planning-with-files not installed):** Creates a `.planning/` directory with persistent working memory for this fix loop. This helps the Manager and sub-agents survive context resets.

```bash
cd {REPO_PATH}
PLANNING_ROOT="/Users/tim_openclaw/.openclaw/workspace/skills/planning-with-files/scripts"
if [ -d "$PLANNING_ROOT" ]; then
  bash "$PLANNING_ROOT/init-session.sh" --plan-dir "fix-issue-${ISSUE_NUMBER}"
  echo "[planning-with-files] initialized"
else
  echo "[planning-with-files] not installed — skipping Step 0g"
fi
```

After init, populate `task_plan.md` with actual phases from the issue analysis:
- Phase 1: Read & Analyze (0a-0b already done, mark `complete`)
- Phase 2-N: One phase per fix group from Step 1 (mark first as `in_progress`)
- Phase N+1: Review & CI pass
- Phase N+2: Merge & Close

Also populate `findings.md` with the issue analysis results (problem description, files mentioned, severity).

Planning files persist across context resets, /compact, and sub-agent sessions. Hooks auto-inject plan context on every message.

### Step 1: Group Problems

Output format:
```
=== GROUPING ===
Group A: ({files}) — {N} issues — #{issue_number}
Group B: ...
... (up to {MAX_FIX_AGENTS} groups)
=== END GROUPING ===
```

### Step 2: Spawn Fix Sub-agents

For each group, spawn a sub-agent. Template in `references/fix-agent-prompt.md`.

```javascript
sessions_spawn({
  task: `[use reference/fix-agent-prompt.md content with variables filled]`,
  cwd: "{REPO_PATH}",
  runtime: "subagent",
  mode: "run"
})
```

⚠️ Fix agents: timeout = 0 (never timeout).

### Step 3: Wait & Record

- Poll `subagents list` for completion
- Save each sub-agent's retrospective → ~/.openclaw/workspace/memory/
- All done → Step 4

### Step 4: Spawn Review Sub-agent (Dual-Axis)

Use the **review** skill (`~/.openclaw/workspace/skills/review/SKILL.md`) instead of the old code-review skill. The review runs TWO axes in parallel sub-agents:

**Standards** — does the code follow this repo's documented coding standards?
**Spec** — does the code faithfully implement the originating issue / PRD?

Template in `references/review-agent-prompt.md`.

### Step 5: Review Decision — ⛔ HARD GATE (MANDATORY)

**Before any push, a Review sub-agent MUST be dispatched and BOTH axes must PASS.**

- **BOTH PASS** → Step 6
- **FAIL on Standards axis** → save findings to ~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-review-round-{N}.md → back to Step 2 with enriched fix instructions. Fix agents MUST address the Standards violations before re-reviewing.
- **FAIL on Spec axis** → same process. Fix agents adjust implementation to match the spec.
- **FAIL on both** → prioritize Spec fixes (they affect correctness) over Standards (they affect style).

⛔ No exceptions. No shortcuts. Both axes must pass before any push.

### Step 6: ⛔ SELF-CHECK — Was Review Dispatched and Passed?

**BEFORE any push, you MUST pass this self-check. If you can't, you skipped review and MUST go back.**

```
SELF-CHECK:
[ ] Did I spawn a Review sub-agent in this cycle?
[ ] Did BOTH axes (Standards + Spec) return PASS?
[ ] Are all review findings recorded in memory/ retro?

If ANY checkbox is NO → ⛔ STOP. Go back to Step 4. Do not push.
```

Only proceed if ALL checks pass.

### Step 7: Rebase + Commit + Push (⛔ GATE: Self-check passed)

```bash
cd {REPO_PATH}
git checkout {BRANCH_NAME}
git pull origin {BRANCH_NAME} --rebase
git add -A
git commit -m "fix({ALL_ISSUES}): address issues from #{ALL_ISSUES}"
git push origin {BRANCH_NAME}
```

Verify with `git diff HEAD --stat` before commit.

### Step 8: Copilot Re-review

If COPILOT_ENABLED = true:
```bash
gh pr edit {PR_NUMBER} --add-reviewer @copilot
```

### Step 9: Watch

Template in `references/watch-agent-prompt.md`.

### Step 10: Act on Watch Result

| Result | Action |
|--------|--------|
| `ready_to_merge` | If `AUTO_MERGE=true` (from Step 0d answer):
  ```bash
  cd {REPO_PATH}
  git checkout main && git pull origin main
  gh pr merge {PR_NUMBER} --squash --delete-branch
  git pull origin main
  ```
  Close all associated issues:
  ```bash
  IFS=',' read -ra ISSUES <<< "{ALL_ISSUES}"
  for iss in "${ISSUES[@]}"; do
    gh issue close "$iss" --comment "Closed by PR #${PR_NUMBER}"
  done
  ```
  Report: "PR #{PR_NUMBER} auto-merged + {count_of_all_issues} issues closed 🚀"
  Otherwise (AUTO_MERGE=false):
  ```bash
  gh pr ready {PR_NUMBER}
  ```
  Report {PERSON}: "PR #{PR_NUMBER} is ready to merge! Run `gh pr merge {PR_NUMBER} --squash --delete-branch` when ready."
  Then close all associated issues:
  ```bash
  IFS=',' read -ra ISSUES <<< "{ALL_ISSUES}"
  for iss in "${ISSUES[@]}"; do
    gh issue close "$iss" --comment "Closed by PR #${PR_NUMBER}"
  done
  ``` |
| `ci_failed` | Log errors → back to Step 2 |
| `needs_fix` | Reply + resolve threads → back to Step 2 |
| `copilot_error` | Copilot review failed (error/rate limit). **Do NOT block pipeline.** CI status takes priority. If CI is passing → treat as `ready_to_merge`. If CI is failing → treat as `ci_failed`. Notify {PERSON} optionally: "Copilot review unavailable on PR #{PR_NUMBER} (rate limit/error). Django CI is still valid."
| `waiting` | Watch timed out (30 min). Escalate to {PERSON}: "Watch timed out on PR #{PR_NUMBER} after 30 min — please check manually." |

### Step 12: Loop Protection

- Max 5 cycles total
- Same problem unresolved after 3 cycles → escalate to {PERSON}
- Watch timeout (>30 min) → escalate
- Same CI failure 3× → escalate

---

## Reference Files

### Sub-agent Prompt Templates (loaded at respective steps)

| File | Sub-agent | When to Load |
|------|-----------|-------------|
| `references/fix-agent-prompt.md` | **Fix Sub-agent** — parallel code repair | Step 2 — spawn one per group (up to {MAX_FIX_AGENTS}) |
| `references/review-agent-prompt.md` | **Review Sub-agent** — dual-axis (Standards + Spec) via review skill | Step 4 — spawned once per loop cycle |
| `references/watch-agent-prompt.md` | **Watch Sub-agent** — CI + comments monitor | Step 9 — spawned once |

### Manager Reference Guide

| File | Purpose | When to Load |
|------|---------|-------------|
| `references/grouping.md` | Problem classification strategy for Manager | Step 1 — Manager reads to decide grouping |

Load each reference only when you reach the corresponding step. Do not pre-load all of them.

---

## Memory — Save Retrospectives

Every sub-agent MUST save its retrospective to `~/.openclaw/workspace/memory/` after completing:

| Sub-agent | File pattern | Example |
|-----------|-------------|---------|
| Fix Group A | `~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-fix-group-A.md` | `2026-05-14-22-49-384-fix-group-A.md` |
| Fix Group B | `~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-fix-group-B.md` | `2026-05-14-22-49-384-fix-group-B.md` |
| Fix Group C | `~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-fix-group-C.md` | `2026-05-14-22-49-384-fix-group-C.md` |
| Fix Group D | `~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-fix-group-D.md` | `2026-05-14-22-49-384-fix-group-D.md` |
| Review | `~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-review-round-{N}.md` | `2026-05-14-22-49-384-review-round-1.md` |
| Watch | `~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-watch-round-{N}.md` | `2026-05-14-22-49-384-watch-round-1.md` |

The Manager tracks round numbers for Review and Watch (increment each loop cycle).

## Communication Rules

- Report progress after each major step
- Escalate blockers immediately
- Final message: "{PERSON}, PR #{PR_NUMBER} is ready to merge! [summary of changes]"
