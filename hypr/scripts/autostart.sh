#!/bin/bash
# autostart.sh

# ── Purge orphelins session précédente ───────
# Relogin/crash d'Hyprland → les process de l'ancienne session (waybar, fcitx5,
# mako, polkit, wl-paste...) restent vivants avec leur ancienne signature.
# Invisibles à l'écran, mais ils bloquent les nouveaux (singletons, sockets,
# ports). À purger AVANT tout lancement.
~/.config/hypr/scripts/cleanup-orphans.sh

# ── Wallpaper ────────────────────────────────
# wallpaper.sh tue les hyprpaper orphelins (bug : orphelin d'une session passée
# → waypaper ne le remplace pas → fond noir) puis lance waypaper --restore.
~/.config/hypr/scripts/wallpaper.sh

# ── Bar ──────────────────────────────────────
# waybar est lancé par theme-apply.sh (le thème doit être prêt avant la barre)

# ── Notifications ────────────────────────────
mako &

# ── IME japonais (fcitx5 + mozc) ──────────────
fcitx5 -d &

# ── Polkit ───────────────────────────────────
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

# ── Idle / Lock ──────────────────────────────
# hypridle tourne TOUJOURS : le lock au capot (logind HandleLidSwitch=lock
# → lock-session → lock_cmd → hyprlock) dépend de lui. Si l'idle est
# désactivé via le panneau Settings (Super+I), settings.py écrit un conf
# lock-only (pas de timeouts de veille) mais hypridle reste lancé.
hypridle &

# ── Lecteur MPD (CC musique + finder) ────────
# Service user normalement activé par install.sh ; ce start est un filet de
# sécurité (sans effet si déjà lancé).
systemctl --user start mpd 2>/dev/null &

# File vide au boot : MPD restaure la queue depuis state_file → FLUXO restait
# scotchée en pause (repeat on + file à 1 piste) et le CC restait dessus.
# mpc clear → démarrage propre ; le CC bascule sur le lecteur qui joue.
for _ in 1 2 3 4 5; do
    mpc clear 2>/dev/null && break
    sleep 0.5
done

# ── Media syncro (waybar mpris : dernier lecteur joué) ───────────
# playerctld (fourni par playerctl) n'est PAS un service systemd : lancé
# manuellement hors repo, il ne revient pas au boot → le module mpris de la
# waybar reste scotché sur le premier lecteur au lieu du dernier joué.
playerctld daemon &

# ── Presse-papier ────────────────────────────
wl-paste --type text --watch cliphist store &
wl-paste --type image --watch cliphist store &

# ── Thème dynamique ──────────────────────────
# waypaper --restore déclenche déjà theme-apply.sh via post_command ;
# l'appel direct ci-dessous est un filet de sécurité (verrou flock = un seul apply).
~/.config/scripts/theme-apply.sh >/dev/null 2>&1 &
