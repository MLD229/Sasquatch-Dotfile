#!/bin/bash
# lock-media.sh — now playing pour hyprlock (pollé via cmd[update:2000])
# Sortie : "♫ titre — artiste" si quelque chose joue, sinon vide → label invisible.
set -u

out=$(curl -s -m 1 http://127.0.0.1:8765/api/music/status 2>/dev/null) || exit 0
[ -z "$out" ] && exit 0

playing=$(printf '%s' "$out" | jq -r '.playing // false' 2>/dev/null)
[ "$playing" = "true" ] || exit 0

title=$(printf '%s' "$out" | jq -r '.title // empty' 2>/dev/null)
[ -n "$title" ] || exit 0

artist=$(printf '%s' "$out" | jq -r '.artist // empty' 2>/dev/null)
if [ -n "$artist" ]; then
    printf '♫ %s — %s\n' "$title" "$artist"
else
    printf '♫ %s\n' "$title"
fi
