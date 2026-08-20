"""Métriques système — échantillonne CPU/RAM/GPU/temp/réseau chaque seconde
et garde un historique glissant (utilisé par /api/stats et les sparklines)."""

import json
import os
import socket
import subprocess
import threading
import time
from collections import deque

from config import HIST_LEN


class Metrics:
    """Échantillonne les métriques système chaque seconde et conserve un
    historique glissant (cpu, ram, gpu, vram, températures, réseau)."""

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
