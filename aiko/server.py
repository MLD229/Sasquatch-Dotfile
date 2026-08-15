#!/usr/bin/env python3
# ─────────────────────────────────────────────────────────────
#  愛子 (Aiko) — server.py
#  Backend HTTP local pour la sidebar chat (Quickshell).
#
#  Endpoints :
#    GET  /api/health              → état serveur
#    GET  /api/model/status        → llama-server tourne ? modèle chargé ?
#    POST /api/model/start         → démarre llama-server (lazy)
#    POST /api/model/stop          → arrête llama-server
#    POST /api/chat                → {message, image?} → {job_id} (streaming)
#    GET  /api/chat/poll/<id>      → {done, text, error?}
#    POST /api/chat/reset          → vide l'historique (nouvelle conversation)
#    POST /api/capture             → slurp+grim → {image_b64} (attachée, pas envoyée)
#    GET  /api/palette             → palette thème (pattern CC)
#    POST /api/session/save        → sauvegarde la conversation → sessions/
#    POST /api/close               → arrête llama-server + quitte
#
#  Python stdlib uniquement. Ports : backend=8780, llama-server=8781.
# ─────────────────────────────────────────────────────────────
import base64
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(SCRIPT_DIR, "config.json")
MODELS_DIR = os.path.join(SCRIPT_DIR, "models")
SESSIONS_DIR = os.path.join(SCRIPT_DIR, "sessions")
PORT = 8780

# ─── Config ─────────────────────────────────────────────────

def load_config():
    with open(CONFIG_PATH) as f:
        return json.load(f)

cfg = load_config()
MODEL_CFG = cfg["model"]
SERVER_CFG = cfg["server"]
LLAMA_CFG = cfg["llama_bin"]
VRAM_CFG = cfg.get("vram", {"enabled": False, "min_free_mb": 3000, "lms_unload": True})
PERSONA = cfg["persona"]

LLAMA_PORT = SERVER_CFG["llama_port"]
LLAMA_HOST = SERVER_CFG["llama_host"]
LLAMA_URL = f"http://{LLAMA_HOST}:{LLAMA_PORT}"

# Historique du chat (mémoire vive — vierge à chaque ouverture)
history = []
history_lock = threading.Lock()

# Jobs de génération (streaming)
jobs = {}
jobs_lock = threading.Lock()
job_counter = [0]


# ─── llama-server (lazy) ────────────────────────────────────

def find_llama_bin():
    """Trouve le binaire llama-server : custom → LM Studio backend → PATH."""
    custom = LLAMA_CFG.get("custom_bin", "")
    if custom and os.path.isfile(custom):
        return custom, []
    backend = LLAMA_CFG.get("backend_dir", "")
    if backend and os.path.isfile(os.path.join(backend, "llama-server")):
        libs = [backend]
        vendor = LLAMA_CFG.get("vendor_dir", "")
        if vendor and os.path.isdir(vendor):
            libs.append(vendor)
        return os.path.join(backend, "llama-server"), libs
    from shutil import which
    p = which("llama-server")
    if p:
        return p, []
    return None, []

llama_proc = None
llama_proc_lock = threading.Lock()
llama_ready = threading.Event()


def llama_env():
    """Env avec LD_LIBRARY_PATH si backend LM Studio."""
    _, libs = find_llama_bin()
    env = dict(os.environ)
    if libs:
        env["LD_LIBRARY_PATH"] = ":".join(libs)
    return env


def llama_running():
    """True si llama-server répond (test du port = source de vérité)."""
    try:
        with urllib.request.urlopen(f"{LLAMA_URL}/v1/models", timeout=1.5) as r:
            return r.status == 200
    except Exception:
        return False


def vram_free_mb():
    """VRAM libre via nvidia-smi (Mo). None si indispo (pas de GPU NVIDIA)."""
    try:
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=memory.free", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5,
        )
        return int(out.stdout.strip().splitlines()[0])
    except Exception:
        return None


def ensure_vram():
    """Si VRAM libre < seuil, décharge le modèle LM Studio (Rin) — lazy coopératif.
    Retourne (ok, message)."""
    if not VRAM_CFG.get("enabled"):
        return True, ""
    free = vram_free_mb()
    if free is None:
        return True, ""  # pas de NVIDIA / indispo → on tente quand même
    if free >= VRAM_CFG["min_free_mb"]:
        return True, ""
    if VRAM_CFG.get("lms_unload"):
        try:
            subprocess.run(["lms", "unload", "--all"], capture_output=True, timeout=30)
            time.sleep(2)
            return True, "Rin déchargé pour libérer la VRAM (se recharge tout seul)"
        except Exception as e:
            return False, f"impossible de décharger LM Studio : {e}"
    return False, f"VRAM insuffisante ({free} Mo libres) — décharge Rin d'abord (lms unload --all)"


