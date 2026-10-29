#!/usr/bin/env python3
"""Sasquatch sidebar — backend HTTP (stdlib only, 127.0.0.1:8778).

POURQUOI UN SERVEUR À PART (et pas une extension de cc/server.py) :
  * le timer/chrono/alarme doit continuer PANNEAU FERMÉ → il faut un process
    permanent. Celui du CC tourne déjà, mais on ne veut pas risquer de le
    casser : la règle du brief est « on consomme le CC, on ne le modifie pas ».
  * un service systemd user dédié (sasquatch-sidebar.service) = redémarrage
    automatique, logs journald, et aucune dépendance au cycle de vie du QML.

PALETTE : on ne réimplémente rien. On importe cc/palette.py (le module du CC,
qui lit ~/.config/cc/qml/Palette.qml régénéré par theme-apply.py) ; si
l'import échoue on interroge le CC (GET /api/palette sur 8765) ; en dernier
recours seulement, les défauts Catppuccin.

État persistant : $XDG_STATE_HOME/sasquatch/sidebar-state.json
(écriture atomique tmp + os.replace → jamais de JSON tronqué).

Endpoints
  GET  /api/health
  GET  /api/palette                → palette du wallpaper courant
  GET  /api/env                    → outils présents/absents + session Hyprland
  GET  /api/state?since=N          → todo + chrono/timer/alarmes + modes + events
  POST /api/todo        {action: add|toggle|del|clear_done, text?, id?, prio?}
  POST /api/stopwatch   {action: start|pause|reset}
  POST /api/timer       {action: start|pause|reset, seconds?, label?}
  POST /api/alarm       {action: add|del, hhmm?, id?}
  POST /api/modes       {mode: lite|gaming|bluesun|dnd|nosleep, on: bool, kelvin?}
  POST /api/system      {target: volume|brightness, value: 0..100}
  POST /api/media       {action: playpause|next|prev}
  POST /api/action      {name: wallpaper_next|lock|screenshot|clipboard_copy}
  GET  /api/clipboard               → 3 dernières entrées cliphist
  GET  /api/player                  → piste en cours (playerctl)
"""

import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import clock as clockmod          # noqa: E402
import modes as modesmod          # noqa: E402

PORT = int(os.environ.get("SASQUATCH_SIDEBAR_PORT", "8778"))
HOST = "127.0.0.1"
CC_DIR = os.path.expanduser("~/.config/cc")
CC_PORT = 8765

STATE_HOME = os.environ.get("XDG_STATE_HOME",
                            os.path.join(os.path.expanduser("~"), ".local", "state"))
STATE_DIR = os.path.join(STATE_HOME, "sasquatch")
STATE_FILE = os.path.join(STATE_DIR, "sidebar-state.json")

PALETTE_FALLBACK = {   # secours Catppuccin — même défaut que cc/palette.py
    "bg": "#1e1e2e", "bgSolid": "#181825", "card": "#181825",
    "cardSolid": "#181825", "text": "#cdd6f4", "textDim": "#a6adc8",
    "accent": "#89b4fa", "accent2": "#94e2d5", "overlay": "#000000",
    "good": "#a6e3a1", "warn": "#f9e2af", "hot": "#f38ba8",
}

LOCK = threading.RLock()
REQ_COUNT = {}        # {path: n} — sert aux tests (« le QML interroge bien »)
STATE = {}
CLOCK = None
MODES = None
DIRTY = {"v": False}


# ── état persistant ───────────────────────────────────────────────────────

def load_state():
    try:
        with open(STATE_FILE, encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, dict):
                return data
    except (OSError, ValueError):
        pass
    return {}


def save_state():
    os.makedirs(STATE_DIR, exist_ok=True)
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(STATE, f, ensure_ascii=False, indent=1)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, STATE_FILE)     # atomique : jamais de JSON tronqué
    DIRTY["v"] = False


def mark_dirty():
    DIRTY["v"] = True


def _default_state():
    return {"todo": [], "next_todo_id": 1, "stopwatch": {}, "timer": {},
            "alarms": [], "events": [], "event_seq": 0,
            "modes": {}, "modes_saved": {}, "procs": {}}


# ── palette : on consomme le mécanisme existant ───────────────────────────

def read_palette():
    """1) cc/palette.py (source de vérité, lit qml/Palette.qml)
       2) GET http://127.0.0.1:8765/api/palette (le CC)
       3) défauts."""
    try:
        if CC_DIR not in sys.path:
            sys.path.insert(0, CC_DIR)
        import palette as cc_palette            # noqa: WPS433
        return cc_palette.read_palette()
    except Exception:
        pass
    try:
        with urllib.request.urlopen(
                "http://127.0.0.1:%d/api/palette" % CC_PORT, timeout=2) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception:
        return dict(PALETTE_FALLBACK)


