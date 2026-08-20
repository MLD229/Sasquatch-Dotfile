"""Wallpaper picker — lister / choisir / appliquer un fond d'écran (Sasquatch).

Le sélecteur (Quickshell, Super+Y) remplace waypaper comme outil de
changement de wallpaper. Le « souvenir » du dossier = la config waypaper
elle-même (clé folder=) : pas de fichier d'état séparé. Sur un fresh
install où le dossier mémorisé n'existe pas, la liste est vide et l'UI
invite à parcourir (zenity, lancé par le serveur — il a DISPLAY/WAYLAND
via le manager systemd user).

Pipeline apply : config.ini (folder + wallpaper) → `apply-wallpaper.sh`
(hyprpaper direct, plus de dépendance waypaper) → theme-apply.sh
→ toute la palette suit (waybar, kitty, fastfetch, CC, overlays japonais…).
Le script commun est partagé avec wallpaper.sh (restauration au login).
"""

import hashlib
import io
import os
import random
import subprocess

from config import RUNTIME_DIR

CONFIG_INI = os.path.expanduser("~/.config/waypaper/config.ini")
IMAGE_EXTS = (".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp")
THUMB_DIR = os.path.join(RUNTIME_DIR, "sasquatch-wp-thumbs")
THUMB_SIZE = (240, 135)


def _read_config():
    """Lit folder + wallpaper depuis config.ini waypaper (expansion ~)."""
    folder = wallpaper = None
    try:
        with open(CONFIG_INI) as f:
            for line in f:
                s = line.strip()
                key, _, val = s.partition("=")
                key = key.strip()
                if key == "folder":
                    folder = os.path.expanduser(val.strip())
                elif key == "wallpaper":
                    # Pas startswith : "wallpaperengine_folder" commence aussi
                    # par "wallpaper" → matching strict par clé exacte.
                    wallpaper = os.path.expanduser(val.strip())
    except OSError:
        pass
    return folder, wallpaper


def _write_config(folder, wallpaper):
    """Écrit folder= / wallpaper= dans config.ini, préserve le reste."""
    try:
        with open(CONFIG_INI) as f:
            lines = f.readlines()
    except OSError:
        lines = []
    out = []
    wf = ww = False
    for line in lines:
        s = line.strip()
        key = s.partition("=")[0].strip()
        if key == "folder" and folder is not None:
            out.append(f"folder = {folder}\n")
            wf = True
        elif key == "wallpaper" and wallpaper is not None:
            out.append(f"wallpaper = {wallpaper}\n")
            ww = True
        else:
            out.append(line)
    if folder is not None and not wf:
        out.append(f"folder = {folder}\n")
    if wallpaper is not None and not ww:
        out.append(f"wallpaper = {wallpaper}\n")
    try:
        with open(CONFIG_INI, "w") as f:
            f.writelines(out)
        return True
    except OSError:
        return False


def list_wallpapers():
    """Images du dossier courant (triées par nom) + état."""
    folder, current = _read_config()
    files = []
    if folder and os.path.isdir(folder):
        try:
            names = sorted(
                n for n in os.listdir(folder)
                if n.lower().endswith(IMAGE_EXTS)
                and os.path.isfile(os.path.join(folder, n))
            )
        except OSError:
            names = []
        files = [{"name": n, "path": os.path.join(folder, n)} for n in names]
    return {
        "folder": folder,
        "folderExists": bool(folder) and os.path.isdir(folder),
        "current": current,
        "files": files,
    }


def random_wallpaper():
    """Pioche un fichier aléatoire dans le dossier courant (bouton aléatoire)."""
    data = list_wallpapers()
    if not data["files"]:
        return {"ok": False, "error": "aucun fichier"}
    pick = random.choice(data["files"])
    return {"ok": True, "name": pick["name"], "path": pick["path"]}


def set_folder(folder):
    """Mémorise le dossier choisi (écrit config.ini folder=) + liste."""
    folder = os.path.expanduser((folder or "").strip())
    if not folder or not os.path.isdir(folder):
        return {"ok": False, "error": "dossier introuvable"}
    _write_config(folder, None)
    return {"ok": True, **list_wallpapers()}


def apply_wallpaper(path):
    """Applique un wallpaper : config.ini + apply-wallpaper.sh (hyprpaper
    direct, plus de dépendance waypaper) + theme-apply.sh (palette)."""
    path = os.path.expanduser((path or "").strip())
    if not path or not os.path.isfile(path):
        return {"ok": False, "error": "fichier introuvable"}
    if not _write_config(os.path.dirname(path), path):
        return {"ok": False, "error": "config illisible"}
    script = os.path.expanduser("~/.config/cc/apply-wallpaper.sh")
    try:
        subprocess.Popen(
            [script, path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        return {"ok": False, "error": "apply-wallpaper.sh introuvable"}
    return {"ok": True}


def pick_path(kind):
    """Sélecteur natif zenity (le serveur a DISPLAY/WAYLAND via le manager).
    kind: "folder" → dossier, sinon fichier. Renvoie {ok, path}."""
    if kind == "folder":
        cmd = ["zenity", "--file-selection", "--directory",
               "--title=Choisir un dossier de fonds d'écran"]
    else:
        cmd = ["zenity", "--file-selection",
               "--title=Choisir un fond d'écran"]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    except (OSError, subprocess.TimeoutExpired):
        return {"ok": False, "error": "zenity indisponible"}
    path = proc.stdout.strip()
    if proc.returncode != 0 or not path:
        return {"ok": False, "error": "annulé"}
    return {"ok": True, "path": path}


def thumbnail(path):
    """Miniature JPEG (cache sha1) pour le filmstrip du sélecteur."""
    path = os.path.expanduser((path or "").strip())
    if not path or not os.path.isfile(path):
        return None
    try:
        from PIL import Image
    except ImportError:
        return None
    key = hashlib.sha1(path.encode()).hexdigest()[:16]
    os.makedirs(THUMB_DIR, exist_ok=True)
    out_path = os.path.join(THUMB_DIR, key + ".jpg")
    if os.path.exists(out_path):
        try:
            with open(out_path, "rb") as f:
                return f.read()
        except OSError:
            pass
    try:
        img = Image.open(path)
        # Pillow ≥ 9.1 : Image.Resampling.LANCZOS (ancien alias Image.LANCZOS
        # toujours valide en runtime mais inconnu de Pyright → getattr).
        resample = getattr(Image, "Resampling", Image).LANCZOS
        img.thumbnail(THUMB_SIZE, resample)
        buf = io.BytesIO()
        img.convert("RGB").save(buf, "JPEG", quality=82)
        data = buf.getvalue()
        with open(out_path, "wb") as f:
            f.write(data)
        return data
    except Exception:
        return None
