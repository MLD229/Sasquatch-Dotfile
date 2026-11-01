#!/usr/bin/env python3
"""widgets_json.py — écrivain UNIQUE de cc/widgets.json (brief widgets v1 §4).

Le QML (Studio, drag, panneau de style) et la barre ne réécrivent JAMAIS le
fichier : ils passent par POST /api/widgets, donc par `apply()` ici.

Règles appliquées (brief §4) :
  - `type` validé contre le registre (`cc/widgets/Sasquatch/Widgets/registry.json`) ;
  - chaque nombre clampé sur les bornes du registre (alpha, blur, radius, options) ;
  - clé inconnue = refus explicite (jamais d'écriture silencieuse d'un champ
    qu'on ne comprend pas) ;
  - `revision` incrémentée à chaque écriture ;
  - écriture atomique (temporaire dans le même dossier + os.replace), 4 espaces ;
  - APRÈS écriture : relecture obligatoire du fichier, et c'est la version
    relue qui est renvoyée ({"ok": true, "revision": N, "instance": {...}}).

Placement (brief bugs §1) :
  - `add` sur `cc` choisit la PREMIÈRE CELLULE LIBRE de la grille 12 colonnes
    (balayage haut → bas, gauche → droite) : deux ajouts ne se recouvrent jamais ;
  - `add` sur `background` décale en cascade (0.02 par instance) puis cherche
    une place libre, et borne toujours `x + w/écran <= 1` (l'écran réel vient du
    champ optionnel `screen: {w, h}` ; sinon 1920x1080) ;
  - identifiants `<type>-<n>` monotones, compteur persisté dans `seq` : un id
    supprimé n'est jamais réattribué ;
  - `variant` recale la géométrie sur la taille naturelle de la nouvelle
    variante (cellules pour `cc`, w/h px pour `background`).

API :
  get()               -> document complet ({"version","revision","instances"})
  apply(op)           -> {"ok": true, "revision": N, "instance": {...}}
                         lève OpError (ValueError) si l'opération est invalide.

Opérations : add | rm | move | resize | style | variant | option | reorder | autoplace

`autoplace` (brief autoplace) ne calcule RIEN ici : cc/autoplace.py fournit les
géométries (fonctions pures), ce module les valide avec `_geo` puis écrit une
seule révision. Tout ou rien : si un widget n'a pas de place, `autoplace`
répond {"ok": false, "unplaced": [...], "reason": "..."} et le fichier n'est
PAS touché (aucune révision, rien de déplacé).

CLI (pour les tests et Asuka) :
  widgets_json.py get
  widgets_json.py apply '{"op": "move", "id": "clock-bg", "geo": {"x": 1.4}}'
  widgets_json.py apply -           # lit l'opération JSON sur stdin
Sortie : une ligne JSON sur stdout, toujours. Code 0 = opération traitée,
2 = plantage inattendu (traceback sur stderr).
"""

import json
import os
import sys
import tempfile

import autoplace

HERE = os.path.dirname(os.path.abspath(__file__))

# Surcharges d'environnement : les tests tournent sur une copie, sans jamais
# toucher le widgets.json du service.
REGISTRY_FILE = os.environ.get("SASQUATCH_REGISTRY_JSON") or os.path.join(
    HERE, "widgets", "Sasquatch", "Widgets", "registry.json")
WIDGETS_FILE = os.environ.get("SASQUATCH_WIDGETS_JSON") or os.path.join(
    HERE, "widgets.json")

GRID_COLUMNS = 12
GRID_ROWS_MAX = 64
FREE_MIN_W = 120
FREE_MIN_H = 64
FREE_MAX = 8192
SLOT_MAX = 64
# Écran de repli quand le client ne dit pas sa taille (curl, tests) : sert
# seulement à borner `x + w/écran <= 1`, jamais à décider d'un rendu.
NOMINAL_SCREEN = (1920, 1080)
# Cascade d'ajout sur le fond (brief bugs §1.2) : +0.02 par instance.
CASCADE_STEP = 0.02
GEO_KEYS = {
    "cc": ("col", "row", "w", "h"),
    "background": ("x", "y", "w", "h"),
    "bar": ("slot",),
    "subpage": ("slot",),
}
STYLE_KEYS = ("alpha", "accent", "blur", "radius")
HOSTS = ("background", "cc", "bar", "subpage")