def _cc_post(path, payload=None, timeout=8):
    """POST vers le CC existant (screenshot / wallpaper) — on consomme."""
    data = json.dumps(payload or {}).encode("utf-8")
    req = urllib.request.Request(
        "http://127.0.0.1:%d%s" % (CC_PORT, path), data=data,
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8") or "{}")


def _cc_get(path, timeout=8):
    with urllib.request.urlopen("http://127.0.0.1:%d%s" % (CC_PORT, path),
                                timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8") or "{}")


# ── helpers système ───────────────────────────────────────────────────────

def _run(cmd, timeout=6):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except FileNotFoundError:
        return 127, "", "%s introuvable" % cmd[0]
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"


def set_volume(value):
    if not shutil.which("wpctl"):
        return {"ok": False, "error": "wpctl absent"}
    v = max(0.0, min(1.0, float(value) / 100.0))
    rc, _, err = _run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@",
                       "%.2f" % v])
    return {"ok": rc == 0, "volume": round(v * 100), "err": err}


def get_volume():
    if not shutil.which("wpctl"):
        return {"ok": False, "volume": 0, "muted": False}
    rc, out, _ = _run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"])
    m = re.search(r"Volume:\s*([0-9.]+)", out or "")
    if not m:
        # pas de sink par défaut (session sans audio) : on le dit, on ne
        # renvoie pas un faux 0 % silencieux.
        return {"ok": False, "volume": 0, "muted": False,
                "error": (out or "").strip()[:120] or "aucun sink par défaut"}
    return {"ok": rc == 0, "volume": int(round(float(m.group(1)) * 100)),
            "muted": "[MUTED]" in (out or "")}


def get_brightness():
    if not shutil.which("brightnessctl"):
        return {"ok": False, "brightness": 0}
    rc, out, _ = _run(["brightnessctl", "-m"])
    # format observé : "intel_backlight,backlight,26666,100%,26666"
    # → le pourcentage n'est pas toujours en 5e position : on prend le
    # premier champ de la forme NN%.
    pct = 0
    for field in (out or "").split(","):
        m = re.match(r"\s*(\d+)%\s*$", field)
        if m:
            pct = int(m.group(1))
            break
    return {"ok": rc == 0 and bool(out), "brightness": pct,
            "error": "" if out else "brightnessctl: sortie vide"}


def set_brightness(value):
    if not shutil.which("brightnessctl"):
        return {"ok": False, "error": "brightnessctl absent"}
    pct = max(1, min(100, int(value)))
    rc, _, err = _run(["brightnessctl", "set", "%d%%" % pct])
    return {"ok": rc == 0, "brightness": pct, "err": err}


def player_status():
    if not shutil.which("playerctl"):
        return {"ok": False, "error": "playerctl absent"}
    def q(fmt):
        rc, out, _ = _run(["playerctl", "metadata", "--format", fmt])
        return out if rc == 0 else ""
    return {"ok": True, "title": q("{{title}}"), "artist": q("{{artist}}"),
            "status": q("{{status}}")}


def clipboard_entries(n=3):
    if not shutil.which("cliphist"):
        return {"ok": False, "error": "cliphist absent", "items": []}
    rc, out, _ = _run(["cliphist", "list"])
    items = []
    for line in (out or "").splitlines()[:n]:
        cid, _, preview = line.partition("\t")
        # cliphist rend les images en brut : "[[ binary data 189 KiB png 342x691 ]]".
        # Illisible dans la sidebar → on le résume. Le texte multi-lignes est
        # aplati et coupé court (une ligne = une entrée).
        p = preview.strip()
        m = re.match(r"\[\[\s*binary data\s+([\d.]+\s*\w+)\s+(\w+)\s+(\d+x\d+)\s*\]\]", p)
        if m:
            p = "image %s · %s · %s" % (m.group(2).upper(), m.group(3), m.group(1))
        else:
            p = " ".join(p.split())
            if len(p) > 70:
                p = p[:69].rstrip() + "…"
        items.append({"id": cid, "preview": p})
    return {"ok": rc == 0, "items": items}


def clipboard_copy(cid):
    if not shutil.which("cliphist") or not shutil.which("wl-copy"):
        return {"ok": False, "error": "cliphist/wl-copy absent"}
    try:
        p1 = subprocess.Popen(["cliphist", "decode", str(cid)],
                              stdout=subprocess.PIPE)
        p2 = subprocess.Popen(["wl-copy"], stdin=p1.stdout)
        p1.stdout.close()
        p2.wait(timeout=5)
        return {"ok": p2.returncode == 0}
    except Exception as exc:
        return {"ok": False, "error": str(exc)}


