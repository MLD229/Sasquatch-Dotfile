"""Gestionnaire de playlist MPD — panneau « Sasquatch Playlist » (Super+P).

Le panneau (pl/main.qml, lancé par pl/pl.sh) pilote le MPD via le serveur
CC (127.0.0.1:8765). Routes exposées (cc/server.py) :
  GET  /api/playlist/status  → random/repeat/single/consume + état
  GET  /api/playlist/list    → pistes de la playlist courante
  GET  /api/playlist/library → bibliothèque du dossier courant (scan + filtre)
  POST /api/playlist/toggle  {mode}   → random|repeat|single|consume
  POST /api/playlist/play    {pos}    → sauter à la piste
  POST /api/playlist/remove  {pos}    → retirer une piste
  POST /api/playlist/clear / shuffle
  POST /api/playlist/add     {file, play} → ajouter (et jouer) un morceau
  POST /api/playlist/load    {folder, random} → clear + add dossier + play
  POST /api/playlist/folder  {folder} → mémorise le dossier de bibliothèque
  POST /api/playlist/pick             → zenity dossier
  POST /api/playlist/open             → toggle le panneau (bouton du CC)

Contrainte : MPD ne lit QUE music_directory (~/songs). Le « choix du
dossier » permet donc de naviguer dans un dossier SOUS la racine MPD
(albums, playlists…) ; un dossier hors racine renvoie une erreur claire.
"""

import os
import subprocess

from config import RUNTIME_DIR
from mpd import _mpd_read_kv, _mpd_readline, _mpd_send, _mpd_socket

# ── Constantes ─────────────────────────────────────────────────────
# music_directory du mpd.conf (repo) — la racine que MPD sait lire.
MUSIC_DIR = os.path.expanduser("~/songs")
AUDIO_EXTS = (".mp3", ".flac", ".ogg", ".opus", ".m4a", ".aac", ".wav", ".wma")
# Souvenir du dossier de bibliothèque choisi dans le panneau (texte brut,
# fichier séparé de settings.json pour ne pas entrer en course avec le
# panneau Settings qui réécrit settings.json).
FOLDER_STATE = os.path.expanduser("~/.config/settings/playlist_folder")
PLAYLIST_SH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "pl", "pl.sh")
MAX_LIBRARY_FILES = 5000


# ── Primitives MPD ─────────────────────────────────────────────────
def _mpd_cmd(cmd):
    """Envoie une commande MPD simple, retourne le dict clé/valeur."""
    try:
        s, f = _mpd_socket()
        try:
            _mpd_send(f, cmd)
            return _mpd_read_kv(f)
        finally:
            s.close()
    except Exception:
        return {}


def _mpd_ok(cmd):
    """Envoie une commande MPD, retourne True si OK (pas d'ACK)."""
    try:
        s, f = _mpd_socket()
        try:
            _mpd_send(f, cmd)
            _mpd_read_kv(f)
        finally:
            s.close()
        return True
    except Exception:
        return False


def _mpd_playlistinfo():
    """playlistinfo → liste de dicts {pos, file, title, artist, album, duration}."""
    try:
        s, f = _mpd_socket()
        try:
            _mpd_send(f, "playlistinfo")
            tracks, cur = [], None
            while True:
                line = _mpd_readline(f)
                if line == "OK" or line == "":
                    break
                if line.startswith("ACK"):
                    return []
                if line.startswith("file: "):
                    if cur is not None:
                        tracks.append(cur)
                    cur = {"file": line.split(": ", 1)[1], "title": None,
                           "artist": None, "album": None, "duration": 0}
                elif cur is not None and ": " in line:
                    k, v = line.split(": ", 1)
                    if k == "Pos":
                        cur["pos"] = int(v)
                    elif k == "Title":
                        cur["title"] = v
                    elif k == "Artist":
                        cur["artist"] = v
                    elif k == "Album":
                        cur["album"] = v
                    elif k == "Time":
                        try:
                            cur["duration"] = int(v)
                        except ValueError:
                            cur["duration"] = 0
            if cur is not None:
                tracks.append(cur)
            return tracks
        finally:
            s.close()
    except Exception:
        return []


def _title_of(track):
    """Titre affichable : tag sinon basename (fichiers yt-dlp sans tags)."""
    t = track.get("title")
    if t:
        return t
    f = track.get("file") or ""
    return os.path.splitext(os.path.basename(f))[0] if f else "Piste inconnue"


