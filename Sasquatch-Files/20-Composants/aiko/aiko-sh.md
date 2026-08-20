---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# aiko/aiko.sh

## Rattachements

**Composant parent** : [[20-Composants/aiko]]

**Scripts et fichiers lus** :
- [[20-Composants/aiko/server-py]] — lancé `python3 server.py --port 8780` (logs → server.log) ; arrêt via POST /api/close
- [[20-Composants/aiko/main-qml]] — lancé via `quickshell -p` au toggle ON
- [[20-Composants/aiko/config-json]] — lit `model.model_file` pour vérifier la présence du modèle
- [[20-Composants/aiko/setup-sh]] — rappelé par notification si le modèle manque

**Lancé ici** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = $mod, N, exec, ~/.config/aiko/aiko.sh` (Super+N)

**Référencé par** :
- [[10-Fondations/install]] — chmod +x aiko/*.sh
- [[00-Index]]