def next_wallpaper():
    """Appelle le mécanisme existant : CC (/api/wallpaper/random puis apply,
    qui lance apply-wallpaper.sh) — on ne touche à aucun script."""
    try:
        pick = _cc_get("/api/wallpaper/random")
        if not pick.get("ok"):
            return {"ok": False, "error": pick.get("error", "aucun fond")}
        res = _cc_post("/api/wallpaper/apply", {"file": pick.get("path")})
        return {"ok": bool(res.get("ok")), "name": pick.get("name"),
                "path": pick.get("path"), "cc": res}
    except Exception as exc:
        return {"ok": False, "error": "CC 8765 injoignable (%s)" % exc}


# ── todo ──────────────────────────────────────────────────────────────────

def todo_counts():
    items = STATE["todo"]
    return {"total": len(items), "remaining": sum(1 for i in items if not i["done"]),
            "done": sum(1 for i in items if i["done"])}


def todo_action(body):
    action = body.get("action") or ""
    items = STATE["todo"]
    if action == "add":
        text = (body.get("text") or "").strip()
        if not text:
            return {"ok": False, "error": "texte vide"}
        item = {"id": STATE["next_todo_id"], "text": text[:300],
                "done": False, "prio": "high" if body.get("prio") == "high" else "normal",
                "ts": int(time.time())}
        STATE["next_todo_id"] += 1
        items.append(item)
        mark_dirty()
        return {"ok": True, "item": item}
    if action == "toggle":
        for it in items:
            if it["id"] == body.get("id"):
                it["done"] = not it["done"]
                it["done_ts"] = int(time.time()) if it["done"] else None
                mark_dirty()
                return {"ok": True, "item": it}
        return {"ok": False, "error": "tâche introuvable"}
    if action == "del":
        before = len(items)
        STATE["todo"] = [i for i in items if i["id"] != body.get("id")]
        if len(STATE["todo"]) == before:
            return {"ok": False, "error": "tâche introuvable"}
        mark_dirty()
        return {"ok": True}
    if action == "clear_done":
        n = sum(1 for i in items if i["done"])
        STATE["todo"] = [i for i in items if not i["done"]]
        mark_dirty()
        return {"ok": True, "removed": n}
    if action == "set_prio":
        for it in items:
            if it["id"] == body.get("id"):
                it["prio"] = "high" if it["prio"] != "high" else "normal"
                mark_dirty()
                return {"ok": True, "item": it}
        return {"ok": False, "error": "tâche introuvable"}
    return {"ok": False, "error": "action inconnue: %s" % action}


# ── ticker (le temps tourne sans aucune UI) ───────────────────────────────

def ticker():
    while True:
        try:
            with LOCK:
                fired = CLOCK.tick()
                if fired:
                    mark_dirty()
                if DIRTY["v"]:
                    save_state()
            for ev in fired:
                if ev["kind"] == "timer":
                    clockmod._notify("Timer terminé", ev["label"] or "Timer")
                else:
                    clockmod._notify("Alarme", ev["label"] or "")
        except Exception:
            pass
        time.sleep(0.5)


