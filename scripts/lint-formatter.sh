#!/usr/bin/env bash
set -euo pipefail

# lint-formatter.sh -- Wraps linter output with agent-friendly fix instructions.
#
# Usage: lint-formatter.sh <command> [--hints <hints-file>]
#
# Runs the linter command, captures output, and appends fix hints
# from .harness/lint-hints.yml for each matched rule.
#
# Example:
#   lint-formatter.sh "./gradlew ktlintCheck" --hints .harness/lint-hints.yml
#
# This makes linter errors actionable for AI agents:
#   BEFORE: "Wildcard import (no-wildcard-imports)"
#   AFTER:  "Wildcard import (no-wildcard-imports)
#            FIX: Replace `import foo.*` with explicit imports for each used class.
#            See: AGENTS.md#imports"

HINTS_FILE=".harness/lint-hints.yml"
COMMAND=""

# --- Parse arguments --------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hints)
      HINTS_FILE="$2"
      shift 2
      ;;
    *)
      if [[ -z "$COMMAND" ]]; then
        COMMAND="$1"
      else
        COMMAND="$COMMAND $1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$COMMAND" ]]; then
  echo "Usage: lint-formatter.sh <command> [--hints <hints-file>]" >&2
  exit 1
fi

# --- Run the linter command --------------------------------------------------

OUTPUT_FILE=$(mktemp)
trap 'rm -f "$OUTPUT_FILE"' EXIT

EXIT_CODE=0
eval "$COMMAND" > "$OUTPUT_FILE" 2>&1 || EXIT_CODE=$?

# If the command succeeded, just output and exit
if [[ "$EXIT_CODE" -eq 0 ]]; then
  cat "$OUTPUT_FILE"
  exit 0
fi

# --- Check for hints file ----------------------------------------------------

if [[ ! -f "$HINTS_FILE" ]]; then
  echo "--- Linter failed (exit code $EXIT_CODE) ---"
  cat "$OUTPUT_FILE"
  echo ""
  echo "TIP: Create $HINTS_FILE to get agent-friendly fix hints."
  echo "     See templates/lint-hints.yml.template for examples."
  exit "$EXIT_CODE"
fi

# --- Check for yq ------------------------------------------------------------

if ! command -v yq &>/dev/null; then
  echo "--- Linter failed (exit code $EXIT_CODE) ---"
  cat "$OUTPUT_FILE"
  echo ""
  echo "WARNING: yq not found. Install yq to enable agent-friendly fix hints."
  exit "$EXIT_CODE"
fi

# --- Read all rules ONCE into arrays (avoid O(N*M) yq spawns) ----------------

DEFAULT_FIX_CMD=$(yq -r '.default_fix_command // ""' "$HINTS_FILE")
DEFAULT_FIX=$(yq -r '.rules._default.fix // ""' "$HINTS_FILE")

declare -a RULE_PATTERNS RULE_FIXES RULE_REFS
i=0
while IFS=$'\t' read -r name pattern fix ref; do
  [[ "$name" == "_default" || -z "$pattern" ]] && continue
  RULE_PATTERNS[$i]="$pattern"
  RULE_FIXES[$i]="$fix"
  RULE_REFS[$i]="$ref"
  i=$((i + 1))
done < <(yq -r '.rules | to_entries[] | [.key, .value.pattern // "", .value.fix // "", .value.ref // ""] | @tsv' "$HINTS_FILE" 2>/dev/null)

# --- Process output, append fix hints (no yq calls in the loop) -------------

echo "--- Linter failed (exit code $EXIT_CODE) -- Enhanced output with fix hints ---"
echo ""

while IFS= read -r line; do
  echo "$line"
  matched=false
  for ((j=0; j<${#RULE_PATTERNS[@]}; j++)); do
    if echo "$line" | grep -qEi "${RULE_PATTERNS[$j]}"; then
      [[ -n "${RULE_FIXES[$j]}" ]] && echo "  FIX: ${RULE_FIXES[$j]}"
      [[ -n "${RULE_REFS[$j]}" ]] && echo "  See: ${RULE_REFS[$j]}"
      matched=true
      break
    fi
  done
  if [[ "$matched" == "false" ]] && echo "$line" | grep -qEi "(error|warning|violation)"; then
    if [[ -n "$DEFAULT_FIX" ]]; then
      echo "  FIX: ${DEFAULT_FIX//\{default_fix_command\}/$DEFAULT_FIX_CMD}"
    fi
  fi
done < "$OUTPUT_FILE"

exit "$EXIT_CODE"
