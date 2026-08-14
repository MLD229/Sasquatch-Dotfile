"""Gestion du process cava (égaliseur) — fifo + spawn au démarrage du serveur,
arrêt propre à la fermeture. Viz (viz.py) lit la même fifo.

Entrée audio : le monitor PipeWire, capturé par ffmpeg vers une FIFO
(/tmp/sasquatch-audio.fifo), que cava lit. Ça capture TOUT le son qui sort
(MPD, navigateur, lecteurs tiers) — la vieille FIFO MPD ne transportait que
la musique MPD, donc l'égaliseur restait muet sur YouTube etc.
Voir cava.conf.
"""

import os
import shutil
import subprocess
import threading
import time

from config import CAVA_FIFO, SCRIPT_DIR

CAVA_CFG = os.path.join(SCRIPT_DIR, "cava.conf")
AUDIO_FIFO = "/tmp/sasquatch-audio.fifo"

_cava_proc = None
_ffmpeg_proc = None


def _monitor_source():
    """Nom de la source pulse qui capte la sortie audio (monitor du sink).
    Ex : alsa_output.pci-0000_00_1f.3.analog-stereo.monitor"""
    try:
        out = subprocess.run(
            ["pactl", "list", "short", "sources"],
            capture_output=True, text=True, timeout=5,
        ).stdout
        for line in out.splitlines():
            if ".monitor" in line:
                return line.split("\t")[1]
    except Exception:
        pass
    return None


def _start_ffmpeg():
    """ffmpeg : monitor PipeWire → FIFO audio (PCM 44100:16:2 pour cava).
    Ouvre la fifo en écriture (bloquant jusqu'à ce que cava la lise).
    Un ancien ffmpeg orphelin (serveur tué sans /api/close, ou relance du
    watchdog) écrirait dans la même fifo → on le purge AVANT d'en lancer
    un nouveau, sinon doublon (deux écrivains sur la même fifo)."""
    global _ffmpeg_proc
    try:
        mon = _monitor_source()
        if not mon or not shutil.which("ffmpeg"):
            return False
        # Purge des ffmpeg sasquatch-audio restants (pattern bracket : ne
        # jamais matcher sa propre ligne de commande avec pkill -f).
        subprocess.run(["pkill", "-9", "-f", "ffmpeg.*sasquatch-audio"],
                       capture_output=True, timeout=3)
        if not os.path.exists(AUDIO_FIFO):
            os.mkfifo(AUDIO_FIFO)
        _ffmpeg_proc = subprocess.Popen(
            ["ffmpeg", "-y", "-v", "error", "-f", "pulse", "-i", mon,
             "-f", "s16le", "-ar", "44100", "-ac", "2", AUDIO_FIFO],
            start_new_session=True,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return True
    except Exception:
        return False


def _start_cava():
    """Create the fifo and spawn cava so /api/viz has real data.
    Viz._loop already polls for the fifo, so it will start reading as soon
    as the fifo exists. cava is spawned detached so the server never blocks.
    Un ancien cava orphelin (serveur tué sans /api/close) écrirait dans la
    même fifo → frames entrelacées ; on le purge AVANT de lancer le nôtre.
    ffmpeg (monitor → fifo) doit être lancé AVANT cava pour que la fifo
    audio soit alimentée."""
    global _cava_proc
    try:
        # SIGKILL : cava ignore SIGTERM quand il est bloqué sur une fifo.
        subprocess.run(["pkill", "-9", "-f", "cava -p"], capture_output=True, timeout=3)
        if not os.path.exists(CAVA_FIFO):
            os.mkfifo(CAVA_FIFO)
        if _ffmpeg_proc is None or _ffmpeg_proc.poll() is not None:
            _start_ffmpeg()
        _cava_proc = subprocess.Popen(
            ["cava", "-p", CAVA_CFG],
            start_new_session=True,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return True
    except Exception:
        return False


def _stop_cava():
    global _cava_proc, _ffmpeg_proc
    if _ffmpeg_proc is not None:
        try:
            _ffmpeg_proc.terminate()
            try:
                _ffmpeg_proc.wait(timeout=2)
            except Exception:
                _ffmpeg_proc.kill()
        except Exception:
            pass
        _ffmpeg_proc = None
    if _cava_proc is not None:
        try:
            _cava_proc.terminate()
            try:
                _cava_proc.wait(timeout=2)
            except Exception:
                _cava_proc.kill()  # cava résiste parfois au SIGTERM (fifo bloqué)
        except Exception:
            pass
        _cava_proc = None
    # Sécurité : aucun cava de ce panel ne doit survivre (sinon orphelin qui
    # réécrit dans la fifo au prochain démarrage). SIGKILL obligatoire.
    subprocess.run(["pkill", "-9", "-f", "cava -p"], capture_output=True, timeout=3)
    subprocess.run(["pkill", "-9", "-f", "ffmpeg.*sasquatch-audio"], capture_output=True, timeout=3)
    try:
        os.unlink(CAVA_FIFO)
    except Exception:
        pass
    try:
        os.unlink(AUDIO_FIFO)
    except Exception:
        pass


def _cava_watchdog():
    """Respawn ffmpeg/cava s'ils meurent (EOF fifo pendant une pause, crash…).
    Boucle daemon, démarrée par server.py."""
    global _cava_proc, _ffmpeg_proc
    while True:
        time.sleep(5)
        if _ffmpeg_proc is not None and _ffmpeg_proc.poll() is not None:
            _start_ffmpeg()
        if _cava_proc is not None and _cava_proc.poll() is not None:
            _start_cava()
