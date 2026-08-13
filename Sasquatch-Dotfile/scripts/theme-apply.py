#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
theme-apply.py — palette dynamique depuis le wallpaper (Sasquatch-Dotfile)

Extrait les couleurs dominantes d'un wallpaper (PIL) et réécrit les blocs
délimités par les marqueurs SASQUATCH-PALETTE-BEGIN/END dans :
  - waybar/style.css          (palette @define-color)
  - kitty/kitty.conf          (foreground/background/accents/cursor)
  - hypr/conf.d/general.conf  (col.active_border / col.inactive_border)
  - mako/config               (fichier entier)
  - rofi/themes/colors.rasi   (fichier entier)
Écrit aussi /tmp/sasquatch-palette-kitty.conf pour kitty @ set-colors.

Usage:
  theme-apply.py <wallpaper>           # applique
  theme-apply.py <wallpaper> --print-palette   # affiche key=value, n'applique pas
"""
import colorsys
import os
import re
import sys

from PIL import Image

CONFIG = os.path.expanduser("~/.config")

CSS_BEGIN = "/* === SASQUATCH-PALETTE-BEGIN === */\n"
CSS_END = "/* === SASQUATCH-PALETTE-END === */\n"
CMT_BEGIN = "# === SASQUATCH-PALETTE-BEGIN ===\n"
CMT_END = "# === SASQUATCH-PALETTE-END ===\n"

FILES = {
    "waybar": f"{CONFIG}/waybar/style.css",
    "kitty": f"{CONFIG}/kitty/kitty.conf",
    "hypr": f"{CONFIG}/hypr/conf.d/general.conf",
    "hyprlock": f"{CONFIG}/hypr/hyprlock.conf",
    "mako": f"{CONFIG}/mako/config",
    "rofi": f"{CONFIG}/rofi/themes/colors.rasi",
    "kitty_cache": "/tmp/sasquatch-palette-kitty.conf",
}

# Palette par défaut (Catppuccin Mocha-like) — utilisée si extraction impossible
DEFAULTS = {
    "BG": "#0f0f19", "BG_ALT": "#1e1e2e", "FG": "#cdd6f4", "FG_DIM": "#6c7086",
    "ACCENT": "#88aaee", "ACCENT2": "#aa88ff",
    "RED": "#f38ba8", "GREEN": "#a6e3a1", "YELLOW": "#f9e2af", "CYAN": "#89dceb",
}

# ─────────────────────────── extraction ───────────────────────────

def _hx(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(v))) for v in c)

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

def extract(path):
    """Retourne le dict palette (hex)."""
    img = Image.open(path).convert("RGB")
    img.thumbnail((160, 160))
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

def b_hypr(p):
    return "\n".join([
        "    col.active_border = rgba(%s) rgba(%s) 45deg" % (p["ACCENT"][1:] + "ee", p["ACCENT2"][1:] + "ee"),
        "    col.inactive_border = rgba(444444aa)",
    ])

def b_hyprlock(p):
    return "\n".join([
        "label {",
        "    monitor =",
        "    text = cmd[update:1000] echo \"$(date +'%H:%M')\"",
        "    color = rgba(%sff)" % p["FG"][1:],
        "    font_size = 72",
        "    font_family = JetBrains Mono Bold",
        "    position = 0, -20",
        "    halign = center",
        "    valign = center",
        "}",
        "",
        "label {",
        "    monitor =",
        "    text = cmd[update:1000] echo \"$(date +'%A %d %B')\"",
        "    color = rgba(%scc)" % p["FG_DIM"][1:],
        "    font_size = 18",
        "    font_family = JetBrains Mono",
        "    position = 0, -110",
        "    halign = center",
        "    valign = center",
        "}",
        "",
        "input-field {",
        "    monitor =",
        "    size = 280, 48",
        "    outline_thickness = 2",
        "    dots_size = 0.3",
        "    dots_spacing = 0.2",
        "    outer_color = rgba(%s44)" % p["ACCENT"][1:],
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
    ])

def b_mako(p):
    return "\n".join([
        "# mako/config — palette dynamique (généré par theme-apply.py)",
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
    def dec(h, a):
        r, g, b = int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16)
        return "rgba(%d, %d, %d, %s)" % (r, g, b, a)
    return "\n".join([
        "/* Sasquatch · Palette de couleurs dynamique (généré par theme-apply.py) */",
        "* {",
        "    /* ── Backgrounds ────────────────────────────────── */",
        "    bg-window:   %s;" % dec(p["BG"], "0.85"),
        "    bg-input:    %s;" % dec(p["BG_ALT"], "0.80"),
        "    bg-selected: %s;" % dec(p["ACCENT"], "0.25"),
        "    urgent-bg:   %s;" % dec(p["RED"], "0.25"),
        "",
        "    /* ── Foregrounds ────────────────────────────────── */",
        "    fg:          %s;" % dec(p["FG"], "1.0"),
        "    fg-dim:      %s;" % dec(p["FG_DIM"], "1.0"),
        "    fg-selected: rgba(255, 255, 255, 1.0);",
        "",
        "    /* ── Accents ────────────────────────────────────── */",
        "    accent:      %s;" % dec(p["ACCENT"], "1.0"),
        "    accent-dim:  %s;" % dec(p["ACCENT"], "0.75"),
        "    urgent:      %s;" % dec(p["RED"], "1.0"),
        "",
        "    /* ── Border ─────────────────────────────────────── */",
        "    border:      %s;" % dec(p["ACCENT"], "0.50"),
        "}",
    ])

# ─────────────────────────── patching ───────────────────────────

def replace_block(path, begin, end, new):
    with open(path, encoding="utf-8") as f:
        content = f.read()
    pat = re.compile(re.escape(begin) + r".*?" + re.escape(end), re.S)
    if not pat.search(content):
        print("⚠ marqueurs absents: %s" % path, file=sys.stderr)
        return False
    with open(path, "w", encoding="utf-8") as f:
        f.write(pat.sub(lambda m: begin + new.rstrip() + "\n" + end, content))
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

    if "--print-palette" in sys.argv:
        for k in ("BG", "BG_ALT", "FG", "FG_DIM", "ACCENT", "ACCENT2", "RED", "GREEN", "YELLOW", "CYAN"):
            print("%s=%s" % (k, p[k]))
        return 0

    ok = True
    ok &= replace_block(FILES["waybar"], CSS_BEGIN, CSS_END, b_waybar(p))
    ok &= replace_block(FILES["kitty"], CMT_BEGIN, CMT_END, b_kitty(p))
    ok &= replace_block(FILES["hypr"], CMT_BEGIN, CMT_END, b_hypr(p))
    ok &= replace_block(FILES["hyprlock"], CMT_BEGIN, CMT_END, b_hyprlock(p))
    ok &= replace_block(FILES["mako"], CMT_BEGIN, CMT_END, b_mako(p))
    ok &= replace_block(FILES["rofi"], CSS_BEGIN, CSS_END, b_rofi(p))

    with open(FILES["kitty_cache"], "w", encoding="utf-8") as f:
        f.write(b_kitty(p) + "\n")

    print("Thème appliqué: BG=%s FG=%s ACCENT=%s ACCENT2=%s" % (p["BG"], p["FG"], p["ACCENT"], p["ACCENT2"]))
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
