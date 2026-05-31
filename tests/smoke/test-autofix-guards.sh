#!/usr/bin/env bash
# test-autofix-guards.sh — regression tests for auto-fix path guards and workflow contracts

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_contains() {
  local file="$1"
  local needle="$2"
  local msg="$3"
  if grep -Fq -- "$needle" "$file"; then
    pass "$msg"
  else
    fail "$msg"
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  local msg="$3"
  if grep -Fq -- "$needle" "$file"; then
    fail "$msg"
  else
    pass "$msg"
  fi
}

assert_contains "${ROOT_DIR}/.github/scripts/ci-autofix.js" "fs.lstatSync(abs)" "ci-autofix checks lstat before writes"
assert_contains "${ROOT_DIR}/.github/scripts/ci-autofix.js" "fs.realpathSync(abs)" "ci-autofix checks real path before writes"
assert_contains "${ROOT_DIR}/.github/scripts/ci-autofix.js" "process.exit(1)" "ci-autofix exits non-zero on hard failures"
assert_not_contains "${ROOT_DIR}/.github/scripts/ci-autofix.js" "'.github/'" "ci-autofix does not allow workflow/script self-modification"

assert_contains "${ROOT_DIR}/.github/scripts/claude-autofix.js" "fs.lstatSync(abs)" "claude-autofix checks lstat before writes"
assert_contains "${ROOT_DIR}/.github/scripts/claude-autofix.js" "fs.realpathSync(abs)" "claude-autofix checks real path before writes"
assert_not_contains "${ROOT_DIR}/.github/scripts/claude-autofix.js" "'.github/'" "claude-autofix does not allow workflow/script self-modification"

assert_not_contains "${ROOT_DIR}/.github/workflows/auto-fix.yml" "fix_path = '/tmp/claude-fix.json'" "auto-fix workflow no longer has stale patch-apply contract"
assert_not_contains "${ROOT_DIR}/.github/workflows/code-review.yml" "continue-on-error: true" "code review workflow does not suppress review step failures"
assert_contains "${ROOT_DIR}/.github/workflows/code-review.yml" "Claude review failed before producing findings" "code review workflow fails when findings are missing after script failure"
assert_contains "${ROOT_DIR}/.github/workflows/code-review.yml" "Checkout trusted automation" "code review workflow checks out trusted automation separately"
assert_contains "${ROOT_DIR}/.github/workflows/code-review.yml" "node ../trusted/.github/scripts/claude-review.js" "code review runs trusted review script"
assert_contains "${ROOT_DIR}/.github/workflows/code-review.yml" "node ../trusted/.github/scripts/claude-autofix.js" "code review auto-fix runs trusted fix script"
assert_contains "${ROOT_DIR}/.github/workflows/code-review.yml" "persist-credentials: false" "code review PR checkouts do not persist push credentials"
assert_contains "${ROOT_DIR}/.github/workflows/code-review.yml" "statuses: write" "code review workflow can enforce commit statuses"
assert_contains "${ROOT_DIR}/.github/scripts/claude-review.js" 'throw new Error(`Failed to set commit status' "code review fails closed when status updates fail"
assert_contains "${ROOT_DIR}/.github/scripts/claude-review.js" "claudeApiWithRetry" "code review retries transient Claude API failures"
assert_contains "${ROOT_DIR}/.github/scripts/claude-review.js" "Claude review skipped — Claude API unavailable." "code review clears pending status when API retries fail"
assert_contains "${ROOT_DIR}/.github/scripts/claude-review.js" "Claude API permanent failure" "code review fails permanent API failures"
assert_contains "${ROOT_DIR}/.github/workflows/auto-fix.yml" "node ../trusted/.github/scripts/ci-autofix.js" "CI auto-fix runs trusted fix script"
assert_contains "${ROOT_DIR}/.github/workflows/auto-fix.yml" "working-directory: pr" "CI auto-fix mutates only the PR checkout"
assert_contains "${ROOT_DIR}/.github/workflows/auto-fix.yml" "FAILED_LOG_FILE: /tmp/failed-log.txt" "CI auto-fix passes logs by file instead of GITHUB_ENV heredoc"
assert_not_contains "${ROOT_DIR}/.github/workflows/auto-fix.yml" "EOF_MARKER" "CI auto-fix avoids static GITHUB_ENV heredoc delimiters"
assert_contains "${ROOT_DIR}/.github/workflows/auto-fix.yml" "npm test" "CI auto-fix reruns project tests before pushing"
assert_contains "${ROOT_DIR}/.github/scripts/claude-autofix.js" "npm test" "review auto-fix reruns project tests before pushing"
assert_not_contains "${ROOT_DIR}/.github/scripts/claude-autofix.js" "const verifyEnv = { ...process.env }" "review auto-fix builds a minimal verification environment"
assert_contains "${ROOT_DIR}/.github/scripts/claude-autofix.js" "GITHUB_ENV: '/tmp/verify-env-blocked'" "review auto-fix isolates verification from workflow env mutation"
assert_contains "${ROOT_DIR}/.github/scripts/claude-autofix.js" "GITHUB_PATH: '/tmp/verify-path-blocked'" "review auto-fix isolates verification from workflow path mutation"
assert_contains "${ROOT_DIR}/.github/workflows/auto-fix.yml" "GITHUB_ENV: /tmp/verify-env-blocked" "CI auto-fix isolates verification from workflow env mutation"
assert_contains "${ROOT_DIR}/.github/workflows/auto-fix.yml" "GITHUB_PATH: /tmp/verify-path-blocked" "CI auto-fix isolates verification from workflow path mutation"
assert_contains "${ROOT_DIR}/.github/workflows/auto-fix.yml" 'gh pr list -R "$GITHUB_REPOSITORY"' "CI auto-fix passes repository context to gh PR lookup"
assert_contains "${ROOT_DIR}/.github/workflows/auto-fix.yml" 'gh pr comment -R "$GITHUB_REPOSITORY"' "CI auto-fix passes repository context to gh PR comments"
assert_contains "${ROOT_DIR}/.github/workflows/code-review.yml" 'gh pr comment -R "$GITHUB_REPOSITORY"' "review auto-fix passes repository context to gh PR comments"
assert_contains "${ROOT_DIR}/.github/workflows/auto-fix.yml" 'git push origin "HEAD:${PR_BRANCH}"' "CI auto-fix pushes using validated branch env"
assert_contains "${ROOT_DIR}/.github/workflows/code-review.yml" 'git push origin "HEAD:${PR_BRANCH}"' "review auto-fix pushes using validated branch env"
assert_not_contains "${ROOT_DIR}/.github/workflows/auto-fix.yml" 'github.event.workflow_run.head_branch }}"' "CI auto-fix does not interpolate branch expressions into shell quotes"
assert_not_contains "${ROOT_DIR}/.github/workflows/code-review.yml" 'git push origin HEAD:${{ github.event.pull_request.head.ref }}' "review auto-fix does not interpolate branch expressions into shell commands"

