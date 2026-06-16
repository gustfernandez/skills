# Stage flow

## Autonomous chain (first pass)

```
/orchestrator (new task)
      │
      ▼
  ┌─────────────────────────────────────────────────────────┐
  │  PLAN  (inlined-planner.md)                            │
  │  in:  task description                                  │
  │  out: ~/.claude/plans/<slug>.md                         │
  │  halt: AskUserQuestion decision → surface + stop        │
  └─────────────────────────────────────────────────────────┘
      │
      ▼  (skip if --skip-plan-review)
  ┌─────────────────────────────────────────────────────────┐
  │  PLAN-REVIEW  (plan-review-agents.md)                  │
  │  2–3 parallel Opus subagents                            │
  │  APPROVED  → continue                                   │
  │  NEEDS_REVISION (1st) → revise plan + retry once        │
  │  NEEDS_REVISION (2nd) → HALT                            │
  └─────────────────────────────────────────────────────────┘
      │ APPROVED
      ▼
  ┌─────────────────────────────────────────────────────────┐
  │  EXECUTE  (inlined-executor.md)                        │
  │  walk Critical files table                              │
  │  run Verification block                                 │
  │  halt on any non-zero exit                              │
  └─────────────────────────────────────────────────────────┘
      │ verification clean
      ▼
  ┌─────────────────────────────────────────────────────────┐
  │  REVIEW  (inlined-reviewer.md, local mode)             │
  │  Must-fix > 0 → HALT (marker NOT touched)              │
  │  Must-fix == 0 → touch .review-passed                  │
  └─────────────────────────────────────────────────────────┘
      │ marker touched
      ▼
  ┌─────────────────────────────────────────────────────────┐
  │  PR-CREATE  (inlined-pr-creator.md)                    │
  │  stage Critical files → commit → push                   │
  │  gh pr create + @copilot  (no label)                    │
  │  [--auto-merge optional]                                │
  └─────────────────────────────────────────────────────────┘
      │
      ▼
  DONE (round 0)
  "Re-invoke /orchestrator when Copilot posts review comments."
```

---

## Re-entry path (Copilot has reviewed)

```
/orchestrator  (autodetect → state row 2 → pr-comments)
      │
      ▼
  ┌─────────────────────────────────────────────────────────┐
  │  PR-COMMENTS  (inlined-pr-comments.md)                 │
  │  classify Fix / Decline / Defer                         │
  │  declines: post + resolve inline (immediately)          │
  │  fixes: write plan + sidecar                            │
  └─────────────────────────────────────────────────────────┘
      │ fix_threads non-empty
      ▼
  EXECUTE (from-sidecar; skip PLAN-REVIEW)
      │
      ▼
  REVIEW (local)
      │
      ▼
  PR-CREATE (existing PR detected → push only, no new PR)
      │
      ▼
  DONE (re-entry)
  "Re-invoke /orchestrator after Copilot re-reviews to run pr-finalize."
```

---

## Finalize path (fix commits pushed)

```
/orchestrator  (autodetect → state row 3 → pr-finalize)
      │
      ▼
  ┌─────────────────────────────────────────────────────────┐
  │  PR-FINALIZE  (inlined-pr-finalize.md)                 │
  │  validate LOCAL == REMOTE HEAD                          │
  │  post "Fixed in <sha>" replies                          │
  │  resolve fix threads                                    │
  │  gated Copilot re-request (auto rounds 1–2; halt ≥3)   │
  └─────────────────────────────────────────────────────────┘
      │
      ▼
  DONE
```

---

## Transition guards

| Transition | Guard |
|---|---|
| PLAN → PLAN-REVIEW | Always. `--skip-plan-review` bypasses (with warning). |
| PLAN-REVIEW → EXECUTE | Only on APPROVED. NEEDS_REVISION loops back to PLAN once, then halts. |
| EXECUTE → REVIEW | Only if Verification block exits zero. Non-zero → halt. |
| REVIEW → PR-CREATE | Only if Must-fix == 0 (marker touched). `--halt-on-should-fix`: also require Should-fix == 0. |
| PR-CREATE → DONE | Always after PR is created or updated. Orchestrator does NOT poll for Copilot. |
| PR-COMMENTS → EXECUTE | Only if `fix_threads` non-empty. All declines/defers → DONE cleanly. |
| EXECUTE (re-entry) → REVIEW | Same as first-pass. |
| REVIEW (re-entry) → PR-CREATE | Same guard; existing PR detected in pr-creator Step 7 → push only. |
| PR-FINALIZE → DONE | After posting replies and resolving threads. |
| PR-FINALIZE → HALT | `round_number >= 2` → print command, do not run it. |

---

## Key behaviors

- **Sidecar-derived plans skip PLAN-REVIEW.** Plans written by pr-comments are machine-generated to a fixed shape; running the review subagents on them adds no signal.
- **PR-CREATE detects an existing PR (Step 7 in pr-creator).** When one is found, it pushes a follow-up commit on the same branch instead of creating a new PR. This is existing pr-creator behavior — the orchestrator inherits it verbatim.
- **The orchestrator ends at DONE on the first pass.** It does not poll for Copilot review results. Re-invocation is user-initiated.
- **Decline resolution is immediate (in PR-COMMENTS).** Declined comments are posted and threads resolved during analysis — no code change is needed, so there is no reason to wait until after executor.
