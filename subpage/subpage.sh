#!/usr/bin/env bash
# Sasquatch Subpage — toggle la sub page (scratchpad Hyprland, Super+S)
#
# La « sub page » est un special workspace Hyprland (scratchpad natif) :
#   hyprctl dispatch togglespecialworkspace subpage
# Les apps lancées pendant que la page est active s'y ouvrent (workspace
# actif) ; re-Super+S → le special workspace se cache, les apps restent
# ouvertes dans la page.
#
# Le cadre décoratif (subpage/main.qml, fenêtre transparente à contour
# arrondi) vit DANS le special workspace via la windowrule rules.conf
# (`workspace special:subpage silent`).
#
# ⚠️ ORDRE CRITIQUE (2026-08-20, testé) : mapper une fenêtre avec la
# windowrule `workspace special:subpage silent` pendant que le special est
# OUVERT le FERME (comportement Hyprland observé 2×). Donc : le cadre doit
# être mappé AVANT d'ouvrir le special — jamais après.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Le special workspace est-il OUVERT sur un moniteur ?
# ⚠️ NE PAS tester `hyprctl activeworkspace` : il montre le workspace du
# moniteur (いち, に...), JAMAIS special:subpage. Source de vérité :
# `hyprctl monitors -j` → champ specialWorkspace.
special_open() {
    python3 - <<'EOF'
import json, subprocess, sys
try:
    out = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=3)
    for m in json.loads(out.stdout):
        sw = m.get("specialWorkspace") or {}
        if sw.get("name") == "special:subpage":
            sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
EOF
}

if special_open; then
    # Page ouverte → fermer le special workspace (le cadre reste vivant,
    # caché dedans — il n'y a aucun mapping à ce moment)
    hyprctl dispatch togglespecialworkspace subpage >/dev/null 2>&1
    exit 0
fi

# Page fermée → s'assurer que le cadre tourne (le mapping se fait avec le
# special FERMÉ : la fenêtre se cache dedans), PUIS ouvrir le special.
#
# ⚠️ Détection par FENÊTRE (hyprctl clients), PAS par pgrep : un quickshell
# lancé avec un chemin relatif (`quickshell -p main.qml` depuis subpage/) ne
# matche pas un pgrep `[q]uickshell.*subpage/main.qml` → on relançait un
# SECOND cadre (bug 2026-08-20 : « on ne voit pas les fenêtres » — le 2e
# cadre fullscreen flottait AU-DESSUS des apps tiled et les masquait).
frame_exists() {
    hyprctl clients -j 2>/dev/null | grep -q '"title": "Sasquatch Subpage"'
}
if ! frame_exists; then
    quickshell -p "$SCRIPT_DIR/main.qml" >/dev/null 2>&1 &
    # ⚠️ ATTENDRE le mapping RÉEL de la fenêtre (pas un sleep fixe) :
    # un premier démarrage quickshell peut prendre 5-10 s ; si on toggles le
    # special avant que la fenêtre ne soit mappée, elle se mappe avec le
    # special OUVERT → elle le FERME (piège ordre critique documenté).
    for _ in $(seq 1 30); do
        if frame_exists; then
            break
        fi
        sleep 0.4
    done
fi

# 🔻 Le cadre doit TOUJOURS être EN DESSOUS des apps du special workspace.
# Sans ça, la FloatingWindow fullscreen passe au-dessus des apps tiled :
# elle les cache (fond opaque), bloque les clics (« ça ne s'active pas »)
# et monte jusqu'à la waybar. On force TOUS les cadres en bas de pile z à
# chaque toggle (un cadre doublon laissé au-dessus = même bug).
for frame_addr in $(hyprctl clients -j 2>/dev/null | python3 -c "
import json, sys
try:
    for c in json.load(sys.stdin):
        if c.get('title') == 'Sasquatch Subpage':
            print(c.get('address', ''))
except Exception:
    pass
"); do
    [ -n "$frame_addr" ] && hyprctl dispatch alterzorder bottom "$frame_addr" >/dev/null 2>&1
done

hyprctl dispatch togglespecialworkspace subpage >/dev/null 2>&1
exit 0
