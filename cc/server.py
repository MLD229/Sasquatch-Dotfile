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
import shutil
import signal
import subprocess
import sys
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
                    stop as player_stop, seek as player_seek, fetch_art,
                    music_sources as player_sources, set_source as player_set_source)
from web_bridge import handle_web_post as web_bridge_post
from actions import (do_screenshot, do_translate, do_imgsearch, do_finder,
                     tools_health)
from palette import read_palette
import sysinfo
from wallpaper import (list_wallpapers, set_folder, apply_wallpaper,
                       pick_path, thumbnail, random_wallpaper, lumgrid)
import widgets_json
import notes as notes_db
from playlist import (playlist_status, playlist_list, playlist_toggle,
                      playlist_play, playlist_playtoggle, playlist_stop,
                      playlist_next, playlist_prev, playlist_seek,
                      playlist_remove, playlist_clear,
                      playlist_shuffle, playlist_add, load_folder,
                      library_list, get_folder, set_folder as pl_set_folder,
                      pick_folder, open_panel)
from cava import (_start_cava, _stop_cava, _cava_watchdog, _cava_idle_watchdog,
                  _ensure_cava, _touch_viz_poll)

# Instances partagées (créées au chargement, comme dans le single-file original).
metrics = Metrics()
viz = Viz()

# ── Modes (DND, allégé, nuit, flou) : UN SEUL moteur ─────────────────────
# Le widget Toggles parle à ces routes ; aucune logique de mode n'est
# dupliquée : tout passe par cc/sidebar/modes.py (le même module que la
# sidebar). État persisté à part de sidebar-state.json — deux process qui
# écriraient le même JSON s'écraseraient ; la vérité AFFICHÉE reste la
# lecture réelle des outils (makoctl / hyprctl), faite à chaque appel.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "sidebar"))
import modes as modesmod                                           # noqa: E402

MODES_STATE_FILE = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "sasquatch", "cc-modes.json")

# Option Hyprland pilotée par le toggle « flou » (pas un mode : pas d'état
# sauvegardé, la valeur réelle suffit).
BLUR_OPT = "decoration:blur:enabled"

# Outil requis par toggle → commande d'installation affichée si absent.
MODES_TOOLS = {
    "dnd": {"tool": "makoctl", "install": "sudo pacman -S mako"},
    "lite": {"tool": "hyprctl", "install": "sudo pacman -S hyprland"},
    "blur": {"tool": "hyprctl", "install": "sudo pacman -S hyprland"},
    "bluesun": {"tool": "hyprsunset", "install": "sudo pacman -S hyprsunset"},
}


def _modes_load():
    try:
        with open(MODES_STATE_FILE, encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, dict):
                data.setdefault("modes", {})
                data.setdefault("modes_saved", {})
                data.setdefault("procs", {})
                return data
    except (OSError, ValueError):
        pass
    return {"modes": {}, "modes_saved": {}, "procs": {}}


def _modes_save():
    """Écriture atomique de l'état des modes (jamais de JSON tronqué)."""
    try:
        os.makedirs(os.path.dirname(MODES_STATE_FILE), exist_ok=True)
        tmp = MODES_STATE_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(MODES_STATE, f, ensure_ascii=False, indent=1)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, MODES_STATE_FILE)
    except OSError:
        pass


MODES_STATE = _modes_load()
MODES = modesmod.ModeEngine(MODES_STATE)
MODES_LOCK = threading.Lock()


def _modes_report():
    """État complet relu : `real` vient des outils, pas du dictionnaire."""
    missing = [{"mode": k, "tool": v["tool"], "install": v["install"]}
               for k, v in MODES_TOOLS.items()
               if not modesmod.ModeEngine.have(v["tool"])]
    return {
        "ok": True,
        "modes": dict(MODES_STATE.get("modes", {})),
        "real": MODES.real_state(),
        "env": MODES.env(),
        "kelvin": MODES_STATE.get("modes", {}).get("kelvin", 4000),
        "missing": missing,
        "state_file": MODES_STATE_FILE,
    }

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


