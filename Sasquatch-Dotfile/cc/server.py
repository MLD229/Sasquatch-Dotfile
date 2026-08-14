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
from mpd import (mpd_status, mpd_simple_command, mpd_toggle, mpd_albumart,
                 notify_track_change, video_id_from_file, yt_thumbnail)
from player import (now_playing as player_now_playing, toggle as player_toggle,
                    next_track as player_next, prev_track as player_prev,
                    stop as player_stop, seek as player_seek, fetch_art)
from actions import do_screenshot, do_translate, do_imgsearch, do_finder
from palette import read_palette
from cava import _start_cava, _stop_cava, _cava_watchdog

# Instances partagées (créées au chargement, comme dans le single-file original).
metrics = Metrics()
viz = Viz()


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
            vals = viz.get()
            self._json({"vals": vals, "bars": len(vals)})
            return

        if path == "/api/music/status":
            st = player_now_playing()  # MPRIS (navigateur…) + MPD unifiés
            notify_track_change(st)  # notif au changement de piste (≤1 s)
            self._json(st)
            return

        if path == "/api/palette":
            # Palette dynamique : relue à chaque requête → l'UI suit le thème.
            self._json(read_palette())
            return

        if path == "/albumart":
            qs = urllib.parse.parse_qs(parsed.query)
            art_url = (qs.get("url") or [None])[0]
            if art_url:
                # Art MPRIS (navigateur/YouTube…) : thumbnail distante ou fichier.
                data = fetch_art(art_url)
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
        if path == "/api/music/volume":
            v = max(0, min(100, _safe_int(body.get("v", 0))))
            self._json({"ok": mpd_simple_command("setvol %d" % v)})
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
        if path == "/api/music/seek":
            pos = _safe_int(body.get("pos", 0))
            self._json({"ok": player_seek(pos)})
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
    _start_cava()
    threading.Thread(target=_cava_watchdog, daemon=True).start()
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
