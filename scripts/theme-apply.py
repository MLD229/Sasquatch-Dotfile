#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
theme-apply.py — palette dynamique depuis le wallpaper (Sasquatch-Dotfile)

Extrait les couleurs dominantes d'un wallpaper (PIL) et réécrit les blocs
délimités par les marqueurs SASQUATCH-PALETTE-BEGIN/END dans :
  - waybar/style.css          (palette @define-color)
  - kitty/kitty.conf          (foreground/background/accents/cursor)
  - hypr/theme.lua            (col.active_border / col.inactive_border — Lua,
                              chargé en fin de hypr/hyprland.lua)
  - mako/config               (fichier entier)
  - rofi/themes/colors.rasi   (fichier entier)
  - fastfetch/config.jsonc    (logo arch — couleurs du logo, bloc JSONC)
Écrit aussi /tmp/sasquatch-palette-kitty.conf pour kitty @ set-colors.
Écrit aussi la grille de luminance du papier peint (32x18) dans
$XDG_RUNTIME_DIR/sasquatch-lumgrid.json : le shell (Quickshell) la SURVEILLE
avec un FileView, donc l'encre des cartes suit le changement de fond sans
aucun timer ni requête périodique.

Usage:
  theme-apply.py <wallpaper>           # applique
  theme-apply.py <wallpaper> --print-palette   # affiche key=value, n'applique pas
"""
import colorsys
import json
import os
import re
import subprocess
import sys

from PIL import Image

CONFIG = os.path.expanduser("~/.config")
# Runtime dir (0700, tmpfs) pour lock/cache : plus sûr que /tmp (mono-user OK
# mais pas de collision ni d'attaque symlink ; nettoie tout seul au reboot).
RUNDIR = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"

CSS_BEGIN = "/* === SASQUATCH-PALETTE-BEGIN === */\n"
CSS_END = "/* === SASQUATCH-PALETTE-END === */\n"
CMT_BEGIN = "# === SASQUATCH-PALETTE-BEGIN ===\n"
CMT_END = "# === SASQUATCH-PALETTE-END ===\n"

FILES = {
    "waybar": f"{CONFIG}/waybar/style.css",
    "kitty": f"{CONFIG}/kitty/kitty.conf",
    "hypr": f"{CONFIG}/hypr/theme.lua",
    "hyprlock": f"{CONFIG}/hypr/hyprlock.conf",
    "mako": f"{CONFIG}/mako/config",
    "rofi": f"{CONFIG}/rofi/themes/colors.rasi",
    "fastfetch": f"{CONFIG}/fastfetch/config.jsonc",
    "cc": f"{CONFIG}/cc/qml/Palette.qml",
    "kitty_cache": f"{RUNDIR}/sasquatch-palette-kitty.conf",
}

# Grille de luminance du papier peint, lue et SURVEILLÉE par le shell
# (Quickshell FileView). Même dimensions et même formule que
# cc/wallpaper.py:lumgrid() — sinon l'encre des cartes changerait de valeur
# selon la source (fichier / API).
LUMGRID_W = 32
LUMGRID_H = 18
LUMGRID_FILE = "%s/sasquatch-lumgrid.json" % RUNDIR

# Palette par défaut (Catppuccin Mocha-like) — utilisée si extraction impossible
DEFAULTS = {
    "BG": "#0f0f19", "BG_ALT": "#1e1e2e", "FG": "#cdd6f4", "FG_DIM": "#6c7086",
    "ACCENT": "#88aaee", "ACCENT2": "#aa88ff",
    "RED": "#f38ba8", "GREEN": "#a6e3a1", "YELLOW": "#f9e2af", "CYAN": "#89dceb",
}

# ─────────────────────────── extraction ───────────────────────────

def _hx(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(v))) for v in c)

def _rgb(h):
    """#RRGGBB → (r, g, b)."""
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))

def _lum(c):
    return (0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]) / 255.0

def _sat(c):
    return (max(c) - min(c)) / 255.0

def _mix(a, b, t):
    return tuple(int(x + (y - x) * t) for x, y in zip(a, b))

def _hue_deg(c):
    return colorsys.rgb_to_hsv(*(x / 255.0 for x in c))[0] * 360.0

