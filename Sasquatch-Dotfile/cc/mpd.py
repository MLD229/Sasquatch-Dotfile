"""Client MPD minimal (stdlib socket) — status, commandes simples, albumart,
notification au changement de piste (titre/artiste/album + pochette)."""

import hashlib
import os
import re
import socket
import subprocess
import urllib.request

from config import MPD_HOST, MPD_PORT, MPD_SOCKET, ALBUMART_TMP, RUNTIME_DIR

# ── Pochettes YouTube (fichiers yt-dlp "Titre [VIDEOID].mp3") ─────────────
# yt-dlp écrit "Titre [id].mp3" ou "Titre - id.mp3" ; la pochette n'est pas
# embarquée → on la récupère depuis i.ytimg.com (cache disque, 1 dl max).
_YT_BRACKET_RE = re.compile(r"\[([A-Za-z0-9_-]{11})\]", re.I)
_YT_TAIL_RE = re.compile(r"(?:^|[\s\[\]\(\)\-_])([A-Za-z0-9_-]{11})\.(?:mp3|m4a|opus|ogg|flac|wav)$", re.I)
_YT_CACHE_DIR = RUNTIME_DIR


_LOCAL_ART_CACHE = RUNTIME_DIR


def local_albumart(file_):
    """Pochette EMBARQUÉE d'un fichier local (ffmpeg, cache disque).

    yt-dlp embarque souvent une PNG 1280×720 dans les mp3 → ffmpeg l'extrait.
    Retourne bytes (jpeg/png) ou None. Fallback appelant : yt_thumbnail.
    """
    if not file_ or not os.path.isfile(file_):
        return None
    key = hashlib.sha1(file_.encode("utf-8", "replace")).hexdigest()[:12]
    cache = os.path.join(_LOCAL_ART_CACHE, "sasquatch-art-%s.img" % key)
    if os.path.isfile(cache) and os.path.getsize(cache) > 0:
        try:
            with open(cache, "rb") as f:
                return f.read()
        except Exception:
            pass
    try:
        out = subprocess.run(
            ["ffmpeg", "-y", "-i", file_, "-map", "0:v:0", "-c:v", "copy",
             "-f", "image2", cache],
            capture_output=True, timeout=5)
    except Exception:
        return None
    if out.returncode != 0 or not os.path.isfile(cache) or os.path.getsize(cache) == 0:
        return None
    try:
        with open(cache, "rb") as f:
            return f.read()
    except Exception:
        return None


def video_id_from_file(file_):
    if not file_:
        return None
    m = _YT_BRACKET_RE.search(file_)
    if m:
        return m.group(1)
    m = _YT_TAIL_RE.search(file_)
    return m.group(1) if m else None


def yt_thumbnail(video_id):
    """Pochette YouTube (mqdefault 320×180) → bytes, cache disque."""
    if not video_id:
        return None
    path = os.path.join(_YT_CACHE_DIR, "sasquatch-yt-%s.jpg" % video_id)
    if os.path.isfile(path) and os.path.getsize(path) > 0:
        try:
            with open(path, "rb") as f:
                return f.read()
        except Exception:
            pass
    for res in ("mqdefault.jpg", "hqdefault.jpg"):
        url = "https://i.ytimg.com/vi/%s/%s" % (video_id, res)
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            data = urllib.request.urlopen(req, timeout=6).read()
            if data and len(data) > 100:
                with open(path, "wb") as f:
                    f.write(data)
                return data
        except Exception:
            continue
    return None


def _mpd_socket():
    """Connexion MPD : socket unix PAR USER (mpd.conf bind_to_address),
    fallback TCP 127.0.0.1:6600 pour les anciennes configs / tests."""
    if os.path.exists(MPD_SOCKET):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(2)
        s.connect(MPD_SOCKET)
    else:
        s = socket.create_connection((MPD_HOST, MPD_PORT), timeout=2)
    f = s.makefile("rwb", buffering=0)
    line = f.readline()
    if not line.startswith(b"OK MPD"):
        raise ConnectionError("bad MPD welcome")
    return s, f


def _mpd_readline(f):
    return f.readline().decode("utf-8", "replace").rstrip("\n")


def _mpd_send(f, cmd):
    f.write((cmd + "\n").encode("utf-8"))


