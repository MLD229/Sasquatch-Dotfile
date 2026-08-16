#!/usr/bin/env python3
"""
wallclock-ja.py — horloge japonaise flottante sur le fond d'écran (Sasquatch-Dotfile).

Affiche l'heure en hiragana DANS le fond d'écran (layer-shell background, sous
les fenêtres), positionnée automatiquement dans la zone la plus "plate" du
wallpaper (faible variance de couleur = espace libre).

Comportement (spec momo) :
  * À CHAQUE changement de wallpaper (momo change souvent), la position est
    re-calculée et l'horloge GLISSE (animation) vers la nouvelle zone plate.
  * Palette : lue depuis waybar/style.css (bloc SASQUATCH-PALETTE, comme
    fastview.py) — le texte suit le thème dynamique.
  * Rafraîchit l'heure toutes les 30 s ; tooltip GTK natif synchronisé
    (lecture hiragana + traduction + date + calendrier).
  * Fenêtre : layer-shell background, sans focus, input region limitée à
    l'horloge (le hover ne bloque pas le reste du bureau).

Lancé par autostart.sh. pidfile /tmp/sasquatch-wallclock.pid — un ancien
daemon vivant est tué et remplacé au démarrage.

Dépendances : python-gobject, gtk-layer-shell, Pillow, numpy (analyse image).
"""
import atexit
import datetime
import json
import math
import os
import re
import signal
import subprocess
import sys
import time

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import GLib, Gdk, Gtk, GtkLayerShell

try:
    from PIL import Image
    import numpy as np
    HAS_IMAGING = True
except ImportError:
    HAS_IMAGING = False

# ── Constantes ────────────────────────────────────────────────────────────
PIDFILE = "/tmp/sasquatch-wallclock.pid"
WAYPAPER_CONFIG = os.path.expanduser("~/.config/waypaper/config.ini")
STYLE_CSS = os.path.expanduser("~/.config/waybar/style.css")

FONT_TIME = "Noto Sans CJK JP 40"      # heure (hiragana)
FONT_DATE = "Noto Sans CJK JP 13"      # date secondaire
REFRESH_MS = 30_000                     # rafraîchissement heure
WATCH_MS = 2000                         # surveillance changement wallpaper
ANIM_MS = 16                            # pas d'animation (~60 fps)
ANIM_DURATION = 0.6                     # durée du glissement (secondes)
EASE_POWER = 3                          # easing ease-out-cubic

# Taille cible de l'horloge dans la grille d'analyse (en cellules)
CLOCK_CELLS_W = 14
CLOCK_CELLS_H = 6
GRID_W, GRID_H = 48, 27                 # résolution d'analyse (16:9)

# Fallbacks si la palette n'est pas lisible
TEXT_FG = "#e8e8e8"
TEXT_FG_DIM = "#b0b0b0"


# ── Palette (bloc SASQUATCH-PALETTE du style.css) ────────────────────────
def read_palette():
    """Lit le bloc SASQUATCH-PALETTE de waybar/style.css → dict couleur."""
    palette = {}
    try:
        with open(STYLE_CSS) as f:
            css = f.read()
        # Format réel : /* === SASQUATCH-PALETTE-BEGIN === */ ... /* === END === */
        m = re.search(r"SASQUATCH-PALETTE-BEGIN\s*\*/\s*(.*?)/\*\s*===?\s*SASQUATCH-PALETTE", css, re.S)
        block = m.group(1) if m else css
        for var, val in re.findall(r"(@\w+)\s*:\s*(#[0-9a-fA-F]{6})", block):
            palette[var] = val
    except OSError:
        pass
    return palette


