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
   - When multiple reviewers are requested, post each trigger as its own PR conversation comment, not as a combined message.
   - Do not reply to review threads, submit reviews, or mark threads resolved unless the user explicitly asks for those GitHub write actions.

7. Poll without noisy updates.
   - Immediately after posting triggers, record the trigger time and head commit.
   - Poll with `scripts/fetch_pr_review_context.py` until every requested reviewer has a new response for that recorded head.
   - Treat `chatgpt-codex-connector` conversation comments or reviews as Codex responses, and `gemini-code-assist` reviews as Gemini responses.
   - If a poll fails due to a transient GitHub/API/network error, retry rather than treating the round as complete.
   - During long polling, avoid interval status messages unless the user asks for status.

8. Iterate to a stop condition.
   - For each new review round, repeat context gathering and classify only current-head feedback plus unresolved non-outdated threads that are still applicable to the current code.
   - Treat old unresolved threads as stale when the exact issue is already fixed or the latest reviewer response for the current head says there are no comments to address.
   - If any in-scope, correct, implementable suggestion is found, implement it, verify it, commit and push it to the PR branch, update the PR body with a concise follow-up section, then re-trigger the same requested reviewers and poll again.
   - Stop only when all requested reviewers have responded to the latest head commit and there are no remaining in-scope, correct, implementable suggestions.

## Script

Use `scripts/fetch_pr_review_context.py` to fetch PR comments, reviews, and inline review threads with `isResolved` and `isOutdated`:

```bash
uv run python3 ~/.codex/skills/address-follow-up-comments/scripts/fetch_pr_review_context.py
uv run python3 ~/.codex/skills/address-follow-up-comments/scripts/fetch_pr_review_context.py --repo OWNER/REPO --pr 123
```

The script shells out to `gh api graphql`, so it requires an authenticated GitHub CLI.
If the current repository's Python project dependencies make plain `uv run` fail, use `uv run --no-project python3 ...` with the same script arguments.

## Final Response

Summarize:
- PR URL, branch, and latest commit.
- Which feedback was implemented, skipped, or found stale.
- Checks run.
- Latest reviewer status and whether the stop condition was reached.
