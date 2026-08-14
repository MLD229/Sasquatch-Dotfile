#!/bin/bash
# media-ctl.sh <toggle|next|prev|stop>
# Contrôle musique depuis le lock (bindl) : CC API (MPRIS + MPD + web unifiés),
# fallback playerctl si le serveur CC est down.
set -u

cmd="${1:-toggle}"
api="http://127.0.0.1:8765/api/music/$cmd"

if curl -s -m 1 http://127.0.0.1:8765/api/stats >/dev/null 2>&1; then
    curl -s -m 2 -X POST "$api" >/dev/null 2>&1
    exit 0
fi

case "$cmd" in
    toggle) playerctl play-pause 2>/dev/null ;;
    next)   playerctl next 2>/dev/null ;;
    prev)   playerctl previous 2>/dev/null ;;
    stop)   playerctl stop 2>/dev/null ;;
esac
exit 0
