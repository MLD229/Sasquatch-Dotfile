#!/bin/bash
direction=$1
current=$(hyprctl activeworkspace -j | jq '.id')

if [ "$direction" = "up" ] && [ "$current" -lt 10 ]; then
    hyprctl dispatch workspace r+1
elif [ "$direction" = "down" ] && [ "$current" -gt 1 ]; then
    hyprctl dispatch workspace r-1
fi
