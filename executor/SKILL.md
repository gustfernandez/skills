---
name: executor
description: Use immediately after plan mode exits with user approval (in any repository excluding the multiplica monorepo, which has its own multiplica-executor). Turns an approved 6-section plan from ~/.claude/plans/ into executed changes deterministically, runs Verification, and invokes the reviewer skill.
model: sonnet
---

# executor

## Overview

Turns an approved plan into executed changes deterministically. The plan is the contract — do not drift, do not expand scope, do not skip Verification.

Use immediately after plan mode exits with user approval. Pass the plan slug or path; if omitted, the most recently modified file in `~/.claude/plans/` is used.

## Inputs

- **plan** (optional) — slug (`<name>` resolves to `~/.claude/plans/<name>.md`) or absolute path. Default: most recently modified plan file in `~/.claude/plans/`.
- **dry-run** (optional flag) — describe planned actions without executing. Useful for sanity-checking before a large change.

## Workflow

1. **Read the full plan.** Parse all six canonical sections: Context, Changes, Critical files, Tests, Out of scope, Verification. See `../planner/references/canonical-plan-format.md` for parsing rules. Do not start executing until the entire plan is read.

2. **Build task list.** Call `TaskCreate` once per row in the Critical files table, in the order they appear. Each task subject = the file path + one-line summary from the table.

3. **Execute Critical files, in order.** For each row:
   - Mark the task `in_progress` before touching the file.
   - **NEW** files → use `Write`.
   - **MODIFIED** files → `Read` the file first (required before `Edit`), then apply only the change described in the Changes section for that file.
   - After writing/editing, cross-check: does the actual change match the Changes section? If drift is detected, surface it and halt.
   - **Out-of-scope guard**: before touching any file, confirm it is NOT listed under "Out of scope". If it is, halt — never silently expand scope.
   - Mark the task `completed` when done.

4. **Run Verification block.** Execute each fenced bash block from the Verification section, one at a time, in order. Wait for each to complete before starting the next.

5. **Halt on any verification failure.** If any step exits non-zero (lint, type error, or test failure):
   - Mark the current verification task `pending` (it needs a fix-and-retry, not a checkmark).
   - Surface the full failure output verbatim.
   - Do NOT invoke `/reviewer`.
   - Do NOT touch `.claude/.review-passed`.
   - Stop and wait for user direction. The user will fix and re-run.

6. **On clean verification**, invoke `/reviewer` (local mode). The reviewer's must-fix output then determines whether the `.review-passed` marker is touched.

7. **Output the result:**
   - `files_changed` — list of paths actually written/edited.
   - `verification_results` — per-step `pass`/`fail` (+ output snippet on fail).
   - `reviewer_invoked` — bool; if true, include the reviewer's findings summary.
   - `commit_recommendation` — `ready` (verification + reviewer clean) / `blocked` (any failure) / `needs_review` (subjective item for user).

## Common mistakes

- **Executing before reading all sections.** The Out-of-scope list and Verification block must be read before touching any file. Skipping this is how scope creep and broken verification happen.
- **Adding "obviously needed" code not in the plan.** If something is missing from the plan, halt and surface — do not add it. The user can update the plan and re-run the executor.
- **Skipping the Verification block** because "it'll probably pass." Always run it. The value is the guarantee, not the optimism.
- **Touching `.claude/.review-passed` yourself.** Only `reviewer` writes that marker. The executor calls the reviewer and reports its output.
- **Committing after a clean reviewer pass without user approval.** The `.review-passed` marker enables the commit hook — it does not authorize the commit. Per project convention, commits require explicit user approval.
- **Creeping via imports.** A subtle form of scope creep is editing a file because it imports something from a file you just changed. Only touch files listed in Critical files.

## References

- `../planner/references/canonical-plan-format.md` — section parsing rules (how to find Critical files table, Verification blocks, Out-of-scope items).
- `references/halt-conditions.md` — decision tree for halt vs proceed.
