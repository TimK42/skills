# Review Sub-agent Prompt Template

Read this reference at Step 4 when constructing the Review sub-agent task.

## Template

```javascript
sessions_spawn({
  task: `## Review Sub-agent

## Working directory (cwd)
{REPO_PATH}

## Required skills (loaded automatically)
This sub-agent MUST load and follow the **code-review** skill:

| Skill | Purpose | Location |
|-------|---------|----------|
| **code-review** | Systematic code review for security, performance, correctness, maintainability, testing, and accessibility | workspace/skills/code-review/ |
| **uiux-audit** | Browser-based UI/UX audit for accessibility, responsive, i18n, forms, PWA, and visual consistency | workspace/skills/uiux-audit/ |

## First step: Load code-review skill

**BEFORE anything else**, read the code-review skill file to get the actual checklists:

```bash
cat workspace/skills/code-review/SKILL.md
```

This will load the complete review checklists including:
- Security Checklist (12 items)
- Performance Checklist (10 items)
- Correctness Checklist (10 items)
- Maintainability Checklist (10 items)
- Testing Checklist (8 items)

You will use these checklists item-by-item during the review phase.

## Task
Review all uncommitted changes in {REPO_PATH} using the **code-review** skill checklists.

## ⛔ MANDATORY: Run Full Test Suite First

Before any code review, run the full project test suite. **If tests fail, record failures immediately and return FAIL verdict** — do not proceed to code review.

```bash
cd {REPO_PATH}
SECRET_KEY=test python -m pytest -v --tb=short --ds=config.settings.dev 2>&1 | tail -n 40
```

> If coverage threshold is defined, also run:
> ```bash
> SECRET_KEY=test python -m pytest --tb=short --ds=config.settings.dev --cov=apps --cov-report=term-missing --cov-fail-under=60 2>&1 | tail -n 30
> ```

Report results:
- **Tests passed (all green)** → proceed to code review below
- **Tests failed** → record in retrospective as FAIL, attach failure output, abort

## Review phase: Use code-review checklists systematically

**Three-pass review process** (from code-review skill):

### Pass 1 — High-level structure (2-5 min)
1. Read the PR description and linked issue #{ISSUE_NUMBER}
2. Scan the file list — does the change scope make sense?
3. Check the overall approach — is this the right solution?
4. Verify no architectural drift

### Pass 2 — Line-by-line detail (bulk of time)
Systematically check every change against the **code-review** skill checklists:

1. **Security** — SQL injection, XSS, CSRF, auth, secrets, input validation, rate limiting, file uploads, HTTP headers
2. **Performance** — N+1 queries, memory leaks, bundle size, caching, lazy loading, pagination, async operations
3. **Correctness** — edge cases, null handling, off-by-one, race conditions, timezone, encoding, error propagation, state consistency
4. **Maintainability** — naming clarity, SRP, DRY, complexity, dead code, magic numbers, consistent patterns, function length
5. **Testing** — coverage, edge case tests, no flaky tests, test independence, meaningful assertions
6. **Accessibility** — WCAG compliance, keyboard nav, screen readers

### Pass 3 — Hardening (5 min)
1. What could go wrong in production?
2. Check for missing tests on flagged code paths
3. Verify rollback safety
4. Confirm documentation if needed

Also verify:
- Does it properly address issue #{ISSUE_NUMBER}?
- Consistent with existing code style?
- Could it break existing functionality?

## UI/UX Audit Phase (after code review passes)

After the code review verdict is PASS, load the **uiux-audit** skill and run an **affected-pages-only audit**:

```bash
cat workspace/skills/uiux-audit/SKILL.md
```

**Only audit pages affected by the changed files.** Determine affected pages from the changed file list (e.g., if `templates/analytics/dashboard.html` changed, audit only the analytics dashboard page). Do NOT visit every page in the app.

### 1. Check affected routes
Use server logs and a testing user to visit pages related to the changed files:
- If templates changed → audit the corresponding page(s)
- If JS files changed → audit pages that use those scripts
- If CSS/SCSS changed → audit pages with visual changes
- If API views changed → check the pages that consume those APIs
- If urls.py changed → audit the affected URL routes
- If no templates/views changed → skip UI/UX audit (note in retrospective)

