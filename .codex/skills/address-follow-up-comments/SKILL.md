---
name: address-follow-up-comments
description: Handle GitHub PR follow-up review loops after automated or human comments arrive. Use when Codex needs to inspect PR comments/review threads, decide which suggestions are in scope and correct, implement fixes, update the PR body, trigger reviewers such as @codex review or /gemini review when requested, poll for follow-up comments, and repeat until there are no further actionable in-scope suggestions.
---

# Address Follow-up Comments

Use this workflow for iterative PR review follow-up. Bias toward live PR state and local source over memory or prior summaries.

## Core Workflow

1. Resolve the PR.
   - Use the user-provided PR URL/number when present.
   - Otherwise use the current branch with `gh pr view --json number,url,headRefName,baseRefName`.
   - Confirm `gh auth status` if any GitHub command fails.

2. Get enough context before editing.
   - Run `git status -sb` and inspect the current branch, remote, and local dirt.
   - Fetch thread-aware review context with `scripts/fetch_pr_review_context.py`.
   - Read the exact commented file ranges and surrounding implementation before deciding whether a suggestion is correct.
   - Treat unresolved or non-outdated review threads as candidates, but still verify against the current head commit because old threads may already be fixed.

3. Classify each suggestion.
   - Implement only suggestions that are both in scope for the PR and technically correct.
   - Ignore or explain suggestions that are stale, already fixed, out of scope, ambiguous, or would regress behavior.
   - If the user asks to fix all feedback, interpret that as all unresolved actionable in-scope feedback.

4. Implement and verify.
   - Keep edits tightly scoped to the confirmed feedback.
   - Run the smallest relevant checks, plus existing project checks when cheap.
   - Commit and push to the PR branch if this workflow is operating on a remote PR.

5. Update the PR body when useful.
   - Add a concise follow-up section with commit SHAs, review points addressed, and checks run.
   - Keep the original PR description intact unless it is stale or misleading.

6. Trigger follow-up reviewers only when requested.
   - Post exactly the trigger comments the user asks for, such as `@codex review` and `/gemini review`.
   - Do not reply to review threads, submit reviews, or mark threads resolved unless the user explicitly asks for those GitHub write actions.

7. Poll without noisy updates.
   - After posting triggers, record the trigger time and head commit.
   - Poll with `scripts/fetch_pr_review_context.py` until new bot comments/reviews arrive.
   - During long polling, avoid interval status messages unless the user asks for status.

8. Iterate to a stop condition.
   - For each new review round, repeat context gathering, classification, implementation, verification, PR-body update, and reviewer triggers when needed.
   - Stop when the latest responses from all requested reviewers for the current head commit contain no further in-scope, correct, implementable suggestions.

## Script

Use `scripts/fetch_pr_review_context.py` to fetch PR comments, reviews, and inline review threads with `isResolved` and `isOutdated`:

```bash
uv run python3 ~/.codex/skills/address-follow-up-comments/scripts/fetch_pr_review_context.py
uv run python3 ~/.codex/skills/address-follow-up-comments/scripts/fetch_pr_review_context.py --repo OWNER/REPO --pr 123
```

The script shells out to `gh api graphql`, so it requires an authenticated GitHub CLI.

## Final Response

Summarize:
- PR URL, branch, and latest commit.
- Which feedback was implemented, skipped, or found stale.
- Checks run.
- Latest reviewer status and whether the stop condition was reached.
