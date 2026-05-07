#!/usr/bin/env bash

WALL="$1"

[ -f "$WALL" ] || exit 1

# Appliquer wallpaper (hyprpaper)
hyprctl hyprpaper unload all
hyprctl hyprpaper preload "$WALL"
hyprctl hyprpaper wallpaper "eDP-1,$WALL"

# Générer thème
wal -i "$WALL"

# Reload Waybar
pkill waybar
sleep 0.2
waybar >/dev/null 2>&1 &

# Reload dunst
pkill dunst
dunst >/dev/null 2>&1 &

# Reload kitty (optionnel)
kitty @ set-colors -a ~/.cache/wal/colors-kitty.conf 2>/dev/null
