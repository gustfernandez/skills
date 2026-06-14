# Inlined reviewer workflow

> **Source**: verbatim copy of `~/.claude/skills/reviewer/SKILL.md` (minus frontmatter).
> If you notice a discrepancy between this copy and the source, the source is authoritative — read it directly.

---

## Overview

Machines catch syntax (ruff, mypy, pre-commit). This stage catches semantics:

- **Layering violations** — parent importing from child package, business logic in views/serializers.
- **Sibling-pattern drift** — one service deviating from the shape its siblings share.
- **Constant hygiene** — inline literals where a named plain-class constant should be used.
- **Contract preservation** — API response shapes, error codes, DRF `raise_exception` pattern.
- **Naming correctness** — `<entity>_<action>` services, `PascalCase` classes, `kebab-case` URLs without trailing slashes.

Do NOT re-run ruff/mypy/pytest. Those are owned by pre-commit + CI.

## Mode in orchestrator context

Always run in **local mode** (default): diff source is `git diff HEAD` + `git diff --cached`.

Exact diff commands (read at runtime from `~/.claude/skills/reviewer/references/diff-resolution.md`):

```bash
git diff HEAD
git diff --cached
```

## Workflow

1. **Resolve the diff** using local mode commands above.

2. **Classify touched files.** For each changed file, identify which checklist sections apply. Read `~/.claude/skills/reviewer/references/checklist-by-file-type.md` now. Skip files not in the diff.

3. **Run the checklist** from `~/.claude/skills/reviewer/references/checklist.md` now. For each rule emit: `pass`, `fail <file>:<line> — <detail>`, or `n/a`. Collect all findings.

4. **Group findings:**
   - **Must-fix** — blocks commit; `.review-passed` will NOT be touched.
   - **Should-fix** — high risk of review round-trip; worth fixing before PR.
   - **Nit** — style or preference; mention but do not block.

5. **Output a structured report:**

   ```
   ## Review summary — local (<repo>, <branch>)

   ### Must-fix (N)
   - apis.py:42 — [layering] Parent module imports from child package `apv/constants.py`.
     Fix: promote the constant to `voluntary_savings/constants.py`.

   ### Should-fix (N)
   - serializers.py:18 — [constants] Literal "CCV" repeated. Use `ProductType.CCV`.

   ### Nit (N)
   - urls.py:5 — [naming] URL has trailing slash. Remove it.

   ### Skipped
   - migrations/0003_auto.py — auto-generated, not reviewed.
   ```

6. **Touch marker or report blockers:**
   - **Zero must-fix**: run `~/.claude/skills/reviewer/scripts/touch-review-marker.sh`. Print: `✓ Review passed — .claude/.review-passed updated.`
   - **Any must-fix**: do NOT touch the marker. Print: `✗ Review blocked — fix the must-fix items above, then the orchestrator will halt.`

   The orchestrator's REVIEW stage then reads the must-fix count to decide whether to proceed to PR-CREATE or halt.

## What NOT to flag

- **Machine-covered items**: ruff lint, ruff format, mypy type errors, django-upgrade, djlint.
- **Files not in the diff** — never review code outside the diff.

## Read at runtime

- Checklist: `~/.claude/skills/reviewer/references/checklist.md`
- Checklist by file type: `~/.claude/skills/reviewer/references/checklist-by-file-type.md`
- Diff resolution commands: `~/.claude/skills/reviewer/references/diff-resolution.md`
- Marker script: `~/.claude/skills/reviewer/scripts/touch-review-marker.sh`
