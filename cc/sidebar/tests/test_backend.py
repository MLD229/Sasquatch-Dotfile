#!/usr/bin/env python3
"""test_backend.py — tests HEADLESS du backend sidebar (HTTP réel).

Ce qui est prouvé ici, sans aucun écran :
  * les endpoints todo / chrono / timer / alarme / modes répondent ;
  * la todo SURVIT au redémarrage du serveur (fichier d'état) ;
  * le timer CONTINUE sans client (aucune requête pendant 4 s) → l'événement
    de fin est bien enregistré côté backend ;
  * le timer survit aussi à un redémarrage du serveur en cours de route ;
  * les modes échouent proprement (Hyprland/mako/hyprsunset absents) au lieu
    de mentir ou de crasher ;
  * /api/palette renvoie EXACTEMENT les couleurs de ~/.config/cc/qml/Palette.qml.

Lancement : python3 tests/test_backend.py
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PORT = int(os.environ.get("TEST_PORT", "8797"))
BASE = "http://127.0.0.1:%d" % PORT
PALETTE_QML = os.path.expanduser("~/.config/cc/qml/Palette.qml")

PROC = None
TMP = tempfile.mkdtemp(prefix="sidebar-test-")


def req(method, path, body=None, timeout=6):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(BASE + path, data=data, method=method,
                               headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            return json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as exc:
        return {"ok": False, "http": exc.code, "raw": exc.read().decode()[:200]}


def get(path, **kw):
    return req("GET", path, **kw)


def post(path, body):
    return req("POST", path, body)


def start_server():
    global PROC
    env = dict(os.environ)
    env["XDG_STATE_HOME"] = TMP
    env["SASQUATCH_SIDEBAR_PORT"] = str(PORT)
    env["PYTHONUNBUFFERED"] = "1"
    PROC = subprocess.Popen([sys.executable, os.path.join(ROOT, "server.py")],
                            env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True)
    for _ in range(60):
        try:
            h = get("/api/health")
        except Exception:
            h = {}
        if h.get("ok"):
            return h
        time.sleep(0.1)
    out = PROC.stdout.read() if PROC.stdout else ""
    raise RuntimeError("serveur non démarré : %s" % out)


def stop_server():
    global PROC
    if PROC and PROC.poll() is None:
        PROC.terminate()
        try:
            PROC.wait(timeout=5)
        except subprocess.TimeoutExpired:
            PROC.kill()
    PROC = None


RESULTS = []


def check(label, cond, detail=""):
    RESULTS.append(bool(cond))
    print(("  OK   " if cond else "  FAIL ") + label + ((" — " + detail) if detail else ""))
    return bool(cond)


def main():
    print("état de test : %s" % TMP)
    h = start_server()
    print("serveur : %s" % json.dumps(h))

    # ── 1. todo ───────────────────────────────────────────────────────────
    print("\n[1] TODO — ajout / cases / suppression")
    a = post("/api/todo", {"action": "add", "text": "acheter du café", "prio": "high"})
    b = post("/api/todo", {"action": "add", "text": "réviser Quickshell"})
    check("2 tâches ajoutées", a.get("ok") and b.get("ok"))
    st = get("/api/state")
    check("compteurs justes", st["counts"] == {"total": 2, "remaining": 2, "done": 0},
          json.dumps(st["counts"]))
    tid = a["item"]["id"]
    post("/api/todo", {"action": "toggle", "id": tid})
    st = get("/api/state")
    done = [i for i in st["todo"] if i["done"]]
    check("coche → done=1", len(done) == 1 and done[0]["text"] == "acheter du café")
    check("priorité conservée", done[0]["prio"] == "high")
    check("compteur restant = 1", st["counts"]["remaining"] == 1,
          json.dumps(st["counts"]))
    post("/api/todo", {"action": "set_prio", "id": tid})
    check("priorité bascule", get("/api/state")["todo"][0]["prio"] == "normal")

    # ── 2. persistance après redémarrage ──────────────────────────────────
    print("\n[2] PERSISTANCE — kill du serveur puis relance")
    state_file = os.path.join(TMP, "sasquatch", "sidebar-state.json")
    check("fichier d'état écrit", os.path.exists(state_file), state_file)
    stop_server()
    time.sleep(0.3)
    start_server()
    st2 = get("/api/state")
    texts = sorted(i["text"] for i in st2["todo"])
    check("les 2 tâches ont survécu", texts == ["acheter du café", "réviser Quickshell"],
          json.dumps(texts))
    check("l'état coché a survécu",
          any(i["done"] for i in st2["todo"] if i["text"] == "acheter du café"))

    # ── 3. chrono ─────────────────────────────────────────────────────────
    print("\n[3] CHRONO")
    post("/api/stopwatch", {"action": "start"})
    time.sleep(1.3)
    el = get("/api/state")["stopwatch"]
    check("chrono tourne (>1 s)", el["elapsed"] >= 1.0, "%ss" % el["elapsed"])
    post("/api/stopwatch", {"action": "pause"})
    time.sleep(0.6)
    el2 = get("/api/state")["stopwatch"]
    check("chrono figé en pause", abs(el2["elapsed"] - el["elapsed"]) < 0.2,
          "%s → %s" % (el["elapsed"], el2["elapsed"]))
    post("/api/stopwatch", {"action": "reset"})
    check("reset", get("/api/state")["stopwatch"]["elapsed"] == 0)

    # ── 4. timer qui continue SANS client ────────────────────────────────
    print("\n[4] TIMER — 3 s, aucune requête pendant 4,5 s (panneau fermé)")
    post("/api/timer", {"action": "start", "seconds": 3, "label": "test timer"})
    t0 = time.time()
    time.sleep(4.5)                     # AUCUN appel HTTP ici : aucun client
    idle = time.time() - t0
    st = get("/api/state")
    evs = [e for e in st["events"] if e["kind"] == "timer"]
    check("événement de fin enregistré sans client",
          len(evs) == 1 and evs[0]["label"] == "test timer", json.dumps(evs))
    check("timer remis à l'arrêt", st["timer"]["running"] is False)
    print("       (aucune requête envoyée pendant %.1f s)" % idle)

    # ── 5. timer qui survit au redémarrage du serveur ────────────────────
    print("\n[5] TIMER — redémarrage du serveur en cours de compte à rebours")
    post("/api/timer", {"action": "start", "seconds": 8, "label": "survit"})
    stop_server()                        # le process meurt…
    time.sleep(1.0)
    start_server()                       # … et revient
    st = get("/api/state")
    rem = st["timer"]["remaining"]
    check("timer toujours en marche après redémarrage", st["timer"]["running"] is True)
    check("temps restant cohérent (~7 s)", 5.5 <= rem <= 8.0, "%ss" % rem)
    post("/api/timer", {"action": "reset"})

    # ── 6. alarme ─────────────────────────────────────────────────────────
    print("\n[6] ALARME")
    lt = time.localtime()
    hhmm = "%02d:%02d" % (lt.tm_hour, lt.tm_min)
    r = post("/api/alarm", {"action": "add", "hhmm": hhmm})
    check("alarme ajoutée", r.get("ok") is True, json.dumps(r.get("alarm")))
    check("alarme listée", len(get("/api/state")["alarms"]) == 1)
    check("heure invalide refusée",
          post("/api/alarm", {"action": "add", "hhmm": "25:99"}).get("ok") is False)
    aid = r["alarm"]["id"]
    post("/api/alarm", {"action": "del", "id": aid})
    check("alarme supprimée", get("/api/state")["alarms"] == [])

    # ── 7. modes : échec propre ───────────────────────────────────────────
    print("\n[7] MODES — outils absents = état visible, pas de crash")
    env = get("/api/env")
    print("       env : " + json.dumps(env))
    # Ces contrôles testent le CHEMIN D'ÉCHEC (pas de compositeur, pas de mako).
    # Dans une session Hyprland vivante, hyprctl répond et mako tourne : les
    # opérations RÉUSSISSENT, donc l'échec attendu n'a pas lieu. On le dit
    # (SKIP) au lieu de faire échouer la suite pour une raison d'environnement.
    hypr_live = bool(env.get("hyprland"))
    mako_live = bool(env.get("makoctl"))
    mode = post("/api/modes", {"mode": "lite", "on": True})
    if hypr_live:
        print("       SKIP  lite sans Hyprland (session Hyprland active)")
        check("lite répond sans crash (session réelle)",
              mode.get("ok") is not None, json.dumps(mode)[:80])
        post("/api/modes", {"mode": "lite", "on": False})
    else:
        check("lite sans Hyprland → ok:false + message",
              mode.get("ok") is False and "Hyprland" in (mode.get("error") or ""),
              json.dumps(mode.get("error")))
    check("le mode n'est PAS marqué actif après échec",
          get("/api/state")["modes"].get("lite") is not True)
    sun = post("/api/modes", {"mode": "bluesun", "on": True, "kelvin": 3000})
    check("lumière bleue → 'hyprsunset non installé' explicite",
          sun.get("ok") is False and "hyprsunset" in (sun.get("error") or ""),
          json.dumps(sun.get("error")))
    dnd = post("/api/modes", {"mode": "dnd", "on": True})
    if mako_live:
        print("       SKIP  DND sans mako (mako actif dans la session)")
        check("DND répond sans crash (session réelle)",
              dnd.get("ok") is not None, json.dumps(dnd)[:80])
        post("/api/modes", {"mode": "dnd", "on": False})
    else:
        check("DND sans mako → erreur explicite, pas de crash",
              dnd.get("ok") is False and "mako" in (dnd.get("error") or ""),
              json.dumps(dnd.get("error")))
    nosleep = post("/api/modes", {"mode": "nosleep", "on": True})
    check("anti-veille (inhibiteur système) démarre",
          nosleep.get("ok") is True and nosleep.get("pid"), json.dumps(nosleep))
    check("anti-veille visible dans l'état",
          get("/api/state")["modes"].get("nosleep") is True)
    post("/api/modes", {"mode": "nosleep", "on": False})
    check("anti-veille libère l'inhibiteur",
          get("/api/state")["modes"].get("nosleep") is False)

    # ── 8. palette : consommation réelle de cc/qml/Palette.qml ────────────
    print("\n[8] PALETTE — /api/palette == cc/qml/Palette.qml")
    pal = get("/api/palette")
    try:
        src = open(PALETTE_QML, encoding="utf-8").read()
        file_pal = dict(re.findall(r'property\s+color\s+(\w+)\s*:\s*"([^"]+)"', src))
    except OSError:
        file_pal = {}
    same = bool(file_pal) and all(pal.get(k) == v for k, v in file_pal.items())
    check("couleurs identiques au fichier régénéré par theme-apply.py", same,
          json.dumps({k: (pal.get(k), file_pal.get(k)) for k in file_pal
                      if pal.get(k) != file_pal.get(k)}) or "12 clés identiques")
    check("12 clés de palette", len(pal) == 12, str(len(pal)))

    # ── 9. divers ─────────────────────────────────────────────────────────
    print("\n[9] DIVERS")
    check("cliphist lu (3 dernières)", get("/api/clipboard").get("items") is not None)
    check("playerctl interrogé", "ok" in get("/api/player"))
    check("404 sur route inconnue", get("/api/nope").get("ok") is False)

    stop_server()
    print("\n%d/%d vérifications OK" % (sum(RESULTS), len(RESULTS)))
    print("état de test conservé : %s" % TMP)
    return 0 if all(RESULTS) else 1


if __name__ == "__main__":
    try:
        code = main()
    finally:
        stop_server()
    sys.exit(code)
