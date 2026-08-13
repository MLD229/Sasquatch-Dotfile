#!/usr/bin/env bash
# Sasquatch Control Center - toggle launcher
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIDFILE="/tmp/sasquatch-cc-server.pid"
LOGFILE="/tmp/sasquatch-cc-server.log"
WIN_TITLE="Sasquatch CC"

is_alive() {
    [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
}

# Toggle OFF: if the CC window is already open, close it.
if hyprctl clients -j 2>/dev/null | grep -q "\"$WIN_TITLE\""; then
    hyprctl dispatch closewindow "title:^($WIN_TITLE)$" >/dev/null 2>&1
    exit 0
fi

# Clean up orphaned quickshell instances of this panel.
pkill -f "quickshell.*cc/main.qml" >/dev/null 2>&1 || true

# Start backend server if not already alive.
if ! is_alive; then
    nohup python3 "$SCRIPT_DIR/server.py" >"$LOGFILE" 2>&1 &
    echo $! > "$PIDFILE"
fi

# Wait for the server to answer (max ~6s).
for i in $(seq 1 30); do
    if curl -s -o /dev/null -m 1 "http://127.0.0.1:8765/api/stats"; then
        break
    fi
    sleep 0.2
done

quickshell -p "$SCRIPT_DIR/main.qml"
