---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# cc/viz.py

## Rattachements

**Composant parent** : [[20-Composants/cc]]

**Importe** : [[20-Composants/cc/config-py]] — CAVA_FIFO

**Lit la fifo écrite par** : [[20-Composants/cc/cava-py]] — raw 20 bandes 16-bit, ~30 fps

**Importé par** : [[20-Composants/cc/server-py]] — GET /api/viz (lazy, `_ensure_cava()`)

**Consommé par** : [[20-Composants/cc/main-qml]] — égaliseur 20 barres (poll 120 ms)
