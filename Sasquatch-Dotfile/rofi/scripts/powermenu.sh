#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Sasquatch · Power Menu
#  Menu d'alimentation avec icônes Nerd Font
# ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME="$SCRIPT_DIR/../themes/sasquatch.rasi"

# Options
SHUTDOWN="󰐥  Éteindre"
REBOOT="󰜉  Redémarrer"
SUSPEND="󰤄  Veille"
LOGOUT="󰍃  Déconnexion"
LOCK="󰌾  Verrouiller"
CANCEL="  Annuler"

# Lancer rofi
CHOICE=$(printf "%s\n%s\n%s\n%s\n%s\n%s" \
    "$LOCK" "$SUSPEND" "$LOGOUT" "$REBOOT" "$SHUTDOWN" "$CANCEL" \
    | rofi -dmenu \
           -theme "$THEME" \
           -p "󰐥  Alimentation" \
           -lines 6 \
           -no-custom \
           "$@")

case "$CHOICE" in
    "$SHUTDOWN")  systemctl poweroff ;;
    "$REBOOT")    systemctl reboot ;;
    "$SUSPEND")   systemctl suspend ;;
    "$LOGOUT")    loginctl terminate-user "$USER" ;;
    "$LOCK")      loginctl lock-session ;;
    *)            exit 0 ;;
esac
