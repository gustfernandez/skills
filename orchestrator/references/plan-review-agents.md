# Plan-review agents

The automatic plan-approval gate. Runs between PLAN and EXECUTE. Dispatch all agents in a single `Agent` tool call message (parallel execution).

---

## When to run

- Always after PLAN produces a plan file.
- Skip if `--skip-plan-review` was passed (log the bypass loudly: `⚠ --skip-plan-review: plan-reviewer bypassed.`).
- Skip for sidecar-derived re-entry plans (machine-generated from bot instructions; no signal gained from reviewing them).

---

## Agents

Dispatch in one parallel message. Each agent reads the plan file independently and returns a structured findings report.

### Agent 1: Feasibility

**Model**: opus  
**Prompt**:

> You are reviewing an implementation plan for a Django/Python codebase. Your job is to check whether the plan is **feasible and internally consistent** — not to review code quality.
>
> Plan file: `<absolute path to ~/.claude/plans/<slug>.md>`
>
> Checks to perform:
> 1. Do the files in the Critical files table actually exist in the repo (for MODIFIED rows)?
>    - Grep for each file path. Flag any MODIFIED file that cannot be found.
> 2. Does the Verification block use `docker compose -f <compose-file> exec django ...` for any `python`, `pytest`, `mypy`, `manage.py`, or `celery` commands?
>    - Flag any bare host-level invocations.
> 3. Are all canonical sections present? (Context, Changes, Tests, Critical files, Out of scope, Verification)
>    - Flag any missing section.
> 4. Does the Changes section reference files that are NOT in the Critical files table?
>    - Flag any ghost files.
> 5. Is the Verification block non-empty and runnable (has at least one shell command)?
>
> Output format (use EXACTLY this structure):
>
> ```
> [Blocker] <description with file:line if applicable>
> [Important] <description>
> [Nit] <description>
> ```
>
> Return only your findings. Zero findings is a valid result — just write "No findings."

---

### Agent 2: Risk

**Model**: opus  
**Prompt**:

> You are reviewing an implementation plan for a Django/Python codebase. Your job is to check for **semantic and architectural risks** — things that would cause the code change to violate the project's layering rules or introduce real bugs.
>
> Plan file: `<absolute path to ~/.claude/plans/<slug>.md>`
> Standards reference: `~/.claude/skills/planner/references/standards.md`
>
> Checks to perform (read the plan's Changes section carefully):
> 1. **Layering**: does any import in the proposed Changes move from a parent module into a child package? (e.g. `from app.sub.constants import X` inside `app/module.py`). Flag as Blocker.
> 2. **Business logic in views**: does any proposed view method (`post`, `get`, `patch`, `delete`) contain ORM queries, `json.loads`, file orchestration, or bytes extraction? Flag as Blocker.
> 3. **Business logic in serializers**: does any proposed serializer contain ORM queries or multi-step business logic? Flag as Blocker.
> 4. **Sibling drift**: if the plan adds a new service function, does its signature match existing siblings in the same app? (e.g. all siblings pass `user:` as required; new one uses `user=None`). Flag as Important.
> 5. **Missing select_related/prefetch_related**: if the plan adds a selector that does ORM queries with related objects, does it include `select_related`/`prefetch_related`? Flag as Should-fix (map to Important).
> 6. **Migration risk**: if the plan adds a NOT NULL column without a default, flag as Blocker (unsafe on live data).
> 7. **Literal repetition**: if the same domain value string appears 3+ times in the proposed Changes, flag as Important.
>
> Output format (use EXACTLY this structure):
>
> ```
> [Blocker] <description with file:line if applicable>
> [Important] <description>
> [Nit] <description>
> ```
>
> Return only your findings. Zero findings is a valid result — just write "No findings."

---

### Agent 3: Coverage (conditional)

Only dispatch this agent if `--plan-review-source <URL|path>` was passed.

**Model**: opus  
**Prompt**:

> You are reviewing an implementation plan against a source specification to check **coverage** — whether the plan addresses all the requirements in the spec.
>
> Plan file: `<absolute path to ~/.claude/plans/<slug>.md>`
> Source spec: `<URL or path from --plan-review-source>`
>
> Checks to perform:
> 1. Read the source spec. List every distinct requirement or acceptance criterion.
> 2. For each requirement, check whether the plan's Changes section addresses it.
> 3. Flag any requirement that is not addressed.
> 4. Flag any significant feature in the plan that is NOT in the spec (possible scope creep).
>
> Output format (use EXACTLY this structure):
>
> ```
> [Blocker] <description — requirement not addressed>
> [Important] <description>
> [Nit] <description>
> ```
>
> Return only your findings. Zero findings is a valid result — just write "No findings."

---

## Aggregation rules

After all agents return:

| Result | Condition |
|---|---|
| **APPROVED** | Zero `[Blocker]` findings across ALL agents. |
| **NEEDS_REVISION** | Any `[Blocker]` from any agent. |

`[Important]` and `[Nit]` findings are logged in the chain output but do NOT block approval. The main orchestrator session can choose to apply them or document why they were ignored.

---

## On NEEDS_REVISION

**First time:**

1. Collect all `[Blocker]` findings from all agents.
2. Append them to the plan's `## Context` section under a heading:
   ```
   ### Plan-review blockers (round 1)
   - <blocker 1>
   - <blocker 2>
   ```
3. Return to PLAN stage with the instruction: "Revise the plan to address the above blockers. The plan file has been updated with the blockers in the Context section."
4. After PLAN rewrites the file, dispatch the agents again.

**Second time (NEEDS_REVISION again):**

Halt. Print:
- All remaining `[Blocker]` findings.
- The diff between the original plan and the revised plan (to show what changed between the two rounds).
- "The plan-reviewer found blockers in both rounds. Review the plan manually and re-invoke with `--skip-plan-review` if you want to proceed despite the findings, or fix the underlying design issue and re-invoke normally."

---

## Requirements for `Agent(opus)`

These agents require `Agent(opus)` to be in `~/.claude/settings.json` `permissions.allow`. If it is not present and `--skip-plan-review` was not passed, halt:

```
Agent(opus) is not allowed in settings.json.
To fix: add "Agent(opus)" to permissions.allow in ~/.claude/settings.json.
Or pass --skip-plan-review to bypass the plan-reviewer entirely.
```
