#!/usr/bin/env bash
# Sasquatch CC - OCR helper (screen text -> translate or image search)
set -uo pipefail

MODE="${1:-translate}"
TMP_PNG="/tmp/sasquatch-ocr-$$.png"
TMP_TXT="/tmp/sasquatch-ocr-$$"

# Let the CC window fully close before grabbing the screen/selection.
sleep 0.3

geom="$(slurp 2>/dev/null)" || exit 0
[[ -z "$geom" ]] && exit 0

grim -g "$geom" "$TMP_PNG" || exit 1

tesseract "$TMP_PNG" "$TMP_TXT" -l fra >/dev/null 2>&1
TEXT="$(cat "${TMP_TXT}.txt" 2>/dev/null | tr -s ' \n' ' ' | sed 's/^ *//;s/ *$//')"

rm -f "$TMP_PNG" "${TMP_TXT}.txt"

[[ -z "$TEXT" ]] && exit 0

ENC_TEXT="$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$TEXT")"

case "$MODE" in
    translate)
        xdg-open "https://translate.google.com/?sl=auto&tl=fr&text=${ENC_TEXT}&op=translate" >/dev/null 2>&1
        ;;
    imgsearch)
        xdg-open "https://duckduckgo.com/?q=${ENC_TEXT}&iax=images&ia=images" >/dev/null 2>&1
        ;;
    *)
        exit 1
        ;;
esac
