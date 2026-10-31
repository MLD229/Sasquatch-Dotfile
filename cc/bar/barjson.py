#!/usr/bin/env python3
# barjson.py — écriture CHIRURGICALE de la section `apps` de bar.json.
#
# Pourquoi un script séparé : le QML ne doit pas réécrire le JSON entier
# (JSON.stringify écrase l'ordre des clés, l'indentation et les clés inconnues).
# Ici, on ne touche QUE le tableau `apps` :
#   - le reste du fichier est recopié OCTET POUR OCTET (vérifié avant écriture) ;
#   - l'indentation existante est conservée (détectée depuis le fichier) ;
#   - l'ordre des entrées existantes est conservé, une app déjà épinglée est
#     RÉACTIVÉE (enabled: true) au lieu d'être dupliquée ;
#   - écriture atomique : fichier temporaire dans le même dossier + os.replace.
#
# Usage :
#   barjson.py --pin <id>     épingler   (ou réactiver une entrée existante)
#   barjson.py --unpin <id>   détacher   (enabled: false, l'entrée reste en place)
#   barjson.py --set <cle>=<val>  une clé scalaire (bar.position=left|top|right,
#                                 appearance.blockAlpha=0.0, bar.blur=false…)
#   barjson.py [--file PATH]  bar.json par défaut = celui du dossier du script
#
# Sortie : TOUJOURS un objet JSON sur stdout, une ligne :
#   {"ok": true,  "action": "pin", "id": "spotify", "entry": {...}, "count": 4}
#   {"ok": false, "error": "message lisible"}
# Code de sortie : 0 = action traitée (ok vrai ou faux) ; 1 = plantage inattendu.
import json
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_FILE = os.path.join(HERE, "bar.json")

ENTRY_KEYS = ("id", "desktop", "class", "enabled")


# ── Utilitaires ──────────────────────────────────────────────────────────────
def norm(value):
    """Même normalisation que Hypr.norm() côté QML (minuscules alnum)."""
    return re.sub(r"[^a-z0-9]", "", (value or "").lower())


