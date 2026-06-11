---
name: issue2merge
description: >
  Multi-agent fix loop that drives a GitHub issue from triage to merge-ready PR.
  Manager agent coordinates parallel Fix sub-agents, a Review sub-agent (four-axis
  Standards + Spec via the review skill), and CI Fix-Watch + Review-Fix-Watch (parallel). Iterates:
  fix → review → test → push → [ci-fix-watch + review-fix-watch parallel] → merge.
  Use when: (1) user says "fix issue #{N}" or "manager loop", (2) responding to
  PR review comments needing code changes, (3) fixing CI failures across
  multiple files, (4) user explicitly asks to use the fix-loop pattern.
---

# Issue2Merge — Manager Fix Loop

## Your Role: Manager Agent (orchestrate only, do not write code)

**⛔ HARD RULE: YOU are the manager. DO NOT spawn a sub-agent to be the manager.**

The agent that receives the user's request MUST act as the manager directly. Spawning a sub-agent to be the manager is forbidden. You may spawn sub-agents for Fix, Review, Test, CI-Fix-Watch, and Review-Fix-Watch roles, but the manager role stays on the current agent.

You are the commander of this fix loop. Your job:
1. Read the target Issue / PR Review
2. Categorize problems into groups (max {MAX_FIX_AGENTS})
3. Auto-create Branch + Draft PR
4. **Fix Sub-agents** (max {MAX_FIX_AGENTS}, one per group, parallel) — code repairs
5. **Review Sub-agent** (1) — four-axis audit (Standards + Spec + Lint + OCR)
6. **Test Sub-agent** (1) — writes integration tests
7. Review + Test both pass → Commit + Push
8. **CI Fix-Watch + Review-Fix-Watch** (2, parallel) — CI-FW monitors CI + Copilot review status, auto-fixes CI failures, **enables auto-merge only after both pass on latest SHA**. R-F-W handles Copilot notification + auto-fix loop.
9. Loop if needed: CI-FW handles CI failures inline, R-F-W handles its own fix loop
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
| `AUTO_MERGE` | (OBSOLETE — CI-FW handles auto-merge gate) | — |

## Derived automatically on init

| Variable | Derived From |
|----------|-------------|
| `BRANCH_NAME` = `fix-{ISSUE_NUMBER}-manager-loop` |
| `WORK_PATH` = `{REPO_PATH}` |
| `GH_TOKEN` = from `~/.openclaw/openclaw.json` env.vars.GH_TOKEN |
| `PLANNING_ROOT` = `/Users/tim_openclaw/.openclaw/workspace/skills/planning-with-files/scripts` | path to planning-with-files init scripts (resolved absolute path) |
| `REPO_OWNER` = first part of `{REPO_FULL}` before `/` | parsed from REPO_FULL |
| `REPO_NAME` = second part of `{REPO_FULL}` after `/` | parsed from REPO_FULL |

---

## Flow (high level)

