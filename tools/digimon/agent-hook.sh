#!/bin/sh
# DigiTokenBar agent hook for Claude Code: sh ~/.claude/digitokenbar.sh <working|waiting|done>
# Install: cp tools/digimon/agent-hook.sh ~/.claude/digitokenbar.sh, then add the hooks listed in
# docs/digimon/agent-hooks.md to ~/.claude/settings.json.
# The desktop Digimon shows busy dots while Claude works, asks for you when it waits, and cheers
# when it is done. Each session is labeled with its project folder name (percent-encoded; perl
# ships with macOS). pgrep keeps a hook from relaunching the app after you quit it, and open -g
# keeps the terminal focused.
pgrep -xq DigiTokenBar || exit 0
label=$(printf %s "${CLAUDE_PROJECT_DIR##*/}" | perl -pe 's/([^A-Za-z0-9._~-])/sprintf("%%%02X", ord $1)/ge')
open -g "digitokenbar://agent?state=$1&label=$label" >/dev/null 2>&1
exit 0
