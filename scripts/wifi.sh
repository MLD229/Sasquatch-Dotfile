#!/bin/bash
# scripts/wifi.sh — WiFi via iwd (iwctl) + systemd-networkd
# UTILITAIRE NON BINDÉ : usage manuel (terminal) — {toggle|status|menu}.
# La stack réseau est iwd + systemd-networkd (PAS NetworkManager).
set -u

cmd="${1:-}"

# Guard : iwctl absent (requirements iwd) → message clair
if ! command -v iwctl >/dev/null 2>&1; then
    notify-send "WiFi" "iwctl introuvable — installe iwd" -t 3000 2>/dev/null
    exit 1
fi

# Détection auto de l'interface sans fil (override via WIFI_DEV)
DEV="${WIFI_DEV:-$(ls /sys/class/net 2>/dev/null | grep '^wl' | head -1)}"
DEV="${DEV:-wlan0}"

case $cmd in
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
