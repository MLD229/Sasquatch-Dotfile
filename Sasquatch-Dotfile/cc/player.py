"""Multi-source « now playing » : MPRIS (playerctl → Brave/Firefox/Spotify…)
+ MPD. Le CC affiche le lecteur qui joue VRAIMENT (YouTube dans le navigateur,
musique locale MPD…), avec l'image/pochette, la position synchronisée et des
contrôles routés vers la bonne source.

Stdlib only — la découverte MPRIS passe par le binaire `playerctl` (déjà
installé ; playerctld est optionnel, `playerctl --all-players` fonctionne sans).
"""

import os
import re
import shutil
import subprocess
import time
import urllib.parse
import urllib.request

from mpd import mpd_status, mpd_simple_command, mpd_toggle

_SEP = "\x1f"
_ART_CACHE_DIR = "/tmp"

# Récence de lecture : quand un lecteur (MPRIS ou MPD) est passé à « Playing ».
# Le CC affiche « le dernier en général » : si YouTube joue en fond et momo
# lance MPD après, MPD gagne (il a démarré plus récemment) — l'ancien code
# donnait priorité fixe à MPRIS Playing, donc le web gagnait toujours.
_playing_since = {"mpris": 0.0, "mpd": 0.0}
_prev_playing = {"mpris": False, "mpd": False}

# playerctl -a metadata --format : une ligne par lecteur, champs séparés par \x1f.
_FIELDS = ("playerName", "status", "title", "artist", "album",
           "mpris:artUrl", "mpris:length", "position")
_FORMAT = _SEP.join("{{%s}}" % f for f in _FIELDS)


def _run_playerctl(args, timeout=2):
    """Exécute playerctl, retourne stdout (str) ou None (absent/échec)."""
    if shutil.which("playerctl") is None:
        return None
    try:
        out = subprocess.run(["playerctl"] + args, capture_output=True,
                             text=True, timeout=timeout)
    except Exception:
        return None
    return out.stdout if out.returncode == 0 else None


def _us_to_sec(v):
    try:
        return round(float(v) / 1e6, 1)
    except (TypeError, ValueError):
        return 0


def _mpris_players():
    """Lecteurs MPRIS actifs (piste non vide), triés Playing > Paused."""
    out = _run_playerctl(["--no-messages", "--all-players", "metadata",
                          "--format", _FORMAT])
    players = []
    if out:
        for line in out.splitlines():
            parts = line.split(_SEP)
            if len(parts) < 8:
                continue
            name, status, title, artist, album, art, length, position = parts[:8]
            if status == "Stopped" or not title:
                continue
            players.append({
                "name": name,
                "status": status,
                "title": title,
                "artist": artist or None,
                "album": album or None,
                "art": art or None,
                "duration": _us_to_sec(length),
                "elapsed": _us_to_sec(position),
            })
    players.sort(key=lambda p: 0 if p["status"] == "Playing" else 1)
    return players


def _mpris_to_status(p):
    return {
        "source": "mpris",
        "player": p["name"],
        "playing": p["status"] == "Playing",
        "paused": p["status"] == "Paused",
        "title": p["title"],
        "artist": p["artist"],
        "album": p["album"],
        "file": None,
        "volume": 0,
        "elapsed": p["elapsed"],
        "duration": p["duration"],
        "art": ("/albumart?url=" + urllib.parse.quote(p["art"])) if p["art"] else None,
    }


def _mpd_to_status(st):
    st = dict(st)
    st["source"] = "mpd"
    st["player"] = "MPD"
    st["art"] = ("/albumart?t=" + urllib.parse.quote(st["file"])) if st.get("file") else None
    return st


