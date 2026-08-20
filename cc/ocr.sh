#!/usr/bin/env bash
# Sasquatch CC - OCR helper : sélection d'une zone → grim → tesseract →
# texte OCR sur stdout. Ne fait PLUS l'ouverture navigateur (translate/image)
# : c'est le serveur (cc/actions.py + cc/translate.py) qui traite le texte.
set -uo pipefail

TMP_PNG="/tmp/sasquatch-ocr-$$.png"
TMP_TXT="/tmp/sasquatch-ocr-$$"

trap 'rm -f "$TMP_PNG" "${TMP_TXT}.txt"' EXIT

WIN_TITLE="Sasquatch CC"

# Robust window detection: parse hyprctl JSON with python (grep fails on empty/errored output).
window_open() {
    python3 - "$WIN_TITLE" <<'EOF'
import json, subprocess, sys
title = sys.argv[1]
try:
    out = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=3)
    data = json.loads(out.stdout)
    sys.exit(0 if any(title in (c.get("title") or "") for c in data) else 1)
except Exception:
    sys.exit(1)
EOF
}

# Attendre que la fenêtre CC soit réellement unmappée (visible=false) avant de
# capturer : sinon slurp capture le voile/panel. closewindow est async.
for i in $(seq 1 20); do
    window_open || break
    sleep 0.05
done

geom="$(slurp 2>/dev/null)" || exit 1
[[ -z "$geom" ]] && exit 1

grim -g "$geom" "$TMP_PNG" || exit 1

if ! command -v tesseract >/dev/null 2>&1; then
    notify-send "Sasquatch CC" "tesseract requis (pacman -S tesseract tesseract-data-fra)" -t 3000 2>/dev/null
    exit 1
fi

# Langue OCR : réglage panneau Settings (Super+I) — settings.json cc.ocr_lang
OCR_LANG="fra"
if [[ -f "$HOME/.config/settings/settings.json" ]]; then
    OCR_LANG="$(python3 -c 'import json,os;d=json.load(open(os.path.expanduser("~/.config/settings/settings.json")));print(d.get("cc",{}).get("ocr_lang","fra"))' 2>/dev/null || echo fra)"
fi

tesseract "$TMP_PNG" "$TMP_TXT" -l "$OCR_LANG" >/dev/null 2>&1

# Normalise : lignes → espaces, espaces multiples → un seul, nettoie les bords.
sed 's/[[:space:]]\+/ /g; s/^ *//; s/ *$//' "${TMP_TXT}.txt" 2>/dev/null \
    | tr -s '\n' ' '
echo
