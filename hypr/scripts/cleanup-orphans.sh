#!/bin/bash
# cleanup-orphans.sh — purge les process orphelins d'une session Hyprland précédente.
#
# Pourquoi : au relogin / crash / restart d'Hyprland, les process lancés par
# l'ancienne session gardent leur ancienne HYPRLAND_INSTANCE_SIGNATURE dans
# /proc/<pid>/environ. Leur compositor est mort → ils ne s'affichent plus, mais
# ils continuent de tourner et bloquent les nouveaux services :
#   - waybar  → theme-apply.sh voit un "waybar vivant" (pgrep) et skip → pas de barre
#   - fcitx5  → singleton : le nouveau `fcitx5 -d` sort → IME japonais (mozc) mort
#   - mako    → socket $XDG_RUNTIME_DIR/mako.sock occupé → le nouveau crashe
#   - CC      → port 8765 occupé par l'ancien server.py → "Address already in use"
#   - wl-paste/polkit/hyprpaper/kitty → doublons ou fenêtres fantômes
#
# Ce script tue tout process de l'utilisateur dont la signature Hyprland diffère
# de l'instance courante. Les process SANS signature (systemd user, dbus,
# serveurs lancés à la main hors session) sont épargnés.
#
# Usage : lancé par autostart.sh en tête de session (ou à la main dans la session).
set -u

CUR_INST="${HYPRLAND_INSTANCE_SIGNATURE:-}"
if [ -z "$CUR_INST" ]; then
    echo "cleanup-orphans: hors session Hyprland — rien à faire"
    exit 0
fi

# Nos propres PIDs uniquement (pas de permission denied sur /proc root).
MY_PIDS="$(ps -u "$(id -u)" -o pid= 2>/dev/null | tr -d ' ')"
[ -n "$MY_PIDS" ] || exit 0

old_sig() {
    tr '\0' '\n' < "/proc/$1/environ" 2>/dev/null | sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p' | head -1
}

# Passe 1 : TERM (fermeture propre — fcitx5 emmène mozc_server avec lui)
for pid in $MY_PIDS; do
    [ "$pid" = "$$" ] && continue
    sig=$(old_sig "$pid")
    if [ -n "$sig" ] && [ "$sig" != "$CUR_INST" ]; then
        kill "$pid" 2>/dev/null
    fi
done

# Passe 2 : 1.5 s pour sortir proprement, puis KILL les survivants
sleep 1.5
for pid in $MY_PIDS; do
    [ "$pid" = "$$" ] && continue
    [ -d "/proc/$pid" ] || continue
    sig=$(old_sig "$pid")
    if [ -n "$sig" ] && [ "$sig" != "$CUR_INST" ]; then
        kill -9 "$pid" 2>/dev/null
    fi
done

echo "cleanup-orphans: purge session précédente terminée"
exit 0
