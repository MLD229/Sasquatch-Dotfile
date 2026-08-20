---
tags: [sasquatch-files, fondations]
type: reference
updated: 2026-08-19
---

# install

## Rattachements

**Fichiers liés vers `~/.config`** :
- [[20-Composants/hypr]] — hypr/
- [[20-Composants/waybar]] — waybar/
- [[20-Composants/rofi]] — rofi/
- [[20-Composants/mako]] — mako/
- [[20-Composants/kitty]] — kitty/
- [[20-Composants/fcitx5]] — fcitx5/
- [[20-Composants/fish]] — fish/
- [[20-Composants/fastfetch]] — fastfetch/
- [[30-Fichiers/starship-toml]] — starship.toml
- [[20-Composants/scripts]] — scripts/
- [[20-Composants/cc]] — cc/
- [[20-Composants/wp]] — wp/
- [[20-Composants/pl]] — pl/
- [[20-Composants/aiko]] — aiko/
- [[20-Composants/mpd]] — mpd/
- [[20-Composants/settings]] — settings/
- [[20-Composants/themes]] — themes/gtk/gtk-3.0, themes/gtk/gtk-4.0, themes/qt/kdeglobals
- [[30-Fichiers/mimeapps-list]] — mimeapps.list

**Paquets installés** :
- [[10-Fondations/requirements]] — même set que les groupes PKGS_* du script (essentiel / features / optionnel)

**Hook thème dynamique** :
- [[20-Composants/scripts/theme-apply-sh]] — `post_command` de `~/.config/waypaper/config.ini`

**Services systemd** :
- [[20-Composants/cc/sasquatch-cc-service]] — service user du backend CC (port 8765)
- [[20-Composants/waybar/waybar-service]] — service user waybar (restart on-failure)
- [[20-Composants/mpd/mpd-conf]] — service user mpd (lecteur du CC)
- Services système : logind.conf (lock au lid switch), iwd, systemd-networkd, bluetooth, opentabletdriver, pipewire

**Scripts rendus exécutables** :
- [[30-Fichiers/set-wall-sh]] — `chmod +x` (bug #31) ; idem pour scripts/*.sh, hypr/scripts/*.sh, rofi/scripts/*.sh, cc/*.sh, aiko/*.sh, settings/*.sh, pl/*.sh

**Shell par défaut** :
- [[20-Composants/fish/config-fish]] — `chsh` vers fish