# ── Lecture heure/date japonaises (tables clock-ja.py) ───────────────────
HOURS = {
    0: "れいじ", 1: "いちじ", 2: "にじ", 3: "さんじ", 4: "よじ", 5: "ごじ",
    6: "ろくじ", 7: "しちじ", 8: "はちじ", 9: "くじ", 10: "じゅうじ",
    11: "じゅういちじ", 12: "じゅうにじ", 13: "じゅうさんじ", 14: "じゅうよじ",
    15: "じゅうごじ", 16: "じゅうろくじ", 17: "じゅうしちじ", 18: "じゅうはちじ",
    19: "じゅうくじ", 20: "にじゅうじ", 21: "にじゅういちじ", 22: "にじゅうにじ",
    23: "にじゅうさんじ",
}
MIN_UNITS = {
    0: "", 1: "いっぷん", 2: "にふん", 3: "さんぷん", 4: "よんぷん", 5: "ごふん",
    6: "ろっぷん", 7: "ななふん", 8: "はっぷん", 9: "きゅうふん",
}
MIN_TENS = {1: "じゅう", 2: "にじゅう", 3: "さんじゅう", 4: "よんじゅう", 5: "ごじゅう"}
MONTHS = {
    1: "いちがつ", 2: "にがつ", 3: "さんがつ", 4: "しがつ", 5: "ごがつ",
    6: "ろくがつ", 7: "しちがつ", 8: "はちがつ", 9: "くがつ", 10: "じゅうがつ",
    11: "じゅういちがつ", 12: "じゅうにがつ",
}
DAYS = {
    1: "ついたち", 2: "ふつか", 3: "みっか", 4: "よっか", 5: "いつか",
    6: "むいか", 7: "なのか", 8: "ようか", 9: "ここのか", 10: "とおか",
    11: "じゅういちにち", 12: "じゅうににち", 13: "じゅうさんにち", 14: "じゅうよっか",
    15: "じゅうごにち", 16: "じゅうろくにち", 17: "じゅうしちにち", 18: "じゅうはちにち",
    19: "じゅうくにち", 20: "はつか", 21: "にじゅういちにち", 22: "にじゅうににち",
    23: "にじゅうさんにち", 24: "にじゅうよっか", 25: "にじゅうごにち",
    26: "にじゅうろくにち", 27: "にじゅうしちにち", 28: "にじゅうはちにち",
    29: "にじゅうくにち", 30: "さんじゅうにち", 31: "さんじゅういちにち",
}
WEEKDAYS_KANJI = ["月", "火", "水", "木", "金", "土", "日"]


def minutes_ja(m):
    if m == 0:
        return ""
    tens, units = divmod(m, 10)
    return MIN_TENS.get(tens, "") + MIN_UNITS[units]


def time_ja(now):
    h_ja = HOURS[now.hour]
    m_ja = minutes_ja(now.minute)
    return f"{h_ja} {m_ja}".strip() if m_ja else h_ja


def date_ja(now):
    return f"{MONTHS[now.month]} {DAYS[now.day]}"


def calendar_text(year, month):
    cal = __import__("calendar").Calendar(firstweekday=0)
    lines = []
    for week in cal.monthdayscalendar(year, month):
        cells = []
        for d in week:
            if d == 0:
                cells.append("  ")
            elif d == datetime.date.today().day:
                cells.append(f"[{d:2d}]")
            else:
                cells.append(f" {d:2d}")
        lines.append(" ".join(cells).rstrip())
    return "\n".join(lines)


# ── Wallpaper courant ─────────────────────────────────────────────────────
def read_waypaper_wallpaper():
    """Lit le chemin du wallpaper depuis la config waypaper."""
    try:
        with open(WAYPAPER_CONFIG) as f:
            for line in f:
                line = line.strip()
                if line.startswith("wallpaper") and "=" in line:
                    path = line.split("=", 1)[1].strip()
                    return os.path.expanduser(path)
    except OSError:
        pass
    return None


