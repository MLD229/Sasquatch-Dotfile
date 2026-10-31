#!/usr/bin/env python3
# appindex.py — index des fichiers .desktop pour la barre Quickshell (cc/bar).
#
# Deux modes :
#   appindex.py --json            → imprime l'index complet en JSON sur stdout
#   appindex.py --launch <id>     → lance l'application dont l'id desktop est <id>
#
# Aucun port, aucun service : l'index est calculé au démarrage (QML le lit via
# Quickshell.Io.Process) et écrit en cache dans cc/bar/appindex.json.
#
# JSON produit :
#   {"generated": <ts>, "apps": {"spotify": {"name": "Spotify", "icon": "/abs/spotify.png",
#                                            "exec": "spotify", "class": "spotify",
#                                            "terminal": false}, ...},
#    "classes": {"spotify": "spotify", ...}}   # classe normalisée → id desktop
#
# L'icône est résolue ici (thème hicolor puis Papirus puis Tango) : le QML ne
# fait aucun parcours de répertoire, il affiche un chemin absolu ou rien.

import json
import os
import re
import shutil
import subprocess
import sys
import time

HOME = os.path.expanduser("~")

DESKTOP_DIRS = [
    os.path.join(HOME, ".local/share/applications"),
    "/usr/share/applications",
    "/usr/local/share/applications",
    "/var/lib/flatpak/exports/share/applications",
    os.path.join(HOME, ".local/share/flatpak/exports/share/applications"),
    "/var/lib/snapd/desktop/applications",
]

# Ordre de préférence des thèmes (le premier trouvé gagne) ; hicolor est le
# standard, Papirus est ce qui est installé sur ce poste.
ICON_THEMES = ["hicolor", "Papirus", "Papirus-Dark", "Adwaita", "Tango"]
ICON_ROOTS = [
    os.path.join(HOME, ".local/share/icons"),
    os.path.join(HOME, ".icons"),
    "/usr/share/icons",
    "/usr/local/share/icons",
]
ICON_SIZES = ["512x512", "256x256", "128x128", "96x96", "64x64", "48x48",
              "32x32", "scalable", "symbolic", "24x24", "22x22", "16x16"]
ICON_EXTS = [".png", ".svg", ".xpm"]

_exec_cache = {}


def _norm_class(value):
    """Normalise un nom de classe Hyprland / id desktop (minuscules alnum)."""
    return re.sub(r"[^a-z0-9]", "", (value or "").lower())


def _parse_desktop(path):
    """Retourne un dict de la section [Desktop Entry], ou None."""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return None

    # Un .desktop peut contenir plusieurs groupes [X-...] : on ne lit que le
    # premier [Desktop Entry] (le reste = actions, non utilisé ici).
    entry = {}
    inside = False
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            if inside:          # deuxième groupe → on arrête
                break
            inside = line == "[Desktop Entry]"
            continue
        if not inside or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        if key not in entry:      # les clés localisées (Name[fr]) sont ignorées
            entry[key] = val.strip()
    return entry or None


def _icon_roots():
    """Liste des (thème, dossier) à fouiller, dans l'ordre de préférence."""
    roots = []
    for theme in ICON_THEMES:
        for root in ICON_ROOTS:
            base = os.path.join(root, theme)
            if not os.path.isdir(base):
                continue
            for size in ICON_SIZES:
                for cat in ("apps", "applications", "mimetypes", "devices"):
                    d = os.path.join(base, size, cat)
                    if os.path.isdir(d):
                        roots.append(d)
            # certains thèmes posent directement les icônes dans <theme>/
            roots.append(base)
    # dernier recours : pixmaps
    roots.append("/usr/share/pixmaps")
    roots.append(os.path.join(HOME, ".local/share/pixmaps"))
    return roots


def _index_dir(path):
    """mtime de l'index : sert de cache pour éviter de relister à chaque icône."""
    if path not in _exec_cache:
        try:
            _exec_cache[path] = set(os.listdir(path))
        except OSError:
            _exec_cache[path] = set()
    return _exec_cache[path]


def resolve_icon(name):
    """Chemin absolu d'une icône, ou "" si introuvable."""
    if not name:
        return ""
    name = name.strip().strip('"')
    if os.path.isabs(name) and os.path.isfile(name):
        return name
    stem, ext = os.path.splitext(name)
    if ext.lower() in ICON_EXTS:          # "spotify.png" → cherche "spotify.*"
        name = stem
    exts = ICON_EXTS
    for d in _icon_roots():
        entries = _index_dir(d)
        for e in exts:
            f = name + e
            if f in entries:
                return os.path.join(d, f)
    return ""


