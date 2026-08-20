#!/usr/bin/env python3
"""Sasquatch Settings - backend HTTP (stdlib only, 127.0.0.1:8770).

Panneau de configuration du dotfile (Super+I) : veille (hypridle), palette,
horloge (waybar + hyprlock), raccourcis clavier (keybinds-user.conf) et
options du CC. Lit/écrit ~/.config/settings/settings.json (symlinké vers
settings/settings.json du repo) et ne modifie QUE la section concernée.

Conventions (identiques au CC) :
  - réponses JSON avec Content-Length (keep-alive HTTP/1.1)
  - 404 avec Content-Length: 0 (sinon le client QML bloque)
  - jamais d'écriture de settings.json pendant un GET
"""

import hashlib
import json
import os
import re
import signal
import subprocess
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = 8770

HOME = os.path.expanduser("~")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Chemins live (~/.config/* est symlinké vers le repo). realpath() protège
# contre les symlinks de FICHIER : on écrit toujours la cible réelle.
SETTINGS_JSON = os.path.realpath(
    os.path.join(HOME, ".config", "settings", "settings.json"))
HYPRIDLE_CONF = os.path.realpath(
    os.path.join(HOME, ".config", "hypr", "hypridle.conf"))
KEYBINDS_USER_CONF = os.path.realpath(
    os.path.join(REPO, "hypr", "keybinds-user.conf"))
WAYBAR_CONFIG = os.path.realpath(os.path.join(REPO, "waybar", "config"))

# Lectures (symlinks de dossier : équivalents repo/live).
PALETTE_QML = os.path.join(HOME, ".config", "cc", "qml", "Palette.qml")
KEYBINDS_CONF = os.path.join(REPO, "hypr", "keybinds.conf")
THEME_APPLY = os.path.join(HOME, ".config", "scripts", "theme-apply.sh")

# ── Système (gaps/rounding/animations — section SYSTÈME du panneau) ────────
GENERAL_CONF = os.path.join(REPO, "hypr", "conf.d", "general.conf")
DECORATION_CONF = os.path.join(REPO, "hypr", "conf.d", "decoration.conf")
ANIMATIONS_CONF = os.path.join(REPO, "hypr", "conf.d", "animations.conf")

# ---------------------------------------------------------------------------
# Palette (qml/Palette.qml régénéré par theme-apply.py)
# Format : `    readonly property color bg: "#1e1e2e"` (une ligne par propriété)
# ---------------------------------------------------------------------------
PALETTE_DEFAULTS = {
    "bg": "#1e1e2e", "bgSolid": "#181825", "card": "#181825", "cardSolid": "#181825",
    "text": "#cdd6f4", "textDim": "#a6adc8", "accent": "#89b4fa", "accent2": "#94e2d5",
    "overlay": "#000000", "good": "#a6e3a1", "warn": "#f9e2af", "hot": "#f38ba8",
}

# ARGB 8-hex accepté (Palette.qml contient overlay "#99021933", accent2 "#443d39a6")
_RE_PALETTE = re.compile(r'readonly property color (\w+): "?(#[0-9a-fA-F]{6,8})"?')

# ---------------------------------------------------------------------------
# Keybinds (hypr/keybinds.conf)
# ---------------------------------------------------------------------------
_RE_BIND = re.compile(r"^(bind|bindl|binde|bindel|bindr|bindm)\s*=\s*(.+)$")
_BIND_TYPES = ("bind", "bindl", "binde", "bindel", "bindr", "bindm")

# ---------------------------------------------------------------------------
# Template hypridle.conf (timeouts en SECONDES = minutes × 60)
# ---------------------------------------------------------------------------
HYPRIDLE_TEMPLATE = """# hypridle.conf — régénéré par le panneau Settings (Super+I)

general {
    lock_cmd = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch dpms on
    ignore_dbus_inhibit = false
}

# Diminue luminosité après {DIM}s
listener {
    timeout = {DIM}
    on-timeout = brightnessctl -s set 30%
    on-resume = brightnessctl -r
}

# Lock après {LOCK}s
listener {
    timeout = {LOCK}
    on-timeout = loginctl lock-session
}

# Écran off après {OFF}s
listener {
    timeout = {OFF}
    on-timeout = hyprctl dispatch dpms off
    on-resume = hyprctl dispatch dpms on
}

# Suspend après {SUSPEND}s
listener {
    timeout = {SUSPEND}
    on-timeout = systemctl suspend
}
"""

# Variante MINIMALE quand idle est désactivé : hypridle tourne pour le
# lock_cmd (lock au capot via logind → hyprlock) mais SANS les timeouts
# de veille (dim/lock auto/off/suspend).
HYPRIDLE_TEMPLATE_LOCK_ONLY = """# hypridle.conf — régénéré par le panneau Settings (Super+I)
# Mode idle désactivé : hypridle tourne UNIQUEMENT pour le lock au capot.
# (logind HandleLidSwitch=lock → lock-session → lock_cmd → hyprlock)

general {
    lock_cmd = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch dpms on
    ignore_dbus_inhibit = false
}
"""


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def _read_settings():
    try:
        with open(SETTINGS_JSON, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _write_settings(data):
    tmp = SETTINGS_JSON + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4)
        f.write("\n")
    os.replace(tmp, SETTINGS_JSON)


def _safe_minutes(v, default):
    try:
        return max(1, int(v))
    except (TypeError, ValueError):
        return default


def _hypridle_running():
    try:
        r = subprocess.run(["pgrep", "-x", "hypridle"],
                           capture_output=True, timeout=3)
        return r.returncode == 0
    except Exception:
        return False


def _run_theme_apply():
    """~/.config/scripts/theme-apply.sh sans argument : relit le wallpaper
    (waypaper) et relance waybar/hyprlock. Timeout 60 s, stderr capturé."""
    try:
        cmd = [THEME_APPLY]
        if not os.access(THEME_APPLY, os.X_OK):
            cmd = ["bash", THEME_APPLY]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        return r.returncode == 0
    except subprocess.TimeoutExpired:
        return False
    except Exception:
        return False


# ---------------------------------------------------------------------------
# palette
# ---------------------------------------------------------------------------
def _read_palette():
    """Parse qml/Palette.qml ; fallback Catppuccin Mocha si absent/corrompu."""
    try:
        with open(PALETTE_QML, encoding="utf-8") as f:
            content = f.read()
    except OSError:
        return dict(PALETTE_DEFAULTS)
    found = {}
    for m in _RE_PALETTE.finditer(content):
        found[m.group(1)] = m.group(2)
    out = {}
    for key, default in PALETTE_DEFAULTS.items():
        out[key] = found.get(key, default)
    return out


# ---------------------------------------------------------------------------
# keybinds
# ---------------------------------------------------------------------------
def _parse_keybinds():
    """Parse hypr/keybinds.conf.

    Pour chaque ligne bind/bindl/binde/bindel/bindr/bindm (hors commentaires,
    gesture et source) : {"id": md5(8), "type", "mods" ($mod→SUPER),
    "key", "dispatcher", "arg", "section" (dernier en-tête "# ──"), "line"}.
    L'id est calculé sur la ligne stripée (stable GET → POST).
    """
    binds = []
    section = ""
    try:
        with open(KEYBINDS_CONF, encoding="utf-8") as f:
            lines = f.readlines()
    except OSError:
        return binds

    for raw in lines:
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#"):
            if line.startswith("# ──"):
                s = line.strip("# ").strip("─").strip()
                if s:
                    section = s
            continue
        if line.startswith("gesture") or line.startswith("source"):
            continue
        m = _RE_BIND.match(line)
        if not m:
            continue
        bind_type = m.group(1)
        body = m.group(2)
        # commentaire inline
        if "#" in body:
            body = body.split("#", 1)[0]
        parts = [p.strip() for p in body.split(",")]
        mods = parts[0] if len(parts) > 0 else ""
        key = parts[1] if len(parts) > 1 else ""
        dispatcher = parts[2] if len(parts) > 2 else ""
        arg = ",".join(parts[3:]).strip() if len(parts) > 3 else ""
        # espaces multiples nettoyés (résout aussi "resizeactive,  30 0")
        mods = re.sub(r"\s+", " ", mods).strip()
        key = re.sub(r"\s+", " ", key).strip()
        dispatcher = re.sub(r"\s+", " ", dispatcher).strip()
        arg = re.sub(r"\s+", " ", arg).strip()
        binds.append({
            "id": hashlib.md5(line.encode("utf-8")).hexdigest()[:8],
            "type": bind_type,
            "mods": re.sub(r"\s+", " ", mods.replace("$mod", "SUPER")).strip(),
            "key": key,
            "dispatcher": dispatcher,
            "arg": arg,
            "section": section,
            "line": line,
        })
    return binds


def _keybinds_header():
    """Lignes de commentaire (#) actuelles de keybinds-user.conf."""
    header = []
    try:
        with open(KEYBINDS_USER_CONF, encoding="utf-8") as f:
            for ln in f:
                if ln.startswith("#"):
                    header.append(ln)
    except OSError:
        pass
    if not header:
        header = [
            "# keybinds-user.conf — overrides écrits par le panneau Settings (Super+I)\n",
            "# Les binds ci-dessous surchargent ceux de keybinds.conf (dernier gagnant).\n",
            "# Fichier versionné : vide = aucun override.\n",
        ]
    return header


def _post_keybinds(body):
    """Écrit un override dans keybinds-user.conf (en-tête conservé)."""
    bid = (body.get("id") or "").strip()
    command = (body.get("command") or "").strip()
    target = None
    for b in _parse_keybinds():
        if b["id"] == bid:
            target = b
            break
    if not target:
        return {"ok": False, "error": "bind introuvable"}

    # split sur la première virgule : dispatcher + arg (arg vide si absent)
    if "," in command:
        dispatcher, _, arg = command.partition(",")
        dispatcher = re.sub(r"\s+", " ", dispatcher).strip()
        arg = re.sub(r"\s+", " ", arg).strip()
    else:
        dispatcher = re.sub(r"\s+", " ", command).strip()
        arg = ""

    bind_type = target["type"]
    mods = target["mods"]          # déjà résolu ($mod → SUPER)
    key = target["key"]
    if arg:
        new_line = ("%s = %s, %s, %s, %s  # overridden via Settings"
                    % (bind_type, mods, key, dispatcher, arg))
    else:
        new_line = ("%s = %s, %s, %s  # overridden via Settings"
                    % (bind_type, mods, key, dispatcher))

    # Relire le fichier : en-tête # conservé, overrides existants conservés,
    # celui qui matche (type+mods+key) remplacé pour éviter les doublons.
    header = _keybinds_header()
    kept = []
    try:
        with open(KEYBINDS_USER_CONF, encoding="utf-8") as f:
            for ln in f:
                if ln.startswith("#"):
                    continue
                s = ln.strip()
                m = _RE_BIND.match(s)
                if m and m.group(1) == bind_type:
                    b = m.group(2).split("#", 1)[0]
                    bp = [x.strip() for x in b.split(",")]
                    if len(bp) >= 2:
                        bmods = re.sub(r"\s+", " ", bp[0].replace("$mod", "SUPER")).strip()
                        bkey = bp[1].strip()
                        if bmods == mods and bkey == key:
                            continue  # remplacé par new_line
                kept.append(ln)
    except OSError:
        kept = []

    content = "".join(header) + "".join(kept)
    if content and not content.endswith("\n"):
        content += "\n"
    content += new_line + "\n"
    with open(KEYBINDS_USER_CONF, "w", encoding="utf-8") as f:
        f.write(content)

    subprocess.run(["hyprctl", "reload"], capture_output=True, timeout=10)
    return {"ok": True}


def _post_keybinds_reset():
    """keybinds-user.conf réduit à son en-tête commentaire, puis reload."""
    header = _keybinds_header()
    with open(KEYBINDS_USER_CONF, "w", encoding="utf-8") as f:
        f.writelines(header)
    subprocess.run(["hyprctl", "reload"], capture_output=True, timeout=10)
    return {"ok": True}


# ---------------------------------------------------------------------------
# POST handlers
# ---------------------------------------------------------------------------
def _post_veille(body):
    settings = _read_settings()
    idle = settings.get("idle", {})
    enabled = bool(body.get("enabled", idle.get("enabled", True)))
    dim_min = _safe_minutes(body.get("dim_min"), idle.get("dim_min", 3))
    lock_min = _safe_minutes(body.get("lock_min"), idle.get("lock_min", 5))
    off_min = _safe_minutes(body.get("off_min"), idle.get("off_min", 7))
    suspend_min = _safe_minutes(body.get("suspend_min"), idle.get("suspend_min", 15))
    settings["idle"] = {
        "enabled": enabled,
        "dim_min": dim_min,
        "lock_min": lock_min,
        "off_min": off_min,
        "suspend_min": suspend_min,
    }
    _write_settings(settings)

    # Template complet si idle activé, sinon lock-only (hypridle tourne
    # quand même : lock_cmd = lock au capot via logind)
    if enabled:
        conf = (HYPRIDLE_TEMPLATE
                .replace("{DIM}", str(dim_min * 60))
                .replace("{LOCK}", str(lock_min * 60))
                .replace("{OFF}", str(off_min * 60))
                .replace("{SUSPEND}", str(suspend_min * 60)))
    else:
        conf = HYPRIDLE_TEMPLATE_LOCK_ONLY
    tmp = HYPRIDLE_CONF + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(conf)
    os.replace(tmp, HYPRIDLE_CONF)

    # restart hypridle : pkill systématique, relance TOUJOURS (même si
    # idle désactivé — lock au capot dépend de lock_cmd)
    subprocess.run(["pkill", "-x", "hypridle"], capture_output=True, timeout=5)
    try:
        devnull = open(os.devnull, "w")
        subprocess.Popen(["hypridle"], stdout=devnull, stderr=devnull,
                         start_new_session=True)
        devnull.close()
    except Exception:
        pass
    return {"ok": True, "hypridle": _hypridle_running()}


def _post_palette(body):
    settings = _read_settings()
    pal = settings.get("palette", {})
    mode = body.get("mode", pal.get("mode", "auto"))
    accent = body.get("accent", pal.get("accent", "#88aaee"))
    accent2 = body.get("accent2", pal.get("accent2", "#aa88ff"))
    settings["palette"] = {"mode": mode, "accent": accent, "accent2": accent2}
    _write_settings(settings)
    applied = _run_theme_apply()
    return {"ok": True, "applied": applied}


def _post_clock(body):
    settings = _read_settings()
    clk = settings.get("clock", {})
    waybar_format = body.get("waybar_format",
                             clk.get("waybar_format", "\uf5d4  {:%H:%M   %d %b}"))
    lock_24h = bool(body.get("lock_24h", clk.get("lock_24h", True)))
    lock_date = bool(body.get("lock_date", clk.get("lock_date", True)))
    settings["clock"] = {
        "waybar_format": waybar_format,
        "lock_24h": lock_24h,
        "lock_date": lock_date,
    }
    _write_settings(settings)

    # Patch du module "clock" de waybar/config (JSONC sans extension).
    # ensure_ascii=False : on écrit le glyph en UTF-8 brut (comme l'original),
    # pas en escape \uXXXX que waybar n'interpréterait pas.
    try:
        with open(WAYBAR_CONFIG, encoding="utf-8") as f:
            content = f.read()
        esc = json.dumps(waybar_format, ensure_ascii=False)[1:-1]
        pat = re.compile(r'("clock":\s*\{[^}]*?"format":\s*")[^"]*(")')
        new_content, n = pat.subn(
            lambda m: m.group(1) + esc + m.group(2), content, count=1)
        if n:
            with open(WAYBAR_CONFIG, "w", encoding="utf-8") as f:
                f.write(new_content)
    except OSError:
        pass

    _run_theme_apply()  # recharge waybar + hyprlock
    return {"ok": True}


def _post_cc(body):
    settings = _read_settings()
    cc = settings.get("cc", {})
    cava = bool(body.get("cava", cc.get("cava", True)))
    ocr_lang = body.get("ocr_lang", cc.get("ocr_lang", "fra"))
    cover_art = bool(body.get("cover_art", cc.get("cover_art", True)))
    settings["cc"] = {"cava": cava, "ocr_lang": ocr_lang, "cover_art": cover_art}
    _write_settings(settings)
    return {"ok": True}


# ---------------------------------------------------------------------------
# Système (section SYSTÈME : gaps, rounding, animations, wallpaper)
# ---------------------------------------------------------------------------
def _safe_int(v, default):
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


def _patch_file(fpath, pat, repl):
    """Remplace la 1re occurrence du pattern ; écrit seulement si changé."""
    try:
        with open(fpath, encoding="utf-8") as f:
            content = f.read()
    except OSError:
        return False
    new = re.sub(pat, repl, content, count=1)
    if new != content:
        with open(fpath, "w", encoding="utf-8") as f:
            f.write(new)
        return True
    return False


def _read_system():
    def _grab(fpath, pat, default):
        try:
            with open(fpath, encoding="utf-8") as f:
                m = re.search(pat, f.read())
            return int(m.group(1)) if m else default
        except OSError:
            return default
    anim = True
    try:
        with open(ANIMATIONS_CONF, encoding="utf-8") as f:
            am = re.search(r"enabled\s*=\s*(true|false)", f.read())
        anim = am.group(1) != "false" if am else True
    except OSError:
        pass
    return {
        "gaps_in": _grab(GENERAL_CONF, r"gaps_in\s*=\s*(\d+)", 5),
        "gaps_out": _grab(GENERAL_CONF, r"gaps_out\s*=\s*(\d+)", 10),
        "rounding": _grab(DECORATION_CONF, r"rounding\s*=\s*(\d+)", 12),
        "animations": anim,
    }


def _post_system(body):
    gaps_in = max(0, min(30, _safe_int(body.get("gaps_in"), 5)))
    gaps_out = max(0, min(50, _safe_int(body.get("gaps_out"), 10)))
    rounding = max(0, min(30, _safe_int(body.get("rounding"), 12)))
    animations = bool(body.get("animations", True))
    _patch_file(GENERAL_CONF, r"gaps_in\s*=\s*\d+", "gaps_in = %d" % gaps_in)
    _patch_file(GENERAL_CONF, r"gaps_out\s*=\s*\d+", "gaps_out = %d" % gaps_out)
    _patch_file(DECORATION_CONF, r"rounding\s*=\s*\d+", "rounding = %d" % rounding)
    _patch_file(ANIMATIONS_CONF, r"enabled\s*=\s*(true|false)",
                "enabled = %s" % ("true" if animations else "false"))
    subprocess.run(["hyprctl", "reload"], capture_output=True, timeout=10)
    return {"ok": True, "system": _read_system()}


def _post_wallpaper(body=None):
    """Ouvre le sélecteur de wallpaper (toggle, comme le keybind SUPER+Y)."""
    try:
        subprocess.run(["bash", "-c", os.path.join(HOME, ".config", "wp", "wp.sh")],
                       timeout=3)
        return {"ok": True}
    except Exception:
        return {"ok": False}


# ---------------------------------------------------------------------------
# HTTP handler
# ---------------------------------------------------------------------------
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

    def _not_found(self):
        # Piège du projet : Content-Length: 0 obligatoire sur les 404,
        # sinon le client QML reste bloqué (keep-alive HTTP/1.1).
        self.send_response(404)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", "0")
        self.end_headers()

    # -- GET ---------------------------------------------------------------
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/":
            body = (b"<html><head><title>SasquatchSettings</title></head>"
                    b"<body><h1>SasquatchSettings</h1>"
                    b"<p>Serveur actif (127.0.0.1:8770).</p></body></html>")
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/api/health":
            self._json({"ok": True})
            return
        if path == "/api/state":
            self._json({"settings": _read_settings(),
                        "hypridle": _hypridle_running(),
                        "ok": True})
            return
        if path == "/api/palette":
            self._json(_read_palette())
            return
        if path == "/api/system":
            self._json(_read_system())
            return
        if path == "/api/keybinds":
            self._json({"keybinds": _parse_keybinds(), "ok": True})
            return
        self._not_found()

    # -- POST --------------------------------------------------------------
    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        body = self._body_json()

        if path == "/api/veille":
            self._json(_post_veille(body))
            return
        if path == "/api/palette":
            self._json(_post_palette(body))
            return
        if path == "/api/clock":
            self._json(_post_clock(body))
            return
        if path == "/api/keybinds/reset":
            self._json(_post_keybinds_reset())
            return
        if path == "/api/keybinds":
            self._json(_post_keybinds(body))
            return
        if path == "/api/cc":
            self._json(_post_cc(body))
            return
        if path == "/api/system":
            self._json(_post_system(body))
            return
        if path == "/api/wallpaper":
            self._json(_post_wallpaper(body))
            return
        if path == "/api/close":
            self._json({"ok": True})

            def _shutdown():
                time.sleep(0.3)
                os._exit(0)

            threading.Thread(target=_shutdown, daemon=True).start()
            return
        self._not_found()


def _handle_sig(signum, frame):
    os._exit(0)


def main():
    signal.signal(signal.SIGTERM, _handle_sig)
    signal.signal(signal.SIGINT, _handle_sig)
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
