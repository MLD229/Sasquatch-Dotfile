#!/usr/bin/env python3
"""sysinfo.py — données du tableau de bord (profil système, mises à jour, tâches).

Aucune dépendance : lecture de /proc et /etc, plus `pacman -Qu` et `yay -Qua`
pour les mises à jour (avec cache, jamais bloquant pour le rendu).
"""
import json
import os
import platform
import re
import shutil
import socket
import subprocess
import time
import urllib.parse
import urllib.request

STATE_DIR = os.path.expanduser("~/.local/state/sasquatch-cc")
TASKS_FILE = os.path.join(STATE_DIR, "tasks.json")

_sys_cache = {"at": 0.0, "data": None}
_upd_cache = {"at": 0.0, "data": None}
_UPD_TTL = 900.0


def _read(path, default=""):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return default


def _distro():
    for line in _read("/etc/os-release").splitlines():
        if line.startswith("PRETTY_NAME="):
            return line.split("=", 1)[1].strip().strip('"')
    return platform.platform()


def _cpu():
    txt = _read("/proc/cpuinfo")
    m = re.search(r"^model name\s*:\s*(.+)$", txt, re.M)
    if m:
        return re.sub(r"\s+", " ", m.group(1)).strip()
    return platform.processor() or "CPU"


def _gpu():
    """GPU par lspci (rapide). Repli : /sys/class/drm/card*/device/uevent."""
    if shutil.which("lspci"):
        try:
            out = subprocess.run(["lspci"], capture_output=True, text=True, timeout=4).stdout
            gpus = []
            for line in out.splitlines():
                if re.search(r"\b(VGA|3D controller|Display)\b", line):
                    gpus.append(line.split(": ", 1)[-1].strip())
            if gpus:
                return " / ".join(gpus[:2])
        except (OSError, subprocess.SubprocessError):
            pass
    return ""


def _uptime():
    try:
        up = float(_read("/proc/uptime").split()[0])
    except (ValueError, IndexError):
        return 0
    return int(up)


def humain(sec):
    sec = int(sec)
    j, reste = divmod(sec, 86400)
    h, reste = divmod(reste, 3600)
    m = reste // 60
    if j:
        return "%dj %dh %02dm" % (j, h, m)
    if h:
        return "%dh %02dm" % (h, m)
    return "%dm" % m


def sysinfo():
    """Profil système pour la carte identité. Cache 60 s (l'uptime est recalculé)."""
    now = time.time()
    if not _sys_cache["data"] or now - _sys_cache["at"] > 60:
        _sys_cache["data"] = {
            "user": os.environ.get("USER") or os.getlogin() if hasattr(os, "getlogin") else
                    os.environ.get("USER", ""),
            "host": socket.gethostname(),
            "distro": _distro(),
            "kernel": platform.release(),
            "shell": os.path.basename(os.environ.get("SHELL", "")) or "?",
            "cpu": _cpu(),
            "cores": os.cpu_count() or 0,
            "gpu": _gpu(),
        }
        _sys_cache["at"] = now
    d = dict(_sys_cache["data"])
    d["uptime_s"] = _uptime()
    d["uptime"] = humain(d["uptime_s"])
    d["hour"] = int(time.strftime("%H"))
    return d


def _lignes(cmd, timeout):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError) as exc:
        return None, repr(exc)[:120]
    if p.returncode not in (0, 1):
        return None, (p.stderr or "").strip()[:120]
    return [l for l in (p.stdout or "").splitlines() if l.strip()], ""


def updates(max_age=_UPD_TTL):
    """{pacman, aur, total, ok, erreur, age_s}. Cache 15 min.

    pacman -Qu : paquets des dépôts à mettre à jour (nécessite une base
    synchronisée — sinon la liste est vide sans erreur, on le dit).
    yay -Qua   : paquets AUR à mettre à jour (réseau, ~1-3 s).
    """
    now = time.time()
    if _upd_cache["data"] is not None and now - _upd_cache["at"] < max_age:
        d = dict(_upd_cache["data"])
        d["age_s"] = int(now - _upd_cache["at"])
        return d
    pac, err1 = _lignes(["pacman", "-Qu"], 12)
    aur = []
    err2 = ""
    if shutil.which("yay"):
        aur, err2 = _lignes(["yay", "-Qua", "--aur"], 25) or ([], "")
    ok = pac is not None
    d = {
        "pacman": len(pac or []),
        "aur": len(aur or []),
        "total": len(pac or []) + len(aur or []),
        "ok": ok,
        "erreur": err1 or err2,
        "verifie": time.strftime("%H:%M"),
    }
    _upd_cache.update({"at": now, "data": d})
    d = dict(d)
    d["age_s"] = 0
    return d