### 2. Audit each page against all six dimensions

| Dimension | Checklist |
|-----------|-----------|
| **Accessibility** | Skip link, H1→H2→H3 hierarchy, `<main>` landmark, `:focus-visible`, form labels, ARIA labels, images alt, htmlLang, autocomplete |
| **Responsive** | Desktop (1440px), mobile (375px) — hamburger menu, no overflow, card layout |
| **i18n** | Chinese mode (zh-hant) + English mode (en) — every string translated in both directions, language persistence across navigation |
| **Form UX** | Labels, required indicators, validation, loading states, success/error feedback, autocomplete, date placeholders, stale messages |
| **Navigation** | Navbar links, breadcrumb on interior pages, footer links (About/Terms/Privacy), skip link |
| **Visual** | Dark mode toggle + all pages themed, heading hierarchy, semantic HTML, meta descriptions |

### 3. Check for console errors & HTTP responses
- JS console errors on every page load
- 404/500 status codes
- Repeated XHR/fetch failures (e.g., polling broken endpoints)
- Security headers (X-Frame-Options, X-Content-Type-Options, Referrer-Policy)

### 4. PWA checks
- manifest.json returns 200 with valid JSON
- Service worker registered with proper scope
- Offline fallback page renders correctly
- Meta tags (theme-color, apple-mobile-web-app-capable, viewport)

### 5. Use the browser tool
Start the dev server (if not running), log in as a test user, and use the browser tool for:
- `snapshot` — check DOM structure, landmarks, forms, ARIA
- `act(kind=evaluate)` — programmatic checks (forms count, headings, aria, focus)
- `act(kind=resize)` — mobile viewport testing
- Console log inspection

### UI/UX Audit output

Prefix UI/UX findings with severity level:
- [CRITICAL] — Blocks core functionality (console errors, broken flows)
- [HIGH] — Major usability/accessibility gaps (unlabeled forms, missing nav, broken i18n)
- [MEDIUM] — Important improvements (heading hierarchy, partial i18n, dark mode polish)
- [LOW] — Polish/SEO (manifest redirects, minor untranslated strings)

### Write findings to UX_AUDIT.md
Update the project's UX_AUDIT.md with any new findings, keeping the existing report structure. Add a new round section documenting what was found.

## Branch
Working branch: {BRANCH_NAME}

## Review output format (per code-review severity levels)
Prefix every finding with its severity level:
- [CRITICAL] — Security vulnerability, data loss, production crash
- [MAJOR] — Bug, logic error, significant performance regression
- [MINOR] — Improvement reducing future maintenance cost
- [NIT] — Style preference, naming suggestion, trivial cleanup

Format each finding:
- File + line number
- Issue description
- Why it matters
- Concrete fix suggestion (with code example)

## Giving feedback (from code-review skill)
- Be specific — point to exact line and explain the issue
- Explain why — state the risk or consequence
- Suggest a fix — offer concrete alternative or code snippet
- Ask, don't demand — use questions for subjective points
- Acknowledge good work — call out clean solutions
- Separate blocking from non-blocking — use severity labels

## Retrospective format
=== RETROSPECTIVE ===
1. Files reviewed
2. Issues found (by severity count)
3. Key critical/major findings
4. Verdict (PASS/FAIL)
=== END RETROSPECTIVE ===

## Save retrospective
After reporting back, WRITE the retrospective to:
```
~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-review-round-{ROUND}.md
```
Example: `~/.openclaw/workspace/memory/2026-05-14-22-49-384-review-round-1.md`
`,
  cwd: "{REPO_PATH}",
  runtime: "subagent",
  mode: "run"
})
```

## Rules

- Timeout: 3600 (60 minutes — includes test suite + code review + UI/UX audit)
- Review ALL changes, even unfinished ones
- **MUST read code-review SKILL.md at startup** to load actual checklists — do not rely on memory
- Findings must use severity labels: [CRITICAL] [MAJOR] [MINOR] [NIT]
- Follow three-pass review process: structure → line-by-line → hardening
- **Save retrospective** to `~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-review-round-{ROUND}.md`
