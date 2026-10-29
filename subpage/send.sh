#!/usr/bin/env bash
# Sasquatch Sub page v2 — envoyer la fenêtre active DANS la sub page
# (Super+ALT+S)
#
# Comportement :
#   • la fenêtre active part dans `special:subpage` sans changer de workspace
#     visible (movetoworkspacesilent) ;
#   • si la page est fermée, on l'ouvre d'abord — et elle RESTE ouverte (c'est
#     voulu : on veut voir ce qu'on vient d'envoyer) ;
#   • si aucune fenêtre active : message clair, rien d'autre ;
#   • aucun vol de focus : on ne rappelle jamais la fenêtre envoyée (elle part
#     dans le scratchpad, la reprendre n'aurait aucun sens) et on ne touche pas
#     au focus du workspace courant.
#
# Plus d'`alterzorder`, plus d'ordre de mapping : la décoration est un layer de
# fond, jamais une fenêtre du workspace (cf. subpage.sh / shell.qml).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)"
    export HYPRLAND_INSTANCE_SIGNATURE
fi

# ── Fenêtre active : adresse + workspace ──────────────────────────────────
active_json="$(hyprctl activewindow -j 2>/dev/null)" || active_json="{}"

read -r addr ws < <(printf '%s' "$active_json" | "${PYTHON:-python3}" -c '
import json, sys
try:
    win = json.load(sys.stdin)
except ValueError:
    win = {}
addr = win.get("address") or ""
ws = (win.get("workspace") or {}).get("name") or ""
print(addr, ws if ws else "-")
' 2>/dev/null)

if [ -z "${addr:-}" ] || [ "$addr" = "0x0" ]; then
    echo "subpage: aucune fenêtre active — rien à envoyer." >&2
    exit 1
fi

if [ "${ws:-}" = "special:subpage" ]; then
    echo "subpage: la fenêtre active est déjà dans la page." >&2
    exit 0
fi

# ── Page fermée → l'ouvrir d'abord (elle reste ouverte ensuite) ───────────
if ! "$SCRIPT_DIR/subpage.sh" status >/dev/null 2>&1; then
    "$SCRIPT_DIR/subpage.sh" open || exit 1
fi

# Envoi silencieux : la fenêtre quitte son workspace pour le scratchpad sans
# que l'écran courant ne bascule.
hyprctl dispatch movetoworkspacesilent "special:subpage,address:$addr" >/dev/null