def start_llama():
    """Démarre llama-server (lazy). Bloque jusqu'à prêt ou timeout."""
    global llama_proc
    with llama_proc_lock:
        if llama_running():
            llama_ready.set()
            return True, "déjà en cours"
        # Gestion VRAM : décharge LM Studio (Rin) si pas assez de place
        ok_vram, msg_vram = ensure_vram()
        if not ok_vram:
            return False, msg_vram
        bin_path, _ = find_llama_bin()
        if not bin_path:
            return False, "binaire llama-server introuvable (lance bash setup.sh)"
        model_path = os.path.join(MODELS_DIR, MODEL_CFG["model_file"])
        if not os.path.isfile(model_path):
            return False, f"modèle absent : {model_path} (lance bash setup.sh)"
        cmd = [
            bin_path,
            "--host", LLAMA_HOST,
            "--port", str(LLAMA_PORT),
            "--model", model_path,
            "-c", str(MODEL_CFG["n_ctx"]),
            "-ngl", str(MODEL_CFG["n_gpu_layers"]),
            "--parallel", "1",
            "--jinja",
        ]
        mmproj = os.path.join(MODELS_DIR, MODEL_CFG.get("mmproj_file", ""))
        if os.path.isfile(mmproj):
            cmd += ["--mmproj", mmproj]
        # Logs vers journal (fd hérité) — le serveur vit au-delà du subprocess
        try:
            llama_proc = subprocess.Popen(
                cmd, env=llama_env(),
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except Exception as e:
            return False, f"échec démarrage llama-server : {e}"
    # Attend la disponibilité (préfill GPU peut prendre quelques secondes)
    deadline = time.time() + 60
    while time.time() < deadline:
        if llama_running():
            llama_ready.set()
            return True, msg_vram or "modèle chargé"
        time.sleep(0.4)
    return False, "timeout : llama-server ne répond pas (voir journal sasquatch-cc)"


def stop_llama():
    """Arrête llama-server proprement (SIGTERM → KILL)."""
    global llama_proc
    with llama_proc_lock:
        if llama_proc and llama_proc.poll() is None:
            llama_proc.terminate()
            try:
                llama_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                llama_proc.kill()
        llama_proc = None
    llama_ready.clear()


# ─── Chat / génération (streaming) ──────────────────────────

SYSTEM_PROMPT = PERSONA["system_prompt"]

def build_messages():
    with history_lock:
        msgs = [{"role": "system", "content": SYSTEM_PROMPT}] + list(history)
    return msgs


def chat_completion(messages, image_b64=None):
    """Appel non-streaming à llama-server (utilisé par le job streaming)."""
    payload = {
        "messages": messages,
        "temperature": MODEL_CFG["temperature"],
        "max_tokens": MODEL_CFG["max_tokens"],
        "stream": False,
    }
    if image_b64:
        # Vision : image en content_url data URI (format OpenAI)
        text = messages[-1]["content"]
        messages[-1] = {
            "role": "user",
            "content": [
                {"type": "text", "text": text},
                {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{image_b64}"}},
            ],
        }
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        f"{LLAMA_URL}/v1/chat/completions", data=data,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=300) as r:
        resp = json.loads(r.read().decode())
    return resp["choices"][0]["message"]["content"]


def run_chat_job(job_id, user_text, image_b64):
    """Thread du job : garde l'historique, génère, stocke les morceaux."""
    with history_lock:
        history.append({"role": "user", "content": user_text})
    msgs = build_messages()
    full = ""
    try:
        # Note : llama-server supporte stream, mais on fait un appel complet
        # et on renvoie le texte par morceaux depuis le job (simple + robuste).
        full = chat_completion(msgs, image_b64)
        with history_lock:
            history.append({"role": "assistant", "content": full})
    except Exception as e:
        with jobs_lock:
            jobs[job_id]["error"] = str(e)
    with jobs_lock:
        jobs[job_id]["done"] = True
        jobs[job_id]["text"] = full


def start_chat(user_text, image_b64=None):
    if not llama_running():
        ok, msg = start_llama()
        if not ok:
            return None, msg
    job_id = f"job{job_counter[0]}"
    job_counter[0] += 1
    with jobs_lock:
        jobs[job_id] = {"done": False, "text": "", "error": None}
    t = threading.Thread(target=run_chat_job, args=(job_id, user_text, image_b64), daemon=True)
    t.start()
    return job_id, None


# ─── Capture (slurp + grim) ─────────────────────────────────

def do_capture():
    """Sélection de zone → PNG → base64 (attachée au chat, PAS envoyée)."""
    tmp = "/tmp/aiko-captures"
    os.makedirs(tmp, exist_ok=True)
    path = os.path.join(tmp, f"cap-{int(time.time())}.png")
    try:
        sel = subprocess.run(["slurp"], capture_output=True, text=True, timeout=15)
        if sel.returncode != 0 or not sel.stdout.strip():
            return None, "capture annulée"
        geo = sel.stdout.strip()
        grim = subprocess.run(["grim", "-g", geo, path], capture_output=True, timeout=15)
        if grim.returncode != 0 or not os.path.isfile(path):
            return None, "échec grim (sélection ?)"
        with open(path, "rb") as f:
            b64 = base64.b64encode(f.read()).decode()
        return b64, None
    except subprocess.TimeoutExpired:
        return None, "timeout capture"
    except FileNotFoundError as e:
        return None, f"outil manquant : {e}"


# ─── Palette (pattern CC — thème dynamique) ─────────────────

def get_palette():
    """Lit la palette depuis le QML Palette (généré par theme-apply)."""
    candidates = [
        os.path.join(SCRIPT_DIR, "qml", "Palette.qml"),
        os.path.join(SCRIPT_DIR, "..", "cc", "qml", "Palette.qml"),
    ]
    for p in candidates:
        p = os.path.normpath(p)
        if os.path.isfile(p):
            try:
                with open(p) as f:
                    content = f.read()
                pal = {}
                for key in ("bg", "bgSolid", "card", "text", "textDim", "accent", "accent2", "good", "warn", "hot", "overlay"):
                    m = re.search(rf'(?:readonly\s+)?property\s+color\s+{re.escape(key)}\s*:\s*"([^"]+)"', content)
                    if m:
                        pal[key] = m.group(1)
                if pal:
                    return pal
            except Exception:
                pass
    return {}


# ─── HTTP ───────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    server_version = "Aiko/1.0"
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        elif isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode())
        except Exception:
            return {}

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/api/health":
            self._send(200, {"ok": True, "model": MODEL_CFG["model_file"]})
        elif path == "/api/model/status":
            self._send(200, {"running": llama_running()})
        elif path.startswith("/api/chat/poll/"):
            job_id = path.rsplit("/", 1)[-1]
            with jobs_lock:
                job = jobs.get(job_id)
            if not job:
                self._send(404, {"done": True, "error": "job inconnu"})
            else:
                self._send(200, {"done": job["done"], "text": job["text"], "error": job["error"]})
        elif path == "/api/palette":
            self._send(200, get_palette())
        else:
            self._send(404, {"ok": False, "error": "not found"}, "text/plain")

    def do_POST(self):
        path = self.path.split("?")[0]
        body = self._read_body()
        if path == "/api/model/start":
            ok, msg = start_llama()
            self._send(200, {"ok": ok, "msg": msg})
        elif path == "/api/model/stop":
            stop_llama()
            self._send(200, {"ok": True})
        elif path == "/api/chat":
            text = body.get("message", "").strip()
            image = body.get("image") or None
            if not text:
                self._send(400, {"ok": False, "error": "message vide"})
                return
            job_id, err = start_chat(text, image)
            if err:
                self._send(503, {"ok": False, "error": err})
            else:
                self._send(200, {"ok": True, "job_id": job_id})
        elif path == "/api/chat/reset":
            with history_lock:
                history.clear()
            self._send(200, {"ok": True})
        elif path == "/api/capture":
            b64, err = do_capture()
            if err:
                self._send(200, {"ok": False, "error": err})
            else:
                self._send(200, {"ok": True, "image": b64})
        elif path == "/api/session/save":
            name = body.get("name") or f"session-{int(time.time())}"
            safe = re.sub(r"[^a-zA-Z0-9_-]", "_", name) + ".json"
            os.makedirs(SESSIONS_DIR, exist_ok=True)
            with history_lock:
                data = {"name": name, "messages": list(history)}
            with open(os.path.join(SESSIONS_DIR, safe), "w") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            self._send(200, {"ok": True, "file": safe})
        elif path == "/api/close":
            # Répond d'abord, puis arrête proprement
            self._send(200, {"ok": True})
            threading.Timer(0.3, shutdown_server).start()
        else:
            self._send(404, {"ok": False, "error": "not found"}, "text/plain")


# ─── Main ───────────────────────────────────────────────────

def shutdown_server():
    stop_llama()
    os._exit(0)


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main():
    global PORT
    if "--port" in sys.argv:
        try:
            PORT = int(sys.argv[sys.argv.index("--port") + 1])
        except (IndexError, ValueError):
            pass
    # Verrouille le port si déjà occupé → un serveur aiko tourne déjà
    try:
        srv = Server(("127.0.0.1", PORT), Handler)
    except OSError:
        print(f"Aiko déjà lancé sur le port {PORT}", flush=True)
        sys.exit(0)
    print(f"Aiko ready on http://127.0.0.1:{PORT}", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
