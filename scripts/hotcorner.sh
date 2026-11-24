#!/usr/bin/env bash
# hotcorner.sh — coin supérieur gauche = même action que Super+X (libérer le
# workspace / show desktop).
#
# Pourquoi un démon qui sonde au lieu d'un `MouseArea` : le coin appartient à
# la fenêtre qui l'occupe, donc une surface layer ne reçoit jamais le survol
# quand une fenêtre est plein écran. `hyprctl cursorpos` lit la position
# globale, quel que soit ce qu'il y a dessous.
#
# Réglages : zone 8x8 px, 2 relevés consécutifs (≈400 ms de maintien), puis
# 2 s d'immunité et obligation de sortir du coin avant de re-déclencher.
set -uo pipefail

# Lancé comme service systemd --user, ce script n'hérite pas de l'environnement
# Wayland : sans signature, `hyprctl` échoue à chaque sonde (200 ms) et le coin
# ne se déclenche jamais. On la retrouve depuis le socket runtime.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || [ ! -d "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -n1)"
    export HYPRLAND_INSTANCE_SIGNATURE
fi
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"

ZONE="${HOTC_ZONE:-8}"
POLL="${HOTC_POLL:-0.2}"
ACTION="${HOTC_ACTION:-$HOME/.config/scripts/showdesktop.sh}"

seen=0
armed=1

while :; do
    read -r x y <<<"$(hyprctl cursorpos 2>/dev/null | tr -d ',')"
    if [ -z "${x:-}" ] || [ -z "${y:-}" ]; then
        sleep "$POLL"; continue
    fi
    if [ "${x:-99999}" -le "$ZONE" ] && [ "${y:-99999}" -le "$ZONE" ] && [ "${y:-99999}" -ge 0 ]; then
        seen=$((seen + 1))
        if [ "$armed" = "1" ] && [ "$seen" -ge 2 ]; then
            armed=0
            # Journal minimal : chaque déclenchement, avec la sortie réelle du
            # script (un échec silencieux a déjà laissé 14 fenêtres cachées
            # sans fichier d'état).
            log="${XDG_STATE_HOME:-$HOME/.local/state}/sasquatch-hotcorner.log"
            mkdir -p "$(dirname "$log")"
            { echo "[$(date +%H:%M:%S)] trigger cursor=$x,$y state=${XDG_RUNTIME_DIR:-unset}"; "$ACTION" 2>&1; } >>"$log"
            notify-send -t 1200 "Bureau" "Coin supérieur gauche" 2>/dev/null || true
        fi
    else
        seen=0
        if [ "$armed" = "0" ]; then
            armed=1
        fi
    fi
    sleep "$POLL"
done
