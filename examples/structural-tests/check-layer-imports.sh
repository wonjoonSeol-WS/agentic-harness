#!/usr/bin/env bash
set -euo pipefail

# check-layer-imports.sh -- Validates that imports respect layer architecture.
#
# Reads layer ordering from .harness/layers.yml and checks that each source
# file only imports from layers listed in its can_import list.
#
# Usage: check-layer-imports.sh [--config <layers-file>]
#
# Default config path: .harness/layers.yml
#
# Example layers.yml:
#   layers:
#     - name: entity
#       path: "core/entity/**"
#       can_import: []
#     - name: repository
#       path: "core/repository/**"
#       can_import: [entity]
#     - name: service
#       path: "core/service/**"
#       can_import: [entity, repository]
#     - name: api
#       path: "app/api/**"
#       can_import: [entity, service]
#
# Add to post_commands in harness.yml:
#   - "check-layer-imports.sh --config .harness/layers.yml"

CONFIG_FILE=".harness/layers.yml"
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
      echo "Usage: check-layer-imports.sh [--config <layers-file>]" >&2
      exit 1
      ;;
  esac
done

# --- Validate dependencies ---------------------------------------------------

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Config file not found: $CONFIG_FILE" >&2
  echo "Create it using examples/structural-tests/layers.yml.example as a template." >&2
  exit 1
fi

if ! command -v yq &>/dev/null; then
  echo "ERROR: yq is required but not found. Install: https://github.com/mikefarah/yq" >&2
  exit 1
fi

# --- Read layer count --------------------------------------------------------

LAYER_COUNT=$(yq '.layers | length' "$CONFIG_FILE")

if [[ "$LAYER_COUNT" -eq 0 ]]; then
  echo "No layers defined in $CONFIG_FILE"
  exit 0
fi

# --- Build layer path-to-name map --------------------------------------------

declare -A LAYER_PATHS    # layer_name -> glob path pattern
declare -A LAYER_IMPORTS  # layer_name -> comma-separated allowed imports

for i in $(seq 0 $((LAYER_COUNT - 1))); do
  name=$(yq ".layers[$i].name" "$CONFIG_FILE")
  path=$(yq ".layers[$i].path" "$CONFIG_FILE")
  can_import=$(yq ".layers[$i].can_import | join(\",\")" "$CONFIG_FILE" 2>/dev/null || echo "")

  LAYER_PATHS["$name"]="$path"
  LAYER_IMPORTS["$name"]="$can_import"
done

# --- Detect import statements (language-aware) --------------------------------

extract_imports() {
  local file="$1"
  case "$file" in
    *.kt|*.java)
      grep -n "^import " "$file" 2>/dev/null | sed 's/^//' || true
      ;;
    *.ts|*.tsx|*.js|*.jsx)
      grep -n "from ['\"]" "$file" 2>/dev/null | sed 's/^//' || true
      ;;
    *.py)
      grep -n "^\(import \|from .* import\)" "$file" 2>/dev/null | sed 's/^//' || true
      ;;
  esac
}

# --- Determine which layer a path belongs to ----------------------------------

get_layer_for_path() {
  local filepath="$1"
  for layer_name in "${!LAYER_PATHS[@]}"; do
    local pattern="${LAYER_PATHS[$layer_name]}"
    # Convert glob to a prefix check (strip trailing /**)
    local prefix="${pattern%%/\*\*}"
    if [[ "$filepath" == *"$prefix"* ]]; then
      echo "$layer_name"
      return
    fi
  done
  echo ""
}

# --- Check each layer's files ------------------------------------------------

echo "Checking layer import rules from $CONFIG_FILE ..."
echo ""

for layer_name in "${!LAYER_PATHS[@]}"; do
  pattern="${LAYER_PATHS[$layer_name]}"
  allowed="${LAYER_IMPORTS[$layer_name]}"

  # Find source files matching this layer's path pattern
  files=$(find . -path "./$pattern" \( -name "*.kt" -o -name "*.java" -o -name "*.ts" -o -name "*.tsx" -o -name "*.py" \) 2>/dev/null || true)

  for file in $files; do
    imports=$(extract_imports "$file")
    if [[ -z "$imports" ]]; then
      continue
    fi

    while IFS= read -r import_line; do
      # Check if this import references a forbidden layer
      for other_layer in "${!LAYER_PATHS[@]}"; do
        if [[ "$other_layer" == "$layer_name" ]]; then
          continue
        fi

        # Check if this layer is allowed to import from other_layer
        if echo ",$allowed," | grep -q ",$other_layer,"; then
          continue
        fi

        # Check if the import line references the other layer's path
        other_prefix="${LAYER_PATHS[$other_layer]%%/\*\*}"
        if echo "$import_line" | grep -qi "$other_prefix"; then
          line_num=$(echo "$import_line" | cut -d: -f1)
          line_content=$(echo "$import_line" | cut -d: -f2-)
          echo "VIOLATION: $file imports from \"$other_layer\" layer"
          echo "  Line $line_num:$line_content"
          echo "  Rule: \"$layer_name\" layer can only import from: ${allowed:-<nothing>}"
          echo "  FIX: Move the shared type to a lower layer, or use dependency injection."
          echo ""
          VIOLATIONS=$((VIOLATIONS + 1))
        fi
      done
    done <<< "$imports"
  done
done

# --- Report -------------------------------------------------------------------

if [[ "$VIOLATIONS" -gt 0 ]]; then
  echo "Found $VIOLATIONS layer import violation(s)."
  echo "Fix these violations to maintain clean layer architecture."
  exit 1
else
  echo "All layer import rules pass."
  exit 0
fi