```
0. Init: read issue → analyze → create branch + Draft PR → init planning files
1. Group problems into at most {MAX_FIX_AGENTS} groups (keep each group homogeneous)
2. Spawn Fix sub-agents in parallel → each takes one group
   └─ Fix agents run lightweight tests on affected modules before finishing
3. ⏳ Wait for ALL fix sub-agents → record retrospectives
4. 🚨 Spawn Review sub-agent → **four-axis audit (Standards + Spec + Lint + OCR)** via the `review` skill + `ocr` CLI
   └─ Standards: does code follow repo's documented coding standards?
   └─ Spec: does code match what the originating issue asked for?
   └─ Lint: ruff check on changed files — automated Python style/correctness
   └─ OCR: Alibaba open-code-review AI — line-level automated bug/security/quality review
   └─ Runs full test suite first, then runs OCR + triple-axis sub-agents in parallel
5. Review Decision:
   ├─ ALL FOUR axes PASS → Spawn Test Sub-agent
   └─ ANY axis FAIL → save feedback → **back to Step 2** with findings
       └─ Loop: fix → review → fix → review → until all three axes pass
       └─ Max 5 cycles total (step 13 protection)
6. 🧪 Spawn Test Sub-agent → writes integration tests covering the diff
   └─ Reads git diff → analyzes what to test → writes test file(s) → runs them
   └─ Test agent ONLY writes tests — does NOT modify fix code
   └─ Test FAIL (code bug discovered) → back to Step 2
   └─ Test PASS → proceed
7. ⛔ SELF-CHECK: Was Review dispatched AND four axes passed? Was Test agent dispatched AND passed?
8. ⛔ HARD GATE: Review + Tests both must pass. No push without PASS.
   git pull --rebase → commit -m "fix({ALL_ISSUES}): address issues from #{ALL_ISSUES}" → push
9. ⏳ Wait — CI Fix-Watch + Review-Fix-Watch run in parallel (spawned at Step 10)
   └─ CI Fix-Watch → polls every 60s: checks CI + R-FW Copilot signal file + PR merge state.
        Auto-fixes CI failures. **Enables auto-merge ONLY after BOTH CI ✅ AND R-FW signal file exists with matching SHA.**
        Uses file-based handshake to avoid race conditions with Copilot review timing.
        Ends when merged or 1h timeout.
   └─ Review-Fix-Watch → at startup: notify Copilot, then monitors + auto-fixes + replies +
        resolves + push + re-notify loop. **Writes Copilot-clean signal file when all threads resolved.**
        CI-FW reads this signal to know when auto-merge is safe.
        Runs until merge or timeout.

   **Signal file handshake (race condition fix):**
   R-FW writes:  `\$HOME/.openclaw/workspace/memory/{BRANCH_NAME}-copilot-clean.signal` (contains HEAD SHA)
   CI-FW reads:  checks file exists AND content matches HEAD SHA before enabling auto-merge
   This eliminates the race where CI-FW incorrectly treats "Copilot hasn't started" as "Copilot review clean."
10. Act on Combined Results (both agents complete or timeout):
   └─ CI merged → nothing to do (CI-FW gated both checks)
   └─ CI green + auto-merge enabled → waiting for merge
   └─ CI timeout + R-F-W clean → merge ready (check why CI-FW didn't enable auto-merge)
   └─ CI timeout + R-F-W partial remaining → escalate
   └─ both timeout → escalate
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

**0d. (removed — auto-merge gate):** Auto-merge is NOT set by the Manager. CI-FW handles enabling it only after BOTH CI ✅ AND Copilot review ✅ are confirmed on the latest commit SHA. See Step 10.

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
- Phase N+1: Review, Test, CI pass
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

### Step 4: Spawn Review Sub-agent (Four-Axis: Standards + Spec + Lint + OCR)

Use the **review** skill (`~/.openclaw/workspace/skills/review/SKILL.md`) plus the **open-code-review** (`ocr`) CLI. The review runs:

1. Full test suite (gate)
2. **OCR** — Alibaba open-code-review CLI, run inline on git diff for AI-powered bug/security/quality review
3. **Standards** — does the code follow this repo's documented coding standards? (parallel sub-agent)
4. **Spec** — does the code faithfully implement the originating issue / PRD? (parallel sub-agent)

OCR runs inline first, then Standards + Spec sub-agents run in parallel. Template: `references/review-agent-prompt.md`.

### Step 5: Review Decision — ⛔ HARD GATE (MANDATORY)

**Before any push, a Review sub-agent MUST be dispatched and ALL FOUR axes must PASS.**

- **ALL FOUR PASS** → Step 6 (Test Agent)
- **FAIL on any axis** → save findings to memory/, then back to Step 2 with findings. Fix agents address relevant violations before re-reviewing.
- **Multiple failures** → prioritize: Spec (correctness) > OCR (bug/security) > Standards (style/convention).

⛔ No exceptions. No shortcuts. All three axes must pass before proceeding to the Test agent.

### Step 6: Spawn Test Sub-agent

Template in `references/test-agent-prompt.md`.

The Test agent writes integration tests covering all code changes in this branch.
It does NOT modify fix code — changes are already validated by Review.

- **Test PASS** → Step 7 (Self-check)
- **Test FAIL (code bug)** → back to Step 2. The test discovered a bug that Review missed.
- **Test FAIL (test bug)** → Test agent self-corrects and re-runs (up to 3 attempts).

Save retrospective to `~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-test-round-{ROUND}.md`.

### Step 7: ⛔ SELF-CHECK — Was Review and Test Dispatched and Passed?

**BEFORE any push, you MUST pass this self-check. If you can't, you skipped review and MUST go back.**

```
SELF-CHECK:
[ ] Did I spawn a Review sub-agent in this cycle?
[ ] Did ALL FOUR axes (OCR + Standards + Spec + Lint) return PASS?
[ ] Did I spawn a Test sub-agent in this cycle?
[ ] Did the Test agent return PASS?
[ ] Are all review + test findings recorded in memory/ retro?

