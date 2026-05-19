# Grouping Strategy

Read this reference at Step 1 when categorizing issues into groups for parallel sub-agents.

## Classification Priority

1. **By affected file** — issues targeting the same file/group of files → same group
2. **By problem type** — same category (lint / logic / missing tests / docs)
3. **By severity** — blocking issues segregated from minor ones
4. **Cross-file** — distribute to the most relevant group

## Constraints

| Rule | Reason |
|------|--------|
| Max 4 groups | Parallel agent limit |
| Max 20 issues per group | Prevent sub-agent overload |
| Keep groups homogeneous | Don't mix unrelated issue types |

## Output Format

```
=== GROUPING ===
Group A: (src/feature.ts, src/utils.ts) — 5 issues — #{416}: 1,3,7,12,14
Group B: (tests/feature.test.ts) — 3 issues — #{416}: 2,5,9
Group C: (docs/README.md, docs/api.md) — 2 issues — #{416}: 8,15
=== END GROUPING ===
```
