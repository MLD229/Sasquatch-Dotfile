#!/bin/bash
# wallpaper.sh — restaure le wallpaper au login (ex-waypaper --restore).
#
# Délègue tout à apply-wallpaper.sh (même chaîne que le backend CC) :
# tue les hyprpaper orphelins d'une session passée (bug 2026-08-14 : un
# hyprpaper déjà vivant n'était pas remplacé → IPC mort → fond noir, alors
# que la palette suivait quand même) puis relance hyprpaper et applique le
# wallpaper de config.ini.
set -u

~/.config/cc/apply-wallpaper.sh >/dev/null 2>&1 &

exit 0
