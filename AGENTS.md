# AGENTS.md — agentic-harness

## Overview
Open-source framework that orchestrates AI coding agents from GitHub issue to merged PR.

## Key Files
- `prompts/*.md` — Phase-specific system prompts (planner, executor, reviewer, investigator)
- `templates/workflows/*.yml` — GitHub Actions workflow templates
- `templates/*.template` — Config/doc templates users copy to their projects
- `scripts/*.sh` — Utility scripts (CI gate, lint formatter, Jira helpers)
- `examples/` — Language-specific configs and structural test examples
- `init/setup.sh` — Interactive project bootstrapper

## Conventions
- All shell scripts: `#!/usr/bin/env bash`, `set -euo pipefail`
- Shell scripts must pass `bash -n` syntax check
- Prompts are provider-agnostic markdown
- Workflows use `anthropics/claude-code-action@v1` directly (no abstraction layer)
- Config (`harness.yml`) only contains fields that are actually read by scripts or agents
- No dead config — if nothing reads it, don't add it

## Quality Checks
```bash
bash -n scripts/*.sh
bash -n examples/structural-tests/*.sh
bash -n init/setup.sh
```
