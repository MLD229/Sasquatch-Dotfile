#!/bin/bash
# scroll-workspace.sh — change de workspace en bloquant entre 1 et 10.
# Usage : scroll-workspace.sh up|down
direction=$1
current=$(hyprctl activeworkspace -j | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

if [ "$direction" = "up" ] && [ "$current" -lt 10 ]; then
    hyprctl dispatch workspace r+1
elif [ "$direction" = "down" ] && [ "$current" -gt 1 ]; then
    hyprctl dispatch workspace r-1
fi
