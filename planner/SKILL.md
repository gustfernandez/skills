---
name: planner
description: Use when planning a non-trivial code change in any repository (excluding the multiplica monorepo, which has its own multiplica-planner). Writes a 6-section canonical plan to ~/.claude/plans/<slug>.md that the executor skill can consume directly. Skip for typo fixes, single-line renames, simple comment updates, dependency version bumps.
---

# planner

## Overview

Use this skill whenever you are about to plan a non-trivial code change. It explores the codebase, applies the project's standards checklist *at design time*, and writes the finished plan to `~/.claude/plans/<slug>.md` in the canonical six-section shape that `executor` can consume directly.

**Skip for**: typo fixes, single-line renames, simple comment updates, dependency version bumps.

## Inputs

- **Task description** — from the current conversation.
- **Target repo** — inferred from the task or cwd.
- **Ticket / issue** — any issue or ticket reference mentioned by the user.
- **Current branch / worktree path** — from `git branch --show-current` + `pwd`.

## Workflow

1. **Explore the codebase.** Launch Explore subagent(s) to map the affected slice. For multi-repo changes, one Explore per repo in parallel (max 3). Ask each agent to:
   - Identify the affected files and their current state.
   - Find sibling patterns (other services/views in the same app doing the same thing) — catches sibling-drift before the plan is written.
   - Identify existing helpers, constants, and utilities to reuse.

2. **Design the change.** While designing, validate every proposed change against `references/standards.md`. Key checks at design time:
   - **Layering**: parent modules must not import from child packages. Promote constants up.
   - **Sibling consistency**: new service parameters must match the shape of existing siblings (required vs optional, token/client patterns, etc.).
   - **Thin views**: no JSON parsing, file orchestration, or bytes extraction in `post()`/`get()`. Push to serializer validators or mapper helpers.
   - **Single literal**: every domain value uses a named plain-class constant, not a repeated string literal.
   - **DRF pattern**: use `serializer.is_valid(raise_exception=True)` — do not reinvent with a manual `if not serializer.is_valid(): raise ApplicationError(...)` in the view.

3. **Ask before deciding.** Use `AskUserQuestion` for any decision that affects scope, layering direction, or sibling-pattern choice. Never assume — the plan is the contract that `executor` follows.

4. **Write the plan.** Write to `~/.claude/plans/<descriptive-slug>.md` using the canonical sections below. Use a human-readable slug (2–4 words from the task). Do NOT use a random hash.

5. **Call ExitPlanMode.**

## Plan template

```markdown
# <repo> — <brief task title>

## Context
<Why this change is being made. Prior rounds / reviewer threads if applicable.
User decisions from AskUserQuestion, labeled by decision point.
Ticket/issue if any. Worktree path + branch + last commit SHA.>

---

## Changes

### 1. <File path or new component>
<Code snippets in fenced blocks. Note imports added/dropped explicitly.
Call out sibling patterns matched. Explain why (layering, contract preservation, etc.)>

---

## Tests
<Mock-path updates, test suite to run, why existing tests still pass.>

---

## Critical files

| File | Status | Change |
|---|---|---|
| `path/to/file.py` | **NEW** / **MODIFIED** | One-line summary. |

---

## Out of scope (explicit non-goals)
- <Item 1>
- No replies on human-reviewer threads — push the fix, reviewer closes on re-review.

---

## Verification

```bash
# Tests
<test command>

# Lint + types
<lint command>
<type-check command>
```

After all checks pass: commit + push **only after explicit user approval**.
```

## Common mistakes

- **Parent importing from child**: a module at `app/` must not import from `app/sub/constants.py`. Promote the constant up.
- **Fat views**: `post()`/`get()` containing `json.loads`, file orchestration, or ORM queries. Move to a `validate_<field>` method in the serializer or a mapper helper.
- **Literal repetition**: domain values appearing in serializer, mapper, and test. Define once in a plain-class constant (`class ProductType: CCV = "CCV"`), import everywhere.
- **Missing `raise_exception=True`**: do not write `if not serializer.is_valid(): raise ApplicationError(...)` in the view — use `serializer.is_valid(raise_exception=True)`.
- **Skipping "Out of scope"**: every plan must have an explicit non-goals section. It prevents scope creep during execution.
- **Sibling inconsistency**: if all sibling services declare a parameter as required, the new one must too — no `None` default + internal fallback.

## References

- `references/standards.md` — full 12-category standards inventory.
- `references/canonical-plan-format.md` — canonical plan parsing rules (consumed by `executor`).
