#!/bin/bash
# wallpaper.sh — lance hyprpaper/waypaper proprement au login.
#
# Pourquoi ce script :
#   hyprpaper se connecte à l'INSTANCE hyprland qui tourne au moment où il est
#   lancé (socket $XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.hyprpaper.sock).
#   Si un hyprpaper d'une session précédente traîne encore (restart hyprland sans
#   logout complet, crash, etc.), waypaper --restore le voit via `pgrep hyprpaper`
#   et NE LE RELANCE PAS → l'IPC `hyprctl hyprpaper ...` part sur la session
#   courante où personne n'écoute → "invalid hyprpaper request" → fond d'écran noir,
#   alors que la palette (post_command) fonctionne encore. Symptôme exact du bug
#   2026-08-14.
#
#   Fix : tuer TOUT hyprpaper AVANT de laisser waypaper en démarrer un neuf dans
#   la session courante.
set -u

pkill -x hyprpaper 2>/dev/null
# Boucle bornée : pkill est asynchrone — si l'orphelin met >0.3 s à mourir,
# waypaper le verrait encore vivant (pgrep) et ne relancerait rien → fond noir
# intermittent. On attend la mort réelle (max 2 s), on continue sinon.
for _ in $(seq 1 20); do
    pgrep -x hyprpaper >/dev/null 2>&1 || break
    sleep 0.1
done

# waypaper --restore relit config.ini, lance hyprpaper si absent (il vient d'être
# tué, donc il le relance) et applique le wallpaper via IPC. Le post_command
# (~/.config/scripts/theme-apply.sh) est déclenché par waypaper lui-même.
waypaper --restore >/dev/null 2>&1 &

exit 0