class OpError(ValueError):
    """Opération refusée (message lisible destiné au client HTTP)."""


# ── Utilitaires ─────────────────────────────────────────────────────────────
def _num(value, name):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise OpError("%s doit être un nombre" % name)
    return float(value)


def _clamp(value, low, high):
    return max(low, min(high, value))


def _int(value, name, low, high):
    return int(round(_clamp(_num(value, name), low, high)))


def load_registry():
    """{id: entrée} depuis le registre embarqué (seule source des chemins)."""
    try:
        with open(REGISTRY_FILE, encoding="utf-8") as f:
            data = json.load(f)
    except OSError as exc:
        raise OpError("registre illisible : %s" % exc)
    except json.JSONDecodeError as exc:
        raise OpError("registre invalide : %s" % exc)
    entries = {}
    for item in data.get("widgets") or []:
        if isinstance(item, dict) and isinstance(item.get("id"), str):
            entries[item["id"]] = item
    return entries


def default_document():
    return {"version": 1, "revision": 0, "seq": {}, "instances": []}


def _read():
    try:
        with open(WIDGETS_FILE, encoding="utf-8") as f:
            doc = json.load(f)
    except FileNotFoundError:
        return default_document()
    except OSError as exc:
        raise OpError("widgets.json illisible : %s" % exc)
    except json.JSONDecodeError as exc:
        raise OpError("widgets.json invalide : %s" % exc)
    if not isinstance(doc, dict) or not isinstance(doc.get("instances"), list):
        raise OpError("widgets.json invalide (tableau `instances` attendu)")
    if not isinstance(doc.get("version"), int):
        doc["version"] = 1
    if not isinstance(doc.get("revision"), int):
        doc["revision"] = 0
    # Compteurs d'identifiants : jamais remis à zéro, même après une
    # suppression (brief bugs §1.3).
    if not isinstance(doc.get("seq"), dict):
        doc["seq"] = {}
    return doc


def _write(doc):
    """Écriture atomique, 4 espaces d'indentation, puis relecture."""
    folder = os.path.dirname(WIDGETS_FILE) or "."
    fd, tmp = tempfile.mkstemp(prefix=".widgets.json.", suffix=".tmp", dir=folder)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(doc, f, indent=4, ensure_ascii=False)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        try:
            os.chmod(tmp, 0o644)
        except OSError:
            pass
        os.replace(tmp, WIDGETS_FILE)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


# ── Validation ─────────────────────────────────────────────────────────────
def _entry(registry, widget_type):
    entry = registry.get(widget_type)
    if entry is None:
        raise OpError("type inconnu : %r" % widget_type)
    return entry


def _require_component(entry):
    if not (entry.get("component") or "").strip():
        raise OpError("widget %r non livré (composant vide)" % entry.get("id"))


def _host(entry, host):
    if host not in HOSTS:
        raise OpError("hôte inconnu : %r" % host)
    if host not in (entry.get("hosts") or []):
        raise OpError("hôte %r non autorisé pour %r" % (host, entry.get("id")))
    return host


def _variant(entry, variant):
    variants = entry.get("variants") or {}
    if variant is None:
        variant = entry.get("defaultVariant") or (list(variants)[0] if variants else "normal")
    if variant not in variants:
        raise OpError("variante inconnue pour %r : %r" % (entry.get("id"), variant))
    return variant


def _variant_cell(entry, variant):
    spec = (entry.get("variants") or {}).get(variant) or {}
    cell = spec.get("cell") or [4, 2]
    return {
        "w": int(spec.get("w") or 360),
        "h": int(spec.get("h") or 180),
        "cell": [int(cell[0]) if len(cell) > 0 else 4,
                 int(cell[1]) if len(cell) > 1 else 2],
    }


