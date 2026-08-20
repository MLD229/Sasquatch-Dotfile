---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# cc/sasquatch-cc.service

## Rattachements

**Composant parent** : [[20-Composants/cc]]

**Lance** : [[20-Composants/cc/server-py]] — `ExecStart=/usr/bin/python3 %h/.config/cc/server.py`, WorkingDirectory `%h/.config/cc`

**Dépend de** : [[20-Composants/mpd/mpd-conf]] (mpd.service), pipewire/wireplumber

**Nettoyage à l'arrêt** : ExecStopPost pkill cava/ffmpeg → processus de [[20-Composants/cc/cava-py]]

**Démarré par** :
- [[20-Composants/cc/cc-sh]] · [[20-Composants/wp/wp-sh]] · [[20-Composants/pl/pl-sh]] — `systemctl --user start` idempotent
- [[20-Composants/hypr/scripts/autostart-sh]] — restart au login

**Installé par** : [[10-Fondations/install]] — symlink vers `~/.config/systemd/user/` + `enable --now`

**Logs** : journald (`journalctl --user -u sasquatch-cc`)
