# Getting Started

This guide walks you through adopting Agentic Harness in an existing project, from zero to your first agent-generated PR.

---

## Prerequisites

Before you begin, make sure you have:

- A **GitHub repository** where you have admin access (to configure Actions and secrets)
- **One** of these authentication methods for your AI provider:
  - **API Key**: [Anthropic API key](https://console.anthropic.com/) or [OpenAI API key](https://platform.openai.com/)
  - **Claude Max/Pro subscription**: No API key needed — use your OAuth token
  - **AWS Bedrock**: Use your AWS credentials (no Anthropic key needed)
  - **GCP Vertex AI**: Use your GCP credentials (no Anthropic key needed)
- **GitHub Actions** enabled on the repository
- `bash` 4.0+, `jq`, and `curl` available in your CI environment (all pre-installed on `ubuntu-latest`)

## Step 1: Run the Init Script

The fastest way to get started is the init script. From your repository root:

```bash
# Option A: npx (if published to npm)
npx agentic-harness init

# Option B: curl from GitHub
curl -sL https://raw.githubusercontent.com/your-org/agentic-harness/main/init/bootstrap.sh | bash
```

This creates the following files in your repository:

```
your-repo/
  harness.yml                          # Main configuration
  AGENTS.md                            # Agent instructions (customize this)
  ARCHITECTURE.md                      # Domain map and layer rules
  .github/workflows/agentic-harness.yml  # GitHub Actions workflow
  .harness/
    lessons-learned.jsonl              # Feedback loop storage
  docs/
    design-docs/                       # Why decisions were made
    exec-plans/                        # Step-by-step implementation plans
    product-specs/                     # What to build
    references/                        # External links, API docs
```

If you prefer to set things up manually, continue through the steps below and create each file by hand.

## Step 2: Configure harness.yml

Open `harness.yml` and adjust it to your project. Here is a minimal working configuration:

```yaml
# harness.yml
provider: claude
model: claude-opus-4-6

execution:
  post_commands:
    - "npm run lint"
    - "npm test"
    - "npm run build"
  max_retries: 3

context:
  agents_md: AGENTS.md
  include:
    - "src/**"
    - "tests/**"
  exclude:
    - "node_modules/**"
    - "dist/**"
    - "build/**"
```

Key decisions at this stage:

| Option | What to consider |
|--------|-----------------|
| `provider` | Which AI service you have API access to |
| `model` | Larger models produce better plans but cost more |
| `execution.post_commands` | Your existing build, test, and lint commands |
| `context.include` | Only include source directories the agent should read and modify |
| `context.exclude` | Exclude build artifacts, dependencies, and large generated files |

See the [Configuration Reference](configuration.md) for all available options.

## Step 3: Set Up Authentication

Go to your repository: **Settings > Secrets and variables > Actions > New repository secret**.

Pick **one** method:

### Option A: API Key (simplest, pay-per-token)
Add secret `ANTHROPIC_API_KEY` with your Anthropic API key.

### Option B: Claude Max/Pro (use your subscription, no per-token cost)
Run locally: `claude config get oauthToken`
Add secret `CLAUDE_ACCESS_TOKEN` with the returned token.
Then in your workflow, set `CLAUDE_ACCESS_TOKEN` as an env var instead of `agent_token`.

### Option C: AWS Bedrock (use your AWS account)
Add secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`.
In your workflow, set env var `CLAUDE_CODE_USE_BEDROCK: "1"`.

### Option D: GCP Vertex AI (use your GCP project)
Add secrets: `GCP_PROJECT_ID`, plus configure workload identity or service account key.
In your workflow, set env var `CLAUDE_CODE_USE_VERTEX: "1"`.

---

`GITHUB_TOKEN` is provided automatically by GitHub Actions. If your workflow needs to push to protected branches, create a Personal Access Token (PAT) and store it as `GH_PAT`.

## Step 4: Create AGENTS.md

`AGENTS.md` is the single most important file for agent quality. It tells the agent how your project works. A good `AGENTS.md` should cover:

```markdown
# AGENTS.md

## Project Overview
Brief description of what this project does and its tech stack.

## Build and Test Commands
- Build: `npm run build`
- Test: `npm test`
- Lint: `npm run lint`
- Format: `npm run format`

## Code Conventions
- Use TypeScript strict mode
- Components go in `src/components/`
- Tests go next to source files as `*.test.ts`
- Use named exports, not default exports

## Architecture
- Describe your module structure
- Note key patterns (repository pattern, service layer, etc.)
- Call out non-obvious design decisions

## Do Not
- Do not modify `package-lock.json` manually
- Do not add dependencies without justification
- Do not use `any` type in TypeScript
```

The more specific and actionable your `AGENTS.md`, the better the agent performs. Treat it as onboarding documentation for a new team member.

## Step 4b: Create ARCHITECTURE.md

`ARCHITECTURE.md` is the domain map that tells agents where things live and what the dependency rules are. It complements `AGENTS.md` by defining:

- **Domain boundaries**: which modules exist and what they own
- **Layer architecture**: the import direction rules (e.g., Service may import Repository, but not vice versa)
- **Cross-cutting concerns**: how auth, logging, and telemetry are injected
- **Data flow**: how requests move through the system

Use `templates/ARCHITECTURE.md.template` as a starting point. A good `ARCHITECTURE.md` prevents agents from creating wrong-direction imports or placing code in the wrong module.

### Recommended docs/ Structure

Create these directories for agent context navigation:

```
docs/
  design-docs/      -- Why decisions were made (ADRs, design rationales)
  exec-plans/       -- Step-by-step implementation plans (agent-generated or manual)
  product-specs/    -- What to build (PRDs, feature specs)
  references/       -- External links, API docs, vendor documentation
```

Agents check `docs/design-docs/` before proposing new patterns, and output execution plans to `docs/exec-plans/` for permanent record.

## Step 5: Configure Your Build/Test/Lint Commands

Add your project's existing tools to `execution.post_commands` in `harness.yml`. These commands run after the agent writes code. If any fails, the agent sees the error output and self-corrects.

```yaml
# In harness.yml — Kotlin example
execution:
  post_commands:
    - "./gradlew ktlintFormat"
    - "./gradlew compileKotlin"
    - "./gradlew test"
  max_retries: 3
```

```yaml
# TypeScript example
execution:
  post_commands:
    - "pnpm lint --fix"
    - "pnpm type-check"
    - "pnpm test"
  max_retries: 3
```

```yaml
# Python example
execution:
  post_commands:
    - "ruff check --fix ."
    - "black ."
    - "pytest"
    - "mypy ."
  max_retries: 3
```

No wrapper scripts or plugins needed -- just point it at your existing tools.

### Optional: Agent-Friendly Lint Error Messages

Standard linter output tells you _what_ is wrong but not _how to fix it_. The `lint-formatter.sh` script wraps any linter command and appends fix instructions from a YAML file, making errors immediately actionable for AI agents.

**Before** (raw linter output):
```
Wildcard import (no-wildcard-imports)
```

**After** (with lint-formatter.sh):
```
Wildcard import (no-wildcard-imports)
  FIX: Replace `import foo.*` with explicit imports for each used class.
  See: AGENTS.md#imports
```

To set it up:

1. Copy the template to your project:
   ```bash
   cp templates/lint-hints.yml.template .harness/lint-hints.yml
   ```

2. Customize the rules for your linters and conventions.

3. Use `lint-formatter.sh` in your post_commands instead of calling the linter directly:
   ```yaml
   execution:
     post_commands:
       - "lint-formatter.sh './gradlew ktlintCheck' --hints .harness/lint-hints.yml"
   ```

The script requires `yq` for reading the YAML file. If `yq` is not available, it falls back to showing the raw linter output.

### Optional: Structural Tests (Architecture Enforcement)

Structural tests validate architecture rules mechanically -- "service can import repository, but repository cannot import service." They catch violations that linters miss, and they run as regular post_commands.

The harness provides two example scripts in `examples/structural-tests/`:

**Layer import validation** (`check-layer-imports.sh`): Reads layer definitions from `.harness/layers.yml` and checks that no file imports from a layer it is not allowed to depend on.

```yaml
# .harness/layers.yml
layers:
  - name: entity
    path: "core/entity/**"
    can_import: []
  - name: repository
    path: "core/repository/**"
    can_import: [entity]
  - name: service
    path: "core/service/**"
    can_import: [entity, repository]
  - name: api
    path: "app/api/**"
    can_import: [entity, service]
```

**Domain boundary validation** (`check-domain-boundaries.sh`): Reads domain definitions from `.harness/domains.yml` and checks that cross-domain imports only go through public API paths.

To set up structural tests:

1. Copy the scripts to your project or reference them from the harness:
   ```bash
   cp examples/structural-tests/check-layer-imports.sh .harness/
   cp examples/structural-tests/layers.yml.example .harness/layers.yml
   ```

2. Customize `.harness/layers.yml` for your architecture.

3. Add to post_commands:
   ```yaml
   execution:
     post_commands:
       - "./gradlew compileKotlin"
       - "./gradlew test"
       - "check-layer-imports.sh --config .harness/layers.yml"
   ```

When a violation is found, the script reports exactly which file, line, and rule was broken, plus a fix instruction -- so the agent can self-correct immediately.

## Step 6: Set Up the GitHub Actions Workflow

If the init script did not create the workflow file, add it manually:

```yaml
# .github/workflows/agentic-harness.yml
name: Agentic Harness

on:
  issues:
    types: [labeled]
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  pull_request:
    types: [synchronize]

permissions:
  contents: write
  issues: write
  pull-requests: write

jobs:
  harness:
    runs-on: ubuntu-latest
    # Only run when the trigger label is present
    if: >-
      (github.event_name == 'issues' && contains(github.event.issue.labels.*.name, 'auto')) ||
      (github.event_name == 'issue_comment') ||
      (github.event_name == 'pull_request_review_comment') ||
      (github.event_name == 'pull_request')
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 50

      - uses: your-org/agentic-harness@v1
        with:
          provider: claude
          agent_token: ${{ secrets.ANTHROPIC_API_KEY }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
          event_type: ${{ github.event.action }}
```

## Step 7: Test with a Sample Issue

Create a test issue to verify everything works:

1. Go to your repository's **Issues** tab.
2. Create a new issue with a small, well-defined task:
   ```
   Title: Add a health check endpoint

   Add a GET /health endpoint that returns { "status": "ok" } with a 200 status code.
   This endpoint should not require authentication.
   ```
3. Add the **`auto`** label to the issue.
4. Watch the **Actions** tab -- you should see the harness workflow start.
5. After a minute or two, the harness posts a plan comment on the issue.
6. Review the plan and reply with `/approve` to proceed.
7. The harness executes the plan, creates a PR, and runs self-review.

If something goes wrong, check:
- The Actions workflow logs for error messages.
- That your API key secret is correctly set.
- That the `harness.yml` file is valid YAML and committed to the default branch.

## Step 8: Customize for Your Workflow

Once the basic flow works, consider these customizations:

### Require plan approval for large changes

```yaml
# harness.yml
pipeline:
  require_approval: true          # Always require /approve before execution
  auto_approve_complexity: small  # Auto-approve only "small" complexity plans
```

### Set retry limits for post_commands

```yaml
execution:
  post_commands:
    - "./gradlew build"
    - "./gradlew test"
  max_retries: 3          # How many times the agent can self-correct on failures
```

### Enable Jira integration

```yaml
integrations:
  jira:
    enabled: true
    project_key: PROJ
    base_url: https://your-org.atlassian.net
    sync_status: true
```

### Customize context assembly

```yaml
context:
  token_budget: 100000    # Max tokens for context window
  hot:
    - AGENTS.md
    - harness.yml
  warm:
    - "src/core/**"
    - "docs/architecture.md"
  cold:
    - "**/*.md"
```

---

## Optional: Enable Sentinel (Post-Deploy Monitoring)

Sentinel closes the loop between deployment and incident response. When a production alert fires, an investigation agent correlates it with recent deployments and produces root cause analysis.

### 1. Copy the Sentinel workflow

```bash
cp templates/workflows/harness-sentinel.yml .github/workflows/
```

### 2. Add monitoring secrets

Add these GitHub Secrets for your observability tools:

| Secret | Purpose |
|--------|---------|
| `DATADOG_API_KEY` | Query Datadog traces and metrics |
| `DATADOG_APP_KEY` | Datadog application key |
| `JIRA_BASE_URL` | Jira instance URL (for ticket context) |
| `JIRA_EMAIL` | Jira account email |
| `JIRA_API_TOKEN` | Jira API token |

### 3. Configure your alerting tool

Set up your Slack bot or monitoring tool (Datadog, Grafana, PagerDuty) to send a `repository_dispatch` event when an alert fires:

```bash
curl -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/OWNER/REPO/dispatches" \
  -d '{
    "event_type": "alert-triggered",
    "client_payload": {
      "alert_message": "500 errors spiking on auth-service",
      "service": "auth-service",
      "severity": "critical"
    }
  }'
```

### 4. Test with a manual trigger

Go to **Actions > Agentic Harness -- Sentinel > Run workflow** and fill in a test alert message.

The investigation agent will analyze recent PRs, check for DB migrations, and produce a structured recommendation. If it determines a code fix is needed, it creates a GitHub issue with the `auto` label, which triggers the standard harness pipeline.

---

## Next Steps

- Read the [Configuration Reference](configuration.md) for all available options.
- Explore [Context Engineering](context-engineering.md) to optimize what the agent sees.
- Review [Agent Providers](agent-providers.md) to understand provider options.
