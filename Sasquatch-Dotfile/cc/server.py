#!/usr/bin/env python3
"""Sasquatch Control Center - backend HTTP server (stdlib only)."""

import json
import os
import re
import signal
import shutil
import socket
import struct
import subprocess
import sys
import threading
import time
import urllib.parse
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = 8765
HIST_LEN = 90
CAVA_FIFO = "/tmp/sasquatch-cava.fifo"
MPD_HOST = "127.0.0.1"
MPD_PORT = 6600
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


# ==================== METRICS ====================

class Metrics:
    """Samples system metrics every second and keeps a rolling history."""

    def __init__(self):
        self.lock = threading.Lock()
        self.hostname = socket.gethostname()
        self.history = {k: deque(maxlen=HIST_LEN) for k in
                         ("cpu", "ram", "gpu", "vram", "cpu_temp", "gpu_temp", "up", "down")}
        self.latest = {}
        self._prev_cpu_total = None
        self._prev_cpu_idle = None
        self._prev_core = {}
        self._prev_net = {}
        self._prev_net_ts = None
        self._hypr_cache = {"ts": 0, "refresh": 60}
        self._running = True
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def _loop(self):
        while self._running:
            try:
                self._sample()
            except Exception:
                pass
            time.sleep(1)

    def stop(self):
        self._running = False

    def _read_cpu(self):
        with open("/proc/stat") as f:
            lines = f.readlines()
        total_line = lines[0].split()
        vals = [int(x) for x in total_line[1:]]
        idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
        total = sum(vals)
        usage = 0.0
        if self._prev_cpu_total is not None:
            dt = total - self._prev_cpu_total
            di = idle - self._prev_cpu_idle
            if dt > 0:
                usage = max(0.0, min(100.0, (dt - di) / dt * 100.0))
        self._prev_cpu_total = total
        self._prev_cpu_idle = idle

        cores = []
        for line in lines[1:]:
            if not line.startswith("cpu"):
                break
            parts = line.split()
            name = parts[0]
            cvals = [int(x) for x in parts[1:]]
            cidle = cvals[3] + (cvals[4] if len(cvals) > 4 else 0)
            ctotal = sum(cvals)
            cusage = 0.0
            prev = self._prev_core.get(name)
            if prev is not None:
                dt = ctotal - prev[0]
                di = cidle - prev[1]
                if dt > 0:
                    cusage = max(0.0, min(100.0, (dt - di) / dt * 100.0))
            self._prev_core[name] = (ctotal, cidle)
            cores.append(round(cusage, 1))
        return round(usage, 1), cores

    def _read_ram(self):
        info = {}
        with open("/proc/meminfo") as f:
            for line in f:
                k, _, v = line.partition(":")
                info[k.strip()] = int(v.strip().split()[0])
        total = info.get("MemTotal", 0)
        avail = info.get("MemAvailable", total)
        used = max(0, total - avail)
        pct = round(used / total * 100, 1) if total else 0.0
        return {"used": used // 1024, "total": total // 1024, "pct": pct}

    def _read_gpu(self):
        try:
            out = subprocess.run(
                ["nvidia-smi",
                 "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu",
                 "--format=csv,noheader,nounits"],
                capture_output=True, text=True, timeout=2,
            )
            if out.returncode != 0 or not out.stdout.strip():
                return None
            parts = [p.strip() for p in out.stdout.strip().splitlines()[0].split(",")]
            util, mem_used, mem_total, temp = (float(parts[0]), float(parts[1]),
                                                float(parts[2]), float(parts[3]))
            return {"util": util, "vram_used": mem_used, "vram_total": mem_total, "temp": temp}
        except Exception:
            return None

    def _read_cpu_temp(self):
        names = ("coretemp", "k10temp", "zenpower", "x86_pkg_temp")
        try:
            base = "/sys/class/hwmon"
            for hw in os.listdir(base):
                name_path = os.path.join(base, hw, "name")
                if not os.path.isfile(name_path):
                    continue
                with open(name_path) as f:
                    name = f.read().strip()
                if name in names:
                    for i in range(1, 8):
                        tpath = os.path.join(base, hw, f"temp{i}_input")
                        if os.path.isfile(tpath):
                            with open(tpath) as f:
                                return round(int(f.read().strip()) / 1000, 1)
        except Exception:
            pass
        try:
            base = "/sys/class/thermal"
            for zone in os.listdir(base):
                if not zone.startswith("thermal_zone"):
                    continue
                tpath = os.path.join(base, zone, "type")
                if not os.path.isfile(tpath):
                    continue
                with open(tpath) as f:
                    ztype = f.read().strip().lower()
                if "pkg" in ztype or "cpu" in ztype:
                    with open(os.path.join(base, zone, "temp")) as f:
                        return round(int(f.read().strip()) / 1000, 1)
        except Exception:
            pass
        return None

    def _read_net(self):
        try:
            with open("/proc/net/dev") as f:
                lines = f.readlines()[2:]
        except Exception:
            return {"up": 0.0, "down": 0.0, "iface": None}
        now = time.time()
        readings = {}
        for line in lines:
            iface, _, rest = line.partition(":")
            iface = iface.strip()
            if iface == "lo":
                continue
            fields = rest.split()
            if len(fields) < 16:
                continue
            rx = int(fields[0])
            tx = int(fields[8])
            readings[iface] = (rx, tx)
        best_iface, best_up, best_down, best_score = None, 0.0, 0.0, -1.0
        dt = now - self._prev_net_ts if self._prev_net_ts else 1.0
        dt = dt if dt > 0 else 1.0
        for iface, (rx, tx) in readings.items():
            prev = self._prev_net.get(iface)
            if prev:
                drx = max(0, rx - prev[0])
                dtx = max(0, tx - prev[1])
                down = drx / dt / 1024
                up = dtx / dt / 1024
                score = up + down
                if score > best_score:
                    best_score = score
                    best_iface, best_up, best_down = iface, up, down
        self._prev_net = readings
        self._prev_net_ts = now
        return {"up": round(best_up, 1), "down": round(best_down, 1), "iface": best_iface}

    def _read_refresh(self):
        now = time.time()
        if now - self._hypr_cache["ts"] < 60:
            return self._hypr_cache["refresh"]
        try:
            out = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True,
                                  text=True, timeout=2)
            data = json.loads(out.stdout)
            rates = [m.get("refreshRate", 60) for m in data]
            refresh = round(max(rates)) if rates else 60
        except Exception:
            refresh = 60
        self._hypr_cache = {"ts": now, "refresh": refresh}
        return refresh

    def _sample(self):
        cpu, cores = self._read_cpu()
        ram = self._read_ram()
        gpu = self._read_gpu()
        cpu_temp = self._read_cpu_temp()
        gpu_temp = gpu["temp"] if gpu else None
        net = self._read_net()
        try:
            with open("/proc/uptime") as f:
                uptime = float(f.read().split()[0])
        except Exception:
            uptime = 0.0
        try:
            load = list(os.getloadavg())
        except Exception:
            load = [0.0, 0.0, 0.0]
        refresh = self._read_refresh()

        with self.lock:
            self.history["cpu"].append(cpu)
            self.history["ram"].append(ram["pct"])
            self.history["gpu"].append(gpu["util"] if gpu else 0.0)
            self.history["vram"].append(
                round(gpu["vram_used"] / gpu["vram_total"] * 100, 1) if gpu else 0.0)
            self.history["cpu_temp"].append(cpu_temp or 0.0)
            self.history["gpu_temp"].append(gpu_temp or 0.0)
            self.history["up"].append(net["up"])
            self.history["down"].append(net["down"])
            self.latest = {
                "ts": time.time(),
                "hostname": self.hostname,
                "cpu": cpu,
                "cores": cores,
                "load": [round(x, 2) for x in load],
                "ram": ram,
                "gpu": gpu,
                "cpu_temp": cpu_temp,
                "gpu_temp": gpu_temp,
                "net": net,
                "uptime": round(uptime),
                "refresh": refresh,
            }

    def get_stats(self):
        with self.lock:
            data = dict(self.latest)
            data["history"] = {k: list(v) for k, v in self.history.items()}
        return data


