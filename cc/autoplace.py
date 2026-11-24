#!/usr/bin/env python3
"""autoplace.py — placement intelligent des widgets (brief autoplace).

Module PUR : il ne lit ni n'écrit AUCUN fichier. L'écrivain unique reste
`widgets_json.py`, qui appelle `place()` puis écrit (une révision, atomique).

Repris TEL QUEL du wallclock (`waybar/scripts/wallclock-ja.py`,
`find_smart_position`) : grille d'analyse 48x27, pas de balayage 2, score

    luminance moyenne * 1.0  +  ecart_type moyen * 0.5
    + max(0, 3 - distance_au_bord) * 2.0

score MINIMAL retenu, widget CENTRÉ sur la fenêtre choisie (zone sombre et
plate, coins autorisés). L'« ecart_type » est celui du wallclock : `art.std
(axis=2)`, c'est-à-dire la dispersion des 3 canaux d'un pixel (un aplat a une
dispersion nulle), moyennée sur la fenêtre — pas la variance spatiale.

Deux espaces d'unités, selon l'hôte :
  * `background` : pixels écran ; sortie x, y en FRACTIONS 0..1, w, h en px ;
  * `cc`         : cellules de la grille 12 colonnes (une ligne = 96 px) ;
                   sortie col, row, w, h entiers.
Sur `cc`, marges et espacement sont convertis en cellules (largeur de colonne
= écran/12, hauteur de ligne = 96 px) : un espacement inférieur à une
demi-cellule vaut zéro cellule. Les positions sont arrondies vers l'INTÉRIEUR
(floor) puis revalidées : un arrondi ne peut donc jamais réduire une marge, et
un candidat qui échoue à l'arrondi est simplement écarté.

Contraintes (brief §2), aucune exception :
  1. collision : AABB élargie de gap/2 de chaque côté (donc `gap` px entre
     deux rectangles) ; les instances hors `ids` sont des OBSTACLES ;
  2. marge `margin` par rapport aux bords de l'écran passé en paramètre ;
  3. x, y ∈ 0..1 (fond), col/row dans la grille (cc) ;
  4. pas de place ⇒ on ne force pas : tout ou rien (`ok: false`, `unplaced`,
     `reason`) et rien n'est déplacé ;
  5. déterminisme : aucun random, aucun état global, ordre du fichier.

`stack` et `center` travaillent en COLONNES : quand la colonne du coin (ou la
colonne centrée) est pleine, la colonne SUIVANTE s'ouvre vers l'intérieur
(`stack`) ou en symétrie autour du centre (`center`, 0 puis gauche puis droite),
avec le même `gap` et la même `margin`. L'échec n'arrive qu'une fois l'écran
entier épuisé (`unplaced` + « plus de colonne disponible »), et rien n'est
déplacé.

API :
  place(instances, host=..., strategy=..., margin=..., gap=..., corner=...,
        ids=..., screen=(w, h), wallpaper=..., lumgrid=...) -> dict
"""

import math

STRATEGIES = ("theme", "auto", "grid", "spread", "stack", "center", "fit")
HOSTS = ("background", "cc")
CORNERS = ("tr", "tl", "br", "bl")

CC_COLUMNS = 12
CC_ROW_PX = 96.0          # hauteur de ligne du board (brief widgets v1 §4)
CELL_PX = 8.0             # pas de la stratégie `grid` côté fond
FIT_MIN_W = 180.0         # stratégie `fit` : plus petite case encore lisible
FIT_MIN_H = 90.0
GRID_LUM_W, GRID_LUM_H = 48, 27   # grille d'analyse du wallclock
SCAN_STEP = 2             # pas de balayage des fenêtres (wallclock)
EDGE_FREE = 3             # cellules « loin du bord » avant pénalité
EDGE_WEIGHT = 2.0
EPS = 1e-6
MAX_SLOTS = 20000        # garde-fou : `stack`/`center` balaient TOUT l'écran
#                          (colonnes × lignes), pas seulement le coin


# ── Géométrie ───────────────────────────────────────────────────────────────
def _overlap(a, b, gx, gy):
    """AABB élargie de gx/2, gy/2 de chaque côté → `gx`, `gy` de séparation."""
    return (a[0] < b[0] + b[2] + gx and b[0] < a[0] + a[2] + gx
            and a[1] < b[1] + b[3] + gy and b[1] < a[1] + a[3] + gy)


