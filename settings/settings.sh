#!/usr/bin/env bash
# Sasquatch Settings - toggle launcher (même pattern que cc/cc.sh)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIDFILE="/tmp/sasquatch-settings-server.pid"
LOGFILE="/tmp/sasquatch-settings-server.log"
WIN_TITLE="Sasquatch Settings"

is_alive() {
    curl -s -o /dev/null -m 1 "http://127.0.0.1:8770/api/health"
}

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

# Toggle OFF: if the Settings window is already open, close it.
if window_open; then
    hyprctl dispatch closewindow "title:^($WIN_TITLE)$" >/dev/null 2>&1
    exit 0
fi

# Clean up orphaned quickshell instances of this panel.
pkill -f "quickshell.*settings/main.qml" >/dev/null 2>&1 || true

# Start backend server if not already alive.
if ! is_alive; then
    nohup python3 "$SCRIPT_DIR/settings.py" >"$LOGFILE" 2>&1 &
    echo $! > "$PIDFILE"
fi

# Wait for the server to answer (max ~6s).
server_up=0
for i in $(seq 1 30); do
    if curl -s -o /dev/null -m 1 "http://127.0.0.1:8770/api/health"; then
        server_up=1
        break
    fi
    sleep 0.2
done

if [ "$server_up" -ne 1 ]; then
    notify-send "Sasquatch Settings" "Serveur injoignable (port 8770) — panneau non lancé" -t 3000
    exit 1
fi

quickshell -p "$SCRIPT_DIR/main.qml"
