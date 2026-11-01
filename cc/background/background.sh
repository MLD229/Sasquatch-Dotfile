#!/usr/bin/env bash
# background.sh — lanceur / toggle de l'hôte « fond d'écran » des widgets.
#
# La surface est un PanelWindow layer `Background` : elle n'apparaît PAS dans
# `hyprctl clients` (visible avec `hyprctl layers`). Le processus est supervisé
# par sasquatch-bg.service (Restart=always) — comme la barre, le service est la
# SEULE autorité : ce script ne lance jamais quickshell en direct, sinon le
# service relancerait une seconde instance.
#
# Usage : background.sh [toggle|open|close|status]      (défaut : toggle)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SHELL_QML="$SCRIPT_DIR/shell.qml"
UNIT="sasquatch-bg"
CC_PORT="${SASQUATCH_CC_PORT:-8765}"

# Module de widgets partagé : sans ce chemin, `import Sasquatch.Widgets 1.0`
# échoue (brief widgets v1 §0.1) — le shell mourrait au chargement.
WIDGETS_DIR="$HOME/.config/cc/widgets"
if [ -d "$WIDGETS_DIR" ]; then
    export QML_IMPORT_PATH="$WIDGETS_DIR${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
fi

# Session Wayland : les keybinds la fournissent déjà ; on la reconstitue pour
# que le script marche aussi depuis un shell nu (tests, systemd run).
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Motif crocheté : « [q]uickshell » ne peut pas matcher la ligne de commande
# d'un shell qui contiendrait le littéral « quickshell ».
PATTERN="[q]uickshell.*cc/background/shell\\.qml"

bg_pids() {
    local pid
    for pid in $(pgrep -x quickshell 2>/dev/null); do
        if tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "$PATTERN"; then
            printf '%s\n' "$pid"
        fi
    done
}

bg_up() {
    [ -n "$(bg_pids)" ]
}

svc_up() {
    systemctl --user is-active --quiet "$UNIT" 2>/dev/null
}

kill_bg() {
    local pid
    for pid in $(bg_pids); do
        kill -TERM "$pid" 2>/dev/null || true
    done
}

case "${1:-toggle}" in
status)
    if svc_up && bg_up; then
        echo "background: actif ($(bg_pids | tr '\n' ' '))"
        exit 0
    fi
    echo "background: arrêté"
    exit 1
    ;;
close)
    systemctl --user stop "$UNIT" >/dev/null 2>&1 || true
    kill_bg
    for _ in $(seq 1 20); do
        { bg_up || svc_up; } || exit 0
        sleep 0.05
    done
    exit 0
    ;;
open|toggle)
    if [ "${1:-toggle}" = "toggle" ] && { bg_up || svc_up; }; then
        systemctl --user stop "$UNIT" >/dev/null 2>&1 || true
        kill_bg
        exit 0
    fi

    if [ -z "${WAYLAND_DISPLAY:-}" ]; then
        notify-send "Sasquatch — fond" \
            "Aucune session Wayland active (WAYLAND_DISPLAY vide)." -t 3000 \
            2>/dev/null || echo "background: WAYLAND_DISPLAY absent" >&2
        exit 1
    fi

    # Backend : les widgets lisent la palette via 127.0.0.1:8765. Sans lui ils
    # restent lisibles (repli SystemPalette) — on prévient, on ne bloque pas.
    if ! curl -s -o /dev/null -m 1 "http://127.0.0.1:$CC_PORT/api/palette"; then
        systemctl --user start sasquatch-cc >/dev/null 2>&1 || true
        for _ in $(seq 1 20); do
            curl -s -o /dev/null -m 1 "http://127.0.0.1:$CC_PORT/api/palette" && break
            sleep 0.2
        done
    fi

    # Orphelins d'une session précédente (lancement manuel, crash).
    kill_bg

    systemctl --user start "$UNIT" || {
        notify-send "Sasquatch — fond" \
            "Échec du démarrage — journalctl --user -u $UNIT" -t 4000 2>/dev/null || true
        exit 1
    }

    for _ in $(seq 1 30); do
        bg_up && exit 0
        sleep 0.1
    done

    notify-send "Sasquatch — fond" \
        "Surface non affichée après 3 s — journalctl --user -u $UNIT" -t 4000 \
        2>/dev/null || true
    exit 1
    ;;
*)
    echo "usage: background.sh [toggle|open|close|status]" >&2
    exit 2
    ;;
esac