# ── API ────────────────────────────────────────────────────────────
def playlist_status():
    st = _mpd_cmd("status")
    if not st:
        return {"ok": False, "error": "MPD injoignable"}
    # time = "elapsed:total" (ou vide en stop) ; elapsed peut être float.
    elapsed, total = 0, 0
    t = st.get("time", "")
    if ":" in t:
        try:
            elapsed = int(t.split(":")[0])
            total = int(t.split(":")[1])
        except ValueError:
            pass
    try:
        elapsed = float(st.get("elapsed", elapsed))
    except (TypeError, ValueError):
        pass
    try:
        total = float(st.get("duration", total))
    except (TypeError, ValueError):
        pass
    return {
        "ok": True,
        "state": st.get("state", "stop"),
        "random": st.get("random", "0") == "1",
        "repeat": st.get("repeat", "0") == "1",
        "single": st.get("single", "0") == "1",
        "consume": st.get("consume", "0") == "1",
        "volume": int(st.get("volume", "0") or 0),
        "song": int(st.get("song", "-1") or -1),
        "playlistlength": int(st.get("playlistlength", "0") or 0),
        "elapsed": elapsed,
        "duration": total,
    }


def playlist_list():
    st = _mpd_cmd("status")
    cur = int(st.get("song", "-1") or -1)
    tracks = _mpd_playlistinfo()
    out = []
    for t in tracks:
        pos = int(t.get("pos", -1))
        out.append({
            "pos": pos,
            "file": t.get("file"),
            "title": _title_of(t),
            "artist": t.get("artist") or "",
            "album": t.get("album") or "",
            "duration": t.get("duration", 0),
            "current": pos == cur,
        })
    return {"ok": True, "tracks": out}


def playlist_toggle(mode):
    if mode not in ("random", "repeat", "single", "consume"):
        return {"ok": False, "error": "mode inconnu"}
    st = _mpd_cmd("status")
    cur = st.get(mode, "0") == "1"
    new = "1" if not cur else "0"
    ok = _mpd_ok("%s %s" % (mode, new))
    return {"ok": ok, "mode": mode, "value": new == "1"}


def playlist_play(pos):
    try:
        pos = int(pos)
    except (TypeError, ValueError):
        return {"ok": False, "error": "pos invalide"}
    return {"ok": _mpd_ok("play %d" % pos)}


def playlist_playtoggle():
    """Bascule lecture/pause."""
    st = _mpd_cmd("status")
    if not st:
        return {"ok": False, "error": "MPD injoignable"}
    if st.get("state") == "play":
        return {"ok": _mpd_ok("pause 1"), "playing": False}
    return {"ok": _mpd_ok("play"), "playing": True}


def playlist_stop():
    return {"ok": _mpd_ok("stop")}


def playlist_next():
    return {"ok": _mpd_ok("next")}


def playlist_prev():
    return {"ok": _mpd_ok("previous")}


def playlist_seek(sec):
    """Seek absolu dans la piste courante (barre de progression cliquable)."""
    try:
        sec = float(sec)
    except (TypeError, ValueError):
        return {"ok": False, "error": "sec invalide"}
    if sec < 0:
        sec = 0
    return {"ok": _mpd_ok("seekcur %d" % int(sec))}


def playlist_remove(pos):
    try:
        pos = int(pos)
    except (TypeError, ValueError):
        return {"ok": False, "error": "pos invalide"}
    return {"ok": _mpd_ok("delete %d" % pos)}


def playlist_clear():
    return {"ok": _mpd_ok("clear")}


def playlist_shuffle():
    return {"ok": _mpd_ok("shuffle")}


def playlist_add(file_, play=False):
    """Ajoute un morceau/dossier (chemin relatif à MUSIC_DIR). play → le joue."""
    file_ = (file_ or "").strip()
    if not file_:
        return {"ok": False, "error": "fichier vide"}
    if not _mpd_ok('add "%s"' % file_):
        return {"ok": False, "error": "add refusé (hors bibliothèque MPD ?)"}
    if play:
        st = _mpd_cmd("status")
        n = int(st.get("playlistlength", "0") or 0)
        if n > 0:
            _mpd_ok("play %d" % (n - 1))
    return {"ok": True}


# ── Bibliothèque (scan du dossier courant) ─────────────────────────
def music_dir():
    return MUSIC_DIR


def get_folder():
    """Dossier de bibliothèque courant (défaut : racine MPD)."""
    try:
        with open(FOLDER_STATE, encoding="utf-8") as f:
            folder = f.read().strip()
        if folder and os.path.isdir(os.path.expanduser(folder)):
            return os.path.expanduser(folder)
    except OSError:
        pass
    return MUSIC_DIR


def set_folder(folder):
    folder = os.path.expanduser((folder or "").strip())
    if not folder or not os.path.isdir(folder):
        return {"ok": False, "error": "dossier introuvable"}
    try:
        os.makedirs(os.path.dirname(FOLDER_STATE), exist_ok=True)
        with open(FOLDER_STATE, "w", encoding="utf-8") as f:
            f.write(folder + "\n")
    except OSError:
        return {"ok": False, "error": "état illisible"}
    return {"ok": True, "folder": folder}


