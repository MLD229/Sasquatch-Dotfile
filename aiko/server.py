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
#
#  Robustesse (2026-08-15) :
#    - Vrai streaming SSE depuis llama-server (le job met à jour jobs[id]["text"]
#      au fil de l'eau → le poll QML affiche le texte progressivement, y compris
#      pendant les générations vision de 40-60 s).
#    - Catch large + log dans le worker de génération (plus jamais de mort
#      silencieuse sans trace) ; fallback appel non-stream si le SSE échoue.
#    - Handlers SIGTERM/SIGINT → stop_llama() avant exit : llama-server ne
#      reste JAMAIS orphelin (cause racine du « crash silencieux » : server.py
#      tué par un signal → llama-server survivait en gardant la VRAM).
#    - Timeouts réseau explicites (ping 1.5 s, génération 300 s, démarrage 90 s).
#    - Purge des jobs terminés après 60 s (anti-fuite mémoire).
#    - Filet d'erreur : toute exception d'un handler HTTP → 500 JSON logué,
#      le serveur ne meurt jamais sur une requête malformée.
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
import traceback
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(SCRIPT_DIR, "config.json")
MODELS_DIR = os.path.join(SCRIPT_DIR, "models")
SESSIONS_DIR = os.path.join(SCRIPT_DIR, "sessions")
PORT = 8780

# ─── Timeouts / limites ─────────────────────────────────────
LLAMA_PING_TIMEOUT = 1.5      # GET /v1/models (test de vie du port)
LLAMA_READY_TIMEOUT = 90      # attente du démarrage (préfill GPU)
LLAMA_GEN_TIMEOUT = 300       # socket timeout pendant la génération
JOB_RETENTION_SECONDS = 60    # garde un job terminé 60 s (le QML poll), puis purge
MAX_BODY_BYTES = 16 * 1024 * 1024  # body max (image base64) : 16 Mo

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
job_counter_lock = threading.Lock()


def log(msg):
    """Trace vers stderr (→ server.log via aiko.sh). flush pour un log en direct."""
    print(f"[aiko {time.strftime('%H:%M:%S')}] {msg}", file=sys.stderr, flush=True)


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
        with urllib.request.urlopen(f"{LLAMA_URL}/v1/models", timeout=LLAMA_PING_TIMEOUT) as r:
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
        # Ancien process mort → on nettoie la référence avant de relancer
        if llama_proc is not None and llama_proc.poll() is not None:
            llama_proc = None
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
            log(f"llama-server lancé (pid {llama_proc.pid}, port {LLAMA_PORT})")
        except Exception as e:
            llama_proc = None
            return False, f"échec démarrage llama-server : {e}"
    # Attend la disponibilité (préfill GPU peut prendre quelques secondes)
    deadline = time.time() + LLAMA_READY_TIMEOUT
    while time.time() < deadline:
        if llama_running():
            llama_ready.set()
            log("llama-server prêt")
            return True, msg_vram or "modèle chargé"
        # Le process est mort avant d'être prêt → erreur immédiate (pas 90 s d'attente)
        with llama_proc_lock:
            p = llama_proc
        if p is not None and p.poll() is not None:
            log(f"llama-server (pid {p.pid}) mort au démarrage, code {p.returncode}")
            return False, "llama-server a crashé au démarrage (VRAM insuffisante ? binaire ?)"
        time.sleep(0.4)
    return False, "timeout : llama-server ne répond pas (voir server.log)"


def stop_llama():
    """Arrête llama-server proprement (SIGTERM → KILL). Aucun zombie."""
    global llama_proc
    with llama_proc_lock:
        proc = llama_proc
        llama_proc = None
    if proc is not None and proc.poll() is None:
        log(f"stop_llama : SIGTERM → llama-server (pid {proc.pid})")
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            log("stop_llama : SIGKILL (timeout 5 s)")
            proc.kill()
            try:
                proc.wait(timeout=3)
            except Exception:
                pass
    llama_ready.clear()


# ─── Chat / génération (streaming) ──────────────────────────

SYSTEM_PROMPT = PERSONA["system_prompt"]


def build_messages():
    """Historique COMPLET (multi-tours) + system prompt."""
    with history_lock:
        msgs = [{"role": "system", "content": SYSTEM_PROMPT}] + list(history)
    return msgs


