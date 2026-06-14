# Inlined pr-comments workflow

> **Source**: verbatim copy of `~/.claude/skills/pr-comments/SKILL.md` (minus frontmatter).
> If you notice a discrepancy between this copy and the source, the source is authoritative — read it directly.

---

## Overview

Use this stage when Copilot or Devin has posted unresolved inline review comments on a PR.

- Resolves **Decline** comments immediately (posts inline reply, resolves thread) — no code change needed.
- For **Fix** comments, writes a canonical 6-section plan file + a sidecar `.actions.json`, then hands off to EXECUTE stage.

This stage does NOT apply code changes, commit, or push.

## Inputs

- **PR**: from `--pr <N>`, or autodetected via `gh pr view` on the current branch.
- **Worktree**: inferred from `~/.config/superpowers/worktrees/<repo>/<branch>`. If no worktree is needed, work directly in cwd.

## Phase 0 — Preflight

1. **Resolve the PR.** Extract `owner`, `repo`, `pr_number` from the PR reference.

2. **Verify the worktree.** Get PR head branch:
   ```bash
   gh pr view <N> -R <owner>/<repo> --json headRefName --jq .headRefName
   ```
   Check for worktree. If missing:
   ```bash
   git checkout -b <branch> --track origin/<branch>
   ```

3. **Fetch unresolved AI-bot comments.** See `references/gh-snippets.md § Fetch unresolved AI-bot comments`.

4. **Fetch unresolved thread IDs.** See `references/gh-snippets.md § Fetch unresolved thread IDs`. Returns `PRRT_...` node IDs for `resolveReviewThread`.

5. **Filter re-surfaced declines.** For each unresolved thread, check if a resolved thread on the same `path:line` already has a reply starting with `Declined:`. If yes, resolve the new thread immediately with the same reply body and exclude from Phase 1.

6. **Count Copilot review rounds.** See `references/gh-snippets.md § Count Copilot review rounds`. Store as `round_number`.

7. **Bail early.** If zero unresolved AI-bot threads after filtering → print `"nothing to do"` and stop (DONE, not a halt).

## Phase 1 — Analyze + resolve declines + write plan

For each comment:
- Read the file at `path:line` in the worktree plus surrounding context (±20 lines).
- Decide **Fix** / **Decline** / **Defer**.

### Decision criteria

| Decision | When |
|---|---|
| **Fix** | Real bug, type error, layering violation, missing test, or missing OpenAPI schema. Localized, fits within executor scope. |
| **Decline** | Contradicts CLAUDE.md conventions. Cite the specific rule or prior decision. Generic disagreement not accepted. |
| **Defer** | Real issue but out of scope for this PR. Record for final summary; do not resolve. |

### Decline — immediate action

Post reply and resolve thread right now:

```bash
gh api repos/<owner>/<repo>/pulls/<N>/comments/<comment_id>/replies \
  -X POST -f body='Declined: <one-sentence reason citing the CLAUDE.md convention or prior decision>'

gh api graphql -f query='
  mutation($tid: ID!) {
    resolveReviewThread(input: {threadId: $tid}) {
      thread { id isResolved }
    }
  }' -F tid=<thread_node_id>
```

Reply must cite something specific. Do NOT write vague dismissals.

### Fix — collect into fix list

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

The `instruction` field must be precise enough for executor to apply without re-reading the original bot comment.

### If a Fix requires design judgment

Halt. Surface the comment and the decision needed in plain text. Do NOT call `AskUserQuestion`. Let the user decide and re-invoke with clarification.

### Defer — collect for final summary

Record `{comment_id, summary, reason_for_deferral}`. Do not resolve the thread.

### If fix list is empty

Print summary (k declined, p deferred, 0 fixes) and stop (DONE).

### If fix list is non-empty — write plan + sidecar

**Plan file** at `~/.claude/plans/pr-<N>-bot-comments-<YYYY-MM-DD>.md`:

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

```bash
<project test command for touched files via docker compose>
```

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

After writing both files, the orchestrator proceeds automatically to EXECUTE stage (from-sidecar mode).

## Common mistakes

- **Posting vague decline replies.** Cite the CLAUDE.md section or a prior explicit decision.
- **Touching human reviewer threads.** Only bot threads are in scope.
- **Putting business judgment in the plan.** The plan's Changes section should be executor instructions. Design judgment → halt.
- **Wrong thread ID type.** `resolveReviewThread` requires the GraphQL node ID (`PRRT_...`), not the REST `databaseId`.
- **Mismatched plan section names.** Executor is strict about canonical section names: Context, Changes, Tests, Critical files, Out of scope, Verification.
- **Forgetting the sidecar.** The sidecar `.actions.json` is what pr-finalize reads to know which threads to resolve after the push.
