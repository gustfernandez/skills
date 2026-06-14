---
name: pr-comments
description: Use when handling unresolved bot or human review comments on a GitHub PR (in any repository excluding the multiplica monorepo, which has its own multiplica-pr-comments). Analyzes comments, declines inline immediately for items not worth fixing, writes a 6-section plan for fix items, and emits a sidecar JSON for the pr-finalize skill.
---

# pr-comments

## Overview

Use this skill when Copilot or Devin has posted unresolved inline review comments on a PR and you want to handle them using the same plan→execute→review rails as every other code change.

**What this skill does:**
- Resolves **Decline** comments immediately (posts inline reply, resolves thread) — no code change needed.
- For **Fix** comments, writes a canonical 6-section plan file at `~/.claude/plans/` + a sidecar `.actions.json`, then hands off to `executor`.
- After the user pushes the fixes, `/pr-finalize` posts "Fixed in `<sha>`" replies, resolves fix threads, and handles the gated Copilot re-request (auto rounds 1–2, asks after).

**What this skill does NOT do:**
- It does not apply code changes (that's the executor's job).
- It does not commit or push (the user does that; the `.review-passed` gate applies).
- It does not touch human reviewer threads (humans close their own threads — convention).

## Inputs

- **PR**: `pr <N>`, `pr <owner>/<repo>#<N>`, or a GitHub PR URL. Single PR per invocation.
- **Worktree**: inferred from `~/.config/superpowers/worktrees/<repo>/<branch>` (superpowers convention). If a worktree is not needed, work directly in the cwd.

## Workflow

### Phase 0 — Preflight

1. **Resolve the PR.** Extract `owner`, `repo`, `pr_number` from the argument.

2. **Verify the worktree.** Determine the PR's head branch (`gh pr view <N> -R <owner>/<repo> --json headRefName --jq .headRefName`). Check for the worktree at `~/.config/superpowers/worktrees/<repo>/<branch>`. If missing and one is needed, set up a tracking branch from the cwd:
   ```bash
   git checkout -b <branch> --track origin/<branch>
   ```

3. **Fetch unresolved AI-bot comments.** See `references/gh-snippets.md § Fetch unresolved AI-bot comments`.

4. **Fetch unresolved thread IDs.** See `references/gh-snippets.md § Fetch unresolved thread IDs`. This GraphQL query returns the `PRRT_...` node IDs needed for `resolveReviewThread`.

5. **Filter re-surfaced declines.** For each unresolved thread, check whether a *resolved* thread on the same `path:line` already has a reply starting with `Declined:`. If yes, resolve the new thread immediately with the same reply body and exclude it from Phase 1 analysis.

6. **Count Copilot review rounds.** See `references/gh-snippets.md § Count Copilot review rounds`. Store as `round_number`.

7. **Bail early.** If zero unresolved AI-bot threads after filtering → print `"nothing to do"` and stop.

### Phase 1 — Analyze + resolve declines + write plan

For each comment:

- Read the file at `path:line` in the worktree plus surrounding context (typically ±20 lines). Also read any sibling files if the comment references a pattern.
- Decide **Fix** / **Decline** / **Defer**.

#### Decision criteria

| Decision | When |
|---|---|
| **Fix** | The comment identifies a real bug, type error, layering violation, missing test, or missing OpenAPI schema. The change is localized and fits within `executor`'s scope. |
| **Decline** | The suggestion contradicts the project's CLAUDE.md conventions. Always cite the specific rule or prior decision. Generic disagreement is not accepted. |
| **Defer** | The comment identifies a real issue but the fix is out of scope for this PR (e.g. architectural refactor, new feature). Record for the final summary; do not resolve. |

#### Decline — immediate action (in this phase)

Post the inline reply and resolve the thread right now. No code change is involved so there is no reason to wait.

```bash
# Post the reply
gh api repos/<owner>/<repo>/pulls/<N>/comments/<comment_id>/replies \
  -X POST -f body='Declined: <one-sentence reason citing the CLAUDE.md convention, prior decision, or tradeoff>'

# Resolve the thread
gh api graphql -f query='
  mutation($tid: ID!) {
    resolveReviewThread(input: {threadId: $tid}) {
      thread { id isResolved }
    }
  }' -F tid=<thread_node_id>
```

Reply must cite something specific. Do NOT write vague dismissals.

#### Fix — collect into fix list

For each fix, record:
```json
{
  "thread_id": "PRRT_...",
  "comment_id": 31633,
  "file": "path/to/file.py",
  "line": 42,
  "summary": "one sentence describing the fix",
  "instruction": "precise instruction for executor: exact file:line, what to change, import adjustments"
}
```

