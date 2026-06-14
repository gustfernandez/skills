# Argument grammar

## Invocation forms

```
/orchestrator                                    # autodetect stage from state
/orchestrator "<task description>"               # new task → PLAN stage
/orchestrator --task "<task description>"        # explicit form of above
/orchestrator --stage=plan|execute|review|pr|comments|finalize
/orchestrator --pr <N>                           # shorthand for --stage=comments --pr <N>
/orchestrator --plan <slug>                      # pin to ~/.claude/plans/<slug>.md
/orchestrator --resume                           # explicit "continue from autodetected stage"
/orchestrator --dry-run                          # print detected stage + would-be actions; take no action
/orchestrator --auto-merge                       # passed through to pr-creator stage (squash auto-merge)
/orchestrator --halt-on-should-fix               # treat reviewer Should-fix as halt (default: only Must-fix halts)
/orchestrator --skip-plan-review                 # bypass plan-reviewer subagents (logged loudly)
/orchestrator --plan-review-source <URL|path>    # enable Coverage agent in plan-review
```

## Precedence (highest wins)

1. `--stage=<x>` — explicit stage override
2. `--pr <N>` — implies `--stage=comments`
3. `--task "<desc>"` or positional task string — implies `--stage=plan`
4. Autodetect (see `state-detection.md`)

## Flag details

| Flag | Type | Description |
|---|---|---|
| `--stage=<x>` | string | Force entry at this stage. Valid values: `plan`, `execute`, `review`, `pr`, `comments`, `finalize`. |
| `--pr <N>` | int | PR number. Required when `--stage=comments` or `--stage=finalize` is used explicitly. Also accepted as positional second arg. |
| `--task "<desc>"` | string | Task description for the PLAN stage. Equivalent to a positional string argument. |
| `--plan <slug>` | string | Slug or absolute path to the plan file. Overrides the plan-match algorithm in EXECUTE stage. |
| `--resume` | flag | Explicit "continue from autodetected stage." Equivalent to bare invocation but reads more clearly in conversation. |
| `--dry-run` | flag | Print detected stage + would-be first action. No Bash side effects beyond detection commands. |
| `--auto-merge` | flag | Passed through to pr-creator. Enables squash auto-merge after PR creation. |
| `--halt-on-should-fix` | flag | Reviewer Should-fix findings block the chain (default: only Must-fix blocks). |
| `--skip-plan-review` | flag | Skip PLAN-REVIEW subagents. Always log: `⚠ --skip-plan-review: plan-reviewer bypassed.` |
| `--plan-review-source <x>` | string | URL or path to a spec/ticket. Enables the Coverage agent in PLAN-REVIEW. |

## Examples

```
/orchestrator "add an /api/apv/export-csv endpoint that streams a CSV of pending requests"
→ PLAN (with that task), then PLAN-REVIEW, EXECUTE, REVIEW, PR-CREATE

/orchestrator --stage=execute
→ EXECUTE with most-recent plan

/orchestrator --stage=execute --plan add-apv-export-csv
→ EXECUTE with ~/.claude/plans/add-apv-export-csv.md

/orchestrator --pr 123
→ PR-COMMENTS for PR #123

/orchestrator --stage=finalize --plan pr-123-bot-comments-2026-05-12
→ PR-FINALIZE reading that sidecar

/orchestrator --dry-run
→ Print detected stage and intended action only

/orchestrator --skip-plan-review "rename the `apv_type` field to `product_type` in the APV serializer"
→ PLAN (no plan-review gate), EXECUTE, REVIEW, PR-CREATE
```
