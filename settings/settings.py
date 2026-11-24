#!/usr/bin/env python3
"""Sasquatch Settings - backend HTTP (stdlib only, 127.0.0.1:8770).

Panneau de configuration du dotfile (Super+I) : veille (hypridle), palette,
horloge (waybar + hyprlock), raccourcis clavier (hypr/keybinds-user.lua) et
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
KEYBINDS_USER_LUA = os.path.realpath(
    os.path.join(REPO, "hypr", "keybinds-user.lua"))
APPLY_LANG = os.path.join(REPO, "scripts", "apply-lang.sh")

# ── Barre verticale Quickshell (cc/bar) ────────────────────────────────────
# Source unique des options de la barre : cc/bar/bar.json. Le panneau ne
# duplique RIEN dans settings.json ; il lit ce fichier et délègue toute
# écriture à barjson.py --set (garde-fou : bornes par clé, écriture atomique,
# ordre et indentation du fichier préservés).
BAR_JSON = os.path.realpath(os.path.join(HOME, ".config", "cc", "bar", "bar.json"))
BAR_WRITER = os.path.join(REPO, "cc", "bar", "barjson.py")
# Chemin de clé exposé par le panneau -> libellé du contrôle (documentation)
BAR_KEYS = {
    "bar.position": "position",
    "bar.width": "width",
    "bar.blur": "blur",
    "bar.persistentWorkspaces": "persistentWorkspaces",
    "appearance.blockAlpha": "blockAlpha",
    "appearance.hoverAlpha": "hoverAlpha",
    "appearance.cardAlpha": "cardAlpha",
    "runningApps.maxVisible": "maxVisible",
}
# Positions réellement honorées par la barre (cc/bar/shell.qml) : l'écriture
# est refusée en dehors de ce choix, même si barjson.py a la même table.
BAR_POSITIONS = ("left", "top", "right")

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
# hyprlang → Lua (Hyprland >= 0.57 : plus de hyprlang, dispatchers hl.dsp.*)
# ---------------------------------------------------------------------------
# Le panneau laisse taper la commande en syntaxe historique (« exec, kitty »).
# Elle est TRADUITE ici : keybinds-user.lua ne contient que du Lua.
_BIND_FLAGS = {
    "bind": "",
    "bindr": "release = true",
    "bindm": "mouse = true",
    "bindl": "locked = true",
    "binde": "repeating = true",
    "bindel": "locked = true, repeating = true",
}
_DIRECTIONS = {"l": "left", "r": "right", "u": "up", "d": "down",
               "left": "left", "right": "right", "up": "up", "down": "down"}


def _lua_str(s):
    """Chaîne Lua échappée (guillemets doubles)."""
    return '"%s"' % str(s).replace("\\", "\\\\").replace('"', '\\"')


def _lua_dispatcher(dispatcher, arg):
    """« dispatcher, arg » hyprlang → expression Lua hl.dsp.*.

    None = aucun équivalent connu : l'appelant écrit la ligne en COMMENTAIRE
    (rien ne casse, l'utilisateur voit ce qu'il doit adapter à la main)."""
    d = re.sub(r"\s+", " ", (dispatcher or "")).strip().lower()
    a = re.sub(r"\s+", " ", (arg or "")).strip()

    if d == "exec":
        return "hl.dsp.exec_cmd(%s)" % _lua_str(a)
    if d in ("killactive", "closewindow"):
        return "hl.dsp.window.close()"
    if d == "exit":
        return "hl.dsp.exit()"
    if d == "workspace":
        return "hl.dsp.focus({ workspace = %s })" % _lua_str(a or "1")
    if d in ("movetoworkspace", "movetoworkspacesilent"):
        ws = a.split(",")[0].strip() or "1"
        # « silent » (pas de hyprlang) = follow = false : l'écran ne suit pas.
        follow = "false" if d.endswith("silent") else "true"
        return "hl.dsp.window.move({ workspace = %s, follow = %s })" % (_lua_str(ws), follow)
    if d == "togglespecialworkspace":
        return "hl.dsp.workspace.toggle_special(%s)" % _lua_str(a)
    if d in ("movewindow", "movefocus"):
        target = "hl.dsp.window.move" if d == "movewindow" else "hl.dsp.focus"
        return "%s({ direction = %s })" % (target, _lua_str(_DIRECTIONS.get(a, a)))
    if d in ("resizeactive", "resizewindow"):
        parts = a.split()
        try:
            x, y = int(parts[0]), int(parts[1])
        except (IndexError, ValueError):
            return "hl.dsp.window.resize()"          # resize à la souris (bindm)
        return "hl.dsp.window.resize({ x = %d, y = %d })" % (x, y)
    if d == "fullscreen":
        if a in ("1", "maximize", "maximized"):
            return 'hl.dsp.window.fullscreen({ action = "toggle", mode = "maximized" })'
        return 'hl.dsp.window.fullscreen({ action = "toggle" })'
    if d == "togglefloating":
        return 'hl.dsp.window.float({ action = "toggle" })'
    if d == "pseudo":
        return "hl.dsp.window.pseudo()"
    if d == "layoutmsg":
        return "hl.dsp.layout(%s)" % _lua_str(a or "togglesplit")
    if d == "alterzorder":
        # Équivalent bien présent en 0.57 : hl.dsp.window.alter_zorder({mode}).
        return "hl.dsp.window.alter_zorder({ mode = %s })" % _lua_str(a or "top")
    return None


def _lua_dispatcher_from_command(command):
    d, _, a = (command or "").partition(",")
    return _lua_dispatcher(d, a)

# ---------------------------------------------------------------------------
# Template hypridle.conf (timeouts en SECONDES = minutes × 60)
# ---------------------------------------------------------------------------
HYPRIDLE_TEMPLATE = """# hypridle.conf — régénéré par le panneau Settings (Super+I)

