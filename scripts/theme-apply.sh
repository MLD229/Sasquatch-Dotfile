#!/bin/bash
# theme-apply.sh — applique la palette du wallpaper à toute l'interface
# Usage : theme-apply.sh [chemin_wallpaper]
#   Sans argument → lit le wallpaper courant dans ~/.config/waypaper/config.ini
# Hook : post_command de waypaper (remplace $wallpaper) + appel direct au login.
set -u

# Verrou : sérialise les applys (login + post_command + switch rapide se chevauchent).
# On ATTEND (flock -w) au lieu de sortir : si deux wallpapers sont appliqués en
# rafale, le second attend que le premier finisse puis applique le sien — avec
# l'ancien `flock -n || exit 0` le dernier choix était perdu (jamais appliqué).
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

# Skip si la palette n'a pas changé ET que la barre tourne déjà (même wallpaper
# appliqué précédemment — évite de refaire palette + rechargements à chaque
# login). Le fichier $RUNDIR/sasquatch-theme-last est écrit après chaque apply.
# NB : skip keyé sur le chemin, pas le contenu (ré-export du même nom = skip —
# edge case accepté).
LAST="$RUNDIR/sasquatch-theme-last"

# v4 (2026-10-31) : le skip regardait un waybar vivant. Waybar n'est plus la
# barre de la session (barre verticale Quickshell, service sasquatch-bar) : la
# condition teste maintenant QUICKSHELL. Un processus d'une session morte
# (relogin/crash) est vivant pour pgrep mais invisible à l'écran → on exige la
# même signature d'instance Hyprland, sinon la nouvelle session resterait sans
# palette (le skip croirait la barre déjà là).
bar_current_session() {
    local inst="${HYPRLAND_INSTANCE_SIGNATURE:-}" pid sig
    [ -n "$inst" ] || return 1
    for pid in $(pgrep -x quickshell 2>/dev/null); do
        sig=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p' | head -1)
        [ "$sig" = "$inst" ] && return 0
    done
    return 1
}

if [ -f "$WALL" ] && [ "$WALL" = "$(cat "$LAST" 2>/dev/null)" ] && bar_current_session; then
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

# Waybar — DÉFINITIVEMENT MORTE : la barre verticale Quickshell (cc/bar) la
# remplace. 2026-11-24 (lot « installation neutre ») : les DEUX branches qui
# pouvaient (re)démarrer waybar ont été supprimées ici. Elles se déclenchaient
# dès que le lien ~/.config/systemd/user/sasquatch-bar.service manquait
# (installation interrompue, --no-packages, install antérieure à la migration)
# et faisaient `systemctl --user start waybar` ou `waybar &` : deux barres à
# l'écran, dont une que plus rien ne thème et dont les modules ne répondent pas.
# Ce script ne fait plus qu'ARRÊTER waybar si elle traîne. Le retour arrière
# reste documenté (cc/bar/README §8 : `systemctl --user enable --now waybar`).
if systemctl --user is-active --quiet waybar 2>/dev/null; then
    systemctl --user stop waybar >/dev/null 2>&1 || true
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
