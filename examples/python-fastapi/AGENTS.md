# AGENTS.md — Python FastAPI Project

Instructions for AI coding agents working in this Python FastAPI codebase.

## Architecture

This project follows a layered architecture with dependency injection:

- **src/api/** — FastAPI route handlers (thin controllers). Define endpoints, validate input, delegate to services.
- **src/services/** — Business logic layer. All domain rules and orchestration live here.
- **src/models/** — SQLAlchemy ORM models. Define database schema and relationships.
- **src/schemas/** — Pydantic models for request/response validation and serialization.
- **src/repositories/** — Data access layer. All database queries go through repository classes.
- **src/core/** — Configuration, dependencies, and shared utilities.

Data flows inward: Routes call Services, Services call Repositories, Repositories access Models. Never skip layers.

## Python Conventions

- **No wildcard imports.** Always import specific names: `from module import ClassName`.
- **No print() in production code.** Use the `logging` module with structured log messages.
- **Type hints everywhere.** All function signatures must have complete type annotations. Use `mypy --strict` to verify.
- **Pydantic for validation.** Request and response models must extend `BaseModel`. Never accept raw dicts from API endpoints.
- **Async by default.** Route handlers and service methods should be `async def` unless they perform only synchronous CPU-bound work.

## Project Structure

```
src/
  api/
    v1/
      endpoints/       # Route handlers grouped by domain
      dependencies.py  # FastAPI dependency injection
  services/            # Business logic
  repositories/        # Database access (SQLAlchemy queries)
  models/              # SQLAlchemy ORM models
  schemas/             # Pydantic request/response models
  core/
    config.py          # Settings via pydantic-settings
    database.py        # Database session management
    security.py        # Authentication and authorization
tests/
  api/                 # API integration tests
  services/            # Service unit tests
  conftest.py          # Shared fixtures
```

## Testing

- **Framework:** pytest with pytest-asyncio for async tests.
- **Fixtures:** Define reusable fixtures in `conftest.py`. Use factory fixtures for complex object creation.
- **Mocking:** Use `unittest.mock` or `pytest-mock`. Mock at the repository boundary, not inside services.
- Run tests: `pytest`
- Run with coverage: `pytest --cov=src`
- Write tests for every new endpoint and service method. Cover happy paths, validation errors, and edge cases.

## Code Quality

- Run `ruff check --fix .` and `black .` before every commit.
- Run `mypy .` to verify type correctness.
- Keep functions under 30 lines. Extract helpers for complex logic.
- Use docstrings for public functions, but prefer self-documenting code over comments.
- Remove unused variables and imports when found.

## Quality Checks

The following commands run automatically after every code change. If any fails, the agent sees the output and self-corrects.

- `ruff check --fix .` -- linting and import sorting with auto-fix
- `black .` -- code formatting
- `pytest` -- run all tests
- `mypy .` -- full type-checking
- `ruff check .` -- final lint verification
