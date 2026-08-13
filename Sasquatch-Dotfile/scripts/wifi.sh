#!/bin/bash
# scripts/wifi.sh — WiFi via iwd (iwctl) + systemd-networkd

DEV="wlan0"

case $1 in
    toggle)
        if iwctl device "$DEV" show | grep -q "Powered on"; then
            iwctl device "$DEV" set-property Powered off
            notify-send "WiFi" "Désactivé" -i network-wireless-off -t 2000
        else
            iwctl device "$DEV" set-property Powered on
            notify-send "WiFi" "Activé" -i network-wireless -t 2000
        fi
    ;;
    status)
        SSID=$(iwctl station "$DEV" show 2>/dev/null | grep "Connected network" | awk '{print $NF}')
        notify-send "WiFi" "${SSID:-Aucun réseau connecté}" -t 2000
    ;;
    menu)
        kitty --title "iwctl" -e iwctl &
    ;;
    *)
        echo "Usage: $0 {toggle|status|menu}" >&2
    ;;
esac
