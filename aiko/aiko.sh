#!/usr/bin/env bash
# aiko.sh — toggle la sidebar 愛子 (Super+N).  Panneau GAUCHE, LLM éphémère.
#
# CYCLE DE VIE (ce que ce script garantit)
#   ouvrir  : backend python (8791) lancé si absent (~50 ms). Modèle : RIEN.
#   1er msg : le backend lance llama-server, attend /health, streame.
#   fermer  : POST /api/shutdown → llama-server tué, historique RAM jeté,
#             backend sorti → plus AUCUN process aiko, VRAM rendue.
#   filet   : les llama-server orphelins (crash, kill -9) sont tués ici.
#
# SOURCE DE VÉRITÉ : ce script (ou son service aiko.service, s'il est actif).
#   1. un backend aiko déjà vivant est RÉUTILISÉ, jamais doublonné ;
#   2. si 8791 est tenu par autre chose qu'aiko → message clair, on n'ouvre pas ;
#   3. deux pressions rapprochées sont sérialisées par un flock ;
#   4. server.py porte en plus un verrou d'instance unique (flock backend.lock).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QML="$SCRIPT_DIR/shell.qml"
PORT="${AIKO_PORT:-8791}"
# Chemin ABSOLU dans le motif : ne matche pas ce script, ni un autre panneau.
PATTERN="[q]uickshell.*aiko/shell\.qml"
LLAMA_PATTERN="[l]lama-server.*aiko-ephemere"
BACKEND_PATTERN="[a]iko/server\.py"
RUN_DIR="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}}/aiko"
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/aiko-backend.log"
# Python du SYSTÈME (stdlib seulement) : jamais un venv qui traînerait dans le
# PATH d'un shell interactif lancé depuis un keybind.
PY="${AIKO_PYTHON:-$(command -v /usr/bin/python3 || command -v python3 || true)}"

mkdir -p "$RUN_DIR" "${LOG%/*}" 2>/dev/null || true

notify() { notify-send "愛子 (aiko)" "$1" -t "${2:-4000}" 2>/dev/null || true; }
die()    { notify "$1" 5000; echo "aiko: $1" >&2; exit 1; }

panel_open()  { pgrep -f "$PATTERN" >/dev/null 2>&1; }
panel_count() { pgrep -fc "$PATTERN" 2>/dev/null || echo 0; }

# 0 = port libre · 1 = backend aiko vivant · 2 = port tenu par un AUTRE programme
health_code() {
    local body rc
    body="$(curl -s -m 1 "http://127.0.0.1:$PORT/api/health" 2>/dev/null)"
    rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$body" ]; then
        echo 0
    elif printf '%s' "$body" | grep -Eq '"backend"[[:space:]]*:[[:space:]]*"aiko"'; then
        echo 1
    else
        echo 2
    fi
}

service_active() { systemctl --user is-active --quiet aiko.service 2>/dev/null; }

# ── Sérialisation des presses rapprochées (verrou rendu avant quickshell) ──
# ATTENTION (vécu) : ne JAMAIS écrire `exec 9>file 2>/dev/null` — le 2>/dev/null
# devient permanent pour tout le script et masque les erreurs. Et tout process
# long lancé ensuite (le backend) doit être ouvert avec `9>&-`, sinon il hérite
# du verrou et bloque tous les toggles suivants.
exec 9>"$RUN_DIR/toggle.lock" || true
if [ -e "/proc/$$/fd/9" ] && ! flock -n 9; then
    echo "aiko: toggle déjà en cours — ignoré" >&2
    exec 9>&-
    exit 0
fi

# ── Toggle OFF ────────────────────────────────────────────────────────────
if panel_open; then
    # Qui possède le backend ? S'il est tenu par systemd, un SIGKILL serait vu
    # comme un échec (Restart=on-failure) et systemd le relancerait tout seul :
    # il faut `systemctl --user stop`. Vécu, mesuré (journal : status=9/KILL).
    was_service=0
    service_active && was_service=1

    # 1. le backend tue llama-server + jette l'historique + sort proprement
    curl -s -m 5 -X POST "http://127.0.0.1:$PORT/api/shutdown" >/dev/null 2>&1 || true
    # 2. le panneau quitte (il poste déjà shutdown lui-même : idempotent)
    pkill -TERM -f "$PATTERN" >/dev/null 2>&1 || true
    # 3. filet de sécurité : plus un seul llama-server d'aiko
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -f "$LLAMA_PATTERN" >/dev/null 2>&1 || break
        sleep 0.2
    done
    pkill -KILL -f "$LLAMA_PATTERN" >/dev/null 2>&1 || true
    # 4. backend : arrêt propre si systemd le gère, sinon on le tue
    if [ "$was_service" = 1 ]; then
        systemctl --user stop aiko >/dev/null 2>&1 || true
    fi
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ "$(health_code)" = 0 ] && break
        sleep 0.2
    done
    if [ "$(health_code)" != 0 ]; then
        pkill -KILL -f "$BACKEND_PATTERN" >/dev/null 2>&1 || true
    fi
    exec 9>&-
    exit 0
