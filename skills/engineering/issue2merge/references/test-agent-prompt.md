# Test Sub-agent Prompt Template

Read this reference at Step 6 when constructing the Test sub-agent task.

## Purpose

After Review passes (code is correct), this agent writes integration tests covering the diff.
It does NOT modify fix code — changes are already validated by Review.

## Template (Manager constructs this)

```javascript
sessions_spawn({
  task: `## Test Sub-agent

## Working directory (cwd)
{REPO_PATH}

## Task
Write integration tests for the code changes in this branch.

## Context

### Diff to cover
\`git diff origin/main...HEAD\`

### Issue being fixed: #{ISSUE_NUMBER}
\`\`\`
{ISSUE_BODY}
\`\`\`

## Instructions

### Step 1: Analyze the diff
Run and read:
\`\`\`bash
cd {REPO_PATH}
git diff origin/main...HEAD --stat
git diff origin/main...HEAD
\`\`\`

Identify:
- Which files changed? (views, models, templates, utilities)
- What behaviour changed? (new features? bug fixes? UI changes?)
- Which areas need tests? (auth, i18n, edge cases, error handling)

### Step 2: Determine test file location
- Integration tests → \`tests/test_issue{ISSUE_NUMBER}_integration.py\`
- App-specific unit tests → \`apps/<app>/tests/test_<feature>.py\`
- Follow existing project conventions (check recent test files for patterns)

### Step 3: Write tests
Cover these categories (as applicable to the diff):

| Category | When needed | Example |
|----------|------------|---------|
| **Happy path** | Always | Normal user action succeeds |
| **Auth / permissions** | Views changed | Login required, unauthorised = 302/403 |
| **i18n** | Templates or model strings changed | Check both en + zh-hant rendering |
| **Edge cases** | Input validation, boundaries | Empty input, max length, special chars |
| **Regression** | Bug fix | Test the exact scenario from the issue |
| **Heading hierarchy** | Templates changed | H1-H6 levels, no skips |

Test patterns (follow existing project style):
\`\`\`python
from django.test import TestCase
from django.urls import reverse

class SomeFeatureTest(TestCase):
    def setUp(self):
        # setup fixtures
        pass

    def test_happy_path(self):
        response = self.client.get(reverse("view_name"))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "expected text")
\`\`\`

### Step 4: Run your tests
\`\`\`bash
cd {REPO_PATH}
SECRET_KEY=test python -m pytest -v --tb=short tests/test_issue{ISSUE_NUMBER}_integration.py --ds=config.settings.dev 2>&1 | tail -n 40
\`\`\`

- **Tests pass** → report PASS
- **Tests fail because test is wrong** → fix the test, re-run
- **Tests fail because code is wrong** → report FAIL with details (Manager will loop back to Step 2)

### Step 5: Verify no false positives
Confirm your tests would fail WITHOUT the fix:
- If the fix is a one-liner, mentally verify
- If unsure, explain your reasoning in the retrospective

## Wait — Important Rules

- **Do NOT modify fix code.** Only write/modify test files.
- **Do NOT run git commands.** Manager handles git.
- **Do NOT run the full test suite.** Only your new test file(s) — Review already ran full suite.
- **Use Django TestCase** (not pytest fixtures) — follow project convention.
- **Test the right thing.** The test should verify the fix works, not that Django works.

## Test output format
After running tests, paste the test output (last 40 lines from pytest).

## Retrospective format
=== TEST RETROSPECTIVE ===
1. Diff summary (files changed, what they do)
2. Test file created/modified
3. Test coverage (happy path, auth, i18n, edge cases — what was tested)
4. Test result (PASS/FAIL)
5. If FAIL: what test failed and why (test bug vs code bug)
=== END TEST RETROSPECTIVE ===

## Save retrospective
After reporting back, WRITE the retrospective to:
\`~/.openclaw/workspace/memory/{YYYY-MM-DD}-{HH-MM}-{ISSUE_NUMBER}-test-round-{ROUND}.md\`
`,
  cwd: "{REPO_PATH}",
  runtime: "subagent",
  mode: "run"
})
```

## Rules

- Timeout: 600 (10 minutes — analyze diff + write tests + run)
- Must read `git diff` before writing tests
- Must run tests before reporting
- Test failures caused by bugs in fix code → report FAIL, Manager loops
- Test failures caused by test bugs → self-correct and re-run (up to 3 attempts)
- Never modify non-test files
- Save retrospective to `memory/`
