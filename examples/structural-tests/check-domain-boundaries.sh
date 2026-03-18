#!/usr/bin/env bash
set -euo pipefail

# check-domain-boundaries.sh -- Validates cross-domain import rules.
#
# Reads domain definitions from .harness/domains.yml and checks that
# files in one domain only import from another domain's public API path.
# Internal files (not in public_api) must not be imported cross-domain.
#
# Usage: check-domain-boundaries.sh [--config <domains-file>]
#
# Default config path: .harness/domains.yml
#
# Example domains.yml:
#   domains:
#     auth:
#       path: "services/auth/"
#       public_api: "services/auth/api/"
#     payment:
#       path: "services/payment/"
#       public_api: "services/payment/api/"
#     common:
#       path: "core/common/"
#       public_api: "core/common/"
#
# Add to post_commands in harness.yml:
#   - "check-domain-boundaries.sh --config .harness/domains.yml"

CONFIG_FILE=".harness/domains.yml"
VIOLATIONS=0

# --- Parse arguments --------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: check-domain-boundaries.sh [--config <domains-file>]" >&2
      exit 1
      ;;
  esac
done

# --- Validate dependencies ---------------------------------------------------

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Config file not found: $CONFIG_FILE" >&2
  echo "Create it using examples/structural-tests/domains.yml.example as a template." >&2
  exit 1
fi

if ! command -v yq &>/dev/null; then
  echo "ERROR: yq is required but not found. Install: https://github.com/mikefarah/yq" >&2
  exit 1
fi

# --- Read domain definitions -------------------------------------------------

DOMAIN_NAMES=$(yq '.domains | keys | .[]' "$CONFIG_FILE" 2>/dev/null || true)

if [[ -z "$DOMAIN_NAMES" ]]; then
  echo "No domains defined in $CONFIG_FILE"
  exit 0
fi

declare -A DOMAIN_PATHS
declare -A DOMAIN_PUBLIC

for name in $DOMAIN_NAMES; do
  DOMAIN_PATHS["$name"]=$(yq ".domains.\"$name\".path" "$CONFIG_FILE")
  DOMAIN_PUBLIC["$name"]=$(yq ".domains.\"$name\".public_api" "$CONFIG_FILE")
done

# --- Check cross-domain imports ----------------------------------------------

echo "Checking domain boundary rules from $CONFIG_FILE ..."
echo ""

for source_domain in $DOMAIN_NAMES; do
  source_path="${DOMAIN_PATHS[$source_domain]}"

  # Find all source files in this domain
  files=$(find "./$source_path" \( -name "*.kt" -o -name "*.java" -o -name "*.ts" -o -name "*.tsx" -o -name "*.py" \) 2>/dev/null || true)

  for file in $files; do
    for target_domain in $DOMAIN_NAMES; do
      if [[ "$target_domain" == "$source_domain" ]]; then
        continue
      fi

      target_path="${DOMAIN_PATHS[$target_domain]}"
      public_path="${DOMAIN_PUBLIC[$target_domain]}"

      # Find imports that reference the target domain's path but NOT its public API
      while IFS= read -r import_line; do
        if [[ -z "$import_line" ]]; then
          continue
        fi

        # Check if the import references the target domain
        if ! echo "$import_line" | grep -q "$target_path"; then
          continue
        fi

        # Check if it references the public API path (allowed)
        if echo "$import_line" | grep -q "$public_path"; then
          continue
        fi

        # This is a violation: importing internal files cross-domain
        line_num=$(echo "$import_line" | cut -d: -f1)
        line_content=$(echo "$import_line" | cut -d: -f2-)
        echo "VIOLATION: $file imports internal code from \"$target_domain\" domain"
        echo "  Line $line_num:$line_content"
        echo "  Rule: Cross-domain imports must use the public API: $public_path"
        echo "  FIX: Import from $public_path instead, or move the type to the public API."
        echo ""
        VIOLATIONS=$((VIOLATIONS + 1))
      done < <(grep -n "import\|from " "$file" 2>/dev/null || true)
    done
  done
done

# --- Report -------------------------------------------------------------------

if [[ "$VIOLATIONS" -gt 0 ]]; then
  echo "Found $VIOLATIONS domain boundary violation(s)."
  echo "Fix these violations to maintain clean domain separation."
  exit 1
else
  echo "All domain boundary rules pass."
  exit 0
fi
