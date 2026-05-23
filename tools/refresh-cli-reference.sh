#!/usr/bin/env bash
# refresh-cli-reference.sh
# Re-runs multica --help series, updates docs/cli-reference.md and docs/cli-reference.lock
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT="${REPO_ROOT}/docs/cli-reference.md"
LOCK="${REPO_ROOT}/docs/cli-reference.lock"

if ! command -v multica >/dev/null 2>&1; then
  echo "ERROR: multica not found in PATH" >&2
  exit 1
fi

capture() {
  local heading="$1"
  shift
  echo "## ${heading}"
  echo ""
  echo '```'
  "$@" 2>&1
  echo '```'
  echo ""
}

{
  echo "# Multica CLI Reference"
  echo ""
  echo "> Generated: $(date -u +%Y-%m-%d)"
  echo "> Source: live binary at $(command -v multica)"
  echo ""
  echo "---"
  echo ""

  capture "multica" multica --help
  echo "---"
  echo ""

  capture "multica issue" multica issue --help
  echo "---"
  echo ""

  capture "multica issue get" multica issue get --help
  echo ""
  echo "**Examples:**"
  echo ""
  echo '```bash'
  echo 'multica issue get MUL-123'
  echo 'multica issue get MUL-123 --output json'
  echo '```'
  echo ""
  echo "---"
  echo ""

  capture "multica issue comment" multica issue comment --help
  echo "---"
  echo ""

  capture "multica issue comment add" multica issue comment add --help
  echo ""
  echo "**Examples:**"
  echo ""
  echo '```bash'
  echo '# Simple comment'
  echo 'multica issue comment add MUL-123 --content "Looks good, merging now"'
  echo ''
  echo '# Reply to a specific comment'
  echo 'multica issue comment add MUL-123 --parent <comment-id> --content "Thanks!"'
  echo ''
  echo '# Multi-line from stdin'
  printf '%s\n' 'printf "Line 1\nLine 2" | multica issue comment add MUL-123 --content-stdin'
  echo ''
  echo '# From a file'
  echo 'multica issue comment add MUL-123 --content-file ./report.md'
  echo '```'
  echo ""
  echo "---"
  echo ""

  capture "multica issue status" multica issue status --help
  echo ""
  echo "**Valid statuses:** \`backlog\`, \`todo\`, \`in_progress\`, \`in_review\`, \`done\`, \`blocked\`, \`cancelled\`"
  echo ""
  echo '```bash'
  echo 'multica issue status MUL-123 in_progress'
  echo 'multica issue status MUL-123 done'
  echo '```'
  echo ""

} > "${OUT}"

sha256sum "${OUT}" > "${LOCK}"

echo "Updated: ${OUT}"
echo "Lock:    ${LOCK}"
cat "${LOCK}"