The `instruction` field must be precise enough for `executor` to apply without re-reading the original bot comment.

#### Defer — collect for final summary

Record in the deferred list: `{comment_id, summary, reason_for_deferral}`. Do not resolve the thread.

#### If fix list is empty

Print a summary (k declined, p deferred, 0 fixes) and stop. Optionally run `/pr-finalize <PR>` to handle the gated Copilot re-request.

#### If fix list is non-empty — write plan + sidecar

**Plan file** at `~/.claude/plans/pr-<N>-bot-comments-<YYYY-MM-DD>.md` in the canonical 6-section format:

```markdown
# <repo> — PR #<N> bot-comment fixes (round <round_number+1>)

## Context
PR: <owner>/<repo>#<N>
Round: <round_number+1> (Copilot has reviewed <round_number> time(s) so far).
Branch: <branch>, worktree: <worktree_path>.

Fixing <k> bot inline comments. Declined <m> inline (replies posted + threads resolved).
<Deferred: p items surfaced below in Out of scope.>

Fix comment IDs (for cross-reference): <comma-separated comment_ids>.

---

## Changes

### 1. <file path>
<Precise fix with code snippet. Note imports added/dropped. Reference the bot comment summary.>

---

## Tests
<Which existing tests still pass. New tests if a comment requested coverage.>

---

## Critical files

| File | Status | Change |
|---|---|---|
| `path/to/file.py` | **MODIFIED** | One-line summary. |

---

## Out of scope (explicit non-goals)
- Declined comments (already resolved inline): <brief list with rationale>
- Deferred items: <brief list with deferral reason>
- No replies to human reviewer threads.

---

## Verification

\`\`\`bash
<project test command for touched files>
\`\`\`

/reviewer
```

**Sidecar state file** at `~/.claude/plans/pr-<N>-bot-comments-<YYYY-MM-DD>.actions.json`:

```json
{
  "pr": {"owner": "<owner>", "repo": "<repo>", "number": 42},
  "worktree": "/path/to/worktree",
  "branch": "<branch>",
  "round_number": 1,
  "fix_threads": [
    {"thread_id": "PRRT_...", "comment_id": 31633, "file": "...", "line": 42, "summary": "..."}
  ],
  "declined_threads_already_resolved": [
    {"thread_id": "PRRT_...", "comment_id": 31633, "reply_posted": true}
  ],
  "deferred": [
    {"comment_id": 31633, "reason": "..."}
  ]
}
```

`/pr-finalize` reads the sidecar after the user pushes.

#### Final output

Print:
- Plan file path + sidecar path
- `<repo>#<N>: k fixes planned, m declined (resolved inline), p deferred — round <round_number+1>`
- `Review the plan; approve to continue. After executor runs and you push, run /pr-finalize pr-<N>-bot-comments-<YYYY-MM-DD>.`

### Handoff — existing rails (no action needed here)

1. User reviews the plan, approves via ExitPlanMode.
2. `executor` walks the Critical files table, applies edits, runs Verification.
3. Executor auto-invokes `/reviewer` (local) on clean verification.
4. Reviewer touches `.claude/.review-passed`. The commit/push gate unblocks.
5. User commits + pushes (no push without explicit approval).
6. User runs `/pr-finalize pr-<N>-bot-comments-<YYYY-MM-DD>`.

## Common mistakes

- **Posting vague decline replies.** "Declined: not needed" is not acceptable. Cite the CLAUDE.md section or a prior explicit decision.
- **Resolving human reviewer threads.** Only bot threads are in scope. Don't touch human reviewer threads.
- **Putting business judgment in the plan.** The plan's Changes section should be executor instructions, not open-ended questions. If a fix requires design judgment, use `AskUserQuestion` before writing the plan.
- **Wrong thread ID type.** `resolveReviewThread` requires the GraphQL node ID (`PRRT_...`), not the REST `databaseId`. The Phase 0 GraphQL query returns both — use `.id` for resolution.
- **Mismatched plan section names.** `executor` is strict about canonical section names: `Context`, `Changes`, `Tests`, `Critical files`, `Out of scope`, `Verification` (with the exact trailing `/reviewer` call in the Verification block). A renamed or missing section causes the executor to halt.
- **Forgetting the sidecar.** The sidecar `.actions.json` is what `/pr-finalize` reads to know which threads to resolve after the push.

## References

- `references/gh-snippets.md` — all `gh api` and GraphQL commands used in this skill.
- `executor` skill — walks the plan produced here.
- `pr-finalize` skill — post-push cleanup (fix-thread resolution + gated Copilot re-request).
