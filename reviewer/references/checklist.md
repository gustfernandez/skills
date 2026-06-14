# Review Checklist

Each rule: `severity | category | rule | how to detect`.

Severity: **must** (blocks commit), **should** (high review-round risk), **nit** (style preference), **rec** (process/hygiene reminder — non-blocking, never affects the marker).

---

## Layering

| Sev | Rule | How to detect |
|-----|------|---------------|
| must | Parent module does not import from a child package | In the diff, look for `from .<child_pkg>` imports inside a file that lives at a *higher* level than the imported module. e.g. `models.py` importing `from .apv.constants import`. |
| must | Business logic is not in views / apis | Inspect `post()`/`get()` bodies for: `json.loads`, file orchestration, `MultiValueDict` iteration, DB queries, external HTTP calls outside the primary service call. |
| must | Business logic is not in serializers | Inspect `validate_*` and `to_representation` for: DB queries, external HTTP calls, side effects. |
| must | Business logic is not in models (save/delete/signals) | Grep for `def save(`, `def delete(`, `post_save`, `pre_save` signal receivers with non-trivial logic. |
| should | Selectors use select_related / prefetch_related | If a selector returns a queryset with related objects accessed later, check for `.select_related()` / `.prefetch_related()`. |

---

## Serializers

| Sev | Rule | How to detect |
|-----|------|---------------|
| must | `ChoiceField` uses a named constant, not inline list | `ChoiceField(choices=[...])` with raw tuples. Should be `ChoiceField(choices=NAMED_CHOICES)`. |
| must | `default=<value>` field does not also have `required=False` | Grep for `default=` + `required=False` on the same field. |
| should | `validate_<field>` used for field-level parsing (e.g. JSON string) | Inline `json.loads` inside a view instead of a serializer `validate_payload` method. |
| must | `serializer.is_valid(raise_exception=True)` used — no manual guard | Grep for `if not serializer.is_valid():` in views/apis. |

---

## Constants

| Sev | Rule | How to detect |
|-----|------|---------------|
| should | Domain value literals are not repeated | Grep diff for repeated string literals across serializer + mapper + test. Each should appear only in the constant definition. |
| must | Constants use plain-class style, not enum or dict | `class ProductType: CCV = "CCV"` is correct. `Enum` subclasses are non-standard for this pattern. |
| must | Constant defined at the right package level | If a parent module uses a constant, it must be defined at or above that level, not in a child package. |

---

## Views / APIs

| Sev | Rule | How to detect |
|-----|------|---------------|
| must | View shape: serialize → service → response | Count lines in `post()`/`get()`. If > ~10, read carefully for business logic. |
| nit | No trailing slash on URL patterns | Grep `urlpatterns` for `path(".../"`. Remove trailing slash. |
| nit | URL is kebab-case | Grep `urlpatterns` for underscores in path segments. Should be kebab-case. |

---

## Services & Integrations

| Sev | Rule | How to detect |
|-----|------|---------------|
| must | Integration client parameters are required (no `None` default) if siblings are required | Compare new service/client signature vs sibling services in the same app. |
| must | `_handle_response` not copy-pasted across client methods | If two or more methods in the same client file have identical HTTP-error-check + upstream-propagation blocks, extract to `_handle_response`. |
| should | Integration client validates response with Pydantic | After `response.json()`, look for a `SomeSchema(**data)` or `SomeSchema.model_validate(data)` call. Raw dict access without Pydantic is risky. |

---

## Models

| Sev | Rule | How to detect |
|-----|------|---------------|
| should | `default=` uses a constant, not a bare string | `default="A"` where a named constant exists. |
| should | `choices=` uses constants, not inline tuples | Inline `choices=[("P", "Payroll")]` where a named constant exists. |

---

## Testing

| Sev | Rule | How to detect |
|-----|------|---------------|
| must | All external HTTP calls are mocked | Grep test file for any `httpx`, `requests`, or integration client instantiation without a `mocker.patch`. |
| must | Mock path matches the module that *imports* the function | After a refactor, check that `mocker.patch("module_a.fn")` still points to where `fn` is imported, not where it's defined. |
| should | `APIClient` + `status.HTTP_*` used (not raw integers) | Grep for integer status codes (e.g. `== 200`, `== 400`) in test assertions. |
| nit | Test file mirrors source structure | `{app}/tests/services/test_{service}.py` for service tests; `{app}/tests/test_{api}.py` for API tests. |

---

## Commit / PR

Read `~/.claude/skills/conventions/pr.md` and enforce every rule it defines. Severity mapping for detection:

| Sev | What to check | How |
|-----|--------------|-----|
| must | Conventional Commits format | `git log -1` — matches `<type>(<scope>): <description>`? |
| rec† | Screenshot present on frontend PRs | PR body has `## Screenshots` section or explicit `No visual change`. Applies when diff touches `.tsx`, `.jsx`, `.vue`, `.html`, `.css`, `.scss`. |
| should | Ticket / Notion ID not in commit subject | Grep `git log -1` for `MLTPB-\d+` or `notion.so`; verify it's in PR body instead. |
| should | PR not fullstack (split front/back when possible) | Diff touches both `.py`/`.sql` and `.tsx`/`.ts`/`.vue`/`.css`? |
| rec† | Front/back label set | `gh pr view --json labels` shows `frontend`, `backend`, or `fullstack`. |
| nit | Commit type matches the change | `feat` = new functionality, `fix` = bug, `refactor` = restructuring. |

> **† Author-scoped — see `conventions/pr.md`.** The screenshot and front/back label rules apply **only when reviewing your own PR**. When the PR is authored by someone else (especially in a routine), do **not** raise a missing screenshot or missing label at any severity. Check authorship: `gh pr view "$PR_NUM" --json author --jq .author.login` vs `gh api user --jq .login`.

---

## Shell / Scripts

| Sev | Rule | How to detect |
|-----|------|---------------|
| must | No `cd <dir> && git ...` compounds | Grep shell scripts for this pattern. Use `git -C /abs/path` instead. |
| should | No unquoted `$var` in loops expected to word-split | Grep for `for x in $var` — use `while read` instead in zsh/bash. |
