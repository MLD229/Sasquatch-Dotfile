#!/bin/bash
# apply-lang.sh — applique la langue mémorisée (settings.json → lang.mode) à l'UI.
#
#   Waybar     : copie la config de la langue (config = FR, config.ja = 日本語)
#                puis redémarre waybar. Si le service systemd user waybar est
#                installé, c'est LUI le lanceur (un `waybar &` direct donnerait
#                2 barres) — restart/start via systemctl, fallback direct sinon.
#   Workspaces : hyprctl dispatch renameworkspace 1..10 (noms JA ou numéros FR),
#                sans déplacer les fenêtres.
#   wallclock / hyprlock / clock-ja : NON redémarrés — ils relisent
#                settings.json à chaque tick/exécution.
#
# Appelé par : settings.py (toggle du panneau Super+I) et autostart.sh (login).
set -u

SETTINGS_JSON="$HOME/.config/settings/settings.json"
WAYBAR_DIR="$HOME/.config/waybar"
CONFIG_ACTIVE="$WAYBAR_DIR/config"     # fichier lu par waybar (copie de la langue)
CONFIG_FR="$WAYBAR_DIR/config.fr"      # source française
CONFIG_JA="$WAYBAR_DIR/config.ja"      # source japonaise

# Langue mémorisée : "ja" par défaut (état actuel du système).
LANG_MODE=$(python3 - "$SETTINGS_JSON" <<'EOF'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    mode = (data or {}).get("lang", {}).get("mode")
    print(mode if mode in ("ja", "fr") else "ja")
except Exception:
    print("ja")
EOF
)

# ── Workspaces : rename à chaud (sans déplacer les fenêtres) ──
# JA : lectures hiragana (règles rules.conf au boot, re-renommés ici selon la
# langue mémorisée) ; FR : numéros. `dispatch` est la syntaxe 0.56
# (`hyprctl renameworkspace` = "unknown request").
# ⚠️ ORDRE : renommer AVANT le redémarrage waybar — si waybar est (re)démarré
# avant le rename, il garde les anciens noms en cache et ne suit pas le
# changement (bug observé : noms JA affichés alors que hyprctl dit FR).
if [ "$LANG_MODE" = "ja" ]; then
    NAMES=(いち に さん よん ご ろく なな はち きゅう じゅう)
else
    NAMES=(1 2 3 4 5 6 7 8 9 10)
fi
for i in $(seq 1 10); do
    hyprctl dispatch renameworkspace "$i" "${NAMES[$((i - 1))]}" >/dev/null 2>&1
done

# ── Waybar : config de la langue + redémarrage ────────────────
# config = fichier ACTIF ; config.fr / config.ja = sources des deux langues.
# À chaque toggle : si l'actif est de l'AUTRE langue, on le sauvegarde dans
# sa source (les patchs /api/clock de settings.py s'appliquent aux sources),
# puis on copie la source de la langue choisie vers l'actif.
CHANGED=0
if [ "$LANG_MODE" = "ja" ]; then
    if [ ! -f "$CONFIG_JA" ]; then
        notify-send "Sasquatch" "Langue 日本語 : waybar/config.ja introuvable" -u critical 2>/dev/null || true
        exit 1
    fi
    if ! cmp -s "$CONFIG_ACTIVE" "$CONFIG_JA"; then
        # Back-sync garde-fou : n'écraser la source FR que si l'actif est
        # vraiment la config FR (label connu), pas un fichier stale quelconque.
        grep -q "Batterie" "$CONFIG_ACTIVE" 2>/dev/null && cp -f "$CONFIG_ACTIVE" "$CONFIG_FR"
        cp -f "$CONFIG_JA" "$CONFIG_ACTIVE"
        CHANGED=1
    fi
else
    if [ ! -f "$CONFIG_FR" ]; then
        notify-send "Sasquatch" "Langue Français : waybar/config.fr introuvable" -u critical 2>/dev/null || true
        exit 1
    fi
    if ! cmp -s "$CONFIG_ACTIVE" "$CONFIG_FR"; then
        grep -q "でんち" "$CONFIG_ACTIVE" 2>/dev/null && cp -f "$CONFIG_ACTIVE" "$CONFIG_JA"
        cp -f "$CONFIG_FR" "$CONFIG_ACTIVE"
        CHANGED=1
    fi
fi

if [ "$CHANGED" = "1" ]; then
    if systemctl --user is-active --quiet waybar; then
        # Config changée (labels) : un simple `reload` (SIGUSR2) ne recharge que le
        # CSS → restart complet (relit aussi les noms de workspaces renommés).
        systemctl --user restart waybar >/dev/null 2>&1 || true
    elif systemctl --user list-unit-files waybar.service >/dev/null 2>&1; then
        systemctl --user start waybar >/dev/null 2>&1 || true
    else
        # Service non installé → fallback direct (ancien comportement).
        pkill -x waybar 2>/dev/null
        sleep 0.2
        waybar >/dev/null 2>&1 &
    fi
    if [ "$LANG_MODE" = "ja" ]; then
        notify-send "Sasquatch" "Langue : 日本語" 2>/dev/null || true
    else
        notify-send "Sasquatch" "Langue : Français" 2>/dev/null || true
    fi
fi

exit 0
