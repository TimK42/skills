# Review Sub-agent Prompt Template (Triple-Axis + OCR + Lint)

Read this reference at Step 4 when constructing the Review sub-agent task.

Uses the **review** skill (`workspace/skills/review/SKILL.md`) — dual-axis: Standards + Spec.
Also runs **open-code-review** (`ocr`) — Alibaba's AI code review CLI for automated line-level review.
Also runs **ruff** lint — automated Python style/correctness check on changed files.

## Template (Manager constructs this)

```javascript
sessions_spawn({
  task: `## Review Sub-agent — Triple-Axis (Standards + Spec + Lint) + OCR

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

- **Tests passed (all green)** → proceed with OCR + triple-axis sub-agents review
- **Tests failed** → record as FAIL, attach failure output, abort

## Step 1: Pin fixed point (already done — main)
## Step 2: Identify spec source (already done — Issue #{ISSUE_NUMBER})
## Step 3: Identify standards sources (already done — list above)

## Step 4: Run OCR Review (Alibaba open-code-review)

Run the \`ocr\` CLI to get an AI-powered code review with line-level comments.

\`\`\`bash
cd {REPO_PATH}
ocr review --audience agent -b "Issue #{ISSUE_NUMBER}: {ISSUE_TITLE}" --from origin/main --to HEAD --format json 2>&1
\`\`\`

If \`ocr\` is not installed, install it first: \`npm install -g @alibaba-group/open-code-review\`

### Parse OCR output

Filter OCR comments by priority:
- **High** — obvious bugs, security issues, clear mistakes → include in FAIL report
- **Medium** — reasonable concerns, context-dependent suggestions → note but don't block
- **Low** — likely false positives → discard silently

## Step 5: Spawn triple-axis sub-agents in parallel

Alongside OCR, spawn THREE sub-agents using the review skill's dual-axis approach plus a lint check:

### Standards sub-agent
Task: "Read the standards docs (CONTRIBUTING.md, CONTEXT.md, pyproject.toml). Then read \`git diff origin/main...HEAD\`. Report per file/hunk every place the diff violates a documented standard. Cite the standard (file + the rule). Distinguish hard violations from judgement calls. Skip anything tooling enforces. Under 400 words."

### Spec sub-agent
Task: "Read the spec (Issue #{ISSUE_NUMBER} body above). Then read \`git diff origin/main...HEAD\`. Report: (a) requirements the spec asked for that are missing or partial; (b) behaviour in the diff that wasn't asked for (scope creep); (c) requirements that look implemented but where the implementation looks wrong. Quote the spec line for each finding. Under 400 words."

### Lint sub-agent
Task: "Run ruff on files changed in this branch. Use \`ruff check $(git diff origin/main...HEAD --name-only --diff-filter=ACMR | grep -v node_modules | grep '\\.py$' || echo '')\' to run lint. Report every violation with file path and line number. Classify by rule code (e.g., F841, E501) and severity level. If no violations found, confirm \"Lint clean — no violations.\" Under 300 words."

## Step 6: Aggregate

Present results under:
## OCR Review
[OCR findings — High priority items only, with file paths and line numbers]
If OCR found no High issues, note: "OCR review clean — no high-priority issues found."

## Standards
[verbatim report from Standards sub-agent]

## Spec
[verbatim report from Spec sub-agent]

## Lint
[verbatim or summary of Lint sub-agent report]

End with: "Total: {N} findings (OCR: {X}, Standards: {Y}, Spec: {Z}, Lint: {W}) — worst issue: {description}"

## Verdict
- **PASS** → all four axes have no hard violations or blocking issues
- **FAIL** → one or more axes have hard violations that need fixing

## Retrospective format
=== RETROSPECTIVE ===
1. Files reviewed
2. OCR High findings (count)
3. Standards findings (count + severity)
4. Spec findings (count + severity)
5. Lint findings (count + rule codes)
6. Verdict (PASS/FAIL)
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

- Timeout: 4200 (70 minutes — includes test suite + OCR + triple-axis review + lint)
- MUST load the review skill at startup
- **Must run full test suite before any review** — failing tests = FAIL
- Run OCR review inline first, then spawn triple-axis sub-agents in parallel (Standards + Spec + Lint)
- Do NOT merge or rerank findings across axes — keep them separate
- Verdict is PASS only if ALL FOUR axes pass
- Save retrospective to `memory/`
- If ruff is not installed, the Lint sub-agent should install it: `pip install ruff`
