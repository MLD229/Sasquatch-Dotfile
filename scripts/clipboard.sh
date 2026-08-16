#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Sasquatch · Presse-papier (cliphist + rofi)
#  SUPER+V : historique du presse-papier, copie la sélection
#  SUPER+V (déjà ouvert) : referme (toggle)
# ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME="$SCRIPT_DIR/../rofi/themes/sasquatch.rasi"
PIDFILE="/tmp/sasquatch-clipboard.pid"

# Guard : cliphist absent (requirements cliphist) → message clair.
if ! command -v cliphist >/dev/null 2>&1; then
    notify-send "Presse-papier" "cliphist introuvable — installe cliphist" -t 3000 2>/dev/null
    exit 1
fi

# Toggle : si le presse-papier est déjà ouvert → le refermer.
# PIÈGE (leçon 2026-08-14) : vérifier que le PID stocké est bien rofi — un PID
# réutilisé après relogin (kill -0 répond « vivant » à tort) tuerait un innocent.
_pid="$(cat "$PIDFILE" 2>/dev/null || true)"
if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null \
    && [ "$(cat "/proc/$_pid/comm" 2>/dev/null)" = "rofi" ]; then
    kill "$_pid" 2>/dev/null
    rm -f "$PIDFILE"
    exit 0
fi
rm -f "$PIDFILE"

OUT="$(mktemp)"
# Presse-papier vide → rien à afficher (rofi 2.0 sortirait aussitôt avec
# stdin vide + -no-custom, on dirait « ça marche pas »). Message explicite.
if ! cliphist list | grep -q .; then
    notify-send "Presse-papier" "Historique vide — copie quelque chose d'abord" -t 2000
    rm -f "$OUT"
    exit 0
fi
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
