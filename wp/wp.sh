#!/usr/bin/env bash
# Sasquatch Wallpaper Picker — toggle launcher (Quickshell, Super+Y).
#
# Remplace waypaper comme outil de changement de wallpaper. Backend = serveur
# CC (sasquatch-cc, port 8765) : /api/wallpapers (liste), /api/wallpaper/apply
# (waypaper --restore → theme-apply.sh → toute la palette suit), /api/wallpaper/
# pick (zenity dossier/fichier). L'UI suit la palette du thème.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIN_TITLE="Sasquatch Wallpaper"

# Détection robuste de fenêtre : parse du JSON hyprctl avec python
# (grep échoue sur sortie vide/erronée).
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

# Toggle OFF : si la fenêtre est déjà ouverte, la fermer.
if window_open; then
    hyprctl dispatch closewindow "title:^($WIN_TITLE)$" >/dev/null 2>&1
    exit 0
fi

# Purge des instances quickshell orphelines de ce panneau.
pkill -f "[q]uickshell.*wp/main.qml" >/dev/null 2>&1 || true

# Garantir le serveur backend (service systemd user, idempotent).
if ! systemctl --user is-active --quiet sasquatch-cc; then
    systemctl --user start sasquatch-cc
fi

# Attente de la réponse du serveur (max ~6s).
server_up=0
for i in $(seq 1 30); do
    if curl -s -o /dev/null -m 1 "http://127.0.0.1:8765/api/stats"; then
        server_up=1
        break
    fi
    sleep 0.2
done

if [ "$server_up" -ne 1 ]; then
    notify-send "Wallpaper" "Serveur injoignable (port 8765) — logs : journalctl --user -u sasquatch-cc" -t 3000
    exit 1
fi

quickshell -p "$SCRIPT_DIR/main.qml"
