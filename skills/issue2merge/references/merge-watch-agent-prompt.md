# Merge Watch Sub-agent Prompt Template

Read this reference at Step 11 when constructing the Merge Watch sub-agent task.

## Template

```javascript
sessions_spawn({
  task: `## Merge Watch Sub-agent

## Working directory (cwd)
{REPO_PATH}

## Task
Watch PR #{PR_NUMBER} on branch {BRANCH_NAME} for merge-ready conditions,
then auto-merge when safe.

This agent runs AFTER CI Fix-Watch and Review-Fix-Watch have completed successfully.
It adds a final safety buffer before merging.

## Key variables
- BRANCH_NAME: {BRANCH_NAME}
- PR_NUMBER: {PR_NUMBER}
- REPO_FULL: {REPO_FULL}
- ALL_ISSUES: {ALL_ISSUES}
- GH_TOKEN: from ~/.openclaw/openclaw.json
- AUTO_MERGE: {AUTO_MERGE}  (true = merge, false = report only)

## Behavior

### Main Loop (repeat every 30 seconds):

1. **Check merge readiness:**
   \`\`\`bash
   # PR merge state
   curl -s -H "Authorization: token $GH_TOKEN" \
     "https://api.github.com/repos/{REPO_FULL}/pulls/{PR_NUMBER}" \
     | jq '{state, merged, mergeable, mergeable_state}'

   # CI status
   curl -s -H "Authorization: token $GH_TOKEN" \
     "https://api.github.com/repos/{REPO_FULL}/commits/{BRANCH_NAME}/check-runs" \
     | jq '[.check_runs[] | {name, status, conclusion}]'

   # Copilot comment threads
   curl -s -X POST \
     -H "Authorization: Bearer $GH_TOKEN" \
     -H "Accept: application/vnd.github+json" \
     -H "X-GitHub-Api-Version: 2026-03-10" \
     https://api.github.com/graphql \
     -d '{"query": "query { repository(owner: \"{REPO_OWNER}\", name: \"{REPO_NAME}\") { pullRequest(number: {PR_NUMBER}) { reviewThreads(first: 100) { nodes { id isResolved } } } } }"}' \
     | jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length'
   \`\`\`

2. **Evaluate conditions:**
   - **If PR already merged** → STOP (nothing to do)
   - **If ALL conditions met:**
     - PR state = OPEN, merged = false
     - mergeable = true
     - All CI check runs: status=COMPLETED, conclusion=SUCCESS
     - Zero unresolved Copilot threads
     - **Then**: wait 120 seconds, re-check conditions
       - If still all good → proceed to merge
       - If something changed → restart wait cycle
   - **If conditions not met** → continue polling

### Merge (only when AUTO_MERGE=true):
\`\`\`bash
cd {REPO_PATH}
git checkout main && git pull origin main
gh pr merge {PR_NUMBER} --squash --delete-branch
git pull origin main
\`\`\`

Close associated issues:
\`\`\`bash
IFS=',' read -ra ISSUES <<< "{ALL_ISSUES}"
for iss in "${ISSUES[@]}"; do
  gh issue close "$iss" --comment "Closed by PR #${PR_NUMBER}"
done
\`\`\`

### Report (when AUTO_MERGE=false):
Report to parent agent:
> PR #{PR_NUMBER} is merge-ready. All conditions met: CI green, no unresolved threads, mergeable. Ready for manual merge.

### End conditions
STOP when ANY:
1. PR merged (by this agent or externally)
2. Timeout: 1800 seconds (30 minutes)

### Report format
=== MERGE WATCH RESULT ===
Status: (merged / merge_ready / timeout / already_merged)
Merged By: (self / external / n/a)
CI State: (green / partial / red)
Unresolved Threads: (count)
Details: (summary)
=== END MERGE WATCH RESULT ===

## Rules
- Poll every 30 seconds
- **120-second safety buffer** before merging — confirms no new review arrives
- If any condition reverts during buffer → reset timer
- Token must not appear in any output
- Timeout: 1800 seconds (30 minutes)
- Save retrospective to: ~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-merge-watch.md
`,
  cwd: "{REPO_PATH}",
  runtime: "subagent",
  mode: "run"
})
```

## Rules

- Poll every 30 seconds
- **120-second safety buffer** before merge — ensures no new review arrives
- If any condition reverts during buffer → reset timer
- Token must not appear in any output
- Timeout: 1800 seconds (30 minutes)
- **Save retrospective** to the path specified above
