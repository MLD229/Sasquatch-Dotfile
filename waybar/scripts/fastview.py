#!/usr/bin/env python3
"""
sasquatch-fastview — aperçu des workspaces au survol (waybar + Hyprland).

Quand le curseur survole un numéro de workspace dans waybar, une fenêtre
layer-shell (overlay, sans focus) s'affiche sous la barre avec un aperçu du
bureau de ce workspace :

  * workspace VISIBLE (actif sur le moniteur sous le curseur)
      -> capture grim réelle du bbox des fenêtres. grim ne capture que ce
         qui est rendu à l'écran, donc seul le workspace actif est capturable
         sans changer de workspace (ce qui provoquerait un flash visible).
  * workspace INACTIF
      -> mini-plan schématique dessiné (cairo) depuis `hyprctl clients -j` :
         chaque fenêtre = rectangle arrondi positionné à l'échelle, coloré
         par classe, avec titre. Instantané, sans flash, sans capture.

Le daemon est lancé par waybar via le module invisible `custom/fastview`
(format vide). Cycle de vie :
  * pidfile /tmp/sasquatch-fastview.pid — au démarrage, un ancien daemon
    encore vivant (ex: relance de waybar) est tué et remplacé ;
  * watchdog — si waybar n'est plus vivant, le daemon s'arrête tout seul.

Aucun polling coûteux : le curseur est lu à 25 Hz (hyprctl cursorpos ~1 ms),
la capture grim n'a lieu qu'à l'entrée en hover (cache 8 s par workspace),
et `hyprctl clients -j` n'est relu qu'à 1 Hz pendant qu'un aperçu schématique
est affiché.

Palette : relue depuis waybar/style.css (bloc SASQUATCH-PALETTE) à chaque
affichage -> le popup suit la palette dynamique du thème.
"""

import atexit
import json
import math
import os
import signal
import subprocess
import sys
import time

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, Pango, PangoCairo, GtkLayerShell

# ── Constantes ────────────────────────────────────────────────────────────
PIDFILE = "/tmp/sasquatch-fastview.pid"
STYLE_CSS = os.path.expanduser("~/.config/waybar/style.css")

POLL_MS = 40            # lecture du curseur (25 Hz)
DATA_MS = 1000          # rafraîchissement données hyprctl pendant l'affichage
BARS_TTL = 0.5          # cache géométrie waybar (secondes)
CAPTURE_TTL = 8.0       # cache capture grim par workspace (secondes)
CAPTURE_PAD = 8         # marge autour du bbox des fenêtres pour la capture
BAR_TOP_RESERVED = 42   # hauteur réservée waybar (36 + marge 6) — zone exclue
WS_COUNT = 10           # persistent-workspaces "*": 10
WS_MARGIN = 6           # CSS #workspaces { margin: 0 6px }
WS_PADDING = 4          # CSS #workspaces { padding: 0 4px }
BTN_MIN_W = 24          # CSS #workspaces button { min-width: 24px }
BTN_PAD = 7             # CSS #workspaces button { padding: 0 7px }
FONT_BTN = "JetBrainsMono Nerd Font 14"
FONT_TITLE = "JetBrainsMono Nerd Font 9"
# Labels des boutons workspaces (waybar config : format "{name}", noms définis
# dans hypr/conf.d/rules.conf) — la mesure des largeurs DOIT utiliser les
# MÊMES textes que waybar, sinon le hover fastview est décalé.
WS_LABELS = ["いち", "に", "さん", "よん", "ご", "ろく", "なな", "はち", "きゅう", "じゅう"]

POPUP_W = 340
POPUP_H_MAX = 230
POPUP_PAD = 12
CAPTURE_DIR = "/tmp"


# ── Hyprland IPC ──────────────────────────────────────────────────────────
def hyprctl(args, as_json=False):
    """Appelle hyprctl et renvoie la sortie (dict si as_json)."""
    try:
        out = subprocess.run(
            ["hyprctl", *args], capture_output=True, text=True, timeout=2
        ).stdout
    except Exception:
        return {} if as_json else ""
    if as_json:
        try:
            return json.loads(out)
        except Exception:
            return {}
    return out


def ensure_instance_env():
    """Sécurise HYPRLAND_INSTANCE_SIGNATURE (multi-sessions)."""
    if "HYPRLAND_INSTANCE_SIGNATURE" not in os.environ:
        inst = hyprctl(["instances", "-j"], as_json=True)
        if isinstance(inst, list) and inst:
            os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = inst[0].get("instance", "")


