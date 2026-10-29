"""modes.py — moteur des « modes » de la slide bar Sasquatch.

Principe : on ne DEVINE jamais l'état d'avant. Avant d'appliquer un mode, on
lit la valeur réelle (`hyprctl getoption -j <opt>`) et on la sauvegarde dans
le JSON d'état ; à la désactivation on réécrit ces valeurs. Chaque mode est
idempotent (re-appliquer « on » alors qu'il est déjà on ne fait rien).

Ce module ne dépend PAS de Wayland pour être testable : toute la partie
exécution passe par un `runner` injectable. En mode --dry-run on affiche les
commandes sans les lancer (preuve de correction sans session Hyprland).

CLI :
    modes.py env                     # disponibilité des outils
    modes.py status                  # état courant des modes
    modes.py set lite on|off         # [--dry-run]
    modes.py set gaming on|off       # [--dry-run]
    modes.py set bluesun on|off --kelvin 4000
    modes.py set dnd on|off
    modes.py set nosleep on|off
    modes.py selftest                # cycle apply/restore avec runner factice
"""

import json
import os
import shutil
import signal
import subprocess
import sys
import threading
import time

# ── Chemins / constantes ──────────────────────────────────────────────────

CC_DIR = os.path.expanduser("~/.config/cc")
STATE_HOME = os.environ.get("XDG_STATE_HOME",
                            os.path.join(os.path.expanduser("~"), ".local", "state"))
STATE_DIR = os.path.join(STATE_HOME, "sasquatch")
STATE_FILE = os.path.join(STATE_DIR, "sidebar-state.json")

# Réglages désactivés par le mode « allégé » (valeurs remises à zéro).
LITE_OPTS = ("animations:enabled",
             "decoration:blur:enabled",
             "decoration:shadow:enabled")

DND_MODE = "do-not-disturb"
HYPRSUNSET_MIN, HYPRSUNSET_MAX = 2500, 6500


# ── Environnement Hyprland ────────────────────────────────────────────────

def hypr_env():
    """Env avec HYPRLAND_INSTANCE_SIGNATURE / WAYLAND_DISPLAY.

    Le service systemd user démarre SANS signature Hyprland (comme
    sasquatch-cc) : on la retrouve au moment de l'appel en prenant le
    répertoire le plus récent de $XDG_RUNTIME_DIR/hypr.
    """
    env = dict(os.environ)
    runtime = env.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
    env["XDG_RUNTIME_DIR"] = runtime
    if not env.get("HYPRLAND_INSTANCE_SIGNATURE"):
        base = os.path.join(runtime, "hypr")
        try:
            cands = [os.path.join(base, d) for d in os.listdir(base)]
            cands = [c for c in cands if os.path.isdir(c)]
            cands.sort(key=lambda p: os.path.getmtime(p), reverse=True)
            if cands:
                env["HYPRLAND_INSTANCE_SIGNATURE"] = os.path.basename(cands[0])
        except OSError:
            pass
    if not env.get("WAYLAND_DISPLAY"):
        try:
            names = sorted(n for n in os.listdir(runtime) if n.startswith("wayland-"))
            if names:
                env["WAYLAND_DISPLAY"] = names[0]
        except OSError:
            pass
    return env


