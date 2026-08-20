#!/bin/bash
# waybar-toggle.sh — bascule visibilité de la waybar (Super+J).
#
# waybar écoute SIGUSR1 = toggle visible/invisible (signal natif, pas de kill).
# On ne vise QUE le waybar de l'instance Hyprland COURANTE : un orphelin
# d'une session morte (relogin/crash) a une vieille signature dans son
# /proc/<pid>/environ — lui envoyer le signal ne ferait rien à l'écran
# (même logique que waybar_current_session() de theme-apply.sh).
set -uo pipefail

inst="${HYPRLAND_INSTANCE_SIGNATURE:-}"
if [ -z "$inst" ]; then
    notify-send "Waybar" "Pas d'instance Hyprland" -t 2000 2>/dev/null
    exit 1
fi

for pid in $(pgrep -x waybar 2>/dev/null); do
    sig=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p' | head -1)
    if [ "$sig" = "$inst" ]; then
        kill -USR1 "$pid"
        exit 0
    fi
done

notify-send "Waybar" "Barre introuvable (session ?)" -t 2000 2>/dev/null
exit 1