def out(obj):
    json.dump(obj, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    sys.stdout.flush()


def fail(msg):
    out({"ok": False, "error": msg})
    return 0


# ── Repérage du tableau `apps` dans le TEXTE (pas dans l'objet parsé) ────────
def match_bracket(text, start):
    """Index exclusif de la fin du bloc ouvert à `start` ('[' ou '{')."""
    depth = 0
    in_str = False
    esc = False
    for i in range(start, len(text)):
        c = text[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            continue
        if c == '"':
            in_str = True
        elif c in "[{":
            depth += 1
        elif c in "]}":
            depth -= 1
            if depth == 0:
                return i + 1
    raise ValueError("bar.json : accolade non fermée")


def find_key(text, key):
    """(debut_valeur, fin_valeur, colonne_de_la_clé) pour "key": <valeur>."""
    needle = '"%s"' % key
    idx = text.find(needle)
    while idx != -1:
        line_start = text.rfind("\n", 0, idx) + 1
        column = idx - line_start
        j = idx + len(needle)
        while j < len(text) and text[j] in " \t\r\n":
            j += 1
        if j < len(text) and text[j] == ":":
            j += 1
            while j < len(text) and text[j] in " \t\r\n":
                j += 1
            if j < len(text) and text[j] == "[":
                return j, match_bracket(text, j), column
        idx = text.find(needle, idx + 1)
    return None


def load(path):
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    return text, json.loads(text)


def render_apps(entries, column):
    """Tableau `apps` au même gabarit que le fichier existant."""
    if not entries:
        return "[]"
    pad_obj = " " * (column + 4)
    pad_fld = " " * (column + 8)
    blocks = []
    for entry in entries:
        fields = []
        for key, value in entry.items():
            fields.append(pad_fld + json.dumps(key, ensure_ascii=False) + ": "
                          + json.dumps(value, ensure_ascii=False))
        blocks.append(pad_obj + "{\n" + ",\n".join(fields) + "\n" + pad_obj + "}")
    return "[\n" + ",\n".join(blocks) + "\n" + " " * column + "]"


def write_atomic(path, text, mode):
    """Fichier temporaire dans le MÊME dossier + os.replace (atomique)."""
    folder = os.path.dirname(os.path.abspath(path)) or "."
    fd, tmp = tempfile.mkstemp(prefix=".bar.json.", suffix=".tmp", dir=folder)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, mode & 0o7777)
        os.replace(tmp, path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


# ── Résolution de l'app (index .desktop) ────────────────────────────────────
def resolve(app_id):
    sys.path.insert(0, HERE)
    import appindex  # même dossier que ce script

    index = appindex.build_index()
    app = index["apps"].get(app_id)
    if not app:
        return None
    desktop = app_id + ".desktop"          # forme des entrées existantes
    return {
        "id": app_id,
        "desktop": desktop,
        "class": app.get("class") or app_id,
        "enabled": True,
    }


def entry_matches(entry, app_id, fresh):
    """Une entrée désigne-t-elle la même app ? (id, .desktop, classe, normalisé)"""
    if not isinstance(entry, dict):
        return False
    wanted = {norm(app_id)}
    if fresh:
        wanted.add(norm(fresh["desktop"]))
        wanted.add(norm(fresh["class"]))
    for key in ("id", "desktop", "class"):
        value = entry.get(key)
        if value and norm(value) in wanted:
            return True
    # desktop "spotify.desktop" vs id "spotify"
    desk = (entry.get("desktop") or "")
    if desk and norm(re.sub(r"\.desktop$", "", desk)) in wanted:
        return True
    return False


# ── Action ──────────────────────────────────────────────────────────────────
def change(path, action, app_id):
    if not os.path.isfile(path):
        return fail("bar.json introuvable : %s" % path)
    try:
        text, root = load(path)
    except OSError as exc:
        return fail("bar.json illisible : %s" % exc)
    except ValueError as exc:
        return fail("bar.json invalide (JSON) : %s — aucune écriture" % exc)
    if not isinstance(root, dict):
        return fail("bar.json n'est pas un objet — aucune écriture")

    found = find_key(text, "apps")
    if not found:
        return fail('bar.json : aucune section "apps" — aucune écriture')
    start, end, column = found

    entries = root.get("apps")
    if not isinstance(entries, list):
        return fail('bar.json : "apps" n\'est pas un tableau — aucune écriture')
    entries = [dict(e) if isinstance(e, dict) else e for e in entries]

    fresh = None if action == "unpin" else resolve(app_id)
    if action == "pin" and fresh is None:
        return fail("application inconnue dans l'index .desktop : %s" % app_id)

    target = -1
    for i, entry in enumerate(entries):
        if entry_matches(entry, app_id, fresh):
            target = i
            break

    changed = False
    if action == "pin":
        if fresh is None:
            return fail("application inconnue dans l'index .desktop : %s" % app_id)
        if target >= 0:
            entry = entries[target]
            if entry.get("enabled") is not True:
                entry["enabled"] = True
                changed = True
            for key in ENTRY_KEYS:              # complète les champs manquants
                if key != "enabled" and not entry.get(key):
                    entry[key] = fresh[key]
                    changed = True
        else:
            entries.append(dict(fresh))
            changed = True
    else:                                        # unpin
        if target < 0:
            return fail("application non épinglée : %s" % app_id)
        entry = entries[target]
        if entry.get("enabled") is not False:
            entry["enabled"] = False
            changed = True

    result = {
        "ok": True,
        "action": action,
        "id": app_id,
        "changed": changed,
        "entry": entries[target] if target >= 0 else entries[-1],
        "count": sum(1 for e in entries
                     if isinstance(e, dict) and e.get("enabled") is not False),
    }
    if not changed:
        result["note"] = "déjà dans l'état demandé"
        out(result)
        return 0

    # Le SEUL morceau remplacé est la valeur de "apps".
    body = render_apps(entries, column)
    new_text = text[:start] + body + text[end:]

    # Garde-fou : JSON valide ET tout le reste identique, sinon on n'écrit rien.
    try:
        check = json.loads(new_text)
    except ValueError as exc:
        return fail("réécriture invalide (%s) — aucune écriture" % exc)
    before = {k: v for k, v in root.items() if k != "apps"}
    after = {k: v for k, v in check.items() if k != "apps"}
    if before != after:
        return fail("une autre section que `apps` aurait bougé — aucune écriture")
    if before.keys() != after.keys():
        return fail("ordre des sections modifié — aucune écriture")

    if not os.access(path, os.W_OK):
        return fail("bar.json en lecture seule (%s) — aucune écriture" % path)

    mode = os.stat(path).st_mode
    try:
        write_atomic(path, new_text, mode)
    except OSError as exc:
        return fail("écriture impossible : %s — fichier inchangé" % exc)

    out(result)
    return 0


# ── Écriture d'une clé scalaire (--set, v5a) ────────────────────────────────
# Table de bornes : une clé absente d'ici est REFUSÉE. Le panneau Settings ne
# doit pas pouvoir écrire n'importe quoi dans le fichier de la barre.
#   (min, max)   → nombre borné
#   (None, tuple) → choix fermé (chaîne)
#   (None, None)  → booléen true/false
SET_BOUNDS = {
    # v5b : trois positions honorées par la barre (left | top | right).
    # "top" = barre horizontale : les quatre groupes passent en Row et la
    # hauteur de la surface vaut bar.width (voir cc/bar/shell.qml).
    "bar.position": (None, ("left", "top", "right")),
    "bar.width": (32, 64),
    "bar.blur": (None, None),
    "bar.persistentWorkspaces": (0, 12),
    "appearance.panelAlpha": (0.0, 1.0),
    # v5b : fond des pilules. blockAlpha 0 = aucun fond au repos (défaut).
    "appearance.blockAlpha": (0.0, 1.0),
    "appearance.hoverAlpha": (0.0, 1.0),
    "appearance.activeAlpha": (0.0, 1.0),
    "appearance.cardAlpha": (0.5, 1.0),
    "runningApps.maxVisible": (1, 6),
}


def _scalar_span(text, key):
    """(debut, fin) de la valeur SCALAIRE de "key" dans le texte, sinon None."""
    needle = '"%s"' % key
    idx = text.find(needle)
    while idx != -1:
        j = idx + len(needle)
        while j < len(text) and text[j] in " \t\r\n":
            j += 1
        if j < len(text) and text[j] == ":":
            j += 1
            while j < len(text) and text[j] in " \t\r\n":
                j += 1
            if j < len(text) and text[j] not in "[{":
                if text[j] == '"':
                    k = j + 1
                    while k < len(text):
                        if text[k] == "\\":
                            k += 2
                            continue
                        if text[k] == '"':
                            return j, k + 1
                        k += 1
                    return None
                k = j
                while k < len(text) and text[k] not in ",\n]}":
                    k += 1
                end = k
                while end > j and text[end - 1] in " \t\r":
                    end -= 1
                return j, end
        idx = text.find(needle, idx + 1)
    return None


def _object_span(text, key):
    """(debut, fin, colonne) du bloc OBJET de "key", sinon None."""
    needle = '"%s"' % key
    idx = text.find(needle)
    while idx != -1:
        column = idx - (text.rfind("\n", 0, idx) + 1)
        j = idx + len(needle)
        while j < len(text) and text[j] in " \t\r\n":
            j += 1
        if j < len(text) and text[j] == ":":
            j += 1
            while j < len(text) and text[j] in " \t\r\n":
                j += 1
            if j < len(text) and text[j] == "{":
                return j, match_bracket(text, j), column
        idx = text.find(needle, idx + 1)
    return None


def set_key(path, assignment):
    """--set <chemin>=<valeur> : une seule clé, formatage du fichier préservé."""
    if "=" not in assignment:
        return fail("--set exige <chemin>=<valeur>")
    dotted, raw = assignment.split("=", 1)
    dotted = dotted.strip()
    raw = raw.strip()
    if dotted not in SET_BOUNDS:
        return fail("clé non autorisée : %s" % dotted)

    text, data = load(path)
    lo, hi = SET_BOUNDS[dotted]
    if hi is None:
        low = raw.lower()
        if low not in ("true", "false"):
            return fail("%s : booléen attendu (true|false)" % dotted)
        value = low == "true"
        rendered = "true" if value else "false"
    elif isinstance(hi, tuple):
        if raw not in hi:
            return fail("%s : valeur attendue parmi %s" % (dotted, ", ".join(hi)))
        value = raw
        rendered = json.dumps(raw, ensure_ascii=False)
    else:
        try:
            value = float(raw) if ("." in raw or "e" in raw.lower()) else int(raw)
        except ValueError:
            return fail("%s : nombre attendu" % dotted)
        if (lo is not None and value < lo) or (hi is not None and value > hi):
            return fail("%s hors bornes [%s, %s]" % (dotted, lo, hi))
        rendered = ("%g" % value) if isinstance(value, float) else str(value)

    parts = dotted.split(".")
    key = parts[-1]
    span = _scalar_span(text, key)
    if span:
        new_text = text[:span[0]] + rendered + text[span[1]:]
    else:
        # La clé n'existe pas encore : on l'insère dans sa section, ou on crée
        # la section au niveau racine (cas runningApps).
        if len(parts) == 1:
            return fail("clé racine absente : %s" % dotted)
        parent = parts[-2]
        block = _object_span(text, parent)
        if block:
            close = block[1] - 1
            body = text[block[0] + 1:close]
            indent = " " * (block[2] + 4)
            for line in body.split("\n"):
                if line.strip():
                    indent = line[:len(line) - len(line.lstrip())]
                    break
            inner = body.rstrip()
            closing_indent = " " * block[2]
            addition = '%s"%s": %s' % (indent, key, rendered)
            if inner.strip():
                new_body = inner + ",\n" + addition + "\n" + closing_indent
            else:
                new_body = "\n" + addition + "\n" + closing_indent
            new_text = text[:block[0] + 1] + new_body + text[close:]
        else:
            # Section racine absente : insérée avant la dernière accolade.
            root_close = text.rstrip().rfind("}")
            if root_close == -1:
                return fail("bar.json : racine introuvable")
            inner = text[:root_close].rstrip()
            addition = ('    "%s": {\n        "%s": %s\n    }\n'
                        % (parent, key, rendered))
            new_text = inner + ",\n" + addition + text[root_close:]

    try:
        parsed = json.loads(new_text)          # vérif : le résultat reste du JSON
    except ValueError as exc:
        return fail("écriture refusée (JSON invalide après édition) : %s" % exc)
    node = parsed
    for part in parts:
        node = node.get(part) if isinstance(node, dict) else None
        if node is None:
            break
    if node != value:
        return fail("écriture refusée (valeur relue != demandée)")
    if new_text == text:
        out({"ok": True, "action": "set", "key": dotted, "value": value,
             "changed": False})
        return 0
    try:
        mode = os.stat(path).st_mode
        write_atomic(path, new_text, mode)
    except OSError as exc:
        return fail("écriture impossible : %s" % exc)
    out({"ok": True, "action": "set", "key": dotted, "value": value,
         "changed": True})
    return 0


def main(argv):
    path = DEFAULT_FILE
    if "--file" in argv:
        i = argv.index("--file")
        if i + 1 >= len(argv):
            return fail("--file exige un chemin")
        path = os.path.abspath(argv[i + 1])
    if "--set" in argv:
        i = argv.index("--set")
        if i + 1 >= len(argv):
            return fail("--set exige <chemin>=<valeur>")
        return set_key(path, argv[i + 1])
    for action, flag in (("pin", "--pin"), ("unpin", "--unpin")):
        if flag in argv:
            i = argv.index(flag)
            if i + 1 >= len(argv):
                return fail("%s exige un identifiant d'application" % flag)
            return change(path, action, argv[i + 1])
    print(__doc__ or "barjson.py --pin <id> | --unpin <id> | --set <cle>=<val> [--file PATH]",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as exc:                      # jamais de trace dans le QML
        out({"ok": False, "error": "%s: %s" % (type(exc).__name__, exc)})
        sys.exit(1)
