# Canonical Plan Format

All plans follow the six-section format below. Use these rules to parse a plan file before executing it.

## Section order

1. `## Context` — background, prior rounds, user decisions, ticket, worktree path + branch + last commit SHA.
2. `## Changes` — numbered subsections (`### 1. <file>`), each with fenced code snippets and notes.
3. `## Tests` — mock-path updates, suite to run, why existing tests still pass.
4. `## Critical files` — markdown table with columns: `File | Status | Change`.
5. `## Out of scope (explicit non-goals)` — bullet list. Everything here is forbidden to touch during execution.
6. `## Verification` — one or more fenced bash blocks to run in order.

Sections are separated by `---` horizontal rules. The title is an H1 at the top.

## Parsing rules

### Critical files table

```
| File | Status | Change |
|---|---|---|
| `path/to/file.py` | **NEW** / **MODIFIED** | One-line summary |
```

- Extract rows in the order they appear — that is the execution order.
- `**NEW**` → use `Write` (create file). `**MODIFIED**` → `Read` first, then `Edit`.
- The `Change` column is a summary; the authoritative change description is in `## Changes § N`.
- Rows marked `Possibly:` (e.g. migration files) are conditional — check whether the file was actually generated before adding it to the task list.

### Changes section

Each `### N. <path>` subsection corresponds to one Critical files row. Read the subsection to understand:
- Exact code to write/edit (fenced blocks).
- Imports to add and drop (called out explicitly).
- Sibling patterns referenced (for cross-checking after writing).

### Out of scope section

Parse every bullet point as a forbidden file or action. Before touching any file, confirm its path does not appear in this section. Common patterns:
- `Adding choices to <field>` — do not add `choices` to that field.
- `<file>.py` named explicitly — do not touch that file.
- Meta-rules like "No replies on human-reviewer threads" — apply as a behavioral constraint.

### Verification section

Find all fenced bash blocks (` ```bash ... ``` `) in the `## Verification` section. Execute them in order. Each is one verification step. A step fails if its exit code is non-zero.

Common verification block structure:
```bash
# Tests
<project test command> path/to/tests -x

# Lint + types
<project lint command> path/
<project type-check command> path/
```

### Detecting plan vs conversation context

A valid plan file has:
- An H1 title at line 1.
- All six sections present (Context, Changes, Tests, Critical files, Out of scope, Verification).
- At least one row in the Critical files table.

If any section is missing, halt and ask the user to update the plan before executing.
