#!/bin/bash
# screenshot.sh
DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"
FILE="$DIR/$(date +%Y%m%d_%H%M%S).png"

case $1 in
    full) grim "$FILE" ;;
    area) grim -g "$(slurp)" "$FILE" ;;
esac

wl-copy < "$FILE"
notify-send "Screenshot" "Sauvegardé + copié" -i "$FILE" -t 2000
