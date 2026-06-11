# CI Watch Sub-agent Prompt Template ⛔ DEPRECATED

**Replaced by `ci-fix-watch-agent-prompt.md`.** This file is kept for reference only.

Old CI Watch was a passive monitor (CI only, 30s poll, 30 min timeout).
New CI Fix-Watch: auto-fixes CI failures, checks PR merge state, 60s poll, 1 hour timeout.

Read `ci-fix-watch-agent-prompt.md` at Step 10 instead.

## Template

```javascript
sessions_spawn({
  task: `## CI Watch Sub-agent

## Working directory (cwd)
{REPO_PATH}

## Task
Monitor CI status for PR #{PR_NUMBER} on branch {BRANCH_NAME}.
This agent runs in parallel with Review-Fix-Watch (which handles Copilot comments).

## Steps

### 1. Wait for CI (up to 30 min total)
- **Poll interval**: every 30 seconds
- **Poll method**: Query GitHub Actions for the latest workflow run on {BRANCH_NAME}
  \`\`\`bash
  curl -s -H "Authorization: token $GH_TOKEN" \
    "https://api.github.com/repos/{REPO_FULL}/actions/runs?branch={BRANCH_NAME}&event=pull_request&per_page=5" \
    | jq '.workflow_runs[] | {id, status, conclusion, head_sha, display_title}'
  \`\`\`
- Track the head_sha across polls. If a NEW run appears (different head_sha), it means
  Review-Fix-Watch pushed a new commit — restart CI tracking for the new SHA.
- **Stability check**: CI is considered "done" only when the LATEST run has been
  in \`completed\` status with a final conclusion (success/failure/cancelled) for
  at least 2 consecutive polls.
- Report as soon as CI is stable (pass or fail).

### 2. Report
=== CI WATCH RESULT ===
CI Status: (success / failure / pending / timeout)
Latest SHA: (head_sha)
Job Details: (failed job name + error message if failure)
CI Duration: (how long CI took)
=== END CI WATCH RESULT ===

## Rules
- Timeout: 1800 seconds (30 min). If 30 min expires, report status=pending.
- Poll every 30 seconds — do not spin faster than this
- Handle Review-Fix-Watch pushes: detect new SHA, restart CI tracking
- Use GitHub REST API with GH_TOKEN for queries
- Token must not appear in any output
- **Do NOT check Copilot comments** — Review-Fix-Watch handles that

## Save retrospective
After reporting back, WRITE the retrospective to:
\`\`\`
~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-ci-watch.md
\`\`\`
Example: \`~/.openclaw/workspace/memory/2026-06-04-11-40-61-ci-watch.md\`

### Retrospective format
=== RETROSPECTIVE ===
1. Duration of monitoring
2. SHA changes detected (count of review-fix-watch pushes)
3. CI checks performed (count)
4. Final CI conclusion
5. Issues found
=== END RETROSPECTIVE ===
`,
  cwd: "{REPO_PATH}",
  runtime: "subagent",
  mode: "run"
})
```

## Rules

- Timeout: 1800 seconds (30 min). If 30 min expires, report conclusion=pending.
- **CI must complete**: Always wait for CI to finish (or 30 min timeout) before reporting.
- Poll every 30 seconds — do not spin faster than this
- Use GitHub REST API with GH_TOKEN for queries
- Token must not appear in any output
- **Save retrospective** to the path specified above