def monitor_size():
    """Taille du premier moniteur via hyprctl (fallback 1920x1080)."""
    try:
        out = subprocess.run(
            ["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=2
        ).stdout
        mons = json.loads(out)
        if mons:
            m = mons[0]
            return m["width"], m["height"]
    except Exception:
        pass
    return 1920, 1080


# ── Analyse d'image : trouver la zone plate ───────────────────────────────
def find_flat_position(img_path, scr_w, scr_h):
    """
    Analyse le wallpaper et renvoie (x, y, zone_rgb) :
      * (x, y) = CENTRE en pixels écran de la zone la plus plate
        (faible variance de couleur, loin des bords) ;
      * zone_rgb = (r, g, b) 0..255 couleur MOYENNE de cette zone
        (le fond derrière l'horloge — sert à choisir la couleur du texte).
    """
    if not HAS_IMAGING:
        return (scr_w // 2, scr_h - 120), (200, 200, 200)

    try:
        img = Image.open(img_path).convert("RGB")
    except OSError:
        return (scr_w // 2, scr_h - 120), (200, 200, 200)

    iw, ih = img.size
    scale = max(scr_w / iw, scr_h / ih)
    disp_w, disp_h = iw * scale, ih * scale
    off_x = max(0, (disp_w - scr_w) / 2)
    off_y = max(0, (disp_h - scr_h) / 2)

    small = img.resize((GRID_W, GRID_H))
    arr = np.asarray(small, dtype=float)
    std = arr.std(axis=2)  # (GRID_H, GRID_W)

    cw, ch = CLOCK_CELLS_W, CLOCK_CELLS_H
    best_score, best = float("inf"), None
    step = 2
    for gy in range(0, GRID_H - ch + 1, step):
        for gx in range(0, GRID_W - cw + 1, step):
            region = std[gy:gy + ch, gx:gx + cw]
            score = region.mean()
            edge = min(gx, GRID_W - gx - cw, gy, GRID_H - gy - ch)
            score += max(0, 6 - edge) * 4.0
            if score < best_score:
                best_score, best = score, (gx, gy)

    if best is None:
        return (scr_w // 2, scr_h - 120), (200, 200, 200)

    gx, gy = best
    # Couleur moyenne de la zone (dans la grille réduite : suffisant)
    zone = arr[gy:gy + ch, gx:gx + cw].reshape(-1, 3)
    zone_rgb = tuple(int(round(v)) for v in zone.mean(axis=0))
    cx_img = (gx + cw / 2) / GRID_W * iw
    cy_img = (gy + ch / 2) / GRID_H * ih
    sx = cx_img * scale - off_x
    sy = cy_img * scale - off_y
    return (int(sx), int(sy)), zone_rgb


def adapt_text_color(zone_rgb, lighten_amount=0.35):
    """
    Couleur de texte lisible sur une zone du wallpaper, « un peu plus light ».

    Prend la couleur MOYENNE de la zone plate et l'éclaircit vers le blanc
    (comme demandé par momo : « choisit avec la couleur mais un peu plus
    light »). Si la zone est déjà claire, on fonce à la place pour garder
    le contraste (texte blanc sur fond blanc = illisible).
    Retourne (fg_hex, fg_dim_hex) pour l'heure et la date secondaire.
    """
    r, g, b = (c / 255.0 for c in zone_rgb)
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    if lum < 0.45:
        # fond sombre → éclaircir (la demande « light »)
        def mix(c):
            return int(round((c + (1.0 - c) * lighten_amount) * 255))
        fg = (mix(r), mix(g), mix(b))
        dim = tuple(int(round(c * 0.72)) for c in fg)  # un peu plus discret
    else:
        # fond clair → foncer pour rester lisible
        def mix(c):
            return int(round(c * (1.0 - lighten_amount) * 255))
        fg = (mix(r), mix(g), mix(b))
        dim = tuple(int(round(c * 0.72)) for c in fg)
    return "#{:02x}{:02x}{:02x}".format(*fg), "#{:02x}{:02x}{:02x}".format(*dim)


# ── Fenêtre layer-shell ───────────────────────────────────────────────────
class WallClock:
    def __init__(self):
        self.palette = read_palette()
        self.fg = self.palette.get("@foreground", TEXT_FG)
        self.fg_dim = self.palette.get("@color2", TEXT_FG_DIM)

        self.win = Gtk.Window()
        self.win.set_title("sasquatch-wallclock")
        self.win.set_app_paintable(True)
        self.win.set_decorated(False)
        self.win.set_skip_taskbar_hint(True)
        self.win.set_accept_focus(False)

        screen = self.win.get_screen()
        rgba = screen.get_rgba_visual()
        if rgba:
            self.win.set_visual(rgba)

        GtkLayerShell.init_for_window(self.win)
        # Layer BOTTOM (pas BACKGROUND) : hyprpaper est en background et waypaper
        # le re-charge AU-DESSUS des layers background existants quand le
        # wallpaper change → un wallclock en background passe DERRIÈRE le fond
        # d'écran (invisible). BOTTOM est au-dessus de background mais SOUS les
        # fenêtres normales → toujours visible sur le fond, jamais devant les apps.
        GtkLayerShell.set_layer(self.win, GtkLayerShell.Layer.BOTTOM)
        GtkLayerShell.set_keyboard_mode(self.win, GtkLayerShell.KeyboardMode.NONE)
        GtkLayerShell.auto_exclusive_zone_enable(self.win)
        GtkLayerShell.set_anchor(self.win, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self.win, GtkLayerShell.Edge.LEFT, True)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.win.add(box)

        self.lbl_time = Gtk.Label()
        self.lbl_time.set_use_markup(True)
        box.pack_start(self.lbl_time, False, False, 0)

        self.lbl_date = Gtk.Label()
        self.lbl_date.set_use_markup(True)
        box.pack_start(self.lbl_date, False, False, 0)

        self.win.set_has_tooltip(True)
        self.win.connect("draw", self.on_draw)
        self.win.show_all()

        # Mesure : taille intrinsèque du contenu
        self.update_label()
        self.win.resize(1, 1)
        self.win.queue_resize()

        # État animation
        self.cur_x, self.cur_y = None, None
        self.target_x, self.target_y = None, None
        self.anim_start = 0
        self.current_wallpaper = None
        self.last_wallpaper_mtime = 0

        GLib.idle_add(self.initial_place)
        GLib.timeout_add(REFRESH_MS, self.on_refresh)
        GLib.timeout_add(WATCH_MS, self.on_watch)

    def on_draw(self, widget, cr):
        cr.set_source_rgba(0, 0, 0, 0)
        cr.set_operator(__import__("cairo").OPERATOR_SOURCE)
        cr.paint()
        return False

    def update_label(self):
        now = datetime.datetime.now()
        t_ja = time_ja(now)
        d_ja = date_ja(now)
        wd = WEEKDAYS_KANJI[now.weekday()]
        self.lbl_time.set_markup(
            f'<span font="{FONT_TIME}" foreground="{self.fg}">{t_ja}</span>'
        )
        self.lbl_date.set_markup(
            f'<span font="{FONT_DATE}" foreground="{self.fg_dim}">'
            f"{d_ja}（{wd}） {now:%Y}</span>"
        )
        self.win.set_tooltip_markup(
            f"{t_ja}  —  {now:%H:%M}\n"
            f"{d_ja}（{wd}）  —  {now:%d %B %Y}\n\n"
            f"<tt>{calendar_text(now.year, now.month)}</tt>"
        )
        # Force le recalcul de la taille désirée
        self.win.queue_resize()

    def measure_size(self):
        """Taille intrinsèque (label heure + date)."""
        w_time, h_time = self.lbl_time.get_preferred_width(), self.lbl_time.get_preferred_height()
        w_date, h_date = self.lbl_date.get_preferred_width(), self.lbl_date.get_preferred_height()
        w = max(w_time[1], w_date[1])
        h = h_time[1] + h_date[1] + 2
        return w, h

    def apply_position(self, x, y):
        """Positionne le COIN HAUT-GAUCHE de la fenêtre à (x, y) centré."""
        w, h = self.measure_size()
        GtkLayerShell.set_anchor(self.win, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self.win, GtkLayerShell.Edge.LEFT, True)
        GtkLayerShell.set_margin(self.win, GtkLayerShell.Edge.TOP, max(0, int(y - h / 2)))
        GtkLayerShell.set_margin(self.win, GtkLayerShell.Edge.LEFT, max(0, int(x - w / 2)))
        self.win.resize(w, h)
        self.win.queue_resize()
        # Input region : par défaut toute la surface est input region (le
        # hover/tooltip fonctionne sans appel explicite — set_input_region
        # n'existe PAS dans cette version de gtk-layer-shell).

    def refresh_palette(self):
        """Relit la palette (le thème change avec le wallpaper)."""
        self.palette = read_palette()
        self.fg = self.palette.get("@foreground", TEXT_FG)
        self.fg_dim = self.palette.get("@color2", TEXT_FG_DIM)
        self.update_label()

    def set_zone_color(self, zone_rgb):
        """Couleur du texte adaptée à la zone plate du wallpaper (light)."""
        self.fg, self.fg_dim = adapt_text_color(zone_rgb)
        self.update_label()

    def initial_place(self):
        wp = read_waypaper_wallpaper()
        if wp:
            self.current_wallpaper = wp
            try:
                self.last_wallpaper_mtime = os.path.getmtime(wp)
            except OSError:
                pass
            scr_w, scr_h = monitor_size()
            (cx, cy), zone_rgb = find_flat_position(wp, scr_w, scr_h)
            self.set_zone_color(zone_rgb)
            self.cur_x, self.cur_y = cx, cy
            self.target_x, self.target_y = cx, cy
            self.apply_position(cx, cy)
        return False

    def animate_to(self, tx, ty):
        """Lance une animation de glissement de la position courante → cible."""
        if self.cur_x is None:
            self.cur_x, self.cur_y = tx, ty
            self.apply_position(tx, ty)
            return
        self.target_x, self.target_y = tx, ty
        self.anim_start = time.monotonic()
        GLib.timeout_add(ANIM_MS, self.anim_tick)

    def anim_tick(self):
        t = (time.monotonic() - self.anim_start) / ANIM_DURATION
        if t >= 1.0:
            self.cur_x, self.cur_y = self.target_x, self.target_y
            self.apply_position(self.target_x, self.target_y)
            return False
        # ease-out-cubic
        e = 1 - (1 - t) ** EASE_POWER
        x = self.cur_x + (self.target_x - self.cur_x) * e
        y = self.cur_y + (self.target_y - self.cur_y) * e
        self.apply_position(int(x), int(y))
        return True

    def on_refresh(self):
        self.update_label()
        return True

    def on_watch(self):
        wp = read_waypaper_wallpaper()
        if wp:
            try:
                mt = os.path.getmtime(wp)
            except OSError:
                mt = 0
            if wp != self.current_wallpaper or mt != self.last_wallpaper_mtime:
                self.current_wallpaper = wp
                self.last_wallpaper_mtime = mt
                scr_w, scr_h = monitor_size()
                (tx, ty), zone_rgb = find_flat_position(wp, scr_w, scr_h)
                # Couleur du texte adaptée à la nouvelle zone plate
                self.set_zone_color(zone_rgb)
                # Repart de la position VISUELLE actuelle
                self.cur_x, self.cur_y = (self.target_x, self.target_y) \
                    if self.target_x is not None else (tx, ty)
                self.animate_to(tx, ty)
                # Le thème change avec le wallpaper → relire la palette
                self.refresh_palette()
        return True


# ── Cycle de vie ──────────────────────────────────────────────────────────
def kill_previous():
    try:
        with open(PIDFILE) as f:
            old = int(f.read().strip())
        if old != os.getpid():
            try:
                os.kill(old, signal.SIGTERM)
                time.sleep(0.3)
            except ProcessLookupError:
                pass
    except (OSError, ValueError):
        pass
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))


def main():
    kill_previous()
    atexit.register(lambda: os.path.exists(PIDFILE) and os.unlink(PIDFILE))
    WallClock()
    try:
        Gtk.main()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
