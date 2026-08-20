---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# mpd/mpd.conf

## Rattachements

**Composant parent** : [[20-Composants/mpd]]

**Socket unix (`bind_to_address`)** :
- [[20-Composants/fish/config-fish]] — MPD_HOST = ~/.local/share/mpd/socket
- [[20-Composants/cc/config-py]] — MPD_SOCKET (client du CC)

**FIFO CC Capture (`cc.fifo`)** :
- [[20-Composants/cc/actions-py]] — reconnaissance songrec quand MPD joue

**Lancé ici** :
- [[10-Fondations/install]] — service user systemd
- [[20-Composants/hypr/scripts/autostart-sh]] — `systemctl --user start mpd` (filet de sécurité)
