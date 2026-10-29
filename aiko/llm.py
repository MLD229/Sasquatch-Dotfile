#!/usr/bin/env python3
"""llm.py — cycle de vie de llama-server pour 愛子 (aiko).

Rôle unique : porter un process llama-server de la naissance à la mort.
  - start(profile)  : lance le binaire, attend /health, mesure le cold start
  - stop()          : SIGTERM au groupe, puis SIGKILL après 3 s, puis VÉRIFIE
                      qu'il ne reste rien (pgrep = 0). Répond même si un
                      cold start est en cours (drapeau `abort`).
  - idle_stop()     : tue le process si plus personne ne parle
  - generate(...)   : stream token par token (utilisé par server.py)

Aucune conversation sur disque : l'historique vit en RAM chez server.py.
Une seule pièce de log technique (dernières lignes de stderr) est gardée en
RAM pour le diagnostic — jamais le contenu des conversations.

SEUL fichier écrit par aiko : ~/.local/state/aiko/prefs.json, qui contient
UNIQUEMENT la préférence de modèle (`{"model": "rapide"|"best"}`). C'est une
préférence, pas une mémoire : la conversation, elle, disparaît à la fermeture.
Écriture atomique (tmp + os.replace) ; fichier absent/corrompu → défaut.

Découverte du binaire (dans cet ordre) :
  1. $AIKO_LLAMA_SERVER
  2. llama-server dans le PATH (paquet Arch extra/llama-cpp)
  3. backend CUDA livré par LM Studio (~/.lmstudio/extensions/backends/…)
"""

from __future__ import annotations

import glob
import http.client
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import threading
import time

HERE = os.path.dirname(os.path.realpath(__file__))
MODELS_FILE = os.path.join(HERE, "models.json")
MODELS_DIR = os.path.expanduser(os.environ.get("AIKO_MODELS_DIR", "~/models"))
# Marqueur présent dans l'argv de llama-server : permet de retrouver/écraser un
# orphelin d'une session précédente SANS fichier pid sur disque.
MARKER = "aiko-ephemere"

# ── Unique état persisté : la PRÉFÉRENCE de modèle ───────────────────────
STATE_DIR = os.path.expanduser(
    os.environ.get("AIKO_STATE_DIR", "~/.local/state/aiko"))
PREFS_FILE = os.path.join(STATE_DIR, "prefs.json")
# Clés autorisées dans prefs.json. Tout le reste est refusé → le fichier ne
# peut pas devenir un début de mémoire de conversation.
PREFS_KEYS = ("model", "updated")


def _version_key(path: str) -> list:
    """Trie les backends LM Studio par version (2.9 < 2.10)."""
    nums = re.findall(r"\d+", os.path.basename(os.path.dirname(path)) or "")
    return [int(n) for n in nums] or [0]


def find_llama_server() -> str | None:
    """Renvoie le chemin du binaire llama-server, ou None."""
    env = os.environ.get("AIKO_LLAMA_SERVER")
    if env and os.path.isfile(env) and os.access(env, os.X_OK):
        return env
    which = shutil.which("llama-server")
    if which:
        return which
    # LM Studio : préférer un build CUDA, le plus récent.
    cands = glob.glob(os.path.expanduser(
        "~/.lmstudio/extensions/backends/llama.cpp-*/llama-server"))
    cuda = [c for c in cands if "cuda" in c]
    pool = cuda or cands
    if pool:
        return sorted(pool, key=_version_key)[-1]
    return None


def load_models() -> dict:
    with open(MODELS_FILE, "r", encoding="utf-8") as fh:
        return json.load(fh)


def model_path(profile_cfg: dict) -> str:
    return os.path.join(MODELS_DIR, profile_cfg["file"])


