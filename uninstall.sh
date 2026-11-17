#!/bin/zsh
set -euo pipefail

UID_NUM="$(id -u)"
CFG_DIR="$HOME/.config/camilladsp"
LAUNCH_DIR="$HOME/Library/LaunchAgents"

if [[ -x "$CFG_DIR/eq-ctl.sh" ]]; then
  "$CFG_DIR/eq-ctl.sh" raw || true
fi

launchctl bootout "gui/$UID_NUM/com.user.camilladsp-autoswitch" >/dev/null 2>&1 || true
launchctl bootout "gui/$UID_NUM/com.user.camilladsp" >/dev/null 2>&1 || true
pkill -x camilladsp-watcher >/dev/null 2>&1 || true
pkill -x camilladsp >/dev/null 2>&1 || true

rm -f "$LAUNCH_DIR/com.user.camilladsp.plist" "$LAUNCH_DIR/com.user.camilladsp-autoswitch.plist"
echo "Stopped CamillaDSP + Auto-Watcher and removed LaunchAgents."
echo "(Config files remain in $CFG_DIR; delete manually if no longer needed.)"
