# Configuration Reference

Complete reference for every option in `harness.yml`. The configuration file lives at the repository root (or at the path specified by the `config_path` action input).

---

## File Format

```yaml
# harness.yml — Agentic Harness configuration
# All paths are relative to the repository root.
```

## Top-Level Options

### `provider`

| | |
|---|---|
| **Type** | `string` |
| **Default** | `claude` |
| **Values** | `claude`, `openai`, or a path to a custom provider directory |
| **Description** | The AI provider to use for all agent operations. |

```yaml
provider: claude
```

### `model`

| | |
|---|---|
| **Type** | `string` |
| **Default** | `claude-opus-4-6` |
| **Description** | The model identifier to pass to the provider. Must be a model supported by the chosen provider. |

```yaml
model: claude-opus-4-6
```

### `label`

| | |
|---|---|
| **Type** | `string` |
| **Default** | `auto` |
| **Description** | The GitHub issue label that triggers the harness pipeline. |

```yaml
label: ai-task
```

### `debug`

| | |
|---|---|
| **Type** | `boolean` |
| **Default** | `false` |
| **Description** | Enable verbose debug logging in the orchestrator and all sub-scripts. |

```yaml
debug: true
```

---

## Pipeline Options

Control how the pipeline state machine behaves.

### `pipeline.require_approval`

| | |
|---|---|
| **Type** | `boolean` |
| **Default** | `true` |
| **Description** | Whether to require `/approve` before moving from planning to execution. If `false`, the agent proceeds immediately after planning. |

### `pipeline.auto_approve_complexity`

| | |
|---|---|
| **Type** | `string` |
| **Default** | `none` |
| **Values** | `none`, `small`, `medium`, `all` |
| **Description** | Auto-approve plans at or below this complexity level. The agent self-assesses complexity during planning. |

### `pipeline.timeout_minutes`

| | |
|---|---|
| **Type** | `integer` |
| **Default** | `30` |
| **Description** | Maximum time in minutes for the entire pipeline run before it is marked as failed. |

```yaml
pipeline:
  require_approval: true
  auto_approve_complexity: small
  timeout_minutes: 45
```

---

## Execution Options

Configure how the agent's code changes are verified.

### `execution.pre_commands`

| | |
|---|---|
| **Type** | `list[string]` |
| **Default** | `[]` |
| **Description** | Shell commands to run before the agent writes code (e.g., install dependencies, format existing code). |

### `execution.post_commands`

| | |
|---|---|
| **Type** | `list[string]` |
| **Default** | `[]` |
| **Description** | Shell commands to run after the agent writes code. These are your existing build, test, and lint tools. If any command exits non-zero, the agent sees the error output and self-corrects. |

### `execution.max_retries`

| | |
|---|---|
| **Type** | `integer` |
| **Default** | `3` |
| **Description** | Number of times the agent is allowed to self-correct when `post_commands` fail before giving up. |

### `execution.branch_pattern`

| | |
|---|---|
| **Type** | `string` |
| **Default** | `{issue_number}-{short_title}` |
| **Description** | Pattern for auto-created branch names. Available placeholders: `{issue_number}`, `{short_title}`, `{issue_title_slug}`. |

```yaml
execution:
  pre_commands:
    - "./gradlew ktlintFormat"
  post_commands:
    - "./gradlew compileKotlin"
    - "./gradlew test"
    - "./gradlew ktlintCheck"
  max_retries: 3
  branch_pattern: "harness/{issue_number}-{issue_title_slug}"
```

---

## Context Options

Control how context is assembled for agent prompts.

### `context.agents_md`

| | |
|---|---|
| **Type** | `string` |
| **Default** | `AGENTS.md` |
| **Description** | Path to the agent instructions file. This is always included in the hot context tier. |

### `context.include`

| | |
|---|---|
| **Type** | `list[string]` |
| **Default** | `["**"]` |
| **Description** | Glob patterns for files the agent is allowed to read and modify. |

### `context.exclude`

| | |
|---|---|
| **Type** | `list[string]` |
| **Default** | `["node_modules/**", "build/**", "dist/**", ".git/**"]` |
| **Description** | Glob patterns for files excluded from context assembly. |

### `context.token_budget`

| | |
|---|---|
| **Type** | `integer` |
| **Default** | `100000` |
| **Description** | Maximum token count for the assembled context. The context assembler prioritizes hot > warm > cold tiers within this budget. |

### `context.hot`

