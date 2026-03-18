#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# setup.sh — Interactive project initializer for Agentic Harness
#
# Usage: ./setup.sh [--non-interactive] [--project-dir <path>]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NON_INTERACTIVE=false
PROJECT_DIR="$(pwd)"

# -- Colors & logging --------------------------------------------------------
if [[ -t 1 ]]; then
    RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
    BLUE='\033[0;34m' CYAN='\033[0;36m' BOLD='\033[1m' DIM='\033[2m' RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' RESET=''
fi
info()   { echo -e "${GREEN}[+]${RESET} $*"; }
warn()   { echo -e "${YELLOW}[!]${RESET} $*"; }
error()  { echo -e "${RED}[x]${RESET} $*" >&2; }
header() { echo -e "\n${BOLD}${CYAN}$*${RESET}"; }
step()   { echo -e "  ${DIM}->${RESET} $*"; }

# -- Argument parsing --------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --non-interactive) NON_INTERACTIVE=true; shift ;;
        --project-dir)     PROJECT_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: setup.sh [--non-interactive] [--project-dir <path>]"
            echo "  --non-interactive   Use defaults without prompting"
            echo "  --project-dir       Target project directory (default: cwd)"
            exit 0 ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
done
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# -- Prompt helpers ----------------------------------------------------------
prompt() {
    local var_name="$1" text="$2" default="$3"
    if $NON_INTERACTIVE; then eval "$var_name=\"$default\""; return; fi
    local input
    read -rp "$(echo -e "${BLUE}?${RESET} ${text} ${DIM}[${default}]${RESET}: ")" input
    eval "$var_name=\"${input:-$default}\""
}
prompt_yn() {
    local var_name="$1" text="$2" default="$3"
    if $NON_INTERACTIVE; then eval "$var_name=\"$default\""; return; fi
    local input
    read -rp "$(echo -e "${BLUE}?${RESET} ${text} ${DIM}(y/n) [${default}]${RESET}: ")" input
    eval "$var_name=\"${input:-$default}\""
}

# -- 1. Prerequisites check --------------------------------------------------
header "Checking prerequisites..."
MISSING=()
for cmd in gh git jq; do
    if command -v "$cmd" > /dev/null 2>&1; then step "$cmd $(command -v "$cmd")"
    else MISSING+=("$cmd"); fi
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    error "Missing required tools: ${MISSING[*]}"
    [[ " ${MISSING[*]} " =~ " gh " ]]  && echo "  gh:  https://cli.github.com/"
    [[ " ${MISSING[*]} " =~ " git " ]] && echo "  git: https://git-scm.com/"
    [[ " ${MISSING[*]} " =~ " jq " ]]  && echo "  jq:  https://jqlang.github.io/jq/"
    exit 1
fi
info "All prerequisites satisfied"

# -- 2. Monorepo detection ---------------------------------------------------
header "Detecting project structure..."
detect_monorepo() {
    local d="$1"
    local module_count=0
    # Check for common monorepo patterns
    for pattern in "services/*/build.gradle*" "packages/*/package.json" "modules/*/pom.xml" \
                   "apps/*/build.gradle*" "*/*/pyproject.toml" "services/*/go.mod"; do
        local matches
        matches="$(find "$d" -maxdepth 3 -path "$d/$pattern" 2>/dev/null | wc -l | tr -d ' ')"
        module_count=$((module_count + matches))
    done

    if [[ $module_count -gt 3 ]]; then
        echo "monorepo"
        info "Detected monorepo with ${module_count} modules" >&2
        info "Consider creating per-module AGENTS.md files for better agent context" >&2
    else
        echo "single"
    fi
}
DETECTED_STRUCTURE="$(detect_monorepo "$PROJECT_DIR")"
if [[ "$DETECTED_STRUCTURE" == "monorepo" ]]; then
    info "Project structure: ${BOLD}monorepo${RESET}"
else
    info "Project structure: ${BOLD}single project${RESET}"
fi

