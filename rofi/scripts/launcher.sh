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
# ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME="$SCRIPT_DIR/../themes/sasquatch.rasi"
# Plugin rofi-calc (paquet officiel « extra ») extrait sans root ici.
PLUGIN_DIR="$HOME/.local/lib/rofi"

# qalc vit dans /usr/sbin, absent du PATH d'une session Hyprland :
# sans ça le plugin ne calcule rien (liste vide).
export PATH="/usr/sbin:/sbin:$PATH"

exec rofi \
    -plugin-path "$PLUGIN_DIR" \
    -show combi \
    -modi "combi,drun,run,window,calc" \
    -combi-modes "drun,calc" \
    -combi-display-format "{text}" \
    -theme "$THEME" \
    -show-icons \
    -icon-theme "Papirus-Dark" \
    -drun-display-format "{name}" \
    -drun-match-fields "name,generic,exec,categories,keywords" \
    -no-drun-show-actions \
    -display-combi "  Apps" \
    -terminal "kitty" \
    -no-lazy-grab \
    -sort \
    -sorting-method fzf \
    -matching normal \
    -calc-command "printf '%s' '{result}' | wl-copy" \
    "$@"