| | |
|---|---|
| **Type** | `list[string]` |
| **Default** | `["AGENTS.md", "harness.yml"]` |
| **Description** | Files always included at highest priority. |

### `context.warm`

| | |
|---|---|
| **Type** | `list[string]` |
| **Default** | `[]` |
| **Description** | Glob patterns for files included when they are relevant to the current issue (e.g., files in the same module). |

### `context.cold`

| | |
|---|---|
| **Type** | `list[string]` |
| **Default** | `[]` |
| **Description** | Glob patterns for files included only when token budget allows. Lowest priority. |

```yaml
context:
  agents_md: AGENTS.md
  include:
    - "src/**"
    - "tests/**"
    - "docs/**"
  exclude:
    - "node_modules/**"
    - "dist/**"
    - "*.lock"
  token_budget: 120000
  hot:
    - AGENTS.md
    - CLAUDE.md
    - harness.yml
  warm:
    - "src/core/**"
  cold:
    - "docs/**/*.md"
```

---

## Integration Options

### Jira

| | |
|---|---|
| **`integrations.jira.enabled`** | `boolean`, default `false`. Enable Jira integration. |
| **`integrations.jira.project_key`** | `string`. The Jira project key (e.g., `PROJ`). |
| **`integrations.jira.base_url`** | `string`. Your Jira instance URL. |
| **`integrations.jira.sync_status`** | `boolean`, default `false`. Sync pipeline stage transitions to Jira ticket status. |
| **`integrations.jira.auth_secret`** | `string`, default `JIRA_API_TOKEN`. Name of the GitHub secret containing the Jira API token. |

```yaml
integrations:
  jira:
    enabled: true
    project_key: COREAI
    base_url: https://your-org.atlassian.net
    sync_status: true
    auth_secret: JIRA_API_TOKEN
```

---

## Language-Specific Examples

### Kotlin / Spring Boot

```yaml
provider: claude
model: claude-opus-4-6

execution:
  pre_commands:
    - "./gradlew ktlintFormat"
  post_commands:
    - "./gradlew compileKotlin"
    - "./gradlew test"
    - "./gradlew ktlintCheck"
  max_retries: 3

context:
  agents_md: AGENTS.md
  include:
    - "src/**"
    - "core/**"
    - "app/**"
    - "buildSrc/**"
  exclude:
    - "build/**"
    - "*.jar"
    - ".gradle/**"
```

### TypeScript / Next.js

```yaml
provider: claude
model: claude-opus-4-6

execution:
  post_commands:
    - "pnpm lint --fix"
    - "pnpm type-check"
    - "pnpm test"
    - "pnpm build"
  max_retries: 3

context:
  agents_md: AGENTS.md
  include:
    - "src/**"
    - "tests/**"
    - "public/**"
  exclude:
    - "node_modules/**"
    - ".next/**"
    - "dist/**"
    - "*.lock"
```

### Python / FastAPI

```yaml
provider: openai
model: gpt-4o

execution:
  pre_commands:
    - "ruff check --fix ."
    - "black ."
  post_commands:
    - "pytest"
    - "mypy ."
    - "ruff check ."
  max_retries: 3

context:
  agents_md: AGENTS.md
  include:
    - "app/**"
    - "tests/**"
  exclude:
    - ".venv/**"
    - "__pycache__/**"
    - "*.pyc"
```

---

## Environment Variables

These environment variables are set automatically by the GitHub Action but can be overridden for local development or custom CI setups.

| Variable | Description |
|----------|-------------|
| `HARNESS_ROOT` | Absolute path to the agentic-harness action directory |
| `HARNESS_CONFIG` | Path to the harness.yml file |
| `HARNESS_PROVIDER` | Active provider name |
| `HARNESS_MODEL` | Active model identifier |
| `HARNESS_DEBUG` | Set to `true` for debug logging |
| `HARNESS_LOG_LEVEL` | Log level: `debug`, `info`, `warn`, `error` |
| `AGENT_TOKEN` | API key for the AI provider |
| `GITHUB_TOKEN` | GitHub API token |

---

## Validation

The harness validates your configuration on startup. If `harness.yml` is missing or contains invalid values, the orchestrator exits with a clear error message and does not proceed.

Common validation errors:

- **Unknown provider**: The `provider` value does not match a built-in name or a valid directory path.
- **Invalid token_budget**: Must be a positive integer.
- **Invalid glob patterns**: Patterns in `include` or `exclude` that cannot be parsed.
