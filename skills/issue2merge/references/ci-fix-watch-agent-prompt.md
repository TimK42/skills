# CI Fix-Watch Sub-agent Prompt Template

Read this reference at Step 10 when constructing the CI Fix-Watch sub-agent task.

## Template

```javascript
sessions_spawn({
  task: `## CI Fix-Watch Sub-agent

## Working directory (cwd)
{REPO_PATH}

## Task
Monitor CI status + Copilot review status (via R-FW signal file) + PR merge status for PR #{PR_NUMBER} on branch {BRANCH_NAME}.
When CI fails, auto-fix it. Only enable auto-merge when BOTH CI ✅ AND R-FW Copilot-clean signal exists with matching SHA. End when PR is merged or timeout reached.

## Key variables
- BRANCH_NAME: {BRANCH_NAME}
- PR_NUMBER: {PR_NUMBER}
- REPO_FULL: {REPO_FULL}
- REPO_OWNER: {REPO_OWNER}
- REPO_NAME: {REPO_NAME}
- ALL_ISSUES: {ALL_ISSUES}
- GH_TOKEN: from ~/.openclaw/openclaw.json
- AUTO_MERGE_ENABLED: false (start with auto-merge OFF — CI-FW enables it only after CI ✅ + Copilot signal ✅)
- SIGNAL_FILE_BASE: \$HOME/.openclaw/workspace/memory/{BRANCH_NAME}-copilot-clean.signal

## Required skills
This sub-agent MUST use:
1. **coding-agent-common** (workspace/skills/coding-agent-common/) — for non-trivial CI fixes
2. **coding** (workspace/skills/coding/) — to follow established coding conventions

## Behavior

### Main Loop (repeat until end condition):

