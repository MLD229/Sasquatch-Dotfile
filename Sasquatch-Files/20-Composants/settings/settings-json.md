---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# settings/settings.json

## Rattachements

**Composant parent** : [[20-Composants/settings]]

**Écrit/lu par** :
- [[20-Composants/settings/settings-py]] — lecture/écriture atomique, une section à la fois (idle, palette, clock, cc, keybinds)

**Lu par** :
- [[20-Composants/cc/server-py]] — section `cc` (cava, ocr_lang, cover_art)
- [[20-Composants/cc/ocr-sh]] — `cc.ocr_lang` (langue OCR)

**Référencé par** :
- [[10-Fondations/symlinks]] — `~/.config/settings/settings.json` pointe vers ce fichier
