#!/usr/bin/env bash
# sidebar.sh — toggle la slide bar Sasquatch (Super+U).
#
# Différences avec cc.sh : la sidebar est un PanelWindow (layer-shell) et non
# une fenêtre normale → elle n'apparaît PAS dans `hyprctl clients`, donc la
# détection se fait sur le process quickshell (chemin absolu, motif [q]uickshell
# pour ne jamais matcher ce script).
#
# Le BACKEND (server.py) n'est PAS tué à la fermeture : c'est lui qui fait
# tourner le chrono / timer / alarme panneau fermé. Il vit dans le service
# systemd user sasquatch-sidebar.service.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QML="$SCRIPT_DIR/shell.qml"
PORT="${SASQUATCH_SIDEBAR_PORT:-8778}"
PATTERN="[q]uickshell.*sidebar/shell\.qml"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sasquatch"
mkdir -p "$LOG_DIR"

panel_open() {
    pgrep -f "$PATTERN" >/dev/null 2>&1
}

# ── Toggle OFF ────────────────────────────────────────────────────────────
if panel_open; then
    pkill -TERM -f "$PATTERN" >/dev/null 2>&1 || true
    exit 0
fi

# Orphelins d'une session précédente (crash, relogin…)
pkill -TERM -f "$PATTERN" >/dev/null 2>&1 || true

# Pas de session Wayland (écran de login, tty) → message clair, pas de crash.
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    notify-send "Sasquatch Sidebar" \
        "Aucune session Wayland active (WAYLAND_DISPLAY vide)." -t 3000 \
        2>/dev/null || echo "sidebar: WAYLAND_DISPLAY absent" >&2
    exit 1
fi

# ── Backend ───────────────────────────────────────────────────────────────
if ! curl -s -o /dev/null -m 1 "http://127.0.0.1:$PORT/api/health"; then
    if systemctl --user list-unit-files 2>/dev/null | grep -q '^sasquatch-sidebar.service'; then
        systemctl --user start sasquatch-sidebar >/dev/null 2>&1 || true
    else
        # service non installé (dépôt juste cloné) → lancement direct
        ( setsid /usr/bin/python3 -u "$SCRIPT_DIR/server.py" \
              >>"$LOG_DIR/server.log" 2>&1 & ) || true
    fi
fi

server_up=0
for _ in $(seq 1 30); do
    if curl -s -o /dev/null -m 1 "http://127.0.0.1:$PORT/api/health"; then
        server_up=1
        break
    fi
    sleep 0.2
done

if [ "$server_up" -ne 1 ]; then
    notify-send "Sasquatch Sidebar" \
        "Backend injoignable (port $PORT) — journalctl --user -u sasquatch-sidebar" \
        -t 4000 2>/dev/null || echo "sidebar: backend absent" >&2
    exit 1
fi

# ── Panneau ───────────────────────────────────────────────────────────────
# Chemin ABSOLU obligatoire : c'est ce qui rend le pattern pgrep fiable.
# JAMAIS de grab clavier par défaut : sur Hyprland 0.56.2 le grab du panneau
# empêchait hyprlock de recevoir le mot de passe (écran de verrouillage bloqué).
# Le panneau n'a pas besoin de capturer le clavier pour fonctionner (saisie to-do
# = simple focus fenêtre). SASQUATCH_SIDEBAR_GRAB=1 pour le réactiver si besoin.
export SASQUATCH_SIDEBAR_NOGRAB="${SASQUATCH_SIDEBAR_NOGRAB:-1}"
[ "${SASQUATCH_SIDEBAR_GRAB:-0}" = "1" ] && export SASQUATCH_SIDEBAR_NOGRAB=0

exec quickshell -p "$QML"
