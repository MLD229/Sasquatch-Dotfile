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

# Toggle : si la calculatrice est déjà ouverte → la refermer.
# PIÈGE (leçon 2026-08-14) : ne JAMAIS tuer un PID stocké sans vérifier que
# c'est bien rofi — après un relogin, le PID peut être réutilisé par un autre
# process (kill -0 répond « vivant » à tort) et on tuerait un innocent.
_pid="$(cat "$PIDFILE" 2>/dev/null || true)"
if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null \
    && [ "$(cat "/proc/$_pid/comm" 2>/dev/null)" = "rofi" ]; then
    kill "$_pid" 2>/dev/null
    rm -f "$PIDFILE"
    exit 0
fi
rm -f "$PIDFILE"

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

# Guard : qalc absent (requirements libqalculate) → message clair au lieu
# d'un « Expression invalide » silencieux.
if ! command -v qalc >/dev/null 2>&1; then
    notify-send "Calculatrice" "qalc introuvable — installe libqalculate" -t 3000 2>/dev/null
    exit 1
fi

# Évaluation (qalc -t = résultat brut, sans conversion)
result="$(qalc -t "$expr" 2>/dev/null)"
[ -z "$result" ] && result="Expression invalide"

# Affichage du résultat — Enter = copie dans le presse-papier
printf '%s\n' "$result" | rofi -dmenu -theme "$THEME" -p " = $result" -lines 0 -filter "$result" "$@" 2>/dev/null | tr -d '\n' | wl-copy
exit 0
