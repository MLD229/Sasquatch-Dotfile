---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# aiko/setup.sh

## Rattachements

**Composant parent** : [[20-Composants/aiko]]

**Téléchargements** (dans `models/`, depuis huggingface.co/ggml-org/Qwen2.5-VL-3B-Instruct-GGUF) :
- `Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf` (1,8 Go)
- `mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf` (806 Mo, vision)

**Modèles utilisés par** :
- [[20-Composants/aiko/config-json]] — valeurs par défaut de model_file/mmproj_file
- [[20-Composants/aiko/server-py]] — chargés au démarrage de llama-server

**Vérifie** :
- [[20-Composants/aiko/config-json]] — présence obligatoire
- binaire llama-server : dossier du repo, PATH ou backends LM Studio (`~/.lmstudio/extensions/backends/llama.cpp-*`)

**Référencé par** :
- [[20-Composants/aiko/aiko-sh]] — notification « modèle absent → bash setup.sh »
- [[10-Fondations/install]] — message si models/ vide (paquet AUR llama.cpp-cuda)
- [[00-Index]]
