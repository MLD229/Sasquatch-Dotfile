#!/usr/bin/env python3
"""notes.py — notes courtes du CC (widget `notes`).

Fichier : ~/.config/cc/notes.json (surcharge de test : SASQUATCH_NOTES_JSON).
Écriture ATOMIQUE (temporaire dans le même dossier + os.replace), puis
RELECTURE : c'est la liste relue qui est renvoyée (jamais une supposition).

Format :
  {"version": 1, "notes": [{"id": 3, "text": "...", "at": 1762...}, ...]}
  Les notes les plus récentes sont en tête (insertion en position 0).

API :
  get()          -> {"ok": True, "notes": [...], "count": n, "file": "<path>"}
  apply(op)      -> même chose après écriture + relecture
                    op = {"op": "add", "text": "..."} | {"op": "rm", "id": 3}
                         | {"op": "clear"}
                    lève OpError (ValueError) si l'opération est invalide.

CLI (tests) : notes.py get | notes.py apply '{"op":"add","text":"..."}'
"""

import json
import os
import sys
import tempfile
import time

NOTES_FILE = os.environ.get("SASQUATCH_NOTES_JSON") or os.path.join(
    os.path.expanduser("~"), ".config", "cc", "notes.json")

MAX_NOTES = 100
MAX_TEXT = 400


class OpError(ValueError):
    """Opération refusée (message lisible destiné au client HTTP)."""


def _default():
    return {"version": 1, "notes": []}


def _read():
    try:
        with open(NOTES_FILE, encoding="utf-8") as fh:
            doc = json.load(fh)
    except FileNotFoundError:
        return _default()
    except OSError as exc:
        raise OpError("notes.json illisible : %s" % exc)
    except json.JSONDecodeError as exc:
        raise OpError("notes.json invalide : %s" % exc)
    if not isinstance(doc, dict) or not isinstance(doc.get("notes"), list):
        raise OpError("notes.json invalide (tableau `notes` attendu)")
    doc["version"] = 1
    doc["notes"] = [n for n in doc["notes"] if isinstance(n, dict) and "id" in n]
    return doc


def _write(doc):
    """Écriture atomique (jamais de JSON tronqué si le process meurt)."""
    folder = os.path.dirname(NOTES_FILE) or "."
    os.makedirs(folder, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".notes.json.", suffix=".tmp", dir=folder)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(doc, fh, indent=4, ensure_ascii=False)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        try:
            os.chmod(tmp, 0o644)
        except OSError:
            pass
        os.replace(tmp, NOTES_FILE)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _report(doc):
    notes = doc.get("notes") or []
    return {"ok": True, "notes": notes, "count": len(notes), "file": NOTES_FILE}


def _next_id(notes):
    best = 0
    for n in notes:
        try:
            value = int(n.get("id"))
        except (TypeError, ValueError):
            continue
        best = max(best, value)
    return best + 1


def get():
    return _report(_read())


def apply(op):
    if not isinstance(op, dict):
        raise OpError("opération attendue (objet JSON)")
    kind = op.get("op")
    doc = _read()
    notes = doc["notes"]

    if kind == "add":
        text = op.get("text")
        if not isinstance(text, str):
            raise OpError("champ `text` manquant")
        text = " ".join(text.split())
        if not text:
            raise OpError("note vide")
        if len(text) > MAX_TEXT:
            text = text[:MAX_TEXT]
        notes.insert(0, {"id": _next_id(notes), "text": text, "at": int(time.time())})
        doc["notes"] = notes[:MAX_NOTES]

    elif kind == "rm":
        try:
            target = int(op.get("id"))
        except (TypeError, ValueError):
            raise OpError("champ `id` manquant ou non numérique")
        kept = [n for n in notes if int(n.get("id", -1) or -1) != target]
        if len(kept) == len(notes):
            raise OpError("note inconnue : %r" % op.get("id"))
        doc["notes"] = kept

    elif kind == "clear":
        doc["notes"] = []

    else:
        raise OpError("opération inconnue : %r" % kind)

    _write(doc)
    return _report(_read())


def main(argv):
    try:
        if len(argv) >= 1 and argv[0] == "get":
            out = get()
        elif len(argv) >= 2 and argv[0] == "apply":
            out = apply(json.loads(argv[1]))
        else:
            out = {"ok": False, "error": "usage : notes.py get|apply <json>"}
    except (OpError, json.JSONDecodeError) as exc:
        out = {"ok": False, "error": str(exc)}
    json.dump(out, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