# ==================== VIZ (cava fifo) ====================

class Viz:
    """Reads a 20-band cava raw fifo (16-bit LE, ~30fps) and exposes normalized values."""

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
                        # EOF: writer (cava) closed — drop any partial frame so a
                        # restart cannot leave us permanently misaligned.
                        buf = b""
                        time.sleep(0.05)
                        continue
                    buf += chunk
                    while len(buf) >= 40:
                        frame, buf = buf[:40], buf[40:]
                        raw = struct.unpack("<20H", frame)
                        vals = [min(1.0, (v / 3000.0) ** 0.6) for v in raw]
                        with self.lock:
                            self.vals = vals
                f.close()
            except Exception:
                time.sleep(1)

    def get(self):
        with self.lock:
            return list(self.vals)


# ==================== MPD ====================

def _mpd_socket():
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
    return {
        "playing": state == "play",
        "paused": state == "pause",
        "title": song.get("Title"),
        "artist": song.get("Artist"),
        "album": song.get("Album"),
        "file": song.get("file"),
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


# ==================== ACTIONS ====================

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
    _close_cc_window()
    try:
        subprocess.Popen(["bash", os.path.join(SCRIPT_DIR, "ocr.sh"), "translate"],
                          start_new_session=True, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL)
    except Exception:
        pass


def do_imgsearch(q):
    if q:
        url = "https://duckduckgo.com/?q=" + urllib.parse.quote(q) + "&iax=images&ia=images"
        try:
            subprocess.Popen(["xdg-open", url], start_new_session=True,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass
        return "text"
    _close_cc_window()
    try:
        subprocess.Popen(["bash", os.path.join(SCRIPT_DIR, "ocr.sh"), "imgsearch"],
                          start_new_session=True, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL)
    except Exception:
        pass
    return "image"


def do_finder():
    # Check songrec FIRST: without it, recording 6s just to fail is wasted.
    if shutil.which("songrec") is None:
        return {"ok": False, "recognized": False, "error": "songrec requis (pacman -S songrec)"}
    wav = "/tmp/sasquatch-finder-%d.wav" % os.getpid()
    try:
        subprocess.run(["arecord", "-D", "default", "-f", "cd", "-t", "wav", "-d", "6", "-q", wav],
                        timeout=10, capture_output=True)
    except Exception as e:
        return {"ok": False, "recognized": False, "error": "arecord: %s" % e}
    # A valid WAV is at least the 44-byte RIFF header; anything less means the
    # mic produced no audio (muted/broken device) — fail early with a clear message.
    try:
        if os.path.getsize(wav) <= 44:
            return {"ok": False, "recognized": False, "error": "micro: aucun son capté"}
    except OSError:
        return {"ok": False, "recognized": False, "error": "arecord: fichier absent"}
    try:
        out = subprocess.run(["songrec", "recognize", "-f", wav], capture_output=True,
                              text=True, timeout=15)
    except Exception as e:
        return {"ok": False, "recognized": False, "error": str(e)}
    finally:
        try:
            os.remove(wav)
        except Exception:
            pass

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

    if title:
        return {"ok": True, "recognized": True, "title": title, "artist": artist}
    return {"ok": True, "recognized": False, "error": "non reconnu"}


# ==================== HTTP ====================

metrics = Metrics()
viz = Viz()


def _safe_int(v, default=0):
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


def _not_found(self):
    self.send_response(404)
    self.send_header("Content-Type", "text/plain")
    self.send_header("Content-Length", "0")
    self.end_headers()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body_json(self):
        length = int(self.headers.get("Content-Length", 0) or 0)
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        try:
            return json.loads(raw.decode("utf-8"))
        except Exception:
            return {}

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/":
            body = (b"<html><head><title>SasquatchCC</title></head>"
                     b"<body><h1>SasquatchCC</h1><p>Serveur actif.</p></body></html>")
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if path == "/api/stats":
            self._json(metrics.get_stats())
            return

        if path == "/api/viz":
            vals = viz.get()
            self._json({"vals": vals, "bars": len(vals)})
            return

        if path == "/api/music/status":
            self._json(mpd_status())
            return

        if path == "/albumart":
            st = mpd_status()
            data = mpd_albumart(st.get("file"))
            if not data:
                _not_found(self)
                return
            ctype = "image/jpeg" if data[:3] == b"\xff\xd8\xff" else "image/png"
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return

        _not_found(self)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        body = self._body_json()

        if path == "/api/music/toggle":
            self._json({"ok": mpd_toggle()})
            return
        if path == "/api/music/next":
            self._json({"ok": mpd_simple_command("next")})
            return
        if path == "/api/music/prev":
            self._json({"ok": mpd_simple_command("previous")})
            return
        if path == "/api/music/volume":
            v = max(0, min(100, _safe_int(body.get("v", 0))))
            self._json({"ok": mpd_simple_command("setvol %d" % v)})
            return
        if path == "/api/music/seek":
            pos = _safe_int(body.get("pos", 0))
            self._json({"ok": mpd_simple_command("seekcur %d" % pos)})
            return
        if path == "/api/music/finder":
            self._json(do_finder())
            return
        if path == "/api/screenshot":
            qs = urllib.parse.parse_qs(parsed.query)
            mode = qs.get("mode", ["area"])[0]
            if mode not in ("area", "full", "window"):
                mode = "area"
            self._json({"ok": do_screenshot(mode)})
            return
        if path == "/api/translate":
            do_translate()
            self._json({"ok": True, "mode": "translate"})
            return
        if path == "/api/imgsearch":
            q = (body.get("q") or "").strip()
            mode = do_imgsearch(q if q else None)
            self._json({"ok": True, "mode": mode})
            return
        if path == "/api/close":
            self._json({"ok": True})
            metrics.stop()
            viz.stop()
            _stop_cava()

            def _shutdown():
                time.sleep(0.3)
                os._exit(0)

            threading.Thread(target=_shutdown, daemon=True).start()
            return

        _not_found(self)


def _handle_sig(signum, frame):
    metrics.stop()
    viz.stop()
    _stop_cava()
    os._exit(0)


# ==================== CAVA (equalizer backend) ====================

_cava_proc = None
CAVA_CFG = os.path.join(SCRIPT_DIR, "cava.conf")


def _start_cava():
    """Create the fifo and spawn cava so /api/viz has real data.
    Viz._loop already polls for the fifo, so it will start reading as soon
    as the fifo exists. cava is spawned detached so the server never blocks."""
    global _cava_proc
    try:
        if not os.path.exists(CAVA_FIFO):
            os.mkfifo(CAVA_FIFO)
        _cava_proc = subprocess.Popen(
            ["cava", "-p", CAVA_CFG],
            start_new_session=True,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return True
    except Exception:
        return False


def _stop_cava():
    global _cava_proc
    if _cava_proc is not None:
        try:
            _cava_proc.terminate()
        except Exception:
            pass
        _cava_proc = None
    try:
        os.unlink(CAVA_FIFO)
    except Exception:
        pass


def main():
    signal.signal(signal.SIGTERM, _handle_sig)
    signal.signal(signal.SIGINT, _handle_sig)
    _start_cava()
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
