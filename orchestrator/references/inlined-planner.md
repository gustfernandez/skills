# Inlined planner workflow

> **Source**: verbatim copy of `~/.claude/skills/planner/SKILL.md` (minus frontmatter).
> If you notice a discrepancy between this copy and the source, the source is authoritative — read it directly.

---

## Overview

Use this workflow whenever writing a plan for a non-trivial code change. It explores the codebase, applies the project's standards checklist at design time, and writes the finished plan to `~/.claude/plans/<slug>.md` in the canonical six-section shape that the executor can consume directly.

**Skip for**: typo fixes, single-line renames, simple comment updates, dependency version bumps.

## Inputs

- **Task description** — from the current conversation / orchestrator invocation.
- **Target repo** — inferred from the task or cwd.
- **Ticket / issue** — any issue or ticket reference mentioned by the user.
- **Current branch / worktree path** — from `git branch --show-current` + `pwd`.

## Workflow

1. **Explore the codebase.** Launch Explore subagent(s) to map the affected slice. For multi-repo changes, one Explore per repo in parallel (max 3). Ask each agent to:
   - Identify the affected files and their current state.
   - Find sibling patterns (other services/views in the same app doing the same thing) — catches sibling-drift before the plan is written.
   - Identify existing helpers, constants, and utilities to reuse.

2. **Design the change.** While designing, validate every proposed change against the standards checklist (read at runtime from `~/.claude/skills/planner/references/standards.md`). Key checks at design time:
   - **Layering**: parent modules must not import from child packages. Promote constants up.
   - **Sibling consistency**: new service parameters must match the shape of existing siblings (required vs optional, token/client patterns, etc.).
   - **Thin views**: no JSON parsing, file orchestration, or bytes extraction in `post()`/`get()`. Push to serializer validators or mapper helpers.
   - **Single literal**: every domain value uses a named plain-class constant, not a repeated string literal.
   - **DRF pattern**: use `serializer.is_valid(raise_exception=True)` — do not reinvent with a manual `if not serializer.is_valid(): raise ApplicationError(...)` in the view.

3. **Orchestrator override — no `AskUserQuestion`**: in orchestrator mode, any decision that would normally require `AskUserQuestion` (layering direction, sibling-pattern choice, scope) is a **halt condition**. Surface the question in plain text and stop. Do NOT call `AskUserQuestion`. Do NOT assume.

4. **Write the plan.** Write to `~/.claude/plans/<descriptive-slug>.md` using the canonical sections below. Use a human-readable slug (2–4 words from the task). Do NOT use a random hash.

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
<docker compose -f <compose-file> exec django pytest ...>

# Lint + types
<docker compose -f <compose-file> exec django ruff check ...>
<docker compose -f <compose-file> exec django mypy ...>
```
```

## Common mistakes

- **Parent importing from child**: a module at `app/` must not import from `app/sub/constants.py`. Promote the constant up.
- **Fat views**: `post()`/`get()` containing `json.loads`, file orchestration, or ORM queries. Move to a `validate_<field>` method in the serializer or a mapper helper.
- **Literal repetition**: domain values appearing in serializer, mapper, and test. Define once in a plain-class constant (`class ProductType: CCV = "CCV"`), import everywhere.
- **Missing `raise_exception=True`**: do not write `if not serializer.is_valid(): raise ApplicationError(...)` in the view — use `serializer.is_valid(raise_exception=True)`.
- **Skipping "Out of scope"**: every plan must have an explicit non-goals section. It prevents scope creep during execution.
- **Sibling inconsistency**: if all sibling services declare a parameter as required, the new one must too — no `None` default + internal fallback.

## Read at runtime

Full standards checklist: `~/.claude/skills/planner/references/standards.md`
Canonical plan parsing rules (for executor): `~/.claude/skills/planner/references/canonical-plan-format.md`
