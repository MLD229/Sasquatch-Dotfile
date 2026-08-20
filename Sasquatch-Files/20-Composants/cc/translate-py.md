---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# cc/translate.py

## Rattachements

**Composant parent** : [[20-Composants/cc]]

**Importe** : [[20-Composants/cc/config-py]] — URLs LibreTranslate/GTX, timeouts, langue cible

**Appelé par** : [[20-Composants/cc/actions-py]] — `do_translate()` (texte OCR → traduction)

**Backends** : LibreTranslate local (127.0.0.1:5000) → instances publiques → Google GTX
