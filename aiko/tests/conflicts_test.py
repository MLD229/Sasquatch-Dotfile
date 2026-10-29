#!/usr/bin/env python3
"""conflicts_test.py — les conflits réels, provoqués exprès.

Chaque cas est reproduit pour de vrai (vrais process, vrais ports) :

  1. double backend      : un 2e server.py s'arrête proprement (verrou flock),
                           le 1er continue de servir, un seul process vivant ;
  2. port 8791 étranger  : aiko refuse de démarrer, code retour 2 et message
                           clair (pas de traceback) ;
  3. port 8792 étranger  : le chat renvoie une erreur explicite nommant le
                           port et son occupant, le backend reste debout ;
  4. modèle absent       : erreur UI avec la commande curl exacte, pas de crash ;
  5. llama-server absent : erreur explicite (build Vulkan / paquet CPU only) ;
  6. fermeture pendant le cold start : llama-server tué, backend sorti vite,
                           aucun process orphelin.

Usage : python3 tests/conflicts_test.py
Sortie : une ligne PASS/FAIL par point + code retour 0 si tout passe.
"""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

HERE = os.path.dirname(os.path.realpath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)
import llm  # noqa: E402

CFG = llm.load_models()
PORT = int(os.environ.get("AIKO_PORT") or CFG.get("backend_port") or 8791)
LLAMA_PORT = int(CFG.get("llama_server_port") or 8792)
BASE = f"http://127.0.0.1:{PORT}"
MARKER = llm.MARKER
SCRATCH = tempfile.mkdtemp(prefix="aiko-conflits-")

RESULTS: list[tuple[bool, str]] = []


def check(ok: bool, label: str, detail: str = "") -> bool:
    RESULTS.append((bool(ok), label))
    print(f"  [{'PASS' if ok else 'FAIL'}] {label}" + (f" — {detail}" if detail else ""))
    return bool(ok)


