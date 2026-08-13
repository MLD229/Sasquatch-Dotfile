#!/bin/bash
# autostart.sh

# ── Wallpaper ────────────────────────────────
waypaper --restore &

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

# ── Presse-papier ────────────────────────────
wl-paste --type text --watch cliphist store &
wl-paste --type image --watch cliphist store &

# ── Thème dynamique ──────────────────────────
# waypaper --restore déclenche déjà theme-apply.sh via post_command ;
# l'appel direct ci-dessous est un filet de sécurité (verrou flock = un seul apply).
~/.config/scripts/theme-apply.sh >/dev/null 2>&1 &