def default_runner(cmd, timeout=6):
    """Exécute une commande → (returncode, stdout, stderr)."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True,
                           timeout=timeout, env=hypr_env())
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except FileNotFoundError:
        return 127, "", "%s introuvable" % cmd[0]
    except subprocess.TimeoutExpired:
        return 124, "", "timeout (%ss)" % timeout


# ── Moteur ────────────────────────────────────────────────────────────────

class ModeEngine:
    """Applique / restaure les modes. `state` est le dict persistant partagé
    avec server.py (clés : modes, modes_saved, procs)."""

    def __init__(self, state, runner=None, dry=False):
        self.state = state
        self.run = runner or default_runner
        self.dry = dry
        self.state.setdefault("modes", {})
        self.state.setdefault("modes_saved", {})
        self.state.setdefault("procs", {})      # pid des process lancés (hyprsunset…)
        self._lock = threading.Lock()

    # ── outils ────────────────────────────────────────────────────────────
    @staticmethod
    def have(binary):
        return shutil.which(binary) is not None

    def env(self):
        hypr_ok = False
        rc, out, _ = self.run(["hyprctl", "version"])
        hypr_ok = (rc == 0 and bool(out))
        return {
            "hyprland": hypr_ok,
            "hyprsunset": self.have("hyprsunset"),
            "makoctl": self.have("makoctl"),
            "powerprofilesctl": self.have("powerprofilesctl"),
            "playerctl": self.have("playerctl"),
            "wpctl": self.have("wpctl"),
            "brightnessctl": self.have("brightnessctl"),
            "cliphist": self.have("cliphist"),
            "hyprlock": self.have("hyprlock"),
            "notify_send": self.have("notify-send"),
        }

    def _getoption(self, opt):
        """Valeur réelle d'une option Hyprland (int/bool/str) ou None."""
        rc, out, _ = self.run(["hyprctl", "getoption", "-j", opt])
        if rc != 0 or not out:
            return None
        try:
            data = json.loads(out)
        except ValueError:
            return None
        # getoption -j renvoie {"option":..., "int":1, "set":true, ...}
        for key in ("int", "float", "str"):
            if key in data and data[key] not in (None, ""):
                return data[key]
        return None

    def _keyword(self, opt, value):
        if self.dry:
            return {"dry": True, "cmd": ["hyprctl", "keyword", opt, str(value)]}
        rc, out, err = self.run(["hyprctl", "keyword", opt, str(value)])
        return {"ok": rc == 0, "cmd": ["hyprctl", "keyword", opt, str(value)],
                "out": out, "err": err}

    # ── état des modes ────────────────────────────────────────────────────
    def status(self):
        return {
            "modes": dict(self.state.get("modes", {})),
            "saved": dict(self.state.get("modes_saved", {})),
            "env": self.env(),
            "kelvin": self.state.get("modes", {}).get("kelvin", 4000),
        }

    def set(self, mode, on, kelvin=None):
        """Applique/désactive un mode. Retourne {ok, applied, ...}."""
        with self._lock:
            m = self.state["modes"]
            if mode not in ("lite", "gaming", "bluesun", "dnd", "nosleep"):
                return {"ok": False, "error": "mode inconnu: %s" % mode}
            already = bool(m.get(mode))
            if already == bool(on) and mode != "bluesun":
                return {"ok": True, "applied": False, "reason": "déjà %s" % (
                    "actif" if on else "inactif"), "modes": dict(m)}
            if mode == "lite":
                res = self._set_lite(on)
            elif mode == "gaming":
                res = self._set_gaming(on)
            elif mode == "bluesun":
                res = self._set_bluesun(on, kelvin)
            elif mode == "dnd":
                res = self._set_dnd(on)
            else:
                res = self._set_nosleep(on)
            if res.get("ok"):
                m[mode] = bool(on)
                if mode == "bluesun" and kelvin:
                    m["kelvin"] = int(kelvin)
            res["modes"] = dict(m)
            return res

    # ── primitives à propriétaires (refcount) ────────────────────────────
    # « lite » et « gaming » agissent sur les MÊMES options Hyprland. Avec une
    # seule sauvegarde partagée, activer gaming après lite RÉÉCRIVAIT l'état
    # d'origine avec les valeurs déjà mises à zéro → impossible de revenir
    # (symptôme : on reste bloqué en allégé). On sauvegarde donc UNE fois les
    # vraies valeurs, et chaque mode devient « propriétaire » ; on ne restaure
    # que lorsque plus AUCUN propriétaire ne demande l'état dégradé.
    def _owners(self, key):
        saved = self.state["modes_saved"].get(key)
        if isinstance(saved, dict) and isinstance(saved.get("owners"), list):
            return saved["owners"], saved.get("opts")
        # Rétro-compat : ancien format = {option: valeur} sans enveloppe.
        if isinstance(saved, dict) and saved:
            return ["lite"], saved
        return [], None

    def _lite_acquire(self, owner):
        owners, opts = self._owners("lite")
        if opts:
            # Déjà dégradé : on ajoute simplement le propriétaire, sans
            # re-sauvegarder (sinon on écrase l'état d'origine par des zéros).
            if owner not in owners:
                owners.append(owner)
            self.state["modes_saved"]["lite"] = {"owners": owners, "opts": opts}
            return {"ok": True, "applied": False,
                    "reason": "déjà allégé (propriétaires: %s)" % ",".join(owners)}

        saved = {}
        for opt in LITE_OPTS:
            val = self._getoption(opt)
            if val is not None:
                saved[opt] = val
        if not saved:
            return {"ok": False,
                    "error": "Hyprland injoignable (hyprctl getoption vide)"}
        cmds = [self._keyword(opt, 0) for opt in saved]
        bad = [c for c in cmds if not c.get("ok", True)]
        if bad and not self.dry:
            return {"ok": False, "error": "application partielle", "cmds": cmds}
        self.state["modes_saved"]["lite"] = {"owners": [owner], "opts": saved}
        return {"ok": True, "applied": True, "saved": saved, "cmds": cmds}

    def _lite_release(self, owner):
        owners, opts = self._owners("lite")
        if owner in owners:
            owners.remove(owner)
        if owners:
            self.state["modes_saved"]["lite"] = {"owners": owners, "opts": opts}
            return {"ok": True, "applied": False,
                    "reason": "encore demandé par: %s" % ",".join(owners)}
        if not opts:
            self.state["modes_saved"].pop("lite", None)
            return {"ok": True, "applied": False,
                    "reason": "aucun état sauvegardé (rien à restaurer)"}
        cmds = [self._keyword(opt, value) for opt, value in opts.items()]
        bad = [c for c in cmds if not c.get("ok", True)]
        if bad and not self.dry:
            return {"ok": False, "error": "restauration partielle", "cmds": cmds}
        self.state["modes_saved"].pop("lite", None)
        return {"ok": True, "applied": True, "restored": opts, "cmds": cmds}

    def _dnd_acquire(self, owner):
        owners, _ = self._owners("dnd")
        if owner not in owners:
            owners.append(owner)
        self.state["modes_saved"]["dnd"] = {"owners": owners}
        if len(owners) > 1:
            return {"ok": True, "applied": False, "reason": "déjà demandé"}
        return self._set_dnd(True)

    def _dnd_release(self, owner):
        owners, _ = self._owners("dnd")
        if owner in owners:
            owners.remove(owner)
        if not owners:
            self.state["modes_saved"].pop("dnd", None)
            return self._set_dnd(False)
        self.state["modes_saved"]["dnd"] = {"owners": owners}
        return {"ok": True, "applied": False,
                "reason": "encore demandé par: %s" % ",".join(owners)}

    # ── mode allégé ───────────────────────────────────────────────────────
    def _set_lite(self, on):
        return self._lite_acquire("lite") if on else self._lite_release("lite")

    # ── gaming = allégé + DND + profil de perf ────────────────────────────
    def _set_gaming(self, on):
        out = {"ok": True, "parts": {}}
        if on:
            out["parts"]["lite"] = self._lite_acquire("gaming")
            # DND est best-effort : si mako est absent/injoignable, gaming doit
            # quand même fonctionner (sinon tout le mode échoue pour un bonus).
            dnd = self._dnd_acquire("gaming")
            if not dnd.get("ok"):
                dnd["skipped"] = True
                dnd["warning"] = dnd.get("error", "DND indisponible")
                dnd["ok"] = True
            out["parts"]["dnd"] = dnd
            # Le pill DND doit refléter la réalité, mais sans s'approprier
            # l'état : gaming n'est qu'un propriétaire parmi d'autres.
            if dnd.get("applied"):
                self.state["modes"]["dnd"] = True
            if self.have("powerprofilesctl"):
                rc, cur, _ = self.run(["powerprofilesctl", "get"])
                if rc == 0 and not self.state["modes_saved"].get("powerprofile"):
                    self.state["modes_saved"]["powerprofile"] = cur or "balanced"
                if self.dry:
                    out["parts"]["powerprofile"] = {
                        "ok": True, "skipped": True, "dry": True,
                        "cmd": ["powerprofilesctl", "set", "performance"]}
                else:
                    rc2, _, err = self.run(
                        ["powerprofilesctl", "set", "performance"])
                    # Bonus : un échec de profil de perf ne doit pas annuler
                    # le mode gaming (sinon owners posés + mode non actif).
                    out["parts"]["powerprofile"] = {
                        "ok": True, "applied": rc2 == 0,
                        "skipped": rc2 != 0, "err": err}
            else:
                out["parts"]["powerprofile"] = {
                    "ok": True, "skipped": True,
                    "warning": "powerprofilesctl absent"}
        else:
            out["parts"]["dnd"] = self._dnd_release("gaming")
            # Ne coupe le pill DND que si personne d'autre ne le demande.
            remaining, _ = self._owners("dnd")
            if not remaining:
                self.state["modes"]["dnd"] = False
            out["parts"]["lite"] = self._lite_release("gaming")
            prev = self.state["modes_saved"].pop("powerprofile", None)
            if prev and self.have("powerprofilesctl") and not self.dry:
                rc, _, err = self.run(["powerprofilesctl", "set", prev])
                out["parts"]["powerprofile"] = {"ok": rc == 0, "restored": prev,
                                                "err": err}
        ok = all(p.get("ok", True) for p in out["parts"].values())
        out["ok"] = ok
        if not ok:
            out["error"] = "un composant a échoué (voir parts)"
        return out

    # ── lumière bleue (hyprsunset) ────────────────────────────────────────
    def _kill_proc(self, name):
        pid = self.state["procs"].pop(name, None)
        if pid:
            try:
                os.kill(int(pid), signal.SIGTERM)
            except (OSError, ValueError):
                pass

    def _set_bluesun(self, on, kelvin=None):
        if not self.have("hyprsunset"):
            return {"ok": False, "missing": True,
                    "error": "hyprsunset non installé "
                             "(sudo pacman -S hyprsunset)"}
        k = int(kelvin or self.state["modes"].get("kelvin") or 4000)
        k = max(HYPRSUNSET_MIN, min(HYPRSUNSET_MAX, k))
        if not on:
            self._kill_proc("hyprsunset")
            if not self.dry:
                self.run(["pkill", "-f", "hyprsunset"])
            return {"ok": True, "applied": True, "kelvin": None}

        # hyprsunset ne prend qu'une température au lancement : on relance le
        # process si la température change (léger, il ne fait qu'un shader).
        if self.dry:
            return {"ok": True, "applied": True, "kelvin": k,
                    "cmd": ["hyprsunset", "-t", str(k)]}
        self._kill_proc("hyprsunset")
        try:
            env = hypr_env()
            # start_new_session : hyprsunset doit SURVIVRE à un redémarrage du
            # backend (sinon le filtre s'éteint tout seul et la sidebar, qui lit
            # le PID, ne le voit plus).
            proc = subprocess.Popen(["hyprsunset", "-t", str(k)],
                                    stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL, env=env,
                                    start_new_session=True)
        except OSError as exc:
            return {"ok": False, "error": "lancement hyprsunset: %s" % exc}
        self.state["procs"]["hyprsunset"] = proc.pid
        time.sleep(0.15)
        if proc.poll() is not None:
            return {"ok": False,
                    "error": "hyprsunset a quitté (code %s) — session "
                             "Wayland absente ?" % proc.returncode}
        return {"ok": True, "applied": True, "kelvin": k, "pid": proc.pid}

    # ── ne pas déranger (mako) ────────────────────────────────────────────
    def _dnd_active(self):
        rc, out, _ = self.run(["makoctl", "mode"])
        if rc != 0:
            return None                      # mako injoignable
        return DND_MODE in out.split()

    def _set_dnd(self, on):
        if not self.have("makoctl"):
            return {"ok": False, "missing": True, "error": "makoctl absent"}
        cur = self._dnd_active()
        if cur is None:
            return {"ok": False, "error": "mako injoignable "
                                          "(session graphique absente ?)"}
        if cur == bool(on):
            return {"ok": True, "applied": False, "reason": "déjà dans cet état"}
        arg = "-a" if on else "-r"
        if self.dry:
            return {"ok": True, "applied": True,
                    "cmd": ["makoctl", "mode", arg, DND_MODE]}
        rc, out, err = self.run(["makoctl", "mode", arg, DND_MODE])
        return {"ok": rc == 0, "applied": rc == 0,
                "cmd": ["makoctl", "mode", arg, DND_MODE],
                "out": out, "err": err}

    # ── anti-veille (inhibiteur système, survit à la fermeture du panneau) ─
    def _set_nosleep(self, on):
        if not on:
            self._kill_proc("nosleep")
            return {"ok": True, "applied": True, "inhibitor": None}
        if self.state["procs"].get("nosleep"):
            return {"ok": True, "applied": False, "reason": "déjà actif"}
        cmd = ["systemd-inhibit", "--what=idle:sleep",
               "--who=sasquatch-sidebar", "--why=Mode anti-veille",
               "--mode=block", "sleep", "infinity"]
        if self.dry:
            return {"ok": True, "applied": True, "cmd": cmd}
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL)
        except OSError as exc:
            return {"ok": False, "error": "systemd-inhibit: %s" % exc}
        self.state["procs"]["nosleep"] = proc.pid
        return {"ok": True, "applied": True, "pid": proc.pid}

    # ── arrêt propre (le serveur appelle ça au shutdown) ──────────────────
    def shutdown(self):
        for name in list(self.state.get("procs", {})):
            self._kill_proc(name)