def _hue_shift(c, deg):
    h, s, v = colorsys.rgb_to_hsv(*(x / 255.0 for x in c))
    h = (h + deg / 360.0) % 1.0
    return tuple(int(x * 255) for x in colorsys.hsv_to_rgb(h, s, v))

def _to_lum(c, target):
    """Éclaircit/assombrit vers une luminance cible (garde la teinte)."""
    cur = _lum(c)
    if abs(cur - target) < 0.012:
        return c
    if cur < target:
        t = (target - cur) / (1.0 - cur) if cur < 1.0 else 0.0
        return _mix(c, (255, 255, 255), min(1.0, t))
    t = (cur - target) / cur
    return _mix(c, (0, 0, 0), min(1.0, t))

# Luminance moyenne du papier peint courant (0..1), remplie par extract().
# None = inconnue (extraction échouée / palette par défaut) → valeurs par défaut.
_WALL_LUM = None


def extract(path):
    """Retourne le dict palette (hex)."""
    global _WALL_LUM
    img = Image.open(path).convert("RGB")
    img.thumbnail((160, 160))
    # Luminance MOYENNE du papier peint (0..1) : sert à caler la luminosité du
    # fond de l'écran de verrouillage (et à savoir si une encre claire y tient).
    # Gardée à part (pas dans le dict palette : `_clean_palette` n'accepte que
    # des hex, un float y fait planter tout l'apply).
    gray = img.convert("L")
    raw = gray.tobytes()
    _WALL_LUM = (sum(raw) / float(len(raw))) / 255.0 if raw else None
    q = img.quantize(colors=6, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = q.getpalette() or []
    counts = sorted(q.getcolors() or [], reverse=True)
    colors = [tuple(pal[i * 3:i * 3 + 3]) for _, i in counts] or [(30, 30, 40)]
    dominant = colors[0]

    # accent = couleur la plus "vive" (saturation × proximité du milieu de luminance)
    cands = [c for c in colors if _sat(c) > 0.06]
    if cands:
        accent = max(cands, key=lambda c: _sat(c) * (1.0 - abs(_lum(c) - 0.5)))
    else:
        accent = _hue_shift(dominant, 40)  # image en niveaux de gris

    ha = _hue_deg(accent)
    dh = lambda c: min(abs(_hue_deg(c) - ha), 360 - abs(_hue_deg(c) - ha))
    # accent2 : teinte la plus éloignée, mais pas trop sombre (luminance ≥ 0.18)
    cands2 = [c for c in colors if _lum(c) >= 0.18]
    accent2 = max(cands2 or colors, key=lambda c: dh(c) * (0.4 + _sat(c)))
    if dh(accent2) < 30:
        accent2 = _hue_shift(accent, 45)

    bg = _to_lum(_mix(dominant, (0, 0, 0), 0.55), 0.085)
    bg_alt = _mix(bg, accent, 0.12)
    fg = _to_lum(_mix(dominant, (255, 255, 255), 0.75), 0.82)
    fg_dim = _mix(fg, bg, 0.45)

    return {**DEFAULTS, "BG": _hx(bg), "BG_ALT": _hx(bg_alt), "FG": _hx(fg),
            "FG_DIM": _hx(fg_dim), "ACCENT": _hx(accent), "ACCENT2": _hx(accent2)}

# ────────────────────── grille de luminance (encre adaptative) ──────────────────────

def lumgrid(path):
    """Grille 32x18 de luminance du papier peint (0..1).

    MÊME calcul que cc/wallpaper.py:lumgrid() : resize direct en 32x18 puis
    luminance pondérée WCAG (0.2126/0.7152/0.0722). Identique au bit près, donc
    un widget ne change pas d'encre selon que la valeur vient du fichier ou de
    l'API."""
    img = Image.open(path).convert("RGB").resize((LUMGRID_W, LUMGRID_H))
    raw = img.tobytes()
    values = []
    for i in range(0, len(raw), 3):
        r, g, b = raw[i], raw[i + 1], raw[i + 2]
        values.append(round((0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0, 3))
    return {"wallpaper": os.path.abspath(path), "w": LUMGRID_W, "h": LUMGRID_H,
            "values": values}


def write_lumgrid(path):
    """Écrit la grille pour le shell, atomiquement (os.replace).

    Rien n'est réécrit si le contenu est identique (pas d'événement inotify
    inutile pour le FileView qui surveille le fichier). Ne lève jamais : la
    grille est un confort (encre adaptative), pas une condition d'application
    du thème — un échec ne doit pas empêcher la palette d'être écrite.
    Retourne True si le fichier a été remplacé."""
    try:
        payload = json.dumps(lumgrid(path), separators=(",", ":"))
        os.makedirs(RUNDIR, exist_ok=True)
        try:
            with open(LUMGRID_FILE, encoding="utf-8") as f:
                if f.read().strip() == payload:
                    return False
        except OSError:
            pass
        tmp = LUMGRID_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(payload + "\n")
        # os.replace : jamais de fichier à moitié lu par le shell.
        os.replace(tmp, LUMGRID_FILE)
        return True
    except Exception as e:
        print("⚠ lumgrid non écrit (%s)" % e, file=sys.stderr)
        return False

# ─────────────────────────── générateurs de blocs ───────────────────────────

def b_waybar(p):
    return "\n".join([
        "@define-color background %s;" % p["BG"],
        "@define-color foreground %s;" % p["FG"],
        "@define-color color0 #45475a;",
        "@define-color color1 %s;" % p["RED"],
        "@define-color color2 %s;" % p["GREEN"],
        "@define-color color3 %s;" % p["YELLOW"],
        "@define-color color4 %s;" % p["ACCENT"],
        "@define-color color5 %s;" % p["ACCENT2"],
        "@define-color color6 %s;" % p["CYAN"],
        "@define-color color7 #bac2de;",
        "@define-color color8 %s;" % p["FG_DIM"],
        "@define-color color9 %s;" % p["RED"],
        "@define-color color10 %s;" % p["GREEN"],
        "@define-color color11 %s;" % p["YELLOW"],
        "@define-color color12 %s;" % p["ACCENT"],
        "@define-color color13 %s;" % p["ACCENT2"],
        "@define-color color14 %s;" % p["CYAN"],
        "@define-color color15 #a6adc8;",
    ])

def b_kitty(p):
    return "\n".join([
        "foreground            %s" % p["FG"],
        "background            %s" % p["BG"],
        "selection_foreground  %s" % p["BG"],
        "selection_background  %s" % p["ACCENT"],
        "color4  %s" % p["ACCENT"],
        "color5  %s" % p["ACCENT2"],
        "color12 %s" % p["ACCENT"],
        "color13 %s" % p["ACCENT2"],
        "cursor            %s" % p["ACCENT"],
        "cursor_text_color %s" % p["BG"],
        "active_tab_foreground   %s" % p["BG"],
        "active_tab_background   %s" % p["ACCENT"],
    ])

THEME_LUA_HEADER = (
    "-- theme.lua — généré par scripts/theme-apply.py (ne pas éditer à la main).\n"
    "-- Chargé en fin de hypr/hyprland.lua : pcall(dofile, ...) → absent = ignoré.\n"
    "-- Le fichier = durabilité (relogin) ; le même code est appliqué en direct\n"
    "-- par `hyprctl eval` → effet immédiat, sans relogin.\n")


def b_theme_lua(p):
    """Corps Lua (hl.config) des bordures — sert au FICHIER et à l'eval.

    Remplace l'ancien bloc `col.active_border` de hypr/conf.d/general.conf,
    que plus personne ne lit (hyprlang supprimé en 0.57)."""
    acc = p["ACCENT"][1:] + "ee"
    acc2 = p["ACCENT2"][1:] + "ee"
    return "\n".join([
        "hl.config({",
        "    general = {",
        "        col = {",
        '            active_border = { colors = { "rgba(%s)", "rgba(%s)" }, angle = 45 },' % (acc, acc2),
        '            inactive_border = "rgba(444444aa)",',
        "        },",
        "    },",
        "})",
    ]) + "\n"


def write_theme_lua(p):
    """Écrit hypr/theme.lua atomiquement. True si le contenu a changé.

    N'échoue jamais l'apply : les bordures sont un confort, pas une condition."""
    content = THEME_LUA_HEADER + "\n" + b_theme_lua(p)
    try:
        os.makedirs(os.path.dirname(FILES["hypr"]), exist_ok=True)
        try:
            with open(FILES["hypr"], encoding="utf-8") as f:
                if f.read() == content:
                    return False
        except OSError:
            pass
        tmp = FILES["hypr"] + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(content)
        os.replace(tmp, FILES["hypr"])
        return True
    except OSError as e:
        print("⚠ theme.lua non écrit (%s)" % e, file=sys.stderr)
        return False


def apply_theme_live(p):
    """Applique les bordures tout de suite (hyprctl eval). Muet hors session."""
    try:
        r = subprocess.run(["hyprctl", "eval", b_theme_lua(p)],
                           capture_output=True, text=True, timeout=5)
    except Exception:
        return False
    return "ok" in (r.stdout or "").lower()


def b_hyprlock(p, clock=None):
    clock = clock or {}
    # lock-ja.py : heure + date en hiragana — le lock doit rester en japonais
    # même après un changement de wallpaper (theme-apply régénère CE bloc).
    # Police OBLIGATOIRE : Noto Sans CJK JP (hiragana, pas de tofu).
    # Pas de Pango dans la sortie cmd (hyprlock le gère mal).
    date_label = "" if clock.get("lock_date", True) else "# date masquée (réglage horloge)"
    # Fond = capture d'écran floutée. Sur un papier peint CLAIR, un facteur 0.6
    # laisse le fond à mi-luminosité et l'encre claire (FG) s'y perd : on
    # assombrit juste ce qu'il faut pour que le texte reste lisible (cible
    # ≈ 0.42 de luminance de fond), et on ne touche à rien sur un fond sombre.
    wall_lum = _WALL_LUM
    if isinstance(wall_lum, (int, float)) and wall_lum > 0.02:
        brightness = max(0.35, min(0.60, 0.42 / float(wall_lum)))
    else:
        brightness = 0.60
    lines = [
        "background {",
        "    monitor =",
        "    path = screenshot",
        "    blur_passes = 3",
        "    blur_size = 8",
        "    brightness = %.2f" % brightness,
        "    vibrancy = 0.2",
        "}",
        "",
        "label {",
        "    monitor =",
        "    text = cmd[update:1000] python3 ~/.config/hypr/scripts/lock-ja.py time",
        "    color = rgba(%sff)" % p["FG"][1:],
        "    font_size = 72",
        "    font_family = Noto Sans CJK JP",
        "    position = 0, -20",
        "    halign = center",
        "    valign = center",
        "}",
    ]
    if not date_label:  # lock_date=True → date_label="" → générer le label
        lines += [
            "",
            "label {",
            "    monitor =",
            "    text = cmd[update:1000] python3 ~/.config/hypr/scripts/lock-ja.py date",
            "    color = rgba(%scc)" % p["ACCENT"][1:],
            "    font_size = 18",
            "    font_family = Noto Sans CJK JP",
            "    position = 0, -110",
            "    halign = center",
            "    valign = center",
            "}",
        ]
    else:
        lines += ["", date_label]
    lines += [
        "",
        "label {",
        "    monitor =",
        "    text = cmd[update:2000] ~/.config/hypr/scripts/lock-media.sh",
        "    color = rgba(%scc)" % p["ACCENT"][1:],
        "    font_size = 15",
        "    font_family = JetBrains Mono",
        "    position = 0, -145",
        "    halign = center",
        "    valign = center",
        "}",
    ]
    lines += [
        "",
        "input-field {",
        "    monitor =",
        "    size = 280, 48",
        "    outline_thickness = 2",
        "    dots_size = 0.3",
        "    dots_spacing = 0.2",
        "    outer_color = rgba(%saa)" % p["ACCENT"][1:],
        "    inner_color = rgba(%scc)" % p["BG"][1:],
        "    font_color = rgba(%sff)" % p["FG"][1:],
        "    fade_on_empty = true",
        "    placeholder_text = <i>Mot de passe...</i>",
        "    check_color = rgba(%sff)" % p["GREEN"][1:],
        "    fail_color = rgba(%sff)" % p["RED"][1:],
        "    fail_text = <i>Raté ($ATTEMPTS)</i>",
        "    rounding = 12",
        "    position = 0, -180",
        "    halign = center",
        "    valign = center",
        "}",
    ]
    return "\n".join(lines)

def b_mako(p):
    return "\n".join([
        "sort=-time",
        "layer=overlay",
        "background-color=%scc" % p["BG"],
        "text-color=%s" % p["FG"],
        "width=340",
        "height=120",
        "border-size=1",
        "border-color=%s44" % p["ACCENT"],
        "border-radius=12",
        "padding=12",
        "margin=10",
        "icons=1",
        "max-icon-size=32",
        "",
        "font=JetBrains Mono 12",
        "format=<b>%s</b>\\n%b",
        "",
        "default-timeout=4000",
        "ignore-timeout=0",
        "",
        "[urgency=low]",
        "background-color=%sbb" % p["BG"],
        "border-color=#6c708644",
        "text-color=%s" % p["FG_DIM"],
        "",
        "[urgency=normal]",
        "background-color=%scc" % p["BG"],
        "border-color=%s44" % p["ACCENT"],
        "",
        "[urgency=high]",
        "background-color=%scc" % p["BG"],
        "border-color=%saa" % p["RED"],
        "text-color=%s" % p["RED"],
    ])

def b_rofi(p):
    """.rasi couleurs du lanceur. ALPHAS : la fenêtre est volontairement
    translucide (0.62) — le flou du compositeur reste visible derrière ;
    les anciennes valeurs (0.85/0.80) étaient de fait IGNORÉES par
    sasquatch.rasi (teal en dur) : elles sont maintenant consommées."""
    def dec(h, a):
        r, g, b = int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16)
        return "rgba(%d, %d, %d, %s)" % (r, g, b, a)

    # Accent « texte » : l'extraction peut rendre un accent très sombre
    # (wallpaper désaturé → ACCENT #222124) ; en couleur de texte (prompt,
    # curseur) il disparaît sur la fenêtre. On remonte sa luminance SANS
    # toucher à l'accent des autres composants (waybar/kitty gardent le brut).
    acc = p["ACCENT"]
    if _lum(_rgb(acc)) < 0.32:
        acc = _hx(_to_lum(_rgb(acc), 0.62))

    # accent2 = seconde teinte de la palette ; repli sur accent s'il manque.
    acc2 = p.get("ACCENT2") or acc

    # Sélection : fond accent2 opaque (lisible), texte choisi par luminance
    # → blanc sur accent2 sombre, sombre sur accent2 clair (cas mesuré :
    # #afb1b2, où du blanc serait illisible).
    sel_fg = dec(p["BG"], "1.0") if _lum(_rgb(acc2)) > 0.55 \
        else "rgba(255, 255, 255, 1.0)"

    return "\n".join([
        "* {",
        "    /* ── Backgrounds ────────────────────────────────── */",
        "    bg-window:   %s;" % dec(p["BG"], "0.62"),
        "    bg-input:    %s;" % dec(p["BG_ALT"], "0.55"),
        "    bg-osd:      %s;" % dec(p["BG"], "0.88"),
        "    bg-selected: %s;" % dec(acc2, "0.90"),
        "    urgent-bg:   %s;" % dec(p["RED"], "0.85"),
        "",
        "    /* ── Foregrounds ────────────────────────────────── */",
        "    fg:          %s;" % dec(p["FG"], "1.0"),
        "    fg-dim:      %s;" % dec(p["FG_DIM"], "1.0"),
        "    fg-selected: %s;" % sel_fg,
        "",
        "    /* ── Accents ────────────────────────────────────── */",
        "    accent:      %s;" % dec(acc, "1.0"),
        "    accent-dim:  %s;" % dec(acc, "0.75"),
        "    accent2:     %s;" % dec(acc2, "1.0"),
        "    urgent:      %s;" % dec(p["RED"], "1.0"),
        "",
        "    /* ── Border ─────────────────────────────────────── */",
        "    border:      %s;" % dec(acc, "0.50"),
        "}",
    ])

def b_fastfetch(p):
    """Logo Arch builtin — dégradé sur la teinte de l'accent.
    Le logo arch natif est un dégradé (sombre → clair) ; on garde le style mais
    avec les couleurs du thème. Format fastfetch : "color" = objet { "1".."6" }.
    La dernière clé N'A PAS de virgule (dernière propriété de l'objet color)."""
    accent = _rgb(p["ACCENT"])
    steps = (0.35, 0.48, 0.60, 0.72, 0.85, 0.97)
    cols = [_hx(_to_lum(accent, t)) for t in steps]
    lines = ['    "color": {']
    for i, c in enumerate(cols[:-1]):
        lines.append('        "%d": "%s",' % (i + 1, c))
    lines.append('        "6": "%s"' % cols[-1])
    lines.append('    }')
    return "\n".join(lines)

def b_cc(p):
    """Palette du Control Center (Quickshell) — cc/qml/Palette.qml."""
    return "\n".join([
        '    readonly property color bg: "%s"' % p["BG"],
        '    readonly property color bgSolid: "%s"' % p["BG"],
        '    readonly property color card: "%s"' % p["BG_ALT"],
        '    readonly property color cardSolid: "%s"' % p["BG_ALT"],
        '    readonly property color text: "%s"' % p["FG"],
        '    readonly property color textDim: "%s"' % p["FG_DIM"],
        '    readonly property color accent: "%s"' % p["ACCENT"],
        '    readonly property color accent2: "#44%s"' % p["ACCENT"][1:],
        '    readonly property color overlay: "#99021933"',
        '    readonly property color good: "%s"' % p["GREEN"],
        '    readonly property color warn: "%s"' % p["YELLOW"],
        '    readonly property color hot: "%s"' % p["RED"],
    ])

# ─────────────────────────── patching ───────────────────────────

HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")

def _clean_palette(p):
    """Garantit des valeurs hex valides — toute valeur invalide retombe sur le défaut."""
    out = dict(p)
    for k, v in p.items():
        if not HEX_RE.match(v):
            print("⚠ valeur invalide %s=%s — défaut utilisé" % (k, v), file=sys.stderr)
            out[k] = DEFAULTS.get(k, "#000000")
    return out

def replace_block(path, begin, end, new):
    """Remplace le bloc marqué. Retourne :
    - True  : bloc écrit
    - None  : contenu déjà identique (skip — rien à faire)
    - False : marqueurs absents (warning)
    """
    with open(path, encoding="utf-8") as f:
        content = f.read()
    pat = re.compile(re.escape(begin) + r".*?" + re.escape(end), re.S)
    m = pat.search(content)
    if not m:
        print("⚠ marqueurs absents: %s" % path, file=sys.stderr)
        return False
    replacement = begin + new.rstrip() + "\n" + end
    if content[m.start():m.end()] == replacement:
        return None
    with open(path, "w", encoding="utf-8") as f:
        f.write(pat.sub(lambda _: replacement, content))
    return True

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    path = args[0] if args else None
    p = dict(DEFAULTS)
    if path and os.path.isfile(path):
        try:
            p.update(extract(path))
        except Exception as e:
            print("⚠ extraction échouée (%s) — palette par défaut" % e, file=sys.stderr)
    elif path:
        print("⚠ fichier introuvable: %s — palette par défaut" % path, file=sys.stderr)

    # ── Mode palette MANUEL (panneau Settings, Super+I) ────────────────
    # settings.json → palette.mode == "manual" : on force ACCENT/ACCENT2
    # choisis par l'utilisateur ; le reste (bg/fg) reste dérivé du wallpaper
    # (ou des défauts si pas de wallpaper). Les valeurs invalides sont
    # ignorées silencieusement (_clean_palette les rattraperait sinon).
    try:
        with open(os.path.expanduser("~/.config/settings/settings.json"), encoding="utf-8") as f:
            _settings = json.load(f)
    except Exception:
        _settings = {}
    pal = _settings.get("palette", {}) if isinstance(_settings, dict) else {}
    if pal.get("mode") == "manual":
        if HEX_RE.match(pal.get("accent", "")):
            p["ACCENT"] = pal["accent"]
        if HEX_RE.match(pal.get("accent2", "")):
            p["ACCENT2"] = pal["accent2"]
        print("◈ palette MANUELLE: ACCENT=%s ACCENT2=%s" % (p["ACCENT"], p["ACCENT2"]), file=sys.stderr)
    _clock = _settings.get("clock", {}) if isinstance(_settings, dict) else {}

    p = _clean_palette(p)

    if "--print-palette" in sys.argv:
        for k in ("BG", "BG_ALT", "FG", "FG_DIM", "ACCENT", "ACCENT2", "RED", "GREEN", "YELLOW", "CYAN"):
            print("%s=%s" % (k, p[k]))
        return 0

    blocks = (
        ("waybar", FILES["waybar"], CSS_BEGIN, CSS_END, b_waybar(p)),
        ("kitty", FILES["kitty"], CMT_BEGIN, CMT_END, b_kitty(p)),
        ("hyprlock", FILES["hyprlock"], CMT_BEGIN, CMT_END, b_hyprlock(p, _clock)),
        ("mako", FILES["mako"], CMT_BEGIN, CMT_END, b_mako(p)),
        ("rofi", FILES["rofi"], CSS_BEGIN, CSS_END, b_rofi(p)),
        ("fastfetch", FILES["fastfetch"], CSS_BEGIN, CSS_END, b_fastfetch(p)),
        ("cc", FILES["cc"], CSS_BEGIN, CSS_END, b_cc(p)),
    )

    # ── Atomicité ──────────────────────────────────────────────
    # Pré-vérifier que TOUS les fichiers cibles existent (et contiennent bien
    # les marqueurs BEGIN/END) AVANT d'écrire quoi que ce soit : sinon un
    # dossier/symlink manquant — ou un fichier sans marqueurs (édition manuelle,
    # fichier local non-commité) — faisait écrire les 6 autres puis sortir en 1
    # → moitié de la palette appliquée (état incohérent).
    #
    # Cas particulier cc/qml/Palette.qml : ce fichier est GITIGNORÉ (régénéré à
    # chaque apply) → sur un clone frais il n'existe pas encore. Le créer avec
    # les marqueurs + palette courante avant la pré-vérif (fallback runtime
    # déjà géré par cc/palette.py).
    cc_path = FILES["cc"]
    if not os.path.isfile(cc_path):
        os.makedirs(os.path.dirname(cc_path), exist_ok=True)
        with open(cc_path, "w", encoding="utf-8") as f:
            f.write(CSS_BEGIN + b_cc(p).rstrip() + "\n" + CSS_END)
        print("✔ Palette.qml créé (premier apply)", file=sys.stderr)

    problems = []
    for name, fpath, begin, end, _new in blocks:
        if not os.path.isfile(fpath):
            problems.append("%s (absent)" % fpath)
            continue
        try:
            with open(fpath, encoding="utf-8") as f:
                content = f.read()
        except OSError as e:
            problems.append("%s (illisible: %s)" % (fpath, e))
            continue
        if begin not in content or end not in content:
            problems.append("%s (marqueurs %s manquants)" % (fpath, begin.strip()))
    if problems:
        for p in problems:
            print("⚠ fichier cible: %s" % p, file=sys.stderr)
        return 1

    ok = True
    changed = False
    for name, fpath, begin, end, new in blocks:
        r = replace_block(fpath, begin, end, new)
        if r is False:
            ok = False
        elif r is True:
            changed = True

    # Cache kitty : ne réécrire que si la palette a réellement changé.
    if changed:
        with open(FILES["kitty_cache"], "w", encoding="utf-8") as f:
            f.write(b_kitty(p) + "\n")

    # Bordures Hyprland : theme.lua (durabilité, relu au login) + hyprctl eval
    # (même code, effet immédiat). Hors session Hyprland l'eval échoue en
    # silence : le fichier reste la source de vérité.
    if write_theme_lua(p):
        print("◈ theme.lua écrit : %s" % FILES["hypr"], file=sys.stderr)
    if apply_theme_live(p):
        print("◈ bordures appliquées à chaud (hyprctl eval)", file=sys.stderr)

    # Grille de luminance pour le shell (encre adaptative). Écrite ici, dans le
    # MÊME passage que la palette : Quickshell la surveille, donc l'encre des
    # cartes change sans timer ni requête. Contenu identique = pas de réécriture
    # (write_lumgrid le vérifie), et un échec n'invalide pas la palette.
    if path and os.path.isfile(path):
        if write_lumgrid(path):
            print("◈ lumgrid écrit : %s" % LUMGRID_FILE, file=sys.stderr)

    print("Thème appliqué: BG=%s FG=%s ACCENT=%s ACCENT2=%s" % (p["BG"], p["FG"], p["ACCENT"], p["ACCENT2"]))
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
