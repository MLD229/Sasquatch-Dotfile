#!/bin/bash
# brightness.sh
case $1 in
    up)   brightnessctl set 5%+ ;;
    down) brightnessctl set 5%- ;;
esac
notify-send -h string:x-canonical-private-synchronous:brightness \
    "Luminosité" "$(brightnessctl get)%" -t 1500
