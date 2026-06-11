#!/usr/bin/env bash
# run-verification.sh — program-enforced verification runner (REQ-07-01/02/03)
#
# Runs the verification command, hashes the output, categorizes failures, and
# detects flaky-suspect runs (same output_hash, different exit codes across
# attempts). Prints a ready-to-post [verification] comment body to stdout.
#
# Usage: run-verification.sh <issue_id> [command]
#   command precedence: argument > loop.json.verification_cmd > ecosystem default
#
# Exit code: the verification command's exit code (0 = pass).
set -uo pipefail

MULTICA_WORKDIR="${MULTICA_WORKDIR:-$(pwd)}"

issue_id="${1:-}"
if [[ -z "$issue_id" ]]; then
  echo "usage: run-verification.sh <issue_id> [command]" >&2
  exit 64
fi
if ! [[ "$issue_id" =~ ^[A-Za-z0-9._-]{1,64}$ ]]; then
  echo "run-verification.sh: invalid issue_id" >&2
  exit 64
fi

STATE_DIR="${MULTICA_WORKDIR}/.multica/state/${issue_id}"
LOOP_JSON="${STATE_DIR}/loop.json"
ATTEMPTS="${STATE_DIR}/verify-attempts.jsonl"
mkdir -p "$STATE_DIR"

# --- Resolve command: arg > loop.json.verification_cmd > ecosystem default ---
cmd="${2:-}"
if [[ -z "$cmd" && -f "$LOOP_JSON" ]] && command -v python3 >/dev/null 2>&1; then
  cmd=$(python3 -c "
import json, sys
try:
    print(json.load(open(sys.argv[1])).get('verification_cmd', ''))
except Exception:
    print('')
" "$LOOP_JSON" 2>/dev/null || echo "")
fi
if [[ -z "$cmd" ]]; then
  if   [[ -f "${MULTICA_WORKDIR}/package.json" ]]; then cmd="npm test"
  elif [[ -f "${MULTICA_WORKDIR}/pyproject.toml" || -f "${MULTICA_WORKDIR}/pytest.ini" || -f "${MULTICA_WORKDIR}/setup.py" ]]; then cmd="pytest"
  elif [[ -f "${MULTICA_WORKDIR}/Cargo.toml" ]]; then cmd="cargo test"
  elif [[ -f "${MULTICA_WORKDIR}/go.mod" ]]; then cmd="go test ./..."
  fi
fi
if [[ -z "$cmd" ]]; then
  echo "run-verification.sh: no verification command found (no arg, no loop.json.verification_cmd, no known ecosystem)" >&2
  exit 64
fi

# --- Run (fresh, full output captured) ---
output_file=$(mktemp "${STATE_DIR}/verify-output.XXXXXX")
( cd "$MULTICA_WORKDIR" && bash -c "$cmd" ) > "$output_file" 2>&1
exit_code=$?

output_hash=$(sha256sum "$output_file" | cut -c1-8)

# --- Failure categorization (REQ-07-03): specific patterns before generic ---
category=""
if [[ $exit_code -ne 0 ]]; then
  if   grep -qiE 'SyntaxError|syntax error|ParseError|unexpected token' "$output_file"; then category="syntax"
  elif grep -qiE 'ImportError|ModuleNotFoundError|cannot find module|no module named|unresolved import' "$output_file"; then category="import"
  elif grep -qiE 'timed? ?out|TimeoutError|ETIMEDOUT' "$output_file"; then category="timeout"
  elif grep -qiE 'EACCES|permission denied|EPERM' "$output_file"; then category="permission"
  elif grep -qiE 'AssertionError|assertion failed|expected.*(received|but got)|tests? failed|FAIL' "$output_file"; then category="assertion"
  else category="unknown"
  fi
fi

# --- Flaky detection (REQ-07-02): same output_hash, different exit_code ---
flaky_suspect="false"
if [[ -f "$ATTEMPTS" ]] && command -v python3 >/dev/null 2>&1; then
  flaky_suspect=$(python3 -c "
import json, sys
h, ec = sys.argv[2], int(sys.argv[3])
flaky = 'false'
try:
    for line in open(sys.argv[1]):
        line = line.strip()
        if not line:
            continue
        try:
            a = json.loads(line)
        except Exception:
            continue
        if a.get('output_hash') == h and int(a.get('exit_code', -1)) != ec:
            flaky = 'true'
            break
except FileNotFoundError:
    pass
print(flaky)
" "$ATTEMPTS" "$output_hash" "$exit_code" 2>/dev/null || echo "false")
fi

# --- Append attempt record ---
_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if command -v python3 >/dev/null 2>&1; then
  python3 -c "
import json, sys
rec = {'ts': sys.argv[2], 'exit_code': int(sys.argv[3]), 'output_hash': sys.argv[4],
       'category': sys.argv[5], 'command': sys.argv[6], 'flaky_suspect': sys.argv[7] == 'true'}
with open(sys.argv[1], 'a') as f:
    f.write(json.dumps(rec) + '\n')
" "$ATTEMPTS" "$_ts" "$exit_code" "$output_hash" "$category" "$cmd" "$flaky_suspect" 2>/dev/null || true
fi

# --- Emit ready-to-post [verification] comment body ---
_line="[verification] exit_code=${exit_code} command=\"${cmd}\" output_hash=${output_hash}"
[[ -n "$category" ]] && _line="${_line} category=${category}"
[[ "$flaky_suspect" == "true" ]] && _line="${_line} flaky_suspect=true"
echo "$_line"
tail -10 "$output_file"

rm -f "$output_file"
exit "$exit_code"
