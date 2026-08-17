#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Sasquatch · Calculatrice rofi LIVE (qalc)
#  SUPER+C : ouvre → tape l'expression → le résultat s'affiche
#  EN DIRECT à chaque frappe (mode custom rofi)
#  Enter = copie le résultat dans le presse-papier
#  SUPER+C (déjà ouvert) : referme (toggle)
# ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME="$SCRIPT_DIR/../rofi/themes/sasquatch.rasi"
PIDFILE="/tmp/sasquatch-calc.pid"

# ── MODE LIVE : rofi (mode custom) appelle ce script à CHAQUE frappe
# avec l'expression en 1er argument → on renvoie le résultat sur stdout,
# rofi l'affiche dans la liste. Enter sur le résultat = copié.
if [ $# -gt 0 ] && [ "$1" != "--toggle" ]; then
    expr="$1"
    # vide → rien (qalc renvoie un prompt parasite)
    [ -z "$expr" ] && exit 0
    # PAS de chiffre/opérateur/constante → rien (qalc invente des unités
    # fantômes pour « bonjour » : « 0,000000001 B·b·d »)
    if ! printf '%s' "$expr" | grep -qE '[0-9]|sqrt|sin|cos|tan|log|ln|pi|abs|round|floor|ceil'; then
        exit 0
    fi
    result="$(qalc -t "$expr" 2>/dev/null)"
    [ -n "$result" ] && printf '%s\n' "$result"
    exit 0
fi

# ── TOGGLE : si la calculatrice est déjà ouverte → la refermer.
# PIÈGE (leçon 2026-08-14/16) : ne JAMAIS tuer un PID stocké sans vérifier
# que c'est bien rofi — après un relogin, le PID peut être réutilisé.
_pid="$(cat "$PIDFILE" 2>/dev/null || true)"
if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null \
    && [ "$(cat "/proc/$_pid/comm" 2>/dev/null)" = "rofi" ]; then
    kill "$_pid" 2>/dev/null
    rm -f "$PIDFILE"
    exit 0
fi
rm -f "$PIDFILE"

# ── LANCEMENT : rofi en mode custom « calc » (live à chaque frappe)
OUT="$(mktemp)"
rofi -show calc \
     -modi "calc:$SCRIPT_DIR/calc.sh" \
     -theme "$THEME" \
     -p " Calcul" \
     "$@" >"$OUT" 2>/dev/null &
RPID=$!
echo "$RPID" > "$PIDFILE"
wait "$RPID"
rm -f "$PIDFILE"

# Enter → la sélection (le résultat) part dans le presse-papier
result="$(cat "$OUT")"
rm -f "$OUT"
[ -n "$result" ] && printf '%s' "$result" | tr -d '\n' | wl-copy
exit 0
