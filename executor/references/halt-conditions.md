# Halt Conditions

Decision tree for when to stop execution and surface an issue vs when to proceed.

## Before execution starts

| Condition | Action |
|---|---|
| Plan file not found at the resolved path | Halt. Surface: "Plan not found at `<path>`. Run /planner to create one, or pass an explicit path." |
| Plan is missing one or more canonical sections | Halt. Surface which sections are missing. Ask user to update the plan. |
| No rows in the Critical files table | Halt. Surface: "Critical files table is empty. Nothing to execute." |
| `dry-run` flag passed | Print each planned action without executing. Do not halt — this is expected. Exit after printing. |

## During file execution

| Condition | Action |
|---|---|
| File to be written/edited is listed in "Out of scope" | **Halt immediately.** Surface: "Execution halted — `<file>` is listed under 'Out of scope'. Update the plan to include it, or skip this change." Do not write the file. |
| File in Critical files table not found in cwd's git repo | Surface as a warning, ask whether to create it (if NEW) or skip (if MODIFIED and the path may be wrong). Do not auto-create ambiguous paths. |
| Actual change drifts from the Changes section description | Surface the drift. Ask the user: "The plan says X but I'm about to write Y. Proceed?" Do not silently diverge. |
| `Edit` would fail because `old_string` is not unique | Read the file to find the correct context, update the edit, and document the adjustment in the output report as a minor drift. Do not halt. |
| File is an auto-generated migration | Only write it if it was explicitly listed in Critical files (not under "Possibly:"). For "Possibly:" rows, run `makemigrations --dry-run` first — write the file only if Django actually emits it. |

## During verification

| Condition | Action |
|---|---|
| Verification step exits non-zero (test failure) | **Halt.** Mark task `pending`. Surface full output verbatim. Do NOT invoke reviewer. Do NOT touch marker. |
| Verification step exits non-zero (lint failure) | **Halt.** Same as above. Lint is non-negotiable. |
| Verification step exits non-zero (type error) | **Halt.** Same as above. Types are non-negotiable. |
| Verification step exits non-zero (migration check) | **Halt** if unexpected migration was emitted. Surface the generated file; ask whether to include it. |
| Verification step times out (>5 min) | Surface a warning, ask user whether to wait or abort. Default: wait up to 10 min total. |
| All verification steps pass | Proceed to invoke `/reviewer` (local mode). |

## After reviewer runs

| Condition | Action |
|---|---|
| Reviewer reports zero must-fix | `reviewer` touches `.review-passed`. Report `commit_recommendation: ready`. |
| Reviewer reports ≥1 must-fix | Marker NOT touched. Report `commit_recommendation: blocked`. Surface must-fix items. |
| Reviewer reports only should-fix / nit | Marker IS touched (no must-fix). Report `commit_recommendation: needs_review` — surface the items for the user to decide. |

## Never do

- Never auto-commit after a clean pass. Explicit user approval required.
- Never push. Explicit user approval required.
- Never retry a failing verification step in a loop. Surface and stop — the user directs the fix.
- Never mark a task `completed` if its verification failed. Use `pending`.
- Never write to `.claude/.review-passed` — only `reviewer` does that.
