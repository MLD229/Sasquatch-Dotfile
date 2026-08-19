#!/usr/bin/env bash
# set-wall.sh — change le wallpaper ET applique le thème dynamique
# Usage : ./set-wall.sh <chemin_image>
#
# Délègue à apply-wallpaper.sh (même chaîne que le picker Super+Y et que
# wallpaper.sh au login) : hyprpaper direct + gestion socket stale + thème.
# Les anciennes commandes `hyprctl hyprpaper unload/preload` sont MORTES dans
# hyprpaper v0.8 ("invalid hyprpaper request") — le wallpaper passe direct.
set -u
WALL="${1:-}"

[ -f "$WALL" ] || { echo "Usage: $0 <image>" >&2; exit 1; }

~/.config/cc/apply-wallpaper.sh "$WALL"
