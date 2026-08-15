"""Palette du CC — lit qml/Palette.qml (régénéré par theme-apply.py à chaque
changement de wallpaper) et l'expose en JSON pour que l'UI Quickshell suive
le thème dynamique au lieu de rester figée en Catppuccin."""

import os
import re

PALETTE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "qml", "Palette.qml")

# Fallback (Catppuccin Mocha) si le fichier est absent ou corrompu.
PALETTE_DEFAULTS = {
    "bg": "#1e1e2e", "bgSolid": "#181825", "card": "#181825", "cardSolid": "#181825",
    "text": "#cdd6f4", "textDim": "#a6adc8", "accent": "#89b4fa", "accent2": "#94e2d5",
    "overlay": "#000000", "good": "#a6e3a1", "warn": "#f9e2af", "hot": "#f38ba8",
}

_RE_PROP = re.compile(r'property\s+color\s+(\w+)\s*:\s*"([^"]+)"')


def read_palette():
    """Retourne un dict {cle: "#RRGGBB"|"#AARRGGBB"} prêt pour JSON."""
    try:
        with open(PALETTE_FILE, encoding="utf-8") as f:
            content = f.read()
    except OSError:
        return dict(PALETTE_DEFAULTS)
    found = dict(_RE_PROP.findall(content))
    out = {}
    for key, default in PALETTE_DEFAULTS.items():
        out[key] = found.get(key, default)
    return out
