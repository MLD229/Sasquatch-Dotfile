#!/usr/bin/env bash
# Sasquatch Playlist — toggle launcher (Quickshell, Super+P)
#
# Gestionnaire de playlist MPD (panneau « Sasquatch Playlist »). Backend =
# serveur CC (sasquatch-cc, port 8765) : /api/playlist/status (toggles
# random/repeat/single), /api/playlist/list (playlist courante), /api/playlist/
# library (recherche bibliothèque), /api/playlist/load (🎲 tout en aléatoire),
# /api/playlist/pick (zenity dossier). L'UI suit la palette du thème.
#
# Lancé par le keybind Super+P (env Hyprland complet) OU par le bouton du CC
# (POST /api/playlist/open → le serveur lance ce script SANS signature) → on
# auto-détecte l'instance Hyprland courante si absente de l'environnement.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIN_TITLE="Sasquatch Playlist"

# Instance Hyprland : requise pour hyprctl. Sous un keybind elle est déjà là ;
# depuis le serveur (service systemd user) il faut la retrouver dans /run/user.
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    sig=$(ls -t "/run/user/$(id -u)/hypr/" 2>/dev/null | head -1)
    if [ -n "$sig" ]; then
        export HYPRLAND_INSTANCE_SIGNATURE="$sig"
    fi
fi

# Robust window detection: parse hyprctl JSON with python (grep fails on empty/errored output).
window_open() {
    python3 - "$WIN_TITLE" <<'EOF'
import json, subprocess, sys
title = sys.argv[1]
try:
    out = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=3)
    data = json.loads(out.stdout)
    sys.exit(0 if any(title in (c.get("title") or "") for c in data) else 1)
except Exception:
    sys.exit(1)
EOF
}

# Toggle OFF: if the window is already open, close it.
if window_open; then
    hyprctl dispatch closewindow "title:^($WIN_TITLE)$" >/dev/null 2>&1
    exit 0
fi

# Clean up orphaned quickshell instances of this panel.
pkill -f "quickshell.*pl/main.qml" >/dev/null 2>&1 || true

# Garantir le serveur backend (service systemd user, idempotent).
if ! systemctl --user is-active --quiet sasquatch-cc; then
    systemctl --user start sasquatch-cc
fi

# Wait for the server to answer (max ~6s).
server_up=0
for i in $(seq 1 30); do
    if curl -s -o /dev/null -m 1 "http://127.0.0.1:8765/api/stats"; then
        server_up=1
        break
    fi
    sleep 0.2
done

if [ "$server_up" -ne 1 ]; then
    notify-send "Playlist" "Serveur injoignable (port 8765) — logs : journalctl --user -u sasquatch-cc" -t 3000
    exit 1
fi

# Positionne la fenêtre à DROITE, sous waybar (multi-résolution) :
# ⚠️ `move 100%-N` ne marche PAS avec match:title (bug Hyprland 0.56) →
# on injecte la règle avec la valeur absolue calculée AVANT de créer la fenêtre.
WIN_W=900
MON_W=$(hyprctl monitors -j | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['width'])" 2>/dev/null || echo 1920)
X=$((MON_W - WIN_W - 16))   # 16px de marge à droite
hyprctl keyword "windowrule" "match:title ^(Sasquatch Playlist)$, move $X 62" >/dev/null 2>&1

# Lance le panneau
quickshell -p "$SCRIPT_DIR/main.qml"
