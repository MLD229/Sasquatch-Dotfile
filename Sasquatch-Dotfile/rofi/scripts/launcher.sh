#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Sasquatch · Launcher rofi
#  Lance rofi avec le thème blur/arrondi + icônes auto
# ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME="$SCRIPT_DIR/../themes/sasquatch.rasi"

rofi \
    -show drun \
    -theme "$THEME" \
    -show-icons \
    -icon-theme "Papirus-Dark" \
    -drun-display-format "{name}" \
    -display-drun "  Apps" \
    -modi "drun,run,window" \
    -terminal "kitty" \
    -no-lazy-grab \
    "$@"
