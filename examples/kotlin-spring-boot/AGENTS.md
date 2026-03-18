# AGENTS.md — Kotlin Spring Boot Project

Instructions for AI coding agents working in this Kotlin Spring Boot codebase.

## Architecture

This project follows Clean Architecture with a multi-module Gradle structure:

- **core/entity/** — JPA entities and domain logic. All state mutations happen here.
- **core/repository/** — Hybrid JPA + QueryDSL data access layer.
- **core/service/** — Business logic and orchestration.
- **app/api/** — REST controllers, DTOs, and request/response mapping.
- **buildSrc/** — Centralized dependency versions in `Dependencies.kt`.

Data flows inward: Controllers call Services, Services call Repositories, Repositories access Entities. Never skip layers.

### Layer Import Rules

These rules are enforced mechanically by `check-layer-imports.sh`:

| Layer | Can Import From |
|-------|----------------|
| **entity** | (nothing) |
| **repository** | entity |
| **service** | entity, repository |
| **api** | entity, service |

A repository must never import from a service. A service must never import from a controller. If you need shared types across layers, place them in the entity layer.

## Kotlin Conventions

- **No wildcard imports.** Use explicit imports for every class.
- **LazyLogger pattern.** When a class needs logging, use:
  ```kotlin
  companion object {
      private val logger by LazyLogger()
  }
  ```
  Do NOT use `LoggerFactory.getLogger()` or `KotlinLogging`.
- **Entity method updates.** Never set entity fields directly in the service layer. All field mutations must go through domain methods on the entity (e.g., `entity.complete()`, `entity.updateName(newName)`).
- **QueryDSL for queries.** Use QueryDSL with `JPAQueryFactory` for anything beyond simple `findById`. No raw JPQL strings.
- **Spring Cache annotations.** Use `@Cacheable`, `@CacheEvict` for caching. No manual Redis operations.

## Code Style

- Run `./gradlew ktlintFormat` before every commit.
- Run `./gradlew detekt` to catch code smells.
- Keep functions under 40 lines. Extract helpers for complex logic.
- Use meaningful names. Code should be self-documenting without comments.
- Remove unused variables, imports, and methods when found.

## Testing

- **Framework:** Kotest 5.9.1 with `DescribeSpec` style.
- **Mocking:** MockK 1.14.4 with `relaxed = false` (strict mocks).
- **Pattern:** Arrange-Act-Assert within `describe` / `it` blocks.
- Run tests: `./gradlew test`
- Run a single test class: `./gradlew test --tests "com.example.MyTest"`

Write tests for every new public function. Cover happy paths, error paths, and edge cases.

## API Conventions

- All endpoints must include Swagger annotations (`@Tag`, `@Operation`, `@Schema`).
- Use `@CurrentMember memberId: Long` for user authentication (JWT).
- Use `@CurrentGatewayApiKey gatewayKeyId: Long` for service authentication (API Key).
- Never use `String userId` — always `Long memberId`.

## Quality Checks

The following commands run automatically after every code change. If any fails, the agent sees the output and self-corrects.

- `./gradlew ktlintFormat` -- format code before compilation
- `./gradlew compileKotlin` -- verify compilation
- `./gradlew test` -- run all tests
- `./gradlew ktlintCheck` -- lint verification
- `./gradlew detekt` -- static analysis
