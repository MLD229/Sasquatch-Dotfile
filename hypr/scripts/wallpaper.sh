#!/bin/bash
# wallpaper.sh — restaure le wallpaper au login.
#
# Délègue tout à apply-wallpaper.sh (même chaîne que le backend CC) :
# tue les hyprpaper orphelins d'une session précédente (un hyprpaper déjà
# vivant n'est pas remplacé → IPC mort → fond noir, alors que la palette
# suivait quand même) puis relance hyprpaper et applique le wallpaper de
# config.ini.
set -u

~/.config/cc/apply-wallpaper.sh >/dev/null 2>&1 &

exit 0
