#!/bin/bash
# osd.sh — OSD barre de progression (rofi) pour volume/luminosité.
# Usage : osd.sh <label> <percent> [icon]
# Anti-superposition : tue l'OSD précédent (pkill) avant d'en lancer un nouveau.
LABEL="$1"
PCT="$2"
ICON="${3:-󰓃}"
[ -z "$PCT" ] && exit 1

# Tue l'OSD précédent s'il existe (course-safe pendant les rafales bindel).
# [r]ofi : pattern bracketé — un pkill -f non bracketé s'auto-matcherait
# quand la cmdline du shell contient le pattern.
pkill -f "[r]ofi.*osd.rasi" 2>/dev/null

BARW=16
FILLED=$(( PCT * BARW / 100 ))
BAR=""
for ((i=0; i<BARW; i++)); do
    if [ "$i" -lt "$FILLED" ]; then BAR="${BAR}━"; else BAR="${BAR}─"; fi
done

printf '%s  %s\n%s  %s%%\n' "$ICON" "$LABEL" "$BAR" "$PCT" | \
    rofi -dmenu -theme ~/.config/rofi/themes/osd.rasi -no-custom -lines 2 -p "" &
RPID=$!
sleep 0.9
kill "$RPID" 2>/dev/null
exit 0
