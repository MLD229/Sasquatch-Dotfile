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
import signal
import subprocess
import time
import urllib.parse
import urllib.request

from mpd import mpd_status, mpd_simple_command, mpd_toggle
from config import RUNTIME_DIR
from web_bridge import web_status, push_command as web_push_command

# Les mpv lancés par _pulse_play (Popen + start_new_session) ne sont jamais
# reaptés → chaque next/prev laissait un ZOMBIE jusqu'au restart du serveur.
# SIGCHLD=IGN → reaping automatique par le noyau.
signal.signal(signal.SIGCHLD, signal.SIG_IGN)

_SEP = "\x1f"
_ART_CACHE_DIR = RUNTIME_DIR

# Récence de lecture : quand un lecteur (MPRIS ou MPD) est passé à « Playing ».
# Le CC affiche « le dernier en général » : si YouTube joue en fond et que
# l'utilisateur lance MPD après, MPD gagne (il a démarré plus récemment) —
# l'ancien code donnait priorité fixe à MPRIS Playing, donc le web gagnait
# toujours.
_playing_since = {"mpd": 0.0, "web": 0.0}
_prev_playing = {"mpd": False, "web": False}
_init_done = False

# Récence MPRIS PAR LECTEUR (nom playerctl) — pas un seul bucket "mpris"
# global. Avec un bucket unique, si un lecteur joue déjà et qu'un DEUXIÈME
# lecteur MPRIS démarre (ex. nouvel onglet YouTube pendant qu'un autre
# tourne/est en pause), "mpris" était déjà True → aucune transition détectée
# → le timestamp ne bougeait pas → le CC restait bloqué sur l'ancien lecteur
# au lieu du dernier vraiment lancé. Ici chaque instance MPRIS (souvent
# "chromium.instanceXXXX" par onglet) a son propre timestamp.
_mpris_since = {}
_mpris_prev_playing = {}
_mpris_init_done = False

# playerctl -a metadata --format : une ligne par lecteur, champs séparés par \x1f.
_FIELDS = ("playerName", "status", "title", "artist", "album",
           "mpris:artUrl", "mpris:length", "position", "xesam:url")
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
    """Lecteurs MPRIS actifs (piste non vide), triés Playing > Paused.

    NE PAS filtrer sur le titre : les fichiers locaux sans tags ID3 (ex.
    mp3 yt-dlp « Titre [id].mp3 ») exposent un titre VIDE mais jouent —
    les filtrer rend le lecteur invisible et le CC reste bloqué sur MPD.
    Le fallback titre vient du nom de fichier dans _mpris_to_status().
    """
    out = _run_playerctl(["--no-messages", "--all-players", "metadata",
                          "--format", _FORMAT])
    players = []
    if out:
        for line in out.splitlines():
            parts = line.split(_SEP)
            if len(parts) < 9:
                continue
            name, status, title, artist, album, art, length, position, url = parts[:9]
            if status == "Stopped":
                continue
            players.append({
                "name": name,
                "status": status,
                "title": title or None,
                "artist": artist or None,
                "album": album or None,
                "art": art or None,
                "url": url or None,
                "duration": _us_to_sec(length),
                "elapsed": _us_to_sec(position),
            })
    _update_mpris_recency(players)
    # Tri : Playing avant Paused, puis (parmi les Playing) le lecteur le plus
    # RÉCEMMENT passé à Playing en premier. Sans le 2e critère, plusieurs
    # lecteurs Playing simultanés restaient dans l'ordre renvoyé par
    # playerctl (pas forcément le plus récent) → le CC affichait le mauvais.
    players.sort(key=lambda p: (0 if p["status"] == "Playing" else 1,
                                -_mpris_since.get(p["name"], 0.0)))
    return players


def _update_mpris_recency(players):
    """Met à jour _mpris_since par lecteur individuel (transition → Playing).

    Comme _track_playing_since, on ignore les transitions du tout premier
    appel (serveur qui démarre avec des lecteurs déjà actifs) pour ne pas
    donner artificiellement le même timestamp "now" à tout le monde.
    """
    global _mpris_init_done
    now = time.time()
    seen = set()
    for p in players:
        name = p["name"]
        seen.add(name)
        playing = p["status"] == "Playing"
        was = _mpris_prev_playing.get(name, False)
        if _mpris_init_done and playing and not was:
            _mpris_since[name] = now
        _mpris_prev_playing[name] = playing
    if not _mpris_init_done:
        _mpris_init_done = True
    # Nettoyage : lecteur fermé (onglet/appli quittée) → oublier son état,
    # sinon la mémoire grossit indéfiniment sur une session longue.
    for name in list(_mpris_prev_playing.keys()):
        if name not in seen:
            _mpris_prev_playing.pop(name, None)
            _mpris_since.pop(name, None)


