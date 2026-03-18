# Agentic Harness

**Infrastructure that makes AI coding agents productive and safe.**

[![CI](https://img.shields.io/github/actions/workflow/status/your-org/agentic-harness/ci.yml?branch=main&label=CI)](https://github.com/your-org/agentic-harness/actions)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Version](https://img.shields.io/github/v/release/your-org/agentic-harness?include_prereleases)](https://github.com/your-org/agentic-harness/releases)

---

## What It Does

- **Orchestrates AI agents from issue to merged PR** -- label a GitHub issue, and the harness plans, implements, reviews, and verifies the work automatically.
- **Uses your existing linters and test tools via `post_commands`** -- configure your build, test, and lint commands in `harness.yml` and the agent self-corrects when they fail.
- **Agent-friendly lint error messages** -- `lint-formatter.sh` wraps any linter and appends `FIX:` instructions from a YAML config, so the agent knows exactly how to correct each violation.
- **Structural tests for architecture enforcement** -- validate layer import rules and domain boundaries mechanically via `post_commands`. Catches violations that linters miss.
- **Works with any AI provider** -- ships with Claude and OpenAI adapters; bring your own with a single `run.sh` script.

## Architecture

The design is intentionally thin. GitHub Actions workflow steps control the phases (deterministic), prompt assembly is the main job of the scripts, and the agent runs its own loop (writes code, runs tests, fixes failures).

```
 GitHub Issue                                     Merged PR
     |                                                ^
     v                                                |
 [1. Label: "auto"]                          [5. Human Review]
     |                                                ^
     v                                                |
 +--------------------------------------------------+
 |           GITHUB ACTIONS WORKFLOW                  |
 |                                                    |
 |  Step 1: Plan Agent                                |
 |    assemble prompt -> call agent -> post plan      |
 |                                                    |
 |  Step 2: (on /approve) Executor Agent              |
 |    assemble prompt (with post_commands) ->          |
 |    agent writes code + runs tests + fixes failures |
 |                                                    |
 |  Step 3: Reviewer Agent                            |
 |    assemble prompt (with diff) ->                  |
 |    agent reviews -> posts findings                 |
 |                                                    |
 |  Step 4: Create PR                                 |
 +--------------------------------------------------+
     |
     v
 [CI Gate: runs post_commands again as safety net]
     |
     v
 [Deploy to Production]
     |
     v
 +--------------------------------------------------+
 |           SENTINEL (post-deploy monitoring)        |
 |                                                    |
 |  Alert -> Investigate Agent                        |
 |    correlate with recent PRs + logs ->             |
 |    root cause analysis + rollback assessment ->    |
 |    create hotfix issue if needed                   |
 +--------------------------------------------------+
```

### Key Design Principles

1. **Workflow steps are the state machine.** No shell-script orchestrator. GitHub Actions controls flow, concurrency, and error handling natively.
2. **The agent reads its own context.** AGENTS.md, ARCHITECTURE.md, harness.yml — the agent reads these via file tools. No prompt assembly scripts needed.
3. **The agent runs its own loop.** The agent reads post_commands from harness.yml, runs them, and fixes failures via its built-in agentic loop.
4. **CI is the final gate.** A separate workflow runs post_commands one more time on the PR as a safety net.

## Quick Start

### 1. Install

Copy the workflow files to your repository:

```bash
# Main pipeline
cp templates/workflows/harness-pipeline.yml .github/workflows/
# PR feedback handler
cp templates/workflows/harness-pr-feedback.yml .github/workflows/
# CI gate
cp templates/workflows/harness-ci.yml .github/workflows/
```

### 2. Configure

Create `harness.yml` and `ARCHITECTURE.md` in your repository root. The `ARCHITECTURE.md` defines domain boundaries and layer rules that agents respect when making changes. See `templates/ARCHITECTURE.md.template` for a starter.

Create `harness.yml`:

```yaml
version: "1"

project:
  name: "my-project"
  language: "kotlin"

agent:
  provider: "claude"
  model: "claude-opus-4-6"

execution:
  post_commands:
    - "./gradlew ktlintFormat"
    - "./gradlew compileKotlin"
    - "./gradlew test"
```

### 3. Set Up Auth

Add your agent credentials as GitHub Secrets. In the workflow file, uncomment the auth method you use:

```yaml
env:
  # Option 1: OAuth (Claude Max/Pro, no per-token cost)
  CLAUDE_ACCESS_TOKEN: ${{ secrets.CLAUDE_ACCESS_TOKEN }}
  # Option 2: API Key
  # ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
  # Option 3: AWS Bedrock
  # CLAUDE_CODE_USE_BEDROCK: "1"
  # AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  # AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

### 4. Add a Label

Create a GitHub issue and add the `auto` label. The harness generates a plan and posts it as a comment.

### 5. Approve

Reply `/approve` on the plan comment. The harness executes the plan, reviews the result, and creates a PR.

## Pipeline Phases

| Phase | What Happens | Agent Mode |
|-------|-------------|------------|
| **Plan** | Analyze issue, produce structured implementation plan | Read-only, text output |
| **Execute** | Write code, run verification commands, fix failures | Full tool access, agentic loop |
| **Review (Functional)** | Check if code satisfies issue requirements | Read-only, JSON output |
| **Review (NFR)** | Check performance, security, maintainability | Read-only, JSON output |
| **Respond** | Address human review comments on PR | Full tool access, agentic loop |
| **Investigate** | Analyze production alert, find root cause, assess rollback | Full tool access, read-heavy |
| **CI Check** | Run post_commands as final safety net | No agent, mechanical only |

## Sentinel (Post-Deploy Monitoring)

The Sentinel workflow closes the loop between deployment and incident response. When a production alert fires, an investigation agent automatically:

1. **Parses the alert** -- identifies the affected service, error type, and severity.
2. **Correlates with recent deployments** -- checks PRs merged and deployed in the last 4 hours.
3. **Gathers evidence** -- queries Datadog traces, OpenSearch logs, and reads suspected diffs.
4. **Assesses rollback feasibility** -- checks for DB migrations that would make rollback unsafe.
5. **Produces recommendations** -- structured JSON with root cause, impact, and prioritized actions.
6. **Creates a hotfix issue** -- if a code fix is needed, opens a GitHub issue with the `auto` label, triggering the standard harness pipeline.

To enable Sentinel, copy the workflow template:

```bash
cp templates/workflows/harness-sentinel.yml .github/workflows/
```

Then configure your Slack bot or monitoring tool to send a `repository_dispatch` event with type `alert-triggered`. See [Getting Started](docs/getting-started.md) for details.

## Project Structure

```
agentic-harness/
  scripts/
    run-ci-checks.sh        Runs post_commands for CI gate
    lint-formatter.sh       Wraps linter output with agent-friendly fix hints
    jira-helpers.sh         Bash functions for dynamic Jira access
  prompts/
    planner.md              Planning phase system prompt
    executor.md             Execution phase system prompt
    reviewer-functional.md  Functional review system prompt
    reviewer-nonfunctional.md  NFR review system prompt
    incident-investigator.md   Sentinel investigation system prompt
  templates/
    workflows/
      harness-pipeline.yml  Main pipeline workflow
      harness-pr-feedback.yml  PR feedback handler
      harness-ci.yml        CI gate workflow
      harness-sentinel.yml  Sentinel alert investigation workflow
    harness.yml.template    Example harness.yml
    AGENTS.md.template      Example AGENTS.md
    ARCHITECTURE.md.template  Example ARCHITECTURE.md (domain map)
    lint-hints.yml.template Example agent-friendly lint hint config
  init/                     Initialization scripts
  examples/                 Example configurations per language
    structural-tests/      Layer import and domain boundary validators
  docs/                     Documentation
```

## Configuration

The `harness.yml` file controls all behavior. See the [full configuration reference](docs/configuration.md) for every option.

Minimal example:

```yaml
version: "1"
project:
  name: "my-project"
  language: "typescript"
agent:
  provider: "claude"
  model: "claude-opus-4-6"
execution:
  post_commands:
    - "pnpm lint"
    - "pnpm type-check"
    - "pnpm test"
```

### Recommended Project Documentation Structure

For best results with AI agents, maintain these files and directories:

```
your-repo/
  AGENTS.md                  # Table of contents for agents (~100 lines)
  ARCHITECTURE.md            # Domain map, layer rules, data flow
  docs/
    design-docs/             # Why decisions were made
    exec-plans/              # Step-by-step implementation plans
    product-specs/           # What to build
    references/              # External links, API docs
```

The `ARCHITECTURE.md` file defines domain boundaries and layer import rules. Agents check it before making cross-module changes. Generate a starter version with `init/setup.sh`.

## Adding a Custom Provider

Create `providers/your-provider/run.sh` with a single function:

```bash
agent_run() {
  local phase="$1" prompt_file="$2" model="$3"
  # phase: plan | execute | review-functional | review-nonfunctional | respond
  # prompt_file: path to assembled prompt
  # model: model identifier from harness.yml

  # Your implementation here
}
```

The action sources this file and calls `agent_run`. That is the entire contract.

## Documentation

- [Getting Started](docs/getting-started.md) -- step-by-step adoption guide
- [Configuration Reference](docs/configuration.md) -- every harness.yml option
- [Agent Providers](docs/agent-providers.md) -- provider abstraction and custom providers
- [Context Engineering](docs/context-engineering.md) -- how context assembly works

## Contributing

Contributions are welcome. Please read the following before submitting a PR:

1. **Fork and branch.** Create a feature branch from `main`.
2. **Follow existing patterns.** Read the codebase before adding new abstractions.
3. **Test your changes.** Add or update tests for any new functionality.
4. **Run linters.** Ensure `shellcheck` passes on all shell scripts.
5. **Write clear commit messages.** Use conventional commit format (`feat:`, `fix:`, `docs:`, etc.).
6. **Keep PRs focused.** One logical change per PR.

## License

Licensed under the [Apache License, Version 2.0](LICENSE).

Copyright 2026 Agentic Harness Contributors.

---

Built with the belief that AI agents should be **productive** and **safe** -- not one or the other.
