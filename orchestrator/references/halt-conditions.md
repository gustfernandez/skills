# Halt conditions

Full taxonomy. "Halt" means: surface the error clearly, stop the orchestrator, wait for user direction.

---

## Universal (check before any stage starts)

| Condition | Message |
|---|---|
| Not in a git repository | "Not in a git repository. cd to your project first." |
| `gh auth status` fails | "gh is not authenticated. Run `gh auth login` first." |
| `~/.claude/plans/` not writable | "Cannot write to ~/.claude/plans/. Check disk space and permissions." |
| cwd is the multiplica monorepo | "Use multiplica-* skills for this repo (multiplica-planner, multiplica-executor, etc.)." |

---

## PLAN stage

| Condition | Action |
|---|---|
| Task description is blank or too vague (e.g. "fix it" with no branch context) | Halt: "Task description is too vague. Try: /orchestrator \"<specific change description>\"" |
| Multiple plan files match cwd context and can't be disambiguated | Halt: list the candidates; "Use --plan <slug> to specify." |
| Inlined planner workflow hits `AskUserQuestion` for any decision | Halt: surface the question verbatim in plain text. Do NOT call `AskUserQuestion`. |

---

## PLAN-REVIEW stage

| Condition | Action |
|---|---|
| Second NEEDS_REVISION pass | Halt: print full Blocker list + diff between the two plan versions. |
| Agent times out or returns malformed output | Halt: print raw output. "Re-run /orchestrator or pass --skip-plan-review to bypass." |
| `Agent(opus)` not in settings.json allowlist AND `--skip-plan-review` not passed | Halt: "Add `\"Agent(opus)\"` to ~/.claude/settings.json permissions.allow, or pass --skip-plan-review." |

---

## EXECUTE stage

| Condition | Action |
|---|---|
| Plan file not found at resolved path | Halt: "Plan not found at <path>. Run /planner to create one, or pass --plan <slug>." |
| Plan missing one or more canonical sections | Halt: list missing sections. |
| Critical files table is empty | Halt: "Critical files table is empty. Nothing to execute." |
| File to be written/edited is listed under "Out of scope" | Halt: "Execution halted — <file> is listed under 'Out of scope'. Update the plan." |
| Actual change drifts materially from Changes section | Halt: "Plan says X but I'm about to write Y. Proceed?" Do not silently diverge. |
| Auto-generated migration appeared but wasn't in Critical files | Halt: surface the generated file; ask whether to include it in the plan. |
| Any Verification block exits non-zero (test, lint, type, migration check) | Halt: print full output verbatim. Mark task `pending`. |
| Verification step wall-clock > 10 min | Halt: "Verification timed out. Check the running container and retry." |

---

## REVIEW stage

| Condition | Action |
|---|---|
| Must-fix > 0 | Halt: print all Must-fix items. Marker NOT touched. PR-CREATE NOT invoked. |
| `--halt-on-should-fix` AND Should-fix > 0 | Halt: print all Should-fix items. |
| Not in a git repo or no diff to review (after a clean execute) | Halt: print diagnostics (git status, diff output). |

---

## PR-CREATE stage

| Condition | Action |
|---|---|
| `.review-passed` marker missing (plan-mode, no `--manual`) | Halt: "Run /reviewer first. The commit gate requires a clean reviewer pass." |
| Current branch is `main` or `master` | Halt: "Cannot create a PR from the default branch. Check out a feature branch first." |
| `gh pr create` or `git push` fails with network/auth error | Halt: print the raw error. |
| Push targets a denied refspec (`main`, `master`, `--force`, `-f`) | Halt: "Push blocked by settings.json deny list." |

---

## PR-COMMENTS stage

| Condition | Action |
|---|---|
| Thread cannot be classified Fix/Decline/Defer with confidence | Halt: surface the comment body verbatim and ask. |
| Sidecar branch ≠ current branch (worktree mismatch) | Halt: "Sidecar branch <A> doesn't match current branch <B>. Check out the right branch." |

---

## PR-FINALIZE stage

| Condition | Action |
|---|---|
| Sidecar file missing or invalid JSON | Halt: "~/.claude/plans/<slug>.actions.json not found or invalid." |
| LOCAL HEAD ≠ REMOTE HEAD | Halt: "Branch not pushed yet. Push first, then re-run /orchestrator." |
| `round_number >= 2` | Print the suggested `gh pr edit` command; do NOT run it. This is a soft halt — the chain ends here. |

---

## Never do (universal)

- Never auto-commit after a clean reviewer pass. Explicit user approval required.
- Never push with `--force` or `--no-verify`.
- Never retry a failing verification step in a loop. Surface and stop.
- Never mark a task `completed` if its verification failed. Use `pending`.
- Never write to `.claude/.review-passed` directly — only the reviewer skill does that.
- Never touch human reviewer threads. Only bot threads (Copilot, Devin) are in scope.
