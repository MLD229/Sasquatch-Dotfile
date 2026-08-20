---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# cc/mpd.py

## Rattachements

**Composant parent** : [[20-Composants/cc]]

**Importe** : [[20-Composants/cc/config-py]] — MPD_SOCKET, ALBUMART_TMP, RUNTIME_DIR

**Importé par** :
- [[20-Composants/cc/server-py]] — status, albumart, notif de changement de piste
- [[20-Composants/cc/player-py]] — mpd_toggle / mpd_simple_command
- [[20-Composants/cc/actions-py]] — volume guard + fifo du finder
- [[20-Composants/cc/playlist-py]] — primitives socket `_mpd_*`

**Se connecte à** : [[20-Composants/mpd/mpd-conf]] — socket unix par user (fallback TCP 6600)

**Pochettes** : ffmpeg (extraction embarquée), i.ytimg.com (yt-dlp), notify-send
