---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# scripts/fix-suspend.sh

## Rattachements

**Composant parent** : [[20-Composants/scripts]]

**Appels** : `sed` sur `/etc/default/grub`, `grub-mkconfig`, `systemctl enable nvidia-suspend/resume/hibernate`, lecture `/sys/power/mem_sleep`

**Références** :
- [[20-Composants/hypr/hypridle-conf]] — `after_sleep_cmd` dpms on mentionné comme filet de sécurité
- [[10-Fondations/symlinks]] — le script vit dans ~/.config/scripts via symlink

**Référencé par** :
- (aucun bind) — lancement manuel en sudo (README)
