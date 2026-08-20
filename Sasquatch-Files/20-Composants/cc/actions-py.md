---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# cc/actions.py

## Rattachements

**Composant parent** : [[20-Composants/cc]]

**Importe** : [[20-Composants/cc/config-py]] — SCRIPT_DIR, RUNTIME_DIR ; imports locaux : [[20-Composants/cc/translate-py]], [[20-Composants/cc/mpd-py]]

**Importé par** : [[20-Composants/cc/server-py]] — POST /api/screenshot, /api/translate, /api/imgsearch, /api/music/finder

**Lance** :
- [[20-Composants/scripts/screenshot-sh]] — capture grim/slurp (mode area/full/window)
- [[20-Composants/cc/ocr-sh]] — OCR pour la traduction et la recherche image
- songrec (reconnaissance), ffmpeg/pw-record/arecord (extrait audio), pactl (monitor), xdg-open (DuckDuckGo)

**FIFO MPD** : `~/.local/share/mpd/cc.fifo` (sortie mono 44.1k déclarée dans [[20-Composants/mpd/mpd-conf]])

**Ferme la fenêtre CC** : `hyprctl dispatch closewindow "title:^(Sasquatch CC)$"` (cf. [[20-Composants/hypr/conf.d/rules-conf]])