def now_playing():
    """Statut unifié : le lecteur qui joue et a démarré le plus récemment.

    Ordre : (1) parmi les lecteurs qui jouent (MPRIS ou MPD), le plus récent
    (2) sinon le lecteur en pause le plus récent (3) sinon rien. Ne renvoie
    JAMAIS une piste « chargée » comme si elle jouait.
    """
    mpris = _mpris_players()
    mpris_active = mpris[0] if mpris else None
    st = mpd_status()
    _track_playing_since(mpris, st)

    mpris_playing = bool(mpris_active and mpris_active["status"] == "Playing")
    mpris_paused = bool(mpris_active and mpris_active["status"] == "Paused")
    mpd_playing = bool(st.get("playing"))
    mpd_paused = bool(st.get("paused") and st.get("title"))

    # Le plus récemment activé parmi les lecteurs qui jouent VRAIMENT.
    cands = []
    if mpris_playing:
        cands.append(("mpris", _playing_since["mpris"], _mpris_to_status(mpris_active)))
    if mpd_playing:
        cands.append(("mpd", _playing_since["mpd"], _mpd_to_status(st)))
    if cands:
        cands.sort(key=lambda c: c[1], reverse=True)
        return cands[0][2]

    # Rien ne joue : le lecteur en pause le plus récent.
    paused = []
    if mpris_paused:
        paused.append(("mpris", _playing_since["mpris"], _mpris_to_status(mpris_active)))
    if mpd_paused:
        paused.append(("mpd", _playing_since["mpd"], _mpd_to_status(st)))
    if paused:
        paused.sort(key=lambda c: c[1], reverse=True)
        return paused[0][2]

    return {"source": "none", "player": None, "playing": False, "paused": False,
            "title": None, "artist": None, "album": None, "file": None,
            "volume": 0, "elapsed": 0, "duration": 0, "art": None}


def _track_playing_since(mpris, st):
    """Met à jour _playing_since quand un lecteur passe à Playing
    (transition, pas à chaque poll — sinon la récence serait « toujours
    maintenant » pour le lecteur qui joue en continu)."""
    global _playing_since, _prev_playing
    now = time.time()
    mpris_playing = any(p["status"] == "Playing" for p in mpris)
    mpd_playing = bool(st.get("playing"))
    if mpris_playing and not _prev_playing["mpris"]:
        _playing_since["mpris"] = now
    if mpd_playing and not _prev_playing["mpd"]:
        _playing_since["mpd"] = now
    _prev_playing = {"mpris": mpris_playing, "mpd": mpd_playing}


def active_source():
    """(source, player_name) — même logique de récence que now_playing()."""
    mpris = _mpris_players()
    st = mpd_status()
    _track_playing_since(mpris, st)
    mpris_playing = [p for p in mpris if p["status"] == "Playing"]
    mpd_playing = bool(st.get("playing"))
    if mpris_playing and mpd_playing:
        if _playing_since["mpd"] > _playing_since["mpris"]:
            return "mpd", None
        return "mpris", mpris_playing[0]["name"]
    if mpris_playing:
        return "mpris", mpris_playing[0]["name"]
    if mpd_playing:
        return "mpd", None
    if mpris:
        return "mpris", mpris[0]["name"]
    return "mpd", None


def _mpris_cmd(name, *args):
    return _run_playerctl(["--player", name] + list(args)) is not None


def toggle():
    src, name = active_source()
    if src == "mpris":
        return _mpris_cmd(name, "play-pause")
    return mpd_toggle()


def next_track():
    src, name = active_source()
    if src == "mpris":
        return _mpris_cmd(name, "next")
    return mpd_simple_command("next")


def prev_track():
    src, name = active_source()
    if src == "mpris":
        return _mpris_cmd(name, "previous")
    return mpd_simple_command("previous")


def stop():
    src, name = active_source()
    if src == "mpris":
        return _mpris_cmd(name, "stop")
    return mpd_simple_command("stop")


def seek(pos):
    src, name = active_source()
    if src == "mpris":
        return _mpris_cmd(name, "position", str(int(pos)))
    return mpd_simple_command("seekcur %d" % int(pos))


# ── Image (artUrl MPRIS) : https:// ou file://, cache disque ──────────────

_HTTP_RE = re.compile(r"^https?://", re.I)


def _art_cache_key(url):
    import hashlib
    digest = hashlib.sha1(url.encode("utf-8", "replace")).hexdigest()[:16]
    return os.path.join(_ART_CACHE_DIR, "sasquatch-mpris-art-%s.img" % digest)


def fetch_art(url):
    """Récupère l'image d'un artUrl MPRIS (https:// ou file://) → bytes/None."""
    if not url:
        return None
    if url.startswith("file://"):
        try:
            path = urllib.parse.urlparse(url).path
            with open(path, "rb") as f:
                data = f.read()
            return data if data else None
        except Exception:
            return None
    if not _HTTP_RE.match(url):
        return None
    path = _art_cache_key(url)
    if os.path.isfile(path) and os.path.getsize(path) > 0:
        try:
            with open(path, "rb") as f:
                return f.read()
        except Exception:
            pass
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        data = urllib.request.urlopen(req, timeout=6).read()
        if data and len(data) > 100:
            with open(path, "wb") as f:
                f.write(data)
            return data
    except Exception:
        pass
    return None
