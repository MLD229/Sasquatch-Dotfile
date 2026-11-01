#!/usr/bin/env bash
# autoplace.sh — vérifications du placement intelligent (brief autoplace §5).
#
# Pour CHAQUE stratégie (theme, auto, grid, stack, center, spread), sur un état
# de test de 3 puis 5 instances de tailles différentes, et sur les DEUX hôtes
# (background en pixels, cc en cellules) :
#   1. aucune paire ne se chevauche (espacement `gap` inclus) ;
#   2. tous les rectangles restent à `margin` des bords ;
#   3. x, y ∈ 0..1 (fond) / col, row dans la grille (cc) ;
#   4. déterminisme : deux appels identiques → géométries identiques ;
#   5. cas « plus de place » (marges énormes, ou répartition impossible) :
#      ok:false + unplaced non vide + raison, et RIEN n'est déplacé.
# Plus, au §1b : 9 instances de fond sur 1920x1080 → placed=9 exigé pour les 6
# stratégies (stack/center échouaient avant l'ouverture des colonnes), et au §2
# la raison « plus de colonne disponible » quand l'écran est saturé.
#
# Le widgets.json réel est SAUVEGARDÉ puis RESTAURÉ (trap EXIT) : ce script ne
# laisse aucun widget de test derrière lui.
#
# Usage : bash cc/widgets/tests/autoplace.sh
#         SASQUATCH_CC_PORT=8799 bash cc/widgets/tests/autoplace.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC="$(cd "$HERE/../.." && pwd)"
WIDGETS="$CC/widgets.json"
PORT="${SASQUATCH_CC_PORT:-8765}"
API="http://127.0.0.1:$PORT"
SCREEN_W=1920
SCREEN_H=1080
MARGIN=24
GAP=12

pass=0
fail=0
ok() { printf '  OK   %s\n' "$1"; pass=$((pass + 1)); }
ko() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

post() { curl -s -m 30 -X POST -H 'Content-Type: application/json' -d "$1" "$API/api/widgets"; }
revision() {
    curl -s -m 5 "$API/api/widgets" \
        | python3 -c 'import json,sys;print(json.load(sys.stdin).get("revision"))'
}
# Empreinte des géométries : "id geo id geo …" triée par id (déterminisme).
geos() {
    curl -s -m 5 "$API/api/widgets" | python3 -c '
import json, sys
d = json.load(sys.stdin)["data"]
rows = sorted([[i["id"], i["geo"]] for i in d["instances"]], key=lambda r: r[0])
print(json.dumps(rows, sort_keys=True, ensure_ascii=False))
'
}
ids_json() {   # ids_json <host> → liste JSON des ids de cet hôte
    curl -s -m 5 "$API/api/widgets" | python3 -c '
import json, sys
host = sys.argv[1]
d = json.load(sys.stdin)["data"]
print(json.dumps([i["id"] for i in d["instances"] if i["host"] == host]))
' "$1"
}

# ── 0. Porte d'entrée ──────────────────────────────────────────────────────
echo "== 0. backend :$PORT =="
if ! curl -s -o /dev/null -m 3 "$API/api/widgets"; then
    ko "backend injoignable — systemctl --user start sasquatch-cc"
    echo
    echo "== bilan : $pass OK / $fail FAIL =="
    exit 1
fi
ok "GET /api/widgets répond (révision $(revision))"

# Le service lit le fichier à chaque requête : restaurer le fichier suffit.
BACKUP="$(mktemp)"
TMPDOC="$(mktemp)"
cp "$WIDGETS" "$BACKUP"
restore() {
    cp "$BACKUP" "$WIDGETS"
    rm -f "$BACKUP" "$TMPDOC"
}
trap restore EXIT

# ── Outils d'état de test ──────────────────────────────────────────────────
reset_state() {
    local ids
    ids="$(curl -s -m 5 "$API/api/widgets" | python3 -c '
import json, sys
d = json.load(sys.stdin)["data"]
print(" ".join(i["id"] for i in d["instances"] if i["host"] in ("background", "cc")))
')"
    for one in $ids; do
        post "{\"op\":\"rm\",\"id\":\"$one\"}" >/dev/null
    done
}

