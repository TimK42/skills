# Review-Fix-Watch Sub-agent Prompt Template

Read this reference at Step 10 when constructing the Review-Fix-Watch sub-agent task.

## Template

```javascript
sessions_spawn({
  task: `## Review-Fix-Watch Sub-agent

## Working directory (cwd)
{REPO_PATH}

## Task
Monitor Copilot review inline comments + PR merge state for PR #{PR_NUMBER} on branch {BRANCH_NAME},
and auto-fix + reply + resolve them in a continuous loop until the PR is merged or timeout.

## Key variables
- BRANCH_NAME: {BRANCH_NAME}
- PR_NUMBER: {PR_NUMBER}
- REPO_FULL: {REPO_FULL}
- ALL_ISSUES: {ALL_ISSUES}
- ISSUE_NUMBER: {ISSUE_NUMBER}
- GH_TOKEN: from ~/.openclaw/openclaw.json
- SIGNAL_FILE: \$HOME/.openclaw/workspace/memory/{BRANCH_NAME}-copilot-clean.signal

## Required skills
This sub-agent MUST use:
1. **coding-agent-common** (workspace/skills/coding-agent-common/) — for non-trivial code fixes
2. **coding** (workspace/skills/coding/) — to follow established coding conventions

## Behavior

### Startup

Immediately notify Copilot for initial review:
```bash
git checkout {BRANCH_NAME}
gh pr edit {PR_NUMBER} --add-reviewer @copilot
```

### Main Loop (repeat until end condition):

**Step 1 — Poll every 30 seconds:**

