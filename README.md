# Agentic Harness

**Orchestrate AI coding agents from GitHub issue to merged PR.**

---

## What It Does

1. Label a GitHub issue with `auto`
2. Agent plans, implements, reviews, and creates a PR
3. CI runs your existing linters/tests as a safety net
4. Human reviews and merges

## Pipeline

```
Issue (label: auto) → Plan Agent → Human approves → Executor Agent → Reviewer Agents → PR → CI Gate → Human Review → Merge
```

## Quick Start

### 1. Copy workflows

```bash
mkdir -p .github/workflows
cp templates/workflows/harness-pipeline.yml .github/workflows/
cp templates/workflows/harness-pr-feedback.yml .github/workflows/
cp templates/workflows/harness-ci.yml .github/workflows/
```

### 2. Create `harness.yml`

```yaml
version: "1"
project:
  name: "my-project"
  language: "kotlin"
execution:
  post_commands:
    - "./gradlew ktlintFormat"
    - "./gradlew compileKotlin"
    - "./gradlew test"
```

### 3. Create `AGENTS.md`

A ~100-line table of contents for the agent. See `templates/AGENTS.md.template`.

### 4. Set up auth

Add a GitHub Secret, then uncomment the matching line in your workflow:

```yaml
env:
  # OAuth (Claude Max/Pro):
  CLAUDE_ACCESS_TOKEN: ${{ secrets.CLAUDE_ACCESS_TOKEN }}
  # Or API Key:
  # ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

### 5. Label an issue

Add the `auto` label to a GitHub issue. The agent posts a plan. Reply `/approve` to start.

## How It Works

The workflows use [`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action) directly. The agent reads `harness.yml`, `AGENTS.md`, and `ARCHITECTURE.md` via its file tools — no prompt assembly scripts needed.

| Phase | What happens |
|-------|-------------|
| **Plan** | Agent analyzes issue, posts structured plan as comment |
| **Execute** | Agent writes code, reads `post_commands` from `harness.yml`, runs them, fixes failures |
| **Review** | Two agents review in parallel: functional correctness + non-functional quality |
| **CI Gate** | Workflow runs `post_commands` again as final safety net (not an agent) |
| **Respond** | Agent addresses human review comments on the PR |

## What's in the repo

```
prompts/                   Phase-specific system prompts (the real value)
templates/
  workflows/               GitHub Actions workflow templates
  harness.yml.template     Config template
  AGENTS.md.template       Agent context template (~100 lines, table of contents)
  ARCHITECTURE.md.template Domain map, layer rules
  lint-hints.yml.template  Agent-friendly lint fix hints
scripts/
  run-ci-checks.sh         CI gate: runs post_commands
  lint-formatter.sh        Wraps linters with FIX: hints
  jira-helpers.sh          Bash functions for Jira access
examples/
  kotlin-spring-boot/      Kotlin example config
  typescript-nextjs/       TypeScript example config
  python-fastapi/          Python example config
  structural-tests/        Layer import + domain boundary validators
init/setup.sh              Interactive project bootstrapper
docs/                      Documentation
```

## Agent-Friendly Lint Errors

Wrap any linter with `lint-formatter.sh` to append fix instructions the agent can follow:

```yaml
# harness.yml
execution:
  post_commands:
    - "lint-formatter.sh './gradlew ktlintCheck' --hints .harness/lint-hints.yml"
```

Before: `Wildcard import (no-wildcard-imports)`
After: `Wildcard import (no-wildcard-imports)`
`  FIX: Replace import foo.* with explicit imports for each used class.`

See `templates/lint-hints.yml.template` for rule examples.

## Structural Tests

Enforce architecture rules mechanically as `post_commands`:

```yaml
execution:
  post_commands:
    - "check-layer-imports.sh --config .harness/layers.yml"
    - "check-domain-boundaries.sh --config .harness/domains.yml"
```

See `examples/structural-tests/` for scripts and config.

## Recommended Project Structure

```
your-repo/
  AGENTS.md              Table of contents for agents
  ARCHITECTURE.md        Domain map, layer rules
  harness.yml            Harness config (post_commands, scope)
  docs/
    design-docs/         Why decisions were made
    exec-plans/          Step-by-step plans
    product-specs/       What to build
```

## Docs

- [Getting Started](docs/getting-started.md)
- [Configuration](docs/configuration.md)
- [Agent Providers](docs/agent-providers.md)
- [Context Engineering](docs/context-engineering.md)

## License

[Apache 2.0](LICENSE)
