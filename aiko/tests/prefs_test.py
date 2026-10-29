#!/usr/bin/env python3
"""prefs_test.py — preuve : le modèle choisi est rechargé à la réouverture.

Ce que ce test prouve, sur le vrai backend + le vrai llama-server :

  1. au démarrage, le backend relit ~/.local/state/aiko/prefs.json ;
  2. changer de modèle dans l'UI (POST /api/model) écrit prefs.json
     IMMÉDIATEMENT et tue le llama-server en cours ;
  3. on ferme (POST /api/shutdown) : 0 process, VRAM rendue ;
  4. on rouvre : /api/state rapporte la préférence mémorisée (profile_pref)
     sans qu'aucun modèle ne soit chargé ;
  5. un message SANS profil charge bien ce modèle-là : cmdline du
     llama-server vivant + /api/health → model == préférence.

La préférence d'origine est restaurée à la fin (le test ne laisse pas momo
en 7B s'il était en 3B).

Usage : python3 tests/prefs_test.py
Sortie : une ligne PASS/FAIL par point + code retour 0 si tout passe.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.realpath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)
import llm  # noqa: E402

PORT = int(os.environ.get("AIKO_PORT", 8791))
BASE = f"http://127.0.0.1:{PORT}"
MODELS = llm.load_models()
PREFS_FILE = llm.PREFS_FILE
STATE_DIR = llm.STATE_DIR
MARKER = llm.MARKER

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


def wait_http(path: str, seconds: float = 10.0) -> bool:
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        try:
            get(path, timeout=0.5)
            return True
        except Exception:
            time.sleep(0.1)
    return False


def wait_gone(pred, seconds: float = 10.0) -> bool:
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if not pred():
            return True
        time.sleep(0.15)
    return not pred()


# ── Process ───────────────────────────────────────────────────────────────
def marker_pids() -> list[int]:
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


def cmdline(pid: int) -> str:
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as fh:
            return fh.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def live_model_file(pids: list[int]) -> str:
    """Nom du GGUF réellement chargé par le llama-server vivant."""
    for pid in pids:
        line = cmdline(pid)
        if "-m " in line:
            parts = line.split("-m ", 1)[1].split()
            if parts:
                return os.path.basename(parts[0])
    return ""


class Backend:
    def __init__(self):
        self.proc = None

    def start(self):
        self.proc = subprocess.Popen([sys.executable, "-u",
                                      os.path.join(ROOT, "server.py")],
                                     stdout=subprocess.DEVNULL,
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


def chat(text: str, profile: str | None = None, timeout: float = 180.0) -> dict:
    """Envoie un message ; renvoie {events, tokens, done, error}."""
    body = {"text": text}
    if profile:
        body["profile"] = profile
    req = urllib.request.Request(BASE + "/api/chat", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    events, tokens = [], 0
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        for raw in resp:
            try:
                obj = json.loads(raw.decode())
            except Exception:
                continue
            events.append(obj)
            if obj.get("e") == "token":
                tokens += 1
            if obj.get("e") in ("done", "error"):
                break
    return {
        "events": events,
        "tokens": tokens,
        "ready": next((e for e in events if e.get("e") == "ready"), None),
        "done": next((e for e in events if e.get("e") == "done"), {}),
        "error": next((e for e in events if e.get("e") == "error"), None),
    }


def main() -> int:
    print("=== 愛子 — mémoire du modèle choisi (prefs.json) ===")

    # ── Préparation : terrain propre + sauvegarde de la préférence ────────
    subprocess.run(["pkill", "-f", f"[a]iko/server.py"], capture_output=True)
    for pid in marker_pids():
        try:
            os.kill(pid, 15)
        except OSError:
            pass
    time.sleep(0.6)

    backup_raw = None
    if os.path.exists(PREFS_FILE):
        with open(PREFS_FILE, "r", encoding="utf-8") as fh:
            backup_raw = fh.read()

    current, _note = llm.resolve_profile(MODELS)
    target = "best" if current != "best" else "rapide"
    target_file = MODELS["profiles"][target]["file"]
    print(f"préférence actuelle : {current} · cible du test : {target} "
          f"({target_file})")
    if not os.path.isfile(os.path.join(llm.MODELS_DIR, target_file)):
        print(f"SKIP — GGUF absent : {os.path.join(llm.MODELS_DIR, target_file)}")
        return 0

    be = None
    be2 = None
    try:
        # ── 1. démarrage : la préférence est relue ────────────────────────
        print("\n1) Démarrage du backend")
        be = Backend().start()
        st = get("/api/state")
        check(st.get("profile_pref") == current,
              "préférence relue au démarrage", f"profile_pref={st.get('profile_pref')}")
        check(st.get("state") == "idle" and not st.get("alive"),
              "aucun modèle chargé au démarrage", f"state={st.get('state')}")

        # ── 2. changement de modèle : écriture immédiate + kill ───────────
        print(f"\n2) Changement vers « {target} » (POST /api/model)")
        res = post("/api/model", {"profile": target})
        check(res.get("ok") is True and res.get("profile") == target,
              "backend accepte le nouveau profil", f"réponse={res.get('profile')}")
        check(res.get("persisted") is True,
              "préférence écrite sur disque", f"fichier={res.get('prefs_file')}")

        on_disk = {}
        if os.path.exists(PREFS_FILE):
            with open(PREFS_FILE, "r", encoding="utf-8") as fh:
                on_disk = json.load(fh)
        check(on_disk.get("model") == target,
              f"{PREFS_FILE} contient model={target}", f"contenu={on_disk}")
        check(set(on_disk) <= {"model", "updated"},
              "prefs.json ne contient QUE la préférence (pas d'historique)",
              f"clés={sorted(on_disk)}")

        st = get("/api/state")
        check(st.get("profile_pref") == target,
              "état backend aligné sur la préférence", f"profile_pref={st.get('profile_pref')}")
        check(wait_gone(lambda: len(marker_pids()) > 0, 6),
              "llama-server tué par le changement de modèle", f"pgrep={len(marker_pids())}")

        # ── 3. fermeture ─────────────────────────────────────────────────
        print("\n3) Fermeture (POST /api/shutdown)")
        post("/api/shutdown")
        check(wait_gone(lambda: len(marker_pids()) > 0, 8),
              "plus aucun llama-server", f"pgrep={len(marker_pids())}")
        check(wait_gone(lambda: _http_ok("/api/health"), 5),
              "backend sorti (rien ne tourne)")
        be.stop()

        # ── 4. réouverture : la préférence est toujours là ────────────────
        print("\n4) Réouverture (nouveau process backend)")
        be2 = Backend().start()
        st = get("/api/state")
        check(st.get("profile_pref") == target,
              "le modèle choisi est mémorisé à la réouverture",
              f"profile_pref={st.get('profile_pref')} (prefs.json)")
        check(st.get("state") == "idle" and not st.get("alive"),
              "…et rien n'est chargé avant le 1er message", f"state={st.get('state')}")

        # ── 5. le modèle réellement chargé est bien celui-là ─────────────
        print(f"\n5) Message SANS profil explicite → doit charger {target}")
        res = chat("Réponds par un seul mot : ok")
        ready = res["ready"] or {}
        check(ready.get("profile") == target,
              "« ready » annonce le profil mémorisé",
              f"profile={ready.get('profile')} label={ready.get('label')} "
              f"cold_start={ready.get('cold_start_ms')} ms")
        check(live_model_file(marker_pids()) == target_file,
              "le GGUF réellement chargé est celui de la préférence",
              f"cmdline → {live_model_file(marker_pids())}")
        hl = get("/api/health")
        check(hl.get("model") == target and hl.get("llama_alive") is True,
              f"/api/health confirme model={target}",
              f"model={hl.get('model')} llama_alive={hl.get('llama_alive')}")
        check(res["error"] is None and res["tokens"] >= 1,
              "la génération a bien tourné", f"{res['tokens']} fragments")
    finally:
        # ── Nettoyage : fermer, restaurer la préférence d'origine ─────────
        for proc_be in (be, be2):
            try:
                if proc_be and proc_be.proc and proc_be.proc.poll() is None:
                    try:
                        post("/api/shutdown", timeout=5)
                    except Exception:
                        pass
                    time.sleep(0.5)
                    proc_be.stop()
            except Exception:
                pass
        for pid in marker_pids():
            try:
                os.kill(pid, 9)
            except OSError:
                pass
        if backup_raw is not None:
            with open(PREFS_FILE, "w", encoding="utf-8") as fh:
                fh.write(backup_raw)
            restored = json.loads(backup_raw).get("model")
        else:
            try:
                os.unlink(PREFS_FILE)
            except OSError:
                pass
            restored = MODELS.get("default")
        subprocess.run(["pkill", "-f", f"[a]iko/server.py"], capture_output=True)
        print(f"\n(nettoyage) préférence restaurée : {restored} "
              f"· llama-server restants : {len(marker_pids())}")

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
