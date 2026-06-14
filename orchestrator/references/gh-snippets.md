# `gh` CLI / GraphQL snippets

> **Source**: copy of `~/.claude/skills/pr-comments/references/gh-snippets.md`.
> Commands used by the pr-comments and pr-finalize stages. Copy verbatim — argument shapes are tested.

---

## AI reviewer logins

| Reviewer | Login(s) to match | How to trigger |
|---|---|---|
| GitHub Copilot | `Copilot`, `copilot-pull-request-reviewer`, `copilot-pull-request-reviewer[bot]` | `gh pr edit N -R <owner>/<repo> --add-reviewer "@copilot"` |
| Devin (Cognition) | `devin-ai-integration[bot]` | Post PR comment: `@devin-ai-integration please review this PR` |

---

## Fetch PR head branch (Phase 0)

```bash
gh pr view <N> -R <owner>/<repo> --json headRefName --jq .headRefName
```

---

## Fetch unresolved AI-bot comments (Phase 0)

Returns REST comment objects (id, path, line, body) for unresolved AI-bot comments. Note: REST comments don't expose thread resolution state — use the GraphQL query below to get that.

```bash
gh api repos/<owner>/<repo>/pulls/<N>/comments \
  --jq '.[] | select(.user.login | IN("Copilot","copilot-pull-request-reviewer","copilot-pull-request-reviewer[bot]","devin-ai-integration[bot]")) | {id, path, line, body, pull_request_review_id}'
```

---

## Fetch unresolved thread IDs (Phase 0)

GraphQL — REST doesn't expose thread state or node IDs. Returns `thread_id` (the `PRRT_...` node ID used for `resolveReviewThread`) and the first comment's `databaseId` (used for `/replies`).

```bash
gh api graphql -f query='
  query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) {
      pullRequest(number: $number) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            isOutdated
            comments(first: 1) {
              nodes { databaseId author { login } body }
            }
          }
        }
      }
    }
  }' -F owner=<owner> -F name=<repo> -F number=<N> \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false)
        | select(.comments.nodes[0].author.login | IN("Copilot","copilot-pull-request-reviewer","copilot-pull-request-reviewer[bot]","devin-ai-integration[bot]"))
        | {thread_id: .id, comment_id: .comments.nodes[0].databaseId, preview: .comments.nodes[0].body[:80]}'
```

**Important**: `.id` is the GraphQL node ID (`PRRT_...`) — use this for `resolveReviewThread`. `.comments.nodes[0].databaseId` is the REST integer ID — use this for `/replies`.

---

## Count Copilot review rounds (Phase 0)

```bash
gh api repos/<owner>/<repo>/pulls/<N>/reviews \
  --jq '[.[] | select(.user.login | IN("Copilot","copilot-pull-request-reviewer","copilot-pull-request-reviewer[bot]","devin-ai-integration[bot]"))] | length'
```

Save as `round_number`. If the result is 0, this is round 1 (the bot just reviewed for the first time).

---

## Check for prior decline on same file:line (Phase 0 — re-surfaced decline filter)

```bash
gh api graphql -f query='
  query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) {
      pullRequest(number: $number) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            path
            line
            comments(first: 5) {
              nodes { databaseId author { login } body }
            }
          }
        }
      }
    }
  }' -F owner=<owner> -F name=<repo> -F number=<N> \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == true)
        | select(.path == "<path>" and .line == <line>)
        | .comments.nodes[] | select(.body | startswith("Declined:"))'
```

---

## Post an inline reply to a comment (Phase 1 — declines; Phase 3 — fix replies)

```bash
gh api repos/<owner>/<repo>/pulls/<N>/comments/<comment_id>/replies \
  -X POST -f body='<Reply body. Use single quotes to prevent shell expansion.>'
```

**Single-quote rule**: always wrap the `body` value in single quotes. If the reply body contains a single quote (apostrophe), escape it with `'"'"'`.

**Gotcha**: the path must include `/pulls/<N>/` — omitting the PR number causes 404.

---

## Resolve a review thread (Phase 1 + Phase 3)

```bash
gh api graphql -f query='
  mutation($tid: ID!) {
    resolveReviewThread(input: {threadId: $tid}) {
      thread { id isResolved }
    }
  }' -F tid=<PRRT_thread_node_id>
```

`tid` must be the GraphQL node ID (`PRRT_...`), not the REST databaseId integer.

---

## Post "Fixed in `<sha>`" reply + resolve fix thread (Phase 3 — pr-finalize)

```bash
SHORT_SHA=$(git -C <worktree> rev-parse --short HEAD)

gh api repos/<owner>/<repo>/pulls/<N>/comments/<comment_id>/replies \
  -X POST -f body="Fixed in ${SHORT_SHA}: <one-line fix summary>"

gh api graphql -f query='
  mutation($tid: ID!) {
    resolveReviewThread(input: {threadId: $tid}) {
      thread { id isResolved }
    }
  }' -F tid=<PRRT_thread_node_id>
```

---

## Re-request Copilot review (Phase 3 — pr-finalize, rounds 1–2 only)

```bash
gh pr edit <N> -R <owner>/<repo> --add-reviewer "@copilot"
```

Do NOT run this for `round_number >= 2`. Print the command for the user and let them decide.

---

## Verify branch is pushed (Phase 3 — pr-finalize)

```bash
UPSTREAM=$(git -C <worktree> rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null)
LOCAL=$(git -C <worktree> rev-parse HEAD)
REMOTE=$(git -C <worktree> rev-parse "${UPSTREAM}" 2>/dev/null)

if [ "$LOCAL" != "$REMOTE" ]; then
  echo "Branch not pushed — push first, then re-run /orchestrator"
  exit 1
fi
```
