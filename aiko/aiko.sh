#!/usr/bin/env bash
# 愛子 (Aiko) — toggle launcher (Super+N).
#
# Mode lazy : rien ne tourne quand la sidebar est fermée.
#  - Super+N → lance server.py (backend 8780) + quickshell main.qml
#  - server.py démarre llama-server (8781) à l'ouverture
#  - Fermeture (Escape / clic dehors) → QML POST /api/close →
#    server.py arrête llama-server puis meurt → 0 conso en idle
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIN_TITLE="Aiko"
PORT=8780

# Détection fenêtre robuste (parse hyprctl JSON — grep échoue sur sortie vide)
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

# Toggle OFF : la fenêtre est déjà ouverte → la fermer
if window_open; then
    hyprctl dispatch closewindow "title:^($WIN_TITLE)$" >/dev/null 2>&1
    # Arrêt lazy complet : backend → llama-server → 0 conso
    curl -s -X POST -m 2 "http://127.0.0.1:$PORT/api/close" >/dev/null 2>&1 || true
    # Tue les quickshell de ce panel si encore vivants (fenêtre close ≠ process mort)
    pkill -f "[q]uickshell.*aiko/main.qml" >/dev/null 2>&1 || true
    exit 0
fi

# Nettoyage des quickshell orphelins de CE panel (pattern qui ne matche pas le shell)
pkill -f "[q]uickshell.*aiko/main.qml" >/dev/null 2>&1 || true

# Démarre le backend si pas déjà actif (idempotent)
if ! curl -s -o /dev/null -m 1 "http://127.0.0.1:$PORT/api/health"; then
    # Vérifie le setup (modèle présent) avant de lancer
    MODEL_FILE=$(python3 -c "import json; print(json.load(open('$SCRIPT_DIR/config.json'))['model']['model_file'])" 2>/dev/null)
    if [ -n "$MODEL_FILE" ] && [ ! -f "$SCRIPT_DIR/models/$MODEL_FILE" ]; then
        notify-send "愛子" "Modèle absent : $MODEL_FILE — lance : bash $SCRIPT_DIR/setup.sh" -t 4000
        exit 1
    fi
    python3 "$SCRIPT_DIR/server.py" --port "$PORT" >>"$SCRIPT_DIR/server.log" 2>&1 &
fi

# Attend que le backend réponde (max ~6s)
server_up=0
for i in $(seq 1 30); do
    if curl -s -o /dev/null -m 1 "http://127.0.0.1:$PORT/api/health"; then
        server_up=1
        break
    fi
    sleep 0.2
done

if [ "$server_up" -ne 1 ]; then
    notify-send "愛子" "Backend injoignable (port $PORT) — vérifie server.py" -t 3000
    exit 1
fi

# Positionne la fenêtre à gauche (multi-résolution) :
# `move 100%-N` ne fonctionne pas avec match:title (bug Hyprland 0.56) →
# on injecte la règle avec la valeur absolue calculée AVANT de créer la fenêtre.
WIN_W=420
MON_W=$(hyprctl monitors -j | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['width'])" 2>/dev/null || echo 1920)
X=16   # 16px de marge à gauche
hyprctl keyword "windowrule" "match:title ^(Aiko)$, move $X 62" >/dev/null 2>&1

# Lance la sidebar
quickshell -p "$SCRIPT_DIR/main.qml"
