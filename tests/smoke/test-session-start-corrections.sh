#!/usr/bin/env bash
# test-session-start-corrections.sh — REQ-05-02 repo-correction injection
#
# Covers:
#   1. repo-scoped learning surfaces under "Previous corrections on this repo:"
#   2. files[] paths are included in the correction line
#   3. issue-scoped learning stays in the regular Prior Learnings section
#   4. output remains valid JSON
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${PLUGIN_ROOT}/hooks/session-start.sh"

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL+1)); }

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

mkdir -p "${WORKDIR}/.multica" "${WORKDIR}/src"
echo "x" > "${WORKDIR}/src/a.js"

NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "${WORKDIR}/.multica/learnings.jsonl" <<EOF
{"ts":"${NOW_ISO}","recorded_at":"${NOW_ISO}","scope":"repo","repo":"https://example.com/proj.git","key":"corr-1","insight":"tests need runInBand flag","confidence":9,"files":["src/a.js"]}
{"ts":"${NOW_ISO}","scope":"issue","key":"note-1","insight":"plain issue insight","confidence":8,"files":[]}
EOF

OUT=$(MULTICA_AGENT_SESSION=1 MULTICA_WORKDIR="$WORKDIR" bash "$HOOK" 2>/dev/null)

# --- Test 1: corrections section present with repo entry ---
if printf '%s' "$OUT" | grep -qF "Previous corrections on this repo:" \
   && printf '%s' "$OUT" | grep -qF "corr-1"; then
  pass "repo-scoped correction surfaced under 'Previous corrections on this repo:'"
else
  fail "corrections section or corr-1 missing from context output"
fi

# --- Test 2: files note included ---
if printf '%s' "$OUT" | grep -qF "(files: src/a.js)"; then
  pass "correction line includes touched files"
else
  fail "files note '(files: src/a.js)' missing"
fi

# --- Test 3: issue-scoped entry stays in Prior Learnings ---
if printf '%s' "$OUT" | grep -qF "Prior Learnings" \
   && printf '%s' "$OUT" | grep -qF "note-1"; then
  pass "issue-scoped learning remains in Prior Learnings section"
else
  fail "issue-scoped note-1 missing from Prior Learnings"
fi

# --- Test 4: output is valid JSON ---
if printf '%s' "$OUT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "hook output is valid JSON"
else
  fail "hook output is not valid JSON"
fi

echo "  ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
