"""Visualiseur audio — lit la fifo cava (raw 20 bandes, 16-bit LE, ~30fps)
et expose des valeurs normalisées pour /api/viz."""

import os
import struct
import threading
import time

from config import CAVA_FIFO


class Viz:
    """Lit la fifo cava raw (20 bandes, 16-bit LE, ~30fps) et expose des
    valeurs normalisées pour /api/viz."""

    def __init__(self):
        self.lock = threading.Lock()
        self.vals = [0.0] * 20
        self._running = True
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self):
        self._running = False

    def _loop(self):
        while self._running:
            try:
                if not os.path.exists(CAVA_FIFO):
                    time.sleep(1)
                    continue
                fd = os.open(CAVA_FIFO, os.O_RDONLY | os.O_NONBLOCK)
                f = os.fdopen(fd, "rb", buffering=0)
                buf = b""
                while self._running:
                    try:
                        chunk = f.read(4096)
                    except BlockingIOError:
                        time.sleep(0.02)
                        continue
                    if not chunk:
                        # EOF : l'écrivain (cava) a fermé — on purge la trame
                        # partielle pour qu'un redémarrage ne laisse pas un
                        # désalignement permanent.
                        buf = b""
                        time.sleep(0.05)
                        continue
                    buf += chunk
                    while len(buf) >= 40:
                        frame, buf = buf[:40], buf[40:]
                        raw = struct.unpack("<20H", frame)
                        # cava raw 16-bit = 0..65535 (une division par 3000
                        # saturait à 1.0 en permanence → barres fausses).
                        # ^0.7 = bon contraste sans crête systématique.
                        vals = [min(1.0, (v / 65535.0) ** 0.7) for v in raw]
                        with self.lock:
                            self.vals = vals
                f.close()
            except Exception:
                time.sleep(1)

    def get(self):
        with self.lock:
            return list(self.vals)
