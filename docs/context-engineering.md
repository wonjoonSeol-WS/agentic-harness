# Context Engineering

Context engineering is how the harness assembles the right information for the AI agent at each pipeline stage. Good context means the agent understands your codebase conventions, the issue requirements, and the relevant source code -- without bloating the prompt or drowning in irrelevant files.

---

## Multi-Level Context Hierarchy

The harness uses a navigation-based approach designed to scale to large monorepos (10M+ LOC). Instead of loading everything into the prompt, it gives the agent a **map** and lets it navigate deeper using its file-reading tools.

### Level 0 -- Root Context (always in prompt)

Loaded into every prompt automatically:
- **Root `AGENTS.md`** -- project-wide conventions and agent instructions
- **`CLAUDE.md` / `COPILOT.md` / `CODING_GUIDELINES.md`** -- if they exist at project root
- **Project metadata** from `harness.yml` (name, language)
- **Issue body and title**
- **Module pointer list** -- paths to all sub-directory `AGENTS.md` files

### Level 1 -- Module Context (loaded or pointed to)

Each sub-directory can have its own `AGENTS.md` with module-specific conventions. How these are handled depends on the `navigation_mode` setting:

- **`full`** -- Module `AGENTS.md` files are inlined into the prompt (good for small projects with few modules)
- **`navigation`** -- Module `AGENTS.md` files are listed as pointers only; the agent reads them on-demand (required for large monorepos)
- **`auto`** (default) -- Inline if 5 or fewer modules; navigate if more than 5

Example pointer list in the prompt:
```
## Module-level Context (navigate as needed)
The following modules have their own AGENTS.md:
- services/auth/AGENTS.md
- services/payment/AGENTS.md
- core/common/AGENTS.md
```

### Level 2 -- On-Demand (agent reads as needed)

Detailed files like API specs, schema definitions, and implementation docs are never loaded into the prompt. The agent reads them using its file tools when it determines they are relevant to the task.

```
Level 0: AGENTS.md (root)           <- always in prompt
Level 1: services/auth/AGENTS.md    <- inlined or pointed to
Level 2: services/auth/docs/api.md  <- agent reads on demand
```

This keeps the prompt small regardless of codebase size.

---

## Configuration

All context settings live in the `context` section of `harness.yml`:

```yaml
context:
  agents_md: "AGENTS.md"         # Root context file name
  navigation_mode: "auto"        # auto | full | navigation
  max_file_lines: 200            # Max lines per file in prompt
  max_diff_lines: 2000           # Max diff lines before summarizing
```

### `navigation_mode`

| Mode | Behavior | Best for |
|------|----------|----------|
| `auto` | Inline <=5 modules, navigate >5 | Most projects |
| `full` | Inline all module AGENTS.md | Small projects (<5 modules) |
| `navigation` | List pointers only | Large monorepos (10+ modules) |

### `max_file_lines`

Controls how many lines of any single file are inlined into the prompt. Files longer than this limit are truncated with a note telling the agent to read the full file. Default: 200 lines.

### `max_diff_lines`

Controls diff handling in review phases. Diffs larger than this limit are summarized: the first N lines are shown, followed by a full list of changed files. Default: 2000 lines.

---

## Execution Scope

For monorepos, you can restrict the agent to specific paths using `execution.scope`:

```yaml
execution:
  scope:
    - "services/auth/"
    - "core/common/"
```

When scope is set:
1. The prompt includes a "Scope" section listing allowed paths
2. If a scoped module has an `AGENTS.md`, its first 100 lines are inlined
3. The executor and planner prompts instruct the agent to stay within scope

This prevents the agent from wandering into unrelated modules in a large codebase.

---

## Smart Diff Loading

For review phases (functional and NFR), the harness handles large diffs intelligently:

- **Small diffs** (under `max_diff_lines`): included in full inside a code fence
- **Large diffs** (over `max_diff_lines`): first N lines shown, plus a complete file change list

The agent can always use `git diff` to view the full diff for specific files.

---

## AGENTS.md Best Practices

`AGENTS.md` is the highest-impact file for agent quality. A well-written `AGENTS.md` turns a generic AI model into a context-aware contributor.

### Be specific, not generic

```markdown
# Bad
Follow best practices.

# Good
Use named exports, not default exports. Place React components in
src/components/ with a co-located test file named *.test.tsx.
Run `pnpm lint` before committing.
```