# -- 3. Language detection ----------------------------------------------------
header "Detecting project language..."
detect_language() {
    local d="$1"
    if   [[ -f "$d/build.gradle.kts" ]]; then echo "kotlin"
    elif [[ -f "$d/build.gradle" ]];      then echo "java"
    elif [[ -f "$d/tsconfig.json" ]];     then echo "typescript"
    elif [[ -f "$d/package.json" ]];      then echo "javascript"
    elif [[ -f "$d/pyproject.toml" || -f "$d/setup.py" || -f "$d/requirements.txt" ]]; then echo "python"
    elif [[ -f "$d/go.mod" ]];            then echo "go"
    elif [[ -f "$d/pom.xml" ]];           then echo "java"
    elif [[ -f "$d/Cargo.toml" ]];        then echo "rust"
    else echo "unknown"; fi
}
DETECTED_LANG="$(detect_language "$PROJECT_DIR")"
if [[ "$DETECTED_LANG" == "unknown" ]]; then
    warn "Could not auto-detect project language"
    prompt DETECTED_LANG "Project language (kotlin/typescript/python/java/go)" "typescript"
else
    info "Detected language: ${BOLD}${DETECTED_LANG}${RESET}"
fi

# -- 4. Gather configuration -------------------------------------------------
header "Project configuration"
prompt PROJECT_NAME "Project name" "$(basename "$PROJECT_DIR")"
prompt PROVIDER "AI provider (claude/openai)" "claude"
case "$PROVIDER" in
    claude)  DEFAULT_MODEL="claude-opus-4-6"; DEFAULT_AUTH_SECRET="CLAUDE_ACCESS_TOKEN" ;;
    openai)  DEFAULT_MODEL="gpt-4o"; DEFAULT_AUTH_SECRET="OPENAI_API_KEY" ;;
    *)       DEFAULT_MODEL="claude-opus-4-6"; DEFAULT_AUTH_SECRET="CLAUDE_ACCESS_TOKEN" ;;
esac
prompt MODEL "Model" "$DEFAULT_MODEL"
prompt AUTH_SECRET "GitHub Secret name for auth" "$DEFAULT_AUTH_SECRET"
prompt_yn ENABLE_JIRA "Enable Jira integration?" "n"
prompt_yn ENABLE_SENTINEL "Enable Sentinel (post-deploy alert investigation)?" "n"

# -- 5. Auto-detect common linters and populate post_commands ----------------
detect_commands() {
    case "$1" in
        kotlin)
            PRE_COMMANDS='["./gradlew ktlintFormat"]'
            POST_COMMANDS='["./gradlew compileKotlin", "./gradlew test", "./gradlew ktlintCheck"]' ;;
        java)
            PRE_COMMANDS='["./gradlew spotlessApply"]'
            POST_COMMANDS='["./gradlew compileJava", "./gradlew test"]' ;;
        typescript|javascript)
            PRE_COMMANDS='["pnpm lint --fix"]'
            POST_COMMANDS='["pnpm type-check", "pnpm test", "pnpm build"]' ;;
        python)
            PRE_COMMANDS='["ruff check --fix .", "black ."]'
            POST_COMMANDS='["pytest", "mypy .", "ruff check ."]' ;;
        go)
            PRE_COMMANDS='["gofmt -w ."]'
            POST_COMMANDS='["go build ./...", "go test ./..."]' ;;
        rust)
            PRE_COMMANDS='["cargo fmt"]'
            POST_COMMANDS='["cargo build", "cargo test", "cargo clippy"]' ;;
        *)
            PRE_COMMANDS='[]'
            POST_COMMANDS='[]' ;;
    esac
}
detect_commands "$DETECTED_LANG"
info "Detected post_commands: ${BOLD}${POST_COMMANDS}${RESET}"

# -- 6. Generate harness.yml from template with detected defaults -------------
header "Generating configuration files..."
JIRA_BLOCK=""
if [[ "$ENABLE_JIRA" == "y" ]]; then
    JIRA_BLOCK="
jira:
  enabled: true
  project_key: \"\"      # e.g., PROJ
  base_url: \"\"         # e.g., https://yourorg.atlassian.net"
fi
MONOREPO_BLOCK=""
if [[ "$DETECTED_STRUCTURE" == "monorepo" ]]; then
    MONOREPO_BLOCK="
