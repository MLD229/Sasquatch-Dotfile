#!/usr/bin/env bash
# Sasquatch CC - OCR helper (screen text -> translate or image search)
set -uo pipefail

MODE="${1:-translate}"
TMP_PNG="/tmp/sasquatch-ocr-$$.png"
TMP_TXT="/tmp/sasquatch-ocr-$$"

trap 'rm -f "$TMP_PNG" "${TMP_TXT}.txt"' EXIT

# Wait until the CC window is actually gone before grabbing the screen
# (closewindow is async; slurp must not capture the dark veil).
for i in $(seq 1 20); do
    hyprctl clients -j 2>/dev/null | grep -q '"Sasquatch CC"' || break
    sleep 0.05
done

geom="$(slurp 2>/dev/null)" || exit 0
[[ -z "$geom" ]] && exit 0

grim -g "$geom" "$TMP_PNG" || exit 1

if ! command -v tesseract >/dev/null 2>&1; then
    notify-send "Sasquatch CC" "tesseract requis (pacman -S tesseract tesseract-data-fra)" -t 3000
    exit 1
fi

tesseract "$TMP_PNG" "$TMP_TXT" -l fra >/dev/null 2>&1
TEXT="$(cat "${TMP_TXT}.txt" 2>/dev/null | tr -s ' \n' ' ' | sed 's/^ *//;s/ *$//')"

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