def _screen(op, fallback=None):
    """(w, h) de l'écran réel si le client le dit, sinon repli nominal.

    Le fond est en FRACTIONS : sans la largeur réelle, impossible de garantir
    `x + w/écran <= 1` (brief bugs §1.2). Le Studio et l'hôte de fond envoient
    donc `screen: {w, h}` ; un curl sans ce champ retombe sur 1920x1080.
    """
    fallback = fallback or NOMINAL_SCREEN
    src = op.get("screen") if isinstance(op, dict) else None
    if not isinstance(src, dict):
        return fallback
    raw_w = src.get("w")
    raw_h = src.get("h")
    if not isinstance(raw_w, (int, float)) or not isinstance(raw_h, (int, float)):
        return fallback
    w = int(round(float(raw_w)))
    h = int(round(float(raw_h)))
    if w < 200 or h < 200:
        return fallback
    return (w, h)


def _geo(host, geo, ref=None, keys=None, screen=None):
    """Geo validée et clampée pour `host`. `ref` = geo existante (patch partiel)."""
    if geo is None:
        geo = {}
    if not isinstance(geo, dict):
        raise OpError("geo doit être un objet")
    allowed = keys if keys is not None else GEO_KEYS[host]
    base = dict(ref or {})
    for key, value in geo.items():
        if key not in allowed:
            raise OpError("clé geo inconnue pour l'hôte %s : %r" % (host, key))
        base[key] = value

    if host == "cc":
        col = _int(base.get("col", 0), "geo.col", 0, GRID_COLUMNS - 1)
        row = _int(base.get("row", 0), "geo.row", 0, GRID_ROWS_MAX)
        width = _int(base.get("w", 4), "geo.w", 1, GRID_COLUMNS)
        height = _int(base.get("h", 2), "geo.h", 1, GRID_ROWS_MAX)
        width = min(width, GRID_COLUMNS)
        col = min(col, GRID_COLUMNS - width)
        return {"col": col, "row": row, "w": width, "h": height}
    if host == "background":
        scr_w, scr_h = screen or NOMINAL_SCREEN
        width = _int(base.get("w", 360), "geo.w", FREE_MIN_W, FREE_MAX)
        height = _int(base.get("h", 180), "geo.h", FREE_MIN_H, FREE_MAX)
        # x + w/écran <= 1 : la borne dépend de la taille du widget.
        max_x = max(0.0, 1.0 - width / float(scr_w))
        max_y = max(0.0, 1.0 - height / float(scr_h))
        return {
            "x": round(_clamp(_num(base.get("x", 0.0), "geo.x"), 0.0, max_x), 4),
            "y": round(_clamp(_num(base.get("y", 0.0), "geo.y"), 0.0, max_y), 4),
            "w": width,
            "h": height,
        }
    return {"slot": _int(base.get("slot", 0), "geo.slot", 0, SLOT_MAX)}


# ── Placement automatique (brief bugs §1.1) ──────────────────────────────
def _cells_taken(doc, host, skip_id=None):
    """Ensemble des cellules (col, row) occupées par les instances de `host`."""
    taken = set()
    for inst in doc["instances"]:
        if not isinstance(inst, dict) or inst.get("host") != host:
            continue
        if skip_id is not None and inst.get("id") == skip_id:
            continue
        g = inst.get("geo") or {}
        col = int(g.get("col", 0) or 0)
        row = int(g.get("row", 0) or 0)
        width = max(1, int(g.get("w", 4) or 4))
        height = max(1, int(g.get("h", 2) or 2))
        for c in range(col, min(GRID_COLUMNS, col + width)):
            for r in range(row, row + height):
                taken.add((c, r))
    return taken


def _free_grid(doc, width, height, skip_id=None, rows=None):
    """Première cellule libre, balayage haut → bas puis gauche → droite.

    Jamais un coin fixe : deux `add` successifs du même type ne se recouvrent
    pas (brief bugs §1.1). Si la grille est pleine, on repart à (0, 0).
    """
    taken = _cells_taken(doc, "cc", skip_id)
    width = max(1, min(GRID_COLUMNS, int(width)))
    height = max(1, int(height))
    for row in range(0, rows or GRID_ROWS_MAX):
        for col in range(0, GRID_COLUMNS - width + 1):
            free = True
            for c in range(col, col + width):
                if not free:
                    break
                for r in range(row, row + height):
                    if (c, r) in taken:
                        free = False
                        break
            if free:
                return col, row
    return 0, 0


