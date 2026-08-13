#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Sasquatch · Presse-papier (cliphist + rofi)
#  SUPER+V : historique du presse-papier, copie la sélection
#  SUPER+V (déjà ouvert) : referme (toggle)
# ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME="$SCRIPT_DIR/../rofi/themes/sasquatch.rasi"
PIDFILE="/tmp/sasquatch-clipboard.pid"

# Toggle : si le presse-papier est déjà ouvert → le refermer
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill "$(cat "$PIDFILE")" 2>/dev/null
    rm -f "$PIDFILE"
    exit 0
fi

OUT="$(mktemp)"
cliphist list | rofi \
    -dmenu \
    -theme "$THEME" \
    -p "  Presse-papier" \
    -i \
    -no-custom \
    "$@" >"$OUT" 2>/dev/null &
RPID=$!
echo "$RPID" > "$PIDFILE"
wait "$RPID"
rm -f "$PIDFILE"
SELECTION="$(cat "$OUT")"
rm -f "$OUT"

[ -n "$SELECTION" ] && printf '%s\n' "$SELECTION" | cliphist decode | wl-copy
