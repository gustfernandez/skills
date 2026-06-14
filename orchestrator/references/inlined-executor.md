# Inlined executor workflow

> **Source**: verbatim copy of `~/.claude/skills/executor/SKILL.md` (minus frontmatter).
> If you notice a discrepancy between this copy and the source, the source is authoritative — read it directly.

---

## Overview

Turns an approved plan into executed changes deterministically. The plan is the contract — do not drift, do not expand scope, do not skip Verification.

## Workflow

1. **Read the full plan.** Parse all six canonical sections: Context, Changes, Critical files, Tests, Out of scope, Verification. See canonical-plan-format reference for parsing rules (read at runtime from `~/.claude/skills/planner/references/canonical-plan-format.md`). Do not start executing until the entire plan is read.

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
   - Stop and wait for user direction.

6. **On clean verification**, the orchestrator proceeds to the REVIEW stage (local mode). The orchestrator does not call `Skill(reviewer)` — it inlines the reviewer workflow directly.

7. **Output the result:**
   - `files_changed` — list of paths actually written/edited.
   - `verification_results` — per-step `pass`/`fail` (+ output snippet on fail).

## Common mistakes

- **Executing before reading all sections.** The Out-of-scope list and Verification block must be read before touching any file.
- **Adding "obviously needed" code not in the plan.** If something is missing from the plan, halt and surface — do not add it.
- **Skipping the Verification block** because "it'll probably pass." Always run it.
- **Touching `.claude/.review-passed` yourself.** Only the reviewer workflow writes that marker.
- **Creeping via imports.** Only touch files listed in Critical files.

## Halt conditions

See `~/.claude/skills/executor/references/halt-conditions.md` (or `references/halt-conditions.md` in this skill) for the complete decision tree.

## From-sidecar mode

When entering executor from PR-COMMENTS stage, the plan file is `~/.claude/plans/pr-<N>-bot-comments-<YYYY-MM-DD>.md`. Follow the same workflow — the plan has the same 6-section canonical format. PLAN-REVIEW is skipped for these plans.
