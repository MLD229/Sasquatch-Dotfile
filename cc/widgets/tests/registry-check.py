#!/usr/bin/env python3
# registry-check.py — un widget du registre est-il RÉELLEMENT livré ?
#
# Un « widget fantôme » (tuile proposée dans le Studio, rectangle vide sur le
# canevas) n'a qu'une origine : une entrée de `registry.json` dont le fichier
# `component` n'existe pas sur le disque. Ce script applique la MÊME règle que
# `WidgetRegistry.component()` — l'URL du composant est
# `<dossier du registre>/widgets/<component>` — et compare au disque.
#
# Aucun processus graphique : lecture de fichiers uniquement. Sortie 0 si tout
# est livré, 1 sinon (utilisable en pré-commit / CI).
#
# Usage :
#   python3 cc/widgets/tests/registry-check.py [--root <dépôt>] [--json]
#
# Ce qui est vérifié :
#   1. chaque entrée du registre → composant résolu sur disque (+ taille)
#   2. fichiers `widgets/*.qml` livrés mais absents du registre (orphelins)
#   3. instances de `cc/widgets.json` dont le `type` n'est pas résolvable
#      (= fantôme affiché par l'hôte : il sera ignoré + loggé)

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))          # cc/widgets/tests
MODULE_DIR = os.path.normpath(os.path.join(HERE, "..", "Sasquatch", "Widgets"))
REGISTRY = os.path.join(MODULE_DIR, "registry.json")
COMPONENT_DIR = os.path.join(MODULE_DIR, "widgets")
INSTANCES = os.path.normpath(os.path.join(HERE, "..", "..", "widgets.json"))


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def resolve(entry):
    """(chemin, ok, raison) — même règle que WidgetRegistry.component()."""
    comp = entry.get("component")
    if not isinstance(comp, str) or not comp.strip():
        return None, False, "champ `component` vide (widget non livré)"
    path = os.path.normpath(os.path.join(COMPONENT_DIR, comp))
    if not os.path.isfile(path):
        return path, False, "fichier absent : widgets/%s" % comp
    try:
        size = os.path.getsize(path)
    except OSError as exc:
        return path, False, "illisible : %s" % exc
    if size == 0:
        return path, False, "fichier vide (0 octet)"
    return path, True, ""


def check(root=None):
    global MODULE_DIR, REGISTRY, COMPONENT_DIR, INSTANCES
    if root:
        root = os.path.abspath(root)
        MODULE_DIR = os.path.join(root, "cc", "widgets", "Sasquatch", "Widgets")
        REGISTRY = os.path.join(MODULE_DIR, "registry.json")
        COMPONENT_DIR = os.path.join(MODULE_DIR, "widgets")
        INSTANCES = os.path.join(root, "cc", "widgets.json")

    report = {"registry": REGISTRY, "entries": 0, "resolved": 0,
              "unresolved": [], "orphans": [], "ghost_instances": [],
              "instances_read": None}
    try:
        data = load_json(REGISTRY)
    except (OSError, json.JSONDecodeError) as exc:
        report["error"] = "registre illisible : %s" % exc
        return report

    entries = [w for w in (data.get("widgets") or [])
               if isinstance(w, dict) and isinstance(w.get("id"), str)]
    report["entries"] = len(entries)

    referenced = set()
    for entry in entries:
        path, ok, reason = resolve(entry)
        if ok:
            report["resolved"] += 1
            referenced.add(os.path.basename(path))
        else:
            report["unresolved"].append({"id": entry.get("id"), "reason": reason})
            if isinstance(path, str):
                referenced.add(os.path.basename(path))

    try:
        delivered = sorted(f for f in os.listdir(COMPONENT_DIR) if f.endswith(".qml"))
    except OSError:
        delivered = []
    report["orphans"] = [f for f in delivered if f not in referenced]

    by_id = {e.get("id"): e for e in entries}
    if os.path.isfile(INSTANCES):
        try:
            doc = load_json(INSTANCES)
            insts = doc.get("instances") or []
            report["instances_read"] = len(insts)
            for inst in insts:
                if not isinstance(inst, dict):
                    continue
                typ = inst.get("type")
                entry = by_id.get(typ)
                if entry is None:
                    report["ghost_instances"].append(
                        {"id": inst.get("id"), "type": typ,
                         "reason": "type absent du registre"})
                    continue
                _, ok, reason = resolve(entry)
                if not ok:
                    report["ghost_instances"].append(
                        {"id": inst.get("id"), "type": typ, "reason": reason})
        except (OSError, json.JSONDecodeError) as exc:
            report["error"] = "widgets.json illisible : %s" % exc
    return report


def main(argv):
    root = None
    as_json = False
    i = 1
    while i < len(argv):
        if argv[i] == "--root" and i + 1 < len(argv):
            root = argv[i + 1]
            i += 2
        elif argv[i] == "--json":
            as_json = True
            i += 1
        else:
            print("usage: registry-check.py [--root <dépôt>] [--json]")
            return 2

    rep = check(root)

    if as_json:
        print(json.dumps(rep, indent=2, ensure_ascii=False))
        ok = not rep.get("error") and not rep["unresolved"] and not rep["ghost_instances"]
        return 0 if ok else 1

    if rep.get("error"):
        print("ERREUR : %s" % rep["error"])
        return 1

    print("registre      : %s" % rep["registry"])
    print("composants    : %s" % COMPONENT_DIR)
    print("entrées       : %d" % rep["entries"])
    print("résolus       : %d/%d" % (rep["resolved"], rep["entries"]))
    if rep["unresolved"]:
        print("NON RÉSOLUS   : %d" % len(rep["unresolved"]))
        for item in rep["unresolved"]:
            print("  - %-14s %s" % (item["id"], item["reason"]))
    else:
        print("NON RÉSOLUS   : 0 (aucun widget fantôme dans le registre)")
    if rep["orphans"]:
        print("orphelins     : %s" % ", ".join(rep["orphans"]))
    if rep["instances_read"] is None:
        print("instances     : %s absent (créé par install.sh)" % INSTANCES)
    elif rep["ghost_instances"]:
        print("instances fantômes : %d (seront ignorées par l'hôte)"
              % len(rep["ghost_instances"]))
        for item in rep["ghost_instances"]:
            print("  - %-14s type=%-12s %s"
                  % (item["id"], item["type"], item["reason"]))
    else:
        print("instances     : %d, toutes résolues" % rep["instances_read"])

    ok = not rep["unresolved"] and not rep["ghost_instances"]
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
