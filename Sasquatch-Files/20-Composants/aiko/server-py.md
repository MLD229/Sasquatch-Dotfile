---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# aiko/server.py

## Rattachements

**Composant parent** : [[20-Composants/aiko]]

**Configuration lue** :
- [[20-Composants/aiko/config-json]] — modèle (model_file/mmproj_file, n_ctx), serveur (backend 8780, llama 8781), llama_bin, VRAM, persona, contexte

**Modèle lancé** : llama-server sur `127.0.0.1:8781` — GGUF de `models/` (installés par [[20-Composants/aiko/setup-sh]]), binaire LM Studio CUDA ou PATH

**Persistance** : `sessions/autosave.json` (historique du chat, gitignoré)

**Palette** : lit `qml/Palette.qml` (généré par [[20-Composants/scripts/theme-apply-py]]), fallback `cc/qml/Palette.qml`

**Appelé par** :
- [[20-Composants/aiko/aiko-sh]] — `python3 server.py --port 8780` + POST /api/close
- [[20-Composants/aiko/main-qml]] — toutes les routes API

**Dépendances runtime** : slurp + grim (capture), nvidia-smi + lms (VRAM LM Studio)

**Référencé par** :
- [[00-Index]]
