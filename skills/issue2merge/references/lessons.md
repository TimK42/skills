# Lessons Learned — issue2merge Skill

Collected from actual runs. Update as new patterns emerge.

---

## 1. Prettier/format CI failures: auto-fix first

**Situation:** After manual code edits, Prettier formatting often breaks. CI catches it as a lint failure, adding an extra round.

**Rule:** In CI-Fix-Watch, on any lint/format failure:
1. First try `npx prettier --write` or the project's equivalent formatter
2. If that fixes it, commit and push
3. Only dig into analysis if the formatter run still shows errors

**Root cause:** Manual edits (even via coding agent) don't always match the formatter's expectations. It's faster to auto-format than to read the diff and manually fix spacing.

---

## 2. Copilot reviews on stale commits

**Situation:** Review-Fix-Watch pushes a fix, Copilot re-reviews, but returns comments about issues that were already fixed in the same commit.

**Root cause:** Copilot review runs on the SHA it was triggered on. If the push and the re-notification happen within seconds, Copilot may review an old cached state.

**Mitigation:** Review-Fix-Watch now compares comment commit_id against branch HEAD. If mismatch → stale comment → reply "fixed in newer commit" + resolve without code change.

---

## 3. Multiple review rounds are expected

**Situation:** #94 went through 7 Copilot review rounds despite the fix being conceptually correct from round 1.

**Normal pattern:** Each round Copilot checks more deeply and finds edge cases. Rounds 1-2 are structural, rounds 3-5 are edge cases, rounds 6+ are documentation/styling.

**Guideline:** Don't panic at 5+ rounds. The Review-Fix-Watch handles the mechanical loop. Escalate only when:
- Same comment appears across 3+ rounds (Copilot stuck in a loop)
- Non-trivial logic change requested in round 6+ (should have been caught earlier)

---

## 4. PENDING_FIXES.md accuracy

**Situation:** Copilot flagged PENDING_FIXES.md for inaccuracy — the doc described implementation differently from actual code.

**Lesson:** Any tracking document that describes implementation details is a liability. Prefer:
- Auto-generate from actual git diff (by Test or Review agent)
- Or omit entirely — git log and PR description serve the same purpose

If PENDING_FIXES.md is kept, it must be regenerated from scratch on every significant push.

---

## 5. git pull --rebase is mandatory on push

**Situation:** CI-Fix-Watch and Review-Fix-Watch push concurrently. Without `--rebase`, the second pusher gets a non-fast-forward rejection.

**Rule:** Every `git push` in any sub-agent MUST prefix with:
```bash
git pull origin {BRANCH_NAME} --rebase 2>/dev/null || true
```
This handles concurrent push from the parallel watch agent. If the rebase fails, retry once more before reporting push failure.

---

## 6. Squash merge + branch deletion

**Situation:** After squash merge, the remote branch is automatically deleted. Local branches become stale.

**Post-merge cleanup:**
```bash
git checkout main
git pull origin main
git branch -D {BRANCH_NAME} 2>/dev/null || true
```

Also remove any `.planning/` directories associated with the issue.

---

## 7. Review-Fix-Watch loop timing

**Situation:** Review-Fix-Watch would stop early when it found no comments, but Copilot often generated a new review 2-3 minutes later.

**Fix:** R-F-W now continues looping until merge, with a 3-minute "quiet period" check. Only stops when:
- PR merged
- OR timeout (1h)
- OR 3+ minutes of consecutive clean polls + mergeable + CI green

---

## 8. GH_TOKEN expiry in long sessions

**Situation:** Long-running loops (>30 min) might encounter token expiry.

**Mitigation:** Re-read token from config before each API call batch if delays are >5 minutes:
```bash
GH_TOKEN=$(cat ~/.openclaw/openclaw.json | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('env',{}).get('vars',{}).get('GH_TOKEN',''))")
```

---

## 9. GraphQL thread IDs with dashes

**Situation:** Some thread IDs contain `-` characters (e.g., `PRRT_kwDOOw16Js6A6K7-`), which break inline JSON in `curl -d`.

**Fix:** Always use `--data-binary @file` for GraphQL mutations involving thread IDs. Never inline the JSON.

---

## 11. Single agent all-in-one — no sub-agent parallelism

**Situation (PR #185):** CI-Fix-Watch agent auto-merged the PR before main agent's deeper fix could land, leaving a fix commit orphaned.

**Rule enforced 2026-06-11:**

> **One agent does everything. No parallel sub-agents. No auto-merge from sub-agents.**

```
Single Agent:
  1. Fix the code
  2. Run tests
  3. Handle Copilot review (reply + resolve)
  4. When CI ✅ + Copilot ✅ → merge (main agent only)
```

Sub-agents NEVER:
- Enable auto-merge
- Merge a PR
- Operate on the same PR concurrently

The main agent owns the merge decision. If parallelism is needed (many files), spawn fix-only sub-agents but keep merge authority in main.

---

## 10. ESLint flat config for browser globals

**Situation:** Test files use `document`, `window`, `navigator` which are not available in Node.js ESLint.

**Fix:** In `eslint.config.js`, add:
```javascript
ignores: ['path/to/test-file.js']
```
Or configure the file as browser environment:
```javascript
languageOptions: { globals: globals.browser }
```