fi

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    notify "Aucune session Wayland active (WAYLAND_DISPLAY vide)." 3000
    echo "aiko: WAYLAND_DISPLAY absent" >&2
    exit 1
fi

hs="$(health_code)"
case "$hs" in
2)
    # Port tenu par autre chose : on ne tue rien, on explique.
    OWNER="$(ss -ltnp 2>/dev/null | grep -E ":$PORT([[:space:]]|$)" | head -1)"
    die "Port $PORT déjà occupé par un autre programme — aiko ne s'ouvre pas.
Détail : ${OWNER:-inconnu}
→ libérer le port (sudo ss -ltnp | grep :$PORT) ou changer AIKO_PORT"
    ;;
1)
    # Backend aiko déjà vivant (service systemd ou résidu) : RÉUTILISÉ.
    # On repart propre : zéro conversation en RAM, zéro modèle chargé.
    curl -s -m 3 -X POST "http://127.0.0.1:$PORT/api/new" >/dev/null 2>&1 || true
    curl -s -m 6 -X POST "http://127.0.0.1:$PORT/api/stop" >/dev/null 2>&1 || true
    if service_active; then
        echo "aiko: backend réutilisé (service aiko.service actif)"
    else
        echo "aiko: backend réutilisé (déjà lancé, hors service)"
    fi
    ;;
*)
    # Personne sur le port : on nettoie les résidus d'une session précédente.
    pkill -TERM -f "$LLAMA_PATTERN" >/dev/null 2>&1 || true
    pkill -KILL -f "$LLAMA_PATTERN" >/dev/null 2>&1 || true
    pkill -TERM -f "$BACKEND_PATTERN" >/dev/null 2>&1 || true

    if service_active; then
        systemctl --user start aiko.service >/dev/null 2>&1 || true
        for _ in 1 2 3 4 5 6 7 8; do
            [ "$(health_code)" = 1 ] && break
            sleep 0.1
        done
    fi
    if [ "$(health_code)" != 1 ]; then
        if [ -z "$PY" ]; then
            die "python3 introuvable dans le PATH — installer : sudo pacman -S python"
        fi
        # Lancement à la demande, détaché. Logs techniques seulement (jamais
        # le contenu des conversations) ; AIKO_DEBUG=1 pour les requêtes HTTP.
        # `9>&-` : le backend ne doit PAS hériter du verrou de toggle.
        ( setsid "$PY" -u "$SCRIPT_DIR/server.py" >>"$LOG" 2>&1 9>&- & ) || true
    fi
    ;;
esac

# ── Attente du backend ────────────────────────────────────────────────────
server_up=0
for _ in $(seq 1 40); do
    if [ "$(health_code)" = 1 ]; then
        server_up=1
        break
    fi
    sleep 0.1
done

if [ "$server_up" -ne 1 ]; then
    if [ "$(health_code)" = 2 ]; then
        die "Port $PORT pris par un autre programme après lancement — voir $LOG"
    fi
    die "Backend injoignable (port $PORT) — voir $LOG"
fi

# Deux panneaux aiko ne peuvent pas coexister : on garde le plus récent.
if [ "$(panel_count)" -gt 1 ]; then
    pkill -TERM -f "$PATTERN" >/dev/null 2>&1 || true
fi

# ── Panneau ───────────────────────────────────────────────────────────────
# AUCUN grab clavier (hyprland_focus_grab_v1) : sur Hyprland 0.56.2 un grab
# actif empêchait hyprlock de recevoir le mot de passe. Le panneau se contente
# de demander le focus (WlrKeyboardFocus.OnDemand) pour la saisie.
export SASQUATCH_SIDEBAR_NOGRAB="${SASQUATCH_SIDEBAR_NOGRAB:-1}"

exec 9>&-
exec quickshell -p "$QML"