def _mpris_to_status(p):
    # Fallback titre : fichier local sans tags ID3 → nom de fichier (sans
    # extension). Sans ça, l'UI affiche « Aucune musique en cours » alors
    # que VLC/mpv joue un fichier (mp3 yt-dlp, flac, etc.). La source du
    # nom = xesam:url (l'URL du fichier en lecture) — PAS mpris:artUrl,
    # qui pointe vers le cache d'art du lecteur (ex. ~/.cache/vlc/art/…).
    title = p["title"]
    if not title:
        url = p.get("url")
        if url and url.startswith("file://"):
            try:
                path = urllib.parse.urlparse(url).path
                # xesam:url est URL-encodé (espaces → %20, crochets → %5B…)
                path = urllib.parse.unquote(path)
                title = os.path.splitext(os.path.basename(path))[0]
            except Exception:
                pass
    return {
        "source": "mpris",
        "player": p["name"],
        "playing": p["status"] == "Playing",
        "paused": p["status"] == "Paused",
        "title": title,
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



# ── Fallback PipeWire/PulseAudio : détecter l'audio « brut » (hors MPRIS) ──
_PULSE_SKIP_APPS = {"libcanberra", "speech-dispatcher", "xdg-desktop-portal",
                    "org.freedesktop.portal.Desktop", "pipewire", "pulseaudio",
                    "event sounds"}

def _pulse_streams():
    """Streams audio ACTIFS vus par pactl (sink-inputs Corked: no).

    Filet de sécurité : les apps sans MPRIS (mpv sans plugin, jeux, lecteurs
    exotiques…) sont invisibles pour playerctl. Leur audio, lui, transite par
    PipeWire → pactl les voit avec un nom. Corked: yes = stream en pause/idle
    (piste finie, lecteur qui traîne ouvert) → ignoré.
    """
    if shutil.which("pactl") is None:
        return []
    try:
        out = subprocess.run(["pactl", "list", "sink-inputs"], capture_output=True,
                             text=True, timeout=2).stdout or ""
    except Exception:
        return []
    streams = []
    for block in out.split("Sink Input #")[1:]:
        playing = None
        app = ""
        media = ""
        num = 0
        m = re.match(r"\s*(\d+)", block)
        if m:
            num = int(m.group(1))
        for line in block.splitlines():
            line = line.strip()
            if line.startswith("Corked:"):
                playing = line.split(":", 1)[1].strip().lower() == "no"
            elif line.startswith("application.name"):
                app = line.split("=", 1)[1].strip().strip('"')
            elif line.startswith("media.name"):
                media = line.split("=", 1)[1].strip().strip('"')
        if not playing:
            continue  # en pause / idle → pas d'audio audible
        if app.lower() in _PULSE_SKIP_APPS:
            continue
        # media.name finit souvent par « - mpv » / « - vlc » / « - firefox »
        title = media
        for suffix in (" - " + app, " - firefox", " - vlc", " - mpv"):
            if title.endswith(suffix):
                title = title[: -len(suffix)]
                break
        streams.append({"app": app or "audio", "title": title or media, "num": num})
    # Le numéro de sink-input est MONOTONIQUE (objet PipeWire) : le plus haut
    # = le stream créé le plus récemment → le lecteur « sélectionné » en dernier.
    streams.sort(key=lambda s: s["num"], reverse=True)
    return streams

# Recherche du fichier local (pactl ne donne que le nom) : TOUS les dossiers
# médias connus — la musique ET les vidéos (mp4/mkv…), adaptatif.
_PULSE_SEARCH_DIRS = (os.path.expanduser("~/songs"), os.path.expanduser("~/Music"),
                      os.path.expanduser("~/Téléchargements"),
                      os.path.expanduser("~/Vidéos"), os.path.expanduser("~/Videos"))
# Fallback playlist quand rien de local ne joue → la MUSIQUE seulement.
_PULSE_MUSIC_DIRS = (os.path.expanduser("~/songs"), os.path.expanduser("~/Music"))
_pulse_file_cache = {}


def _resolve_local_file(title):
    """Fichier local correspondant au titre d'un stream pulse (cache par titre).

    pactl ne donne que le NOM de fichier (media.name sans chemin) → on cherche
    dans les dossiers musique connus. Cache dict : la recherche scandir à
    chaque poll serait inutile.
    """
    if title in _pulse_file_cache:
        return _pulse_file_cache[title]
    found = None
    target = (title or "").lower()
    if target:
        for d in _PULSE_SEARCH_DIRS:
            if not os.path.isdir(d):
                continue
            try:
                with os.scandir(d) as it:
                    for e in it:
                        if e.is_file() and e.name.lower() == target:
                            found = e.path
                            break
            except OSError:
                continue
            if found:
                break
    _pulse_file_cache[title] = found
    return found


_PULSE_AUDIO_EXTS = (".mp3", ".flac", ".m4a", ".opus", ".ogg", ".wav", ".aac", ".wma")
_PULSE_VIDEO_EXTS = (".mp4", ".mkv", ".webm", ".avi", ".mov", ".m4v", ".wmv", ".ts", ".flv")
_PULSE_EXTS = _PULSE_AUDIO_EXTS + _PULSE_VIDEO_EXTS


def _pulse_folder_files(directory):
    """Fichiers jouables (audio ET vidéo) du dossier donné, triés par nom.
    → adaptatif : on continue dans le dossier du fichier courant, mp4 inclus."""
    files = []
    if not directory or not os.path.isdir(directory):
        return files
    try:
        with os.scandir(directory) as it:
            for e in it:
                if e.is_file() and e.name.lower().endswith(_PULSE_EXTS):
                    files.append(e.path)
    except OSError:
        return files
    return sorted(files, key=lambda p: os.path.basename(p).lower())


def _pulse_playlist_files():
    """Tous les fichiers audio des dossiers musique, triés (nom, insensible casse)."""
    files = []
    for d in _PULSE_MUSIC_DIRS:
        if not os.path.isdir(d):
            continue
        try:
            with os.scandir(d) as it:
                for e in it:
                    if e.is_file() and e.name.lower().endswith(_PULSE_EXTS):
                        files.append(e.path)
        except OSError:
            continue
    return sorted(files, key=lambda p: os.path.basename(p).lower())


def _pgrep_mpv():
    try:
        out = subprocess.run(["pgrep", "-x", "mpv"], capture_output=True,
                             text=True, timeout=2).stdout or ""
        return [int(x) for x in out.split() if x.strip().isdigit()]
    except Exception:
        return []


def _kill_local_mpv():
    """Tue les mpv dont la cmdline référence un de nos dossiers musique.
    (Précis : ne touche pas un mpv qui joue une vidéo ailleurs.)"""
    killed = 0
    for pid in _pgrep_mpv():
        try:
            with open("/proc/%d/cmdline" % pid, "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
        except OSError:
            continue
        if any(d in cmd for d in _PULSE_SEARCH_DIRS):
            try:
                os.kill(pid, signal.SIGTERM)
                killed += 1
            except OSError:
                pass
    return killed


def _pulse_play(playlist):
    if not playlist:
        return False
    try:
        # start_new_session : le mpv survit au serveur (comme nohup/setsid)
        subprocess.Popen(["mpv"] + playlist, start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except OSError:
        return False


def _pulse_jump(direction):
    """next/prev pour l'audio local (pulse) : playlist mpv depuis la piste
    suivante/précédente. Le wrap est circulaire → à la fin d'une piste, mpv
    enchaîne automatiquement (auto-advance). Ne vole PAS le contrôle d'une
    autre app (vlc, jeu…) : seuls les mpv qui jouent depuis nos dossiers
    musique sont tués."""
    pulse = _pulse_streams()
    app = pulse[0]["app"] if pulse else None
    if app and app.lower() != "mpv":
        return False  # pas notre affaire (vlc, jeu, navigateur sans MPRIS…)
    cur = None
    if pulse:
        cur = _resolve_local_file(pulse[0]["title"])
    if cur:
        # ADAPTATIF : on continue dans le dossier du fichier courant
        # (audio OU vidéo). Si le dossier n'a qu'un fichier → musique.
        files = _pulse_folder_files(os.path.dirname(cur))
        if len(files) < 2:
            files = _pulse_playlist_files()
    else:
        files = _pulse_playlist_files()
    if not files:
        return False
    if cur in files:
        idx = files.index(cur)
    else:
        idx = -1 if direction > 0 else 0  # rien de local → début (next) / fin (prev)
    n = len(files)
    start = (idx + direction) % n
    playlist = files[start:] + files[:start]
    _kill_local_mpv()
    return _pulse_play(playlist)


def now_playing():
    """Statut unifié : le lecteur qui joue et a démarré le plus récemment.

    Ordre : (1) parmi les lecteurs qui jouent (MPRIS ou MPD), le plus récent
    (2) sinon le lecteur en pause le plus récent (3) sinon rien. Ne renvoie
    JAMAIS une piste « chargée » comme si elle jouait.
    """
    mpris = _mpris_players()
    mpris_active = mpris[0] if mpris else None
    st = mpd_status()
    wst = web_status()
    _track_playing_since(mpris, st, wst)

    mpris_playing = bool(mpris_active and mpris_active["status"] == "Playing")
    mpris_paused = bool(mpris_active and mpris_active["status"] == "Paused")
    mpd_playing = bool(st.get("playing"))
    mpd_paused = bool(st.get("paused") and st.get("title"))
    # Le web_bridge (extension Chromium maison) n'est utile que quand le
    # navigateur n'expose PAS MPRIS (sites sans MediaSession API). Brave
    # moderne expose un MPRIS natif complet → si un lecteur MPRIS est actif,
    # on IGNORE la source web pour éviter le doublon (même lecture affichée
    # 2×, « via Brave » qui oscille avec « via YouTube »).
    web_playing = bool(wst and not mpris_active and wst["playing"])
    web_paused = bool(wst and not mpris_active and wst["paused"])

    # Le plus récemment activé parmi les lecteurs qui jouent VRAIMENT.
    cands = []
    if mpris_playing:
        mpris_when = _mpris_since.get(mpris_active["name"], 0.0)
        cands.append(("mpris", mpris_when, _mpris_to_status(mpris_active)))
    if mpd_playing:
        cands.append(("mpd", _playing_since["mpd"], _mpd_to_status(st)))
    if web_playing and wst:
        # La récence du web vient du POST (transition False→True dans le
        # navigateur), pas du poll serveur — sinon au démarrage le web et
        # MPRIS auraient tous les deux 0.0 et le tri stable donnerait mpris.
        wsince = wst.get("playing_since") or 0.0
        cands.append(("web", wsince, wst))
    if cands:
        cands.sort(key=lambda c: c[1], reverse=True)
        return cands[0][2]

    # Filet de sécurité PipeWire : rien en MPRIS/MPD/web, mais un stream est
    # AUDIBLE (mpv sans plugin, jeu, lecteur exotique…) → on l'affiche.
    pulse = _pulse_streams()
    if pulse:
        p = pulse[0]
        local = _resolve_local_file(p["title"])
        art = ("/albumart?local=" + urllib.parse.quote(local)) if local else None
        return {"source": "pulse", "player": p["app"], "playing": True,
                "paused": False, "title": p["title"], "artist": None,
                "album": None, "file": local, "volume": 0, "elapsed": 0,
                "duration": 0, "art": art}

    # Rien ne joue : le lecteur en pause le plus récent.
    paused = []
    if mpris_paused:
        mpris_when = _mpris_since.get(mpris_active["name"], 0.0)
        paused.append(("mpris", mpris_when, _mpris_to_status(mpris_active)))
    if mpd_paused:
        paused.append(("mpd", _playing_since["mpd"], _mpd_to_status(st)))
    if web_paused and wst:
        paused.append(("web", wst.get("playing_since") or 0.0, wst))
    if paused:
        paused.sort(key=lambda c: c[1], reverse=True)
        return paused[0][2]

    return {"source": "none", "player": None, "playing": False, "paused": False,
            "title": None, "artist": None, "album": None, "file": None,
            "volume": 0, "elapsed": 0, "duration": 0, "art": None}


def _track_playing_since(mpris, st, wst=None):
    """Met à jour _playing_since quand un lecteur passe à Playing
    (transition, pas à chaque poll — sinon la récence serait « toujours
    maintenant » pour le lecteur qui joue en continu).

    Au PREMIER appel (serveur qui démarre alors que des sources jouent
    déjà), on initialise _prev_playing SANS marquer de transition :
    sinon toutes les sources actives auraient le même timestamp « now »
    et la première de la liste (mpris) gagnerait toujours, même si c'est
    le web/MPD qui a démarré en dernier.
    """
    global _playing_since, _prev_playing, _init_done
    now = time.time()
    mpd_playing = bool(st.get("playing"))
    web_playing = bool(wst and wst["playing"])

    if not _init_done:
        _prev_playing = {"mpd": mpd_playing, "web": web_playing}
        _init_done = True
        return

    if mpd_playing and not _prev_playing["mpd"]:
        _playing_since["mpd"] = now
    if web_playing and not _prev_playing["web"]:
        _playing_since["web"] = now
    _prev_playing = {"mpd": mpd_playing, "web": web_playing}


def active_source():
    """(source, player_name) — même logique de récence que now_playing()."""
    mpris = _mpris_players()
    st = mpd_status()
    wst = web_status()
    _track_playing_since(mpris, st, wst)
    mpris_playing = [p for p in mpris if p["status"] == "Playing"]
    mpd_playing = bool(st.get("playing"))
    # Idem now_playing() : la source web est ignorée quand un MPRIS est actif
    # (navigateur moderne = MPRIS natif → le web_bridge serait un doublon).
    web_playing = bool(wst and not mpris and wst["playing"])
    web_paused = bool(wst and not mpris and wst["paused"])

    # Tous les lecteurs qui jouent, triés par récence.
    playing = []
    if mpris_playing:
        # mpris_playing[0] est déjà le plus récent (mpris trié par
        # _mpris_players()) — on récupère SON timestamp individuel.
        top = mpris_playing[0]
        playing.append(("mpris", _mpris_since.get(top["name"], 0.0), top["name"]))
    if mpd_playing:
        playing.append(("mpd", _playing_since["mpd"], None))
    if web_playing and wst:
        playing.append(("web", wst.get("playing_since") or 0.0,
                        wst["player"] if wst else None))
    if playing:
        playing.sort(key=lambda c: c[1], reverse=True)
        return playing[0][0], playing[0][2]

    pulse = _pulse_streams()
    if pulse:
        return "pulse", pulse[0]["app"]

    # Rien ne joue : lecteur en pause le plus récent.
    paused = []
    if mpris:
        top = mpris[0]
        paused.append(("mpris", _mpris_since.get(top["name"], 0.0), top["name"]))
    if mpd_playing or (st.get("paused") and st.get("title")):
        paused.append(("mpd", _playing_since["mpd"], None))
    if web_paused and wst:
        paused.append(("web", wst.get("playing_since") or 0.0, wst["player"]))
    if paused:
        paused.sort(key=lambda c: c[1], reverse=True)
        return paused[0][0], paused[0][2]
    return "mpd", None


def _mpris_cmd(name, *args):
    return _run_playerctl(["--player", name] + list(args)) is not None


def toggle():
    src, name = active_source()
    if src == "web":
        web_push_command({"type": "toggle"})
        return True
    if src == "mpris":
        return _mpris_cmd(name, "play-pause")
    if src == "pulse":
        return False  # pas de contrôle sans MPRIS
    return mpd_toggle()


def next_track():
    src, name = active_source()
    if src == "web":
        web_push_command({"type": "next"})
        return True
    if src == "mpris":
        return _mpris_cmd(name, "next")
    if src == "pulse":
        return _pulse_jump(+1)
    return mpd_simple_command("next")


def prev_track():
    src, name = active_source()
    if src == "web":
        web_push_command({"type": "prev"})
        return True
    if src == "mpris":
        return _mpris_cmd(name, "previous")
    if src == "pulse":
        return _pulse_jump(-1)
    return mpd_simple_command("previous")


def stop():
    src, name = active_source()
    if src == "web":
        web_push_command({"type": "stop"})
        return True
    if src == "mpris":
        return _mpris_cmd(name, "stop")
    if src == "pulse":
        return False
    return mpd_simple_command("stop")


def seek(pos):
    src, name = active_source()
    if src == "web":
        web_push_command({"type": "seek", "pos": int(pos)})
        return True
    if src == "mpris":
        return _mpris_cmd(name, "position", str(int(pos)))
    if src == "pulse":
        return False  # pas de seek sans MPRIS (ne pas chercher MPD par erreur)
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
