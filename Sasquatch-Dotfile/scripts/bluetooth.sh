#!/bin/bash
# scripts/bluetooth.sh

case $1 in
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
