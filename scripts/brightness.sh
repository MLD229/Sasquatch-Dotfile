#!/bin/bash
# brightness.sh — luminosité (brightnessctl) + notification mako
# replace-id : les notifications se remplacent (pas de superposition en rafale)
IDFILE="/tmp/sasquatch-brightness-notif.id"

case $1 in
    up)   brightnessctl set 5%+ ;;
    down) brightnessctl set 5%- ;;
esac

PCT=$(brightnessctl get)
MAX=$(brightnessctl max)
VAL=$(( PCT * 100 / MAX ))
LAST_ID=$(cat "$IDFILE" 2>/dev/null || echo 0)

notify-send -r "$LAST_ID" -p "Luminosité" "$VAL%" -t 1200 > "$IDFILE"
~/.config/scripts/osd.sh "Luminosité" "$VAL" "󰃟"
