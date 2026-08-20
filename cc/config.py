"""Constantes partagées du Sasquatch Control Center."""

import os

# ── Runtime PAR UTILISATEUR ──────────────────────────────────────
# XDG_RUNTIME_DIR (/run/user/<uid>) isole fifos + caches par user :
# deux sessions utilisateur peuvent lancer le CC sans collision.
# Fallback /tmp hors session graphique (ex. SSH).
RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"

# ── MPD : socket unix PAR USER (mpd.conf bind_to_address) ─────────
# Chaque user pilote SON instance MPD via son propre socket. Avant :
# bind 127.0.0.1:6600 partagé → n'importe quel user local voyait la
# musique d'un autre (la musique d'un autre user s'affichait dans le CC).
MPD_SOCKET = os.path.expanduser("~/.local/share/mpd/socket")
# Fallback TCP (anciennes configs, tests) — le socket unix prime.
MPD_HOST = "127.0.0.1"
MPD_PORT = 6600

HOST = "127.0.0.1"
PORT = 8765
HIST_LEN = 90
CAVA_FIFO = os.path.join(RUNTIME_DIR, "sasquatch-cava.fifo")
AUDIO_FIFO = os.path.join(RUNTIME_DIR, "sasquatch-audio.fifo")
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
ALBUMART_TMP = os.path.join(RUNTIME_DIR, "sasquatch-albumart.jpg")

# ── Pont navigateur → CC (cc/web_bridge.py + cc/browser-bridge/) ─
# Token partagé avec l'extension Chromium maison : sans lui, une page
# web ne peut pas pousser de now-playing (CORS + token exigé).
WEB_BRIDGE_TOKEN = "sasquatch-cc-bridge"