# ── CLI (preuves sans session) ────────────────────────────────────────────

def _load_state():
    try:
        with open(STATE_FILE, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


class FakeRunner:
    """Runner factice : simule un Hyprland déjà configuré (blur/shadow ON)."""

    def __init__(self):
        self.calls = []
        self.opts = {"animations:enabled": 1,
                     "decoration:blur:enabled": 1,
                     "decoration:shadow:enabled": 1}

    def __call__(self, cmd, timeout=6):
        self.calls.append(list(cmd))
        if cmd[:2] == ["hyprctl", "getoption"]:
            opt = cmd[3]
            if opt not in self.opts:
                return 0, json.dumps({"option": opt, "set": False}), ""
            return 0, json.dumps({"option": opt, "int": self.opts[opt],
                                  "set": True}), ""
        if cmd[:2] == ["hyprctl", "keyword"]:
            self.opts[cmd[2]] = int(cmd[3]) if str(cmd[3]).isdigit() else cmd[3]
            return 0, "ok", ""
        if cmd[:2] == ["hyprctl", "version"]:
            return 0, "Hyprland 0.56.2 (fake)", ""
        return 0, "", ""


def selftest():
    """Prouve apply → restore avec restauration des valeurs d'AVANT."""
    state = {}
    fake = FakeRunner()
    eng = ModeEngine(state, runner=fake)
    ok = True

    print("== état initial simulé ==")
    print(json.dumps(fake.opts, indent=2))

    on = eng.set("lite", True)
    print("\n== set lite on ==")
    print(json.dumps(on, indent=2, ensure_ascii=False))
    ok &= on["ok"] and fake.opts["animations:enabled"] == 0

    again = eng.set("lite", True)
    print("\n== set lite on (idempotence) ==")
    print(json.dumps(again, indent=2, ensure_ascii=False))
    ok &= again["applied"] is False

    off = eng.set("lite", False)
    print("\n== set lite off (restauration) ==")
    print(json.dumps(off, indent=2, ensure_ascii=False))
    ok &= off["ok"] and fake.opts == {"animations:enabled": 1,
                                      "decoration:blur:enabled": 1,
                                      "decoration:shadow:enabled": 1}

    print("\n== commandes réellement émises ==")
    for c in fake.calls:
        print("  " + " ".join(c))

    print("\nSELFTEST:", "OK" if ok else "ÉCHEC")
    return 0 if ok else 1


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd = argv[1]
    dry = "--dry-run" in argv
    args = [a for a in argv[2:] if not a.startswith("--")]
    kelvin = None
    if "--kelvin" in argv:
        kelvin = int(argv[argv.index("--kelvin") + 1])

    if cmd == "selftest":
        return selftest()

    state = _load_state()
    eng = ModeEngine(state, dry=dry)

    if cmd == "env":
        print(json.dumps(eng.env(), indent=2))
        return 0
    if cmd == "status":
        print(json.dumps(eng.status(), indent=2, ensure_ascii=False))
        return 0
    if cmd == "set" and len(args) >= 2:
        res = eng.set(args[0], args[1] in ("on", "true", "1"), kelvin)
        print(json.dumps(res, indent=2, ensure_ascii=False))
        return 0 if res.get("ok") else 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
