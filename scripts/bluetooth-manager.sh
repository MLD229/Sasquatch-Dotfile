#!/bin/bash
# bluetooth-manager.sh — toggle blueman-manager (Super+B)
#
# PIÈGE CONNU (2026-08-16) : blueman-manager crashe au lancement ~80% du temps
# quand le scan BLE est actif (rafales de discovery générant des devices
# fantômes qui apparaissent/disparaissent). Le manager reçoit un signal d'ajout
# pour un objet DBus déjà mort → DBusUnknownObjectError dans DeviceList.py.
#   Symptôme : Super+B ne « marche pas » (fenêtre jamais visible).
#   Quand le scan est off : 6/6 lancements OK. Fix : relancer jusqu'à 5× si le
#   process meurt dans les 2 premières secondes (la fenêtre finit par s'ouvrir).

if pgrep -x blueman-manager >/dev/null; then
    # toggle OFF : fermer la fenêtre
    pkill -x blueman-manager
    exit 0
fi

# toggle ON : lancer avec retry anti-crash (crash pendant l'init, ≤2s)
for i in 1 2 3 4 5; do
    blueman-manager &
    sleep 2
    if pgrep -x blueman-manager >/dev/null; then
        exit 0
    fi
done
exit 0