def _fits(rect, width, height, mx, my):
    x, y, w, h = rect
    return (x >= mx - EPS and y >= my - EPS
            and x + w <= width - mx + EPS and y + h <= height - my + EPS
            and w <= width and h <= height)


def _free(rect, obstacles, gx, gy):
    for other in obstacles:
        if _overlap(rect, other, gx, gy):
            return False
    return True


def _snap(rect, cells):
    """Arrondi vers l'intérieur (jamais un candidat poussé vers l'extérieur)."""
    x, y, w, h = rect
    if cells:
        return (float(math.floor(x + 1e-4)), float(math.floor(y + 1e-4)),
                float(int(round(w))), float(int(round(h))))
    return (float(x), float(y), float(w), float(h))


# ── Grille de score (luminance + dispersion) ────────────────────────────────
class ScoreMap:
    """Grille gw x gh : `lum` (0..1) et `std` (dispersion des canaux, 0..1)."""

    def __init__(self, gw, gh, lum, std):
        self.gw = int(gw)
        self.gh = int(gh)
        self.lum = [float(v) for v in lum]
        self.std = [float(v) for v in std]

    def window(self, i, j, cw, ch):
        """Score d'une fenêtre EN CELLULES : somme des deux moyennes + bord."""
        total_l = total_s = 0.0
        count = 0
        for row in range(j, j + ch):
            base = row * self.gw + i
            lrow = self.lum[base:base + cw]
            srow = self.std[base:base + cw]
            total_l += sum(lrow)
            total_s += sum(srow)
            count += len(lrow)
        if count == 0:
            return float("inf")
        edge = min(i, self.gw - i - cw, j, self.gh - j - ch)
        return ((total_l / count) * 1.0 + (total_s / count) * 0.5
                + max(0, EDGE_FREE - edge) * EDGE_WEIGHT)


