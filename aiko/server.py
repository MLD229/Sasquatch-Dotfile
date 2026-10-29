#!/usr/bin/env python3
"""server.py — backend HTTP de 愛子 (aiko). Port 8791.

Responsabilités :
  - chatter avec llama-server en streaming (NDJSON, token par token) ;
  - porter le CYCLE DE VIE du modèle : rien au démarrage, chargé au 1er
    message, tué à la fermeture de la sidebar ou après inactivité ;
  - garder l'historique UNIQUEMENT EN RAM (aucun fichier d'état) ;
  - mémoriser UNIQUEMENT la préférence de modèle (~/.local/state/aiko/prefs.json) ;
  - ne JAMAIS exécuter une commande proposée par le modèle.

Endpoints
  GET  /api/health            → vivant ? (empreinte "backend": "aiko")
  GET  /api/state             → état moteur, modèle, préférence, VRAM, tok/s
  GET  /api/palette           → palette lue dans cc/qml/Palette.qml
  GET  /api/context           → digest statique du dotfile
  POST /api/chat              → NDJSON streamé (status/ready/token/done/error)
  POST /api/stop              → interrompt la génération en cours
  POST /api/new               → vide l'historique (RAM)
  POST /api/model             → "rapide" | "best" (persiste + tue le process)
  POST /api/shutdown          → tue le modèle, jette l'historique, s'arrête

Une seule instance à la fois : verrou flock $XDG_RUNTIME_DIR/aiko/backend.lock.
"""

from __future__ import annotations

import fcntl
import json
import os
import re
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import llm  # noqa: E402

HERE = os.path.dirname(os.path.realpath(__file__))
CFG = llm.load_models()


def _envint(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, "") or default)
    except ValueError:
        return default


PORT = _envint("AIKO_PORT", int(CFG.get("backend_port", 8791)))
PALETTE_CANDIDATES = [
    os.path.join(os.path.dirname(HERE), "cc", "qml", "Palette.qml"),
    os.path.expanduser("~/.config/cc/qml/Palette.qml"),
]
IDLE_SECONDS = _envint("AIKO_IDLE_SEC", int(CFG.get("idle_seconds", 300)))
HISTORY_MAX_CHARS = _envint("AIKO_HIST_MAX", int(CFG.get("history_max_chars", 6000)))
HISTORY_MAX_TURNS = int(CFG.get("history_max_turns", 8))
# Verrou d'instance unique : deux backends = port 8791 pris + deux vies pour
# le même domaine. Le fichier vit dans XDG_RUNTIME_DIR (nettoyé au logout).
LOCK_PATH = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR") or os.path.expanduser("~/.cache"),
    "aiko", "backend.lock")
LOCK_FD: int | None = None


def log(*a):
    print("[aiko]", *a, flush=True)


def notify(msg: str) -> None:
    """Notification utilisateur (best-effort, jamais bloquante)."""
    try:
        subprocess.run(["notify-send", "-t", "5000", "愛子 (aiko)", msg],
                       timeout=3, capture_output=True)
    except Exception:
        pass


def acquire_single_instance() -> bool:
    """Verrou exclusif non bloquant. False si un backend tourne déjà."""
    global LOCK_FD
    try:
        os.makedirs(os.path.dirname(LOCK_PATH), exist_ok=True)
        fd = os.open(LOCK_PATH, os.O_RDWR | os.O_CREAT, 0o600)
    except OSError as exc:
        log(f"verrou impossible ({LOCK_PATH}) : {exc} — on continue sans verrou")
        return True
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        os.close(fd)
        return False
    os.ftruncate(fd, 0)
    os.write(fd, f"{os.getpid()}\n".encode())
    LOCK_FD = fd          # gardé ouvert pour la vie du process
    return True


MANAGER = llm.LlamaManager(CFG, log=log)

# Préférence de modèle relue au démarrage (préférence ≠ mémoire : le chat ne
# survit pas, ce choix-là oui). Jamais d'exception ici : repli sur le défaut.
PREF_PROFILE, PREF_NOTE = llm.resolve_profile(CFG)

