# Checklist by File Type

Quick lookup: given a changed file path, which checklist sections to apply.

| File pattern | Checklist sections to apply |
|---|---|
| `*/apis.py`, `*/views.py` | Thin-views, DRF-pattern, Naming |
| `*/serializers.py` | Serializer-rules, Constants, Naming, DRF-pattern |
| `*/services/*.py`, `*/services.py` | Layering, Sibling-consistency, Error-handling, Naming |
| `*/selectors/*.py`, `*/selectors.py` | Layering, ORM-queries, Naming |
| `*/models.py` | Model-rules, Constants, Naming |
| `*/constants.py` | Constants, Naming, Layering (import direction) |
| `*/integrations/*/client.py` | Integration-client-rules, Error-handling, Naming |
| `*/integrations/*/schemas.py` | Pydantic-schemas, Naming |
| `*/tests/test_*.py`, `*/tests/services/test_*.py` | Test-rules, Mock-paths, Naming |
| `*/tests/factories/*.py` | Factory-rules, Naming |
| `*/migrations/*.py` | Auto-generated — skip review unless the user explicitly flagged a concern |
| `urls.py` | URL-naming (kebab-case, no trailing slash) |
| `*/celery/*.py` | Celery-rules (background-only, no business logic), Naming |
| `*.md` | Language (consistent with project convention) |
| `pyproject.toml`, `docker-compose*.yml` | No code-style checks — skip |
| `*.sh` | Shell-hygiene (no `cd && git`, use `git -C`; quote paths; no word-split) |

## Notes

- A single file may match multiple patterns — apply all matching sections.
- `migrations/` files are auto-generated: only flag if the migration contains unexpected field changes (e.g. a `choices` diff that reveals an undeclared constant change).
- Frontend files (`*.tsx`, `*.ts`, `*.jsx`, `*.js`, `*.vue`, `*.css`, `*.scss`, `*.html`) are out of scope for Django-style checklist rules (layering, serializers, services, ORM). However, the **Commit / PR** section always applies to them — including the screenshot rule and front/back label check, which are **author-scoped** (enforced only on your own PRs; skipped when reviewing someone else's — see the `†` note in `checklist.md`).
