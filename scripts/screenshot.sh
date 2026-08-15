#!/bin/bash
# screenshot.sh [full|area|window] [cc]
# Capture d'écran Wayland native (grim + slurp).
#  - fichier PNG dans ~/Pictures/Screenshots
#  - copie dans le presse-papier (wl-copy)
#  - notification aperçu (replace-id : pas d'empilement)
#  - 2e arg "cc" : appelé depuis le Control Center → ferme le CC avant la capture
DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"
FILE="$DIR/$(date +%Y%m%d_%H%M%S_%N).png"

# appelé depuis le Control Center : on masque le CC avant de capturer
if [[ "$2" == "cc" ]]; then
    hyprctl dispatch closewindow "title:^(Sasquatch CC)$" >/dev/null 2>&1
    sleep 0.35
fi

case $1 in
    full)   grim "$FILE" ;;
    window) grim -g "$(slurp -o -f '%x,%y %wx%h')" "$FILE" ;;
    area)   grim -g "$(slurp)" "$FILE" ;;
    *)
        notify-send "Screenshot" "usage: screenshot.sh [full|area|window] [cc]" -t 2500
        exit 1 ;;
esac

if [[ ! -f "$FILE" || ! -s "$FILE" ]]; then
    notify-send "Screenshot" "Capture annulée" -t 1500
    exit 1
fi

wl-copy < "$FILE"
notify-send -p "Screenshot" "$(basename "$FILE") — copié ✓" -i "$FILE" -t 2500 \
    > /tmp/sasquatch-screenshot-notif.id 2>/dev/null
echo "$FILE"