# ── HTTP ──────────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):        # journal plus discret
        sys.stderr.write("[sidebar] %s\n" % (fmt % args))

    def _json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _body_json(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
            if not n:
                return {}
            return json.loads(self.rfile.read(n).decode("utf-8"))
        except Exception:
            return {}

    # ── GET ──
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        qs = urllib.parse.parse_qs(parsed.query)
        REQ_COUNT[path] = REQ_COUNT.get(path, 0) + 1

        if path == "/api/health":
            self._json({"ok": True, "service": "sasquatch-sidebar",
                        "port": PORT, "pid": os.getpid(),
                        "state_file": STATE_FILE,
                        "requests": dict(REQ_COUNT)})
            return
        if path == "/api/palette":
            self._json(read_palette())
            return
        if path == "/api/env":
            with LOCK:
                env = MODES.env()
            # État RÉEL de hyprsunset : il peut tourner sans que la sidebar
            # l'ait lancé (démarré à la main, ou relancé par le service). Sans
            # ça, le bouton « Lumière bleue » s'affichait éteint alors que le
            # filtre était actif.
            env["hyprsunset_running"] = bool(
                subprocess.run(["pgrep", "-x", "hyprsunset"],
                               capture_output=True).returncode == 0)
            env.update({"volume": get_volume(), "brightness": get_brightness()})
            self._json(env)
            return
        if path == "/api/state":
            since = int((qs.get("since") or ["0"])[0] or 0)
            with LOCK:
                snap = CLOCK.snapshot()
                snap["todo"] = [dict(i) for i in STATE["todo"]]
                snap["counts"] = todo_counts()
                snap["modes"] = dict(STATE.get("modes", {}))
                snap["events"] = [e for e in snap["events"] if e["id"] > since]
                snap["server"] = True
            snap["volume"] = get_volume()
            snap["brightness"] = get_brightness()
            self._json(snap)
            return
        if path == "/api/clipboard":
            self._json(clipboard_entries(3))
            return
        if path == "/api/player":
            self._json(player_status())
            return
        if path == "/api/modes":
            with LOCK:
                self._json(MODES.status())
            return
        self._json({"ok": False, "error": "not found"}, 404)

    # ── POST ──
    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        REQ_COUNT["POST " + path] = REQ_COUNT.get("POST " + path, 0) + 1
        body = self._body_json()
        res = {"ok": False, "error": "not found"}

        with LOCK:
            if path == "/api/todo":
                res = todo_action(body)
            elif path == "/api/stopwatch":
                res = CLOCK.stopwatch(body.get("action") or "")
                mark_dirty()
                res["stopwatch"] = CLOCK.snapshot()["stopwatch"]
            elif path == "/api/timer":
                res = CLOCK.timer(body.get("action") or "start",
                                  body.get("seconds"),
                                  body.get("label") or "")
                mark_dirty()
            elif path == "/api/alarm":
                if (body.get("action") or "") == "add":
                    res = CLOCK.add_alarm(body.get("hhmm") or "",
                                          body.get("label") or "")
                elif body.get("action") == "del":
                    res = CLOCK.del_alarm(body.get("id"))
                else:
                    res = {"ok": False, "error": "action inconnue"}
                res["alarms"] = CLOCK.snapshot()["alarms"]
                mark_dirty()
            elif path == "/api/modes":
                res = MODES.set(body.get("mode") or "",
                                bool(body.get("on")), body.get("kelvin"))
                mark_dirty()
            if res.get("ok") or path in ("/api/todo", "/api/modes"):
                save_state()
        if path == "/api/system":
            target = body.get("target")
            if target == "volume":
                res = set_volume(body.get("value", 0))
            elif target == "brightness":
                res = set_brightness(body.get("value", 0))
        elif path == "/api/media":
            act = body.get("action")
            cmd = {"playpause": ["playerctl", "play-pause"],
                   "next": ["playerctl", "next"],
                   "prev": ["playerctl", "previous"]}.get(act)
            if not cmd:
                res = {"ok": False, "error": "action inconnue"}
            elif not shutil.which("playerctl"):
                res = {"ok": False, "error": "playerctl absent"}
            else:
                rc, _, err = _run(cmd)
                res = {"ok": rc == 0, "err": err, "player": player_status()}
        elif path == "/api/action":
            name = body.get("name")
            if name == "wallpaper_next":
                res = next_wallpaper()
            elif name == "lock":
                if shutil.which("hyprlock"):
                    subprocess.Popen(["hyprlock"], stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL)
                    res = {"ok": True}
                else:
                    res = {"ok": False, "error": "hyprlock absent"}
            elif name == "screenshot":
                if not shutil.which("grim"):
                    res = {"ok": False, "error": "grim absent"}
                else:
                    try:
                        res = _cc_post("/api/screenshot?mode=area")
                    except Exception as exc:
                        res = {"ok": False, "error": "CC injoignable (%s)" % exc}
            elif name == "clipboard_copy":
                res = clipboard_copy(body.get("id"))
            else:
                res = {"ok": False, "error": "action inconnue"}
        self._json(res)


def main():
    global STATE, CLOCK, MODES
    STATE = load_state()
    defaults = _default_state()
    for k, v in defaults.items():
        STATE.setdefault(k, v)
    CLOCK = clockmod.Clock(STATE)
    MODES = modesmod.ModeEngine(STATE)
    save_state()

    # Reprise après redémarrage du backend : si un mode « processus » était
    # actif (lumière bleue, anti-veille), on le relance. Sans ça, le filtre
    # restait éteint après un restart du service alors que l'état disait
    # « actif » — et la sidebar affichait un bouton allumé sans effet.
    def _reprendre_modes():
        try:
            eng = MODES                      # réf. locale (jamais None ici)
            m = STATE.get("modes") or {}
            if m.get("bluesun"):
                res = eng.set("bluesun", True, kelvin=m.get("kelvin"))
                print("[sidebar] reprise lumière bleue:", res.get("ok"),
                      flush=True)
            if m.get("nosleep"):
                eng.set("nosleep", True)
        except Exception as exc:          # jamais bloquant au démarrage
            print("[sidebar] reprise modes échouée:", exc, flush=True)

    threading.Thread(target=_reprendre_modes, daemon=True).start()
    threading.Thread(target=ticker, daemon=True).start()
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    srv.daemon_threads = True
    print("[sidebar] http://%s:%d (état: %s)" % (HOST, PORT, STATE_FILE),
          flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        with LOCK:
            MODES.shutdown()
            save_state()


if __name__ == "__main__":
    main()
