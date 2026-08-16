#!/usr/bin/env python3
"""Sasquatch Control Center - backend HTTP server (stdlib only).

Point d'entrée : monte le serveur HTTP (127.0.0.1:8765) et route les requêtes
vers les modules métier. Code découpé pour la lisibilité :
  - config.py   → constantes partagées
  - metrics.py  → Metrics (métriques système + historique)
  - viz.py      → Viz (lecteur fifo cava)
  - mpd.py      → client MPD (status/commandes/albumart)
  - actions.py  → capture, OCR, recherche, finder
  - cava.py     → cycle de vie du process cava
"""

import json
import os
import re
import signal
import subprocess
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from config import HOST, PORT
from metrics import Metrics
from viz import Viz
from mpd import (mpd_status, mpd_albumart, local_albumart,
                 notify_track_change, video_id_from_file, yt_thumbnail)
from player import (now_playing as player_now_playing, toggle as player_toggle,
                    next_track as player_next, prev_track as player_prev,
                    stop as player_stop, seek as player_seek, fetch_art)
from web_bridge import handle_web_post as web_bridge_post
from actions import do_screenshot, do_translate, do_imgsearch, do_finder
from palette import read_palette
from wallpaper import (list_wallpapers, set_folder, apply_wallpaper,
                       pick_path, thumbnail)
from cava import (_start_cava, _stop_cava, _cava_watchdog, _cava_idle_watchdog,
                  _ensure_cava, _touch_viz_poll)

# Instances partagées (créées au chargement, comme dans le single-file original).
metrics = Metrics()
viz = Viz()

# Cache /api/music/status (500 ms) : le QML poll toutes les 1 s + la notif de
# changement de piste → pas besoin de re-fork playerctl / rouvrir le socket MPD
# à chaque requête. La position reste fluide (500 ms de latence max).
_music_cache = {"at": 0.0, "st": None}
_MUSIC_CACHE_MS = 0.5


def _safe_int(v, default=0):
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


def _not_found(self):
    self.send_response(404)
    self.send_header("Content-Type", "text/plain")
    self.send_header("Content-Length", "0")
    self.end_headers()


def _cc_cfg():
    """Réglages CC depuis settings.json (panneau Settings, Super+I)."""
    try:
        with open(os.path.expanduser("~/.config/settings/settings.json"), encoding="utf-8") as f:
            return json.load(f).get("cc", {}) or {}
    except Exception:
        return {}


# ── Volume système (PipeWire via wpctl) ───────────────────────────────────
# Le volume MPD (setvol) est indépendant de ce qu'on entend VRAIMENT (les
# autres apps, YouTube…). Le slider du CC pilote le sink par défaut : la
# barre affiche la vraie valeur au lieu d'un 0% figé.
def _wpctl_volume():
    try:
        out = subprocess.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
                             capture_output=True, text=True, timeout=3).stdout.strip()
        m = re.search(r"Volume:\s*([0-9.]+)", out)
        if m:
            return {"volume": round(float(m.group(1)) * 100), "muted": "[MUTED]" in out}
    except Exception:
        pass
    return {"volume": 0, "muted": False}


def _wpctl_set_volume(v):
    try:
        v = max(0, min(100, v))
        subprocess.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "%d%%" % v],
                       capture_output=True, timeout=3)
        return True
    except Exception:
        return False


def _wpctl_set_mute(mute):
    try:
        subprocess.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "1" if mute else "0"],
                       capture_output=True, timeout=3)
        return True
    except Exception:
        return False


# ── Luminosité (brightnessctl) ──────────────────────────────────────────
def _brightness_get():
    try:
        out = subprocess.run(["brightnessctl", "-m"], capture_output=True,
                             text=True, timeout=3).stdout.strip()
        # format: Device,Class,Value,Percent[%],...
        parts = out.split(",")
        if len(parts) >= 4:
            pct = parts[3].rstrip("%")
            return {"brightness": int(pct)}
    except Exception:
        pass
    return {"brightness": 0}