def _with_image(messages, image_b64):
    """Copie défensive : dernier message user → content list avec l'image.
    Ne mute JAMAIS les dicts de `history` (remplacement d'élément sur une copie)."""
    text = messages[-1]["content"]
    msgs = [dict(m) for m in messages]
    msgs[-1] = {
        "role": "user",
        "content": [
            {"type": "text", "text": text},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{image_b64}"}},
        ],
    }
    return msgs


def chat_completion(messages, image_b64=None):
    """Appel NON-streaming (fallback si le SSE échoue). Timeout explicite."""
    payload = {
        "messages": _with_image(messages, image_b64) if image_b64 else messages,
        "temperature": MODEL_CFG["temperature"],
        "max_tokens": MODEL_CFG["max_tokens"],
        "stream": False,
    }
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        f"{LLAMA_URL}/v1/chat/completions", data=data,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=LLAMA_GEN_TIMEOUT) as r:
        resp = json.loads(r.read().decode())
    return resp["choices"][0]["message"]["content"]


def stream_chat_completion(messages, image_b64=None, on_chunk=None):
    """Appel STREAMING (SSE) à llama-server. on_chunk(str) à chaque morceau.
    Lève une exception en cas d'échec réseau/HTTP/JSON — le worker décide."""
    payload = {
        "messages": _with_image(messages, image_b64) if image_b64 else messages,
        "temperature": MODEL_CFG["temperature"],
        "max_tokens": MODEL_CFG["max_tokens"],
        "stream": True,
    }
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        f"{LLAMA_URL}/v1/chat/completions", data=data,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=LLAMA_GEN_TIMEOUT) as r:
        for raw in r:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            try:
                obj = json.loads(data)
                delta = obj["choices"][0]["delta"]
                c = delta.get("content")
            except Exception:
                continue
            if c and on_chunk:
                on_chunk(c)


def run_chat_job(job_id, user_text, image_b64):
    """Thread du job : garde l'historique, stream la génération, met à jour
    jobs[job_id]["text"] au fil de l'eau. Catch large : un échec ne tue JAMAIS
    le process — il marque le job en erreur (visible dans le poll QML)."""
    with history_lock:
        history.append({"role": "user", "content": user_text})
    msgs = build_messages()
    chunks = []
    error = None

    def on_chunk(c):
        chunks.append(c)
        with jobs_lock:
            j = jobs.get(job_id)
            if j is not None:
                j["text"] = "".join(chunks)

    try:
        stream_chat_completion(msgs, image_b64, on_chunk)
    except Exception as e:
        log(f"[job {job_id}] stream échec : {e}")
        if chunks:
            # Texte partiel déjà reçu → on garde, on signale l'interruption
            error = f"génération interrompue : {e}"
        else:
            # Rien reçu → fallback appel complet (robustesse maximale)
            try:
                full = chat_completion(msgs, image_b64)
                chunks = [full]
                log(f"[job {job_id}] fallback non-stream OK ({len(full)} chars)")
            except Exception as e2:
                error = f"{e2}"
                log(f"[job {job_id}] fallback échoué : {e2}")

    full_text = "".join(chunks)
    with jobs_lock:
        j = jobs.get(job_id)
        if j is None:  # filet : le job existe toujours en pratique
            j = jobs[job_id] = {"done": True, "text": "", "error": None, "finished_at": None}
        if error:
            j["error"] = error
        else:
            j["text"] = full_text
        j["done"] = True
        j["finished_at"] = time.time()

    if error is None:
        with history_lock:
            history.append({"role": "assistant", "content": full_text})
    log(f"[job {job_id}] terminé : {len(full_text)} chars" + (f" — ERREUR : {error}" if error else ""))


def _purge_jobs():
    """Supprime les jobs terminés depuis > JOB_RETENTION_SECONDS (anti-fuite)."""
    now = time.time()
    with jobs_lock:
        stale = [
            jid for jid, j in jobs.items()
            if j.get("done") and (j.get("finished_at") or 0) < now - JOB_RETENTION_SECONDS
        ]
        for jid in stale:
            del jobs[jid]
    if stale:
        log(f"purge de {len(stale)} job(s) terminé(s) : {stale}")