If ANY checkbox is NO → ⛔ STOP. Go back to the failed step. Do not push.
```

Only proceed if ALL checks pass.

### Step 8: Rebase + Commit + Push (⛔ GATE: Self-check passed)

```bash
cd {REPO_PATH}
git checkout {BRANCH_NAME}
git pull origin {BRANCH_NAME} --rebase
git add -A
git commit -m "fix({ALL_ISSUES}): address issues from #{ALL_ISSUES}"
git push origin {BRANCH_NAME}
```

Verify with `git diff HEAD --stat` before commit.

### Step 9: Copilot Re-review (handled by Review-Fix-Watch)

Copilot notification is handled entirely by the Review-Fix-Watch agent:
- **At startup**: notifies Copilot for initial review on the branch
- **After each fix+push**: re-notifies Copilot for re-review

Proceed to Step 10 to spawn both watch agents.

### Step 10: Spawn CI Fix-Watch + Review-Fix-Watch (Parallel)

Spawn **two** sub-agents simultaneously. They run independently in parallel:

**CI Fix-Watch** — monitors CI status + Copilot review status + PR merge state, polls every 60s.
Auto-fixes CI failures. Enables auto-merge ONLY after BOTH CI ✅ and Copilot review ✅ are confirmed on the latest commit SHA.
Ends when PR merged or 1 hour timeout.

**Review-Fix-Watch** — monitors Copilot inline comments + PR merge state, auto-fixes + replies +
resolves + pushes + re-notifies Copilot, loops **until merge or timeout** (does NOT stop early).
Includes comment dedup (checks commit_id vs branch HEAD), escalation for non-trivial fixes.

```javascript
// CI Fix-Watch agent
sessions_spawn({
  task: `[use references/ci-fix-watch-agent-prompt.md content with variables filled]`,
  cwd: "{REPO_PATH}",
  runtime: "subagent",
  mode: "run"
})

// Review-Fix-Watch agent
sessions_spawn({
  task: `[use references/review-fix-watch-agent-prompt.md content with variables filled]`,
  cwd: "{REPO_PATH}",
  runtime: "subagent",
  mode: "run"
})
```

⚠️ Both agents: timeout = 3600s (1 hour).

### Step 11: Act on Combined Results

Wait for **both** agents to report back (or timeout). Then combine results:

| CI Fix-Watch Result | Review-Fix-Watch Result | Action |
|---------------------|------------------------|--------|
| `merged` | any | ✅ PR already merged! CI-FW handled auto-merge gating. Nothing to do. |
| CI green + clean 
  + auto-merge enabled | `all_comments_resolved` / `no_comments_ever` | ✅ CI-FW already enabled auto-merge. Wait for merge to complete. |
| CI green + clean
  (auto-merge NOT yet enabled) | `all_comments_resolved` / `no_comments_ever` | ⚠️ CI-FW timed out before enabling auto-merge. Manually enable:
```bash
gh pr merge {PR_NUMBER} --auto --squash
``` |
| any | `escalation_needed` | ⚠️ Check escalation file. Handle escalated issues. Then re-spawn CI-FW + R-F-W. |
| `timeout` | `timeout` | ⚠️ Both timed out. Escalate to {PERSON}. |

**Close associated issues after merge:**
```bash
IFS=',' read -ra ISSUES <<< "{ALL_ISSUES}"
for iss in "${ISSUES[@]}"; do
  gh issue close "$iss" --comment "Closed by PR #${PR_NUMBER}"
