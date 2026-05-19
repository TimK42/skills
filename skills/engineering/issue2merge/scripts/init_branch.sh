#!/bin/bash
# init_branch.sh — Create branch + Draft PR for manager fix loop
# Usage: scripts/init_branch.sh <repo-path> <issue-numbers> <branch-name> <repo-full>
#   issue-numbers: comma-separated, e.g. "660,661,662"

set -euo pipefail

REPO_PATH="$1"
ISSUE_LIST="$2"
BRANCH_NAME="$3"
REPO_FULL="$4"

cd "$REPO_PATH"

# Parse first issue as primary (for branch naming / title)
PRIMARY_ISSUE="${ISSUE_LIST%%,*}"

# Fetch latest
git checkout main
git pull origin main

# Handle PENDING_FIXES.md: delete from main if it exists (avoids merge conflicts)
if git show main:PENDING_FIXES.md >/dev/null 2>&1; then
  git rm PENDING_FIXES.md
  git commit -m "chore: remove stale PENDING_FIXES.md from main"
  git push origin main
fi

# Create branch
git checkout -b "$BRANCH_NAME"
git push -u origin "$BRANCH_NAME"

# Placeholder commit
echo "# $ISSUE_LIST fixes — started" > PENDING_FIXES.md
git add PENDING_FIXES.md
git commit -m "chore: start work on issue #$PRIMARY_ISSUE"
git push

# Build body with all Closes lines
CLOSES_BODY=""
IFS=',' read -ra ISSUES <<< "$ISSUE_LIST"
for iss in "${ISSUES[@]}"; do
  CLOSES_BODY+="Closes #$iss"$'\n'
done

# Create Draft PR
gh pr create \
  --title "fix($PRIMARY_ISSUE): address issues from #$PRIMARY_ISSUE and related" \
  --body "$CLOSES_BODY" \
  --draft \
  --base main

# Output PR number
PR_NUMBER=$(gh pr view --json number --jq '.number')
echo "PR_NUMBER=$PR_NUMBER"
