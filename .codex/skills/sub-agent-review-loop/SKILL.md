---
name: sub-agent-review-loop
description: Run iterative code-change review loops with fresh sub-agent pairs. Use when the user explicitly asks Codex to spawn sub-agents, reviewers, or multiple model/reasoning passes to review a patch until no confirmed in-scope issues remain, especially when they specify a loop such as "fix confirmed issues, ask reviewers again, then spawn a fresh pair until both first-turn reviews are clean."
---

# Sub-agent Review Loop

Use this skill only when the user explicitly asks for sub-agent review or delegation. The main agent owns the final decision, implementation, and validation.

## Workflow

1. Ground the scope before spawning reviewers.
   - Inspect the actual diff, changed files, test commands, user intent, and any explicit exclusions.
   - Preserve unrelated dirty files and call them out in reviewer prompts as out of scope.
   - If the user specified reviewer models or reasoning effort, use those exactly when the tools support them.

2. Spawn a reviewer pair.
   - Ask reviewers not to edit files.
   - Give them the in-scope files, intent, validation already run, and explicit exclusions.
   - Ask for only confirmed bugs, regressions, or important missing tests with file/line and reproducer.
   - Ask them to respond with `No findings.` when clean.

3. Triage findings before changing code.
   - Do not blindly accept reviewer suggestions. Read enough surrounding code and reproduce or reason from primary local evidence.
   - Treat a finding as actionable only when it is both correct and in scope for the user's requested behavior.
   - Reject or defer speculative, stylistic, theoretical, or rare edge-case findings unless the user asked to handle that edge.

4. Avoid rare edge-case creep.
   - Do not add complex code for obscure collisions or artifact-only cases unless they are part of the requested problem.
   - Examples usually out of scope: a spreadsheet formula parameter deliberately named the same as an Excel function, such as `FILTER` inside `FILTER(...)`; a literal `<think>` tag embedded inside `code_interpreter` source code when the task is about normal tool-call parsing.
   - If the user says to ignore an edge case, remove already-added special handling and matching tests for that edge.

5. Fix confirmed in-scope issues.
   - Implement the smallest patch that preserves the existing design.
   - Run focused validation after each patch.
   - Reply to the reviewer that raised the issue with what changed, why, and validation output. Ask whether the issue is resolved or whether another confirmed in-scope issue remains.
   - If a second reviewer already said `No findings`, notify them about material incremental changes and ask for a quick re-check.

6. Advance the loop.
   - When the current pair agrees there are no remaining confirmed in-scope issues, close them.
   - If that pair had any finding, fix, or scope-changing follow-up, spawn a fresh pair.
   - Stop only when a fresh pair both produce first-turn `No findings.` under the final scope.

## Reviewer Prompt Checklist

Include:

- The repository/path and exact changed files.
- The user-requested intent and explicit non-goals.
- Known unrelated dirty files to ignore.
- Validation commands and results already run.
- The expected output format: findings with evidence, or `No findings.`
- A reminder that reviewers must inspect the current diff and enough context, not just the summary.

## Final Response

Report:

- What changed.
- Which validations passed.
- That the fresh-pair first-turn clean condition was reached.
- Any unrelated dirty files that were intentionally left alone.
