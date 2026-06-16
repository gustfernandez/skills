---
name: pr-creator
description: Use after /reviewer passes (.review-passed marker exists) to stage, commit, push, create a PR, and request Copilot as reviewer. Pass --auto-merge to enable squash auto-merge. Also supports manual mode (--manual --type <T> --description <D> [--scope <S>] [--notion <X>]) without requiring a .review-passed marker. All naming and reviewer rules defer to ~/.claude/skills/conventions/pr.md. No front/back GitHub label is applied. Works in any repository except the multiplica monorepo (use multiplica-pr-creator there).
model: sonnet
---

# pr-creator

## Overview

Bridges the gap between a clean reviewer pass and an open PR. In one shot:

1. Verifies `.review-passed` exists (plan-mode gate — skipped in manual mode).
2. Creates a feature branch if currently on the default branch.
3. Stages the Critical files from the active plan (plan-mode) or `git diff --cached` (manual mode), commits, and pushes.
4. Creates a GitHub PR with title and body per `~/.claude/skills/conventions/pr.md`.
5. Requests Copilot as reviewer.
6. If `--auto-merge` was passed, enables squash auto-merge.
7. Deletes `.review-passed` and exits the worktree if running inside one.

**Invoking this skill is the explicit user approval** for the commit + push that `executor` deferred. Only invoke when you want to ship the current state.

## Inputs

- **`--auto-merge`** (optional) — enable squash auto-merge after PR creation.
- **`--manual`** — skip the `.review-passed` gate and derive context from flags instead of the active plan.
- **`--type <type>`** (manual mode) — Conventional Commits type: `feat | fix | refactor | chore | docs | test | ci`.
- **`--description <desc>`** (manual mode) — short description (becomes the commit + PR title description).
- **`--scope <scope>`** (manual mode, optional) — app or domain scope; omit if unclear.
- **`--notion <URL-or-ID>`** (manual mode, optional) — Notion card URL or bare ID (e.g. `MLTPB-17`).

## Workflow

### Step 1 — Gate

**Plan-mode** (default):
```bash
ls .claude/.review-passed
```
If the file is missing:
```
Blocked: .claude/.review-passed not found.
Run /reviewer first. The commit gate requires a clean reviewer pass.
```
Stop. Do not proceed.

**Manual mode** (`--manual` flag present): skip the gate entirely.

### Step 2 — Resolve context

**Plan-mode:**
Read the most recently modified plan in `~/.claude/plans/` (or the plan passed as argument). Extract ONLY:
- **Plan title** (first `#` heading) → commit message + PR title seed (verified against the diff).
- **Context section** → Notion card extraction.
- **Critical files table** → exact set of files to stage.
- **Verification section** → which checks to RUN; their results become the Test plan boxes.
- **Commit type** → infer from plan title (`feat` / `fix` / `refactor` / `chore` / `docs` / `test` / `ci`).
- **Scope** → infer from the app or domain name in the plan title (omit if unclear).

**The PR body is diff-grounded, not plan-derived.** Per `~/.claude/skills/conventions/pr.md`, generate the description from `pr-diff.txt` (Step 7), not from the plan prose, chat, or memory. The plan only supplies title/scope/Notion/which-files above.

If no plan is found, fall back to manual-mode behavior.

**Manual mode:**
- Type, description, scope from CLI flags.
- Files to stage: `git diff --cached` if anything is staged; otherwise `git diff` (unstaged).
- Summary bullets: derive from the description (single bullet is fine).
- Test plan: a GitHub task list of the checks you actually ran, e.g. `- [x] Verified locally.` (see conventions — run before opening, open with boxes checked).

**Notion extraction (both modes):**
Parse the plan Context or `--notion` flag per `~/.claude/skills/conventions/pr.md` — Notion card patterns in priority order:
1. `**Notion card:** <URL>`
2. `**Notion card:** <ID>`
3. `**Notion:** …` / `Notion: …`

### Step 3 — Branch handling

```bash
CURRENT=$(git branch --show-current)
DEFAULT=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || echo main)
```

**If `CURRENT == DEFAULT`** — create a feature branch from the plan slug (or description slug in manual mode):
```bash
git checkout -b <type>/<slug>
```
Print: `Created branch <branch>.`

**If `CURRENT != DEFAULT`** — use the current branch as-is.

### Step 4 — Classify front/back (for the screenshot decision only)