def _exec_program(exec_line):
    """Commande argv à partir de la ligne Exec (substitution %f/%u faite)."""
    # Nettoyage des jetons de substitution : la barre n'a pas de fichier à
    # passer, on retire donc les marqueurs (et leur argument collé).
    cmd = re.sub(r"%[fFuUdDnNickvm]", "", exec_line or "")
    parts = cmd.split()
    return [p for p in parts if p]


def build_index():
    apps = {}
    classes = {}
    sys_apps = {}      # NoDisplay/Hidden : fusionnées après (priorité aux visibles)
    for d in DESKTOP_DIRS:
        if not os.path.isdir(d):
            continue
        try:
            names = sorted(os.listdir(d))
        except OSError:
            continue
        for fn in names:
            if not fn.endswith(".desktop"):
                continue
            app_id = fn[: -len(".desktop")]
            if app_id in apps:            # ~/.local prime sur /usr/share
                continue
            entry = _parse_desktop(os.path.join(d, fn))
            if not entry:
                continue
            if entry.get("Type", "Application") != "Application":
                continue
            # NoDisplay/Hidden = applis « système » (modules KDE, configurateurs,
            # lanceurs internes) : absentes d'un menu, mais momo veut pouvoir les
            # épingler. On les indexe avec "system": true ; les entrées visibles
            # gardent la priorité (tableau `apps` et table `classes`).
            is_system = (entry.get("NoDisplay", "false").lower() == "true"
                         or entry.get("Hidden", "false").lower() == "true")
            exec_line = entry.get("Exec", "")
            argv = _exec_program(exec_line)
            if not argv:
                continue
            cls = entry.get("StartupWMClass", "") or app_id
            record = {
                "name": entry.get("Name", app_id),
                "icon": resolve_icon(entry.get("Icon", "")),
                "exec": exec_line,
                "argv": argv,
                "class": cls,
                "terminal": entry.get("Terminal", "false").lower() == "true",
                "system": is_system,
            }
            if is_system:
                # Mis de côté : fusionné APRÈS la boucle, sans écraser une
                # entrée visible portant le même id.
                sys_apps[app_id] = record
                continue
            apps[app_id] = record
            # Plusieurs clés possibles pour retrouver l'icône depuis Hyprland :
            # la classe déclarée, l'id desktop, et le nom du binaire lancé.
            for key in (cls, app_id, os.path.basename(argv[0])):
                k = _norm_class(key)
                if k and k not in classes:
                    classes[k] = app_id

    # Entrées système : elles complètent, elles n'écrasent jamais.
    for app_id, record in sys_apps.items():
        if app_id in apps:
            continue
        apps[app_id] = record
        for key in (record["class"], app_id, os.path.basename(record["argv"][0])):
            k = _norm_class(key)
            if k and k not in classes:
                classes[k] = app_id
    return {"generated": time.time(), "apps": apps, "classes": classes}


# ── Lancement ────────────────────────────────────────────────────────────────
def do_launch(app_id):
    idx = build_index()
    app = idx["apps"].get(app_id)
    if not app:
        # App épinglée devenue indisponible (paquet retiré, id désinstallé) :
        # message explicite, jamais un clic silencieux sans effet (brief §8).
        msg = f"application introuvable : {app_id}"
        print(f"appindex: {msg}", file=sys.stderr)
        try:
            subprocess.Popen(["notify-send", "Barre Sasquatch", msg, "-t", "3000"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             stdin=subprocess.DEVNULL, start_new_session=True,
                             close_fds=True)
        except OSError:
            pass
        return 2
    argv = list(app["argv"])
    if app.get("terminal"):
        term = os.environ.get("TERMINAL") or shutil.which("kitty") or "xterm"
        argv = [term, "-e"] + argv
    try:
        subprocess.Popen(argv, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                         start_new_session=True, close_fds=True,
                         cwd=HOME)
    except OSError as exc:
        print(f"appindex: lancement impossible ({app_id}): {exc}", file=sys.stderr)
        return 3
    return 0


def main(argv):
    if "--json" in argv:
        cache = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                             "appindex.json")
        idx = build_index()
        try:
            with open(cache, "w", encoding="utf-8") as fh:
                json.dump(idx, fh, ensure_ascii=False)
        except OSError:
            pass
        json.dump(idx, sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
        return 0
    if "--launch" in argv:
        i = argv.index("--launch")
        if i + 1 >= len(argv):
            print("appindex: --launch exige un id", file=sys.stderr)
            return 1
        return do_launch(argv[i + 1])
    if "--icon" in argv:
        i = argv.index("--icon")
        if i + 1 >= len(argv):
            return 1
        print(resolve_icon(argv[i + 1]))
        return 0
    print(__doc__ or "appindex.py --json | --launch <id> | --icon <name>",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