def _brightness_set(v):
    try:
        v = max(0, min(100, v))
        subprocess.run(["brightnessctl", "set", "%d%%" % v],
                       capture_output=True, timeout=3)
        return True
    except Exception:
        return False


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body_json(self):
        length = int(self.headers.get("Content-Length", 0) or 0)
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        try:
            return json.loads(raw.decode("utf-8"))
        except Exception:
            return {}

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/":
            body = (b"<html><head><title>SasquatchCC</title></head>"
                     b"<body><h1>SasquatchCC</h1><p>Serveur actif.</p></body></html>")
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if path == "/api/stats":
            self._json(metrics.get_stats())
            return

        if path == "/api/viz":
            # Lazy cava : le serveur est PERMANENT (service systemd) → cava/
            # ffmpeg ne tournent que si le CC est visible et poll le viz.
            _ensure_cava()
            _touch_viz_poll()
            vals = viz.get()
            self._json({"vals": vals, "bars": len(vals)})
            return

        if path == "/api/music/status":
            now = time.time()
            cached = _music_cache
            if cached["st"] is not None and now - cached["at"] < _MUSIC_CACHE_MS:
                st = cached["st"]
            else:
                # MPRIS (navigateur…) + MPD unifiés
                st = player_now_playing()
                cached["at"] = now
                cached["st"] = st
            notify_track_change(st)  # notif au changement de piste (≤1 s)
            if not _cc_cfg().get("cover_art", True):
                st["art"] = None  # réglage panneau Settings (Super+I)
            self._json(st)
            return

        if path == "/api/palette":
            # Palette dynamique : relue à chaque requête → l'UI suit le thème.
            self._json(read_palette())
            return

        if path == "/api/wallpapers":
            # Sélecteur de fonds d'écran (Super+Y) : liste du dossier courant.
            self._json(list_wallpapers())
            return

        if path == "/api/wallpaper/thumb":
            # Miniature du filmstrip (cache sha1 côté serveur).
            qs = urllib.parse.parse_qs(parsed.query)
            file_path = (qs.get("file") or [None])[0]
            data = thumbnail(file_path)
            if not data:
                _not_found(self)
                return
            self.send_response(200)
            self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return

        if path == "/albumart":
            qs = urllib.parse.parse_qs(parsed.query)
            art_url = (qs.get("url") or [None])[0]
            local = (qs.get("local") or [None])[0]
            if art_url:
                # Art MPRIS (navigateur/YouTube…) : thumbnail distante ou fichier.
                data = fetch_art(art_url)
            elif local:
                # Audio local (fallback pulse, mpv/vlc sans MPRIS) : pochette
                # embarquée (ffmpeg) sinon thumbnail YouTube si le nom porte un id.
                rp = os.path.realpath(local)
                allowed = [os.path.realpath(os.path.expanduser(d))
                           for d in ("~/songs", "~/Music", "~/Téléchargements",
                                     "~/Vidéos", "~/Videos")]
                if not any(rp.startswith(a + os.sep) for a in allowed):
                    _not_found(self)
                    return
                data = local_albumart(rp)
                if not data:
                    data = yt_thumbnail(video_id_from_file(rp))
            else:
                st = mpd_status()
                data = mpd_albumart(st.get("file"))
                if not data:
                    # Fichiers yt-dlp (sans pochette embarquée) : thumbnail YouTube.
                    data = yt_thumbnail(video_id_from_file(st.get("file")))
            if not data:
                _not_found(self)
                return
            ctype = "image/jpeg" if data[:3] == b"\xff\xd8\xff" else "image/png"
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return

        if path == "/api/system/volume":
            self._json(_wpctl_volume())
            return

        if path == "/api/system/brightness":
            self._json(_brightness_get())
            return

        _not_found(self)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        body = self._body_json()

        if path == "/api/music/toggle":
            self._json({"ok": player_toggle()})
            return
        if path == "/api/music/next":
            self._json({"ok": player_next()})
            return
        if path == "/api/music/prev":
            self._json({"ok": player_prev()})
            return
        if path == "/api/music/stop":
            self._json({"ok": player_stop()})
            return
        if path == "/api/system/volume":
            # Le slider du CC pilote le volume SYSTÈME (wpctl) : la barre
            # reflète ce qu'on entend vraiment. `v` (0-100) ou `mute` (bool).
            if "v" in body:
                _wpctl_set_volume(_safe_int(body.get("v", 0)))
            if "mute" in body:
                _wpctl_set_mute(bool(body.get("mute")))
            self._json(_wpctl_volume())
            return
        if path == "/api/system/brightness":
            if "v" in body:
                _brightness_set(_safe_int(body.get("v", 0)))
            self._json(_brightness_get())
            return
        if path == "/api/wallpaper/folder":
            # Sélecteur : mémorise le dossier choisi (config.ini folder=).
            self._json(set_folder(body.get("folder") or ""))
            return
        if path == "/api/wallpaper/apply":
            # Applique le wallpaper (config.ini + waypaper --restore → thème).
            self._json(apply_wallpaper(body.get("file") or ""))
            return
        if path == "/api/wallpaper/pick":
            # Ouvre le sélecteur natif zenity (dossier ou fichier).
            self._json(pick_path(body.get("kind") or "file"))
            return
        if path == "/api/music/seek":
            pos = _safe_int(body.get("pos", 0))
            self._json({"ok": player_seek(pos)})
            return
        if path == "/api/music/web":
            # Pont navigateur → CC : l'extension Chromium pousse le
            # now-playing (titre, image, position) et reçoit les commandes.
            self._json(web_bridge_post(body))
            return
        if path == "/api/music/finder":
            self._json(do_finder())
            return
        if path == "/api/screenshot":
            qs = urllib.parse.parse_qs(parsed.query)
            mode = qs.get("mode", ["area"])[0]
            if mode not in ("area", "full", "window"):
                mode = "area"
            self._json({"ok": do_screenshot(mode)})
            return
        if path == "/api/translate":
            # Synchrone : l'UI est masquée pendant la sélection OCR, on ne
            # répond qu'une fois texte + traduction prêts (timeout 120 s).
            self._json(do_translate())
            return
        if path == "/api/imgsearch":
            q = (body.get("q") or "").strip()
            self._json(do_imgsearch(q if q else None))
            return
        if path == "/api/close":
            self._json({"ok": True})
            metrics.stop()
            viz.stop()
            _stop_cava()

            def _shutdown():
                time.sleep(0.3)
                os._exit(0)

            threading.Thread(target=_shutdown, daemon=True).start()
            return

        _not_found(self)


def _handle_sig(signum, frame):
    metrics.stop()
    viz.stop()
    _stop_cava()
    os._exit(0)


def main():
    signal.signal(signal.SIGTERM, _handle_sig)
    signal.signal(signal.SIGINT, _handle_sig)
    # cava est LAZY (lancé par /api/viz quand le CC est visible) — le serveur
    # étant permanent (service systemd), on ne le démarre plus ici. L'idle
    # watchdog l'arrête quand le CC ferme. Le réglage panneau Settings
    # (Super+I) cc.cava=False continue de forcer l'arrêt via _stop_cava()
    # au prochain idle tick.
    if not _cc_cfg().get("cava", True):
        _stop_cava()
    threading.Thread(target=_cava_idle_watchdog, daemon=True).start()
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
