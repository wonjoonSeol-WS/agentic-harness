#!/usr/bin/env bash
# =============================================================================
# jira-helpers.sh — Lightweight Jira access for agents via REST API.
#
# Provides bash functions the agent can call to read Jira tickets dynamically.
# Uses API token auth (no daily re-authentication, works in CI).
#
# Auth env vars (set as GitHub Secrets):
#   JIRA_BASE_URL   — e.g., https://your-org.atlassian.net
#   JIRA_AUTH_TYPE   — "cloud" (email+token) or "datacenter" (PAT). Default: cloud
#   JIRA_EMAIL       — Jira account email (cloud only)
#   JIRA_API_TOKEN   — API token (cloud) or personal access token (datacenter)
#
# Usage: source this file, then call jira-read, jira-search, jira-comments
# =============================================================================

_jira_configured() {
  [[ -n "${JIRA_BASE_URL:-}" && -n "${JIRA_API_TOKEN:-}" ]]
}

_jira_curl() {
  local endpoint="$1"
  local url="${JIRA_BASE_URL}/rest/api/3/${endpoint}"
  local auth_type="${JIRA_AUTH_TYPE:-cloud}"

  if [[ "$auth_type" == "datacenter" ]]; then
    # Jira Server/Data Center: personal access token
    curl -sf -H "Authorization: Bearer ${JIRA_API_TOKEN}" \
      -H "Content-Type: application/json" "$url"
  else
    # Jira Cloud: email + API token (basic auth)
    curl -sf -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
      -H "Content-Type: application/json" "$url"
  fi
}

# Read a Jira ticket — returns summary, description, status, priority, linked issues
jira-read() {
  local key="$1"
  if ! _jira_configured; then
    echo "[jira] Not configured. Set JIRA_BASE_URL + JIRA_API_TOKEN as env vars."
    return 1
  fi

  local response
  response="$(_jira_curl "issue/${key}?fields=summary,description,status,priority,issuelinks,comment&expand=renderedFields")" || {
    echo "[jira] Failed to fetch ${key}"
    return 1
  }

  # Output human-readable summary
  echo "$response" | jq -r '
    "## " + .key + ": " + .fields.summary,
    "",
    "**Status**: " + .fields.status.name,
    "**Priority**: " + (.fields.priority.name // "None"),
    "",
    "### Description",
    (.renderedFields.description // .fields.description // "(no description)"),
    "",
    if (.fields.issuelinks | length) > 0 then
      "### Linked Issues",
      (.fields.issuelinks[] |
        "- " + .type.outward + ": " +
        ((.outwardIssue // .inwardIssue) | .key + " — " + .fields.summary + " [" + .fields.status.name + "]")
      )
    else empty end
  ' 2>/dev/null || echo "$response" | jq '.'
}

# Search Jira with JQL — returns key, summary, status for each match
jira-search() {
  local jql="$1"
  local max="${2:-10}"
  if ! _jira_configured; then
    echo "[jira] Not configured."
    return 1
  fi

  local encoded_jql
  encoded_jql="$(printf '%s' "$jql" | python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read()))")"

  local response
  response="$(_jira_curl "search?jql=${encoded_jql}&maxResults=${max}&fields=summary,status,priority")" || {
    echo "[jira] Search failed"
    return 1
  }

  echo "$response" | jq -r '
    "Found " + (.total | tostring) + " issues:",
    "",
    (.issues[] |
      "- **" + .key + "**: " + .fields.summary + " [" + .fields.status.name + "]"
    )
  '
}

# Read comments on a Jira ticket
jira-comments() {
  local key="$1"
  local max="${2:-5}"
  if ! _jira_configured; then
    echo "[jira] Not configured."
    return 1
  fi

  local response
  response="$(_jira_curl "issue/${key}/comment?maxResults=${max}&orderBy=-created")" || {
    echo "[jira] Failed to fetch comments for ${key}"
    return 1
  }

  echo "$response" | jq -r '
    (.comments[] |
      "---",
      "**" + .author.displayName + "** (" + .created[:10] + "):",
      .body
    )
  '
}

# Read a Confluence page by ID (useful when Jira tickets link to wiki pages)
confluence-read() {
  local page_id="$1"
  if ! _jira_configured; then
    echo "[confluence] Not configured."
    return 1
  fi

  local url="${JIRA_BASE_URL}/wiki/api/v2/pages/${page_id}?body-format=storage"
  local auth_type="${JIRA_AUTH_TYPE:-cloud}"
  local response

  if [[ "$auth_type" == "datacenter" ]]; then
    response="$(curl -sf -H "Authorization: Bearer ${JIRA_API_TOKEN}" "$url")"
  else
    response="$(curl -sf -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" "$url")"
  fi

  echo "$response" | jq -r '
    "## " + .title,
    "",
    .body.storage.value
  ' 2>/dev/null || echo "$response" | jq '.'
}
