#!/bin/bash
# volume.sh — volume (wpctl) + notification mako
# replace-id : les notifications se remplacent (pas de superposition en rafale)
IDFILE="/tmp/sasquatch-volume-notif.id"

case $1 in
    up)   wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+ ;;
    down) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
    mute) wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
esac

VOL=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2*100)}')
MUTED=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -c MUTED)
LAST_ID=$(cat "$IDFILE" 2>/dev/null || echo 0)

if [ "$MUTED" -gt 0 ]; then
    notify-send -r "$LAST_ID" -p "Volume" "Muet" -t 1200 > "$IDFILE"
    ~/.config/scripts/osd.sh "Volume" 0 "󰝟"
else
    notify-send -r "$LAST_ID" -p "Volume" "$VOL%" -t 1200 > "$IDFILE"
    if [ "$VOL" -le 33 ]; then ICON="󰕿"; elif [ "$VOL" -le 66 ]; then ICON="󰖀"; else ICON="󰕾"; fi
    ~/.config/scripts/osd.sh "Volume" "$VOL" "$ICON"
fi
