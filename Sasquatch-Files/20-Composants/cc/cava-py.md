---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# cc/cava.py

## Rattachements

**Composant parent** : [[20-Composants/cc]]

**Importe** : [[20-Composants/cc/config-py]] — CAVA_FIFO, AUDIO_FIFO, RUNTIME_DIR

**Importé par** : [[20-Composants/cc/server-py]] — `_ensure_cava()` sur /api/viz, watchdogs idle/respawn

**Génère le conf runtime** à partir de [[20-Composants/cc/cava-conf]] (fichier de référence du repo)

**Alimente** : [[20-Composants/cc/viz-py]] — écrit CAVA_FIFO (raw 20 bandes)

**Chaîne audio** : ffmpeg (monitor PipeWire) → AUDIO_FIFO → `cava -p` → CAVA_FIFO

**Nettoyé par** : [[20-Composants/cc/sasquatch-cc-service]] — ExecStopPost pkill cava/ffmpeg