# fill_state <host> <3|5|9> : ajoute des instances de tailles différentes.
fill_state() {
    local host="$1" count="$2" spec i
    local types3=("clock:normal" "media:compact" "weather:normal")
    local types5=("clock:normal" "media:compact" "weather:normal"
                  "tasks:normal" "resources:compact")
    # 9 instances : le cas mesuré (stack/center échouaient à 6 posés / 3 non
    # placés). Tailles franchement mélangées, comme un vrai bureau chargé.
    local types9=("clock:normal" "media:compact" "calendar:hero"
                  "resources:normal" "weather:compact" "tasks:normal"
                  "volume:compact" "battery:normal" "notes:normal")
    if [ "$host" = "background" ]; then
        # Un hero (560x260) en plus : tailles franchement différentes en px.
        types3=("clock:normal" "media:compact" "calendar:hero")
        types5=("clock:normal" "media:compact" "calendar:hero"
                "resources:normal" "weather:compact")
        types9=("clock:normal" "media:compact" "calendar:hero"
                "resources:normal" "weather:compact" "tasks:normal"
                "volume:compact" "battery:normal" "notes:normal")
    fi
    local -a chosen
    case "$count" in
        3) chosen=("${types3[@]}") ;;
        5) chosen=("${types5[@]}") ;;
        *) chosen=("${types9[@]}") ;;
    esac
    for spec in "${chosen[@]}"; do
        local type="${spec%%:*}" variant="${spec##*:}"
        local r
        r="$(post "{\"op\":\"add\",\"type\":\"$type\",\"host\":\"$host\",\"variant\":\"$variant\"}")"
        if ! printf '%s' "$r" | grep -q '"ok": *true'; then
            ko "add $type/$variant sur $host → $r"
            return 1
        fi
    done
    return 0
}