# ── Données Hyprland ──────────────────────────────────────────────────────
def get_monitors():
    return hyprctl(["monitors", "-j"], as_json=True)


def get_clients():
    return hyprctl(["clients", "-j"], as_json=True)


def cursor_pos():
    p = hyprctl(["cursorpos", "-j"], as_json=True)
    return (p.get("x"), p.get("y")) if isinstance(p, dict) else (None, None)


def get_waybar_bars():
    """Renvoie [(mon_name, x, y, w, h), ...] pour les surfaces waybar."""
    layers = hyprctl(["layers", "-j"], as_json=True)
    bars = []
    if not isinstance(layers, dict):
        return bars
    for mon_name, mon_data in layers.items():
        for arr in (mon_data.get("levels") or {}).values():
            for s in arr:
                if s.get("namespace") == "waybar":
                    bars.append((mon_name, s["x"], s["y"], s["w"], s["h"]))
    return bars


def gdk_monitor_for(mon):
    """Gdk.Monitor correspondant au moniteur hyprctl (par géométrie).

    `hyprctl monitors -j` n'a PAS de clé "index" (c'est "id"), et l'id
    Hyprland n'est pas l'index Gdk. On matche donc par géométrie
    (x, y, width, height), robuste en single et multi-moniteur.
    """
    disp = Gdk.Display.get_default()
    if disp is None:
        return None
    for i in range(disp.get_n_monitors()):
        gm = disp.get_monitor(i)
        g = gm.get_geometry()
        if (
            g.x == mon.get("x", 0)
            and g.y == mon.get("y", 0)
            and g.width == mon.get("width")
            and g.height == mon.get("height")
        ):
            return gm
    return None


def windows_of(ws_id, mon_index):
    """Fenêtres mappées du workspace ws_id sur le moniteur mon_index."""
    clients = get_clients()
    if not isinstance(clients, list):
        return []
    return [
        c
        for c in clients
        if c.get("mapped")
        and not c.get("hidden")
        and (c.get("workspace") or {}).get("id") == ws_id
        and c.get("monitor") == mon_index
        and c.get("at") and c.get("size")
    ]


def stable_hash(s):
    """Hash stable inter-processus (pas de randomisation Python)."""
    return sum(ord(ch) for ch in s)


# ── Géométrie des boutons de workspace ────────────────────────────────────
def measure_button_widths():
    """Largeur de chaque bouton (Pango, même fonte que waybar)."""
    label = Gtk.Label()
    ctx = label.get_pango_context()
    fd = Pango.font_description_from_string(FONT_BTN)
    layout = Pango.Layout.new(ctx)
    layout.set_font_description(fd)
    widths = []
    for i in range(1, WS_COUNT + 1):
        layout.set_text(WS_LABELS[i - 1], -1)
        tw, _ = layout.get_pixel_size()
        widths.append(max(BTN_MIN_W, tw) + 2 * BTN_PAD)
    return widths


# ── Palette (relue depuis style.css) ──────────────────────────────────────
def read_palette():
    pal = {}
    try:
        with open(STYLE_CSS, encoding="utf-8") as f:
            for line in f:
                m = line.strip().split()
                if (
                    len(m) >= 3
                    and m[0] == "@define-color"
                    and (m[1].startswith("color") or m[1] in ("background", "foreground"))
                ):
                    pal[m[1]] = m[2]
    except OSError:
        pass
    # Fallback (palette par défaut du style.css actuel)
    pal.setdefault("background", "#161415")
    pal.setdefault("foreground", "#d2d0d1")
    for i in range(16):
        pal.setdefault(f"color{i}", "#89dceb")
    return pal


def color_of(pal, name):
    """Renvoie (r, g, b) 0..1 à partir d'un hex #rrggbb."""
    h = pal.get(name, "#ffffff").lstrip("#")
    try:
        return tuple(int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4))
    except ValueError:
        return (1.0, 1.0, 1.0)


