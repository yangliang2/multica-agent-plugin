#!/usr/bin/env bash
# Remove multica-agent-plugin hooks from Claude Code settings.
#
# Prefers the npm installer's --uninstall flag (handles both hook removal and
# settings.json cleanup correctly). Falls back to direct python3 path if Node
# is unavailable.
#
# Usage:
#   bash uninstall.sh
#   CLAUDE_SETTINGS_PATH=/custom/settings.json bash uninstall.sh

set -euo pipefail

SETTINGS_PATH="${CLAUDE_SETTINGS_PATH:-${HOME}/.claude/settings.json}"
HOOKS_TARGET="${HOME}/.claude/hooks/multica"

# Prefer npm installer's --uninstall (installed hook path is always HOOKS_TARGET)
if command -v node >/dev/null 2>&1; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "${SCRIPT_DIR}/bin/install.js" ]]; then
    node "${SCRIPT_DIR}/bin/install.js" --uninstall
    exit $?
  fi
fi

# Fallback: direct python3 removal (matches npm-installed hook paths)
if ! command -v python3 >/dev/null 2>&1; then
  echo "[uninstall] ERROR: python3 and node are both unavailable." >&2
  echo "  Install Node.js >= 16 and run: npx multica-agent-plugin --uninstall" >&2
  exit 1
fi

if [[ ! -f "$SETTINGS_PATH" ]]; then
  echo "[uninstall] No settings.json found at ${SETTINGS_PATH}. Nothing to remove."
  exit 0
fi

python3 - "$SETTINGS_PATH" "$HOOKS_TARGET" <<'PYEOF'
import json, sys, os
from pathlib import Path

settings_path = sys.argv[1]
hooks_target  = sys.argv[2]

with open(settings_path, "r") as f:
    settings = json.load(f)

hooks_section = settings.get("hooks", {})
removed = 0

for event in list(hooks_section.keys()):
    original = hooks_section[event]
    filtered = []
    for e in original:
        cmd = e.get("command", "")
        # Match hooks installed by npm installer (path starts with HOOKS_TARGET)
        if cmd.startswith(hooks_target + os.sep) or cmd.startswith(hooks_target + "/"):
            removed += 1
        else:
            filtered.append(e)
    if filtered:
        hooks_section[event] = filtered
    else:
        del hooks_section[event]

if not hooks_section:
    settings.pop("hooks", None)

# Atomic write
import tempfile
tmp = settings_path + ".tmp." + str(os.getpid())
with open(tmp, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
os.replace(tmp, settings_path)

print(f"[uninstall] Removed {removed} hook(s) from {settings_path}")
PYEOF

# Remove hook files
if [[ -d "$HOOKS_TARGET" ]]; then
  rm -rf "$HOOKS_TARGET"
  echo "[uninstall] Removed ${HOOKS_TARGET}"
fi

echo "[uninstall] multica-agent-plugin hooks removed."
echo "[uninstall] Restart Claude Code for changes to take effect."