def _grid_free_at(doc, instance_id, col, row, width, height):
    """Vrai si le bloc (col,row,w,h) ne touche aucune AUTRE instance `cc`."""
    taken = _cells_taken(doc, "cc", instance_id)
    if col < 0 or col + width > GRID_COLUMNS or row < 0:
        return False
    for c in range(col, col + width):
        for r in range(row, row + height):
            if (c, r) in taken:
                return False
    return True


def _background_rects(doc, screen):
    """Rectangles px des instances de fond, pour le test de chevauchement."""
    scr_w, scr_h = screen
    out = []
    for inst in doc["instances"]:
        if not isinstance(inst, dict) or inst.get("host") != "background":
            continue
        g = inst.get("geo") or {}
        try:
            x = float(g.get("x", 0.0)) * scr_w
            y = float(g.get("y", 0.0)) * scr_h
            w = float(g.get("w", 360))
            h = float(g.get("h", 180))
        except (TypeError, ValueError):
            continue
        out.append((x, y, w, h))
    return out


def _free_fraction(doc, width, height, screen, skip_id=None):
    """Position libre du fond : cascade de 0.02 par instance, puis balayage.

    Le décalage en cascade est demandé (brief bugs §1.2) ; le balayage n'entre
    en jeu que si la cascade tombe sur un widget déjà posé. Aucun chevauchement
    tant qu'il reste de la place, et `x + w/écran <= 1` dans tous les cas.
    """
    scr_w, scr_h = screen
    width = float(width)
    height = float(height)
    max_x = max(0.0, 1.0 - width / float(scr_w))
    max_y = max(0.0, 1.0 - height / float(scr_h))
    occupied = [(r[0], r[1], r[2], r[3]) for r in _background_rects(doc, screen)]

    def free(x, y):
        px, py = x * scr_w, y * scr_h
        for (ox, oy, ow, oh) in occupied:
            if px < ox + ow and ox < px + width and py < oy + oh and oy < py + height:
                return False
        return True

    n = len([i for i in doc["instances"]
             if isinstance(i, dict) and i.get("host") == "background"
             and i.get("id") != skip_id])
    base = 0.5 + CASCADE_STEP * n
    for k in range(0, 60):
        x = _clamp(base + CASCADE_STEP * k, 0.0, max_x)
        y = _clamp(base + CASCADE_STEP * k, 0.0, max_y)
        if free(x, y):
            return round(x, 4), round(y, 4)

    # Cascade bloquée (bord d'écran) : balayage complet, pas à pas.
    y = 0.0
    while y <= max_y:
        x = 0.0
        while x <= max_x:
            if free(x, y):
                return round(x, 4), round(y, 4)
            x += CASCADE_STEP
        y += CASCADE_STEP
    return round(max_x, 4), round(max_y, 4)


def _style(entry, style, ref=None):
    bounds = entry.get("style") or {}
    alpha_b = bounds.get("alpha") or [0.03, 0.35]
    blur_b = bounds.get("blur") or [0, 20]
    radius_b = bounds.get("radius") or [0, 24]
    accents = bounds.get("accent") or ["auto"]

    if style is None:
        style = {}
    if not isinstance(style, dict):
        raise OpError("style doit être un objet")
    base = dict(ref or {})
    for key, value in style.items():
        if key not in STYLE_KEYS:
            raise OpError("clé style inconnue : %r" % key)
        base[key] = value

    accent = base.get("accent", "auto")
    if accent not in accents:
        raise OpError("accent inconnu : %r (autorisés : %s)" % (accent, ", ".join(accents)))
    return {
        "alpha": round(_clamp(_num(base.get("alpha", 0.08), "style.alpha"),
                              float(alpha_b[0]), float(alpha_b[1])), 3),
        "accent": accent,
        "blur": _int(base.get("blur", 9), "style.blur", int(blur_b[0]), int(blur_b[1])),
        "radius": _int(base.get("radius", 16), "style.radius",
                       int(radius_b[0]), int(radius_b[1])),
    }