def _mpd_read_kv(f):
    out = {}
    while True:
        line = _mpd_readline(f)
        if line == "OK" or line == "":
            break
        if line.startswith("ACK"):
            raise RuntimeError(line)
        if ": " in line:
            k, v = line.split(": ", 1)
            out[k] = v
    return out


def mpd_status():
    try:
        s, f = _mpd_socket()
        try:
            _mpd_send(f, "status")
            status = _mpd_read_kv(f)
            _mpd_send(f, "currentsong")
            song = _mpd_read_kv(f)
        finally:
            s.close()
    except Exception:
        return {"playing": False, "paused": False, "title": None, "artist": None,
                "album": None, "file": None, "volume": 0, "elapsed": 0, "duration": 0}

    state = status.get("state", "stop")
    file_ = song.get("file")
    # Fallback titre : les fichiers yt-dlp n'ont souvent AUCUN tag Title/Artist.
    # Sans ça, l'UI affiche "Aucune musique en cours" alors que ça joue.
    title = song.get("Title")
    if not title and file_:
        title = os.path.splitext(os.path.basename(file_))[0]
    return {
        "playing": state == "play",
        "paused": state == "pause",
        "title": title,
        "artist": song.get("Artist"),
        "album": song.get("Album"),
        "file": file_,
        "volume": int(status.get("volume", "0") or 0),
        "elapsed": float(status.get("elapsed", "0") or 0),
        "duration": float(status.get("duration", song.get("Time", "0")) or 0),
    }


def mpd_simple_command(cmd):
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


def mpd_toggle():
    st = mpd_status()
    if st["playing"]:
        return mpd_simple_command("pause 1")
    # Le CC pilote le volume SYSTÈME (wpctl) : le volume logiciel MPD traîne
    # souvent à 0 % (mixer software) → lecture parfaitement muette. On le
    # remet à 100 % au démarrage pour que le son suive le vrai slider.
    if st.get("volume", 0) == 0:
        mpd_simple_command("setvol 100")
    return mpd_simple_command("play" if not st["paused"] else "pause 0")


def mpd_albumart(uri):
    if not uri:
        return None
    try:
        s, f = _mpd_socket()
    except Exception:
        return None
    try:
        offset = 0
        data = b""
        total = None
        while True:
            _mpd_send(f, 'albumart "%s" %d' % (uri, offset))
            size = None
            binsize = None
            while True:
                line = _mpd_readline(f)
                if line.startswith("ACK"):
                    return None
                if line.startswith("size: "):
                    size = int(line.split(": ", 1)[1])
                    total = size
                elif line.startswith("binary: "):
                    binsize = int(line.split(": ", 1)[1])
                    break
                elif line == "OK" or line == "":
                    break
            if binsize is None or binsize <= 0:
                break
            chunk = f.read(binsize)
            data += chunk
            f.read(1)          # trailing newline after binary payload
            _mpd_readline(f)   # OK
            offset += binsize
            if total is not None and offset >= total:
                break
        return data if data else None
    except Exception:
        return None
    finally:
        s.close()


# ── Notification changement de piste ──────────────────────────────

def _write_albumart_tmp(uri):
    """Écrit la pochette de la piste courante dans ALBUMART_TMP (pour
    notify-send -i). Retourne le chemin, ou None si pas de pochette."""
    try:
        data = mpd_albumart(uri)
        if not data:
            data = yt_thumbnail(video_id_from_file(uri))  # fichiers yt-dlp
        if not data:
            return None
        with open(ALBUMART_TMP, "wb") as f:
            f.write(data)
        return ALBUMART_TMP
    except Exception:
        return None


_last_track = {"file": None}


def notify_track_change(st):
    """Notifie au changement de piste (une seule fois par piste) : titre,
    artiste — album, avec la pochette. Appelé par /api/music/status (poll 1 s),
    donc la notification part ≤1 s après le changement."""
    f = st.get("file")
    if not f or f == _last_track["file"]:
        return
    _last_track["file"] = f

    title = st.get("title") or "Piste inconnue"
    artist = st.get("artist") or ""
    album = st.get("album") or ""
    subtitle = " — ".join(x for x in (artist, album) if x)

    img = _write_albumart_tmp(f)
    cmd = ["notify-send", "-a", "MPD", "-t", "4000"]
    if img:
        cmd += ["-i", img]
    cmd += [title, subtitle]
    try:
        subprocess.run(cmd, timeout=3,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
