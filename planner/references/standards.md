# Project Standards

Canonical source. Used by `planner` (design-time checklist) and `reviewer` (review-time checklist via `../../reviewer/references/checklist.md`).

---

## 1. Architecture & Layering (HackSoft Django Styleguide)

- Business logic lives **only** in `services/` (writes) and `selectors/` (reads). Never in views, serializers, signals, forms, or model `save()`/`delete()`.
- Views call services/selectors and handle HTTP only. Target view shape: extract token → run serializer → on invalid raise via `raise_exception=True` → call service → return `Response`.
- Serializers are **input-only** — no business logic, no inline JSON parsing, no file-bytes extraction. Multipart file conversion belongs in a mapper (`services/mappers.py`), never in the view.
- `ChoiceField(choices=<NAMED_CONSTANT>)` — never inline choice lists. Extract to a named constant.
- A DRF field with `default=<value>` is already implicitly not required — never add `required=False` alongside a `default`.
- Use `model.clean()` (or Pydantic) for validation — not serializers, forms, or model methods.
- No Django signals, no `save()`/`delete()` overrides, no custom managers for business logic.
- Selectors must call `.select_related()` / `.prefetch_related()` for related models.
- Imports at top of file. Inline imports only to break circular dependencies.
- All code must be typed (`mypy` + `django-stubs`).
- Celery tasks live in `celery/` and are background-only — no direct domain logic.

---

## 2. Naming Conventions

- Functions/methods/variables/files: `snake_case`.
- Classes: `PascalCase`. Class-based services use `.execute()`; file is still `snake_case`.
- Services/selectors: `<entity>_<action>` for functions (e.g. `user_register`, `invoice_create`); `EntityAction` for classes.
- API URLs: `kebab-case`, **no trailing slashes** (e.g. `/api/voluntary-savings/apv/payroll-procedures`).
- Serializers: `PascalCase` + `Serializer` suffix (e.g. `PayrollProcedureRequestSerializer`).
- Constants/error codes: `UPPER_SNAKE_CASE`.
- Domain value constants: plain-class style (`class ProductType: CCV = "CCV"`). Never duplicate the literal. Promote up the package tree if a parent module needs it (avoid parent → child imports).

---

## 3. Language

- Code, comments, commit messages, API responses, error messages, docs, PR titles, PR bodies: **consistent within the project**. Choose one language and stick to it.
- Match the language convention already established in the project's existing code and CLAUDE.md.

---

## 4. Folder Conventions

Standard Django service tree:
```
<app>/
  services/          # write operations
  selectors/         # read operations
  tests/
    factories/
    services/
  celery/
  core/
    exceptions.py    # ApplicationError + ErrorCode
    exception_handlers.py  # custom DRF handler
  integrations/
    <service>/
      client.py      # HTTP client class
      schemas.py     # Pydantic response models
```

---

## 5. Auth, Errors & Integrations

- Services raise `ApplicationError(code, message, status_code)`. The custom DRF exception handler returns `{"code": "...", "message": "..."}`. Views never `try/except` business errors.
- Integration clients: use `httpx`, validate every external response with Pydantic, accept API tokens as explicit parameters — never read from globals. Shared response-handling (HTTP error check, upstream propagation, non-dict body guard) lives in one private `_handle_response` — never copy-paste across methods.
- **Sibling consistency**: if other services in the same app declare a client parameter as required (no default), new services must too. No `None` default + internal fallback.
- Factory functions instantiate clients in views for DI/testability.

---

## 6. Testing

- Framework: `pytest` + `factory_boy` + DRF `APIClient`.
- Test files mirror source: `{app}/tests/services/test_{service}.py`, `{app}/tests/test_{api}.py`.
- All external HTTP calls **must be mocked** — zero real network calls in tests.
- Use `APIClient` and `status.HTTP_*` constants — not raw strings or integer status codes.
- Mock at the point of use: if a function moved between modules, update mock paths to match the new import location.
- Run inside Docker: `docker compose -f <compose-file> exec django pytest` (or `run --rm` if containers are down). Never run `pytest` on the host unless the project runs natively.

---

## 7. Pre-Commit / Tooling (machine-enforced — do NOT duplicate in skills)

These run automatically via pre-commit or project hooks. Skills must not re-run them.

Common tool set (may vary by project): `trailing-whitespace`, `end-of-file-fixer`, `ruff-check --fix`, `ruff-format`, `mypy`.

---

## 8. Commit / PR Conventions

- Conventional Commits: `<type>(<scope>): <description>`. Types: `feat|fix|refactor|docs|test|chore|ci`.
- Scope = Django app or integration target.
- PR title = same format (used as squash commit). Ticket numbers go in the PR body, never in title or commit messages.
- Never commit directly to `main`. Branch first: `<type>/<short-description>`.
- Never push without explicit user approval.

---

## 9. PR Review Loop

- Per inline comment: fix-and-resolve OR decline with an inline reply citing the convention + decision, then resolve. Never leave a declined bot comment silent.
- After every push: re-request review to get a fresh evaluation of the new commit.
- CI lint failures take priority over optional bot suggestions.
- **Human reviewer threads**: push the fix and stop — no inline replies, no thread resolution. The reviewer owns their threads.

---

## 10. Shell / Operational Hygiene

- Never use compound `cd <dir> && git ...` — use `git -C /abs/path <cmd>`.
- All Python tooling runs via Docker or a project task runner. Never run on the host unless the project runs natively.

---

## 11. Plan Structure (canonical sections for planner output)

```
# <repo> — <brief task title>
## Context          — why, prior rounds, user decisions, ticket, worktree + SHA
## Changes          — numbered per-file, with fenced code + import notes
## Tests            — mock paths, suite, why existing pass
## Critical files   — markdown table: File | Status | Change
## Out of scope     — explicit non-goals bullet list
## Verification     — copy-paste bash blocks
```

Footer: "After all checks pass: commit + push **only after explicit user approval**."
