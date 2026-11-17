#!/bin/zsh
echo "[$(date '+%Y-%m-%d %H:%M:%S')] CoreAudio device change detected"
exec "$HOME/.config/camilladsp/eq-ctl.sh" auto