def start_chat(user_text, image_b64=None):
    _purge_jobs()
    if not llama_running():
        ok, msg = start_llama()
        if not ok:
            return None, msg
    with job_counter_lock:
        job_id = f"job{job_counter[0]}"
        job_counter[0] += 1
    with jobs_lock:
        jobs[job_id] = {"done": False, "text": "", "error": None, "finished_at": None}
    t = threading.Thread(target=run_chat_job, args=(job_id, user_text, image_b64), daemon=True)
    t.start()
    log(f"[chat] job {job_id} démarré ({len(user_text)} chars, image={'oui' if image_b64 else 'non'})")
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
    server_version = "Aiko/1.1"
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        elif isinstance(body, str):
            body = body.encode()
        try:
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass  # client parti — jamais fatal

    def _read_body(self):
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except (TypeError, ValueError):
            length = 0
        if length <= 0:
            return {}
        if length > MAX_BODY_BYTES:
            return {"_too_large": True}
        try:
            return json.loads(self.rfile.read(length).decode())
        except Exception:
            return {}

    # ── Routes GET ──
    def _route_get(self):
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
                # Job inconnu → 404 JSON propre (jamais d'exception)
                self._send(404, {"done": True, "text": "", "error": "job inconnu"})
            else:
                self._send(200, {"done": job["done"], "text": job["text"], "error": job["error"]})
        elif path == "/api/palette":
            self._send(200, get_palette())
        else:
            self._send(404, {"ok": False, "error": "not found"})

    # ── Routes POST ──
    def _route_post(self):
        path = self.path.split("?")[0]
        body = self._read_body()
        if body.get("_too_large"):
            self._send(413, {"ok": False, "error": "body trop volumineux"})
            return
        if path == "/api/model/start":
            ok, msg = start_llama()
            self._send(200, {"ok": ok, "msg": msg})
        elif path == "/api/model/stop":
            stop_llama()
            self._send(200, {"ok": True})
        elif path == "/api/chat":
            text = str(body.get("message") or "").strip()
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
            name = str(body.get("name") or f"session-{int(time.time())}")
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
            self._send(404, {"ok": False, "error": "not found"})

    # ── Filet de sécurité : une exception ici ne tue JAMAIS le serveur ──
    def do_GET(self):
        try:
            self._route_get()
        except Exception:
            log(f"GET {self.path} → exception :\n{traceback.format_exc()}")
            try:
                self._send(500, {"ok": False, "error": "internal error"})
            except Exception:
                pass

    def do_POST(self):
        try:
            self._route_post()
        except Exception:
            log(f"POST {self.path} → exception :\n{traceback.format_exc()}")
            try:
                self._send(500, {"ok": False, "error": "internal error"})
            except Exception:
                pass


# ─── Main ───────────────────────────────────────────────────

def shutdown_server():
    """Arrêt propre : llama-server tué AVANT l'exit (aucun orphelin)."""
    log("shutdown : arrêt de llama-server…")
    stop_llama()
    log("bye")
    os._exit(0)


def _signal_shutdown(signum, frame):
    """SIGTERM/SIGINT → même arrêt propre que /api/close.
    Cause racine du crash silencieux : server.py tué par un signal laissait
    llama-server (start_new_session) orphelin, VRAM bloquée, chat « mort ».
    stop_llama tourne dans un thread dédié (pas de lock dans un handler de
    signal → pas de deadlock)."""
    log(f"signal {signum} reçu — arrêt propre")
    t = threading.Thread(target=stop_llama, daemon=True)
    t.start()
    t.join(timeout=6)
    os._exit(128 + signum)


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    request_queue_size = 128  # pics de polls QML (150 ms) pendant une vision


def main():
    global PORT
    if "--port" in sys.argv:
        try:
            PORT = int(sys.argv[sys.argv.index("--port") + 1])
        except (IndexError, ValueError):
            pass
    signal.signal(signal.SIGTERM, _signal_shutdown)
    signal.signal(signal.SIGINT, _signal_shutdown)
    # Verrouille le port si déjà occupé → un serveur aiko tourne déjà
    try:
        srv = Server(("127.0.0.1", PORT), Handler)
    except OSError:
        print(f"Aiko déjà lancé sur le port {PORT}", flush=True)
        sys.exit(0)
    log(f"Aiko ready on http://127.0.0.1:{PORT}")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        _signal_shutdown(signal.SIGINT, None)


if __name__ == "__main__":
    main()
