#!/usr/bin/env python3
"""state.py — « la sub page est-elle ouverte ? » (source de vérité UNIQUE).

La sub page = le special workspace Hyprland `special:subpage`
(`hyprctl dispatch togglespecialworkspace subpage`).

SEULE source de vérité : `hyprctl monitors -j` →
    monitor.specialWorkspace.name == "special:subpage"

`hyprctl activeworkspace` ne convient PAS : il renvoie le workspace du
moniteur (いち, に, …) et JAMAIS le special. Il ne dit donc rien sur la page.

La voie rapide par socket (`.socket.sock` + `j/monitors`) a été SUPPRIMÉE :
mesuré le 2026-10-29, elle a renvoyé `closed` alors que `hyprctl monitors -j`
disait `open` (deux instances Hyprland dans ~/.runtime/hypr, la signature
devinée n'était pas celle de la session affichée). Un état qui diverge de
`hyprctl` est un bug : on ne prend plus AUCUNE décision sur une donnée non
confirmée par l'IPC officiel. `hyprctl` est le client de référence de
Hyprland lui-même — même chemin, même réponse que ce que voit l'écran.

Rien n'est stocké sur disque : l'état est relu à chaque interrogation, ce qui
le rend juste même si la page a été fermée par un autre biais (autre keybind,
`hyprctl dispatch` à la main, script tiers).

Modes
    --check                 exit 0 = ouverte, exit 1 = fermée (muet)
    --monitor               nom du moniteur qui l'affiche (exit 1 si fermée)
    --json                  {"open": bool, "monitor": "eDP-1"|null, "source": "hyprctl"}
    --watch [--interval S]  reste vivant ; imprime UNE ligne par CHANGEMENT :
                            "open eDP-1" ou "closed"  (consommé par shell.qml)
"""

import argparse
import json
import os
import subprocess
import sys
import time

TARGET = "special:subpage"


# ── Localisation de la session Hyprland ────────────────────────────────────
def runtime_dir():
    return os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()


def candidate_signatures():
    """Signatures d'instance à essayer, dans l'ordre : celle de l'env d'abord.

    Hyprland crée un dossier par instance dans $XDG_RUNTIME_DIR/hypr. Une
    session peut en laisser plusieurs (redémarrages) : on essaie celle que
    l'environnement désigne, puis les autres de la plus récente à la plus
    ancienne, et on garde la première qui répond vraiment.
    """
    base = os.path.join(runtime_dir(), "hypr")
    sigs = []
    env_sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if env_sig:
        sigs.append(env_sig)
    try:
        names = [
            (os.path.getmtime(os.path.join(base, name)), name)
            for name in os.listdir(base)
        ]
    except OSError:
        return sigs
    for _, name in sorted(names, reverse=True):
        if name not in sigs:
            sigs.append(name)
    return sigs


# ── Lecture de l'état ──────────────────────────────────────────────────────
def _monitors_with(sig):
    """`hyprctl monitors -j` pour une signature donnée, ou None si muet."""
    env = os.environ.copy()
    env["XDG_RUNTIME_DIR"] = runtime_dir()
    env["HYPRLAND_INSTANCE_SIGNATURE"] = sig
    try:
        out = subprocess.run(
            ["hyprctl", "monitors", "-j"],
            capture_output=True,
            text=True,
            timeout=3,
            env=env,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0 or not out.stdout.strip():
        return None
    try:
        data = json.loads(out.stdout)
    except ValueError:
        return None
    return data if isinstance(data, list) else None


def monitors():
    """Moniteurs Hyprland, ou None si aucune instance ne répond."""
    for sig in candidate_signatures():
        mons = _monitors_with(sig)
        if mons is not None:
            return mons
    return None


def state():
    """{"open": bool, "monitor": str|None}. Lève RuntimeError si Hyprland muet."""
    mons = monitors()
    if mons is None:
        raise RuntimeError("Hyprland ne répond pas (hyprctl monitors -j vide)")
    for mon in mons:
        special = mon.get("specialWorkspace") or {}
        if special.get("name") == TARGET:
            return {"open": True, "monitor": mon.get("name")}
    return {"open": False, "monitor": None}


# ── Boucle de surveillance (consommée par shell.qml) ───────────────────────
def watch(interval):
    """Imprime "open <moniteur>" / "closed" à chaque changement d'état."""
    last = None
    while True:
        try:
            st = state()
        except RuntimeError:
            st = None  # Hyprland muet : on garde le dernier état connu
        if st is not None:
            line = ("open " + (st["monitor"] or "")) if st["open"] else "closed"
            if line != last:
                sys.stdout.write(line + "\n")
                sys.stdout.flush()
                last = line
        time.sleep(interval)


def main():
    parser = argparse.ArgumentParser(description="État de la sub page (special:subpage).")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--check", action="store_true", help="exit 0 si ouverte, 1 sinon")
    group.add_argument("--monitor", action="store_true", help="moniteur qui l'affiche")
    group.add_argument("--json", action="store_true", help="état en JSON")
    group.add_argument("--watch", action="store_true", help="surveille et imprime les changements")
    parser.add_argument("--interval", type=float, default=0.15, help="période de --watch (s)")
    args = parser.parse_args()

    if args.watch:
        try:
            watch(max(0.02, args.interval))
        except (KeyboardInterrupt, BrokenPipeError):
            pass  # shell.qml a disparu (fin de vie normale)
        return 0

    try:
        st = state()
    except RuntimeError as exc:
        print("state.py: %s" % exc, file=sys.stderr)
        return 2

    if args.json:
        st = dict(st, source="hyprctl")
        print(json.dumps(st))
    elif args.monitor:
        if not st["open"]:
            return 1
        print(st["monitor"] or "")
    elif args.check:
        return 0 if st["open"] else 1
    else:
        print("open %s" % (st["monitor"] or "") if st["open"] else "closed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