# verify <host> <want> <label> : contraintes lues dans widgets.json (relu par
# le serveur). Affiche "OK sep=X" ou "FAIL …".
verify() {
    local host="$1" want="$2"
    curl -s -m 10 "$API/api/widgets" > "$TMPDOC"
    python3 - "$TMPDOC" "$host" "$MARGIN" "$GAP" "$want" "$SCREEN_W" "$SCREEN_H" <<'PY'
import json, math, sys

path, host = sys.argv[1], sys.argv[2]
margin, gap = float(sys.argv[3]), float(sys.argv[4])
want = int(sys.argv[5])
scr_w, scr_h = float(sys.argv[6]), float(sys.argv[7])

doc = json.load(open(path))["data"]
insts = [i for i in doc["instances"] if i["host"] == host]
errs = []
if len(insts) != want:
    errs.append("%d instances au lieu de %d" % (len(insts), want))

col_w, row_px = scr_w / 12.0, 96.0
if host == "background":
    rects = [(float(i["geo"]["x"]) * scr_w, float(i["geo"]["y"]) * scr_h,
              float(i["geo"]["w"]), float(i["geo"]["h"])) for i in insts]
    W, H = scr_w, scr_h
    mx = my = margin
    gx = gy = gap
else:
    # Cellules → pixels, avec EXACTEMENT la règle de cc/autoplace.py.
    rects = [(float(i["geo"]["col"]) * col_w, float(i["geo"]["row"]) * row_px,
              float(i["geo"]["w"]) * col_w, float(i["geo"]["h"]) * row_px)
             for i in insts]
    W = 12.0 * col_w
    H = float(max(4, int(scr_h // row_px))) * row_px
    mx = math.ceil(margin / col_w) * col_w
    my = math.ceil(margin / row_px) * row_px
    gx = int(round(gap / col_w)) * col_w
    gy = int(round(gap / row_px)) * row_px

for i, (x, y, w, h) in enumerate(rects):
    if w <= 0 or h <= 0:
        errs.append("%d : taille nulle" % i)
    if x < mx - 0.5 or y < my - 0.5:
        errs.append("%d : marge %.1f/%.1f px < %.1f" % (i, x, y, max(mx, my)))
    if x + w > W - mx + 0.5 or y + h > H - my + 0.5:
        errs.append("%d : dépasse la marge droite/bas" % i)
    if x < -1e-9 or y < -1e-9 or x > W + 1e-9 or y > H + 1e-9:
        errs.append("%d : hors de l'écran" % i)

least = None
for i in range(len(rects)):
    a = rects[i]
    for j in range(i + 1, len(rects)):
        b = rects[j]
        if (a[0] < b[0] + b[2] and b[0] < a[0] + a[2]
                and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]):
            errs.append("chevauchement %d/%d" % (i, j))
        sep = max(b[0] - (a[0] + a[2]), a[0] - (b[0] + b[2]),
                  b[1] - (a[1] + a[3]), a[1] - (b[1] + b[3]))
        least = sep if least is None else min(least, sep)
        # Le fichier écrit x/y en fractions à 4 décimales : 1e-4 * 1920 = 0,2 px
        # d'imprécision possible, d'où la tolérance de 0,5 px sur l'espacement.
        if sep < max(gx, gy) - 0.5:
            errs.append("espacement %d/%d = %.1f px < %.1f" % (i, j, sep, max(gx, gy)))

if errs:
    print("FAIL " + " | ".join(errs[:4]))
else:
    print("OK sep=%.1f" % (least if least is not None else 0.0))
PY
}

# ── 1. Une passe par stratégie × hôte × nombre ─────────────────────────────
echo
echo "== 1. placement (3 puis 5 instances, 2 hôtes, 6 stratégies) =="

run_case() {
    local host="$1" count="$2" strat="$3"
    local label="$strat/$host/$count"
    if ! reset_state_then_fill "$host" "$count"; then
        ko "$label : état de test non construit"
        return
    fi
    local rev0 ids payload resp placed unplaced reason
    rev0="$(revision)"
    ids="$(ids_json "$host")"
    payload="{\"op\":\"autoplace\",\"host\":\"$host\",\"strategy\":\"$strat\",\"margin\":$MARGIN,\"gap\":$GAP,\"corner\":\"tr\",\"ids\":$ids,\"screen\":{\"w\":$SCREEN_W,\"h\":$SCREEN_H}}"
    resp="$(post "$payload")"

    placed="$(printf '%s' "$resp" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(len(d.get("placed") or []))' 2>/dev/null)"
    unplaced="$(printf '%s' "$resp" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(len(d.get("unplaced") or []))' 2>/dev/null)"
    reason="$(printf '%s' "$resp" | python3 -c 'import json,sys;d=json.load(sys.stdin);print((d.get("reason") or d.get("error") or "")[:70])' 2>/dev/null)"
    if [ "${placed:-x}" != "$count" ] || [ "${unplaced:-x}" != "0" ]; then
        ko "$label : ${placed:-?} placés / ${unplaced:-?} non placés (attendu $count/0) — $reason"
        return
    fi
    if [ "$(revision)" != "$((rev0 + 1))" ]; then
        ko "$label : révision $(revision) au lieu de $((rev0 + 1))"
        return
    fi
    ok "$label : $placed placés"

    # Contraintes relues dans le fichier.
    local check
    check="$(verify "$host" "$count")"
    case "$check" in
        OK*) ok "$label : $check" ;;
        *)   ko "$label : $check" ;;
    esac

    # Déterminisme : même appel, mêmes géométries.
    local before after
    before="$(geos)"
    post "$payload" >/dev/null
    after="$(geos)"
    if [ "$before" = "$after" ]; then
        ok "$label : déterminisme (2 appels → mêmes géométries)"
    else
        ko "$label : géométries différentes au 2e appel"
    fi
}

reset_state_then_fill() {
    reset_state
    fill_state "$1" "$2"
}

for count in 3 5; do
    for strat in theme auto grid stack center spread; do
        for host in background cc; do
            if [ "$host" = "cc" ] && [ "$strat" = "spread" ] && [ "$count" = "5" ]; then
                continue          # traité au §2 (pas de place par construction)
            fi
            run_case "$host" "$count" "$strat"
        done
    done
done

# ── 1b. 9 instances de fond : le cas qui échouait (stack/center) ───────────
# 1920x1080, marges 24, espacement 12 : 9 widgets tiennent en 3 colonnes. Le
# coin tr saturé ne doit donc PAS faire échouer `stack` (colonne suivante vers
# l'intérieur) ni `center` (colonnes symétriques).
echo
echo "== 1b. 9 instances de fond (1920x1080) : placed=9 exigé, 6 stratégies =="
for strat in theme auto grid spread stack center; do
    run_case background 9 "$strat"
done

# ── 2. On ne force pas : marges énormes, puis répartition impossible ───────
echo
echo "== 2. pas de place → ok:false, unplaced, RIEN n'est déplacé =="

