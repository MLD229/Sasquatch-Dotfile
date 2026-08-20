#!/usr/bin/env bash
# Sasquatch Subpage — envoyer la fenêtre courante DANS la sub page (Super+Shift+S)
#
# Comportement (validé momo 2026-08-20) :
#   - la fenêtre active quitte son workspace et part dans special:subpage
#   - si la page est FERMÉE, on l'ouvre automatiquement (sinon la fenêtre
#     serait invisible, cachée dans le scratchpad)
#   - le cadre décoratif doit tourner AVANT le movetoworkspace : il se mappe
#     dans le special workspace via la windowrule rules.conf (cf. subpage.sh)
#
# ⚠️ ORDRE CRITIQUE (cf. subpage.sh) : ne JAMAIS lancer le cadre quand le
# special est OUVERT (le mapping le FERME). Cas couvert ci-dessous :
#   - page fermée + cadre absent → lancer le cadre (mapping safe), PUIS bouger
#   - page ouverte + cadre absent → NE PAS lancer le cadre (bug), bouger direct
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Le special workspace est-il OUVERT sur un moniteur ? (source de vérité :
# `hyprctl monitors -j` → champ specialWorkspace — PAS activeworkspace)
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

# Fenêtre active : titre + workspace
active_info() {
    hyprctl activewindow -j 2>/dev/null || echo "{}"
}

# Pousser TOUS les cadres « Sasquatch Subpage » en bas de la pile z.
# L'ouverture du special re-z-order le cadre (float) AU-DESSUS des apps
# tiled → il les cache (« on ne voit pas les fenêtres »). À appeler APRÈS
# chaque toggle/movetoworkspace (jamais avant : il ferme le special).
push_frame_down() {
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
}

# Le cadre tourne-t-il ? Détection par FENÊTRE (hyprctl clients), PAS par
# pgrep (un chemin relatif échappe au pattern — leçon 2026-08-20).
frame_exists() {
    hyprctl clients -j 2>/dev/null | grep -q '"title": "Sasquatch Subpage"'
}

active_title="$(active_info | python3 -c "import json,sys; print(json.load(sys.stdin).get('title',''))" 2>/dev/null)"
active_ws="$(active_info | python3 -c "import json,sys; print((json.load(sys.stdin).get('workspace') or {}).get('name',''))" 2>/dev/null)"

# Garde-fous : ne pas bouger le cadre lui-même, ni une fenêtre déjà dedans
if [ "$active_title" = "Sasquatch Subpage" ]; then
    exit 0
fi
if [ "$active_ws" = "special:subpage" ]; then
    exit 0
fi

if special_open; then
    # Page ouverte → bouger direct (le cadre est censé tourner ; s'il est
    # absent, on ne le lance PAS ici : mapping sur special ouvert = fermeture)
    hyprctl dispatch movetoworkspace special:subpage >/dev/null 2>&1
    push_frame_down
else
    # Page fermée → s'assurer que le cadre tourne (mapping safe), PUIS bouger
    # la fenêtre (elle se cache dans le scratchpad), PUIS ouvrir la page.
    # ⚠️ ATTENDRE le mapping RÉEL de la fenêtre (pas un sleep fixe) : un
    # premier démarrage quickshell peut prendre 5-10 s (cf. subpage.sh).
    if ! frame_exists; then
        quickshell -p "$SCRIPT_DIR/main.qml" >/dev/null 2>&1 &
        for _ in $(seq 1 30); do
            if frame_exists; then
                break
            fi
            sleep 0.4
        done
    fi
    hyprctl dispatch movetoworkspace special:subpage >/dev/null 2>&1
    hyprctl dispatch togglespecialworkspace subpage >/dev/null 2>&1
    push_frame_down
fi
exit 0