execution:
  pre_commands: ${PRE_COMMANDS}
  post_commands: ${POST_COMMANDS}
  max_retries: 3
  checkout_depth: 50
  # scope:
  #   - \"services/auth/\"
  #   - \"core/common/\"
context:
  navigation_mode: \"navigation\"
  max_file_lines: 200
  max_diff_lines: 2000"
else
    MONOREPO_BLOCK="
execution:
  pre_commands: ${PRE_COMMANDS}
  post_commands: ${POST_COMMANDS}
  max_retries: 3"
fi

cat > "${PROJECT_DIR}/harness.yml" <<YAML
# Agentic Harness Configuration — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
version: "1"
project:
  name: "${PROJECT_NAME}"
  language: "${DETECTED_LANG}"
agent:
  provider: "${PROVIDER}"
  model: "${MODEL}"
  # Auth is configured in the workflow file, not here.
${MONOREPO_BLOCK}
${JIRA_BLOCK}
YAML
step "Created harness.yml"

# -- 7. Generate AGENTS.md from template -------------------------------------
cat > "${PROJECT_DIR}/AGENTS.md" <<'MD'
# AGENTS.md

Project-specific instructions for AI coding agents. Read automatically
by the Agentic Harness during planning and execution phases.

## Project Overview
<!-- Describe the project's purpose and architecture here -->

## Conventions
<!-- List coding conventions, naming patterns, and style rules -->

## Testing
<!-- Describe the testing strategy, frameworks, and how to run tests -->

## Quality Checks
<!-- Your build/test/lint commands are configured in harness.yml under execution.post_commands -->
MD
step "Created AGENTS.md"

# -- 7b. Generate ARCHITECTURE.md from template --------------------------------
if [[ -f "${HARNESS_ROOT}/templates/ARCHITECTURE.md.template" ]]; then
    cp "${HARNESS_ROOT}/templates/ARCHITECTURE.md.template" "${PROJECT_DIR}/ARCHITECTURE.md"
else
    cat > "${PROJECT_DIR}/ARCHITECTURE.md" <<'MD'
# ARCHITECTURE.md

<!-- Top-level domain map for AI agents. See templates/ARCHITECTURE.md.template for full version. -->

## System Overview
<!-- One paragraph: what the system does, who uses it, key constraints -->

## Domain Map
| Domain | Path | Responsibility | Owner |
|--------|------|---------------|-------|

## Layer Architecture
<!-- Define dependency ordering: Types -> Config -> Repository -> Service -> Runtime -> UI -->
<!-- Layers can only import from layers to their LEFT -->

## Cross-Cutting Concerns
<!-- How auth, logging, telemetry, feature flags are injected -->

## Data Flow
<!-- Key data paths through the system -->

## External Dependencies
| Dependency | Type | Purpose | Docs |
|-----------|------|---------|------|
MD
fi
step "Created ARCHITECTURE.md"

# -- 7c. Create docs/ directory structure ---------------------------------------
mkdir -p "${PROJECT_DIR}/docs/design-docs"
mkdir -p "${PROJECT_DIR}/docs/exec-plans"
mkdir -p "${PROJECT_DIR}/docs/product-specs"
mkdir -p "${PROJECT_DIR}/docs/references"
touch "${PROJECT_DIR}/docs/design-docs/.gitkeep"
touch "${PROJECT_DIR}/docs/exec-plans/.gitkeep"
touch "${PROJECT_DIR}/docs/product-specs/.gitkeep"
touch "${PROJECT_DIR}/docs/references/.gitkeep"
step "Created docs/ directory structure (design-docs, exec-plans, product-specs, references)"

# -- 8. Create .harness/ directory and lessons-learned.jsonl ------------------
mkdir -p "${PROJECT_DIR}/.harness"
touch "${PROJECT_DIR}/.harness/lessons-learned.jsonl"
step "Created .harness/ and lessons-learned.jsonl"