# ── Capture grim (workspace visible uniquement) ───────────────────────────
def capture_ws(ws_id, mon):
    """Capture le bbox des fenêtres du ws visible ; renvoie le chemin PNG."""
    mon_index = mon.get("id")
    wins = windows_of(ws_id, mon_index)
    if not wins:
        return None
    x1 = min(c["at"][0] for c in wins)
    y1 = min(c["at"][1] for c in wins)
    x2 = max(c["at"][0] + c["size"][0] for c in wins)
    y2 = max(c["at"][1] + c["size"][1] for c in wins)
    x1 = max(x1 - CAPTURE_PAD, 0)
    y1 = max(y1 - CAPTURE_PAD, BAR_TOP_RESERVED)
    x2 = min(x2 + CAPTURE_PAD, mon["width"])
    y2 = min(y2 + CAPTURE_PAD, mon["height"])
    if x2 <= x1 or y2 <= y1:
        return None
    path = os.path.join(CAPTURE_DIR, f"sasquatch-fastview-{ws_id}.png")
    try:
        r = subprocess.run(
            ["grim", "-t", "png", "-g", f"{x1},{y1} {x2 - x1}x{y2 - y1}", path],
            capture_output=True, text=True, timeout=5,
        )
    except Exception:
        return None
    return path if r.returncode == 0 and os.path.exists(path) else None


