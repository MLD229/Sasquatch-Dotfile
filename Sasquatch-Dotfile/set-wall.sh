#!/usr/bin/env bash
# set-wall.sh — change le wallpaper ET applique le thème dynamique
# Usage : ./set-wall.sh <chemin_image>

set -u
WALL="${1:-}"

[ -f "$WALL" ] || { echo "Usage: $0 <image>" >&2; exit 1; }

# Appliquer wallpaper (hyprpaper) — moniteur actif ou eDP-1 en secours
MONITOR=$(hyprctl monitors -j 2>/dev/null | python3 -c "import json,sys; m=json.load(sys.stdin); print(m[0]['name'] if m else '')" 2>/dev/null)
MONITOR="${MONITOR:-eDP-1}"
hyprctl hyprpaper unload all 2>/dev/null
hyprctl hyprpaper preload "$WALL"
hyprctl hyprpaper wallpaper "$MONITOR,$WALL"

# Thème dynamique (palette → waybar/kitty/hyprland/mako/rofi)
~/.config/scripts/theme-apply.sh "$WALL"