def _scan_audio(folder, query=None):
    """Fichiers audio du dossier (récursif, cap MAX_LIBRARY_FILES), triés."""
    query = (query or "").strip().lower()
    files = []
    try:
        for root, _dirs, names in os.walk(folder):
            for n in sorted(names):
                if len(files) >= MAX_LIBRARY_FILES:
                    break
                if not n.lower().endswith(AUDIO_EXTS):
                    continue
                if query and query not in n.lower():
                    continue
                files.append(os.path.join(root, n))
            if len(files) >= MAX_LIBRARY_FILES:
                break
    except OSError:
        pass
    return files


def library_list(folder=None, query=None):
    """Fichiers audio du dossier courant (ou choisi) + chemins relatifs MPD."""
    folder = os.path.expanduser((folder or "").strip()) or get_folder()
    in_library = False
    rel_files = []
    try:
        rel = os.path.relpath(folder, MUSIC_DIR)
        in_library = not rel.startswith("..") and rel != ".."
    except ValueError:
        in_library = False
    if os.path.isdir(folder):
        for path in _scan_audio(folder, query):
            rel_files.append({
                "name": os.path.basename(path),
                "path": path,
                "rel": os.path.relpath(path, MUSIC_DIR) if in_library else path,
            })
    return {
        "ok": True,
        "folder": folder,
        "musicDir": MUSIC_DIR,
        "inLibrary": in_library,
        "count": len(rel_files),
        "files": rel_files,
    }


def load_folder(folder=None, random=False):
    """Clear + charge un dossier + play. random → active le mode aléatoire.
    Le dossier doit être sous MUSIC_DIR (MPD ne lit que sa racine)."""
    folder = os.path.expanduser((folder or "").strip()) or get_folder()
    if not os.path.isdir(folder):
        return {"ok": False, "error": "dossier introuvable"}
    try:
        rel = os.path.relpath(folder, MUSIC_DIR)
    except ValueError:
        rel = None
    if rel is None or rel.startswith(".."):
        return {"ok": False,
                "error": "dossier hors bibliothèque MPD (%s)" % MUSIC_DIR}
    if not _mpd_ok("clear"):
        return {"ok": False, "error": "MPD injoignable"}
    if rel == ".":
        # Racine MPD : pas d'`add` de dossier → on ajoute fichier par fichier.
        for path in _scan_audio(folder):
            _mpd_ok('add "%s"' % os.path.relpath(path, MUSIC_DIR))
    else:
        if not _mpd_ok('add "%s"' % rel):
            return {"ok": False, "error": "add refusé"}
    if random:
        _mpd_ok("random 1")
    st = _mpd_cmd("status")
    n = int(st.get("playlistlength", "0") or 0)
    if n > 0:
        _mpd_ok("play 0")
    return {"ok": True, "count": n, "random": random}


def pick_folder():
    """Sélecteur natif zenity (le serveur a DISPLAY/WAYLAND via le manager)."""
    try:
        proc = subprocess.run(
            ["zenity", "--file-selection", "--directory",
             "--title=Choisir un dossier de musique (bibliothèque MPD)"],
            capture_output=True, text=True, timeout=180)
    except (OSError, subprocess.TimeoutExpired):
        return {"ok": False, "error": "zenity indisponible"}
    path = proc.stdout.strip()
    if proc.returncode != 0 or not path:
        return {"ok": False, "error": "annulé"}
    return {"ok": True, "path": path}


# ── Ouverture du panneau depuis le CC ──────────────────────────────
def _hypr_signature():
    """Signature de l'instance Hyprland courante (socket le plus récent).
    Le serveur tourne en service systemd user : pas de signature dans son
    env → pl.sh lancé depuis ici ne verrait pas Hyprland sans ça."""
    d = os.path.join("/run/user", str(os.getuid()), "hypr")
    try:
        sigs = sorted(
            os.listdir(d),
            key=lambda s: os.path.getmtime(os.path.join(d, s)),
            reverse=True)
        return sigs[0] if sigs else None
    except OSError:
        return None


def open_panel():
    """Toggle du panneau playlist (bouton dans la tuile musique du CC)."""
    if not os.path.isfile(PLAYLIST_SH):
        return {"ok": False, "error": "pl.sh introuvable"}
    env = dict(os.environ)
    sig = _hypr_signature()
    if sig:
        env["HYPRLAND_INSTANCE_SIGNATURE"] = sig
    try:
        subprocess.Popen(["bash", PLAYLIST_SH], env=env,
                         start_new_session=True,
                         stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)
        return {"ok": True}
    except OSError:
        return {"ok": False, "error": "impossible de lancer pl.sh"}