# -- 9. Copy GitHub Actions workflows ----------------------------------------
WORKFLOWS_SRC="${HARNESS_ROOT}/templates/workflows"
WORKFLOWS_DST="${PROJECT_DIR}/.github/workflows"
mkdir -p "$WORKFLOWS_DST"
if [[ -d "$WORKFLOWS_SRC" ]] && [[ -n "$(ls -A "$WORKFLOWS_SRC" 2>/dev/null)" ]]; then
    cp "$WORKFLOWS_SRC"/*.yml "$WORKFLOWS_DST/" 2>/dev/null || true
    step "Copied workflow templates to .github/workflows/"
else
    cat > "$WORKFLOWS_DST/agentic-harness.yml" <<WORKFLOW
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
    if: >
      (github.event_name == 'issues' && contains(github.event.label.name, 'auto')) ||
      (github.event_name == 'issue_comment') ||
      (github.event_name == 'pull_request_review_comment') ||
      (github.event_name == 'pull_request')
    steps:
      - uses: actions/checkout@v4
      - uses: agentic-harness/agentic-harness@v1
        with:
          config_path: harness.yml
          # auth via env var — picks up CLAUDE_ACCESS_TOKEN, ANTHROPIC_API_KEY, etc.
        env:
          ${AUTH_SECRET}: \${{ secrets.${AUTH_SECRET} }}
          github_token: \${{ secrets.GITHUB_TOKEN }}
          event_type: \${{ github.event_name }}
WORKFLOW
    step "Generated .github/workflows/agentic-harness.yml"
fi

# -- 9b. Copy Sentinel workflow if enabled -------------------------------------
if [[ "$ENABLE_SENTINEL" == "y" ]]; then
    if [[ -f "${HARNESS_ROOT}/templates/workflows/harness-sentinel.yml" ]]; then
        cp "${HARNESS_ROOT}/templates/workflows/harness-sentinel.yml" "$WORKFLOWS_DST/"
        step "Copied Sentinel workflow to .github/workflows/"
    else
        warn "Sentinel workflow template not found at ${HARNESS_ROOT}/templates/workflows/harness-sentinel.yml"
    fi
fi

# -- 10. Remind user about GitHub secrets ------------------------------------
header "Setup complete!"
echo ""
info "Files created:"
echo "  harness.yml            Main configuration"
echo "  AGENTS.md              Agent instructions (customize this)"
echo "  ARCHITECTURE.md        Domain map and layer rules (customize this)"
echo "  docs/                  Documentation directory structure"
echo "  .harness/              Harness state directory"
echo "  .github/workflows/     GitHub Actions workflow"
echo ""
warn "Next steps:"
echo "  1. ${BOLD}Edit AGENTS.md${RESET} with your project's conventions and patterns"
echo "  2. ${BOLD}Edit ARCHITECTURE.md${RESET} with your domain map and layer rules"
echo "  3. ${BOLD}Review harness.yml${RESET} and adjust commands for your build system"
echo "  4. ${BOLD}Set the GitHub secret${RESET}: ${DIM}gh secret set ${AUTH_SECRET}${RESET}"
echo "  5. ${BOLD}Add .harness/ to .gitignore${RESET} (optional): ${DIM}echo '.harness/' >> .gitignore${RESET}"
echo ""
[[ "$ENABLE_JIRA" == "y" ]] && warn "Jira enabled — fill in project_key and base_url in harness.yml" && echo ""
[[ "$ENABLE_SENTINEL" == "y" ]] && warn "Sentinel enabled — configure Datadog secrets and Slack webhook. See docs/getting-started.md" && echo ""

# -- 11. Offer to create an initial commit -----------------------------------
prompt_yn CREATE_COMMIT "Create an initial commit with these files?" "n"
if [[ "$CREATE_COMMIT" == "y" ]]; then
    cd "$PROJECT_DIR"
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        error "Not a git repository. Initialize with: git init"; exit 1
    fi
    git add harness.yml AGENTS.md ARCHITECTURE.md .harness/lessons-learned.jsonl .github/workflows/ docs/
    git commit -m "chore: initialize agentic-harness configuration

Add harness.yml, AGENTS.md, ARCHITECTURE.md, docs/ structure, and
GitHub Actions workflows for automated AI-driven issue resolution."
    info "Committed. Push with: git push"
fi
