#!/usr/bin/env bash
# render-anchors.sh
# Replaces <<cli:some.command>> anchors in target files with real command
# examples sourced from docs/cli-reference.md.
#
# Usage:
#   tools/render-anchors.sh <file> [<file> ...]
#   tools/render-anchors.sh --inplace <file> [<file> ...]
#
# Without --inplace, renders to stdout (one file only).
# With --inplace, edits each file in place.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLI_REF="${REPO_ROOT}/docs/cli-reference.md"

if [[ ! -f "${CLI_REF}" ]]; then
  echo "ERROR: ${CLI_REF} not found — run tools/refresh-cli-reference.sh first" >&2
  exit 1
fi

INPLACE=0
if [[ "${1:-}" == "--inplace" ]]; then
  INPLACE=1
  shift
fi

if [[ $# -eq 0 ]]; then
  echo "Usage: $(basename "$0") [--inplace] <file> [<file> ...]" >&2
  exit 1
fi

# Map of anchor -> replacement text
# Each anchor resolves to the canonical one-liner for that command.
declare -A ANCHOR_MAP
ANCHOR_MAP["cli:issue.get"]='multica issue get <id> --output json'
ANCHOR_MAP["cli:issue.comment.add"]='multica issue comment add <issue-id> --content "your message"'
ANCHOR_MAP["cli:issue.comment.list"]='multica issue comment list <issue-id>'
ANCHOR_MAP["cli:issue.status"]='multica issue status <id> <status>'
ANCHOR_MAP["cli:issue.list"]='multica issue list --output json'
ANCHOR_MAP["cli:issue.create"]='multica issue create --title "..." --assignee "AgentName"'
ANCHOR_MAP["cli:issue.assign"]='multica issue assign <id> --to "AgentName"'
ANCHOR_MAP["cli:issue.metadata.set"]='multica issue metadata set <issue-id> --key <key> --value <value>'

render_file() {
  local input="$1"
  local content
  content="$(cat "${input}")"

  for anchor in "${!ANCHOR_MAP[@]}"; do
    local replacement="${ANCHOR_MAP[${anchor}]}"
    # Replace <<anchor>> with the resolved command
    content="${content//<<${anchor}>>/${replacement}}"
  done

  echo "${content}"
}

for file in "$@"; do
  if [[ ! -f "${file}" ]]; then
    echo "ERROR: file not found: ${file}" >&2
    exit 1
  fi

  if [[ "${INPLACE}" -eq 1 ]]; then
    tmp="$(mktemp)"
    render_file "${file}" > "${tmp}"
    mv "${tmp}" "${file}"
    echo "Rendered: ${file}"
  else
    render_file "${file}"
  fi
done