general {
    lock_cmd = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl eval 'hl.dispatch(hl.dsp.dpms("on"))'
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
    on-timeout = hyprctl eval 'hl.dispatch(hl.dsp.dpms("off"))'
    on-resume = hyprctl eval 'hl.dispatch(hl.dsp.dpms("on"))'
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
    after_sleep_cmd = hyprctl eval 'hl.dispatch(hl.dsp.dpms("on"))'
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


def _keybinds_with_overrides():
    """Binds effectifs : keybinds.conf + overrides enregistrés dans settings.json.

    Le panneau affiche donc ce qui est RÉELLEMENT actif, pas la ligne d'origine.
    Les ids restent ceux de keybinds.conf (stables pour les POST)."""
    binds = _parse_keybinds()
    overrides = _read_settings().get("keybinds") or {}
    for bind in binds:
        command = overrides.get(bind["id"])
        if not command:
            continue
        dispatcher, _, arg = command.partition(",")
        bind["dispatcher"] = dispatcher.strip()
        bind["arg"] = arg.strip()
        bind["line"] = "%s = %s, %s, %s" % (bind["type"], bind["mods"], bind["key"], command.strip())
    return binds


def _keybinds_user_lua(settings=None):
    """Contenu complet de hypr/keybinds-user.lua (fichier REMPLACÉ en entier).

    Deux blocs :
      1. hl.config des options SYSTÈME modifiées par le panneau (gaps/rounding/
         animations) — les .conf ne sont plus lus par Hyprland 0.57 ;
      2. un hl.bind par raccourci surchargé (commandes stockées en hyprlang
         dans settings.json, traduites ici en hl.dsp.*).
    """
    settings = settings if settings is not None else _read_settings()
    system = _read_system()
    overrides = settings.get("keybinds") or {}
    lines = [
        "-- keybinds-user.lua — généré par le panneau Settings (Super+I)",
        "-- REMPLACÉ EN ENTIER à chaque écriture : ne pas éditer à la main.",
        "-- Chargé en fin de hypr/hyprland.lua (pcall(dofile, ...) : absence tolérée).",
        "",
        "-- ── Système (gaps / rounding / animations) ──",
        "hl.config({",
        "    general = { gaps_in = %d, gaps_out = %d }," % (system["gaps_in"], system["gaps_out"]),
        "    decoration = { rounding = %d }," % system["rounding"],
        "    animations = { enabled = %s }," % ("true" if system["animations"] else "false"),
        "})",
        "",
        "-- ── Raccourcis surchargés ──",
    ]
    by_id = {b["id"]: b for b in _parse_keybinds()}
    for bid, command in overrides.items():
        target = by_id.get(bid)
        if not target:
            continue                     # keybinds.conf a changé depuis l'override
        # Hyprland Lua : chaque modificateur séparé par " + "
        # (« $mod SHIFT » → « SUPER + SHIFT »).
        combo = " + ".join((target["mods"] or "").split() + [target["key"]])
        lua = _lua_dispatcher_from_command(command)
        if lua is None:
            lines.append("-- non traduit (à adapter) : bind = %s, %s, %s"
                         % (combo, target["dispatcher"], command))
            continue
        flags = _BIND_FLAGS.get(target["type"], "")
        # Hyprland 0.57 : hl.bind sur un combo déjà pris AJOUTE un bind (les deux
        # commandes partent). Il faut donc libérer le combo juste avant. hl.unbind
        # ne normalise pas : il reçoit la chaîne EXACTE passée à hl.bind.
        lines.append("hl.unbind(%s)  -- libère le combo (sinon la surcharge "
                     "s'ajoute au lieu de remplacer)" % _lua_str(combo))
        if flags:
            lines.append("hl.bind(%s, %s, { %s })  -- %s"
                         % (_lua_str(combo), lua, flags, command))
        else:
            lines.append("hl.bind(%s, %s)  -- %s" % (_lua_str(combo), lua, command))
    return "\n".join(lines) + "\n"


def _write_keybinds_lua(settings=None):
    """Réécrit hypr/keybinds-user.lua atomiquement (remplacement complet)."""
    content = _keybinds_user_lua(settings)
    tmp = KEYBINDS_USER_LUA + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(content)
    os.replace(tmp, KEYBINDS_USER_LUA)
    return {"ok": True}


def _post_keybinds(body):
    """Enregistre un override de bind (settings.json) puis réécrit le Lua."""
    bid = (body.get("id") or "").strip()
    command = (body.get("command") or "").strip()
    if not any(b["id"] == bid for b in _parse_keybinds()):
        return {"ok": False, "error": "bind introuvable"}
    if not command:
        return {"ok": False, "error": "commande vide"}
    settings = _read_settings()
    overrides = dict(settings.get("keybinds") or {})
    overrides[bid] = command
    settings["keybinds"] = overrides
    _write_settings(settings)
    _write_keybinds_lua(settings)
    # Reload complet : hl.bind ne peut PAS surcharger un bind par `eval`
    # (il en ajouterait un second sur le même combo).
    subprocess.run(["hyprctl", "reload"], capture_output=True, timeout=10)
    return {"ok": True}


def _post_keybinds_reset():
    """Supprime tous les overrides de binds puis réécrit le Lua."""
    settings = _read_settings()
    settings["keybinds"] = {}
    _write_settings(settings)
    _write_keybinds_lua(settings)
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

    # Le réglage waybar_format est lu directement par
    # waybar/scripts/clock-ja.py (mode FR, à chaque tick) → pas de patch de
    # config ici. _run_theme_apply recharge waybar (le module custom relit
    # settings.json) + hyprlock (lock_24h / lock_date).
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
# Langue UI (FR/日本語) — mémoire permanente dans settings.json
# ---------------------------------------------------------------------------
def _read_lang():
    settings = _read_settings()
    mode = settings.get("lang", {}).get("mode")
    return mode if mode in ("ja", "fr") else "ja"


def _bar_read():
    """Valeurs courantes de la barre, lues depuis cc/bar/bar.json.

    Aucune copie en mémoire du panneau : c'est le fichier qui fait foi (la
    barre le surveille et se recharge seule). Fichier absent/illisible →
    {"ok": false}, la section passe en lecture seule côté QML.
    """
    try:
        with open(BAR_JSON, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        return {"ok": False, "error": "bar.json illisible : %s" % exc}
    bar = data.get("bar") or {}
    app = data.get("appearance") or {}
    run = data.get("runningApps") or {}
    return {
        "ok": True,
        "path": BAR_JSON,
        "values": {
            "bar.position": bar.get("position", "left"),
            "bar.width": bar.get("width", 40),
            "bar.blur": bool(bar.get("blur", True)),
            "bar.persistentWorkspaces": bar.get("persistentWorkspaces", 10),
            "appearance.blockAlpha": app.get("blockAlpha", 0.0),
            "appearance.hoverAlpha": app.get("hoverAlpha", 0.16),
            "appearance.cardAlpha": app.get("cardAlpha", 0.86),
            "runningApps.maxVisible": run.get("maxVisible", 3),
        },
    }


def _post_bar(body):
    """Une clé de bar.json : déléguée au writer chirurgical (barjson.py --set)."""
    key = (body or {}).get("key")
    value = (body or {}).get("value")
    if key not in BAR_KEYS:
        return {"ok": False, "error": "clé inconnue : %s" % key}
    if value is None:
        return {"ok": False, "error": "valeur manquante pour %s" % key}
    # Garde-fou supplémentaire côté serveur : une position qui ne serait pas
    # honorée par la barre ferait mentir le bouton du panneau.
    if key == "bar.position" and value not in BAR_POSITIONS:
        return {"ok": False,
                "error": "position attendue parmi %s" % ", ".join(BAR_POSITIONS)}
    if isinstance(value, bool):
        rendered = "true" if value else "false"
    elif isinstance(value, float):
        rendered = "%g" % value
    else:
        rendered = str(value)
    try:
        proc = subprocess.run(
            ["python3", BAR_WRITER, "--set", "%s=%s" % (key, rendered), "--file", BAR_JSON],
            capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError) as exc:
        return {"ok": False, "error": "writer injoignable : %s" % exc}
    lines = (proc.stdout or "").strip().splitlines()
    try:
        res = json.loads(lines[-1]) if lines else {"ok": False, "error": "aucune sortie"}
    except ValueError:
        return {"ok": False, "error": "sortie du writer illisible : %s" % (proc.stdout or "")[:200]}
    # On renvoie l'état RÉEL relu (pas la valeur demandée) : le panneau affiche
    # ce qui est vraiment dans le fichier après écriture.
    state = _bar_read().get("values")
    res["state"] = state
    # Pour la position, la valeur RELUE est répétée à la racine : le panneau
    # n'a pas à fouiller `state` pour savoir où est la barre.
    if key == "bar.position" and isinstance(state, dict):
        res["position"] = state.get("bar.position")
    return res


def _post_lang(body):
    mode = body.get("mode")
    if mode not in ("ja", "fr"):
        return {"ok": False, "error": "mode invalide (ja|fr)"}
    settings = _read_settings()
    settings["lang"] = {"mode": mode}
    _write_settings(settings)
    # apply-lang.sh en arrière-plan : waybar restart + renameworkspace prennent
    # ~1 s — ne JAMAIS bloquer la réponse HTTP (Popen non bloquant).
    try:
        cmd = [APPLY_LANG]
        if not os.access(APPLY_LANG, os.X_OK):
            cmd = ["bash", APPLY_LANG]
        devnull = open(os.devnull, "w")
        subprocess.Popen(cmd, stdout=devnull, stderr=devnull,
                         start_new_session=True)
        devnull.close()
    except Exception:
        pass
    return {"ok": True, "mode": mode}


# ---------------------------------------------------------------------------
# Système (section SYSTÈME : gaps, rounding, animations, wallpaper)
# ---------------------------------------------------------------------------
def _safe_int(v, default):
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


def _read_system():
    """Valeurs gaps/rounding/animations effectives.

    Priorité : settings.json["system"] (ce que le panneau a écrit) ; sinon les
    .conf d'origine, conservés comme référence/rollback (plus lus par Hyprland).
    """
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

    out = {
        "gaps_in": _grab(GENERAL_CONF, r"gaps_in\s*=\s*(\d+)", 5),
        "gaps_out": _grab(GENERAL_CONF, r"gaps_out\s*=\s*(\d+)", 10),
        "rounding": _grab(DECORATION_CONF, r"rounding\s*=\s*(\d+)", 12),
        "animations": anim,
    }
    saved = _read_settings().get("system")
    if isinstance(saved, dict):
        for key in out:
            if key not in saved:
                continue
            out[key] = bool(saved[key]) if key == "animations" else _safe_int(saved[key], out[key])
    return out


def _post_system(body):
    """Écrit gaps/rounding/animations en Lua (hl.config) + reload.

    Plus aucun .conf n'est modifié : hypr/keybinds-user.lua est la surcouche
    unique, rechargée par `hyprctl reload` (qui relit hyprland.lua → dofile).
    """
    system = {
        "gaps_in": max(0, min(30, _safe_int(body.get("gaps_in"), 5))),
        "gaps_out": max(0, min(50, _safe_int(body.get("gaps_out"), 10))),
        "rounding": max(0, min(30, _safe_int(body.get("rounding"), 12))),
        "animations": bool(body.get("animations", True)),
    }
    settings = _read_settings()
    settings["system"] = system
    _write_settings(settings)
    _write_keybinds_lua(settings)
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
            self._json({"keybinds": _keybinds_with_overrides(), "ok": True})
            return
        if path == "/api/lang":
            self._json({"mode": _read_lang()})
            return
        if path == "/api/bar":
            self._json(_bar_read())
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
        if path == "/api/lang":
            self._json(_post_lang(body))
            return
        if path == "/api/bar":
            self._json(_post_bar(body))
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
