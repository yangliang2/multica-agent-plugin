#!/usr/bin/env bash
echo "⚠️  install.sh is deprecated. Use: npx multica-agent-plugin"
echo "   Or: node bin/install.js"
echo "   Continuing with legacy install..."
# Install multica-agent-plugin into Claude Code.
#
# Steps:
#   1. Verify multica CLI is present
#   2. Merge hooks.json into ~/.claude/settings.json (or $CLAUDE_SETTINGS_PATH)
#   3. Print MULTICA_PLUGIN_ROOT export reminder
#   4. Print success message
#
# Usage:
#   MULTICA_PLUGIN_ROOT=/path/to/plugin bash install.sh
#   CLAUDE_SETTINGS_PATH=/custom/settings.json bash install.sh

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_JSON="${PLUGIN_ROOT}/hooks/hooks.json"
SETTINGS_PATH="${CLAUDE_SETTINGS_PATH:-${HOME}/.claude/settings.json}"

# ---------------------------------------------------------------------------
# 1. Check multica CLI
# ---------------------------------------------------------------------------
if ! command -v multica >/dev/null 2>&1; then
  echo "[install] ERROR: multica CLI not found in PATH." >&2
  echo "[install] Install multica first: https://multica.dev/docs/install" >&2
  exit 1
fi
echo "[install] multica found: $(command -v multica)"

# ---------------------------------------------------------------------------
# 2. Merge hooks.json into settings.json
# ---------------------------------------------------------------------------
if [[ ! -f "$HOOKS_JSON" ]]; then
  echo "[install] ERROR: hooks.json not found at ${HOOKS_JSON}" >&2
  exit 1
fi

# Require python3 for JSON merging
if ! command -v python3 >/dev/null 2>&1; then
  echo "[install] ERROR: python3 is required for JSON merging but was not found." >&2
  exit 1
fi

mkdir -p "$(dirname "$SETTINGS_PATH")"

# If settings.json does not exist, start with empty object
if [[ ! -f "$SETTINGS_PATH" ]]; then
  printf '{}' > "$SETTINGS_PATH"
fi

# Substitute MULTICA_PLUGIN_ROOT in hooks.json before merging
hooks_content=$(sed "s|\${MULTICA_PLUGIN_ROOT}|${PLUGIN_ROOT}|g" "$HOOKS_JSON")

# Merge: existing settings win on key conflicts EXCEPT hooks, which we append to
python3 - <<PYEOF
import json, sys

settings_path = "${SETTINGS_PATH}"
hooks_json    = json.loads('''${hooks_content}''')

with open(settings_path, "r") as f:
    settings = json.load(f)

hooks_section = settings.setdefault("hooks", {})

for event, entries in hooks_json.get("hooks", {}).items():
    existing = hooks_section.setdefault(event, [])
    for entry in entries:
        # Avoid duplicate entries (match on command)
        if not any(e.get("command") == entry.get("command") for e in existing):
            existing.append(entry)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print(f"[install] Hooks merged into {settings_path}")
PYEOF

# ---------------------------------------------------------------------------
# 3. MULTICA_PLUGIN_ROOT reminder
# ---------------------------------------------------------------------------
echo ""
echo "[install] Add the following to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
echo ""
echo "  export MULTICA_PLUGIN_ROOT=\"${PLUGIN_ROOT}\""
echo ""

# ---------------------------------------------------------------------------
# 4. Success
# ---------------------------------------------------------------------------
echo "[install] multica-agent-plugin installed successfully."
echo "[install] Restart Claude Code for hooks to take effect."