```bash
git diff --name-only origin/$DEFAULT...HEAD
```

Match extensions per `~/.claude/skills/conventions/pr.md` to decide whether a `## Screenshots` section is required:
- `frontend` — only `.tsx | .ts | .jsx | .js | .vue | .css | .scss | .html`
- `backend` — only `.py | .sql` (plus configs)
- `fullstack` — both

**No GitHub label is applied** — labels are off per `~/.claude/skills/conventions/pr.md`. Use the result only to gate Step 7's Screenshots section.

### Step 5 — Stage and commit

**Plan-mode:** stage only the files from the Critical files table:
```bash
git add <file1> <file2> ...
```

**Manual mode:** stage `git diff --cached` as-is (or add all unstaged if nothing is cached).

Commit with Conventional Commits format per `~/.claude/skills/conventions/pr.md`:
```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <description>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

### Step 6 — Push

```bash
git push -u origin HEAD
```

Never `--force` or `--no-verify`.

### Step 7 — Create PR (or update existing)

Check for an existing PR:
```bash
PR_NUM=$(gh pr view --json number --jq .number 2>/dev/null)
```

First, generate the diff that grounds the description (BASE resolved per `~/.claude/skills/conventions/pr.md`):
```bash
git fetch origin "$BASE"
git diff origin/"$BASE"...HEAD > pr-diff.txt
git diff --name-only origin/"$BASE"...HEAD | wc -l   # file count for Technical Details
```

Build the title (first body line) per `~/.claude/skills/conventions/pr.md`:
- No ticket: `<type>(<scope>): <description>`
- With ticket: `<type>(<scope>): <description> — <TICKET>`

Build the body from the **PR body template + grounding rules** in the conventions file — every concrete claim must appear in `pr-diff.txt` or a changed path, ≤ 300 words, `Not evident from diff` where unknown. For frontend PRs (LABEL = `frontend` / `fullstack`) include a `## Screenshots` section.

```bash
gh pr create --title "<title>" --body "<diff-grounded body per conventions/pr.md>"
PR_NUM=$(gh pr view --json number --jq .number)
```

If a PR already exists, skip creation and use the existing `PR_NUM`.

### Step 8 — Request Copilot review

```bash
gh pr edit "$PR_NUM" --add-reviewer @copilot
```

Note: `@copilot` (with `@`) is the correct alias for `gh`. The REST `/requested_reviewers` endpoint silently no-ops for bots; `@copilot` via `gh pr edit` is the only form that works.

### Step 9 — Auto-merge (only if `--auto-merge` was passed)

```bash
gh pr merge "$PR_NUM" --auto --squash
```

Print: `Auto-merge enabled (squash).`

### Step 10 — Output

```
PR #<N>: <title>
Branch: <branch>
Commit: <short sha>
Reviewer: Copilot requested
Auto-merge: <enabled | disabled>
URL: <pr url>
```

### Step 11 — Cleanup

Delete the review gate marker and the diff scratch file so they do not accumulate across branches:
```bash
rm -f .claude/.review-passed pr-diff.txt
```

If the current working directory is inside a worktree (path contains `.claude/worktrees/`), call the `ExitWorktree` tool to remove the worktree and return to the main tree. Do this **after** printing the Step 10 output so the URL is visible before the context switches.

## Common mistakes

- **Skipping the `.review-passed` gate in plan-mode.** Never proceed if the file is missing.
- **Using `git add .`** instead of staging only Critical files.
- **Wrong Copilot alias.** Use `@copilot` — not `Copilot`, not `copilot-pull-request-reviewer`.
- **Committing before reading the full plan.** The commit message must match the plan's intent.
- **Applying a front/back GitHub label.** Labels are off — never run `gh pr edit --add-label` or `gh label create`. Classification is used only to decide the Screenshots section.
- **Hardcoding rules in this file.** Naming, reviewer, screenshot, and ticket rules belong in `~/.claude/skills/conventions/pr.md`.
- **Omitting the screenshot section on frontend PRs.** Always include the `## Screenshots` placeholder in the body; the author fills it before merging.

## References

- `~/.claude/skills/conventions/pr.md` — all PR naming, reviewer, and screenshot rules.
- `../reviewer/SKILL.md` — writes the `.review-passed` marker this skill gates on.
- `../executor/SKILL.md` — applies the code changes; this skill ships them.
- `../pr-comments/SKILL.md` — handles bot feedback after the PR is open.
