#!/bin/sh
# Installs the DigiTokenBar Claude Code hooks for the current user. Run it yourself:
#   sh tools/digimon/install-agent-hooks.sh
# Copies agent-hook.sh to ~/.claude/digitokenbar.sh and adds five hooks to ~/.claude/settings.json
# (docs/digimon/agent-hooks.md). A dated backup of the settings is written first. Existing hooks and
# settings are kept, and running it again adds nothing.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
settings="$HOME/.claude/settings.json"
command -v jq >/dev/null 2>&1 || { echo "jq is needed: brew install jq" >&2; exit 1; }
mkdir -p "$HOME/.claude"
cp "$here/agent-hook.sh" "$HOME/.claude/digitokenbar.sh"
[ -f "$settings" ] || echo '{}' > "$settings"
if grep -q 'digitokenbar.sh' "$settings"; then
    echo "Hooks are already installed in $settings"
    exit 0
fi
backup="$settings.before-digitokenbar.$(date +%Y%m%d-%H%M%S)"
cp "$settings" "$backup"
tmp=$(mktemp)
jq '
  def add(event; entry): .hooks[event] = ((.hooks[event] // []) + [entry]);
  def cmd(state): {"type": "command", "command": ("sh ~/.claude/digitokenbar.sh " + state + " || true")};
  .hooks = (.hooks // {})
  | add("UserPromptSubmit"; {"hooks": [cmd("working")]})
  | add("PostToolUse"; {"matcher": "*", "hooks": [cmd("working")]})
  | add("PreToolUse"; {"matcher": "AskUserQuestion", "hooks": [cmd("waiting")]})
  | add("Notification"; {"matcher": "permission_prompt|elicitation_dialog", "hooks": [cmd("waiting")]})
  | add("Stop"; {"hooks": [cmd("done")]})
' "$settings" > "$tmp"
jq -e '.hooks.Stop' "$tmp" >/dev/null
cat "$tmp" > "$settings"
rm -f "$tmp"
echo "Installed the DigiTokenBar hooks in $settings"
echo "Backup: $backup"
