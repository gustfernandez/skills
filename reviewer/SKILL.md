---
name: reviewer
description: Use to review a diff or PR for design-time semantics in any repository (excluding the multiplica monorepo, which has its own multiplica-reviewer). Catches layering violations, sibling-pattern drift, constant hygiene, contract preservation, and naming. Does NOT re-run lint/types/tests — those are owned by pre-commit + CI. Writes .claude/.review-passed marker on a clean local pass to unblock the commit/push gate.
---

# reviewer

## Overview

Machines catch syntax (ruff, mypy, pre-commit). This skill catches semantics:

- **Layering violations** — parent importing from child package, business logic in views/serializers.
- **Sibling-pattern drift** — one service deviating from the shape its siblings share.
- **Constant hygiene** — inline literals where a named plain-class constant should be used.
- **Contract preservation** — API response shapes, error codes, DRF `raise_exception` pattern.
- **Naming correctness** — `<entity>_<action>` services, `PascalCase` classes, `kebab-case` URLs without trailing slashes.
- **Commit/PR hygiene** — Conventional Commits scope, reviewer flags on PR creation.

Do NOT re-run ruff/mypy/pytest. Those are owned by pre-commit + CI.

## Modes

| Mode | Command | Diff source |
|---|---|---|
| **local** (default) | `/reviewer` | `git diff HEAD` + `git diff --cached` |
| **branch** | `/reviewer branch` | `git diff origin/<default>...HEAD` |
| **file** | `/reviewer file path/to/file.py` | Read file directly |
| **pr** | `/reviewer pr <N>` or `pr <owner>/<repo>#<N>` | `gh pr diff <N>` |

See `references/diff-resolution.md` for the exact commands per mode.

## Workflow

1. **Resolve the diff** using `references/diff-resolution.md`. For `local`/`branch`/`file` modes, resolve relative to the cwd's git repo root. For `pr` mode, resolve repo from the PR number or URL.

2. **Classify touched files.** For each changed file, identify which checklist sections apply using `references/checklist-by-file-type.md`. Skip files not in the diff.

3. **Run the checklist** from `references/checklist.md`. For each rule emit: `pass`, `fail <file>:<line> — <detail>`, or `n/a`. Collect all findings.

4. **Group findings:**
   - **Must-fix** — blocks commit; `.review-passed` will NOT be touched.
   - **Should-fix** — high risk of review round-trip; worth fixing before PR.
   - **Nit** — style or preference; mention but do not block.
   - **Recommendation** — process/hygiene reminder (screenshots, front/back label); non-blocking, never affects the marker.

5. **Output a structured report:**

   ```
   ## Review summary — <mode> (<repo>, <branch>)

   ### Must-fix (N)
   - apis.py:42 — [layering] Parent module imports from child package `apv/constants.py`.
     Fix: promote the constant to `voluntary_savings/constants.py`.

   ### Should-fix (N)
   - serializers.py:18 — [constants] Literal "CCV" repeated. Use `ProductType.CCV`.

   ### Nit (N)
   - urls.py:5 — [naming] URL has trailing slash. Remove it.

   ### Recommendation (N)
   - PR body — [pr] No `## Screenshots` section. Add one or state `No visual change`.

   ### Skipped
   - migrations/0003_auto.py — auto-generated, not reviewed.
   ```

6. **Touch marker or report blockers:**
   - **Local/branch/file, zero must-fix**: run `scripts/touch-review-marker.sh`. Print: `✓ Review passed — .claude/.review-passed updated. Commit/push gate will allow.`
   - **Local/branch/file, any must-fix**: do NOT touch the marker. Print: `✗ Review blocked — fix the must-fix items above, then re-run /reviewer.`
   - **PR mode**: never touch the marker. Print the report and wait for user action.

7. **PR mode — posting comments (explicit only).** If the user asks to post findings as inline GitHub review comments, use `gh pr review <N> --request-changes --body "..."` plus per-file inline comments via `gh api`. Do NOT post automatically.

## What NOT to flag

- **Machine-covered items**: ruff lint, ruff format, mypy type errors, django-upgrade, djlint. Pre-commit already runs these on every `Edit`/`Write`.
- **Files not in the diff** — never review code outside the diff, even if it looks suspicious.

## Common mistakes

- **Re-running ruff/mypy/pytest.** Don't. They run via pre-commit's `PostToolUse` hook on every file edit. Running them again is noise.
- **Posting `gh pr review` without explicit user approval.** In PR mode, the report is for the user first.
- **Touching `.review-passed` after a PR-mode review.** That marker gates local commits only.
- **Resolving human reviewer threads** after pushing a fix. Per project convention: push the fix and stop. The reviewer closes their own threads on re-review.
- **Flagging bot suggestions already declined.** Check existing thread history — it may be a deliberate deviation with recorded rationale.

## References

- `references/checklist.md` — full severity-tagged standards checklist (must / should / nit).
- `references/checklist-by-file-type.md` — file-type → applicable checklist sections.
- `references/diff-resolution.md` — per-mode git/gh diff commands.
- `scripts/touch-review-marker.sh` — writes the `.review-passed` marker on a clean local pass.
