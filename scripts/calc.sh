#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Sasquatch · Calculatrice (rofi + qalc)
#  SUPER+C : tape une expression → Enter → résultat affiché
#  Enter sur le résultat → copié dans le presse-papier
#  SUPER+C (déjà ouvert) : referme (toggle)
# ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME="$SCRIPT_DIR/../rofi/themes/sasquatch.rasi"
PIDFILE="/tmp/sasquatch-calc.pid"

# Toggle : si la calculatrice est déjà ouverte → la refermer
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill "$(cat "$PIDFILE")" 2>/dev/null
    rm -f "$PIDFILE"
    exit 0
fi

# Saisie de l'expression
OUT="$(mktemp)"
rofi -dmenu -theme "$THEME" -p " Calcul" -no-custom "$@" >"$OUT" 2>/dev/null &
RPID=$!
echo "$RPID" > "$PIDFILE"
wait "$RPID"
rm -f "$PIDFILE"
expr="$(cat "$OUT")"
rm -f "$OUT"
[ -z "$expr" ] && exit 0

# Évaluation (qalc -t = résultat brut, sans conversion)
result="$(qalc -t "$expr" 2>/dev/null)"
[ -z "$result" ] && result="Expression invalide"

# Affichage du résultat — Enter = copie dans le presse-papier
printf '%s\n' "$result" | rofi -dmenu -theme "$THEME" -p " = $result" -lines 0 -filter "$result" "$@" 2>/dev/null | tr -d '\n' | wl-copy
exit 0
