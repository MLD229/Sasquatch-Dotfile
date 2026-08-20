---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# cc/ocr.sh

## Rattachements

**Composant parent** : [[20-Composants/cc]]

**Appelé par** : [[20-Composants/cc/actions-py]] — `do_translate()` et `do_imgsearch()` (sélection → grim → tesseract)

**Outils** : slurp (sélection), grim (capture), tesseract (OCR), hyprctl (attente unmapping du CC)

**Lit** : [[20-Composants/settings/settings-json]] — `cc.ocr_lang` (défaut fra)
