# PR Conventions

Project-agnostic PR rules and the PR-description generation procedure.
Single source of truth — `/reviewer`, `/pr-creator`, and `/orchestrator` defer here.
Adapt concrete commands/labels/base-branch to the current repo; the principles
(diff-grounded description, evidence-backed test plan, explicit scope boundaries) hold everywhere.

## Base branch

The PR is always diffed as `BASE...HEAD` — additions/changes the current branch
introduces on top of `BASE`. Never reverse the direction.

Resolve `BASE` in this order:
1. The repo's integration branch if it uses one (`development`, `develop`, `staging`).
2. Otherwise the default branch: `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name` (usually `main`).

```bash
git fetch origin "$BASE"
git diff origin/"$BASE"...HEAD > pr-diff.txt
git diff --name-only origin/"$BASE"...HEAD | wc -l   # file count
```

## PR description generation (diff-grounded)

The description body is grounded in the diff, NOT in the plan, chat, or memory.

### Grounding & accuracy rules

- Ground every concrete claim in `pr-diff.txt` or `git diff --name-only origin/$BASE...HEAD`.
- Ignore prior chat context, memory notes, previous tasks, assumptions from other branches.
- Mention symbols, models, endpoints, fields, business flows ONLY when they appear in the current diff.
- If a detail is missing, write `Not evident from diff` — never guess.
- If the diff changes only docs / instructions / skills, state there are no runtime service behavior changes and write `No runtime service behavior changes.` under Service Changes.
- Before finalizing: verify every concrete term in the description appears in `pr-diff.txt` or a changed file path.
- Cap the body at **300 words**.
- Delete `pr-diff.txt` after generating the description.

### PR body template

```markdown
## Overview
Brief summary of what this PR accomplishes.

## High-Level Architectural Changes
System design changes, new patterns, architectural decisions. Omit if none.

## Key Features
Major features added, modified, or removed.

## Service Changes
How each service/component behavior changed. `No runtime service behavior changes.` for docs-only PRs.

## Test plan
GitHub task list — RUN each check before opening; tick the box and append the real result. Cite the exact command.
- [x] `<test command + path>` — <N passed>
- [x] `<type checker / linter>` — no new errors (pre-existing baseline unchanged)
- [ ] Post-deploy / external: `<command>` (<why it can't run pre-merge>)

## Technical Details
- Files changed: X files (from `git diff --name-only origin/$BASE...HEAD | wc -l`)
- Breaking changes: None / <list>
- Related issue: #XXXX or Not evident from diff

🤖 Generated with [Claude Code](https://claude.ai/code)
```

Drop any section that has no diff-grounded content (except Overview, Service Changes, Technical Details). Add `## Screenshots` for frontend PRs (see below).

### Test plan rules

- Every claim carries evidence: exact command + result count (`4 passed`, `198 passed`), not "tests pass".
- Type-checker / linter line reads "no new errors (pre-existing baseline unchanged)" — never claim a clean baseline you didn't establish.
- Migrations / schema changes: applied + verified against a real DB, rollback roundtrip clean. If the reverse is a no-op, say so and why.
- Boxes that can't be ticked pre-merge (post-deploy loads, prod-credential steps, reviewer-side checks) stay `- [ ]` with the reason inline.

## PR title format

First line of the body. Conventional Commits, verified against the diff:
- No ticket: `<type>(<scope>): <description>`
- With ticket: `<type>(<scope>): <description> — <TICKET>`

Description is a concrete phrase, not a category. Scope = module/domain from a changed path. Omit scope if unclear.

## Commit message format

Conventional Commits: `<type>(<scope>): <subject>`

- Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`.
- Subject: imperative, lowercase, ≤ 50 chars, no trailing period.
- Body: only when the "why" isn't obvious from the subject.
- Footer:
  ```
  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
  ```

## Severity mapping (for /reviewer)

- **must-fix** — breaks tests/type checker, persists wrong data/state, missing or incorrect migration, behavior change outside stated scope, secrets/credentials in diff.
- **should-fix** — duplicated literal where a named constant exists, unhandled edge case the diff introduces, missing test for a new branch, undocumented rollback path.
- **nit** — naming, comment wording, import order. Skip unless it changes meaning.

## Notion card patterns

Priority order when parsing the plan Context or `--notion` flag:
1. `**Notion card:** <URL>`
2. `**Notion card:** <ID>`
3. `**Notion:** …` / `Notion: …`

IDs look like `ABC-123`. Omit if absent — never invent one.

## Label / scope mapping by file extension

- `.tsx`, `.ts`, `.jsx`, `.js`, `.vue`, `.css`, `.scss`, `.html` → `frontend`
- `.py`, `.rb`, `.go`, `.java`, `.rs`, `.sql` (plus server config) → `backend`
- both present → `fullstack`

## Reviewer assignment

Request Copilot via `gh pr edit "$PR_NUM" --add-reviewer @copilot`.
Use `@copilot` (with `@`) — the REST `/requested_reviewers` endpoint silently no-ops for bots.

## Screenshot requirements

Author-scoped. Frontend (`frontend` / `fullstack`) PRs include a `## Screenshots` section with at least one image, or the literal text "No visual change". Backend-only PRs omit it.

## Front/back labels

Author-scoped. Apply exactly one of `frontend` / `backend` / `fullstack` from the diff classification above. Create the label with `gh label create … --force` if missing before applying.
