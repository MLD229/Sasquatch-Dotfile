#!/bin/bash
# autostart.sh

# ── Purge orphelins session précédente ───────
# Relogin/crash d'Hyprland → les process de l'ancienne session (waybar, fcitx5,
# mako, polkit, wl-paste...) restent vivants avec leur ancienne signature.
# Invisibles à l'écran, mais ils bloquent les nouveaux (singletons, sockets,
# ports). À purger AVANT tout lancement.
~/.config/hypr/scripts/cleanup-orphans.sh

# ── Env graphique pour le backend CC ─────────
# Le service sasquatch-cc (enabled) démarre au login AVANT Hyprland → sans
# WAYLAND_DISPLAY/HYPRLAND_INSTANCE_SIGNATURE/DISPLAY. Résultat : zenity
# (choix dossier du sélecteur) et apply-wallpaper.sh (changement de fond)
# échouent silencieusement depuis le backend. On propage l'env de la session
# au user manager systemd, puis on redémarre le service pour qu'il en hérite.
systemctl --user import-environment WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DISPLAY XDG_CURRENT_DESKTOP 2>/dev/null || true
systemctl --user restart sasquatch-cc 2>/dev/null || true

# ── Wallpaper ────────────────────────────────
# wallpaper.sh restaure le wallpaper au login via apply-wallpaper.sh (tue les
# hyprpaper orphelins d'une session passée → fond noir, puis relance propre).
~/.config/hypr/scripts/wallpaper.sh

# ── Horloge flottante (projet UI japonaise) ──
# wallclock-ja.py : heure en hiragana dans le fond d'écran, positionnée dans
# la zone plate du wallpaper (analyse variance), glisse quand le wallpaper
# change (watcher interne 2 s). Layer background, sous les fenêtres.
python3 ~/.config/waybar/scripts/wallclock-ja.py >/dev/null 2>&1 &

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
# apply-wallpaper.sh déclenche déjà theme-apply.sh ; l'appel direct ci-dessous
# est un filet de sécurité (verrou flock = un seul apply).
~/.config/scripts/theme-apply.sh >/dev/null 2>&1 &
