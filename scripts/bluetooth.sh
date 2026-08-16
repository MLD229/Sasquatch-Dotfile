#!/bin/bash
# scripts/bluetooth.sh — toggle Bluetooth rapide (bluetoothctl, CLI pure)
# UTILITAIRE NON BINDÉ : Super+B passe par bluetooth-manager.sh (UI blueman,
# wrapper anti-crash scan BLE). Ce script reste dispo pour la CLI.
set -u

cmd="${1:-}"

# Guard : bluetoothctl absent (requirements bluez-utils) → message clair
if ! command -v bluetoothctl >/dev/null 2>&1; then
    notify-send "Bluetooth" "bluetoothctl introuvable — installe bluez-utils" -t 3000 2>/dev/null
    exit 1
fi

case $cmd in
    toggle)
        if bluetoothctl show | grep -q "Powered: yes"; then
            bluetoothctl power off
            notify-send "Bluetooth" "Désactivé" -i bluetooth-disabled -t 2000
        else
            bluetoothctl power on
            notify-send "Bluetooth" "Activé" -i bluetooth -t 2000
        fi
    ;;
    status)
        DEV=$(bluetoothctl info | grep "Name" | cut -d: -f2 | xargs)
        notify-send "Bluetooth" "${DEV:-Aucun appareil connecté}" -t 2000
    ;;
    menu)
        blueman-manager &
    ;;
esac
