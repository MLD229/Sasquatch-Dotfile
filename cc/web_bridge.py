"""Pont navigateur → CC (source « web » pour le now-playing).

Chromium/Brave n'expose PAS MPRIS nativement → YouTube dans le navigateur
est invisible pour playerctl/MPD. Ce module reçoit le now-playing poussé
par l'extension Chromium maison (cc/browser-bridge/) via POST /api/music/web,
et lui fait passer les commandes (toggle/seek/next…) dans la réponse.

Protocole (POST /api/music/web) :
  body : {token, title, artist, album, art, duration, position, playing,
          paused, url}
  → réponse : {command: null|{type: "toggle"|"play"|"pause"|"stop"|"next"|
              "prev"|"seek", pos: <secondes>}}

Sécurité : token partagé (config.py WEB_BRIDGE_TOKEN) exigé — une page web
ne peut pas POST (CORS + token), seule l'extension le connaît.
"""

import threading
import time
import urllib.parse

from config import WEB_BRIDGE_TOKEN

# ── État partagé ────────────────────────────────────────────────────────
_lock = threading.Lock()
_state = {
    "token_ok": False,
    "playing": False,
    "paused": False,
    "title": None,
    "artist": None,
    "album": None,
    "art": None,        # URL d'image (https://…)
    "duration": 0.0,
    "position": 0.0,
    "url": None,
    "last_seen": 0.0,   # time.time() du dernier POST — pour la fraîcheur
    "playing_since": 0.0,  # transition False→True (récence de lecture)
    "player": None,     # nom du player (ex. "youtube", "netflix"…)
}
_command = None        # commande en attente pour l'extension
_command_at = 0.0      # timestamp de la commande (timeout si l'extension ne POST pas)
_STALE_AFTER = 5.0     # au-delà : la source web est considérée morte
_CMD_TIMEOUT = 3.0     # au-delà : la commande en attente est périmée


def _fresh():
    return time.time() - _state["last_seen"] <= _STALE_AFTER


def handle_web_post(body):
    """Traite un POST /api/music/web. Retourne la réponse JSON (dict)."""
    global _command, _command_at
    token = body.get("token") or ""
    if token != WEB_BRIDGE_TOKEN:
        return {"error": "bad token"}
    with _lock:
        playing = bool(body.get("playing"))
        # Transition False→True = la lecture a démarré dans le navigateur.
        # C'est LA récence qui départage les sources (le « dernier lancé »).
        if playing and not _state["playing"]:
            _state["playing_since"] = time.time()
        _state.update({
            "token_ok": True,
            "playing": playing,
            "paused": bool(body.get("paused")),
            "title": body.get("title") or None,
            "artist": body.get("artist") or None,
            "album": body.get("album") or None,
            "art": body.get("art") or None,
            "duration": float(body.get("duration") or 0),
            "position": float(body.get("position") or 0),
            "url": body.get("url") or None,
            "player": body.get("player") or None,
            "last_seen": time.time(),
        })
        cmd = _command
        cmd_at = _command_at
        _command = None
        _command_at = 0.0
    # Commande périmée (l'extension n'a pas POSTé à temps) → ne pas envoyer.
    if cmd is not None and time.time() - cmd_at > _CMD_TIMEOUT:
        cmd = None
    return {"command": cmd}


def push_command(cmd):
    """Met une commande en attente pour l'extension (appelé par player.py
    quand la source active est « web »)."""
    global _command, _command_at
    with _lock:
        _command = cmd
        _command_at = time.time()


def web_status():
    """Statut de la source web (dict style player.py), ou None si morte."""
    with _lock:
        if not _state["token_ok"] or not _fresh():
            return None
        return {
            "source": "web",
            "player": _state["player"] or "navigateur",
            "playing": _state["playing"],
            "paused": _state["paused"],
            "title": _state["title"],
            "artist": _state["artist"],
            "album": _state["album"],
            "file": _state["url"],
            "volume": 0,
            "elapsed": _state["position"],
            "duration": _state["duration"],
            "playing_since": _state["playing_since"],
            "art": ("/albumart?url=" + urllib.parse.quote(_state["art"]))
                   if _state["art"] else None,
        }


def is_active():
    """La source web est-elle considérée présente (fraîche) ?"""
    with _lock:
        return _state["token_ok"] and _fresh()
