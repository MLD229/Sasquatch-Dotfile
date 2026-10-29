#!/usr/bin/env python3
"""test_clock.py — tests déterministes du moteur chrono/timer/alarme.

Aucune attente réelle : `now` est injecté, donc on prouve la précision
(timer qui sonne à la bonne seconde même si le tick est en retard), la
non-répétition des alarmes et la reconnexion après « redémarrage ».

Lancement : python3 tests/test_clock.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import clock as clockmod  # noqa: E402


class FakeTime:
    def __init__(self, t=1_700_000_000.0):
        self.t = t

    def __call__(self):
        return self.t

    def advance(self, dt):
        self.t += dt


def check(label, cond, detail=""):
    print(("  OK   " if cond else "  FAIL ") + label + ((" — " + detail) if detail else ""))
    return bool(cond)


def test_timer_exact():
    print("\n[timer] 3 s lancé, tick à 1 s puis tick à 7 s (tick en retard)")
    ft = FakeTime()
    st = {}
    c = clockmod.Clock(st, now=ft)
    c.timer("start", 3)
    ft.advance(1)
    fired = c.tick()
    ok = check("rien ne sonne à t+1s", fired == [], repr(fired))
    ft.advance(6)                     # t+7s : le tick a « sauté » 6 s
    fired = c.tick()
    ok &= check("sonne au tick suivant (horloge absolue, pas de compteur)",
                len(fired) == 1 and fired[0]["kind"] == "timer", repr(fired))
    ok &= check("timer repassé à l'arrêt", c.snapshot()["timer"]["running"] is False)
    ok &= check("pas de double sonnerie au tick d'après", c.tick() == [])
    return ok


def test_timer_pause_resume():
    print("\n[timer] pause/reprise conserve le restant")
    ft = FakeTime()
    c = clockmod.Clock({}, now=ft)
    c.timer("start", 60)
    ft.advance(20)
    c.timer("pause")
    rem = c.timer_remaining()
    ft.advance(300)                   # en pause : le temps ne court plus
    ok = check("restant figé pendant la pause", abs(c.timer_remaining() - rem) < 0.01,
               "%.2f vs %.2f" % (rem, c.timer_remaining()))
    c.timer("start")                  # reprise sans durée
    ft.advance(rem - 1)
    ok &= check("pas de sonnerie 1 s avant la fin", c.tick() == [])
    ft.advance(1.5)
    ok &= check("sonne à la fin", len(c.tick()) == 1)
    return ok


def test_stopwatch():
    print("\n[chrono] start / pause / reset")
    ft = FakeTime()
    c = clockmod.Clock({}, now=ft)
    c.stopwatch("start")
    ft.advance(5)
    c.stopwatch("pause")
    e = c.stopwatch_elapsed()
    ft.advance(100)
    ok = check("chrono figé en pause", abs(c.stopwatch_elapsed() - e) < 0.01)
    c.stopwatch("start")
    ft.advance(2)
    ok &= check("reprise cumulative (≈7 s)", abs(c.stopwatch_elapsed() - 7) < 0.01,
                "%.2f" % c.stopwatch_elapsed())
    c.stopwatch("reset")
    ok &= check("reset à 0", c.stopwatch_elapsed() == 0)
    return ok


def test_alarm():
    print("\n[alarme] next_ts, sonnerie unique, disparition")
    now = 1_700_000_000.0             # 2023-11-14 22:13:20 UTC
    import time as _t
    lt = _t.localtime(now)
    print("  (heure locale de référence : %02d:%02d)" % (lt.tm_hour, lt.tm_min))
    ft = FakeTime(now)
    c = clockmod.Clock({}, now=ft)
    nxt = clockmod.Clock.next_ts("%02d:%02d" % (lt.tm_hour, (lt.tm_min + 1) % 60), now)
    ok = check("next_ts = dans le futur (≤ 24 h)", now < nxt <= now + 86400,
               "+%.0fs" % (nxt - now))
    res = c.add_alarm("%02d:%02d" % (lt.tm_hour, (lt.tm_min + 1) % 60))
    ok &= check("alarme enregistrée", res["ok"] and len(c.state["alarms"]) == 1)
    ok &= check("heure invalide refusée", c.add_alarm("99:99")["ok"] is False)
    ft.t = float(res["alarm"]["target"]) - 0.5
    ok &= check("pas de sonnerie avant l'heure", c.tick() == [])
    ft.t = float(res["alarm"]["target"]) + 0.5
    fired = c.tick()
    ok &= check("sonne à l'heure", len(fired) == 1 and fired[0]["kind"] == "alarm",
                repr(fired))
    ok &= check("alarme non récurrente retirée", c.state["alarms"] == [])
    ok &= check("pas de seconde sonnerie", c.tick() == [])
    return ok


def test_persistence_shape():
    print("\n[état] JSON sérialisable (persistance disque)")
    import json
    c = clockmod.Clock({})
    c.timer("start", 90)
    c.add_alarm("07:30")
    c.stopwatch("start")
    try:
        blob = json.dumps(c.state)
        ok = check("json.dumps(state) fonctionne", len(blob) > 50, "%d octets" % len(blob))
    except TypeError as exc:
        ok = check("json.dumps(state) fonctionne", False, str(exc))
    # « redémarrage » : on relit le state sérialisé dans un nouveau moteur
    c2 = clockmod.Clock(json.loads(json.dumps(c.state)))
    ok &= check("timer toujours en marche après reload",
                c2.snapshot()["timer"]["running"] is True)
    ok &= check("alarme toujours présente après reload", len(c2.state["alarms"]) == 1)
    return ok


def main():
    results = [test_timer_exact(), test_timer_pause_resume(), test_stopwatch(),
               test_alarm(), test_persistence_shape()]
    print("\n%d/%d groupes OK" % (sum(1 for r in results if r), len(results)))
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
