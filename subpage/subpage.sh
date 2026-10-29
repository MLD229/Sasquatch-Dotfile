#!/usr/bin/env bash
# Sasquatch Sub page v2 — toggle la page (Super+S)
#
# La « sub page » est un special workspace Hyprland (`special:subpage`) :
# les apps qu'on y met restent vivantes, cachées, quand la page est fermée.
#
# Décoration = surface layer-shell de FOND (shell.qml, Quickshell) qui ne vit
# PAS dans le workspace. C'est ce qui supprime les 40 lignes de précautions de
# l'ancienne version :
#   • plus de windowrule → plus de piège « mapper la fenêtre pendant que le
#     special est ouvert le FERME » : l'ordre d'ouverture n'a plus d'importance ;
#   • plus d'`alterzorder bottom` : un layer background est TOUJOURS sous les
#     fenêtres ;
#   • plus de flou : on ne demande aucun blur sur ce namespace.
#
# Usage : subpage.sh [toggle|open|close|status]      (défaut : toggle)

set -uo pipefail

# `pwd -P` : chemin CANONIQUE (le dépôt est aussi atteint via le symlink
# ~/.config/subpage) → la détection du process quickshell est la même quel
# que soit le point d'entrée.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
STATE_SCRIPT="$SCRIPT_DIR/state.py"
SHELL_QML="$SCRIPT_DIR/shell.qml"
PY="${PYTHON:-python3}"
RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/subpage"
LOG_FILE="$RUN_DIR/decoration.log"

# Session Hyprland : les keybinds la fournissent déjà ; on la reconstitue pour
# que le script marche aussi depuis un shell nu (tests, cron).
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)"
    export HYPRLAND_INSTANCE_SIGNATURE
fi

# ── La page est-elle ouverte ? (source de vérité unique : state.py) ────────
page_open() {
    "$PY" "$STATE_SCRIPT" --check
}

# ── La décoration tourne-t-elle ? ─────────────────────────────────────────
# Détection PRÉCISE : un process dont l'argv contient EXACTEMENT le chemin de
# notre shell.qml (pas un `pgrep -f quickshell` approximatif qui matcherait le
# CC, la sidebar ou un chemin relatif). Rien n'est stocké sur disque.
decoration_pids() {
    local dir pid found=1
    for dir in /proc/[0-9]*; do
        pid="${dir#/proc/}"
        [ -r "$dir/cmdline" ] || continue
        if tr '\0' '\n' < "$dir/cmdline" 2>/dev/null | grep -Fxq "$SHELL_QML"; then
            printf '%s\n' "$pid"
            found=0
        fi
    done
    return $found
}

decoration_running() {
    decoration_pids >/dev/null 2>&1
}

layer_visible() {
    hyprctl layers 2>/dev/null | grep -q "namespace: subpage"
}

start_decoration() {
    if decoration_running; then
        return 0
    fi
    mkdir -p "$RUN_DIR"
    # `-n` (--no-duplicate) : quickshell sort tout seul s'il tourne déjà pour
    # cette config → jamais deux surfaces « subpage » superposées.
    setsid quickshell -n -p "$SHELL_QML" >"$LOG_FILE" 2>&1 &
    for _ in $(seq 1 40); do
        if decoration_running; then
            return 0
        fi
        sleep 0.1
    done
    echo "subpage: la décoration n'a pas démarré (voir $LOG_FILE)" >&2
    return 1
}

stop_decoration() {
    local pids pid alive
    pids="$(decoration_pids)" || return 0
    for pid in $pids; do
        kill -TERM "$pid" 2>/dev/null
    done
    for _ in $(seq 1 20); do
        alive=0
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then alive=1; fi
        done
        if [ "$alive" -eq 0 ]; then
            return 0
        fi
        sleep 0.05
    done
    for pid in $pids; do
        kill -KILL "$pid" 2>/dev/null
    done
    return 0
}

open_page() {
    if ! start_decoration; then
        return 1
    fi
    # La décoration n'est pas mappée dans le workspace : on peut ouvrir la page
    # AVANT, APRÈS ou PENDANT son démarrage, ça ne la ferme plus.
    if ! page_open; then
        hyprctl dispatch togglespecialworkspace subpage >/dev/null
    fi
    # Preuve de mise en route : la surface doit apparaître dans les layers.
    for _ in $(seq 1 30); do
        if layer_visible; then
            return 0
        fi
        sleep 0.1
    done
    echo "subpage: la page est ouverte mais la décoration n'apparaît pas." >&2
    tail -n 5 "$LOG_FILE" >&2 2>/dev/null
    return 1
}

close_page() {
    # La décoration se cache d'elle-même (synchro sur l'état réel) ; on
    # l'arrête pour ne pas laisser un process à sonder Hyprland pour rien.
    if page_open; then
        hyprctl dispatch togglespecialworkspace subpage >/dev/null
    fi
    stop_decoration
}

case "${1:-toggle}" in
    toggle)
        if page_open; then close_page; else open_page; fi
        ;;
    open)
        open_page
        ;;
    close)
        close_page
        ;;
    status)
        if page_open; then
            printf 'open %s\n' "$("$PY" "$STATE_SCRIPT" --monitor)"
        else
            echo "closed"
            exit 1
        fi
        ;;
    *)
        echo "usage: $0 [toggle|open|close|status]" >&2
        exit 2
        ;;
esac