SYSTEM_PROMPT = """Tu es 愛子 (Aiko), l'assistante locale du dotfile Hyprland de momo (Arch Linux, Hyprland, kitty, fish, waybar, mako, quickshell).
Règles :
- Réponds en français, court et direct : 5 lignes max sauf demande explicite.
- Toute commande shell va dans UN bloc ```bash``` (une commande par bloc, sans "$").
  Tu ne l'exécutes JAMAIS : momo la copie lui-même.
- Signale quand une commande est risquée (sudo, rm, redirection vers un fichier système).
- Hors sujet dotfile : réponds brièvement quand même, sans prétendre avoir accès au web.
- Tu n'as aucune mémoire entre deux sessions : ne promets pas de te souvenir.
- Le contexte est petit (4k) : pas de réponse-fleuve."""

CONTEXT_DIGEST = """Contexte dotfile (résumé statique, PAS une lecture récursive) :
- ~/.config/hypr/        Hyprland : keybinds.conf, conf.d/rules.conf, conf.d/blur.conf
- ~/.config/kitty/       terminal kitty (kitty.conf)
- ~/.config/fish/        shell fish (config.fish)
- ~/.config/waybar/      barre waybar (config + style.css)
- ~/.config/mako/        notifications mako (config)
- ~/.config/cc/sidebar/  slide bar quickshell (shell.qml + server.py, Super+U)
- ~/.config/aiko/        cette sidebar (shell.qml + server.py, Super+N)
- ~/.config/settings/    panneau réglages quickshell (Super+I)
Source : dépôt ~/Downloads/Sasquatch-Dotfile (mêmes fichiers)."""

# ── Historique : RAM uniquement, perdu avec le process. ──────────────────
HISTORY: list[dict] = []
HIST_LOCK = threading.Lock()
GEN_LOCK = threading.Lock()
LAST_STATS = {"tok_s": None, "tokens": 0, "first_token_ms": None}


def history_reset() -> int:
    with HIST_LOCK:
        n = len(HISTORY)
        HISTORY.clear()
    return n


def history_snapshot(text: str, inject: bool) -> list[dict]:
    """Ajoute le message utilisateur et renvoie system + historique borné."""
    with HIST_LOCK:
        HISTORY.append({"role": "user", "content": text})
        turns = HISTORY[-(HISTORY_MAX_TURNS * 2):]
        kept, total = [], 0
        for msg in reversed(turns):
            total += len(msg["content"])
            if total > HISTORY_MAX_CHARS:
                break
            kept.append(msg)
        kept.reverse()
    system = SYSTEM_PROMPT + ("\n\n" + CONTEXT_DIGEST if inject else "")
    return [{"role": "system", "content": system}] + kept


def history_append(role: str, content: str) -> None:
    with HIST_LOCK:
        HISTORY.append({"role": role, "content": content})


