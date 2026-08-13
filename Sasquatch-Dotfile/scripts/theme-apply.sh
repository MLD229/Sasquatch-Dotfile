#!/bin/bash
# theme-apply.sh — applique la palette du wallpaper à toute l'interface
# Usage : theme-apply.sh [chemin_wallpaper]
#   Sans argument → lit le wallpaper courant dans ~/.config/waypaper/config.ini
# Hook : post_command de waypaper (remplace $wallpaper) + appel direct au login.
set -u

# Verrou : une seule application à la fois (login + post_command peuvent se chevaucher)
exec 9>/tmp/sasquatch-theme.lock
flock -n 9 || exit 0

REPO="${HOME}/.config"
SCRIPT_DIR="$REPO/scripts"

WALL="${1:-}"
if [ -z "$WALL" ] || [ ! -f "$WALL" ]; then
    RAW=$(grep -m1 '^wallpaper' "$HOME/.config/waypaper/config.ini" 2>/dev/null | sed 's/^[^=]*= *//')
    case "$RAW" in
        "~"*) WALL="$HOME${RAW#\~}" ;;
        *)    WALL="$RAW" ;;
    esac
fi

if [ ! -f "$WALL" ]; then
    echo "theme-apply: wallpaper introuvable ($WALL)" >&2
    exit 1
fi

if ! python3 "$SCRIPT_DIR/theme-apply.py" "$WALL"; then
    notify-send "Thème" "Échec de l'application de la palette" -t 2000 2>/dev/null
    exit 1
fi

# ── Rechargements ──────────────────────────────
# Hyprland (bordures)
hyprctl reload >/dev/null 2>&1

# Waybar (CSS) — démarre ou relance systématiquement (nouveau thème = nouveau CSS)
# 9>&- : ne pas laisser waybar hériter du fd de verrou (flock serait tenu à vie)
pkill -x waybar 2>/dev/null
sleep 0.2
waybar >/dev/null 2>&1 9>&- &

# Mako (notifications)
if command -v makoctl >/dev/null 2>&1; then
    makoctl reload >/dev/null 2>&1
fi

# Kitty (instances en cours)
KITTYC=/tmp/sasquatch-palette-kitty.conf
if [ -f "$KITTYC" ] && command -v kitty >/dev/null 2>&1; then
    kitty @ set-colors -a "$KITTYC" >/dev/null 2>&1
fi

notify-send -h string:x-canonical-private-synchronous:theme "Thème" "Palette appliquée — $(basename "$WALL")" -t 1500 2>/dev/null 9>&-
echo "theme-apply: OK ($WALL)"
exit 0