# ── Notifications (mako) — widget `notifications` ─────────────────────────
# Format VÉRIFIÉ sur cette machine (mako 1.10) : le JSON s'obtient avec le
# drapeau `-j` → `makoctl list -j` (visibles) et `makoctl history -j`
# (historique). « makoctl list -a » n'existe pas ici (invalid option -- 'a').
# Champs réellement renvoyés : id, app_name, app_icon, category, desktop_entry,
# summary, body (balisage Pango), urgency, actions {clé: libellé}.
MAKO_INSTALL = "sudo pacman -S mako"
_TAG_RE = re.compile(r"<[^>]+>")


def _plain(value):
    """Texte affichable : mako met du balisage (<b>…) dans summary/body."""
    return " ".join(_TAG_RE.sub(" ", "" + (value or "")).split())


def _mako_json(args):
    """Liste JSON de `makoctl <args> -j`, ou None si mako est absent/muet."""
    try:
        proc = subprocess.run(["makoctl"] + args + ["-j"],
                              capture_output=True, text=True, timeout=2)
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    try:
        data = json.loads(proc.stdout or "[]")
    except ValueError:
        return None
    return data if isinstance(data, list) else None


def _mako_item(n, active):
    return {
        "id": n.get("id"),
        "app": _plain(n.get("app_name")),
        "icon": "" + (n.get("app_icon") or ""),
        "summary": _plain(n.get("summary")),
        "body": _plain(n.get("body")),
        "urgency": n.get("urgency") or "normal",
        "actions": list((n.get("actions") or {}).keys()),
        "active": active,
    }


def mako_report():
    """Notifications visibles + historique, relus à chaque appel (jamais un cache)."""
    if not shutil.which("makoctl"):
        return {"ok": False, "available": False, "running": False, "tool": "makoctl",
                "install": MAKO_INSTALL, "items": [], "count": 0, "activeCount": 0,
                "error": "mako n'est pas installé"}
    active = _mako_json(["list"])
    history = _mako_json(["history"])
    if active is None and history is None:
        return {"ok": False, "available": True, "running": False, "tool": "makoctl",
                "install": MAKO_INSTALL, "items": [], "count": 0, "activeCount": 0,
                "error": "mako ne répond pas"}

    merged = []
    active_ids = set()
    for n in (active or []):
        if isinstance(n, dict):
            active_ids.add(n.get("id"))
            merged.append((n, True))
    for n in (history or []):
        if isinstance(n, dict) and n.get("id") not in active_ids:
            merged.append((n, False))

    def _id(pair):
        nid = pair[0].get("id")
        return nid if isinstance(nid, int) else 0

    # Les plus récentes d'abord (l'id mako est croissant) ; les visibles
    # passent devant l'historique.
    live = sorted([p for p in merged if p[1]], key=_id, reverse=True)
    past = sorted([p for p in merged if not p[1]], key=_id, reverse=True)
    items = [_mako_item(n, flag) for n, flag in (live + past)]
    return {"ok": True, "available": True, "running": True, "tool": "makoctl",
            "install": MAKO_INSTALL, "items": items, "count": len(items),
            "activeCount": len(live), "error": ""}