def _tasks_read():
    try:
        with open(TASKS_FILE, "r", encoding="utf-8") as fh:
            d = json.load(fh)
        if isinstance(d, dict) and isinstance(d.get("items"), list):
            return d
    except (OSError, ValueError):
        pass
    return {"items": []}


def _tasks_write(d):
    os.makedirs(STATE_DIR, exist_ok=True)
    tmp = TASKS_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(d, fh, ensure_ascii=False, indent=1)
    os.replace(tmp, TASKS_FILE)


def tasks(action="list", **kw):
    """Liste / ajoute / coche / supprime une tâche. Écriture atomique."""
    d = _tasks_read()
    items = d["items"]
    if action == "add":
        t = (kw.get("text") or "").strip()
        if t:
            items.append({"id": int(time.time() * 1000), "text": t[:200],
                          "done": False, "at": time.strftime("%Y-%m-%d %H:%M")})
            _tasks_write(d)
    elif action == "toggle":
        for it in items:
            if str(it.get("id")) == str(kw.get("id")):
                it["done"] = not it.get("done")
                break
        _tasks_write(d)
    elif action == "remove":
        d["items"] = [it for it in items if str(it.get("id")) != str(kw.get("id"))]
        _tasks_write(d)
    elif action == "clear":
        d["items"] = [it for it in items if not it.get("done")]
        _tasks_write(d)
    items = d["items"]
    return {"items": items, "total": len(items),
            "done": len([i for i in items if i.get("done")])}


# ── Météo (open-meteo, sans clé) ────────────────────────────────────────────
WMO = {0: "ciel dégagé", 1: "plutôt dégagé", 2: "partiellement nuageux", 3: "couvert",
       45: "brouillard", 48: "brouillard givrant", 51: "bruine", 53: "bruine",
       55: "bruine dense", 61: "pluie faible", 63: "pluie", 65: "forte pluie",
       71: "neige faible", 73: "neige", 75: "forte neige", 80: "averses",
       81: "averses", 82: "fortes averses", 95: "orage", 96: "orage grêle",
       99: "orage violent"}
_wx_cache = {"at": 0.0, "city": None, "data": None}
_WX_TTL = 600.0


def _get_json(url, timeout=6):
    req = urllib.request.Request(url, headers={"User-Agent": "sasquatch-cc/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def weather(city=None):
    """{ok, city, temp, code, label, lat, lon, age_s}. open-meteo, cache 10 min."""
    city = (city or "").strip() or "Lyon"
    now = time.time()
    c = _wx_cache
    if c["data"] and c["city"] == city and now - c["at"] < _WX_TTL:
        d = dict(c["data"])
        d["age_s"] = int(now - c["at"])
        return d
    try:
        g = _get_json("https://geocoding-api.open-meteo.com/v1/search?"
                      + urllib.parse.urlencode({"name": city, "count": 1, "language": "fr"}))
        hit = (g.get("results") or [{}])[0]
        lat, lon = hit.get("latitude"), hit.get("longitude")
        nom = hit.get("name") or city
        if lat is None:
            raise ValueError("ville introuvable")
        f = _get_json("https://api.open-meteo.com/v1/forecast?"
                      + urllib.parse.urlencode({"latitude": lat, "longitude": lon,
                                                "current": "temperature_2m,weather_code",
                                                "timezone": "auto"}))
        cur = f.get("current") or {}
        code = int(cur.get("weather_code") or 0)
        data = {"ok": True, "city": nom, "temp": round(cur.get("temperature_2m") or 0),
                "code": code, "label": WMO.get(code, "—"),
                "lat": lat, "lon": lon}
    except Exception as exc:  # noqa: BLE001
        data = {"ok": False, "city": city, "erreur": repr(exc)[:120],
                "temp": None, "code": None, "label": "indisponible"}
    _wx_cache.update({"at": now, "city": city, "data": data})
    d = dict(data)
    d["age_s"] = 0
    return d
