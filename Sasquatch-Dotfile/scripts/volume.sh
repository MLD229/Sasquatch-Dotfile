#!/bin/bash
# volume.sh
case $1 in
    up)     wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+ ;;
    down)   wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
    mute)   wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
esac
notify-send -h string:x-canonical-private-synchronous:volume \
    "Volume" "$(wpctl get-volume @DEFAULT_AUDIO_SINK@)" -t 1500
