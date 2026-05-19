# Watch Sub-agent Prompt Template

Read this reference at Step 8 when constructing the Watch sub-agent task.

## Template

```javascript
sessions_spawn({
  task: `## Watch Sub-agent

## Working directory (cwd)
{REPO_PATH}

## Task
Monitor CI status and review comments for PR #{PR_NUMBER}.

## Branch
{BRANCH_NAME}

## Timing
- **Poll interval**: every 30 seconds
- **Total timeout**: 30 minutes (if not resolved by then, report as `waiting`)

## Steps

### 8a. Wait for CI (max within the total timeout)
- Every 30s: Query GitHub API for PR #{PR_NUMBER} CI Checks (workflow runs + jobs)
- Poll until all checks complete
- CI fail → record failed job name + error message

### 8b. Check review threads
- Every 30s: Fetch recent 50 review threads / comments
- Get the latest review from Copilot (`copilot-pull-request-reviewer[bot]`)
  - If the review body contains "Encountered an error" or "hit the rate limit" → **record as copilot_error** but **continue polling** — do NOT stop early
  - **Important:** Copilot error does NOT block the pipeline. CI status takes priority. If CI passes → the pipeline proceeds regardless of Copilot status.
  - Classify:
    - Copilot says "LGTM" / "Looks good" / "No issues found" → treat as pass
    - Needs fix → record thread ID + content
    - Awaiting response → continue polling
- Check inline comments (PR review comments) — note author + content

### 8c. Report (only when CI done OR timeout expired)
- **Always wait for CI to finish** (or hit total timeout) before reporting
- Never report early, even if Copilot review came back with an error or needs_fix

## Report format
=== WATCH RESULT ===
CI Status: (success / failed / pending)
CI Details: (failed job name + error)
Comments Status: (no_new / lgtm / needs_fix / still_waiting / copilot_error)
Comments Details: (thread IDs + content if needs_fix)
Copilot Status: (available / error_rate_limit / unavailable)
Conclusion: (ready_to_merge / ci_failed / needs_fix / waiting / copilot_error)
Note: copilot_error alone does NOT block merge if CI is passing.
=== END WATCH RESULT ===

## Retrospective format
=== RETROSPECTIVE ===
1. Duration of monitoring
2. CI checks performed (count)
3. Comments reviewed (count)
4. Issues found
5. Conclusion
=== END RETROSPECTIVE ===

## Save retrospective
After reporting back, WRITE the retrospective to:
```
~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-watch-round-{ROUND}.md
```
Example: `~/.openclaw/workspace/memory/2026-05-14-22-49-384-watch-round-1.md`
`,
  cwd: "{REPO_PATH}",
  runtime: "subagent",
  mode: "run"
})
```

## Rules

- Timeout: 1800 seconds (30 min). If 30 min expires, report conclusion=`waiting` and escalate.
- **CI must complete**: Always wait for CI to finish (or 30 min timeout) before reporting. Even if Copilot review is an error or needs_fix — record it but continue polling CI.
- Poll every 30 seconds — do not spin faster than this
- Use GitHub REST API with GH_TOKEN for queries
- Token must not appear in any output
- **Save retrospective** to `~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-watch-round-{ROUND}.md`