no_place_case() {
    local host="$1" count="$2" strat="$3" margin="$4" label="$5"
    local sw="$SCREEN_W" sh="$SCREEN_H"
    if [ -n "${6:-}" ]; then sw="${6%x*}"; sh="${6#*x}"; fi
    reset_state_then_fill "$host" "$count" || { ko "$label : état non construit"; return; }
    local ids payload rev0 geos0 resp ok_flag unplaced reason rev1 geos1
    # Les ids viennent de l'état de test RÉEL (recalculé après remplissage).
    ids="$(ids_json "$host")"
    payload="{\"op\":\"autoplace\",\"host\":\"$host\",\"strategy\":\"$strat\",\"margin\":$margin,\"gap\":$GAP,\"corner\":\"tr\",\"ids\":$ids,\"screen\":{\"w\":$sw,\"h\":$sh}}"
    rev0="$(revision)"
    geos0="$(geos)"
    resp="$(post "$payload")"
    ok_flag="$(printf '%s' "$resp" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("ok"))' 2>/dev/null)"
    unplaced="$(printf '%s' "$resp" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(len(d.get("unplaced") or []))' 2>/dev/null)"
    reason="$(printf '%s' "$resp" | python3 -c 'import json,sys;d=json.load(sys.stdin);print((d.get("reason") or "")[:90])' 2>/dev/null)"
    rev1="$(revision)"
    geos1="$(geos)"
    if [ "$ok_flag" != "False" ]; then
        ko "$label : ok=$ok_flag au lieu de false"
        return
    fi
    if [ "${unplaced:-0}" -lt 1 ]; then
        ko "$label : unplaced vide"
        return
    fi
    if [ -z "$reason" ]; then
        ko "$label : aucune raison lisible"
        return
    fi
    # Motif attendu dans la raison (colonnes épuisées, etc.).
    if [ -n "${7:-}" ] && ! printf '%s' "$reason" | grep -qF "$7"; then
        ko "$label : raison sans « $7 » · $reason"
        return
    fi
    if [ "$rev0" != "$rev1" ] || [ "$geos0" != "$geos1" ]; then
        ko "$label : état modifié (révision $rev0 → $rev1)"
        return
    fi
    ok "$label : ok:false, $unplaced non placé(s), rien de déplacé · $reason"
}

no_place_case background 3 theme 900 \
    "marges 900 px (theme/background)"
no_place_case cc 5 spread "$MARGIN" \
    "spread/cc à 5 (cols=3 × 4 cellules > 10 disponibles)"
# Colonnes épuisées : 9 widgets de fond sur un écran trop petit. La raison doit
# dire POURQUOI (« plus de colonne disponible »), pas seulement « pas de place ».
no_place_case background 9 stack "$MARGIN" \
    "stack, 9 widgets sur 900x600 (colonnes épuisées)" 900x600 \
    "plus de colonne disponible"
no_place_case background 9 center "$MARGIN" \
    "center, 9 widgets sur 900x600 (colonnes épuisées)" 900x600 \
    "plus de colonne disponible"

# ── 3. Refus explicites (aucune écriture) ──────────────────────────────────
echo
echo "== 3. entrées invalides → erreur claire, aucune écriture =="
rev0="$(revision)"
# Les accents arrivent en \\uXXXX : on décode le JSON avant de chercher.
refus() {   # refus <payload> <motif attendu> <libellé>
    local out
    out="$(post "$1" | python3 -c '
import json, sys
d = json.load(sys.stdin)
err = (d.get("error") or "") + " " + (d.get("reason") or "")
print("OK" if d.get("ok") is False and sys.argv[1] in err else "NON " + err)
' "$2")"
    case "$out" in
        OK) ok "$3 refusé (message clair)" ;;
        *)  ko "$3 : $out" ;;
    esac
}

refus '{"op":"autoplace","host":"background","strategy":"magique"}' \
      "stratégie inconnue" "stratégie inconnue"
refus '{"op":"autoplace","host":"bar"}' "hôte non géré" "hôte non géré"
if [ "$(revision)" = "$rev0" ]; then ok "aucune révision consommée par les refus"; else ko "révision modifiée par un refus"; fi

echo
echo "== bilan : $pass OK / $fail FAIL =="
[ "$fail" -eq 0 ]
