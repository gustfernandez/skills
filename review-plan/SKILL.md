---
name: review-plan
description: Use when an implementation plan has been drafted and needs independent validation before execution — dispatches parallel subagents to review it from orthogonal angles (coverage vs source card, feasibility vs codebase, adversarial risk). Drops to 2 agents when no source card/spec is supplied.
---

# Review Plan

## Overview

Dispatches 2 or 3 parallel subagents to review a plan file from distinct angles, then synthesizes their reports. Each agent examines different inputs so their findings are orthogonal rather than overlapping.

**Core principle:** three inputs, three agents. Card coverage reads the card. Feasibility reads the code. Risk reads the plan adversarially. Removing any one loses a whole category of finding; adding a fourth mostly duplicates existing coverage.

## When to Use

- A plan file has been drafted (typically in `~/.claude/plans/`) and you want an independent check before execution
- You're about to call `ExitPlanMode` and want a last-pass review
- The user asks for a "second opinion" or "review" on a plan

**Don't use when:**
- The plan is trivial (one-line change, rename, typo fix)
- The plan hasn't been written yet — write it first
- You're debugging an execution, not validating a plan

## Inputs

- **plan_path** (required): absolute path to the plan markdown file
- **source** (optional): URL or local path of a Notion card / Linear ticket / spec doc the plan is derived from. When present, enables the Coverage agent.

## Workflow

1. **Pick the agent count.** Source present → 3 agents. Source absent → 2 agents (skip Coverage).
2. **Read the plan yourself first** (one pass, no notes). You need enough context to write self-contained agent prompts and to synthesize at the end. If the plan file is huge, skim structure only.
3. **Dispatch in parallel.** Single message, multiple Agent tool calls. Each prompt is self-contained — agents have no shared memory. Set `model` per agent (see Agent Roles table for defaults).
4. **Synthesize** the reports into a deduplicated list of findings grouped by severity: `[Blocker]`, `[Important]`, `[Nit]`.
5. **Surface findings** to the user before modifying the plan. Don't silently edit.

## Agent Roles

| Agent | Inputs | Default model | Focus |
|---|---|---|---|
| **Coverage** (only with source) | plan + source | `sonnet` | Does every acceptance criterion, DoD item, and explicit requirement in the source appear in the plan? Anything in the plan not backed by the source (scope creep)? Any open questions in the source the plan fails to address or defer explicitly? |
| **Feasibility** | plan + codebase | `sonnet` | Do the file paths, function names, APIs, migration numbers, dependencies, and patterns referenced in the plan actually exist in the current tree and behave as assumed? Are "existing patterns to reuse" cited correctly? |
| **Risk** | plan only | `opus` | What could go wrong? Hidden assumptions, failure modes, race conditions, rollout/migration risks, missing observability, unstated invariants, what breaks if a dependency is down. |

### Why these models

- **Coverage → sonnet.** Diff-style text comparison. Needs careful reading and cross-referencing but moderate reasoning. Haiku misses nuance on multi-part requirements; Opus is wasteful.
- **Feasibility → sonnet.** Tool-heavy (Read/Grep/Glob) lookup work. Sonnet is the sweet spot — Haiku can miss subtle pattern mismatches, Opus burns tokens for what's mostly verification.
- **Risk → opus.** Adversarial reasoning, hypothetical failure modes, and cross-cutting system thinking. This is where depth matters most — in practice, Risk surfaces the plurality of blockers, and that's not an accident. Sonnet works for small plans but misses subtler race conditions and contract-semantic ambiguities.

### When to override

- **Small plan (<500 words) or tight budget:** all three on `sonnet`.
- **Large or infrastructure-heavy plan with rollout/migration complexity:** promote Feasibility to `opus` too.
- **Card-only pass (you already trust the codebase):** Coverage on `opus` for stricter requirement diffing.

Pass `model` on each `Agent` tool call to override the default.

## Agent Prompt Template

Every agent prompt must include:

- **The angle** — which of the three roles this agent plays
- **Absolute paths** — to the plan file and (if applicable) the source
- **Output contract** — structured report, under 800 words, findings grouped as `[Blocker]` / `[Important]` / `[Nit]` with file:line citations or verbatim quotes
- **Explicit constraint** — identify gaps, don't propose rewrites. The main thread decides what to apply.

**Feasibility example:**
> You are reviewing an implementation plan at `<plan_path>` for technical feasibility against the current codebase. For every file path, function name, class, migration number, external API, or "existing pattern to reuse" the plan cites, verify it exists in the current tree and behaves as the plan assumes. Also check that new code fits the conventions visible in neighboring files. Return findings grouped as `[Blocker] / [Important] / [Nit]` with file:line citations. Do not propose rewrites — only identify mismatches. Under 800 words.

**Coverage example:**
> You are reviewing an implementation plan at `<plan_path>` against its source at `<source>`. Read both. Diff them: (a) every acceptance criterion, DoD item, error code, endpoint, and explicit requirement in the source that does NOT appear in the plan; (b) anything in the plan that has no basis in the source (scope creep or invention); (c) open questions in the source that the plan neither addresses nor explicitly defers. Return findings grouped as `[Blocker] / [Important] / [Nit]` with quoted snippets. Do not propose rewrites. Under 800 words.

**Risk example:**
> You are reviewing an implementation plan at `<plan_path>` adversarially. The plan will be executed by a human. Play it forward in your head: what fails? Focus on hidden assumptions, rollout/migration order, concurrency, error paths not discussed, dependencies outside the plan's control, observability gaps, data migrations that can't be rolled back, security implications, and anything the plan says "just do X" for that hides complexity. Return findings grouped as `[Blocker] / [Important] / [Nit]` with plan-section citations. Do not propose rewrites. Under 800 words.

## Synthesis

After the agents return:

1. **Deduplicate** overlapping findings. Same issue surfaced by two angles = one finding, note both angles.
2. **Group by severity.** `[Blocker]` first, then `[Important]`, then `[Nit]`.
3. **Surface top findings prominently** — the user cares about 3–5 blockers, not 40 nits.
4. **Offer** to update the plan file. Don't edit silently.

## Quick Reference

| Situation | Agents |
|---|---|
| Plan + Notion card / Linear ticket / spec doc | Coverage + Feasibility + Risk |
| Plan only (no source) | Feasibility + Risk |
| Plan is trivial | Skip — just execute |
| Multiple sources | Single Coverage agent reads them all |
| Plan was just produced by another agent (e.g. Ultraplan) | Use this skill — independent reviewers catch things the author missed |

## Common Mistakes

- **Sequential dispatch.** Agents must run in parallel — one message with multiple `Agent` tool calls. Sequential is 3× slower for no gain.
- **Overlapping prompts.** If two agents cover the same angle, reports duplicate. Keep roles orthogonal.
- **Silent edits post-review.** Show findings first. Let the user (or main-thread Claude with user consent) decide what to apply.
- **Running Coverage with no source.** Degenerates into generic "does the plan make sense" review — that's Feasibility + Risk's job. Skip Coverage when there's no source to diff against.
- **Letting agents propose rewrites.** Their job is to find gaps. Rewrites are the main thread's responsibility. Cap each agent at findings-only.
- **Skipping the main-thread read.** You need your own mental model of the plan to synthesize 3 reports into a coherent summary. Don't delegate the whole loop.
