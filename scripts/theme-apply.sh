#!/bin/bash
# theme-apply.sh — applique la palette du wallpaper à toute l'interface
# Usage : theme-apply.sh [chemin_wallpaper]
#   Sans argument → lit le wallpaper courant dans ~/.config/waypaper/config.ini
# Hook : post_command de waypaper (remplace $wallpaper) + appel direct au login.
set -u

# Verrou : sérialise les applys (login + post_command + switch rapide se chevauchent).
# On ATTEND (flock -w) au lieu de sortir : si momo switch deux wallpapers vite,
# le second attend que le premier finisse puis applique le sien — avec l'ancien
# `flock -n || exit 0` le dernier choix était PERDU (jamais appliqué).
RUNDIR="${XDG_RUNTIME_DIR:-/tmp}"
exec 9>"$RUNDIR/sasquatch-theme.lock"
if ! flock -w 20 9; then
    # Un apply bloqué ne doit pas avaler silencieusement le nouveau wallpaper.
    notify-send "Thème" "⚠ Apply ignoré (verrou occupé >20 s)" -t 3000 2>/dev/null 9>&-
    exit 0
fi

REPO="${HOME}/.config"
SCRIPT_DIR="$REPO/scripts"

WALL="${1:-}"
if [ -z "$WALL" ] || [ ! -f "$WALL" ]; then
    # Strippe un éventuel préfixe moniteur (façon waypaper) : "eDP-1:~/..." → "~/..."
    RAW=$(grep -m1 '^wallpaper' "$HOME/.config/waypaper/config.ini" 2>/dev/null | sed 's/^[^=]*= *//; s/^[^:~]*://')
    case "$RAW" in
        "~"*) WALL="$HOME${RAW#\~}" ;;
        *)    WALL="$RAW" ;;
    esac
fi

# Skip si la palette n'a pas changé ET que waybar tourne déjà (même wallpaper
# appliqué précédemment — évite pkill+relance waybar à chaque login).
# Le fichier $RUNDIR/sasquatch-theme-last est écrit après chaque apply réussi.
# NB : skip keyé sur le chemin, pas le contenu (ré-export du même nom = skip —
# edge case accepté).
LAST="$RUNDIR/sasquatch-theme-last"

# Un waybar ne compte pour le skip idempotent que s'il appartient à l'instance
# Hyprland COURANTE. Un orphelin d'une session morte (relogin/crash) est vivant
# pour pgrep mais invisible à l'écran → sans ce test, la nouvelle session
# resterait sans barre (le skip penserait que la barre tourne déjà).
waybar_current_session() {
    local inst="${HYPRLAND_INSTANCE_SIGNATURE:-}" pid sig
    [ -n "$inst" ] || return 1
    for pid in $(pgrep -x waybar 2>/dev/null); do
        sig=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p' | head -1)
        [ "$sig" = "$inst" ] && return 0
    done
    return 1
}

if [ -f "$WALL" ] && [ "$WALL" = "$(cat "$LAST" 2>/dev/null)" ] && waybar_current_session; then
    echo "theme-apply: inchangé ($WALL)"
    exit 0
fi

# Palette : theme-apply.py ne sort >0 que si un fichier cible est illisible ou
# absent (atomicité) — sinon il applique toujours quelque chose, y compris la
# palette par défaut quand l'extraction échoue.
# Ne JAMAIS sortir avant les rechargements : waybar est lancé ICI au login.
if [ -f "$WALL" ]; then
    if ! python3 "$SCRIPT_DIR/theme-apply.py" "$WALL"; then
        notify-send "Thème" "⚠ Palette non appliquée (fichier cible absent ?)" -t 3000 2>/dev/null 9>&-
        MSG="Échec palette"
    else
        echo "$WALL" > "$LAST"
        MSG="Palette appliquée — $(basename "$WALL")"
    fi
else
    echo "theme-apply: wallpaper introuvable ($WALL) — palette par défaut" >&2
    python3 "$SCRIPT_DIR/theme-apply.py" 2>/dev/null
    MSG="Palette par défaut (wallpaper introuvable)"
fi

# ── Rechargements ──────────────────────────────
# Hyprland (bordures)
hyprctl reload >/dev/null 2>&1

# Waybar (CSS) — démarre ou relance systématiquement (nouveau thème = nouveau CSS)
# 9>&- : ne pas laisser waybar hériter du fd de verrou (flock serait tenu à vie)
# Supervision : si le service waybar (waybar/waybar.service) est INSTALLÉ, c'est
# LUI le seul lanceur — `systemctl --user start` est idempotent et ne crée PAS de
# doublon, même pendant la course du login (service encore en retry
# Restart=on-failure ; un `waybar &` direct donnerait 2 barres). Fallback direct
# uniquement si le service n'existe pas du tout (install.sh pas relancé).
if systemctl --user is-active --quiet waybar; then
    systemctl --user reload waybar >/dev/null 2>&1 || true
elif systemctl --user list-unit-files waybar.service >/dev/null 2>&1; then
    systemctl --user start waybar >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5; do
        systemctl --user is-active --quiet waybar && break
        sleep 0.3
    done
    systemctl --user reload waybar >/dev/null 2>&1 || true
else
    # Service non installé → fallback direct (ancien comportement).
    pkill -x waybar 2>/dev/null
    sleep 0.2
    waybar >/dev/null 2>&1 9>&- &
fi

# Mako (notifications)
if command -v makoctl >/dev/null 2>&1; then
    makoctl reload >/dev/null 2>&1
fi

# Kitty (instances en cours)
KITTYC="$RUNDIR/sasquatch-palette-kitty.conf"
if [ -f "$KITTYC" ] && command -v kitty >/dev/null 2>&1; then
    kitty @ set-colors -a "$KITTYC" >/dev/null 2>&1
fi

notify-send -h string:x-canonical-private-synchronous:theme "Thème" "$MSG" -t 1500 2>/dev/null 9>&-
echo "theme-apply: OK ($WALL)"
exit 0
