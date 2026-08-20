---
tags: [sasquatch-files, composants]
type: composant
updated: 2026-08-19
---

# aiko

## Rattachements

**Fichiers du composant** :
- [[20-Composants/aiko/aiko-sh]] — toggle launcher (Super+N)
- [[20-Composants/aiko/config-json]] — modèle GGUF, ports, persona
- [[20-Composants/aiko/main-qml]] — sidebar chat Quickshell
- [[20-Composants/aiko/server-py]] — backend HTTP 8780 + llama-server 8781
- [[20-Composants/aiko/setup-sh]] — téléchargement des modèles

**Lancé ici** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = $mod, N, exec, ~/.config/aiko/aiko.sh` (Super+N)
- [[20-Composants/hypr/conf.d/rules-conf]] — `windowrule = match:title ^(Aiko)$, float on`

**Référencé par** :
- [[10-Fondations/install]] — symlink `~/.config/aiko` → repo, chmod aiko/*.sh, rappel setup.sh si models/ vide
- [[00-Index]]
