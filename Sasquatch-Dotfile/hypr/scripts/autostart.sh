#!/bin/bash
# autostart.sh

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
hypridle &

# ── Lecteur MPD (CC musique + finder) ────────
# Service user normalement activé par install.sh ; ce start est un filet de
# sécurité (sans effet si déjà lancé).
systemctl --user start mpd 2>/dev/null &

# ── Presse-papier ────────────────────────────
wl-paste --type text --watch cliphist store &
wl-paste --type image --watch cliphist store &

# ── Thème dynamique ──────────────────────────
# waypaper --restore déclenche déjà theme-apply.sh via post_command ;
# l'appel direct ci-dessous est un filet de sécurité (verrou flock = un seul apply).
~/.config/scripts/theme-apply.sh >/dev/null 2>&1 &
