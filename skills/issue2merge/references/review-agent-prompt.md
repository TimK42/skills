# Review Sub-agent Prompt Template (Dual-Axis)

Read this reference at Step 4 when constructing the Review sub-agent task.

Uses the **review** skill (`workspace/skills/review/SKILL.md`) — dual-axis: Standards + Spec.

## Template (Manager constructs this)

```javascript
sessions_spawn({
  task: `## Review Sub-agent — Dual-Axis (Standards + Spec)

## Working directory (cwd)
{REPO_PATH}

## Required skill: review
Load and follow the **review** skill at:
\`\`\`bash
cat ~/.openclaw/workspace/skills/review/SKILL.md
\`\`\`

## Context from Manager

### Fixed point
\`main\` (compare branch against main branch)

### Diff command
\`git diff origin/main...HEAD\` (three-dot merge-base comparison)

### Commits
\`\`\`
{COMMIT_LIST}
\`\`\`

### Spec source: Issue #{ISSUE_NUMBER}
\`\`\`
{ISSUE_BODY}
\`\`\`

### Standards sources (files to check)
- CONTRIBUTING.md
- CONTEXT.md
- pyproject.toml (ruff config: double-quotes, line-length=100, target py311)

## ⛔ Step 0: Run Full Test Suite First
Before any review, run the full project test suite and confirm ALL tests pass.

\`\`\`bash
cd {REPO_PATH}
SECRET_KEY=test python -m pytest -v --tb=short --ds=config.settings.dev 2>&1 | tail -n 40
\`\`\`

- **Tests passed (all green)** → proceed with dual-axis review
- **Tests failed** → record as FAIL, attach failure output, abort

## Step 1: Pin fixed point (already done — main)
## Step 2: Identify spec source (already done — Issue #{ISSUE_NUMBER})
## Step 3: Identify standards sources (already done — list above)

## Step 4: Spawn both sub-agents in parallel

Spawn TWO sub-agents using the review skill's dual-axis approach:

### Standards sub-agent
Task: "Read the standards docs (CONTRIBUTING.md, CONTEXT.md, pyproject.toml). Then read \`git diff origin/main...HEAD\`. Report per file/hunk every place the diff violates a documented standard. Cite the standard (file + the rule). Distinguish hard violations from judgement calls. Skip anything tooling enforces. Under 400 words."

### Spec sub-agent
Task: "Read the spec (Issue #{ISSUE_NUMBER} body above). Then read \`git diff origin/main...HEAD\`. Report: (a) requirements the spec asked for that are missing or partial; (b) behaviour in the diff that wasn't asked for (scope creep); (c) requirements that look implemented but where the implementation looks wrong. Quote the spec line for each finding. Under 400 words."

## Step 5: Aggregate

Present results under:
## Standards
[verbatim report from Standards sub-agent]

## Spec
[verbatim report from Spec sub-agent]

End with: "Total: {N} findings (Standards: {X}, Spec: {Y}) — worst issue: {description}"

## Verdict
- **PASS** → both axes have no hard violations or blocking issues
- **FAIL** → one or both axes have hard violations that need fixing

## Retrospective format
=== RETROSPECTIVE ===
1. Files reviewed
2. Standards findings (count + severity)
3. Spec findings (count + severity)
4. Verdict (PASS/FAIL)
=== END RETROSPECTIVE ===

## Save retrospective
After reporting back, WRITE the retrospective to:
\`~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-review-round-{ROUND}.md\`
`,
  cwd: "{REPO_PATH}",
  runtime: "subagent",
  mode: "run"
})
```

## Rules

- Timeout: 3600 (60 minutes — includes test suite + dual-axis review)
- MUST load the review skill at startup
- **Must run full test suite before any review** — failing tests = FAIL
- Dual-axis review spawns TWO sub-agents in parallel (Standards + Spec)
- Do NOT merge or rerank findings across axes — keep them separate
- Verdict is PASS only if BOTH axes pass
- Save retrospective to `memory/`
