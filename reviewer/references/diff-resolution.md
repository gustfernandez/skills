# Diff Resolution

Per-mode commands for obtaining the diff to review.

## local (default)

```bash
# Staged + unstaged changes relative to HEAD
git diff HEAD
# Also capture staged-only (shown separately if HEAD is empty)
git diff --cached
# List of changed files
git diff --name-only HEAD
```

Run from the cwd's git repo root (resolved via `git rev-parse --show-toplevel`).

## branch

```bash
# Detect the default branch
DEFAULT=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')
DEFAULT=${DEFAULT:-main}

# Full diff from where the branch diverged
git diff origin/${DEFAULT}...HEAD

# List of changed files
git diff --name-only origin/${DEFAULT}...HEAD
```

Run from the cwd's git repo root.

## file

```bash
# Read the file directly — no diff needed
# Pass the absolute path to the Read tool
```

For a single-file review, read the full file and apply only the checklist rules relevant to that file type (see `checklist-by-file-type.md`). Do not restrict review to a diff — the entire file is in scope.

## pr

```bash
# Fetch the PR diff
gh pr diff <N>

# List changed files with their status
gh pr view <N> --json files --jq '.files[] | "\(.status) \(.filename)"'

# PR metadata (title, body, base branch, reviewers)
gh pr view <N> --json title,body,baseRefName,reviewRequests,author
```

For PRs in a different repo than the cwd, prefix with `-R <owner>/<repo>`:
```bash
gh pr diff <N> -R <owner>/<repo>
gh pr view <N> -R <owner>/<repo> --json files --jq '.files[].filename'
```

Accepted input forms for `pr` mode:
- `/reviewer pr 42` — PR #42 in the current repo.
- `/reviewer pr myorg/myrepo#42` — explicit repo.
- `/reviewer pr https://github.com/myorg/myrepo/pull/42` — full URL.

## Worktree note

When running inside a git worktree (e.g. `~/.config/superpowers/worktrees/<repo>/<branch>/`), the repo root is still resolved via `git rev-parse --show-toplevel`. The worktree shares the `.git` dir with the main clone, so all git commands work normally.
