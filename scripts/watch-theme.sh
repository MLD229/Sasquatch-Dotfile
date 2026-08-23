#!/bin/bash
# watch-theme.sh — trace les changements palette/wallpaper pour diagnostiquer le bug hyprlock
# Usage: watch-theme.sh  (log dans ~/.cache/sasquatch-theme-watch.log)
RUNDIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
LOG="$HOME/.cache/sasquatch-theme-watch.log"
: > "$LOG"

snap() {
    echo "=== $(date '+%H:%M:%S.%3N') ===" >> "$LOG"
    echo "config.ini : $(grep -m1 '^wallpaper' "$HOME/.config/waypaper/config.ini" 2>/dev/null)" >> "$LOG"
    echo "LAST       : $(cat "$RUNDIR/sasquatch-theme-last" 2>/dev/null)" >> "$LOG"
    echo "hyprpaper  : $(hyprctl hyprpaper listactive 2>/dev/null | head -2 | tr '\n' ' ')" >> "$LOG"
    echo "hyprlock   : $(stat -c '%y' "$HOME/.config/hypr/hyprlock.conf" 2>/dev/null | cut -d. -f1)" >> "$LOG"
    echo "palette    : $(grep -m1 '@define-color color4' "$HOME/.config/waybar/style.css" 2>/dev/null)" >> "$LOG"
    echo "hyprlock pid: $(pgrep -x hyprlock | tr '\n' ' ')" >> "$LOG"
}

echo "=== WATCH START $(date '+%H:%M:%S') ===" >> "$LOG"
snap

while true; do
    sleep 1
    # Capture l'état si quelque chose a changé depuis la dernière passe
    CUR="$(grep -m1 '^wallpaper' "$HOME/.config/waypaper/config.ini" 2>/dev/null)|$(cat "$RUNDIR/sasquatch-theme-last" 2>/dev/null)|$(hyprctl hyprpaper listactive 2>/dev/null | md5sum | cut -c1-8)|$(pgrep -x hyprlock | md5sum | cut -c1-8)"
    [ "$CUR" != "$PREV" ] && { PREV="$CUR"; snap; }
done