def _options(entry, options, ref=None):
    specs = entry.get("options") or {}
    if options is None:
        options = {}
    if not isinstance(options, dict):
        raise OpError("options doit être un objet")
    base = dict(ref or {})
    for key, value in options.items():
        if key not in specs:
            raise OpError("option inconnue pour %r : %r" % (entry.get("id"), key))
        base[key] = value

    out = {}
    for key, spec in specs.items():
        value = base.get(key, spec.get("default"))
        kind = spec.get("type")
        if kind == "int":
            out[key] = _int(value, "option %s" % key,
                            int(spec.get("min", 0)), int(spec.get("max", 1000)))
        elif kind == "bool":
            if not isinstance(value, bool):
                raise OpError("option %s : booléen attendu" % key)
            out[key] = value
        elif kind == "enum":
            allowed = spec.get("values") or []
            if value not in allowed:
                raise OpError("option %s : valeur %r hors de %s" % (key, value, allowed))
            out[key] = value
        elif kind == "string":
            if not isinstance(value, str):
                raise OpError("option %s : chaîne attendue" % key)
            out[key] = value
        else:
            out[key] = value
    return out


def _find(doc, instance_id):
    if not isinstance(instance_id, str) or not instance_id:
        raise OpError("id d'instance manquant")
    for index, inst in enumerate(doc["instances"]):
        if isinstance(inst, dict) and inst.get("id") == instance_id:
            return index, inst
    raise OpError("instance inconnue : %r" % instance_id)


def _bump_seq(doc, widget_type, instance_id):
    """Un id explicite (`clock-7`) pousse le compteur au-delà : jamais réutilisé."""
    tail = instance_id.rsplit("-", 1)[-1]
    if not tail.isdigit():
        return
    seq = doc.setdefault("seq", {})
    seq[widget_type] = max(int(seq.get(widget_type) or 0), int(tail))


def _unique_id(doc, widget_type, wanted=None):
    """`<type>-<n>` monotone : un id supprimé ne revient JAMAIS (brief §1.3).

    Le compteur vit dans le document (`seq`), pas dans les instances : une
    suppression ne le fait donc pas reculer, et deux instances du même type ne
    peuvent pas se retrouver avec le même identifiant.
    """
    taken = {inst.get("id") for inst in doc["instances"] if isinstance(inst, dict)}
    seq = doc.setdefault("seq", {})
    if isinstance(wanted, str) and wanted and wanted not in taken:
        _bump_seq(doc, widget_type, wanted)
        return wanted
    number = int(seq.get(widget_type) or 0)
    while True:
        number += 1
        candidate = "%s-%d" % (widget_type, number)
        if candidate not in taken:
            break
    seq[widget_type] = number
    return candidate


def _reslot_order(doc):
    """Les hôtes bar/subpage sont ordonnés : slot = position dans le fichier."""
    slot = 0
    for inst in doc["instances"]:
        if isinstance(inst, dict) and inst.get("host") in ("bar", "subpage"):
            inst["geo"] = {"slot": slot}
            slot += 1


def _wallpaper_context():
    """(chemin, lumgrid) du fond courant — jamais bloquant : au pire (None, None).

    `wallpaper.lumgrid()` est déjà en cache par (chemin, mtime, taille) : la
    luminance n'est pas recalculée à chaque placement. Une machine sans PIL ou
    sans wallpaper retombe sur (None, None) et `autoplace` choisit son repli.
    """
    try:
        import wallpaper as wallpaper_mod
        grid = wallpaper_mod.lumgrid()
    except Exception:
        return None, None
    if not isinstance(grid, dict):
        return None, None
    path = grid.get("wallpaper") or None
    if not grid.get("values"):
        return path, None
    return path, grid


# ── API ────────────────────────────────────────────────────────────────────
def get():
    """Document complet (l'appelant l'enveloppe : {"ok":true,"revision":N,"data":…})."""
    return _read()


