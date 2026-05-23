#!/usr/bin/env bash
# Remove multica-agent-plugin hooks from Claude Code settings.
#
# Steps:
#   1. Locate settings.json (default: ~/.claude/settings.json)
#   2. Remove entries whose command path contains MULTICA_PLUGIN_ROOT or the
#      resolved plugin directory
#   3. Print success message
#
# Usage:
#   MULTICA_PLUGIN_ROOT=/path/to/plugin bash uninstall.sh
#   CLAUDE_SETTINGS_PATH=/custom/settings.json bash uninstall.sh

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_PATH="${CLAUDE_SETTINGS_PATH:-${HOME}/.claude/settings.json}"

if [[ ! -f "$SETTINGS_PATH" ]]; then
  echo "[uninstall] No settings.json found at ${SETTINGS_PATH}. Nothing to remove."
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[uninstall] ERROR: python3 is required but was not found." >&2
  exit 1
fi

python3 - <<PYEOF
import json, sys

settings_path = "${SETTINGS_PATH}"
plugin_root   = "${PLUGIN_ROOT}"

with open(settings_path, "r") as f:
    settings = json.load(f)

hooks_section = settings.get("hooks", {})
removed = 0

for event in list(hooks_section.keys()):
    original = hooks_section[event]
    filtered = [
        e for e in original
        if plugin_root not in e.get("command", "")
        and "\${MULTICA_PLUGIN_ROOT}" not in e.get("command", "")
    ]
    removed += len(original) - len(filtered)
    if filtered:
        hooks_section[event] = filtered
    else:
        del hooks_section[event]

if not hooks_section:
    settings.pop("hooks", None)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print(f"[uninstall] Removed {removed} hook(s) from {settings_path}")
PYEOF

echo "[uninstall] multica-agent-plugin hooks removed."
echo "[uninstall] Restart Claude Code for changes to take effect."