def _pil_grid(path, gw, gh):
    """(lum, std) par cellule de l'image, ou None si PIL/`path` indisponible."""
    if not path:
        return None
    try:
        from PIL import Image
    except ImportError:
        return None
    try:
        img = Image.open(path).convert("RGB").resize((gw, gh))
        raw = img.tobytes()
    except Exception:
        return None
    lum = []
    std = []
    for k in range(0, len(raw), 3):
        r, g, b = raw[k], raw[k + 1], raw[k + 2]
        lum.append((0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0)
        mean = (r + g + b) / 3.0
        var = ((r - mean) ** 2 + (g - mean) ** 2 + (b - mean) ** 2) / 3.0
        std.append(math.sqrt(var) / 255.0)
    return lum, std


def score_map(wallpaper=None, lumgrid=None):
    """ScoreMap depuis la grille servie (lumgrid) ou depuis l'image (PIL).

    `lumgrid` = {"w","h","values"} de /api/wallpaper/lumgrid : sa luminance est
    réutilisée TELLE QUELLE (l'image n'est pas rouverte pour elle). La
    dispersion n'y figure pas : elle vient de l'image quand PIL est présent,
    sinon elle vaut 0 (zone considérée plate). None = aucune donnée.
    """
    gw = gh = 0
    lum = None
    if isinstance(lumgrid, dict):
        try:
            gw = int(lumgrid.get("w") or 0)
            gh = int(lumgrid.get("h") or 0)
            values = lumgrid.get("values") or []
            if gw > 0 and gh > 0 and len(values) == gw * gh:
                lum = [float(v) for v in values]
            else:
                gw = gh = 0
        except (TypeError, ValueError):
            gw = gh = 0
    if gw == 0 or lum is None:
        grid = _pil_grid(wallpaper, GRID_LUM_W, GRID_LUM_H)
        if grid is None:
            return None
        return ScoreMap(GRID_LUM_W, GRID_LUM_H, grid[0], grid[1])
    grid = _pil_grid(wallpaper, gw, gh)
    std = grid[1] if grid else [0.0] * (gw * gh)
    return ScoreMap(gw, gh, lum, std)


# ── Candidats, par stratégie (ordre de préférence = ordre d'essai) ──────────
def _theme_order(w, h, width, height, smap):
    """Fenêtres de la grille de score, du MEILLEUR score au moins bon."""
    if smap is None:
        return []
    cw = max(1, min(smap.gw, int(round(w / width * smap.gw))))
    ch = max(1, min(smap.gh, int(round(h / height * smap.gh))))
    ranked = []
    for j in range(0, smap.gh - ch + 1, SCAN_STEP):
        for i in range(0, smap.gw - cw + 1, SCAN_STEP):
            score = smap.window(i, j, cw, ch)
            # Centre de la fenêtre ramené dans l'espace de l'hôte.
            cx = (i + cw / 2.0) / smap.gw * width
            cy = (j + ch / 2.0) / smap.gh * height
            ranked.append((score, i, j, (cx - w / 2.0, cy - h / 2.0, w, h)))
    ranked.sort(key=lambda item: (item[0], item[1], item[2]))
    return [item[3] for item in ranked]


def _grid_order(w, h, width, height, mx, my, step):
    """Balayage haut → bas / gauche → droite, positions multiples de `step`."""
    x0 = math.ceil((mx - EPS) / step) * step
    y0 = math.ceil((my - EPS) / step) * step
    nx = int(math.floor((width - mx - w - x0) / step + EPS)) + 1
    ny = int(math.floor((height - my - h - y0) / step + EPS)) + 1
    out = []
    for j in range(max(0, ny)):
        for i in range(max(0, nx)):
            out.append((x0 + i * step, y0 + j * step, w, h))
    return out


def _stack_order(w, h, width, height, mx, my, gap, corner):
    """COLONNES depuis `corner` : la 0 collée au coin, les suivantes vers l'intérieur.

    Le pas des colonnes vaut `w + gap` : chaque widget est aligné sur le bord du
    coin dans sa colonne (colonnes collées au coin, largeur = celle du widget,
    donc jamais de place perdue quand les largeurs diffèrent — sur le `cc` un
    widget de 4 cellules ouvre bien 2 colonnes dans un board de 12). Une colonne
    n'est ouverte que si la précédente est pleine (`tr` → puis la colonne à
    GAUCHE, etc.) : on n'échoue donc qu'après avoir épuisé tout l'écran, plus
    jamais « empilement saturé dans le coin ».

    Le pas vertical de balayage vaut `gap` (et non la hauteur du widget) : le
    premier emplacement libre est donc collé au bloc déjà posé, sans trou
    parasite quand les widgets ont des hauteurs différentes.
    """
    step = max(1.0, float(gap))
    pitch = max(1.0, float(w) + float(gap))
    out = []
    k = 0
    while len(out) < MAX_SLOTS:
        if corner in ("tr", "br"):
            x = width - mx - k * pitch - w
        else:
            x = mx + k * pitch
        if x < mx - EPS or x + w > width - mx + EPS:
            break                      # plus aucune colonne vers l'intérieur
        if corner in ("tr", "tl"):
            y = my
            while y + h <= height - my + EPS and len(out) < MAX_SLOTS:
                out.append((x, y, w, h))
                y += step
        else:
            y = height - my - h
            while y >= my - EPS and len(out) < MAX_SLOTS:
                out.append((x, y, w, h))
                y -= step
        k += 1
    return out


def _center_order(w, h, width, height, mx, my, gap, start_y):
    """COLONNES SYMÉTRIQUES autour du centre : 0, puis gauche, puis droite, etc.

    Même logique que `_stack_order` (une colonne n'est ouverte que si les
    précédentes sont pleines) mais symétrique : la colonne 0 est centrée, puis
    on ouvre la colonne immédiatement à GAUCHE, puis celle à DROITE, et ainsi
    de suite jusqu'aux marges ; le pas est `w + gap` de chaque côté.

    Chaque colonne est balayée vers le BAS depuis `start_y` (le haut du bloc
    centré, calculé par `place()`), puis vers le haut : le bloc reste centré
    tant qu'il tient, et ne s'étale qu'en cas de besoin.
    """
    step = max(1.0, float(gap))
    pitch = max(1.0, float(w) + float(gap))
    cx = (width - w) / 2.0
    offsets = [0.0]
    span = max(0.0, width - 2 * mx)
    for d in range(1, int(math.ceil(span / (2.0 * pitch))) + 2):
        offsets.append(-d * pitch)
        offsets.append(d * pitch)
    out = []
    for off in offsets:
        x = cx + off
        if x < mx - EPS or x + w > width - mx + EPS:
            continue
        y = max(my, start_y)
        while y + h <= height - my + EPS and len(out) < MAX_SLOTS:
            out.append((x, y, w, h))
            y += step
        y = min(height - my - h, start_y - step)
        while y >= my - EPS and len(out) < MAX_SLOTS:
            out.append((x, y, w, h))
            y -= step
    return out


def _spread_order(w, h, index, width, height, mx, my, gap, cols, rows):
    """Répartition régulière : une case par widget, widget centré dans sa case.

    Une seule position possible par widget : soit la case convient, soit le
    widget est « non placé » avec une raison (aucune déformation, aucun
    déplacement de la case — la régularité est le contrat de `spread`).
    """
    cw = (width - 2 * mx - (cols - 1) * gap) / float(cols)
    ch = (height - 2 * my - (rows - 1) * gap) / float(rows)
    if w > cw + EPS or h > ch + EPS:
        return []
    col = index % cols
    row = index // cols
    x = mx + col * (cw + gap) + (cw - w) / 2.0
    y = my + row * (ch + gap) + (ch - h) / 2.0
    return [(x, y, w, h)]


# ── Cœur ────────────────────────────────────────────────────────────────────
def _fail(strategy, reasons, message, note=""):
    """Réponse d'échec : `placed` vide (rien n'est appliqué), raisons lisibles."""
    unplaced = [k for k in reasons]
    detail = ""
    if unplaced:
        detail = " — " + ", ".join("%s (%s)" % (k, reasons[k]) for k in unplaced)
    return {"ok": False, "strategy": strategy, "placed": [],
            "unplaced": unplaced, "reason": message + detail, "note": note}


def _rect_of(inst, host, scr_w, scr_h):
    geo = inst.get("geo") or {}
    try:
        if host == "background":
            return (float(geo.get("x", 0.0)) * scr_w, float(geo.get("y", 0.0)) * scr_h,
                    float(geo.get("w", 360)), float(geo.get("h", 180)))
        return (float(geo.get("col", 0)), float(geo.get("row", 0)),
                float(geo.get("w", 4)), float(geo.get("h", 2)))
    except (TypeError, ValueError):
        return None


def _size_of(inst, host):
    geo = inst.get("geo") or {}
    try:
        if host == "background":
            w = float(geo.get("w", 360))
            h = float(geo.get("h", 180))
        else:
            w = float(geo.get("w", 4))
            h = float(geo.get("h", 2))
    except (TypeError, ValueError):
        return None
    if w <= 0 or h <= 0:
        return None
    return w, h


def _fit_place(targets, width, height, mx, my, gx, gy):
    """Stratégie `fit` (« Remplir ») : la TAILLE suit l'écran.

    La surface utile (écran − marges) est découpée en n cases égales ; le
    nombre de colonnes retenu est celui dont le format de case est le plus
    proche du format naturel moyen des widgets (donc on ne les étire pas dans
    un sens absurde). Retourne (cases, cols, rows, cw, ch) ou None si aucune
    découpe ne laisse une case lisible.
    """
    n = len(targets)
    if n <= 0:
        return None
    avail_w = width - 2 * mx
    avail_h = height - 2 * my
    nat = [(_size_of(i, "background") or (360.0, 180.0)) for i in targets]
    nat_ratio = sum(w / h for w, h in nat) / float(n)
    best = None
    for c in range(1, n + 1):
        r = int(math.ceil(n / float(c)))
        cw = (avail_w - gx * (c - 1)) / float(c)
        ch = (avail_h - gy * (r - 1)) / float(r)
        if cw < FIT_MIN_W - EPS or ch < FIT_MIN_H - EPS:
            continue
        score = abs(math.log((cw / ch) / nat_ratio))
        if best is None or score < best[0] - 1e-9:
            best = (score, c, r, cw, ch)
    if best is None:
        return None
    _, cols, rows, cw, ch = best
    cases = []
    for index, inst in enumerate(targets):
        col = index % cols
        row = index // cols
        cases.append((inst.get("id"),
                      (mx + col * (cw + gx), my + row * (ch + gy), cw, ch)))
    return cases, cols, rows, cw, ch


def place(instances, host="background", strategy="auto", margin=24, gap=12,
          corner="tr", ids=None, screen=(1920, 1080),
          wallpaper=None, lumgrid=None):
    """Calcule les NOUVELLES géométries. Ne touche à rien d'autre.

    Retourne {"ok", "strategy", "placed", "unplaced", "reason", "note"}.
    `placed` reste vide dès qu'un widget n'a pas de place (tout ou rien).
    """
    if strategy not in STRATEGIES:
        return _fail(strategy, {}, "stratégie inconnue : %r" % (strategy,))
    if host not in HOSTS:
        return _fail(strategy, {}, "hôte non géré par autoplace : %r" % (host,))
    corner = corner if corner in CORNERS else "tr"
    try:
        margin = max(0.0, float(margin))
        gap = max(0.0, float(gap))
        scr_w = max(200.0, float(screen[0]))
        scr_h = max(200.0, float(screen[1]))
    except (TypeError, ValueError, IndexError):
        return _fail(strategy, {}, "paramètres numériques invalides (margin/gap/screen)")

    host_insts = [i for i in instances
                  if isinstance(i, dict) and i.get("host") == host]
    known = set(i.get("id") for i in host_insts)
    reasons = {}
    if ids is None:
        targets = list(host_insts)
    else:
        if not isinstance(ids, (list, tuple)):
            return _fail(strategy, {}, "`ids` doit être une liste")
        wanted = [str(v) for v in ids]
        targets = [i for i in host_insts if i.get("id") in set(wanted)]
        for missing in wanted:
            if missing not in known:
                reasons[missing] = "instance absente de l'hôte %s" % host
    if not targets and not reasons:
        return _fail(strategy, {}, "aucun widget à placer sur l'hôte %s" % host)

    # Espace de travail : pixels (fond) ou cellules (cc).
    cells = (host == "cc")
    if cells:
        col_px = scr_w / float(CC_COLUMNS)
        width = float(CC_COLUMNS)
        height = float(max(1, int(scr_h // CC_ROW_PX)))
        mx = float(math.ceil(margin / col_px))
        my = float(math.ceil(margin / CC_ROW_PX))
        gx = float(max(0, int(round(gap / col_px))))
        gy = float(max(0, int(round(gap / CC_ROW_PX))))
    else:
        width, height = scr_w, scr_h
        mx = my = margin
        gx = gy = gap

    # ── Stratégie `fit` (« Remplir ») ───────────────────────────────────────
    # Le seul mode qui MODIFIE la taille : la surface utile est découpée en n
    # cases égales et chaque widget prend sa case. Résultat : le fond est
    # occupé sans trou ni débordement quelle que soit la résolution, au lieu de
    # widgets de taille fixe posés au hasard. `cc` est un board en cellules qui
    # défile → pas de fit (refus explicite, jamais un géo bancale).
    if strategy == "fit":
        if cells:
            return _fail(strategy, {"": "hôte cc (board en cellules)"},
                         "Remplir : réservé au fond d'écran")
        fitted = _fit_place(targets, width, height, mx, my, gx, gy)
        if fitted is None:
            return _fail(strategy, {"": "cases < %dx%d px" % (FIT_MIN_W, FIT_MIN_H)},
                         "pas assez de place pour %d widget(s) avec ces marges"
                         % len(targets))
        cases, cols, rows, cw, ch = fitted
        entries = []
        for iid, (x, y, w, h) in cases:
            entries.append({
                "id": iid,
                "x": math.floor(x / width * 10000.0) / 10000.0,
                "y": math.floor(y / height * 10000.0) / 10000.0,
                "w": int(round(w)), "h": int(round(h)),
            })
        return {"ok": True, "strategy": strategy, "placed": entries,
                "unplaced": [], "reason": "",
                "note": "%d×%d cases de %d×%d px"
                        % (cols, rows, int(round(cw)), int(round(ch)))}

    target_ids = set(id(i) for i in targets)
    obstacles = []
    for inst in host_insts:
        if id(inst) in target_ids:
            continue
        rect = _rect_of(inst, host, scr_w, scr_h)
        if rect is not None:
            obstacles.append(rect)

    # `theme` sans grille de score (ni lumgrid ni PIL) : repli empilé en haut à
    # droite, comme le wallclock qui retombe au centre bas sans imagerie.
    note = ""
    effective = strategy
    smap = score_map(wallpaper, lumgrid) if strategy in ("theme", "auto") else None
    if strategy == "theme" and smap is None:
        effective = "stack"
        corner = "tr"
        note = "pas de luminance disponible (PIL/lumgrid) : repli Empilé en haut à droite"
    elif strategy == "auto" and smap is None:
        note = "pas de luminance disponible : ordre de balayage pur"

    placed = []
    occupied = list(obstacles)
    total_h = sum((_size_of(i, host) or (0.0, 0.0))[1] for i in targets)
    target_y = max(my, (height - (total_h + gy * max(0, len(targets) - 1))) / 2.0)
    cols = max(1, int(math.ceil(math.sqrt(len(targets)))))
    rows = int(math.ceil(len(targets) / float(cols)))
    if cells:
        unit = "cellules"
        marg_txt, gap_txt = int(round(mx)), int(round(gy))
    else:
        unit = "px"
        marg_txt, gap_txt = int(round(margin)), int(round(gap))

    for index, inst in enumerate(targets):
        iid = inst.get("id")
        size = _size_of(inst, host)
        if size is None:
            reasons[iid] = "géométrie illisible"
            continue
        w, h = size
        if w > width - 2 * mx + EPS:
            reasons[iid] = ("%d px de large pour %d px disponibles avec %d px de marge"
                            % (w, width - 2 * mx, margin))
            continue
        if h > height - 2 * my + EPS:
            reasons[iid] = ("%d px de haut pour %d px disponibles avec %d px de marge"
                            % (h, height - 2 * my, margin))
            continue

        if effective in ("theme", "auto"):
            candidates = _theme_order(w, h, width, height, smap)
            if effective == "auto":
                candidates = candidates + _grid_order(w, h, width, height, mx, my,
                                                      CELL_PX if not cells else 1.0)
            why = "plus de zone libre avec ces marges"
        elif effective == "grid":
            candidates = _grid_order(w, h, width, height, mx, my,
                                     CELL_PX if not cells else 1.0)
            why = "plus de cellule libre sur la grille"
        elif effective == "stack":
            candidates = _stack_order(w, h, width, height, mx, my, gy, corner)
            why = ("plus de colonne disponible — écran saturé depuis le coin %s "
                   "(marges %d %s, espacement %d %s)"
                   % (corner, marg_txt, unit, gap_txt, unit))
        elif effective == "center":
            candidates = _center_order(w, h, width, height, mx, my, gy,
                                       target_y)
            why = ("plus de colonne disponible — écran saturé autour du centre "
                   "(marges %d %s, espacement %d %s)"
                   % (marg_txt, unit, gap_txt, unit))
        else:
            candidates = _spread_order(w, h, index, width, height, mx, my, gy,
                                       cols, rows)
            why = ("case de la répartition trop petite (%d colonnes pour %d widgets)"
                   % (cols, len(targets)))

        done = False
        rect = None
        for cand in candidates:
            rect = _snap(cand, cells)
            if not _fits(rect, width, height, mx, my):
                continue
            if not _free(rect, occupied, gx, gy):
                continue
            occupied.append(rect)
            placed.append((iid, rect))
            done = True
            break
        if not done:
            reasons[iid] = why

    if reasons or not placed:
        out = _fail(strategy, reasons or {"": "aucune cible"}, "placement impossible", note)
        if reasons:
            out["reason"] = "pas de place — " + ", ".join(
                "%s (%s)" % (k, reasons[k]) for k in reasons)
        return out

    entries = []
    for iid, (x, y, w, h) in placed:
        if cells:
            entries.append({"id": iid, "col": int(x), "row": int(y),
                            "w": int(w), "h": int(h)})
        else:
            entries.append({"id": iid,
                            "x": math.floor(x / width * 10000.0) / 10000.0,
                            "y": math.floor(y / height * 10000.0) / 10000.0,
                            "w": int(round(w)), "h": int(round(h))})
    return {"ok": True, "strategy": strategy, "placed": entries,
            "unplaced": [], "reason": "", "note": note}
