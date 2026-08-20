---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# cc/metrics.py

## Rattachements

**Composant parent** : [[20-Composants/cc]]

**Importe** : [[20-Composants/cc/config-py]] — HIST_LEN (90)

**Importé par** : [[20-Composants/cc/server-py]] — instance `Metrics()` partagée, GET /api/stats

**Consommé par** :
- [[20-Composants/cc/main-qml]] — jauges et sparklines (CPU/RAM/GPU/temp/réseau)
- [[20-Composants/cc/qml/gauge-qml]] · [[20-Composants/cc/qml/sparkline-qml]] — rendu des données

**Outils système** : nvidia-smi (GPU), hyprctl (refresh rate), /proc/*
