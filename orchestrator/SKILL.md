---
name: orchestrator
description: Autonomously chains the dev workflow (plan → review-plan → execute → review → PR → comments → finalize). Use when continuing existing work, shipping a feature, addressing bot review comments, or whenever the user says "continue", "keep going", "ship it", "finish this", "open the PR", or "address the bot". Also triggers on bare /orchestrator with no arguments.
---

# orchestrator

## Overview

A single skill that drives the full dev-workflow loop autonomously. It detects which stage to enter from the filesystem and git state, or accepts explicit overrides, then chains through all stages until the PR is open (or PR comments are resolved) — pausing only on errors or genuine ambiguity.

**Pause conditions**: errors, verification failures, ambiguous decisions that require human judgment. Everything else proceeds without prompting.

**Existing skills** (`/planner`, `/executor`, `/reviewer`, `/pr-creator`, `/pr-comments`, `/pr-finalize`) remain unchanged and fully usable on their own.

**Out of scope**: the multiplica monorepo (use `multiplica-*` skills there). If cwd is the multiplica repo, halt with a clear message.

---

## Step 0 — Parse arguments

Read `references/argument-grammar.md` now. Parse the invocation to determine:

1. Any explicit `--stage`, `--pr`, `--task`, `--plan`, `--resume`, `--dry-run`, `--auto-merge`, `--halt-on-should-fix`, `--skip-plan-review`, `--plan-review-source` flags.
2. Any positional task string (implies `--stage=plan` with that task description).

Store parsed flags for use throughout this session.

---

## Step 1 — Detect stage

Read `references/state-detection.md` now. Follow the 8-row precedence table to determine the entry stage. Run detection signals in order; stop at the first match.

If `--dry-run` was passed: after detection, print the detected stage and the would-be first action, then stop. No reads, no writes, no Bash side effects beyond the detection commands.

---

## Step 2 — Dispatch to entry stage

Based on the detected (or explicit) stage, jump to the appropriate section below. Work through the stage, then follow the **→ next** pointer at the end of each section.

---

## PLAN stage

Read `references/inlined-planner.md` now. Follow that workflow exactly to write a 6-section canonical plan to `~/.claude/plans/<slug>.md`.

**Orchestrator-specific override**: if the inlined planner workflow would call `AskUserQuestion` for a layering, sibling-pattern, or scope decision — **halt instead**. Surface the question in plain text and stop. The user clarifies and re-invokes with `--task`.

After writing the plan: → **PLAN-REVIEW stage** (unless `--skip-plan-review` was passed, in which case → **EXECUTE stage** with a loud warning logged).

---

## PLAN-REVIEW stage

Read `references/plan-review-agents.md` now. Dispatch the plan-reviewer subagents as specified there.

**On APPROVED** (zero `[Blocker]` findings): → **EXECUTE stage**.

**On NEEDS_REVISION** (first time): inject the Blocker findings as additional context into the plan and loop back to PLAN stage once. The plan file is rewritten in place.

**On NEEDS_REVISION** (second time): halt. Print the full Blocker list and the diff between the two plan versions. Do not proceed to EXECUTE.

---

## EXECUTE stage

Read `references/inlined-executor.md` now. Follow that workflow exactly.

**From-sidecar mode** (when entering from PR-COMMENTS stage): the plan file is the `pr-<N>-bot-comments-<YYYY-MM-DD>.md` file written by PR-COMMENTS. Skip PLAN-REVIEW for this plan (it is machine-generated from bot instructions).

On verification failure: **halt**. Print failing block output verbatim. Do not proceed.

On verification success: → **REVIEW stage**.

---

## REVIEW stage

Read `references/inlined-reviewer.md` now. Run in **local mode** (default). This reviews staged and unstaged changes in the cwd repo.

On Must-fix == 0: the marker is touched; → **PR-CREATE stage**.

On Must-fix > 0: **halt**. Print all Must-fix items. Do NOT touch the marker. Do NOT proceed to PR-CREATE.

If `--halt-on-should-fix` was passed AND Should-fix > 0: **halt** even if Must-fix == 0.

---

## PR-CREATE stage

Read `references/inlined-pr-creator.md` now. Follow that workflow exactly. Pass `--auto-merge` through if the flag was set.

On first pass (no existing PR): create the PR, apply the label, request `@copilot`. Print the PR URL, label, and "Done — re-invoke /orchestrator when Copilot posts review comments." **DONE (round 0).**

On re-entry pass (existing PR detected in Step 7 of pr-creator): push the follow-up commit to the existing branch/PR instead of opening a new one. Print the commit SHA and "Push complete — re-invoke /orchestrator to run pr-finalize after Copilot re-reviews." **DONE (re-entry).**

---

## PR-COMMENTS stage

Read `references/inlined-pr-comments.md` now. Follow that workflow exactly.

If `fix_threads` is empty after analysis: print summary (k declined, p deferred, 0 fixes). **DONE — nothing to execute.**

If `fix_threads` is non-empty: write the plan file and sidecar, then → **EXECUTE stage (from-sidecar mode)**.

---

## PR-FINALIZE stage

Read `references/inlined-pr-finalize.md` now. Follow that workflow exactly.

After posting "Fixed in <sha>" replies and resolving threads: **DONE**.

If `round_number >= 2`: halt as specified in the pr-finalize workflow (print suggested command, do not run it).

---

## Universal halt conditions

Before starting any stage, check:
- Not in a git repository → halt.
- `gh` not authenticated (`gh auth status` fails) → halt with "Run `gh auth login` first."
- `~/.claude/plans/` not writable → halt.
- cwd is the multiplica monorepo → halt with "Use multiplica-* skills for this repo."

See `references/halt-conditions.md` for the full taxonomy.

---

## Read-at-runtime pointers

The following files are NOT duplicated in this skill — read them at the point in the workflow that needs them:

- **HackSoft standards**: `~/.claude/skills/planner/references/standards.md`
- **Reviewer checklist**: `~/.claude/skills/reviewer/references/checklist.md`
- **Reviewer checklist by file type**: `~/.claude/skills/reviewer/references/checklist-by-file-type.md`
- **Reviewer diff resolution**: `~/.claude/skills/reviewer/references/diff-resolution.md`
- **Canonical plan format** (for executor parsing): `~/.claude/skills/planner/references/canonical-plan-format.md`
- **PR conventions**: `~/.claude/skills/conventions/pr.md`
- **Marker script**: `~/.claude/skills/reviewer/scripts/touch-review-marker.sh`

---

## References (local)

- `references/argument-grammar.md` — full flag spec + precedence.
- `references/state-detection.md` — 8-row state precedence table + plan-match algorithm.
- `references/stage-flow.md` — transition diagram + per-transition guards.
- `references/halt-conditions.md` — full halt taxonomy per stage.
- `references/plan-review-agents.md` — plan-reviewer subagent prompts + aggregation.
- `references/inlined-planner.md` — planner workflow (verbatim).
- `references/inlined-executor.md` — executor workflow (verbatim).
- `references/inlined-reviewer.md` — reviewer workflow (verbatim).
- `references/inlined-pr-creator.md` — pr-creator workflow (verbatim).
- `references/inlined-pr-comments.md` — pr-comments workflow (verbatim).
- `references/inlined-pr-finalize.md` — pr-finalize workflow (verbatim).
- `references/gh-snippets.md` — all gh API / GraphQL commands.