def _mako_dismiss(op, nid):
    """op = dismiss-all | dismiss (id) → état RÉEL de makoctl."""
    if op == "dismiss-all":
        cmd = ["makoctl", "dismiss", "-a"]
    else:
        cmd = ["makoctl", "dismiss", "-n", "" + str(nid)]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
    except (OSError, subprocess.SubprocessError) as exc:
        return {"ok": False, "error": "makoctl : %s" % exc}
    if proc.returncode != 0:
        return {"ok": False, "error": (proc.stderr or "échec makoctl").strip()}
    return {"ok": True}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode("utf-8")
        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, OSError):
            # Client parti (ex: fenêtre quickshell fermée) → pas un bug, on ignore.
            pass

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

        # ── Tableau de bord (v6) : profil système, mises à jour, tâches ──
        if path == "/api/sysinfo":
            self._json(sysinfo.sysinfo())
            return

        if path == "/api/updates":
            self._json(sysinfo.updates())
            return

        if path == "/api/tasks":
            self._json(sysinfo.tasks())
            return

        if path == "/api/modes":
            # État des toggles (DND, allégé, nuit, flou) — moteur unique
            # cc/sidebar/modes.py, valeurs réelles relues à chaque GET.
            with MODES_LOCK:
                self._json(_modes_report())
            return

        if path == "/api/weather":
            q = urllib.parse.parse_qs(parsed.query)
            self._json(sysinfo.weather((q.get("city") or [None])[0]))
            return

        if path == "/api/tools/health":
            # Dépendances des 4 outils (page « Outils ») : l'UI affiche
            # « non installé : X » au lieu d'un bouton qui ne fait rien.
            self._json(tools_health())
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

        if path == "/api/music/sources":
            # Sources détectées (MPRIS / MPD / pulse) + épingle courante
            # (brief v1b). Coût : 1 playerctl + 1 socket MPD + 1 pactl.
            self._json(player_sources())
            return

        if path == "/api/palette":
            # Palette dynamique : relue à chaque requête → l'UI suit le thème.
            self._json(read_palette())
            return

        if path == "/api/wallpapers":
            # Sélecteur de fonds d'écran (Super+Y) : liste du dossier courant.
            self._json(list_wallpapers())
            return

        if path == "/api/wallpaper/random":
            # Bouton aléatoire : pioche un fichier aléatoire du dossier courant.
            self._json(random_wallpaper())
            return

        if path == "/api/wallpaper/lumgrid":
            # Luminance 32x18 du wallpaper courant (texte adaptatif des
            # widgets, Theme.qml). Cache par (chemin, mtime) côté module.
            self._json(lumgrid())
            return

        if path == "/api/widgets":
            # Instances du système de widgets (widgets.json, lu seul).
            doc = widgets_json.get()
            self._json({"ok": True, "revision": doc.get("revision", 0), "data": doc})
            return

        if path == "/api/notifications":
            # Widget `notifications` : visibles (makoctl list -j) + historique
            # (makoctl history -j), texte débarrassé du balisage Pango.
            self._json(mako_report())
            return

        if path == "/api/notes":
            # Widget `notes` : notes courtes persistées (~/.config/cc/notes.json).
            try:
                self._json(notes_db.get())
            except notes_db.OpError as exc:
                self._json({"ok": False, "error": str(exc),
                            "notes": [], "count": 0}, 400)
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

        if path == "/api/playlist/status":
            # Toggles random/repeat/single/consume + état du MPD (panneau Super+P).
            self._json(playlist_status())
            return

        if path == "/api/playlist/list":
            # Pistes de la playlist courante (pos, titre, durée, current).
            self._json(playlist_list())
            return

        if path == "/api/playlist/library":
            # Bibliothèque du dossier courant (scan) + filtre `q` (recherche).
            qs = urllib.parse.parse_qs(parsed.query)
            folder = (qs.get("folder") or [None])[0]
            q = (qs.get("q") or [None])[0]
            self._json(library_list(folder=folder, query=q))
            return

        if path == "/api/system/brightness":
            self._json(_brightness_get())
            return

        _not_found(self)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        body = self._body_json()

        if path == "/api/tasks":
            self._json(sysinfo.tasks(
                action=(body.get("action") or "list"),
                text=body.get("text"), id=body.get("id")))
            return

        if path == "/api/modes":
            # {mode: dnd|lite|bluesun|blur|gaming|nosleep, on: bool, kelvin?}
            # La réponse contient `real` : l'état RELU après application, que
            # le widget affiche (jamais une supposition optimiste).
            mode = (body.get("mode") or "").strip()
            on = bool(body.get("on"))
            if mode not in ("dnd", "lite", "bluesun", "blur", "gaming", "nosleep"):
                self._json({"ok": False, "error": "mode inconnu: %s" % mode}, 400)
                return
            with MODES_LOCK:
                if mode == "blur":
                    res = MODES.set_option(BLUR_OPT, on)
                else:
                    res = MODES.set(mode, on, body.get("kelvin"))
                if res.get("ok"):
                    _modes_save()
                rep = _modes_report()
            rep["applied"] = res
            rep["ok"] = bool(res.get("ok"))
            if not res.get("ok"):
                rep["error"] = res.get("error") or "échec de l'application"
                rep["missing"] = rep.get("missing") or []
            self._json(rep)
            return

        if path == "/api/widgets":
            # Écriture des instances : UNIQUEMENT par widgets_json.apply
            # (clamp sur les bornes du registre, révision, écriture atomique).
            try:
                self._json(widgets_json.apply(body))
            except ValueError as exc:
                self._json({"ok": False, "error": str(exc)}, 400)
            return

        if path == "/api/notifications":
            # {op: "dismiss-all"} | {op: "dismiss", id: N} → état RELU ensuite.
            op = (body.get("op") or "").strip()
            if op not in ("dismiss-all", "dismiss"):
                self._json({"ok": False, "error": "op inconnue: %r" % op}, 400)
                return
            res = _mako_dismiss(op, body.get("id"))
            rep = mako_report()
            rep["applied"] = res
            if not res.get("ok"):
                rep["ok"] = False
                rep["error"] = res.get("error") or "échec makoctl"
            self._json(rep)
            return

        if path == "/api/notes":
            # {op: "add", text} | {op: "rm", id} | {op: "clear"} — écriture
            # atomique dans cc/notes.py, réponse = liste RELUE du fichier.
            try:
                self._json(notes_db.apply(body))
            except notes_db.OpError as exc:
                self._json({"ok": False, "error": str(exc)}, 400)
            return

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
        if path == "/api/music/source":
            # Épingle de source : persistée dans ~/.config/cc/music.json,
            # respectée par active_source() (brief v1b). Body {"name": "..."}.
            res = player_set_source(body.get("name") or "")
            # Le statut est caché 500 ms : on invalide pour que la réponse
            # suivante (et le widget) voie tout de suite la nouvelle source.
            _music_cache["at"] = 0.0
            _music_cache["st"] = None
            self._json(res)
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
            # Applique le wallpaper (config.ini + apply-wallpaper.sh → hyprpaper + thème).
            self._json(apply_wallpaper(body.get("file") or ""))
            return
        if path == "/api/wallpaper/pick":
            # Ouvre le sélecteur natif zenity (dossier ou fichier).
            self._json(pick_path(body.get("kind") or "file"))
            return
        if path == "/api/playlist/toggle":
            # random|repeat|single|consume → bascule + état.
            self._json(playlist_toggle(body.get("mode") or ""))
            return
        if path == "/api/playlist/play":
            self._json(playlist_play(body.get("pos")))
            return
        if path == "/api/playlist/playtoggle":
            self._json(playlist_playtoggle())
            return
        if path == "/api/playlist/stop":
            self._json(playlist_stop())
            return
        if path == "/api/playlist/next":
            self._json(playlist_next())
            return
        if path == "/api/playlist/prev":
            self._json(playlist_prev())
            return
        if path == "/api/playlist/seek":
            # {sec} — seek absolu dans la piste courante (barre cliquable).
            self._json(playlist_seek(body.get("sec")))
            return
        if path == "/api/playlist/remove":
            self._json(playlist_remove(body.get("pos")))
            return
        if path == "/api/playlist/clear":
            self._json(playlist_clear())
            return
        if path == "/api/playlist/shuffle":
            self._json(playlist_shuffle())
            return
        if path == "/api/playlist/add":
            # {file: rel, play: bool} — ajoute (et joue) un morceau trouvé.
            self._json(playlist_add(body.get("file") or "",
                                    play=bool(body.get("play"))))
            return
        if path == "/api/playlist/load":
            # {folder, random} — clear + charge le dossier + play.
            self._json(load_folder(folder=body.get("folder"),
                                   random=bool(body.get("random"))))
            return
        if path == "/api/playlist/folder":
            # Mémorise le dossier de bibliothèque du panneau.
            self._json(pl_set_folder(body.get("folder") or ""))
            return
        if path == "/api/playlist/pick":
            # zenity dossier (choisir le dossier où sont les musiques).
            self._json(pick_folder())
            return
        if path == "/api/playlist/open":
            # Bouton du CC : toggle la fenêtre playlist (pl/pl.sh).
            self._json(open_panel())
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
                # Avant : « area » par défaut → un mode fautif lançait slurp
                # (sélection interactive) au lieu de répondre une erreur.
                self._json({"ok": False, "error": "mode invalide"}, 400)
                return
            self._json(do_screenshot(mode))
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