a) **Check PR merge state:**
\`\`\`bash
curl -s -H "Authorization: token $GH_TOKEN" \
  "https://api.github.com/repos/{REPO_FULL}/pulls/{PR_NUMBER}" \
  | jq '{state, merged, mergeable, head_sha: (.head.sha[0:8])}'
\`\`\`

b) **Fetch branch head SHA:**
\`\`\`bash
cd {REPO_PATH}
git fetch origin {BRANCH_NAME}
BRANCH_HEAD=$(git rev-parse origin/{BRANCH_NAME})
\`\`\`

c) **Check for new unresolved Copilot inline comments** (using GraphQL):
\`\`\`bash
curl -s -X POST \
  -H "Authorization: Bearer $GH_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  https://api.github.com/graphql \
  -d '{"query": "query { repository(owner: \"{REPO_OWNER}\", name: \"{REPO_NAME}\") { pullRequest(number: {PR_NUMBER}) { reviewThreads(first: 100) { nodes { id isResolved comments(first: 5) { nodes { id body commit { oid } } } } } } } }"}'
\`\`\`

**Step 2 — Dedup check (NEW):**
For each unresolved comment, compare \`commit.oid\` (the SHA the comment was attached to) against \`BRANCH_HEAD\`:
- If \`comment.commit.oid\` IS \`BRANCH_HEAD\` → new comment targeting latest code → needs fix
- If \`comment.commit.oid\` is NOT \`BRANCH_HEAD\` → stale comment from previous commit → reply explaining it was already fixed in newer commit + resolve WITHOUT fixing code

**Step 3 — If NEW unresolved comments on latest SHA found:**

a) Read the affected code files

b) **Classify each comment:**
   - **Trivial** (docstrings, locale codes, test assertions, single-line style) → edit directly
   - **Non-trivial** (logic changes, multi-file, complex refactor) → see escalation below

c) **Escalation for non-trivial fixes:**
   Save details to escalation file:
   \`\`\`md
   ~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-rfw-escalation.md
   \`\`\`
   Content:
   - Comment ID and body
   - Problem description
   - Why it's non-trivial
   
   Then reply to the thread: "This requires a non-trivial code change (logic/multi-file). Logged for main agent escalation. Will continue monitoring other comments."
   Resolve the thread (to unblock monitoring).

d) **Fix trivial comments:**
   - Make the code change via edit tool
   - Use coding-agent-common for any fix that needs it

e) **Reply** to EVERY inline comment thread via GraphQL \`addPullRequestReviewThreadReply\`
   - Explain what was fixed
   - For stale comments (dedup step 2): "This was on commit X. The fix was applied in commit Y (current HEAD). Resolving."
   - For escalated comments: "Logged for main agent escalation."
   - Use --data-binary @file approach for threads with \`-\` in IDs

f) **Resolve** EVERY thread via GraphQL \`resolveReviewThread\`

g) **Commit + push (handle concurrent push conflicts):**
   \`\`\`bash
   cd {REPO_PATH}
   git add -A
   git commit -m "fix({ALL_ISSUES}): address Copilot review comments"
   git pull origin {BRANCH_NAME} --rebase 2>/dev/null || true
   git push origin {BRANCH_NAME}
   \`\`\`
   If push fails (non-fast-forward), retry with pull --rebase once more.

h) **Re-notify** Copilot:
   \`\`\`bash
   gh pr edit {PR_NUMBER} --add-reviewer @copilot
   \`\`\`

i) Go back to **Step 1** (continue monitoring — loop until merge or timeout)

**Step 4 — If NO new unresolved comments on latest SHA:**
- Do NOT stop. Continue polling.
- Wait 3 minutes minimum (6 polls × 30s) of consecutive "no new comments" before considering stopping.
- During this wait, keep checking PR merge state.
- When the wait period ends AND all clean → **Write Copilot-clean signal file** for CI-FW:
  ```bash
  cd {REPO_PATH}
  BRANCH_HEAD=$(git rev-parse origin/{BRANCH_NAME})
  echo "$BRANCH_HEAD" > "$SIGNAL_FILE"
  echo "SIGNAL_WRITTEN: $BRANCH_HEAD"
  ```
  This signal tells CI-FW: "R-FW confirmed Copilot review is clean on this SHA." CI-FW will check this file before enabling auto-merge.

### End conditions
STOP and report when ANY:
1. **PR is merged** (from merge state check)
2. **Total timeout**: 3600 seconds (1 hour)
3. **No new comments for 3+ consecutive minutes + all threads resolved + PR is mergeable and CI green** — safe to stop

### Signal file cleanup on start
Before starting the main loop, remove any stale signal file from a previous run:
```bash
rm -f "$SIGNAL_FILE"
```

### Report format
=== REVIEW-FIX-WATCH RESULT ===
Status: (merged / all_clean / timeout / escalation_needed)
Comments Fixed: (count)
Stale Comments Skipped: (count — from dedup)
Escalated Comments: (count)
Rounds Completed: (N)
Last Push SHA: (commit hash)
Details: (summary)
=== END REVIEW-FIX-WATCH RESULT ===

## GraphQL API Reference (inline comment reply + resolve)

### Reply to a thread:
\`\`\`bash
cat > /tmp/review-fix-reply.json << 'GRAPHQL_EOF'
{
  "query": "mutation { addPullRequestReviewThreadReply(input: { body: \\"REPLY_TEXT\\", pullRequestReviewThreadId: \\"THREAD_NODE_ID\\", clientMutationId: \\"rfw-1\\" }) { comment { id } } }"
}
GRAPHQL_EOF

curl -s -X POST \
  -H "Authorization: Bearer $GH_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  --data-binary @/tmp/review-fix-reply.json \
  https://api.github.com/graphql
\`\`\`

### Resolve a thread:
\`\`\`bash
cat > /tmp/review-fix-resolve.json << 'GRAPHQL_EOF'
{
  "query": "mutation { resolveReviewThread(input: { threadId: \\"THREAD_NODE_ID\\" }) { thread { isResolved } } }"
}
GRAPHQL_EOF

curl -s -X POST \
  -H "Authorization: Bearer $GH_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  --data-binary @/tmp/review-fix-resolve.json \
  https://api.github.com/graphql
\`\`\`

### Check thread resolved state with commit info (for dedup):
\`\`\`bash
curl -s -X POST \
  -H "Authorization: Bearer $GH_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  https://api.github.com/graphql \
  -d '{"query": "query { repository(owner: \"{REPO_OWNER}\", name: \"{REPO_NAME}\") { pullRequest(number: {PR_NUMBER}) { reviewThreads(first: 100) { nodes { id isResolved comments(first: 5) { nodes { id body commit { oid abbreviatedOid } } } } } } } }"}'
\`\`\`

## Rules
- **Poll exactly every 30 seconds** — no faster
- **Loop until merge** — do NOT stop on first "no comments" batch. Wait 3+ min of consecutive clean polls + mergeable + CI green
- **Write Copilot-clean signal file** at Stop condition 3 (all clean), so CI-FW can enable auto-merge
- **Signal file contains just the SHA** of the branch HEAD that R-FW confirmed clean
- **Dedup**: Compare comment's \`commit.oid\` with branch HEAD before fixing. Stale comments → reply+resolve only, no code change.
- **Escalation**: Non-trivial fixes → log to escalation file, reply "logged for escalation", resolve, continue loop
- **Every fix MUST include**: reply + resolve + commit + push + re-notify
- GraphQL for replies/resolutions (not REST API)
- Token must not appear in any output
- Timeout: 3600 seconds (1 hour total)

## Save retrospective
After stopping, WRITE the retrospective to:
\`\`\`
~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-review-fix-watch.md
\`\`\`

### Retrospective format
=== RETROSPECTIVE ===
1. Duration active
2. Polls performed (count)
3. Comments: found(N) fixed(N) stale(N) escalated(N)
4. Rounds completed
5. End condition reached
6. Final status
=== END RETROSPECTIVE ===
`,
  cwd: "{REPO_PATH}",
  runtime: "subagent",
  mode: "run"
})
```

## Rules

- Timeout: 3600 seconds (1 hour). If 1 hour expires, report conclusion=timeout.
- Poll every 30 seconds
- **Loop until merge** — do not stop early
- Dedup stale comments against branch HEAD SHA
- Escalate non-trivial fixes to escalation file
- Use GitHub REST API + GraphQL with GH_TOKEN
- Token must not appear in any output
- **Save retrospective** to the path specified above
