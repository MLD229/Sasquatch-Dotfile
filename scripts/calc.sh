#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Sasquatch · Calculatrice (SUPER+C)
#  Toute la logique de calcul vit dans rofi/scripts/calc-modi.sh
#  (la même que celle du launcher, mode « calc »).
#
#  Pourquoi -dmenu et pas le modi « calc » du plugin rofi-calc : mesuré ici,
#  libcalc.so (~/.local/lib/rofi) affiche « Add to history » mais ne calcule
#  rien avec ce rofi 2.0 → repli sur un dmenu piloté par calc-modi.sh.
#
#  Utilisation : SUPER+C → on tape 2+2 → Entrée → le résultat est copié et
#  affiché (notification). La liste propose les 5 derniers calculs : Entrée
#  sur une ligne re-copie son résultat. SUPER+C = aussi toggle.
# ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CALC_MODE="$SCRIPT_DIR/../rofi/scripts/calc-modi.sh"
THEME="$SCRIPT_DIR/../rofi/themes/sasquatch.rasi"
HIST="$HOME/.cache/sasquatch-calc.hist"
PIDFILE="/tmp/sasquatch-calc.pid"

# qalc vit dans /usr/sbin, souvent absent du PATH d'une session Hyprland
export PATH="/usr/sbin:/sbin:$PATH"

[ -x "$CALC_MODE" ] || { echo "calc-modi.sh introuvable: $CALC_MODE" >&2; exit 1; }

# ── Toggle : si la calculatrice est déjà ouverte → la refermer.
# Piège : ne JAMAIS tuer un PID stocké sans vérifier que c'est bien rofi —
# après un relogin, le PID peut être réutilisé.
_pid="$(cat "$PIDFILE" 2>/dev/null || true)"
if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null \
    && [ "$(cat "/proc/$_pid/comm" 2>/dev/null)" = "rofi" ]; then
    kill "$_pid" 2>/dev/null
    rm -f "$PIDFILE"
    exit 0
fi
rm -f "$PIDFILE"

mkdir -p "$(dirname "$HIST")"
lines="$(tail -n 5 "$HIST" 2>/dev/null | sed '/^[[:space:]]*$/d')"
OUT="$(mktemp)"

# ── Lancement : rofi -dmenu (ce qui est tapé revient sur stdout)
if [ -n "$lines" ]; then
    printf '%s\n' "$lines" | rofi -dmenu \
        -theme "$THEME" -p " Calcul" -lines 5 \
        -mesg "Entrée = calculer puis copier" \
        -show-icons -icon-theme "Papirus-Dark" "$@" >"$OUT" 2>/dev/null &
else
    printf '' | rofi -dmenu \
        -theme "$THEME" -p " Calcul" -lines 5 \
        -mesg "Entrée = calculer puis copier" \
        -show-icons -icon-theme "Papirus-Dark" "$@" >"$OUT" 2>/dev/null &
fi
RPID=$!
echo "$RPID" > "$PIDFILE"
wait "$RPID"
rm -f "$PIDFILE"

sel="$(cat "$OUT" 2>/dev/null || true)"
rm -f "$OUT"
[ -z "$sel" ] && exit 0

# Ligne d'historique (« expr = res ») ou expression tapée ?
case "$sel" in
    *\ =\ *) line="$sel" ;;
    *)
        line="$("$CALC_MODE" --eval "$sel")"
        [ -z "$line" ] && exit 0
        ;;
esac

"$CALC_MODE" --copy "$line"

# Historique : la nouvelle ligne en tête, sans doublon, 5 max
{ printf '%s\n' "$line"; cat "$HIST" 2>/dev/null; } |
    awk 'NF && !seen[$0]++' | head -n 5 > "$HIST.tmp" && mv "$HIST.tmp" "$HIST"

notify-send -a "Sasquatch · Calcul" -t 4000 "$line" 2>/dev/null || true
exit 0
