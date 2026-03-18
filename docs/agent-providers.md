# Agent Providers

Workflows use AI agent providers directly via their GitHub Actions — no abstraction layer.

## Supported Providers

| Provider | Action | Default model |
|---|---|---|
| Claude | `anthropics/claude-code-action@v1` | `claude-opus-4-6` |
| OpenAI | `openai/codex-action@v1` | `gpt-4o` |

## Switching Providers

Edit the `uses:` line in your workflow files:

```yaml
# Claude (default in templates)
- uses: anthropics/claude-code-action@v1
  with:
    prompt: "Read prompts/executor.md for instructions..."
    allowed_tools: "Read,Write,Edit,Bash,Grep,Glob"
    model: "claude-opus-4-6"
  env:
    CLAUDE_ACCESS_TOKEN: ${{ secrets.CLAUDE_ACCESS_TOKEN }}

# OpenAI
- uses: openai/codex-action@v1
  with:
    prompt: "Read prompts/executor.md for instructions..."
  env:
    OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
```

## Authentication

Auth is configured as env vars in the workflow, never in `harness.yml`.

### Claude

| Method | Env var | Notes |
|---|---|---|
| OAuth (Max/Pro) | `CLAUDE_ACCESS_TOKEN` | `claude config get oauthToken` |
| API Key | `ANTHROPIC_API_KEY` | console.anthropic.com |
| AWS Bedrock | `CLAUDE_CODE_USE_BEDROCK=1` + AWS creds | No Anthropic key needed |
| GCP Vertex | `CLAUDE_CODE_USE_VERTEX=1` + GCP creds | No Anthropic key needed |

### OpenAI

| Method | Env var |
|---|---|
| API Key | `OPENAI_API_KEY` |

## Prompt Templates

Prompts are provider-agnostic markdown in `prompts/`. The agent reads them via file tools:

| Phase | File |
|---|---|
| plan | `prompts/planner.md` |
| execute | `prompts/executor.md` |
| review-functional | `prompts/reviewer-functional.md` |
| review-nonfunctional | `prompts/reviewer-nonfunctional.md` |
| investigate | `prompts/incident-investigator.md` |