done
```
Report: "PR #{PR_NUMBER} auto-merged + {count_of_all_issues} issues closed 🚀"

### Step 11.5: Merge Watch (safety buffer before merge)

After CI Fix-Watch + Review-Fix-Watch are clean, spawn a Merge Watch sub-agent
for a **120-second safety buffer** before merging. This confirms no new Copilot
review arrives during the buffer window.

**Escalation handling:** Before spawning Merge Watch, check for escalation file:
```bash
ls ~/.openclaw/workspace/memory/*-rfw-escalation.md 2>/dev/null
```
If escalation file exists → read it, handle the non-trivial fix (via Fix sub-agent),
then re-spawn CI Fix-Watch + Review-Fix-Watch.

```javascript
sessions_spawn({
  task: `[use references/merge-watch-agent-prompt.md content with variables filled]`,
  cwd: "{REPO_PATH}",
  runtime: "subagent",
  mode: "run"
})
```

⚠️ Agent timeout: 1800s (30 minutes).

### Merge Watch results:
| Status | Action |
|--------|--------|
| `merged` | ✅ Done. Report success. |
| `merge_ready` | Safe to merge. If CI-FW didn't enable auto-merge, run `gh pr merge {PR_NUMBER} --auto --squash`. |
| `timeout` | ⚠️ 30 min buffer expired. Check PR manually. |

### Step 12: Post-Cycle Fix Loop (fallback — manual Copilot fixes)

**Used only when Review-Fix-Watch was not deployed** (e.g., COPILOT_ENABLED was false
but Copilot comments still appeared). Normal path goes through Step 10 review-fix-watch.

When this fallback is needed:

```
12.1: Fix Copilot comments (via Fix sub-agent or direct edit for trivial changes)
12.2: Reply to EVERY Copilot thread via GraphQL addPullRequestReviewThreadReply
12.3: Resolve EVERY thread via GraphQL resolveReviewThread
12.4: Commit + push
12.5: Re-notify Copilot: gh pr edit {PR_NUMBER} --add-reviewer @copilot
12.6: Re-spawn CI Fix-Watch + Review-Fix-Watch (parallel, same as Step 10)
```

**Rules:**
- Trivial fixes (locale codes, docstrings, test assertions, docs) → manager CAN fix directly via edit tool
- Logic changes or multi-file fixes → MUST use a Fix sub-agent
- Every reply MUST be via GraphQL (not REST comments API)
- Every push MUST be followed by re-spawning CI Fix-Watch + Review-Fix-Watch
- Max 10 fallback iterations
- Save retrospective per iteration: `memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-copilot-fix-round-{N}.md`

### Step 13: Loop Protection

- Max 5 full cycles total (Step 2→4→6→8→9→10→11)
- Review-Fix-Watch internal loop: built-in loop until merge or 1h timeout
- Post-cycle fallback (Step 12): max 10 iterations
- Same problem unresolved after 3 full cycles → escalate to {PERSON}
- CI Fix-Watch timeout (>1 hour) → escalate
- Same CI failure 3× → escalate
- **Escalation file**: If R-F-W writes to `memory/*-rfw-escalation.md`, the manager MUST read it and handle before Merge Watch

---

## Reference Files

### Sub-agent Prompt Templates (loaded at respective steps)

| File | Sub-agent | When to Load |
|------|-----------|-------------|
| `references/fix-agent-prompt.md` | **Fix Sub-agent** — parallel code repair | Step 2 — spawn one per group (up to {MAX_FIX_AGENTS}) |
| `references/review-agent-prompt.md` | **Review Sub-agent** — four-axis (OCR + Standards + Spec + Lint) via review skill + ocr CLI | Step 4 — spawned once per loop cycle |
| `references/test-agent-prompt.md` | **Test Sub-agent** — integration tests for diff | Step 6 — spawned after Review passes |
| `references/ci-fix-watch-agent-prompt.md` | **CI Fix-Watch Sub-agent** — CI monitoring + auto-fix + merge detection | Step 10 — spawned in parallel with Review-Fix-Watch |
| `references/review-fix-watch-agent-prompt.md` | **Review-Fix-Watch Sub-agent** — auto-fix Copilot comments, loop until merge, dedup, escalation | Step 10 — spawned in parallel with CI Fix-Watch |
| `references/merge-watch-agent-prompt.md` | **Merge Watch Sub-agent** — 120s safety buffer, then auto-merge or report ready | Step 11.5 — spawned after CI+R-F-W both clean |
| `references/lessons.md` | **Lessons learned** from past runs | Step 10/11 — read for guidance |

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
| Test | `~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-test-round-{ROUND}.md` | `2026-05-14-22-49-384-test-round-1.md` |
| CI Fix-Watch | `~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-ci-fix-watch.md` | `2026-06-04-11-40-61-ci-fix-watch.md` |
| Review-Fix-Watch | `~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-review-fix-watch.md` | `2026-06-04-11-40-61-review-fix-watch.md` |
| Copilot Fix (fallback) | `~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-copilot-fix-round-{N}.md` | `2026-06-02-15-11-881-copilot-fix-round-2.md` |

## Communication Rules

- Report progress after each major step
- Escalate blockers immediately
- Final message: "{PERSON}, PR #{PR_NUMBER} is ready to merge! [summary of changes]"
