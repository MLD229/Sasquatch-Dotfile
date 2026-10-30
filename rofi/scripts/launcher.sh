#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Sasquatch · Launcher rofi (mode combi : applis + calculatrice)
#  Une seule instance. La calculatrice est le modi NATIF « calc »
#  (plugin rofi-calc) : le résultat s'affiche PENDANT la frappe.
#    · sélectionner une app     → elle se lance (drun)
#    · sélectionner un résultat → il part dans le presse-papier
#
#  Pourquoi un plugin et pas un mode script : rofi 2.0 n'appelle un mode
#  script qu'AU DÉMARRAGE (rofi-script(5)) → aucun recalcul pendant la
#  frappe. Seul un modi natif (plugin) recalcule à chaque touche.
#
#  Le plugin est CHERCHE, pas suppose : paquet `rofi-calc` (→ /usr/lib/rofi)
#  ou extraction locale (~/.local/lib/rofi). S'il est absent, le lanceur
#  s'ouvre quand meme, en apps seules : une machine fraiche ne doit jamais
#  se retrouver sans lanceur parce qu'un plugin manque.
# ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME="$SCRIPT_DIR/../themes/sasquatch.rasi"

# qalc vit dans /usr/sbin, absent du PATH d'une session Hyprland :
# sans ça le plugin ne calcule rien (liste vide).
export PATH="/usr/sbin:/sbin:$PATH"

# ── plugin calc : premier dossier qui contient vraiment libcalc.so ────────
PLUGIN_DIR=""
for d in /usr/lib/rofi "$HOME/.local/lib/rofi" "/usr/lib64/rofi"; do
    if [ -f "$d/libcalc.so" ]; then
        PLUGIN_DIR="$d"
        break
    fi
done

MODI="combi,drun,run,window"
COMBIS="drun"
EXTRA=()
if [ -n "$PLUGIN_DIR" ]; then
    MODI="$MODI,calc"
    COMBIS="drun,calc"
    EXTRA+=(-calc-command "printf '%s' '{result}' | wl-copy")
else
    # une seule fois par session : dire pourquoi la calculatrice est absente
    flag="${XDG_RUNTIME_DIR:-/tmp}/sasquatch-rofi-nocalc.warned"
    if [ ! -e "$flag" ]; then
        command -v notify-send >/dev/null 2>&1 && \
            notify-send -a Rofi "Calculatrice indisponible" \
                "Plugin rofi-calc absent : sudo pacman -S rofi-calc" 2>/dev/null
        : > "$flag" 2>/dev/null
    fi
fi

ARGS=(-show combi -modi "$MODI" -combi-modes "$COMBIS"
      -combi-display-format "{text}"
      -theme "$THEME"
      -show-icons -icon-theme "Papirus-Dark"
      -drun-display-format "{name}"
      -drun-match-fields "name,generic,exec,categories,keywords"
      -no-drun-show-actions
      -display-combi "  Apps"
      -terminal "kitty"
      -no-lazy-grab -sort -sorting-method fzf -matching normal)

[ -n "$PLUGIN_DIR" ] && ARGS+=(-plugin-path "$PLUGIN_DIR")
[ ${#EXTRA[@]} -gt 0 ] && ARGS+=("${EXTRA[@]}")

exec rofi "${ARGS[@]}" "$@"
