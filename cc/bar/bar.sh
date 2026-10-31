#!/usr/bin/env bash
# bar.sh — toggle de la barre verticale Sasquatch (Super+J).
#
# La barre est un PanelWindow (layer-shell) : elle n'apparaît PAS dans
# `hyprctl clients`. La détection se fait donc sur le processus quickshell
# (chemin absolu + motif crocheté [q]uickshell pour ne jamais matcher ce
# script). Un deuxième appel = fermeture : c'est le toggle, pas un lancement.
#
# Fermer la barre = tuer le processus : Hyprland libère alors l'exclusiveZone
# tout seul (vérifiable avec `hyprctl layers` et monitors[].reserved).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QML="$SCRIPT_DIR/shell.qml"
CC_PORT="${SASQUATCH_CC_PORT:-8765}"
# Motif crocheté : « [q]uickshell » ne peut pas matcher la ligne de commande
# d'un shell qui contiendrait le littéral « quickshell ».
PATTERN="[q]uickshell.*cc/bar/shell\.qml"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sasquatch"
mkdir -p "$LOG_DIR"

# PIDs de la barre. `pgrep -x quickshell` (nom exact) + lecture de
# /proc/<pid>/cmdline : on ne peut PAS se tuer soi-même, contrairement à un
# `pkill -f` qui matcherait le script appelant.
bar_pids() {
    local pid
    for pid in $(pgrep -x quickshell 2>/dev/null); do
        if tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "$PATTERN"; then
            printf '%s\n' "$pid"
        fi
    done
}

bar_up() {
    [ -n "$(bar_pids)" ]
}

kill_bar() {
    local pid
    for pid in $(bar_pids); do
        kill -TERM "$pid" 2>/dev/null || true
    done
}

# ── Service systemd : une seule autorité sur le processus ─────────────────
# Le processus de la barre est lancé par sasquatch-bar.service (Restart=on-failure
# → une barre qui crashe revient seule, et l'autostart vient de default.target).
# Ce script ne doit donc PAS lancer quickshell en direct : sinon, après un seul
# Super+J, la barre vivrait hors supervision systemd (aucun redémarrage sur
# crash, aucune reprise au login) et deux instances pourraient coexister.
# Le toggle passe par `systemctl --user stop/start` ; les orphelins éventuels
# (vieille session, lancement manuel) sont tués à part.
svc_up() {
    systemctl --user is-active --quiet sasquatch-bar 2>/dev/null
}

# ── Toggle OFF ────────────────────────────────────────────────────────────
if bar_up || svc_up; then
    systemctl --user stop sasquatch-bar >/dev/null 2>&1 || true
    kill_bar
    # Attente courte : la zone réservée doit être rendue avant de rendre la main.
    for _ in $(seq 1 20); do
        { bar_up || svc_up; } || exit 0
        sleep 0.05
    done
    for _pid in $(bar_pids); do kill -KILL "$_pid" 2>/dev/null || true; done
    exit 0
fi

# Orphelins d'une session précédente (crash, relogin…)
kill_bar

# Pas de session Wayland (tty, écran de login) → message clair, pas de crash.
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    notify-send "Barre Sasquatch" \
        "Aucune session Wayland active (WAYLAND_DISPLAY vide)." -t 3000 \
        2>/dev/null || echo "bar: WAYLAND_DISPLAY absent" >&2
    exit 1
fi

# ── Backend CC (source des données : palette, stats, volume) ─────────────
if ! curl -s -o /dev/null -m 1 "http://127.0.0.1:$CC_PORT/api/palette"; then
    systemctl --user start sasquatch-cc >/dev/null 2>&1 || true
fi

backend_up=0
for _ in $(seq 1 40); do
    if curl -s -o /dev/null -m 1 "http://127.0.0.1:$CC_PORT/api/palette"; then
        backend_up=1
        break
    fi
    sleep 0.2
done

if [ "$backend_up" -ne 1 ]; then
    # La barre sait démarrer sans backend (couleurs de secours, états
    # « indisponible ») : on prévient, on ne bloque pas.
    notify-send "Barre Sasquatch" \
        "Backend CC injoignable (port $CC_PORT) — barre lancée en mode dégradé." \
        -t 4000 2>/dev/null || echo "bar: backend absent, mode dégradé" >&2
fi

# ── Barre ─────────────────────────────────────────────────────────────────
# Lancement via le service (seule autorité) : le process est alors supervisé
# (Restart=on-failure) et suit l'autostart de session. `exec quickshell` en
# direct ici sortirait la barre de systemd dès le premier Super+J.
systemctl --user start sasquatch-bar || {
    notify-send "Barre Sasquatch" "Échec du démarrage — journalctl --user -u sasquatch-bar" -t 4000 2>/dev/null || true
    exit 1
}

# Vérification réelle : la surface doit exister (PanelWindow = layer surface,
# donc invisible dans `hyprctl clients`).
for _ in $(seq 1 30); do
    if bar_up; then
        exit 0
    fi
    sleep 0.1
done

notify-send "Barre Sasquatch" "Barre non affichée après 3 s — journalctl --user -u sasquatch-bar" -t 4000 2>/dev/null || true
exit 1