### Include build and test commands

```markdown
## Commands
- Build: `./gradlew clean build`
- Test: `./gradlew test`
- Lint: `./gradlew ktlintFormat`
```

### Describe your architecture

```markdown
## Module Structure
- `core/entity/` -- JPA entities
- `core/service/` -- business logic
- `app/api/` -- REST controllers
```

### List explicit prohibitions

```markdown
## Do Not
- Do not use wildcard imports
- Do not modify database migration files that have already been applied
```

### For monorepos: create per-module AGENTS.md

Each module should have its own `AGENTS.md` with:
- Module-specific conventions that differ from the root
- Key file locations within the module
- Module-specific build/test commands
- Dependencies on other modules

Keep the root `AGENTS.md` focused on project-wide conventions and the module map.

### Keep it concise

The root `AGENTS.md` is loaded on every turn. Keep it under 200 lines (configurable via `max_file_lines`). Link to external docs for details instead of inlining them.

---

## Shallow Clones for Large Repos

For large repositories, use shallow clones to speed up checkout:

```yaml
execution:
  checkout_depth: 50    # last 50 commits (default in workflow template)
```

The workflow template uses `fetch-depth: 50` by default. Set to `0` for full history if your workflow needs deep git history.

---

## Stage-Specific Context

The context assembler adjusts what it includes based on the pipeline stage:

| Stage | Included | Agent Navigates |
|-------|----------|-----------------|
| **Planning** | Root AGENTS.md, issue body, module pointers | Module AGENTS.md, source files |
| **Execution** | Root AGENTS.md, approved plan, scope, module pointers | Module AGENTS.md, source files, tests |
| **Review** | Root AGENTS.md, diff (smart-loaded), issue body | Full diff via git, changed files |

---

## Mechanical Enforcement Stack

Context files (AGENTS.md, ARCHITECTURE.md) tell the agent what the rules are. But documentation alone is not reliable -- agents can ignore or misinterpret written rules. The harness provides three layers of mechanical enforcement that work together:

### Layer 1: AGENTS.md + ARCHITECTURE.md (Documentation)

Written rules that the agent reads before writing code. These define conventions, layer architecture, and prohibited patterns. They are the first line of defense and handle the majority of cases.

### Layer 2: Agent-Friendly Lint Errors (Remediation)

When the agent does break a rule, the linter catches it. But raw linter output often lacks enough context for the agent to self-correct correctly. `lint-formatter.sh` wraps linter commands and appends `FIX:` instructions from `.harness/lint-hints.yml`, turning each error into a direct remediation instruction.

The executor prompt is designed to prioritize `FIX:` lines over its own judgment, so the fix instructions you write in `lint-hints.yml` directly control the agent's correction behavior.

### Layer 3: Structural Tests (Architecture Enforcement)

Some rules cannot be expressed as lint rules -- for example, "repository layer must not import from service layer." Structural test scripts (`check-layer-imports.sh`, `check-domain-boundaries.sh`) validate these architecture rules mechanically by scanning imports against a layer/domain configuration file.

These run as regular `post_commands` and produce violation messages with `FIX:` hints, integrating with the same remediation pattern.

### How They Work Together

```
Agent reads AGENTS.md           -> knows the rules (Layer 1)
Agent writes code               -> may break a rule
post_commands run linter         -> lint-formatter.sh adds FIX hint (Layer 2)
post_commands run structural tests -> check-layer-imports.sh flags violation (Layer 3)
Agent reads FIX hints            -> self-corrects precisely
```

This creates a feedback loop where conventions are documented, enforced mechanically, and corrected with precise instructions -- all without human intervention.

---

## Debugging Context Issues

If the agent ignores your conventions or misunderstands the task:

1. **Check AGENTS.md** -- is the convention documented? If not, add it.
2. **Check navigation_mode** -- if the agent should be reading module-level context, make sure module `AGENTS.md` files exist.
3. **Check scope** -- for monorepos, ensure `execution.scope` restricts the agent to the right directories.
4. **Check file sizes** -- if your root `AGENTS.md` is over 200 lines, the excess is truncated. Move module-specific content to per-module `AGENTS.md` files.
5. **Check diff size** -- if review comments miss issues, your diff may have been truncated. Check `max_diff_lines` or split the change into smaller PRs.
