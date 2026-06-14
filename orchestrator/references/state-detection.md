# State detection

Run signals in order; stop and use the first match. Explicit args (row 1) always win.

## Precedence table

| # | Signal | Detection | Resulting stage |
|---|---|---|---|
| 1 | **Explicit args** | Argument parse from SKILL.md Step 0 | Jump to the specified stage |
| 2 | **Open PR AND unresolved AI-bot threads** | See commands below | `pr-comments` |
| 3 | **Sidecar exists AND push has landed** | See commands below | `pr-finalize` |
| 4 | **Sidecar exists AND push has NOT landed** | Sidecar exists; HEAD not ahead of sidecar mtime | `executor --from-sidecar` |
| 5 | **`.review-passed` marker exists AND no open PR** | See commands below | `pr-creator` |
| 6 | **Matching plan exists AND working tree clean** | Plan-match algorithm + `git status` | `executor` |
| 7 | **Uncommitted changes AND no matching plan** | `git status --porcelain` non-empty; no plan match | `reviewer` (local mode); halt after |
| 8 | **Nothing matches** | — | **Halt**: "No state detected. Pass a task description or `--stage=<x>`." |

---

## Row 2 — Open PR + unresolved AI-bot threads

```bash
# Step 1: check for an open PR on the current branch
PR_INFO=$(gh pr view --json number,state,headRefName,isDraft 2>/dev/null)
PR_NUM=$(echo "$PR_INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['number'])" 2>/dev/null)

# Step 2: if PR exists and is open and not draft, check for unresolved bot comments
if [ -n "$PR_NUM" ]; then
  OWNER=$(gh repo view --json owner --jq .owner.login)
  REPO=$(gh repo view --json name --jq .name)
  UNRESOLVED=$(gh api graphql -f query='
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          reviewThreads(first: 100) {
            nodes {
              id isResolved
              comments(first: 1) {
                nodes { author { login } }
              }
            }
          }
        }
      }
    }' -F owner="$OWNER" -F name="$REPO" -F number="$PR_NUM" \
    --jq '[.data.repository.pullRequest.reviewThreads.nodes[]
          | select(.isResolved == false)
          | select(.comments.nodes[0].author.login | IN("Copilot","copilot-pull-request-reviewer","copilot-pull-request-reviewer[bot]","devin-ai-integration[bot]"))]
          | length' 2>/dev/null)
  # If UNRESOLVED > 0 → match row 2
fi
```

---

## Row 3 — Sidecar exists AND push landed

```bash
# Find most recent sidecar
SIDECAR=$(ls -t ~/.claude/plans/pr-*-bot-comments-*.actions.json 2>/dev/null | head -1)

if [ -n "$SIDECAR" ]; then
  # Extract branch from sidecar
  BRANCH=$(python3 -c "import sys,json; d=json.load(open('$SIDECAR')); print(d['branch'])")
  WORKTREE=$(python3 -c "import sys,json; d=json.load(open('$SIDECAR')); print(d.get('worktree', '.'))")

  LOCAL=$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null)
  UPSTREAM=$(git -C "$WORKTREE" rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null)
  REMOTE=$(git -C "$WORKTREE" rev-parse "${UPSTREAM}" 2>/dev/null)

  SIDECAR_MTIME=$(python3 -c "import os; print(int(os.path.getmtime('$SIDECAR')))")
  COMMIT_TIME=$(git -C "$WORKTREE" log -1 --format="%ct" 2>/dev/null)

  # Row 3: push landed AND latest commit is newer than sidecar
  if [ "$LOCAL" = "$REMOTE" ] && [ "$COMMIT_TIME" -gt "$SIDECAR_MTIME" ]; then
    : # match row 3 → pr-finalize
  # Row 4: sidecar exists but push hasn't happened or is ahead
  else
    : # match row 4 → executor --from-sidecar
  fi
fi
```

---

## Row 5 — `.review-passed` AND no open PR

```bash
MARKER=$(ls .claude/.review-passed 2>/dev/null)
PR_NUM=$(gh pr view --json number --jq .number 2>/dev/null)

# Row 5: marker exists and no open PR
if [ -n "$MARKER" ] && [ -z "$PR_NUM" ]; then
  : # match row 5 → pr-creator
fi
```

---

## Row 6 — Matching plan AND clean working tree

Check working tree:

```bash
DIRTY=$(git status --porcelain 2>/dev/null)
```

If `DIRTY` is empty, run the plan-match algorithm below.

---

## Plan-match algorithm

Used in row 6. Priority order — first match wins:

1. **Branch + mtime**: plan file mtime within 24h **AND** `## Context` section contains current branch name.
   ```bash
   BRANCH=$(git branch --show-current)
   CUTOFF=$(($(date +%s) - 86400))
   for f in ~/.claude/plans/*.md; do
     MTIME=$(python3 -c "import os; print(int(os.path.getmtime('$f')))")
     if [ "$MTIME" -gt "$CUTOFF" ]; then
       if grep -q "branch: $BRANCH\|Branch: $BRANCH\|/$BRANCH\|$BRANCH" "$f"; then
         PLAN="$f"
         break
       fi
     fi
   done
   ```

2. **Slug in commits**: plan slug appears in any non-merged commit subject on the current branch.
   ```bash
   COMMITS=$(git log origin/main..HEAD --format="%s" 2>/dev/null)
   for f in ~/.claude/plans/*.md; do
     SLUG=$(basename "$f" .md)
     if echo "$COMMITS" | grep -q "$SLUG"; then
       PLAN="$f"
       break
     fi
   done
   ```

3. **Most recent**: most-recently-modified plan file in `~/.claude/plans/`.
   ```bash
   PLAN=$(ls -t ~/.claude/plans/*.md 2>/dev/null | head -1)
   ```

**If multiple candidates tie at any tier**: halt and list them. Ask the user to pass `--plan <slug>` explicitly.

---

## Notes

- Rows 2–5 run detection shell commands; keep them in a read-only posture (no writes, no mutations).
- Row 2 requires `gh auth` and network; if `gh` is unavailable, skip to row 3.
- Row 7 (uncommitted changes, no plan): the orchestrator runs reviewer in local mode (informative) then halts. It does NOT try to reconstruct a plan for hand-written changes.