# ── HTTP ──────────────────────────────────────────────────────────────────
def get(path: str, timeout: float = 3.0):
    with urllib.request.urlopen(BASE + path, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def post(path: str, body: dict | None = None, timeout: float = 20.0):
    data = json.dumps(body or {}).encode()
    req = urllib.request.Request(BASE + path, data=data,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def http_ok(path: str = "/api/health", timeout: float = 0.6) -> bool:
    try:
        get(path, timeout=timeout)
        return True
    except Exception:
        return False


def wait_http(timeout: float = 10.0) -> bool:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if http_ok():
            return True
        time.sleep(0.1)
    return False


def wait_until(pred, timeout: float = 10.0) -> bool:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if pred():
            return True
        time.sleep(0.1)
    return pred()


# ── Process / ports ───────────────────────────────────────────────────────
def marker_pids() -> list[int]:
    try:
        out = subprocess.run(["pgrep", "-f", MARKER], capture_output=True,
                             text=True, timeout=3).stdout
    except Exception:
        return []
    return [int(x) for x in out.split() if x.isdigit()]


def backend_pids() -> list[int]:
    try:
        out = subprocess.run(["pgrep", "-f", "[a]iko/server.py"], capture_output=True,
                             text=True, timeout=3).stdout
    except Exception:
        return []
    return [int(x) for x in out.split() if x.isdigit()]


def take_port(port: int) -> socket.socket:
    """Occupe un port pour de vrai (test du conflit).

    SO_REUSEADDR : permet de reprendre le port même si d'anciennes connexions
    traînent en TIME_WAIT (sinon le test échouerait au lieu de tester aiko).
    """
    last: Exception | None = None
    for _ in range(30):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            s.bind(("127.0.0.1", port))
            s.listen(4)
            return s
        except OSError as exc:
            last = exc
            s.close()
            time.sleep(0.2)
    raise SystemExit(f"impossible d'occuper le port {port} : {last}")


def port_free(port: int) -> bool:
    with socket.socket() as s:
        s.settimeout(0.4)
        return s.connect_ex(("127.0.0.1", port)) != 0


class Backend:
    """Un server.py lancé comme aiko.sh le ferait (détaché de son propre log)."""

    def __init__(self, name: str, extra_env: dict | None = None):
        self.name = name
        self.log_path = os.path.join(SCRATCH, f"{name}.log")
        self.env = dict(os.environ)
        self.env.pop("AIKO_STATE_DIR", None)
        if extra_env:
            self.env.update(extra_env)
        self.proc: subprocess.Popen | None = None

    def spawn(self) -> subprocess.Popen:
        fh = open(self.log_path, "wb")
        self.proc = subprocess.Popen([sys.executable, "-u",
                                      os.path.join(ROOT, "server.py")],
                                     env=self.env, stdout=fh, stderr=fh,
                                     start_new_session=True)
        return self.proc

    def start(self) -> "Backend":
        self.spawn()
        if not wait_http(12):
            raise SystemExit(f"[{self.name}] backend injoignable — voir {self.log_path}")
        return self

    def wait_exit(self, timeout: float = 8.0) -> int | None:
        try:
            return self.proc.wait(timeout=timeout) if self.proc else None
        except subprocess.TimeoutExpired:
            return None

    def log_text(self) -> str:
        try:
            with open(self.log_path, "r", encoding="utf-8", errors="replace") as fh:
                return fh.read()
        except OSError:
            return ""

    def stop(self) -> None:
        if self.proc and self.proc.poll() is None:
            if http_ok():
                try:
                    post("/api/shutdown", timeout=5)
                except Exception:
                    pass
            try:
                self.proc.wait(timeout=4)
            except subprocess.TimeoutExpired:
                self.proc.kill()


def chat_error(text: str = "test") -> dict:
    """Envoie un message et renvoie le premier événement d'erreur (ou {})."""
    body = json.dumps({"text": text}).encode()
    req = urllib.request.Request(BASE + "/api/chat", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        for raw in resp:
            try:
                obj = json.loads(raw.decode())
            except Exception:
                continue
            if obj.get("e") in ("error", "done"):
                return obj
    return {}


def clean_slate() -> None:
    subprocess.run(["pkill", "-f", "[a]iko/server.py"], capture_output=True)
    for pid in marker_pids():
        try:
            os.kill(pid, 15)
        except OSError:
            pass
    wait_until(lambda: not marker_pids(), 6)
    wait_until(lambda: not backend_pids(), 6)
    wait_until(lambda: port_free(PORT), 6)
    time.sleep(0.2)


# ── 1. double backend ─────────────────────────────────────────────────────
def test_double_backend() -> None:
    print("\n1) Double backend (aiko.sh + aiko.service, deux server.py)")
    b1 = Backend("b1").start()
    b2 = Backend("b2")
    b2.spawn()
    rc = b2.wait_exit(8)
    log = b2.log_text()
    check(rc == 0, "le 2e backend sort de lui-même (code 0, pas de crash)",
          f"code={rc}")
    check("un backend aiko tourne déjà" in log,
          "message clair : « un backend tourne déjà »",
          log.strip().splitlines()[-1] if log.strip() else "(log vide)")
    check(len(backend_pids()) == 1, "un seul server.py vivant",
          f"pids={backend_pids()}")
    check(http_ok(), "le 1er backend sert toujours (port 8791 intact)")
    b1.stop()


# ── 2. port 8791 tenu par un autre programme ──────────────────────────────
def test_backend_port_foreign() -> None:
    print("\n2) Port 8791 occupé par un AUTRE programme")
    dummy = take_port(PORT)
    try:
        b = Backend("b_port8791")
        b.spawn()
        rc = b.wait_exit(10)
        log = b.log_text()
        check(rc == 2, "aiko refuse de démarrer (code 2)", f"code={rc}")
        check("déjà occupé" in log and "Traceback" not in log,
              "message clair et pas de traceback",
              next((ln for ln in log.splitlines() if "occupé" in ln), "(rien)"))
    finally:
        dummy.close()


# ── 3. port 8792 tenu par un autre programme ──────────────────────────────
def test_llama_port_foreign() -> None:
    print(f"\n3) Port {LLAMA_PORT} (llama-server) occupé par un autre programme")
    b = Backend("b_port8792").start()
    dummy = take_port(LLAMA_PORT)
    try:
        ev = chat_error("Bonjour")
        msg = str(ev.get("message") or "")
        check(ev.get("e") == "error", "le chat renvoie une erreur (pas un blocage)",
              ev.get("e", "rien"))
        check(str(LLAMA_PORT) in msg and "occupé" in msg,
              f"le message nomme le port {LLAMA_PORT} et l'occupant", msg.splitlines()[0] if msg else "(vide)")
        check(http_ok(), "le backend reste debout après l'erreur")
    finally:
        dummy.close()
        b.stop()


# ── 4. modèle absent ──────────────────────────────────────────────────────
def test_model_missing() -> None:
    print("\n4) Modèle absent (dossier de GGUF vide)")
    empty = os.path.join(SCRATCH, "models-vide")
    os.makedirs(empty, exist_ok=True)
    b = Backend("b_nomodel", {"AIKO_MODELS_DIR": empty}).start()
    try:
        ev = chat_error("Bonjour")
        msg = str(ev.get("message") or "")
        check(ev.get("e") == "error", "erreur remontée à l'UI", ev.get("e", "rien"))
        check("absent" in msg, "le message dit que le modèle est absent",
              msg.splitlines()[0] if msg else "(vide)")
        check("curl -fL -C -" in msg, "la commande de téléchargement exacte est donnée",
              next((ln.strip() for ln in msg.splitlines() if "curl" in ln), "(rien)"))
        check(http_ok(), "le backend ne crashe pas")
    finally:
        b.stop()


# ── 5. llama-server absent ────────────────────────────────────────────────
def test_binary_missing() -> None:
    print("\n5) llama-server absent (ni PATH, ni LM Studio)")
    fakehome = os.path.join(SCRATCH, "home-nobin")
    emptybin = os.path.join(SCRATCH, "bin-vide")
    os.makedirs(fakehome, exist_ok=True)
    os.makedirs(emptybin, exist_ok=True)
    env = {"HOME": fakehome, "PATH": emptybin,
           "XDG_RUNTIME_DIR": os.path.join(fakehome, "run"),
           "AIKO_MODELS_DIR": llm.MODELS_DIR}
    b = Backend("b_nobin", env).start()
    try:
        ev = chat_error("Bonjour")
        msg = str(ev.get("message") or "")
        check(ev.get("e") == "error", "erreur remontée à l'UI", ev.get("e", "rien"))
        check("llama-server introuvable" in msg,
              "message explicite « llama-server introuvable »",
              msg.splitlines()[0] if msg else "(vide)")
        check("installer.sh" in msg or "pacman" in msg,
              "la piste d'installation est donnée",
              next((ln.strip() for ln in msg.splitlines() if "installer" in ln
                    or "pacman" in ln), "(rien)"))
        check(http_ok(), "le backend ne crashe pas")
    finally:
        b.stop()
        shutil.rmtree(fakehome, ignore_errors=True)


# ── 6. fermeture pendant le cold start ────────────────────────────────────
def test_close_during_cold_start() -> None:
    print("\n6) Fermeture pendant le chargement du modèle")
    b = Backend("b_cold").start()
    loading = threading.Event()
    outcome: dict = {}

    def stream() -> None:
        body = json.dumps({"text": "Bonjour"}).encode()
        req = urllib.request.Request(BASE + "/api/chat", data=body,
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                for raw in resp:
                    try:
                        obj = json.loads(raw.decode())
                    except Exception:
                        continue
                    if obj.get("e") == "status":
                        loading.set()
        except Exception as exc:                     # noqa: BLE001
            outcome["stream_error"] = repr(exc)

    th = threading.Thread(target=stream, daemon=True)
    th.start()
    started = loading.wait(8)
    check(started, "le cold start a bien commencé (événement status reçu)")

    t0 = time.monotonic()
    try:
        res = post("/api/shutdown", timeout=20)
        ok = res.get("ok") is True
    except Exception as exc:                        # noqa: BLE001
        ok = False
        res = {"error": repr(exc)}
    elapsed = time.monotonic() - t0
    check(ok, "shutdown accepté pendant le cold start", f"réponse={str(res)[:120]}")
    check(elapsed < 5.0, "réponse rapide (pas d'attente de la fin du chargement)",
          f"{elapsed:.2f}s")
    check(wait_until(lambda: not marker_pids(), 8),
          "llama-server tué, aucun orphelin", f"pgrep={len(marker_pids())}")
    check(wait_until(lambda: not backend_pids(), 8), "backend sorti")
    th.join(timeout=3)


def main() -> int:
    print("=== 愛子 — conflits provoqués (double backend, ports, arrêt, absence) ===")
    clean_slate()
    try:
        test_double_backend()
        clean_slate()
        test_backend_port_foreign()
        clean_slate()
        test_llama_port_foreign()
        clean_slate()
        test_model_missing()
        clean_slate()
        test_binary_missing()
        clean_slate()
        test_close_during_cold_start()
    finally:
        clean_slate()
        shutil.rmtree(SCRATCH, ignore_errors=True)

    # ── État final ───────────────────────────────────────────────────────
    print("\nÉtat final")
    check(not backend_pids(), "0 server.py restant", f"pids={backend_pids()}")
    check(not marker_pids(), "0 llama-server restant", f"pids={marker_pids()}")
    check(port_free(PORT) and port_free(LLAMA_PORT),
          f"ports {PORT} et {LLAMA_PORT} libres")
    prefs_ok = True
    if os.path.exists(llm.PREFS_FILE):
        try:
            with open(llm.PREFS_FILE, "r", encoding="utf-8") as fh:
                obj = json.load(fh)
            prefs_ok = isinstance(obj, dict) and set(obj) <= {"model", "updated"}
        except (OSError, ValueError):
            prefs_ok = False
    check(prefs_ok, "préférence de modèle intacte et valide", llm.PREFS_FILE)

    failed = [lbl for ok, lbl in RESULTS if not ok]
    print(f"\n=== {len(RESULTS) - len(failed)}/{len(RESULTS)} PASS ===")
    if failed:
        print("ÉCHECS :")
        for lbl in failed:
            print("  -", lbl)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
