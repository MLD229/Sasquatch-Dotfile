#!/bin/bash
# autostart.sh

# ── Wallpaper ────────────────────────────────
waypaper --restore &

# ── Bar ──────────────────────────────────────
waybar &

# ── Notifications ────────────────────────────
mako &

# ── Polkit ───────────────────────────────────
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

# ── Idle / Lock ──────────────────────────────
hypridle &

# ── Presse-papier ────────────────────────────
wl-paste --type text --watch cliphist store &
wl-paste --type image --watch cliphist store &
