"""Constantes partagées du Sasquatch Control Center."""

import os

HOST = "127.0.0.1"
PORT = 8765
HIST_LEN = 90
CAVA_FIFO = "/tmp/sasquatch-cava.fifo"
MPD_HOST = "127.0.0.1"
MPD_PORT = 6600
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# ── Traduction OCR (cc/translate.py) ─────────────────────────────
# Ordre des backends : LibreTranslate local (self-hosted, 127.0.0.1:5000),
# puis instances publiques LibreTranslate, puis fallback Google GTX (sans clé).
TRANSLATE_LOCAL_URL = "http://127.0.0.1:5000/translate"
TRANSLATE_PUBLIC_URLS = (
    "https://libretranslate.de/translate",
    "https://translate.argosopentech.com/translate",
)
TRANSLATE_GTX_URL = "https://translate.googleapis.com/translate_a/single"
TRANSLATE_TARGET = "fr"
TRANSLATE_TIMEOUT = 6
TRANSLATE_MAX_LEN = 1500

# ── Notification musique (changement de piste) ───────────────────
ALBUMART_TMP = "/tmp/sasquatch-albumart.jpg"
