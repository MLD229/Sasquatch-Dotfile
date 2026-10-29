"""clock.py — moteur chrono / timer / alarme de la slide bar Sasquatch.

POURQUOI CE MODULE EXISTE : la logique de temps ne vit PAS dans le QML. Un
timer QML meurt avec la fenêtre ; ici le temps est calculé côté backend
(service systemd user permanent), donc un timer lancé puis panneau fermé
continue de tourner et sonne quand même.

Principe « horloge absolue » : on ne décrémente jamais un compteur à chaque
tick (une seconde perdue au suspend/reload = timer faux). On stocke un
timestamp de fin (`ends_at`) et on calcule le reste à la demande. Conséquence :
le timer est juste même si le process n'a pas tourné pendant N minutes
(redémarrage du serveur pendant le timer → il sonne quand même).

`now` est injectable → tests déterministes sans dormir.
"""

import math
import time
import uuid

MAX_TIMER = 24 * 3600


def _fmt(sec):
    sec = max(0, int(sec))
    h, rem = divmod(sec, 3600)
    m, s = divmod(rem, 60)
    return "%d:%02d:%02d" % (h, m, s) if h else "%02d:%02d" % (m, s)


class Clock:
    """État persistant dans le dict `state` (partagé avec server.py)."""

    def __init__(self, state, now=time.time):
        self.state = state
        self.now = now
        self.state.setdefault("stopwatch", {"running": False, "accum": 0.0,
                                            "started_at": None})
        self.state.setdefault("timer", {"running": False, "total": 0,
                                        "ends_at": None, "label": "",
                                        "done": True})
        self.state.setdefault("alarms", [])
        self.state.setdefault("events", [])
        self.state.setdefault("event_seq", 0)

    # ── dérivés ───────────────────────────────────────────────────────────
    def stopwatch_elapsed(self):
        sw = self.state["stopwatch"]
        val = float(sw.get("accum") or 0)
        if sw.get("running") and sw.get("started_at"):
            val += max(0.0, self.now() - float(sw["started_at"]))
        return val

    def timer_remaining(self):
        t = self.state["timer"]
        if t.get("running") and t.get("ends_at"):
            return max(0.0, float(t["ends_at"]) - self.now())
        return max(0.0, float(t.get("remaining") or 0))

    def snapshot(self):
        sw = self.state["stopwatch"]
        t = self.state["timer"]
        return {
            "stopwatch": {
                "running": bool(sw.get("running")),
                "elapsed": round(self.stopwatch_elapsed(), 2),
                "text": _fmt(self.stopwatch_elapsed()),
            },
            "timer": {
                "running": bool(t.get("running")),
                "total": int(t.get("total") or 0),
                "remaining": round(self.timer_remaining(), 2),
                # arrondi SUPÉRIEUR : un timer de 5 s doit afficher 00:05, pas
                # 00:04 (le restant vaut 4,99 s juste après le départ).
                "text": _fmt(math.ceil(self.timer_remaining())),
                "label": t.get("label") or "",
                "done": bool(t.get("done", True)),
            },
            "alarms": [dict(a) for a in self.state["alarms"]],
            "events": [dict(e) for e in self.state["events"][-20:]],
        }

    # ── chrono ────────────────────────────────────────────────────────────
    def stopwatch(self, action):
        sw = self.state["stopwatch"]
        if action == "start":
            if sw.get("running"):
                return {"ok": True, "applied": False}
            sw["started_at"] = self.now()
            sw["running"] = True
        elif action == "pause":
            if not sw.get("running"):
                return {"ok": True, "applied": False}
            sw["accum"] = self.stopwatch_elapsed()
            sw["started_at"] = None
            sw["running"] = False
        elif action == "reset":
            sw.update({"running": False, "accum": 0.0, "started_at": None})
        else:
            return {"ok": False, "error": "action inconnue: %s" % action}
        return {"ok": True, "applied": True, "stopwatch": self.snapshot()["stopwatch"]}

    # ── timer ─────────────────────────────────────────────────────────────
    def timer(self, action, seconds=None, label=""):
        t = self.state["timer"]
        if action in ("start", "set"):
            if seconds is None:
                # start sans durée : reprend le temps restant s'il en reste
                rem = self.timer_remaining()
                if rem <= 0:
                    rem = float(t.get("total") or 0)
                if rem <= 0:
                    return {"ok": False, "error": "aucune durée"}
            else:
                rem = float(seconds)
            rem = max(1.0, min(float(MAX_TIMER), rem))
            t["total"] = int(rem)
            t["ends_at"] = self.now() + rem
            t["running"] = True
            t["done"] = False
            if label:
                t["label"] = label
            return {"ok": True, "applied": True, "timer": self.snapshot()["timer"]}
        if action == "pause":
            if not t.get("running"):
                return {"ok": True, "applied": False}
            t["remaining"] = self.timer_remaining()
            t["running"] = False
            t["ends_at"] = None
            return {"ok": True, "applied": True, "timer": self.snapshot()["timer"]}
        if action in ("reset", "cancel"):
            t.update({"running": False, "ends_at": None, "remaining": 0,
                      "done": True, "label": ""})
            return {"ok": True, "applied": True, "timer": self.snapshot()["timer"]}
        return {"ok": False, "error": "action inconnue: %s" % action}

    # ── alarmes ───────────────────────────────────────────────────────────
    @staticmethod
    def next_ts(hhmm, now):
        """Prochaine occurrence de HH:MM (aujourd'hui si encore à venir,
        sinon demain)."""
        hh, mm = [int(x) for x in hhmm.split(":")]
        lt = time.localtime(now)
        target = time.mktime((lt.tm_year, lt.tm_mon, lt.tm_mday, hh, mm, 0,
                              0, 0, -1))
        if target <= now:
            target += 86400
        return target

    def add_alarm(self, hhmm, label=""):
        try:
            hh, mm = [int(x) for x in hhmm.split(":")]
            assert 0 <= hh < 24 and 0 <= mm < 60
        except (ValueError, AssertionError):
            return {"ok": False, "error": "heure invalide (HH:MM attendu)"}
        now = self.now()
        alarm = {"id": uuid.uuid4().hex[:8], "hhmm": "%02d:%02d" % (hh, mm),
                 "label": label, "target": self.next_ts(hhmm, now),
                 "fired": False}
        self.state["alarms"].append(alarm)
        self.state["alarms"].sort(key=lambda a: a["target"])
        return {"ok": True, "alarm": alarm, "alarms": self.state["alarms"]}

    def del_alarm(self, alarm_id):
        before = len(self.state["alarms"])
        self.state["alarms"] = [a for a in self.state["alarms"]
                                if a["id"] != alarm_id]
        return {"ok": len(self.state["alarms"]) != before,
                "alarms": self.state["alarms"]}

    # ── événements (sonneries) ────────────────────────────────────────────
    def _emit(self, kind, label):
        self.state["event_seq"] += 1
        ev = {"id": self.state["event_seq"], "kind": kind,
              "label": label, "ts": self.now()}
        self.state["events"].append(ev)
        # anneau borné : l'UI ne lit que les 20 derniers
        self.state["events"] = self.state["events"][-50:]
        return ev

    def tick(self):
        """À appeler régulièrement (0,5 s). Retourne les événements déclenchés."""
        fired = []
        t = self.state["timer"]
        if t.get("running") and t.get("ends_at") and self.now() >= float(t["ends_at"]):
            t["running"] = False
            t["ends_at"] = None
            t["remaining"] = 0
            t["done"] = True
            label = t.get("label") or "Timer"
            fired.append(self._emit("timer", label))
            t["label"] = ""
        now = self.now()
        for a in self.state["alarms"]:
            if not a.get("fired") and now >= float(a["target"]):
                a["fired"] = True
                fired.append(self._emit("alarm",
                                        a.get("label") or a["hhmm"]))
        # une alarme non récurrente disparaît une fois sonnée
        if any(a.get("fired") for a in self.state["alarms"]):
            self.state["alarms"] = [a for a in self.state["alarms"]
                                    if not a.get("fired")]
        return fired


def _notify(title, body):
    """Notification mako (notify-send) + son système — best effort, jamais
    bloquant : outil absent = on ignore, le timer a quand même sonné côté
    backend (l'événement reste lisible dans /api/state)."""
    import os
    import shutil
    import subprocess

    if shutil.which("notify-send"):
        try:
            subprocess.run(["notify-send", "-u", "critical", "-a", "Sasquatch",
                            title, body], timeout=3, capture_output=True)
        except Exception:
            pass

    sounds = ("/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga",
              "/usr/share/sounds/freedesktop/stereo/complete.oga",
              "/usr/share/sounds/freedesktop/stereo/bell.oga")
    for snd in sounds:
        if not os.path.exists(snd):
            continue
        for player in ("pw-play", "paplay"):
            if shutil.which(player):
                try:
                    subprocess.Popen([player, snd], stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL)
                    return
                except Exception:
                    continue
        break
