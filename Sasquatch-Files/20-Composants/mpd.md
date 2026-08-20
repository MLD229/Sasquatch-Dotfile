---
tags: [sasquatch-files, composants]
type: composant
updated: 2026-08-19
---

# mpd

## Rattachements

**Fichiers du composant** :
- [[20-Composants/mpd/mpd-conf]] — lecteur local (socket unix + fifo CC Capture)

**Lancé ici** :
- [[10-Fondations/install]] — service user systemd mpd activé
- [[20-Composants/hypr/scripts/autostart-sh]] — `systemctl --user start mpd` (filet) + `mpc clear`

**Consommé par** :
- [[20-Composants/cc/config-py]] — MPD_SOCKET (même chemin que bind_to_address)
- [[20-Composants/cc/mpd-py]] — client MPD (socket AF_UNIX)
- [[20-Composants/cc/actions-py]] — fifo cc.fifo (reconnaissance songrec)
- [[20-Composants/fish/config-fish]] — MPD_HOST pour mpc/ncmpc
