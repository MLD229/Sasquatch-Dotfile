#!/usr/bin/env python3
"""lifecycle_test.py — preuve du cycle de vie éphémère de 愛子.

Vérifie, sur le vrai backend + le vrai llama-server :
  1. au repos            : 0 process llama-server, VRAM au niveau de base
  2. 1er message         : llama-server démarre, /health OK AVANT le 1er token
  3. streaming           : les tokens arrivent par morceaux (>= 5 instants)
  4. fermeture (shutdown): llama-server tué → pgrep = 0, VRAM rendue,
                           backend sorti, historique jeté
  5. inactivité          : modèle déchargé tout seul, backend toujours léger
  6. Stop                : la génération s'arrête, le modèle reste chargé
  7. persistance         : SEULE la préférence de modèle (~/.local/state/aiko/
                           prefs.json) est écrite ; aucun historique, aucun état
                           de conversation (l'historique meurt avec le process).

Usage :  python3 tests/lifecycle_test.py            (test complet)
         python3 tests/lifecycle_test.py --quick    (sans les tests 5 et 6)
Sortie : une ligne PASS/FAIL par point + code retour 0 si tout passe.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.realpath(__file__))
ROOT = os.path.dirname(HERE)
PORT = int(os.environ.get("AIKO_PORT", 8791))
LLAMA_PORT = 8792
MARKER = "aiko-ephemere"
BASE = f"http://127.0.0.1:{PORT}"
STATE_DIR = os.path.expanduser("~/.local/state/aiko")
PREFS_FILE = os.path.join(STATE_DIR, "prefs.json")
# Clés tolérées dans prefs.json : uniquement la préférence de modèle.
PREFS_ALLOWED = {"model", "updated"}

RESULTS: list[tuple[bool, str]] = []


def persisted_files() -> list[str]:
    try:
        return sorted(os.listdir(STATE_DIR))
    except OSError:
        return []


def persistence_shape() -> tuple[bool, str]:
    """Vrai si l'état disque ne contient QUE la préférence de modèle.

    Autorisé : rien du tout, ou exactement prefs.json avec la clé `model`.
    Refusé : tout autre fichier (historique, session, cache de conversation).
    """
    files = persisted_files()
    extra = [f for f in files if f != "prefs.json"]
    if extra:
        return False, f"fichiers inattendus dans {STATE_DIR} : {extra}"
    if "prefs.json" not in files:
        return True, "prefs.json absent (premier lancement) — rien d'autre"
    try:
        with open(PREFS_FILE, "r", encoding="utf-8") as fh:
            obj = json.load(fh)
    except (OSError, ValueError) as exc:
        return False, f"prefs.json illisible : {exc}"
    if not isinstance(obj, dict) or not set(obj) <= PREFS_ALLOWED:
        return False, f"clés inattendues dans prefs.json : {obj!r}"
    return True, f"prefs.json = {obj} (préférence seule)"


def check(ok: bool, label: str, detail: str = "") -> bool:
    RESULTS.append((bool(ok), label))
    print(f"  [{'PASS' if ok else 'FAIL'}] {label}" + (f" — {detail}" if detail else ""))
    return bool(ok)


def pgrep_marker() -> int:
    r = subprocess.run(["pgrep", "-fc", f"[{MARKER[0]}]{MARKER[1:]}"],
                       capture_output=True, text=True)
    return int(r.stdout.strip() or 0)


def llama_pids() -> list[int]:
    r = subprocess.run(["pgrep", "-x", "llama-server"], capture_output=True, text=True)
    out = []
    for line in r.stdout.split():
        try:
            out.append(int(line))
        except ValueError:
            pass
    return out


def alive_pids() -> list[int]:
    """PIDs vivants (un zombie <defunct> ne compte pas comme un process lourd)."""
    live = []
    for pid in llama_pids():
        try:
            with open(f"/proc/{pid}/stat", "r", encoding="utf-8") as fh:
                state = fh.read().split()[2]
        except OSError:
            continue
        if state != "Z":
            live.append(pid)
    return live


def vram() -> int | None:
    r = subprocess.run(["nvidia-smi", "--query-gpu=memory.used",
                        "--format=csv,noheader,nounits"], capture_output=True, text=True)
    v = r.stdout.strip().splitlines()
    return int(v[0]) if v and v[0].strip().isdigit() else None


def get(path: str, timeout: float = 3.0):
    with urllib.request.urlopen(BASE + path, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def post(path: str, body: dict | None = None, timeout: float = 10.0):
    data = json.dumps(body or {}).encode()
    req = urllib.request.Request(BASE + path, data=data,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def wait_http(path: str, timeout: float = 10.0) -> bool:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            get(path, timeout=0.5)
            return True
        except Exception:
            time.sleep(0.1)
    return False


def wait_gone(pred, timeout: float = 8.0) -> bool:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if not pred():
            return True
        time.sleep(0.15)
    return not pred()


def llama_health() -> bool:
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{LLAMA_PORT}/health",
                                    timeout=1.0) as resp:
            return b'"ok"' in resp.read()
    except Exception:
        return False


class Backend:
    """Lance server.py comme le fait aiko.sh (process indépendant)."""

    def __init__(self, idle_seconds: int = 300):
        self.env = dict(os.environ, AIKO_IDLE_SEC=str(idle_seconds))
        self.proc = None

    def start(self):
        self.proc = subprocess.Popen([sys.executable, "-u",
                                      os.path.join(ROOT, "server.py")],
                                     env=self.env, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL)
        if not wait_http("/api/health", 10):
            raise SystemExit("backend injoignable")
        return self

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()


def stream_chat(text: str, stop_after: float | None = None) -> dict:
    """Consomme le NDJSON et horodate chaque événement."""
    body = json.dumps({"text": text, "profile": "rapide"}).encode()
    req = urllib.request.Request(BASE + "/api/chat", data=body,
                                 headers={"Content-Type": "application/json"})
    t0 = time.monotonic()
    events, tokens, first_token_at, ready_at, loading_at = [], 0, None, None, None
    stopped_sent = False
    with urllib.request.urlopen(req, timeout=180) as resp:
        while True:
            line = resp.readline()
            if not line:
                break
            try:
                obj = json.loads(line.decode())
            except Exception:
                continue
            events.append(obj)
            kind = obj.get("e")
            if kind == "status":
                loading_at = time.monotonic() - t0
            elif kind == "ready":
                ready_at = time.monotonic() - t0
            elif kind == "token":
                tokens += 1
                if first_token_at is None:
                    first_token_at = time.monotonic() - t0
            if stop_after is not None and not stopped_sent \
                    and time.monotonic() - t0 > stop_after:
                post("/api/stop", {})
                stopped_sent = True
            if kind in ("done", "error"):
                break
    total = time.monotonic() - t0
    return {"events": events, "tokens": tokens, "first_token_at": first_token_at,
            "ready_at": ready_at, "loading_at": loading_at, "total": total,
            "done": next((e for e in events if e.get("e") == "done"), {}),
            "error": next((e for e in events if e.get("e") == "error"), None)}


def health_window(port: int, seconds: float) -> list[tuple[float, bool]]:
    """Échantillonne /health du llama-server pendant la génération."""
    samples = []
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        samples.append((round(time.monotonic(), 2), llama_health()))
        time.sleep(0.2)
    return samples


def main():
    quick = "--quick" in sys.argv
    print("=== 愛子 — test de cycle de vie éphémère ===")
    for pid in alive_pids():
        print(f"  (nettoyage) llama-server {pid} tué")
        try:
            os.kill(pid, 15)
        except OSError:
            pass
    time.sleep(1)
    subprocess.run(["pkill", "-f", "[a]iko/server.py"], capture_output=True)

    base_vram = vram()
    print(f"VRAM de base : {base_vram} MiB")

    # ── 1. rien ne tourne avant ouverture ────────────────────────────────
    print("\n1) Au repos")
    check(pgrep_marker() == 0, "0 process llama-server d'aiko",
          f"pgrep={pgrep_marker()}")
    ok_state, detail = persistence_shape()
    check(ok_state, "seule la préférence de modèle est persistée (au plus)", detail)

    be = Backend(idle_seconds=300).start()
    st = get("/api/state")
    check(st["state"] == "idle" and not st["alive"],
          "backend ouvert sans modèle chargé", f"state={st['state']}")

    # ── 2. premier message ───────────────────────────────────────────────
    print("\n2) Premier message (chargement à la demande)")
    res = stream_chat("Réponds par une seule commande bash : recharger Hyprland.")
    ev = res["events"]
    check(ev and ev[0].get("e") == "status", "événement « chargement du modèle… » émis")
    ready = next((e for e in ev if e.get("e") == "ready"), None)
    check(ready is not None, "événement « ready » reçu",
          f"cold_start={ready and ready.get('cold_start_ms')}ms")
    check(pgrep_marker() == 1, "exactement 1 llama-server après le 1er message",
          f"pgrep={pgrep_marker()} pids={alive_pids()}")
    check(llama_health(), f"/health OK sur {LLAMA_PORT} avant la 1re génération")
    check(res["first_token_at"] is not None,
          "premier token mesuré",
          f"{res['first_token_at']:.2f}s après la requête")
    check(res["tokens"] >= 5, "streaming token par token (>=5 fragments)",
          f"{res['tokens']} fragments, 1er à {res['first_token_at']:.2f}s, "
          f"fin à {res['total']:.2f}s")
    check(res["error"] is None, "aucune erreur")
    print(f"     tok/s={res['done'].get('tok_s')} · "
          f"cold_start={res['done'].get('cold_start_ms')}ms · "
          f"1er_token={res['done'].get('first_token_ms')}ms")

    # ── 3. fin de génération : le modèle RESTE chargé ───────────────────
    print("\n3) Après la réponse")
    check(pgrep_marker() == 1, "modèle toujours chargé (pas de déchargement auto)",
          f"pid={alive_pids()}")
    st = get("/api/state")
    print(f"     historique RAM : {st['history_len']} messages · "
          f"VRAM du modèle : {st.get('vram_mib')} MiB")

    # ── 6. Stop (fait avant shutdown pour garder le modèle) ─────────────
    if not quick:
        print("\n6) Bouton Stop en pleine génération")
        res = stream_chat("Écris un paragraphe de 300 mots sur l'histoire de "
                          "Linux.", stop_after=1.2)
        done = res["done"]
        check(done.get("stopped") is True, "le flux se termine avec stopped=true",
              f"{res['tokens']} tokens avant l'arrêt")
        check(pgrep_marker() == 1, "Stop garde le modèle chargé (pas un déchargement)")

    # ── 4. fermeture ────────────────────────────────────────────────────
    print("\n4) Fermeture (POST /api/shutdown)")
    t0 = time.monotonic()
    res = post("/api/shutdown")
    check(res.get("ok") is True, "shutdown accepté",
          f"how={res.get('how')} historique_jeté={res.get('history_dropped')}")
    ok = wait_gone(lambda: pgrep_marker() > 0, 8)
    delay = time.monotonic() - t0
    check(ok, "pgrep llama-server = 0 après fermeture",
          f"en {delay:.2f}s · pgrep={pgrep_marker()} · pids={alive_pids()}")
    v = vram()
    check(v is None or base_vram is None or v <= base_vram + 40,
          "VRAM rendue", f"{base_vram} MiB → {v} MiB")
    check(wait_gone(lambda: _http_ok("/api/health"), 5),
          "backend sorti aussi (plus rien ne tourne)", f"port {PORT} fermé")
    check(be.proc.poll() is not None, "le process backend a bien quitté",
          f"code={be.proc.poll()}")

    # ── 5. inactivité ──────────────────────────────────────────────────
    if not quick:
        print("\n5) Inactivité (AIKO_IDLE_SEC=6)")
        be2 = Backend(idle_seconds=6).start()
        res = stream_chat("Dis juste : ok")
        check(pgrep_marker() == 1, "modèle chargé après le message")
        print("     attente de 12 s sans message…")
        gone = wait_gone(lambda: pgrep_marker() > 0, 20)
        check(gone, "modèle déchargé tout seul après inactivité",
              f"pgrep={pgrep_marker()}")
        check(_http_ok("/api/health"), "le backend reste vivant (léger)")
        st = get("/api/state")
        check(st["state"] == "idle", "état revenu à idle", f"state={st['state']}")
        post("/api/shutdown")
        be2.stop()
    else:
        be.stop()

    # ── 7. persistance : la préférence seule ────────────────────────────
    print("\n7) Persistance : la préférence de modèle, rien d'autre")
    ok_state, detail = persistence_shape()
    check(ok_state, "aucun historique/état de conversation sur disque", detail)
    leftovers = [p for p in ("history.json", "state.json", "conversation.json")
                 if os.path.exists(os.path.join(ROOT, p))]
    check(not leftovers, "aucun fichier d'état/historique dans le dossier aiko",
          str(leftovers))
    check(pgrep_marker() == 0, "0 process à la fin")

    failed = [lbl for ok, lbl in RESULTS if not ok]
    print(f"\n=== {len(RESULTS) - len(failed)}/{len(RESULTS)} PASS ===")
    if failed:
        print("ÉCHECS :")
        for lbl in failed:
            print("  -", lbl)
        return 1
    return 0


def _http_ok(path: str) -> bool:
    try:
        get(path, timeout=0.6)
        return True
    except Exception:
        return False


if __name__ == "__main__":
    sys.exit(main())