# ── Daemon fastview ───────────────────────────────────────────────────────
class FastView:
    def __init__(self):
        self.bar_widths = measure_button_widths()
        self.module_span = WS_MARGIN + WS_PADDING + sum(self.bar_widths)
        self.palette = {}
        self._provider = None
        self.popup = None
        self.drawing = None
        self.title_label = None
        self.state = None        # dict de l'aperçu affiché
        self.hovered = None      # (ws_id, mon_name)
        self.cache = {}          # ws_id -> (ts, state)
        self.active_ws = {}      # mon_name -> ws_id (rafraîchi)
        self._bars = []
        self._bars_ts = 0.0
        self._sup_ts = 0.0       # cache condition de suppression
        self._suppressed = False

    # ── Cycle de vie ──────────────────────────────────────────────────
    def take_over(self):
        if os.path.exists(PIDFILE):
            try:
                old = int(open(PIDFILE).read().strip())
                cmd = open(f"/proc/{old}/cmdline", "rb").read().decode()
                if "fastview" in cmd:
                    os.kill(old, signal.SIGTERM)
                    time.sleep(0.4)
            except Exception:
                pass
        with open(PIDFILE, "w") as f:
            f.write(str(os.getpid()))
        atexit.register(self._cleanup)

    def _cleanup(self):
        try:
            os.unlink(PIDFILE)
        except OSError:
            pass

    def _waybar_alive(self):
        try:
            return (
                subprocess.run(["pgrep", "-x", "waybar"],
                               capture_output=True, timeout=2).returncode == 0
            )
        except Exception:
            return True

    # ── Fenêtre popup (layer-shell) ────────────────────────────────────
    def build_popup(self):
        win = Gtk.Window.new(Gtk.WindowType.POPUP)
        win.set_app_paintable(True)
        GtkLayerShell.init_for_window(win)
        GtkLayerShell.set_namespace(win, "sasquatch-fastview")
        GtkLayerShell.set_layer(win, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.LEFT, True)
        GtkLayerShell.set_keyboard_mode(win, GtkLayerShell.KeyboardMode.NONE)
        win.set_size_request(POPUP_W, 1)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.set_name("fastview-box")
        self.title_label = Gtk.Label(xalign=0.0)
        self.title_label.set_name("fastview-title")
        box.pack_start(self.title_label, False, False, 0)

        self.drawing = Gtk.DrawingArea()
        self.drawing.set_size_request(POPUP_W - 2 * POPUP_PAD, 140)
        self.drawing.connect("draw", self.on_draw)
        box.pack_start(self.drawing, True, True, 0)

        win.add(box)
        win.connect("destroy", Gtk.main_quit)
        win.show_all()
        win.hide()
        self.popup = win

    def apply_palette_css(self):
        self.palette = read_palette()
        bg = color_of(self.palette, "background")
        fg = color_of(self.palette, "foreground")
        ac = color_of(self.palette, "color4")
        css = (
            f"window {{ background: rgba({int(bg[0]*255)},{int(bg[1]*255)},{int(bg[2]*255)},0.92);"
            f" border-radius: 12px; }} \n"
            f"#fastview-box {{ border: 1px solid rgba({int(ac[0]*255)},{int(ac[1]*255)},{int(ac[2]*255)},0.55);"
            f" border-radius: 12px; padding: 8px; background: transparent; }} \n"
            f"#fastview-title {{ color: rgba({int(ac[0]*255)},{int(ac[1]*255)},{int(ac[2]*255)},1.0);"
            f" font-weight: bold; font-size: 12px; padding-bottom: 2px; }} \n"
        )
        if self._provider is None:
            self._provider = Gtk.CssProvider()
            Gtk.StyleContext.add_provider_for_screen(
                Gdk.Screen.get_default(), self._provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
            )
        self._provider.load_from_data(css.encode())

    # ── Condition de suppression ─────────────────────────────────────
    def _is_suppressed(self, mon_name):
        """Vrai si le popup ne doit PAS s'afficher :
        1. une fenêtre est en fullscreen sur ce moniteur (vidéo/jeu → pas
           d'aperçu au survol), OU
        2. la waybar n'est pas affichée sur ce moniteur (le fastview vit
           dans la waybar : pas de barre → pas de popup).
        Cache 0,5 s (coût hyprctl clients -j).
        """
        now = time.monotonic()
        if now - self._sup_ts < 0.5:
            return self._suppressed
        self._sup_ts = now
        # 2. waybar absente → supprimé (le hover gère déjà le cas où le
        # curseur sort de la barre ; ici on couvre le cas barre entière
        # invisible sur ce moniteur).
        bar_present = any(b[0] == mon_name for b in self._bars)
        if not bar_present:
            self._suppressed = True
            return True
        clients = get_clients()
        if not isinstance(clients, list):
            self._suppressed = False
            return False
        # moniteur sous le curseur (par nom)
        mon_id = None
        mons = get_monitors()
        if isinstance(mons, list):
            for m in mons:
                if m.get("name") == mon_name:
                    mon_id = m.get("id")
                    break
        for c in clients:
            if not c.get("mapped"):
                continue
            if c.get("fullscreen") and (mon_id is None or c.get("monitor") == mon_id):
                self._suppressed = True
                return True
        self._suppressed = False
        return False

    # ── Données / état ────────────────────────────────────────────────
    def refresh_active(self):
        mons = get_monitors()
        if isinstance(mons, list):
            for m in mons:
                ws = (m.get("activeWorkspace") or {}).get("id")
                if ws is not None:
                    self.active_ws[m["name"]] = ws
        return mons if isinstance(mons, list) else []

    def build_state(self, ws_id, mon, mon_index):
        """Construit l'état de l'aperçu : mode image / schematic / vide."""
        now = time.time()
        cached = self.cache.get(ws_id)
        if cached and now - cached[0] < CAPTURE_TTL:
            return cached[1]

        if self.active_ws.get(mon["name"]) == ws_id:
            path = capture_ws(ws_id, mon)
            if path:
                try:
                    pix = GdkPixbuf.Pixbuf.new_from_file(path)
                    scale = min(
                        (POPUP_W - 2 * POPUP_PAD) / pix.get_width(),
                        (POPUP_H_MAX - 26) / pix.get_height(),
                    )
                    w = max(1, int(pix.get_width() * scale))
                    h = max(1, int(pix.get_height() * scale))
                    scaled = pix.scale_simple(
                        w, h, GdkPixbuf.InterpType.BILINEAR
                    )
                    st = {
                        "mode": "image",
                        "pixbuf": scaled,
                        "ws": ws_id,
                        "mon": mon,
                        "n": len(windows_of(ws_id, mon_index)),
                    }
                    self.cache[ws_id] = (now, st)
                    return st
                except Exception:
                    pass

        wins = windows_of(ws_id, mon_index)
        st = {
            "mode": "schematic" if wins else "empty",
            "wins": wins,
            "ws": ws_id,
            "mon": mon,
        }
        self.cache[ws_id] = (now, st)
        return st

    def live_refresh(self):
        """Relu des données à 1 Hz : rafraîchit le schéma, jamais l'image
        (re-capturer pendant que le popup est affiché le capturerait lui-même).
        Cache aussi le popup si la suppression (fullscreen / CC fermé) devient
        active pendant un hover prolongé.
        """
        if self.hovered and self.popup and self.popup.get_visible():
            ws_id, mon_name = self.hovered
            if self._is_suppressed(mon_name):
                self._hide()
                return True
            cached = self.cache.get(ws_id)
            if cached and cached[1].get("mode") != "image":
                self.cache.pop(ws_id, None)
                self.show_state(ws_id, mon_name)
        return True

    # ── Affichage ─────────────────────────────────────────────────────
    def show_state(self, ws_id, mon_name):
        mons = self.refresh_active()
        mon = next((m for m in mons if m["name"] == mon_name), None)
        if mon is None:
            return
        st = self.build_state(ws_id, mon, mon.get("id"))
        n = st.get("n", len(st.get("wins", [])))
        actif = "  ● アクティブ" if self.active_ws.get(mon_name) == ws_id else ""
        label = WS_LABELS[ws_id - 1] if 1 <= ws_id <= WS_COUNT else str(ws_id)
        self.title_label.set_markup(
            f"ワークスペース {label} — espace de travail {ws_id}{actif}"
            f"   <span alpha='60%'>· {n} fenêtre(s)</span>"
        )

        if st["mode"] == "image":
            ph = min(st["pixbuf"].get_height(), POPUP_H_MAX - 26)
        elif st["mode"] == "schematic":
            mw = mon["width"]
            mh = mon["height"] - BAR_TOP_RESERVED
            scale = min((POPUP_W - 2 * POPUP_PAD) / mw, (POPUP_H_MAX - 26) / mh)
            ph = max(1, int(mh * scale))
        else:
            ph = 90
        self.drawing.set_size_request(POPUP_W - 2 * POPUP_PAD, ph)
        self.drawing.queue_draw()

        self.state = st
        self.apply_palette_css()
        self.place_and_show(ws_id, mon_name)

    def place_and_show(self, ws_id, mon_name):
        bars = get_waybar_bars()
        bar = next((b for b in bars if b[0] == mon_name), None)
        mons = get_monitors()
        mon = next((m for m in mons if m["name"] == mon_name), None)
        if bar is None or mon is None:
            return
        _, bx, by, _, bh = bar
        idx = ws_id - 1
        cx = (
            bx + WS_MARGIN + WS_PADDING
            + sum(self.bar_widths[:idx]) + self.bar_widths[idx] // 2
        )
        popup_x = max(8, min(cx - POPUP_W // 2, mon["width"] - POPUP_W - 8))
        # layer-shell : y rendu = zone exclusive des layers inférieurs (réservé
        # par waybar en haut) + margin_top. On compense pour viser le y absolu.
        reserved = mon.get("reserved") or [0, 0, 0, 0]
        reserved_top = reserved[1] if isinstance(reserved, list) and len(reserved) >= 2 else 0
        margin_top = max(0, (by + bh + 4) - reserved_top)
        popup_y = by + bh + 4

        # Multi-moniteur : poser le popup sur le moniteur du curseur
        try:
            gdk_mon = gdk_monitor_for(mon)
            if gdk_mon:
                GtkLayerShell.set_monitor(self.popup, gdk_mon)
        except Exception:
            pass

        GtkLayerShell.set_margin(self.popup, GtkLayerShell.Edge.TOP, margin_top)
        GtkLayerShell.set_margin(self.popup, GtkLayerShell.Edge.LEFT, popup_x)
        self.popup.show()

    def on_draw(self, widget, cr):
        if not self.state:
            return
        st = self.state
        w = widget.get_allocated_width()
        h = widget.get_allocated_height()

        # Fond sombre OPAQUE : le thème GTK par défaut (Adwaita light) peint
        # le DrawingArea en gris clair et transparaît sous les alpha du
        # schéma → popup « clair » malgré la palette. On repeint toujours
        # le fond avec la couleur du thème avant le contenu.
        bg = color_of(self.palette, "background")
        cr.set_source_rgba(*bg, 1.0)
        cr.rectangle(0, 0, w, h)
        cr.fill()

        if st["mode"] == "image":
            pix = st["pixbuf"]
            x = (w - pix.get_width()) / 2
            y = (h - pix.get_height()) / 2
            cr.save()
            cr.translate(x, y)
            Gdk.cairo_set_source_pixbuf(cr, pix, 0, 0)
            cr.paint()
            cr.restore()
            return

        if st["mode"] == "empty":
            self._draw_rounded(cr, 0, 0, w, h, 10,
                               color_of(self.palette, "color8"), 0.15)
            layout = self._make_layout(widget, "Aucune fenêtre", FONT_TITLE)
            tw, th = layout.get_pixel_size()
            cr.set_source_rgba(*color_of(self.palette, "color8"), 0.9)
            cr.move_to((w - tw) / 2, (h - th) / 2)
            PangoCairo.show_layout(cr, layout)
            return

        # schematic
        mon = st["mon"]
        mw = mon["width"]
        mh = mon["height"] - BAR_TOP_RESERVED
        scale = min(w / mw, h / mh)
        ox = (w - mw * scale) / 2
        oy = (h - mh * scale) / 2

        self._draw_rounded(cr, ox, oy, mw * scale, mh * scale, 8,
                           color_of(self.palette, "background"), 0.55)
        for win in st["wins"]:
            wx = win["at"][0]
            wy = win["at"][1] - BAR_TOP_RESERVED
            ww = win["size"][0]
            wh = win["size"][1]
            rx = ox + wx * scale
            ry = oy + wy * scale
            rw = max(2.0, ww * scale)
            rh = max(2.0, wh * scale)
            cls = (win.get("class") or win.get("initialClass") or "?").lower()
            c = color_of(self.palette, f"color{1 + (stable_hash(cls) % 15)}")
            self._draw_rounded(cr, rx, ry, rw, rh, min(6, rw / 6), c, 0.35)
            cr.set_line_width(1.0)
            cr.set_source_rgba(*c, 0.9)
            cr.rectangle(rx + 0.5, ry + 0.5, max(0, rw - 1), max(0, rh - 1))
            cr.stroke()
            if rw > 70 and rh > 20:
                layout = self._make_layout(
                    widget, self._clip_title(win, rw / scale), FONT_TITLE
                )
                cr.set_source_rgba(*color_of(self.palette, "foreground"), 0.95)
                cr.move_to(rx + 4, ry + max(2, (rh - layout.get_pixel_size()[1]) / 2))
                PangoCairo.show_layout(cr, layout)

    def _clip_title(self, win, max_w_px):
        title = (win.get("title") or win.get("initialTitle") or "").strip()
        if not title:
            title = win.get("class") or "fenêtre"
        return title[: max(1, int(max_w_px / 7))]

    def _make_layout(self, widget, text, font):
        layout = widget.create_pango_layout(text)
        layout.set_font_description(Pango.font_description_from_string(font))
        return layout

    def _draw_rounded(self, cr, x, y, w, h, r, rgb, alpha):
        r = min(r, w / 2, h / 2)
        cr.save()
        cr.new_sub_path()
        cr.arc(x + r, y + r, r, math.pi, 1.5 * math.pi)
        cr.arc(x + w - r, y + r, r, 1.5 * math.pi, 2 * math.pi)
        cr.arc(x + w - r, y + h - r, r, 0, 0.5 * math.pi)
        cr.arc(x + r, y + h - r, r, 0.5 * math.pi, math.pi)
        cr.close_path()
        cr.set_source_rgba(*rgb, alpha)
        cr.fill()
        cr.restore()

    # ── Boucle hover ──────────────────────────────────────────────────
    def poll_cursor(self):
        cx, cy = cursor_pos()
        if cx is None:
            return True
        now = time.monotonic()
        if now - self._bars_ts > BARS_TTL:
            self._bars = get_waybar_bars()
            self._bars_ts = now
        bars = self._bars

        bar = None
        for b in bars:
            _, bx, by, bw, bh = b
            if by <= cy <= by + bh and bx <= cx <= bx + bw:
                bar = b
                break
        if bar is None:
            self._hide()
            return True
        mon_name, bx, by, bw, bh = bar
        rel_x = cx - bx
        if rel_x < WS_MARGIN + WS_PADDING:
            self._hide()
            return True
        acc = WS_MARGIN + WS_PADDING
        idx = None
        for i, bwid in enumerate(self.bar_widths):
            if acc <= rel_x < acc + bwid:
                idx = i
                break
            acc += bwid
        if idx is None:
            self._hide()
            return True

        ws_id = idx + 1
        if self._is_suppressed(mon_name):
            self._hide()
            return True
        if self.hovered != (ws_id, mon_name):
            self.hovered = (ws_id, mon_name)
            # état frais à l'entrée (sauf image encore chaude : pas de re-capture)
            cached = self.cache.get(ws_id)
            if not cached or time.time() - cached[0] >= CAPTURE_TTL:
                self.cache.pop(ws_id, None)
            self.show_state(ws_id, mon_name)
        return True

    def _hide(self):
        if self.hovered is not None:
            self.hovered = None
        if self.popup and self.popup.get_visible():
            self.popup.hide()

    def run(self):
        ensure_instance_env()
        self.take_over()
        self.build_popup()
        self.refresh_active()
        signal.signal(signal.SIGTERM, lambda *a: Gtk.main_quit())
        GLib.timeout_add(POLL_MS, self.poll_cursor)
        GLib.timeout_add(DATA_MS, self.live_refresh)
        GLib.timeout_add(
            2000, lambda: (Gtk.main_quit() if not self._waybar_alive() else True)
        )
        Gtk.main()


if __name__ == "__main__":
    FastView().run()