# ── Préférence de modèle : lecture / écriture atomique ───────────────────
def load_prefs() -> dict:
    """Lit prefs.json. Absent, corrompu ou illisible → dict vide (jamais d'exception)."""
    try:
        with open(PREFS_FILE, "r", encoding="utf-8") as fh:
            obj = json.load(fh)
    except FileNotFoundError:
        return {}
    except (OSError, ValueError):
        return {}
    if not isinstance(obj, dict):
        return {}
    return {k: v for k, v in obj.items() if k in PREFS_KEYS}


def save_prefs(prefs: dict) -> bool:
    """Écrit prefs.json de façon atomique (tmp + os.replace). True si écrit."""
    clean = {k: v for k, v in prefs.items() if k in PREFS_KEYS}
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        tmp = f"{PREFS_FILE}.tmp.{os.getpid()}"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(clean, fh, ensure_ascii=False, indent=2, sort_keys=True)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, PREFS_FILE)
        return True
    except OSError:
        try:
            os.unlink(f"{PREFS_FILE}.tmp.{os.getpid()}")
        except OSError:
            pass
        return False


def save_profile_pref(cfg: dict, profile: str) -> bool:
    """Mémorise le profil choisi. Refuse un profil inconnu (préférence ≠ mémoire)."""
    if profile not in cfg.get("profiles", {}):
        return False
    prefs = load_prefs()
    prefs["model"] = profile
    prefs["updated"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    return save_prefs(prefs)


def resolve_profile(cfg: dict, prefs: dict | None = None) -> tuple[str, str]:
    """Profil à utiliser au démarrage → (profil, note technique vide si honoré).

    La préférence n'est retenue que si le profil existe dans models.json ET si
    son GGUF est présent ; sinon on retombe sur models.json["default"] avec une
    note (log technique / /api/state) — jamais de crash.
    """
    profiles = cfg.get("profiles", {})
    default = cfg.get("default")
    if default not in profiles:
        default = next(iter(profiles), "")
    default = str(default or "")
    prefs = load_prefs() if prefs is None else prefs
    want = prefs.get("model")
    if not want:
        return default, ""
    if not isinstance(want, str) or want not in profiles:
        return default, f"préférence « {want} » inconnue de models.json → {default}"
    if not os.path.isfile(model_path(profiles[want])):
        return default, (f"modèle de « {want} » absent "
                         f"({model_path(profiles[want])}) → {default}")
    return want, ""


def download_hint(profile_cfg: dict) -> str:
    """Commande exacte de téléchargement du GGUF (bartowski, Q4_K_M)."""
    fname = profile_cfg["file"]
    url = ("https://huggingface.co/bartowski/"
           + fname.replace("-Q4_K_M.gguf", "-GGUF")
           + "/resolve/main/" + fname)
    return f'curl -fL -C - -o "{model_path(profile_cfg)}" "{url}"'


def port_owner(port: int) -> str:
    """« nom (pid N) » du programme qui écoute sur le port, ou chaîne vide."""
    try:
        out = subprocess.run(["ss", "-ltnp"], capture_output=True,
                             text=True, timeout=3).stdout
    except Exception:
        return ""
    for line in (out or "").splitlines():
        if f":{port} " not in line and not line.rstrip().endswith(f":{port}"):
            continue
        m = re.search(r"pid=(\d+)", line)
        if not m:
            continue
        pid = int(m.group(1))
        try:
            with open(f"/proc/{pid}/comm", "r", encoding="utf-8") as fh:
                name = fh.read().strip()
        except OSError:
            name = "?"
        return f"{name} (pid {pid})"
    return ""


def pgrep_llama_server() -> list[int]:
    """PIDs des llama-server qui portent notre marqueur (ou tous, si asked)."""
    try:
        out = subprocess.run(["pgrep", "-f", MARKER], capture_output=True,
                             text=True, timeout=3).stdout
    except Exception:
        return []
    pids = []
    for line in out.split():
        try:
            pids.append(int(line))
        except ValueError:
            pass
    return [p for p in pids if p != os.getpid()]


def _nvsmi(args: list[str]) -> list[str]:
    try:
        out = subprocess.run(["nvidia-smi", *args], capture_output=True,
                             text=True, timeout=3).stdout
        return [ln.strip() for ln in (out or "").splitlines() if ln.strip()]
    except Exception:
        return []


def vram_used_mib(pid: int | None = None):
    """VRAM (MiB). Avec pid : celle de CE process seulement ; sinon GPU entier.

    Under Vulkan/CUDA, nvidia-smi liste le process llama-server : c'est la
    mesure honnête (la VRAM globale inclut les jeux et autres modèles).
    """
    if pid:
        total = 0
        for line in _nvsmi(["--query-compute-apps=pid,used_memory",
                            "--format=csv,noheader,nounits"]):
            parts = [p.strip() for p in line.split(",")]
            if len(parts) >= 2 and parts[0].isdigit() and int(parts[0]) == pid:
                total += int(parts[1]) if parts[1].isdigit() else 0
        if total:
            return total
    rows = _nvsmi(["--query-gpu=memory.used", "--format=csv,noheader,nounits"])
    if rows and rows[0].isdigit():
        return int(rows[0])
    return None


class ModelMissing(RuntimeError):
    pass


class LlamaManager:
    def __init__(self, cfg: dict | None = None, log=print):
        self.cfg = cfg or load_models()
        self.log = log
        self.port = int(self.cfg.get("llama_server_port", 8792))
        self.proc: subprocess.Popen | None = None
        self.profile: str | None = None
        self.lock = threading.RLock()
        self.state = "idle"            # idle | loading | ready | error
        self.last_error: str = ""
        self.stderr_tail: list[str] = []
        self.cold_start_ms: int | None = None
        self.loaded_at: float = 0.0
        self.last_used: float = time.time()
        self.busy = threading.Event()  # génération en cours
        self.cancel = threading.Event()
        # Demande d'arrêt immédiat : fait sortir _wait_health sans attendre la
        # fin du cold start (fermeture du panneau pendant le chargement).
        self.abort = threading.Event()
        self._flash_args: str | None = None
        self._devs_cache: list[str] | None = None
        self.idle_seconds = int(os.environ.get(
            "AIKO_IDLE_SEC", self.cfg.get("idle_seconds", 300)))

    # ── binaire / args ────────────────────────────────────────────────────
    def binary(self) -> str | None:
        return find_llama_server()

    def _devices(self) -> list[str]:
        """Liste les périphériques d'inférence ('Vulkan1: NVIDIA ...')."""
        if self._devs_cache is not None:
            return self._devs_cache
        binp = self.binary()
        devs: list[str] = []
        if binp:
            try:
                out = subprocess.run([binp, "--list-devices"], capture_output=True,
                                     text=True, timeout=8).stdout
                for line in (out or "").splitlines():
                    line = line.strip()
                    if line and line.lower().startswith(("vulkan", "cuda", "rocm",
                                                         "metal", "sycl", "gpu")):
                        devs.append(line)
            except Exception:
                # Diagnostic seulement : sans liste, on ne pinne pas le GPU.
                devs = []
        self._devs_cache = devs
        return devs

    def _pick_device(self, profile: str) -> str:
        """Choisit le GPU : champ 'device' du profil, sinon la carte NVIDIA.

        Le pick évite le piège mesuré ici : cette machine expose Vulkan0 (Intel
        iGPU, mémoire partagée) et Vulkan1 (GTX 1660 Ti). Sans pin, llama.cpp
        répartit les couches sur les deux → plus lent.
        """
        p = self.cfg["profiles"][profile]
        if p.get("device"):
            return str(p["device"])
        for dev in self._devices():
            if "nvidia" in dev.lower():
                return dev.split(":", 1)[0].strip()
        return ""

    def _argv(self, profile: str, flash: str) -> list[str]:
        p = self.cfg["profiles"][profile]
        binp = self.binary()
        argv = [
            binp, "-m", model_path(p),
            "--host", "127.0.0.1", "--port", str(self.port),
            "-c", str(p.get("ctx", 4096)),
            "-ngl", str(p.get("ngl", 99)),
            "-t", str(p.get("threads", 6)),
            "--alias", MARKER,
            "--no-webui",
        ]
        dev = self._pick_device(profile)
        if dev:
            argv += ["--device", dev]
        if flash == "on":
            argv += ["--flash-attn", "on"]   # builds récents (>= b4x)
        elif flash == "flag":
            argv += ["--flash-attn"]         # builds anciens (booléen)
        return argv

    def _reader(self, proc: subprocess.Popen) -> None:
        """Garde les 40 dernières lignes de stderr en RAM (diagnostic)."""
        stream = proc.stderr
        if stream is None:
            return
        try:
            for raw in iter(stream.readline, b""):
                line = raw.decode("utf-8", "replace").rstrip()
                if not line:
                    continue
                self.stderr_tail.append(line)
                del self.stderr_tail[:-40]
        except Exception:
            # Process tué pendant la lecture : normal (stop(), changement de modèle).
            pass

    # ── démarrage ─────────────────────────────────────────────────────────
    def _port_free(self) -> bool:
        with socket.socket() as s:
            s.settimeout(0.4)
            return s.connect_ex(("127.0.0.1", self.port)) != 0

    def kill_orphans(self) -> list[int]:
        """Tue un llama-server laissé par une session précédente."""
        pids = pgrep_llama_server()
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        if pids:
            time.sleep(0.8)
            for pid in pids:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            self.log(f"[llm] orphelins tués : {pids}")
        return pids

    def _kill_by_marker(self) -> list[int]:
        """Tue tout llama-server d'aiko SANS prendre le verrou.

        Indispensable pendant un cold start : le process candidat n'est pas
        encore dans self.proc (il n'est publié qu'une fois /health OK), donc
        `stop()` ne peut pas le joindre autrement.
        """
        pids = pgrep_llama_server()
        if not pids:
            return []
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass
        deadline = time.monotonic() + 1.5
        while time.monotonic() < deadline and pgrep_llama_server():
            time.sleep(0.1)
        for pid in pgrep_llama_server():
            try:
                os.kill(pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
        return pids

    def start(self, profile: str | None = None) -> dict:
        with self.lock:
            self.abort.clear()
            profile = profile or self.profile or self.cfg["default"]
            if profile not in self.cfg["profiles"]:
                raise ValueError(f"profil inconnu : {profile}")

            if self.proc is not None and self.proc.poll() is None:
                if profile == self.profile:
                    return self.status()
                self.stop()          # changement de modèle : on repart de zéro

            binp = self.binary()
            if not binp:
                self.state = "error"
                self.last_error = (
                    "llama-server introuvable — il faut un build GPU :\n"
                    "  bash " + os.path.join(HERE, "installer.sh") + "\n"
                    "  (Vulkan 80 tok/s ; le paquet Arch extra/llama-cpp est "
                    "CPU seul : 12,8 tok/s)")
                raise ModelMissing(self.last_error)

            path = model_path(self.cfg["profiles"][profile])
            if not os.path.isfile(path):
                self.state = "error"
                self.last_error = (
                    f"modèle « {profile} » absent : {path}\n"
                    f"  télécharger : {download_hint(self.cfg['profiles'][profile])}\n"
                    f"  ou tout vérifier : bash {os.path.join(HERE, 'installer.sh')}")
                raise ModelMissing(self.last_error)

            if not self._port_free():
                self.kill_orphans()
                if not self._port_free():
                    owner = port_owner(self.port) or "un autre programme"
                    self.state = "error"
                    self.last_error = (
                        f"port {self.port} déjà occupé par {owner} "
                        f"(ce n'est pas un llama-server d'aiko).\n"
                        f"  → libérer le port, ou changer \"llama_server_port\" "
                        f"dans models.json")
                    raise RuntimeError(self.last_error)

            self.state = "loading"
            self.last_error = ""
            self.stderr_tail = []
            self.cancel.clear()
            p = self.cfg["profiles"][profile]
            timeout = int(p.get("load_timeout", 90))
            t0 = time.monotonic()

            variants = [self._flash_args] if self._flash_args else ["on", "flag", "off"]
            last_err = ""
            for variant in variants:
                if self.abort.is_set():
                    break
                argv = self._argv(profile, variant or "off")
                self.log(f"[llm] start {profile} : {' '.join(argv)}")
                proc = subprocess.Popen(
                    argv, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                    stdin=subprocess.DEVNULL, start_new_session=True, bufsize=0)
                threading.Thread(target=self._reader, args=(proc,),
                                 daemon=True).start()
                ok, err = self._wait_health(proc, timeout)
                if ok:
                    self.proc = proc
                    self.profile = profile
                    self.state = "ready"
                    self.loaded_at = time.time()
                    self.last_used = time.time()
                    self.cold_start_ms = int((time.monotonic() - t0) * 1000)
                    self._flash_args = variant if variant != "off" else None
                    self.log(f"[llm] prêt en {self.cold_start_ms} ms "
                             f"(flash-attn={variant})")
                    return self.status()
                # échec : on tue ce candidat et on essaie la variante suivante
                last_err = err
                self._kill_proc(proc)
                if self.abort.is_set():
                    break
                if "unrecognized" not in err and "invalid" not in err \
                        and "unknown" not in err:
                    break

            self.state = "error"
            self.last_error = last_err or "échec du démarrage de llama-server"
            raise RuntimeError(self.last_error)

    def _wait_health(self, proc: subprocess.Popen, timeout: int) -> tuple[bool, str]:
        """Le port peut répondre AVANT que le modèle soit prêt → on poll /health."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.abort.is_set():
                # Fermeture pendant le cold start : on n'attend pas 75 s.
                return False, "chargement annulé (arrêt demandé)"
            if proc.poll() is not None:
                tail = " | ".join(self.stderr_tail[-6:])
                return False, (f"llama-server est mort (code {proc.returncode}) : {tail}")
            try:
                conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=1.5)
                conn.request("GET", "/health")
                resp = conn.getresponse()
                body = resp.read().decode("utf-8", "replace")
                conn.close()
                if resp.status == 200 and '"ok"' in body:
                    return True, ""
            except Exception:
                pass
            time.sleep(0.05)
        tail = " | ".join(self.stderr_tail[-6:])
        return False, f"timeout {timeout}s sur /health ({tail})"

    # ── arrêt ─────────────────────────────────────────────────────────────
    def _kill_proc(self, proc: subprocess.Popen, grace: float = 3.0) -> str:
        if proc is None or proc.poll() is not None:
            return "already-dead"
        how = "sigterm"
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except Exception:
            try:
                proc.terminate()
            except Exception:
                pass
        try:
            proc.wait(timeout=grace)
        except subprocess.TimeoutExpired:
            how = "sigkill"
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass
            try:
                proc.wait(timeout=2)
            except Exception:
                pass
        return how

    def stop(self) -> dict:
        """Tue llama-server et rend la main seulement quand c'est VÉRIFIÉ.

        Ne bloque pas un cold start en cours : `abort` est posé d'abord, puis
        les llama-server portant le marqueur sont tués sans attendre le verrou
        (pendant le chargement le process n'est pas encore dans self.proc).
        """
        self.abort.set()
        was_alive = self.proc is not None and self.proc.poll() is None
        early = self._kill_by_marker()
        got = self.lock.acquire(timeout=15)
        try:
            proc, self.proc = self.proc, None
            how = self._kill_proc(proc) if proc is not None else "none"
            if was_alive and how == "already-dead":
                # Tué par le marqueur juste au-dessus (cas normal hors cold start).
                how = "sigterm"
            # Rattrapage : un enfant qui aurait échappé au groupe de process.
            left = self._kill_by_marker()
            if left:
                time.sleep(0.2)
            remaining = pgrep_llama_server()
            self.state = "idle"
            self.profile = None
            self.cold_start_ms = None
            self.cancel.clear()
            res = {
                "ok": not remaining,
                "how": how,
                "pgrep": remaining,
                "pgrep_count": len(remaining),
                "killed_early": early,
                "vram_mib": vram_used_mib(),
            }
            self.log(f"[llm] stop ({how}) — pgrep={remaining} vram={res['vram_mib']} MiB"
                     + (f" · cold start interrompu ({early})" if early else ""))
            return res
        finally:
            if got:
                self.lock.release()
            self.abort.clear()

    def idle_stop(self) -> bool:
        """Tue le modèle si personne n'a parlé depuis idle_seconds."""
        if self.state != "ready" or self.busy.is_set():
            return False
        if time.time() - self.last_used < self.idle_seconds:
            return False
        self.log(f"[llm] inactivité > {self.idle_seconds}s → déchargement")
        self.stop()
        return True

    # ── génération ────────────────────────────────────────────────────────
    def generate(self, messages: list[dict], profile: str | None = None,
                 max_tokens: int | None = None):
        """Générateur : yield des deltas de texte.

        Lève RuntimeError si le moteur ne peut pas démarrer. La fermeture de la
        connexion (abort côté client) fait arrêter la génération par llama.cpp.
        """
        profile = profile or self.profile or self.cfg["default"]
        self.start(profile)
        p = self.cfg["profiles"][profile]
        payload = json.dumps({
            "model": MARKER,
            "messages": messages,
            "stream": True,
            "temperature": p.get("temperature", 0.4),
            "top_p": 0.9,
            "max_tokens": max_tokens or p.get("max_tokens", 700),
            "cache_prompt": True,
        }).encode("utf-8")
        self.busy.set()
        self.cancel.clear()
        conn = None
        try:
            conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=180)
            conn.request("POST", "/v1/chat/completions", body=payload,
                         headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            if resp.status != 200:
                body = resp.read().decode("utf-8", "replace")[:400]
                raise RuntimeError(f"llama-server HTTP {resp.status} : {body}")
            while True:
                if self.cancel.is_set():
                    break
                line = resp.readline()
                if not line:
                    break
                line = line.strip()
                if not line.startswith(b"data:"):
                    continue
                data = line[5:].strip()
                if data == b"[DONE]":
                    break
                try:
                    obj = json.loads(data)
                except Exception:
                    continue
                choices = obj.get("choices") or []
                if not choices:
                    continue
                delta = (choices[0].get("delta") or {}).get("content")
                if delta:
                    self.last_used = time.time()
                    yield delta
                if choices[0].get("finish_reason"):
                    break
        finally:
            self.busy.clear()
            if conn is not None:
                try:
                    conn.close()   # déconnexion → llama.cpp coupe la génération
                except Exception:
                    pass

    # ── état ──────────────────────────────────────────────────────────────
    def status(self) -> dict:
        alive = self.proc is not None and self.proc.poll() is None
        if alive and self.state == "loading":
            self.state = "ready"
        if not alive and self.state in ("ready", "loading"):
            self.state = "idle"
        p = self.cfg["profiles"].get(self.profile or "", {})
        return {
            "state": self.state,
            "profile": self.profile,
            "label": p.get("label"),
            "alive": alive,
            "pid": (self.proc.pid if (alive and self.proc is not None) else None),
            "cold_start_ms": self.cold_start_ms,
            "vram_mib": vram_used_mib(self.proc.pid) if alive and self.proc else 0,
            "vram_gpu_mib": vram_used_mib(),
            "pgrep": pgrep_llama_server(),
            "idle_seconds": self.idle_seconds,
            "error": self.last_error,
            "binary": self.binary(),
            "device": self._pick_device(self.profile or self.cfg["default"]),
            "devices": self._devices(),
        }