def read_palette() -> dict:
    for path in PALETTE_CANDIDATES:
        if not os.path.isfile(path):
            continue
        try:
            with open(path, "r", encoding="utf-8") as fh:
                src = fh.read()
        except OSError:
            continue
        out = {}
        for key, val in re.findall(
                r'property\s+color\s+(\w+)\s*:\s*"(#[0-9a-fA-F]+)"', src):
            out[key] = val
        if out:
            return out
    return {}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "aiko/2.0"

    def log_message(self, format, *args):  # noqa: A002 - signature de la base
        if os.environ.get("AIKO_DEBUG") == "1":
            log("http", format % args)

    # ── helpers ──────────────────────────────────────────────────────────
    def _json(self, obj, code=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _body(self) -> dict:
        try:
            n = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(n) if n else b"{}"
            return json.loads(raw.decode("utf-8") or "{}")
        except Exception as exc:                        # noqa: BLE001
            if os.environ.get("AIKO_DEBUG") == "1":
                log("corps de requête invalide :", exc)
            return {}

    def _stream_start(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        self._closed = False

    def _emit(self, obj) -> bool:
        if self._closed:
            return False
        data = (json.dumps(obj, ensure_ascii=False) + "\n").encode("utf-8")
        try:
            self.wfile.write(b"%x\r\n" % len(data) + data + b"\r\n")
            self.wfile.flush()
            return True
        except (BrokenPipeError, ConnectionResetError):
            self._closed = True
            MANAGER.cancel.set()
            return False

    def _stream_end(self):
        if self._closed:
            return
        try:
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
        except Exception:
            pass

    # ── GET ──────────────────────────────────────────────────────────────
    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/api/health", "/health"):
            st = MANAGER.status()
            return self._json({"ok": True, "backend": "aiko", "pid": os.getpid(),
                               "engine": st["state"], "model": st["profile"],
                               "llama_alive": st["alive"]})
        if path == "/api/state":
            st = MANAGER.status()
            with HIST_LOCK:
                hlen = len(HISTORY)
            return self._json({**st, "history_len": hlen,
                               "tok_s": LAST_STATS["tok_s"],
                               "tokens": LAST_STATS["tokens"],
                               "first_token_ms": LAST_STATS["first_token_ms"],
                               "default": CFG.get("default"),
                               "profiles": {k: v.get("label")
                                            for k, v in CFG["profiles"].items()},
                               "profile_pref": PREF_PROFILE,
                               "pref_note": PREF_NOTE,
                               "prefs_file": llm.PREFS_FILE,
                               "idle_seconds": MANAGER.idle_seconds,
                               "binary": MANAGER.binary(),
                               "lock": LOCK_PATH})
        if path == "/api/palette":
            return self._json(read_palette() or {"error": "palette introuvable"})
        if path == "/api/context":
            return self._json({"text": CONTEXT_DIGEST,
                               "bytes": len(CONTEXT_DIGEST.encode())})
        if path in ("/", "/index.html"):
            return self._json({"ok": True, "hint": "utiliser les endpoints /api/*"})
        return self._json({"ok": False, "error": "not found"}, 404)

    # ── POST ─────────────────────────────────────────────────────────────
    def do_POST(self):
        path = self.path.split("?")[0]
        body = self._body()
        if path == "/api/chat":
            return self.chat(body)
        if path == "/api/stop":
            MANAGER.cancel.set()
            log("stop demandé")
            return self._json({"ok": True, "stopped": True})
        if path == "/api/new":
            n = history_reset()
            LAST_STATS.update({"tok_s": None, "tokens": 0, "first_token_ms": None})
            return self._json({"ok": True, "dropped": n})
        if path == "/api/model":
            profile = str(body.get("profile") or "").strip()
            if profile not in CFG["profiles"]:
                return self._json({"ok": False, "error": "profil inconnu"}, 400)
            if GEN_LOCK.locked():
                return self._json({"ok": False,
                                   "error": "génération en cours — Stop d'abord"}, 409)
            # 1. mémoriser la préférence (avant de tuer : même si le kill échoue,
            #    le choix de momo est retenu à la réouverture) ;
            persisted = llm.save_profile_pref(CFG, profile)
            # 2. libérer la VRAM ; le prochain message recharge le bon modèle.
            killed = MANAGER.stop()
            global PREF_PROFILE, PREF_NOTE
            PREF_PROFILE, PREF_NOTE = profile, ""
            log(f"profil → {profile} (persisté={persisted} · {llm.PREFS_FILE} · "
                f"llama tué={killed['how']})")
            return self._json({"ok": True, "profile": profile,
                               "label": CFG["profiles"][profile].get("label"),
                               "persisted": persisted,
                               "prefs_file": llm.PREFS_FILE,
                               "killed": killed})
        if path == "/api/shutdown":
            return self.shutdown()
        return self._json({"ok": False, "error": "not found"}, 404)

    def shutdown(self):
        MANAGER.cancel.set()
        killed = MANAGER.stop()
        dropped = history_reset()
        LAST_STATS.update({"tok_s": None, "tokens": 0, "first_token_ms": None})
        log(f"shutdown — llama pgrep={killed['pgrep_count']} · "
            f"historique jeté={dropped} messages · "
            f"préférence conservée={PREF_PROFILE}")
        self._json({"ok": True, "history_dropped": dropped,
                    "profile_pref": PREF_PROFILE, **killed})
        # Le backend s'arrête aussi : à la fermeture il ne reste RIEN.
        threading.Thread(target=_delayed_exit, args=(0.3,), daemon=True).start()

    def chat(self, body):
        text = (body.get("text") or "").strip()
        if not text:
            return self._json({"ok": False, "error": "message vide"}, 400)
        # Pas de profil dans la requête → la PRÉFÉRENCE retenue au démarrage.
        profile = body.get("profile") or PREF_PROFILE
        inject = bool(body.get("inject_context"))
        if profile and profile not in CFG["profiles"]:
            return self._json({"ok": False, "error": "profil inconnu"}, 400)
        if not GEN_LOCK.acquire(blocking=False):
            return self._json({"ok": False,
                               "error": "une génération est déjà en cours"}, 409)
        try:
            messages = history_snapshot(text, inject)
            self._stream_start()
            t0 = time.monotonic()
            if MANAGER.state != "ready":
                if not self._emit({"e": "status", "state": "loading",
                                   "text": "chargement du modèle…"}):
                    return
            first_ms = None
            acc, ntok = [], 0
            try:
                for delta in MANAGER.generate(messages, profile=profile):
                    if first_ms is None:
                        first_ms = int((time.monotonic() - t0) * 1000)
                        LAST_STATS["first_token_ms"] = first_ms
                        prof = MANAGER.profile or profile or CFG["default"]
                        self._emit({"e": "ready", "profile": prof,
                                    "label": CFG["profiles"].get(prof, {}).get("label"),
                                    "cold_start_ms": MANAGER.cold_start_ms,
                                    "first_token_ms": first_ms,
                                    "vram_mib": llm.vram_used_mib()})
                    acc.append(delta)
                    ntok += 1
                    if not self._emit({"e": "token", "t": delta}):
                        break
            except llm.ModelMissing as exc:
                self._emit({"e": "error", "message": str(exc)})
                return
            except Exception as exc:                      # noqa: BLE001
                log("erreur génération :", exc)
                self._emit({"e": "error", "message": str(exc)})
                return

            answer = "".join(acc)
            if answer:
                history_append("assistant", answer)
            tail_ms = (time.monotonic() - t0) * 1000 - (first_ms or 0)
            elapsed = max(1e-3, tail_ms / 1000.0)
            tok_s = round(ntok / elapsed, 1) if ntok else 0.0
            LAST_STATS.update({"tok_s": tok_s, "tokens": ntok})
            self._emit({"e": "done", "tokens": ntok, "tok_s": tok_s,
                        "first_token_ms": first_ms,
                        "cold_start_ms": MANAGER.cold_start_ms,
                        "stopped": MANAGER.cancel.is_set(),
                        "elapsed_ms": int((time.monotonic() - t0) * 1000)})
            self._stream_end()
        finally:
            GEN_LOCK.release()


def _delayed_exit(delay: float):
    time.sleep(delay)
    log("backend arrêté (plus rien ne tourne)")
    os._exit(0)


def idle_watchdog():
    """Tue llama-server après inactivité ; le backend reste léger."""
    while True:
        time.sleep(2.0)
        try:
            MANAGER.idle_stop()
        except Exception as exc:                          # noqa: BLE001
            log("watchdog :", exc)


def main():
    log(f"backend {PORT} — llama-server : {MANAGER.binary() or 'ABSENT'}")
    if not MANAGER.binary():
        log("  → build Vulkan/CUDA requis (80 tok/s) : bash "
            + os.path.join(HERE, "installer.sh"))
        log("  → paquet Arch extra/llama-cpp = CPU seul (12,8 tok/s)")
    log(f"  inactivité {IDLE_SECONDS}s · modèles dans {llm.MODELS_DIR}")
    log(f"  préférence modèle : {PREF_PROFILE} ({llm.PREFS_FILE})"
        + (f" — {PREF_NOTE}" if PREF_NOTE else ""))
    if not acquire_single_instance():
        msg = (f"un backend aiko tourne déjà (verrou {LOCK_PATH}) — "
               f"celui-ci s'arrête, rien n'est cassé")
        log(msg)
        return 0
    try:
        srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    except OSError as exc:
        owner = llm.port_owner(PORT) or "un autre programme"
        msg = (f"port {PORT} déjà occupé par {owner} — aiko ne démarre pas "
               f"({exc.strerror or exc})")
        log(msg)
        log(f"  → libérer le port : ss -ltnp | grep :{PORT}")
        notify(msg)
        return 2
    srv.daemon_threads = True
    threading.Thread(target=idle_watchdog, daemon=True).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        MANAGER.stop()


if __name__ == "__main__":
    sys.exit(main())