1. **Poll every 60 seconds** — check CI status AND Copilot signal file AND PR merge state:

   a) **CI status check:**
   \`\`\`bash
   curl -s -H "Authorization: token $GH_TOKEN" \
     "https://api.github.com/repos/{REPO_FULL}/actions/runs?branch={BRANCH_NAME}&event=pull_request&per_page=5" \
     | jq '.workflow_runs[] | {id, status, conclusion, head_sha, display_title}'
   \`\`\`
   Track the head_sha. If a new commit appears (different head_sha), restart CI tracking for the new SHA.
   A run is "stable" only when it's been in \`completed\` status with a final conclusion for at least 2 consecutive polls.

   b) **Copilot review status check (via R-FW signal file):**
   \`\`\`bash
   SIGNAL_FILE="\$HOME/.openclaw/workspace/memory/{BRANCH_NAME}-copilot-clean.signal"
   if [ -f "\$SIGNAL_FILE" ]; then
     SIGNAL_SHA=\$(cat "\$SIGNAL_FILE" | head -1 | tr -d ' \\n')
     echo "SIGNAL_EXISTS=true SIGNAL_SHA=\$SIGNAL_SHA"
   else
     echo "SIGNAL_EXISTS=false SIGNAL_SHA="
   fi
   \`\`\`
   - **Signal file exists AND SIGNAL_SHA matches current head_sha** → R-FW confirmed Copilot review is clean ✅
   - **Signal file exists but SIGNAL_SHA != head_sha** → stale signal from old commit. New Copilot review needed. Do NOT enable auto-merge. Wait for R-FW to re-write signal.
   - **No signal file** → R-FW hasn't confirmed Copilot yet. Do NOT enable auto-merge.

   c) **PR merge state check:**
   \`\`\`bash
   curl -s -H "Authorization: token $GH_TOKEN" \
     "https://api.github.com/repos/{REPO_FULL}/pulls/{PR_NUMBER}" \
     | jq '{merged: .merged, mergeable: .mergeable, state: .state, auto_merge: .auto_merge}'
   \`\`\`

2. **Track head_sha changes:** Keep a variable \`LAST_CHECKED_SHA\`. If the head_sha from the PR merge state check differs from LAST_CHECKED_SHA, it means a new commit was pushed (by R-F-W, CI-FW itself, or manually). In that case:
   - Reset \`LAST_CHECKED_SHA\` to the new SHA
   - Reset CI tracking for the new SHA
   - Reset Copilot signal check for the new SHA (signal may now be stale)
   - Continue to step 3 (don't enable auto-merge yet — need fresh checks on new SHA)

### 3. React to CI state:

   - **CI success (stable on latest SHA)** → proceed to step 4 (Copilot signal gate check).
   - **CI still running** → nothing to do yet. Continue monitoring (go back to step 1).
   - **CI failure detected** (stable failure on latest SHA) → **AUTO-FIX**:

     a) Get the CI run ID and failed job details:
     \`\`\`bash
     # Get the latest failed run ID
     RUN_ID=$(curl -s -H "Authorization: token $GH_TOKEN" \
       "https://api.github.com/repos/{REPO_FULL}/actions/runs?branch={BRANCH_NAME}&event=pull_request&per_page=1" \
       | jq '.workflow_runs[0].id')
     # Get failed job logs
     curl -s -H "Authorization: token $GH_TOKEN" \
       "https://api.github.com/repos/{REPO_FULL}/actions/runs/$RUN_ID/jobs" \
       | jq '.jobs[] | select(.conclusion == "failure") | {name, steps: [.steps[] | select(.conclusion == "failure") | {name, number}]}'
     \`\`\`

     b) Fetch the branch:
     \`\`\`bash
     cd {REPO_PATH}
     git checkout main
     git pull origin main
     git checkout {BRANCH_NAME}
     git pull origin {BRANCH_NAME}
     \`\`\`

     c) **Download CI logs** for the failed job:
     \`\`\`bash
     gh run view $RUN_ID --log > /tmp/ci-fix-logs.txt 2>&1
     head -200 /tmp/ci-fix-logs.txt
     \`\`\`
     Read the key error messages from the CI logs.

     d) **Fix the code** based on the CI error:
        - Lint/formatting errors (Prettier, ESLint, ruff) → run the formatter directly
        - Test failures → read the failing test output, fix the code
        - Build errors → fix the configuration or code
        - Non-trivial fixes → use coding-agent-common skill

     e) **Run tests locally** to verify:
     \`\`\`bash
     cd {REPO_PATH}
     # Detect test runner from package.json or repo structure and run tests
     # Example:
     npm test 2>&1 | tail -n 50
     \`\`\`
     If local tests still fail → go back to step (d) and fix more.
     If local tests pass → proceed.

     f) **Commit + push the fix (handle concurrent push conflicts):**
     \`\`\`bash
     git add -A
     git commit -m "fix({ALL_ISSUES}): fix CI failure on {BRANCH_NAME}"
     git pull origin {BRANCH_NAME} --rebase 2>/dev/null || true
     git push origin {BRANCH_NAME}
     \`\`\`
     If push fails (non-fast-forward), retry with pull --rebase once more.

     g) **Notify Copilot** of the new commit:
     \`\`\`bash
     gh pr edit {PR_NUMBER} --add-reviewer @copilot
     \`\`\`

     h) **Delete stale signal file** (new commit means old signal is invalid):
     \`\`\`bash
     rm -f "\$HOME/.openclaw/workspace/memory/{BRANCH_NAME}-copilot-clean.signal"
     \`\`\`

     i) Go back to **step 1** — wait for the new CI run to complete on the new SHA.

### 4. Auto-merge Gate: CI ✅ AND R-FW Copilot signal ✅ on latest SHA

Only reach this section when CI is stable-success on the latest SHA. Now check Copilot signal:

   - **Signal file exists + SIGNAL_SHA == current head_sha** → R-FW confirms Copilot review is clean. **Enable auto-merge:**
     \`\`\`bash
     gh pr merge {PR_NUMBER} --auto --squash
     \`\`\`
     Then continue monitoring (step 1) until the PR is actually merged.

   - **Signal missing or SHA mismatch** → R-FW hasn't confirmed Copilot yet. Nothing to do.
     R-F-W still working. Continue monitoring (go back to step 1).
     On next poll, head_sha may change (if R-FW pushed a fix), which naturally resets both checks.

### 5. Report

When end condition is reached, report:

=== CI FIX WATCH RESULT ===
Status: (merged / timeout)
PR #: {PR_NUMBER}
CI Runs Monitored: (count)
CI Fixes Applied: (count + description)
Auto-merge Enabled By CI-FW: (yes / no — was the auto-merge gate satisfied?)
Final PR Merge State: (merged: true/false)
Final CI State: (success / failure / pending)
Length of Run: (duration)
=== END CI FIX WATCH RESULT ===

## End conditions
STOP and report when ANY of these is true:
1. **PR is merged** (from merge state check)
2. **Timeout**: 3600 seconds (1 hour) total

## Rules
- Poll exactly every **60 seconds** — no faster
- Check CI status + Copilot signal file + PR merge state every poll
- **Enable auto-merge ONLY after confirming BOTH CI ✅ on latest SHA AND R-FW signal file exists with matching SHA**
- When CI fails: auto-fix, commit, push, delete stale signal file, then continue monitoring
- Track head_sha to detect new commits (from R-FW, self, or manual pushes). Any SHA change resets CI+Copilot checks.
- Use GitHub REST API + \`gh\` CLI for queries
- Token must not appear in any output
- Timeout: 3600 seconds (1 hour)
- **Manager does NOT set auto-merge before spawning CI-FW.** CI-FW is solely responsible for enabling it.
- **CI-FW does NOT check Copilot threads directly** — R-FW handles all Copilot interaction (poll + fix + reply + resolve + write signal). CI-FW only checks R-FW's signal file to decide the merge gate.

## Save retrospective
After stopping, WRITE the retrospective to:
\`\`\`
~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-ci-fix-watch.md
\`\`\`
Example: \`~/.openclaw/workspace/memory/2026-06-04-11-40-61-ci-fix-watch.md\`

### Retrospective format
=== RETROSPECTIVE ===
1. Duration active
2. Polls performed (count)
3. CI failures found and fixed (count + description)
4. PR merge status changes observed
5. Signal file events (created/deleted/re-written) observed
6. End condition reached
7. Final status
=== END RETROSPECTIVE ===
`,
  cwd: "{REPO_PATH}",
  runtime: "subagent",
  mode: "run"
})
```

## Rules

- Timeout: 3600 seconds (1 hour). If 1 hour expires, report status=timeout.
- Poll every 60 seconds — do not spin faster than this
- **Check CI + Copilot signal file + PR merge state each poll**
- When CI fails: auto-fix, commit, push, delete stale signal, notify Copilot, then continue monitoring
- After each push, delete stale signal file so R-FW will re-write it after new Copilot review
- Use GitHub REST API + `gh` CLI for queries
- Token must not appear in any output
- **Save retrospective** to the path specified above
