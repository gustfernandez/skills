# Inlined pr-creator workflow

> **Source**: verbatim copy of `~/.claude/skills/pr-creator/SKILL.md` (minus frontmatter).
> If you notice a discrepancy between this copy and the source, the source is authoritative — read it directly.

---

## Overview

Bridges the gap between a clean reviewer pass and an open PR. In one shot:

1. Verifies `.review-passed` exists (plan-mode gate).
2. Creates a feature branch if currently on the default branch.
3. Stages the Critical files from the active plan, commits, and pushes.
4. Creates a GitHub PR with title and body per PR conventions.
5. Detects frontend/backend/fullstack and applies the matching label.
6. Requests Copilot as reviewer.
7. If `--auto-merge` was passed, enables squash auto-merge.

**Invoking this stage is the explicit user approval** for the commit + push that executor deferred.

All naming, labeling, and reviewer rules read at runtime from `~/.claude/skills/conventions/pr.md`.

## Step 1 — Gate

```bash
ls .claude/.review-passed
```

If the file is missing:
```
Blocked: .claude/.review-passed not found.
Run the REVIEW stage first. The commit gate requires a clean reviewer pass.
```
Stop. Do not proceed.

## Step 2 — Resolve context

Read the most recently modified plan in `~/.claude/plans/` (or the plan passed with `--plan`). Extract:
- **Plan title** (first `#` heading) → commit message + PR title.
- **Context section** → PR body summary + Notion card extraction.
- **Critical files table** → exact set of files to stage.
- **Verification section** → Test plan bullets in PR body.
- **Commit type** → infer from plan title (`feat` / `fix` / `refactor` / `chore` / `docs` / `test` / `ci`).
- **Scope** → infer from the app or domain name in the plan title (omit if unclear).

**Notion extraction (both modes):**
Parse the plan Context per PR conventions — Notion card patterns in priority order:
1. `**Notion card:** <URL>`
2. `**Notion card:** <ID>`
3. `**Notion:** …` / `Notion: …`

## Step 3 — Branch handling

```bash
CURRENT=$(git branch --show-current)
DEFAULT=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || echo main)
```

**If `CURRENT == DEFAULT`** — create a feature branch from the plan slug:
```bash
git checkout -b <type>/<slug>
```

**If `CURRENT != DEFAULT`** — use the current branch as-is.

## Step 4 — Classify front/back

```bash
git diff --name-only origin/$DEFAULT...HEAD
```

Match extensions per PR conventions:
- `frontend` — only `.tsx | .ts | .jsx | .js | .vue | .css | .scss | .html`
- `backend` — only `.py | .sql` (plus configs)
- `fullstack` — both

Store as `LABEL`.

## Step 5 — Stage and commit

Stage only the files from the Critical files table:
```bash
git add <file1> <file2> ...
```

Commit with Conventional Commits format per PR conventions:
```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <description>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

## Step 6 — Push

```bash
git push -u origin HEAD
```

Never `--force` or `--no-verify`.

## Step 7 — Create PR (or update existing)

Check for an existing PR:
```bash
PR_NUM=$(gh pr view --json number --jq .number 2>/dev/null)
```

**If a PR already exists**: skip creation, use the existing `PR_NUM`. (This is the re-entry path after pr-comments → executor → reviewer.)

**If no PR exists**: create one:

```bash
gh pr create \
  --title "<title>" \
  --body "$(cat <<'EOF'
## Summary
<2–3 bullets>

## Test plan
<GitHub task list; RUN before opening the PR, check the boxes for what passed:>
- [x] <verification step you ran, e.g. tests / build / lint from the plan>
- [ ] <only-post-merge or reviewer-side step — label why unchecked>

<!-- FRONTEND: add ## Screenshots section with at least one screenshot, or write "No visual change" -->

Notion: <full URL or ID, omit line if absent>

🤖 Generated with [Claude Code](https://claude.ai/code)
EOF
)"
PR_NUM=$(gh pr view --json number --jq .number)
```

## Step 8 — Apply front/back label

```bash
gh label create frontend  --color 0075ca --force
gh label create backend   --color e4e669 --force
gh label create fullstack --color d93f0b --force
gh pr edit "$PR_NUM" --add-label "$LABEL"
```

## Step 9 — Request Copilot review

```bash
gh pr edit "$PR_NUM" --add-reviewer @copilot
```

Note: `@copilot` (with `@`) is the correct alias. REST endpoint silently no-ops for bots.

## Step 10 — Auto-merge (only if `--auto-merge` was passed)

```bash
gh pr merge "$PR_NUM" --auto --squash
```

## Step 11 — Output

```
PR #<N>: <title>
Branch: <branch>
Commit: <short sha>
Label: <frontend|backend|fullstack>
Reviewer: Copilot requested
Auto-merge: <enabled | disabled>
URL: <pr url>
```

## Common mistakes

- **Skipping the `.review-passed` gate.** Never proceed if the file is missing.
- **Using `git add .`** instead of staging only Critical files.
- **Wrong Copilot alias.** Use `@copilot` — not `Copilot`, not `copilot-pull-request-reviewer`.
- **Omitting the screenshot section on frontend PRs.** Always include the `## Screenshots` placeholder.
- **Hardcoding rules.** Naming, labeling, reviewer, screenshot, and ticket rules are in `~/.claude/skills/conventions/pr.md`.
