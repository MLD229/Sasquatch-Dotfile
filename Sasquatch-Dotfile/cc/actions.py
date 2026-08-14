"""Actions métier du CC : capture d'écran, OCR/traduction, recherche image,
reconnaissance musicale (songrec). Chaque action est un subprocess fire-and-forget
sauf le screenshot (synchrone, l'UI se masque le temps de la capture)."""

import json
import os
import re
import shutil
import subprocess
import time
import urllib.parse
import wave

from config import SCRIPT_DIR, RUNTIME_DIR

# FIFO MPD dédiée au CC (mono 44.1k, mpd.conf "CC Capture") — lecture SOLO.
# Par user : déclarée dans mpd.conf audio_output fifo (mpd la crée au boot).
CC_FIFO = os.path.expanduser("~/.local/share/mpd/cc.fifo")
CC_FIFO_FORMAT = (44100, 1)


def do_screenshot(mode):
    path = os.path.expanduser("~/.config/scripts/screenshot.sh")
    try:
        # Synchronous: the UI hides itself until the capture completes, so we
        # must not return before grim/slurp finishes (or is cancelled by the
        # user). Timeout guards against a hung slurp/notification daemon.
        rc = subprocess.run(["bash", path, mode], timeout=120,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
        return rc == 0
    except Exception:
        return False


def _close_cc_window():
    try:
        subprocess.run(["hyprctl", "dispatch", "closewindow", "title:^(Sasquatch CC)$"],
                        timeout=2, capture_output=True)
    except Exception:
        pass


def do_translate():
    """Synchrone : sélection OCR (slurp) → tesseract → traduction.

    L'UI masque le CC (visible=false) AVANT d'appeler ce endpoint et ne le
    remonte qu'à la réponse : le serveur bloque pendant la sélection, puis
    retourne le texte détecté + sa traduction pour affichage dans le panneau.
    """
    from translate import translate as _translate
    try:
        out = subprocess.run(["bash", os.path.join(SCRIPT_DIR, "ocr.sh")],
                             capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "OCR timeout (120 s)"}
    if out.returncode != 0:
        return {"ok": False, "error": "sélection annulée ou capture échouée"}
    text = (out.stdout or "").strip()
    if not text:
        return {"ok": False, "error": "aucun texte détecté dans la sélection"}

    res = _translate(text)
    res["text"] = text  # le texte OCR original, pour l'affichage UI
    return res


def do_imgsearch(q):
    """Recherche image DuckDuckGo. `q` non vide → recherche directe ;
    sinon OCR de la sélection puis recherche du texte détecté."""
    if q:
        url = "https://duckduckgo.com/?q=" + urllib.parse.quote(q) + "&iax=images&ia=images"
        try:
            subprocess.Popen(["xdg-open", url], start_new_session=True,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass
        return {"ok": True, "mode": "text"}
    _close_cc_window()
    try:
        out = subprocess.run(["bash", os.path.join(SCRIPT_DIR, "ocr.sh")],
                             capture_output=True, text=True, timeout=120)
        text = (out.stdout or "").strip()
        if text:
            url = "https://duckduckgo.com/?q=" + urllib.parse.quote(text) + "&iax=images&ia=images"
            subprocess.Popen(["xdg-open", url], start_new_session=True,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
    return {"ok": True, "mode": "image"}


def _monitor_source():
    """Nom de la source PipeWire qui capte ce qui sort des haut-parleurs
    (le micro n'entend pas la musique — c'était la cause du 'non reconnu')."""
    try:
        out = subprocess.run(["pactl", "list", "short", "sources"],
                             capture_output=True, text=True, timeout=3).stdout
        for line in out.splitlines():
            parts = line.split("\t")
            if len(parts) > 1 and ".monitor" in parts[1]:
                return parts[1]
    except Exception:
        pass
    return None


def _record_snippet(wav, seconds):
    """Enregistre `seconds` s de la sortie audio. Priorité : ffmpeg (durée
    exacte -t, self-terminating) → pw-record → arecord (micro, dernier
    recours)."""
    mon = _monitor_source()

    if mon and shutil.which("ffmpeg"):
        try:
            rc = subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "pulse", "-i", mon,
                                 "-t", str(seconds), "-ac", "1", "-ar", "44100", wav],
                                timeout=seconds + 8, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL).returncode
            if rc == 0 and os.path.getsize(wav) > 44:
                return True
        except Exception:
            pass

    if mon and shutil.which("pw-record"):
        try:
            p = subprocess.Popen(["pw-record", "--target", mon, "--rate", "44100",
                                  "--channels", "1", "--format", "s16", wav],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                p.wait(timeout=seconds + 1)
            except subprocess.TimeoutExpired:
                p.terminate()
                try:
                    p.wait(timeout=3)
                except Exception:
                    p.kill()
            if os.path.getsize(wav) > 44:
                return True
        except Exception:
            pass

    try:
        subprocess.run(["arecord", "-D", "default", "-f", "cd", "-t", "wav",
                        "-d", str(seconds), "-q", wav], timeout=seconds + 5,
                       capture_output=True)
    except Exception:
        return False
    return os.path.getsize(wav) > 44


RECORD_SECONDS = 8
RECORD_LONG_SECONDS = 15  # retry : un extrait faible/coupé a besoin de plus de matière


def _recognize(wav):
    """songrec recognize (fichier en POSITIONNEL, `-j` = JSON) → (title, artist)
    ou None. L'ancien `-f` faisait échouer songrec (« unexpected argument '-f' »)
    → 'non reconnu' à chaque fois, même avec un bon enregistrement."""
    try:
        out = subprocess.run(["songrec", "recognize", "-j", wav], capture_output=True,
                             text=True, timeout=25)
    except Exception:
        return None
    text = out.stdout.strip()
    title, artist = None, None
    try:
        data = json.loads(text)
        track = data.get("track", data)
        title = track.get("title") or track.get("Title")
        artist = track.get("subtitle") or track.get("artist") or track.get("Artist")
    except Exception:
        m = re.search(r"Title:\s*(.+)", text)
        if m:
            title = m.group(1).strip()
        m = re.search(r"Artist:\s*(.+)", text)
        if m:
            artist = m.group(1).strip()
        if not title and " - " in text:
            parts = text.split(" - ", 1)
            title, artist = parts[0].strip(), parts[1].strip()
    return (title, artist) if title else None


def _wav_has_sound(path, threshold=50):
    """Vrai si le WAV contient un signal audible (RMS ≥ seuil). Évite de
    faire tourner songrec sur du silence (rien ne joue → réponse rapide)."""
    try:
        with wave.open(path, "rb") as w:
            data = w.readframes(w.getnframes())
        return _rms(data) >= threshold
    except Exception:
        return False


def _rms(samples_bytes):
    """RMS d'un buffer PCM s16le — remplace audioop (supprimé en Python 3.13+,
    l'ancien import silencieux rendait le check de silence inopérant)."""
    import array
    try:
        a = array.array("h")
        a.frombytes(samples_bytes)
    except Exception:
        return 0
    n = len(a)
    if n == 0:
        return 0
    s = 0
    for v in a:
        s += v * v
    return int((s // n) ** 0.5)


def _mpd_volume_guard():
    """Force MPD volume 100 % pendant la capture et renvoie une fonction de
    restauration. La fifo transporte le signal APRÈS le volume logiciel : à
    0 % la fifo ne contient que des zéros (RMS 0) → songrec ne reconnaît rien,
    même avec MPD en train de jouer (cause n°2 du 'non reconnu')."""
    try:
        from mpd import mpd_status, mpd_simple_command
        vol = mpd_status().get("volume")
    except Exception:
        return None
    if vol is None or vol >= 50:
        return None
    try:
        mpd_simple_command("setvol 100")
    except Exception:
        return None
    return lambda: mpd_simple_command("setvol %d" % vol)


def _record_from_fifo(wav, seconds):
    """Lit `seconds` s de PCM depuis la FIFO MPD du CC (bloquant non-bloquant :
    pas de writer (MPD en pause) → abandon rapide → fallback monitor)."""
    rate, channels = CC_FIFO_FORMAT
    if not os.path.exists(CC_FIFO):
        return False
    needed = rate * seconds
    samples = bytearray()
    try:
        # os.read brut (PAS os.fdopen) : sur une fifo O_NONBLOCK, le BufferedReader
        # de Python convertit EAGAIN en b'' (EOF) → abandon prématuré en 2 s.
        # os.read lève correctement BlockingIOError quand le writer n'a rien écrit.
        fd = os.open(CC_FIFO, os.O_RDONLY | os.O_NONBLOCK)
        try:
            start = time.time()
            while len(samples) < needed * 2:
                try:
                    chunk = os.read(fd, 8192)
                except BlockingIOError:
                    # Si AUCUNE donnée en 2 s (MPD en pause garde le writer
                    # ouvert → EAGAIN, pas EOF) : la fifo ne produira rien,
                    # inutile d'attendre les 11 s du timeout complet.
                    if time.time() - start > (2 if not samples else seconds + 3):
                        break
                    time.sleep(0.05)
                    continue
                if not chunk:
                    # EOF : writer fermé (MPD pause/stop) — le writer peut
                    # rouvrir (reprise), on patiente un peu puis on abandonne.
                    if time.time() - start > 2:
                        break
                    time.sleep(0.05)
                    continue
                samples += chunk
        finally:
            os.close(fd)
    except Exception:
        return False
    if len(samples) < rate * 2:  # moins d'1 s capté → inutile
        return False
    # Rejet si silencieux (MPD volume 0 % ou pause → fifo de zéros)
    if _rms(bytes(samples[:needed * 2])) < 50:
        return False
    try:
        w = wave.open(wav, "wb")
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(samples[:needed * 2]))
        w.close()
        return True
    except Exception:
        return False


def do_finder():
    # Check songrec FIRST: without it, recording 8s just to fail is wasted.
    if shutil.which("songrec") is None:
        return {"ok": False, "recognized": False, "error": "songrec requis (pacman -S songrec)"}
    wav = os.path.join(RUNTIME_DIR, "sasquatch-finder-%d.wav" % os.getpid())

    def _result(title, artist, source="shazam"):
        return {"ok": True, "recognized": True, "title": title,
                "artist": artist, "source": source}

    try:
        # 1) Monitor PipeWire : capte TOUTE la sortie (MPD, navigateur,
        #    YouTube…) — la seule source qui reconnaît un son hors MPD.
        if _record_snippet(wav, RECORD_SECONDS) and _wav_has_sound(wav):
            result = _recognize(wav)
            if result is not None:
                return _result(*result)
            # Retry LONG : un extrait faible/coupé échoue en 8 s ; on
            # ré-enregistre plus longtemps (plus de matière pour l'empreinte).
            if _record_snippet(wav, RECORD_LONG_SECONDS) and _wav_has_sound(wav):
                result = _recognize(wav)
                if result is not None:
                    return _result(*result)

        # 2) FIFO MPD en secours — SEULEMENT si MPD joue réellement. L'ancien
        #    fallback « piste en pause » renvoyait le morceau chargé alors que
        #    RIEN ne jouait → résultat mensonger (« FLUXO » à chaque clic).
        try:
            from mpd import mpd_status
            playing = mpd_status().get("playing")
        except Exception:
            playing = False
        if playing:
            guard = _mpd_volume_guard()  # fifo = zéros si volume MPD 0 %
            try:
                if _record_from_fifo(wav, RECORD_SECONDS) and _wav_has_sound(wav):
                    result = _recognize(wav)
                    if result is not None:
                        return _result(*result)
                if _record_from_fifo(wav, RECORD_LONG_SECONDS) and _wav_has_sound(wav):
                    result = _recognize(wav)
                    if result is not None:
                        return _result(*result)
            finally:
                if guard:
                    guard()

        # Rien d'audible → réponse honnête, PAS la piste chargée en pause.
        return {"ok": True, "recognized": False,
                "error": "non reconnu (rien d'audible)"}
    finally:
        try:
            os.remove(wav)
        except Exception:
            pass