def apply(op):
    """Applique UNE opération, écrit, relit, renvoie la nouvelle révision."""
    if not isinstance(op, dict):
        raise OpError("opération attendue (objet JSON)")
    kind = op.get("op")
    if not isinstance(kind, str):
        raise OpError("champ `op` manquant")
    if kind not in ("add", "rm", "move", "resize", "style", "variant", "option",
                    "reorder", "autoplace"):
        raise OpError("opération inconnue : %r" % kind)

    registry = load_registry()
    doc = _read()
    instance = None
    extra = None

    if kind == "add":
        widget_type = op.get("type")
        if not isinstance(widget_type, str):
            raise OpError("champ `type` manquant")
        entry = _entry(registry, widget_type)
        # Type déclaré mais non livré : refus net, jamais une instance fantôme
        # que l'hôte ne saurait pas dessiner (brief bugs §1.5).
        _require_component(entry)

        host = _host(entry, op.get("host") or (entry.get("hosts") or ["cc"])[0])
        variant = _variant(entry, op.get("variant"))
        cell = _variant_cell(entry, variant)
        screen = _screen(op)

        if host == "cc":
            # Première cellule libre de la grille 12 colonnes (jamais un coin
            # fixe : deux ajouts ne peuvent pas se recouvrir).
            col, row = _free_grid(doc, cell["cell"][0], cell["cell"][1])
            default_geo = {"col": col, "row": row,
                           "w": cell["cell"][0], "h": cell["cell"][1]}
        elif host == "background":
            fx, fy = _free_fraction(doc, cell["w"], cell["h"], screen)
            default_geo = {"x": fx, "y": fy, "w": cell["w"], "h": cell["h"]}
        else:
            default_geo = {"slot": len([i for i in doc["instances"]
                                        if isinstance(i, dict) and i.get("host") == host])}
        geo = _geo(host, op.get("geo") or default_geo, ref=default_geo, screen=screen)

        instance = {
            "id": _unique_id(doc, widget_type, op.get("id") if isinstance(op.get("id"), str) else None),
            "type": widget_type,
            "host": host,
            "variant": variant,
            "geo": geo,
            "style": _style(entry, op.get("style")),
            "options": _options(entry, op.get("options")),
        }
        doc["instances"].append(instance)

    elif kind == "rm":
        index, instance = _find(doc, op.get("id"))
        del doc["instances"][index]
        _reslot_order(doc)
        instance = {"id": instance["id"]}

    elif kind in ("move", "resize"):
        _, instance = _find(doc, op.get("id"))
        entry = _entry(registry, instance.get("type"))
        host = _host(entry, instance.get("host"))
        keys = GEO_KEYS[host] if kind == "move" else ("w", "h")
        if host in ("bar", "subpage") and kind == "resize":
            raise OpError("hôte %s : pas de resize (l'ordre fait la place)" % host)
        instance["geo"] = _geo(host, op.get("geo") or {}, ref=instance.get("geo"),
                               keys=keys, screen=_screen(op))

    elif kind == "style":
        _, instance = _find(doc, op.get("id"))
        entry = _entry(registry, instance.get("type"))
        instance["style"] = _style(entry, op.get("style"), ref=instance.get("style"))

    elif kind == "variant":
        _, instance = _find(doc, op.get("id"))
        entry = _entry(registry, instance.get("type"))
        new_variant = _variant(entry, op.get("variant"))
        instance["variant"] = new_variant
        # La variante définit la taille : on recale la géométrie dessus, sinon
        # « compact » garderait la place du « hero » (brief bugs §2).
        cell = _variant_cell(entry, new_variant)
        host = instance.get("host")
        if host == "cc":
            geo = dict(instance.get("geo") or {})
            width = min(GRID_COLUMNS, cell["cell"][0])
            height = max(1, cell["cell"][1])
            col = int(geo.get("col", 0) or 0)
            row = int(geo.get("row", 0) or 0)
            col = min(col, GRID_COLUMNS - width)
            if not _grid_free_at(doc, instance.get("id"), col, row, width, height):
                col, row = _free_grid(doc, width, height,
                                      skip_id=instance.get("id"),
                                      rows=max(row + height, 1) + GRID_ROWS_MAX // 2)
            geo.update({"col": col, "row": row, "w": width, "h": height})
            instance["geo"] = _geo("cc", geo, ref=geo)
        elif host == "background":
            screen = _screen(op)
            geo = dict(instance.get("geo") or {})
            geo.update({"w": cell["w"], "h": cell["h"]})
            instance["geo"] = _geo("background", geo, ref=geo, screen=screen)

    elif kind == "option":
        _, instance = _find(doc, op.get("id"))
        entry = _entry(registry, instance.get("type"))
        key = op.get("key")
        if not isinstance(key, str) or key not in (entry.get("options") or {}):
            raise OpError("option inconnue pour %r : %r" % (entry.get("id"), key))
        if "value" not in op:
            raise OpError("champ `value` manquant")
        instance["options"] = _options(entry, {key: op["value"]}, ref=instance.get("options"))

    elif kind == "reorder":
        index, instance = _find(doc, op.get("id"))
        target = _int(op.get("to"), "to", 0, max(0, len(doc["instances"]) - 1))
        doc["instances"].insert(target, doc["instances"].pop(index))
        _reslot_order(doc)
        instance = {"id": instance["id"], "to": target}

    elif kind == "autoplace":
        # Placement intelligent (brief autoplace) : le calcul vit dans
        # cc/autoplace.py (fonctions pures, testables) ; l'écriture reste ICI.
        # Tout ou rien : si un widget n'a pas de place, `place()` renvoie
        # ok:false et on sort AVANT toute écriture (aucune révision, rien de
        # déplacé — c'est la contrainte « on ne force pas »).
        host = op.get("host") or "background"
        if host not in ("background", "cc"):
            raise OpError("autoplace : hôte non géré %r (background|cc)" % host)
        strategy = op.get("strategy") or "auto"
        if strategy not in autoplace.STRATEGIES:
            raise OpError("autoplace : stratégie inconnue %r (%s)"
                          % (strategy, ", ".join(autoplace.STRATEGIES)))
        screen = _screen(op)
        wallpaper_path, lumgrid = _wallpaper_context()
        computed = autoplace.place(
            doc["instances"], host=host, strategy=strategy,
            margin=op.get("margin", 24), gap=op.get("gap", 12),
            corner=op.get("corner") or "tr", ids=op.get("ids"),
            screen=screen, wallpaper=wallpaper_path, lumgrid=lumgrid)
        if not computed.get("ok"):
            return computed
        placed = []
        for item in computed["placed"]:
            _, inst = _find(doc, item["id"])
            if host == "background":
                geo = dict((k, item[k]) for k in ("x", "y", "w", "h"))
            else:
                geo = dict((k, item[k]) for k in ("col", "row", "w", "h"))
            # Même validateur que `move` : les bornes de l'hôte s'appliquent.
            inst["geo"] = _geo(host, geo, ref=inst.get("geo"), screen=screen)
            entry = {"id": item["id"]}
            entry.update(inst["geo"])
            placed.append(entry)
        extra = {"placed": placed, "unplaced": [], "strategy": strategy,
                 "note": computed.get("note", "")}

    doc["version"] = 1
    doc["revision"] = int(doc.get("revision") or 0) + 1
    _write(doc)

    # Relecture obligatoire : c'est le fichier relu qui fait foi.
    fresh = _read()
    if fresh.get("revision") != doc["revision"]:
        raise OpError("relecture incohérente (révision %r au lieu de %r)"
                      % (fresh.get("revision"), doc["revision"]))
    written = None
    if instance and instance.get("id"):
        for inst in fresh["instances"]:
            if inst.get("id") == instance["id"]:
                written = inst
                break
    reply = {"ok": True, "revision": fresh["revision"]}
    if instance is not None:
        reply["instance"] = written or instance
    if extra:
        reply.update(extra)
    return reply


# ── CLI ────────────────────────────────────────────────────────────────────
def _emit(obj):
    json.dump(obj, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    sys.stdout.flush()


def main(argv):
    if len(argv) < 2:
        _emit({"ok": False, "error": "usage : widgets_json.py get|apply <json|->"})
        return 0
    action = argv[1]
    try:
        if action == "get":
            doc = get()
            _emit({"ok": True, "revision": doc.get("revision", 0), "data": doc})
            return 0
        if action == "apply":
            if len(argv) < 3:
                _emit({"ok": False, "error": "opération JSON manquante"})
                return 0
            raw = sys.stdin.read() if argv[2] == "-" else argv[2]
            try:
                op = json.loads(raw)
            except json.JSONDecodeError as exc:
                _emit({"ok": False, "error": "JSON invalide : %s" % exc})
                return 0
            _emit(apply(op))
            return 0
        _emit({"ok": False, "error": "action inconnue : %r" % action})
        return 0
    except OpError as exc:
        _emit({"ok": False, "error": str(exc)})
        return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception as exc:            # plantage inattendu : visible, pas silencieux
        sys.stderr.write("widgets_json.py: %s\n" % exc)
        _emit({"ok": False, "error": "plantage inattendu : %s" % exc})
        sys.exit(2)
