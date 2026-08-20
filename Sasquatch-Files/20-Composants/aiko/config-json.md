---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# aiko/config.json

## Rattachements

**Composant parent** : [[20-Composants/aiko]]

**Lu par** :
- [[20-Composants/aiko/server-py]] — `load_config()` : modèle, ports, binaire llama, VRAM, persona, contexte
- [[20-Composants/aiko/aiko-sh]] — vérifie `model.model_file` avant de lancer
- [[20-Composants/aiko/setup-sh]] — vérifie sa présence

**Modèles désignés** : `models/Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf` + `mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf` — téléchargés par [[20-Composants/aiko/setup-sh]]

**Ports** : backend 8780 (server.py), llama-server 8781 (127.0.0.1) — voisins de CC (8765) et Settings (8770)

**Chemin déclaré** :
- [[20-Composants/scripts/screenshot-sh]] — `capture.screenshot_script`

**Référencé par** :
- [[00-Index]]
