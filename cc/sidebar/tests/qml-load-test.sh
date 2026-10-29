#!/usr/bin/env bash
# qml-load-test.sh — charge shell.qml dans un compositeur Wayland EXISTANT et
# vérifie deux choses :
#   1. aucune erreur QML au chargement / à l'exécution (aucune ligne ERROR,
#      TypeError, "is not defined", "Unable to assign") ;
#   2. le panneau interroge vraiment le backend (compteur de requêtes de
#      /api/health qui augmente pendant le run) → preuve d'intégration réelle.
#
# Usage :
#   WAYLAND_DISPLAY=wayland-test ./tests/qml-load-test.sh [durée_s]
# Sans WAYLAND_DISPLAY, le test est SAUTÉ (exit 77) : c'est le cas sur un tty
# de login, où aucun panneau ne peut être dessiné.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
DURATION="${1:-10}"
PORT="${SASQUATCH_SIDEBAR_PORT:-8778}"
BASE="http://127.0.0.1:$PORT"

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "SKIP: WAYLAND_DISPLAY absent (aucun compositeur → pas de rendu possible)"
    exit 77
fi
if ! curl -s -o /dev/null -m 2 "$BASE/api/health"; then
    echo "FAIL: backend $BASE injoignable (lance server.py d'abord)"; exit 1
fi

count_state() {
    curl -s -m 2 "$BASE/api/health" | python3 -c \
        'import json,sys; print(json.load(sys.stdin)["requests"].get("/api/state",0))'
}

before="$(count_state)"
log="$(mktemp -t qml-load-XXXX.log)"
( cd "$ROOT" && timeout "$DURATION" quickshell -p "$ROOT/shell.qml" ) >"$log" 2>&1
after="$(count_state)"

echo "── sortie quickshell ($(wc -l <"$log") lignes) ──"
cat "$log"
echo "── fin sortie ──"

fail=0
if grep -qiE "error|typeerror|is not defined|unable to assign|cannot assign|non-existent" "$log"; then
    echo "FAIL: erreur(s) QML détectée(s)"; fail=1
else
    echo "OK   : aucune erreur QML"
fi
if grep -q "Configuration Loaded" "$log"; then
    echo "OK   : configuration chargée par Quickshell"
else
    echo "FAIL: 'Configuration Loaded' absent"; fail=1
fi
polls=$(( after - before ))
if [ "$polls" -ge 5 ]; then
    echo "OK   : $polls requêtes /api/state pendant ${DURATION}s (panneau vivant)"
else
    echo "FAIL: seulement $polls requêtes /api/state — le QML ne tourne pas"; fail=1
fi

rm -f "$log"
exit "$fail"