# Behavioral guard checks for the path resolver without calling the Claude API.
TMP_REPO="$(mktemp -d)"
trap 'rm -rf "$TMP_REPO"' EXIT
mkdir -p "${TMP_REPO}/hooks" "${TMP_REPO}/tools"
printf 'safe\n' > "${TMP_REPO}/hooks/target.sh"
printf 'outside\n' > "${TMP_REPO}/outside.txt"
ln -s ../outside.txt "${TMP_REPO}/hooks/link.sh"

if (cd "$TMP_REPO" && node - <<'NODE'
const fs = require('fs');
const path = require('path');
const REPO_ROOT = process.cwd();
const REPO_ROOT_REAL = fs.realpathSync(REPO_ROOT);
const ALLOWLIST_PREFIXES = ['hooks/', 'tools/', 'bin/', 'tests/'];
function isAllowedRelPath(rel) {
  return !rel.startsWith('..') && !path.isAbsolute(rel) &&
    ALLOWLIST_PREFIXES.some(prefix => rel.startsWith(prefix));
}
function resolveAllowedRepoPath(relPath) {
  if (typeof relPath !== 'string' || !relPath.trim()) return null;
  const normalized = relPath.replace(/\\/g, '/');
  if (!isAllowedRelPath(normalized)) return null;
  const abs = path.resolve(REPO_ROOT, normalized);
  const rel = path.relative(REPO_ROOT, abs).replace(/\\/g, '/');
  if (!isAllowedRelPath(rel)) return null;
  try {
    const stat = fs.lstatSync(abs);
    if (stat.isSymbolicLink() || !stat.isFile()) return null;
    const real = fs.realpathSync(abs);
    const realStat = fs.statSync(real);
    if (!realStat.isFile()) return null;
    const realRel = path.relative(REPO_ROOT_REAL, real).replace(/\\/g, '/');
    if (!isAllowedRelPath(realRel)) return null;
    if (realRel !== rel) return null;
  } catch {
    return null;
  }
  return { abs, rel };
}
if (!resolveAllowedRepoPath('hooks/target.sh')) process.exit(1);
if (resolveAllowedRepoPath('hooks/link.sh')) process.exit(2);
if (resolveAllowedRepoPath('.github/workflows/auto-fix.yml')) process.exit(3);
if (resolveAllowedRepoPath('../outside.txt')) process.exit(4);
if (resolveAllowedRepoPath('hooks/missing.sh')) process.exit(5);
NODE
); then
  pass "path resolver accepts valid files and rejects symlink/.github/traversal paths"
else
  fail "path resolver accepts valid files and rejects symlink/.github/traversal paths"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
