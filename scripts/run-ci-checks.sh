#!/usr/bin/env bash
set -euo pipefail

# run-ci-checks.sh — Runs post_commands as CI gate. NOT called by the agent.
# The agent runs these commands itself via its agentic loop.
# This script runs them AGAIN in CI as the final safety net.
#
# Usage: run-ci-checks.sh [--config <path>]

PROJECT_ROOT="${GITHUB_WORKSPACE:-.}"

# -- Logging ----------------------------------------------------------------

log_info()  { echo "[ci-check:info]  $*"; }
log_error() { echo "[ci-check:error] $*" >&2; }

# -- Main -------------------------------------------------------------------

main() {
  local config_file="harness.yml"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config) config_file="${2:-harness.yml}"; shift 2 ;;
      *)        shift ;;
    esac
  done

  # Resolve config path
  if [[ ! "$config_file" = /* ]]; then
    config_file="${PROJECT_ROOT}/${config_file}"
  fi

  if [[ ! -f "$config_file" ]]; then
    log_error "Config file not found: ${config_file}"
    exit 1
  fi

  local commands
  commands="$(yq -r '.execution.post_commands[]? // empty' "$config_file" 2>/dev/null || echo "")"

  if [[ -z "$commands" ]]; then
    log_info "No post_commands configured, nothing to check"
    exit 0
  fi

  local failed=0
  local total=0
  local passed=0

  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    total=$((total + 1))
    log_info "Running: ${cmd}"

    if eval "$cmd"; then
      passed=$((passed + 1))
      log_info "PASSED: ${cmd}"
    else
      failed=1
      log_error "FAILED: ${cmd}"
    fi
  done <<< "$commands"

  log_info "Results: ${passed}/${total} commands passed"

  if [[ $failed -ne 0 ]]; then
    log_error "CI gate FAILED — one or more post_commands did not pass"
    exit 1
  fi

  log_info "CI gate PASSED"
}

main "$@"
