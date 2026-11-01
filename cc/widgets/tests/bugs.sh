#!/usr/bin/env bash
# bugs.sh — parcours de non-régression du mécanisme d'ajout (brief bugs §5).
#
# Sur les DEUX hôtes (cc et background) : add → move → resize → variant → rm,
# chaque étape vérifiée par un GET /api/widgets (révision + valeur relue), pas
# par la mémoire du script. Rien n'est laissé derrière : les instances créées
# ici sont supprimées à la fin, même en cas d'échec (trap).
#
# Usage : bash cc/widgets/tests/bugs.sh            (backend sur 127.0.0.1:8765)
#         SASQUATCH_CC_PORT=8799 bash …            (autre port)
#         SASQUATCH_SCREEN_W=2560 SASQUATCH_SCREEN_H=1600 bash …  (écran annoncé)
set -uo pipefail

PORT="${SASQUATCH_CC_PORT:-8765}"
BASE="http://127.0.0.1:$PORT"
SCR_W="${SASQUATCH_SCREEN_W:-1920}"
SCR_H="${SASQUATCH_SCREEN_H:-1080}"
TMP="$(mktemp -d)"
CREATED=()
PASS=0
FAIL=0

cleanup() {
    local id
    for id in "${CREATED[@]:-}"; do
        [ -n "$id" ] || continue
        curl -s -m 5 -X POST "$BASE/api/widgets" \
            -H 'Content-Type: application/json' \
            -d "{\"op\":\"rm\",\"id\":\"$id\"}" >/dev/null 2>&1 || true
    done
    rm -rf "$TMP"
}
trap cleanup EXIT

ok()  { printf '  ok    %s\n' "$1"; PASS=$((PASS + 1)); }
ko()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
head_() { printf '\n%s\n' "$1"; }

post() { curl -s -m 5 -X POST "$BASE/api/widgets" -H 'Content-Type: application/json' -d "$1"; }
get()  { curl -s -m 5 "$BASE/api/widgets"; }
rev()  { get | python3 -c 'import json,sys; print(json.load(sys.stdin).get("revision",-1))'; }

# check <libellé> <code python>  (le JSON de la dernière réponse est dans $TMP/last.json)
check() {
    local label="$1"
    if python3 - "$TMP/last.json" <<PY
import json, sys
doc = json.load(open(sys.argv[1]))
$2
PY
    then ok "$label"; else ko "$label"; fi
}

# check_all <libellé> <code python>  (le DOCUMENT complet — GET — est dans all.json)
check_all() {
    local label="$1"
    if python3 - "$TMP/all.json" <<PY
import json, sys
doc = json.load(open(sys.argv[1]))
$2
PY
    then ok "$label"; else ko "$label"; fi
}

command -v curl >/dev/null || { echo "curl manquant"; exit 2; }
curl -sf -m 3 "$BASE/api/widgets" >/dev/null || {
    echo "backend injoignable sur $BASE — lance sasquatch-cc d'abord" >&2
    exit 1
}

printf 'widgets.json — hôte cc + background, écran annoncé %sx%s\n' "$SCR_W" "$SCR_H"

# ── 1. add sur `cc` : première cellule libre, jamais un chevauchement ───────
head_ "1 · add sur cc"
R0=$(rev)
post '{"op":"add","type":"clock","host":"cc"}' > "$TMP/last.json"
ID_CC=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["instance"]["id"])' "$TMP/last.json")
CREATED+=("$ID_CC")
check "id <type>-<n> ($ID_CC)" "
i = json.load(open(sys.argv[1]))['instance']
assert i['id'].startswith('clock-') and i['id'].split('-')[-1].isdigit(), i['id']
" 
check "révision +1" "
assert json.load(open(sys.argv[1]))['revision'] == $R0 + 1
"
# aucun chevauchement avec une autre instance `cc`
get > "$TMP/all.json"
check_all "aucun chevauchement sur la grille 12 colonnes" "
doc = json.load(open(sys.argv[1]))
me = [i for i in doc['data']['instances'] if i['id'] == '$ID_CC'][0]['geo']
def cells(g):
    return {(c, r) for c in range(g['col'], g['col'] + g['w'])
                   for r in range(g['row'], g['row'] + g['h'])}
mine = cells(me)
for inst in doc['data']['instances']:
    if inst['id'] == '$ID_CC' or inst['host'] != 'cc':
        continue
    assert not (mine & cells(inst['geo'])), ('chevauche ' + inst['id'])
"

# second exemplaire du même type : autre cellule, autre id
post '{"op":"add","type":"clock","host":"cc"}' > "$TMP/last.json"
ID_CC2=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["instance"]["id"])' "$TMP/last.json")
CREATED+=("$ID_CC2")
check "deuxième instance : id distinct ($ID_CC2)" "
assert '$ID_CC2' != '$ID_CC'
"
get > "$TMP/all.json"
check_all "deuxième instance : cellule distincte" "
doc = json.load(open(sys.argv[1]))
a = [i for i in doc['data']['instances'] if i['id'] == '$ID_CC'][0]['geo']
b = [i for i in doc['data']['instances'] if i['id'] == '$ID_CC2'][0]['geo']
assert (a['col'], a['row']) != (b['col'], b['row'])
"

# ── 2. add sur `background` : cascade + clamp x + w/écran <= 1 ─────────────
head_ "2 · add sur background"
post "{\"op\":\"add\",\"type\":\"weather\",\"host\":\"background\",\"screen\":{\"w\":$SCR_W,\"h\":$SCR_H}}" > "$TMP/last.json"
ID_BG=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["instance"]["id"])' "$TMP/last.json")
CREATED+=("$ID_BG")
check "x + w/écran <= 1 (box dans l'écran)" "
i = json.load(open(sys.argv[1]))['instance']
g = i['geo']
assert g['x'] >= 0 and g['y'] >= 0, g
assert g['x'] + g['w'] / $SCR_W <= 1.0001, g
assert g['y'] + g['h'] / $SCR_H <= 1.0001, g
"
post "{\"op\":\"add\",\"type\":\"weather\",\"host\":\"background\",\"screen\":{\"w\":$SCR_W,\"h\":$SCR_H}}" > "$TMP/last.json"
ID_BG2=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["instance"]["id"])' "$TMP/last.json")
CREATED+=("$ID_BG2")
get > "$TMP/all.json"
check_all "cascade d'au moins 0.02 et pas de superposition" "
doc = json.load(open(sys.argv[1]))
inst = [i for i in doc['data']['instances'] if i['host'] == 'background']
a = [i for i in inst if i['id'] == '$ID_BG'][0]['geo']
b = [i for i in inst if i['id'] == '$ID_BG2'][0]['geo']
assert abs(b['x'] - a['x']) >= 0.0199 or abs(b['y'] - a['y']) >= 0.0199, (a, b)
def box(g):
    return (g['x'] * $SCR_W, g['y'] * $SCR_H, g['w'], g['h'])
ax, ay, aw, ah = box(a)
bx, by, bw, bh = box(b)
assert not (bx < ax + aw and ax < bx + bw and by < ay + ah and ay < by + bh), (a, b)
"

# ── 3. move ────────────────────────────────────────────────────────────────
head_ "3 · move"
post "{\"op\":\"move\",\"id\":\"$ID_BG\",\"geo\":{\"x\":1.4,\"y\":1.4},\"screen\":{\"w\":$SCR_W,\"h\":$SCR_H}}" > "$TMP/last.json"
check "move hors écran : clampé à 1 - w/écran" "
i = json.load(open(sys.argv[1]))['instance']
g = i['geo']
assert g['x'] + g['w'] / $SCR_W <= 1.0001, g
assert g['y'] + g['h'] / $SCR_H <= 1.0001, g
assert g['x'] > 0.4, g
"
post "{\"op\":\"move\",\"id\":\"$ID_CC\",\"geo\":{\"col\":11,\"row\":0}}" > "$TMP/last.json"
check "move cc : col ramené dans la grille (w=4)" "
i = json.load(open(sys.argv[1]))['instance']
assert i['geo']['col'] + i['geo']['w'] <= 12, i['geo']
"

# ── 4. resize ──────────────────────────────────────────────────────────────
head_ "4 · resize"
post "{\"op\":\"resize\",\"id\":\"$ID_BG\",\"geo\":{\"w\":900,\"h\":400}}" > "$TMP/last.json"
check "resize background : w/h relus" "
i = json.load(open(sys.argv[1]))['instance']
assert (i['geo']['w'], i['geo']['h']) == (900, 400), i['geo']
assert i['geo']['x'] + i['geo']['w'] / $SCR_W <= 1.0001, i['geo']
"
post "{\"op\":\"resize\",\"id\":\"$ID_CC\",\"geo\":{\"w\":99,\"h\":99}}" > "$TMP/last.json"
check "resize cc : w borné à 12 colonnes" "
i = json.load(open(sys.argv[1]))['instance']
assert 1 <= i['geo']['w'] <= 12, i['geo']
"

# ── 5. variant : la géométrie suit la taille du registre ──────────────────
head_ "5 · variant"
post "{\"op\":\"variant\",\"id\":\"$ID_CC\",\"variant\":\"hero\"}" > "$TMP/last.json"
ID_CC_BEFORE="$ID_CC"
check "variant cc hero : 8x2 cellules" "
i = json.load(open(sys.argv[1]))['instance']
assert i['variant'] == 'hero', i['variant']
assert (i['geo']['w'], i['geo']['h']) == (8, 2), i['geo']
"
post "{\"op\":\"variant\",\"id\":\"$ID_BG\",\"variant\":\"hero\",\"screen\":{\"w\":$SCR_W,\"h\":$SCR_H}}" > "$TMP/last.json"
check "variant background hero : 560x260 px, x/y re-clampés" "
i = json.load(open(sys.argv[1]))['instance']
assert (i['geo']['w'], i['geo']['h']) == (560, 260), i['geo']
assert i['geo']['x'] + i['geo']['w'] / $SCR_W <= 1.0001, i['geo']
"

# ── 6. rm : l'id supprimé n'est jamais réattribué ─────────────────────────
head_ "6 · rm + unicité"
post "{\"op\":\"rm\",\"id\":\"$ID_CC\"}" > "$TMP/last.json"
get > "$TMP/all.json"
check_all "$ID_CC supprimé du fichier" "
doc = json.load(open(sys.argv[1]))
assert all(i['id'] != '$ID_CC' for i in doc['data']['instances'])
"
post '{"op":"add","type":"clock","host":"cc"}' > "$TMP/last.json"
ID_NEW=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["instance"]["id"])' "$TMP/last.json")
CREATED+=("$ID_NEW")
check "nouvel id jamais réutilisé (ancien $ID_CC, nouveau $ID_NEW)" "
assert '$ID_NEW' != '$ID_CC', '$ID_NEW'
num = lambda s: int(s.split('-')[-1])
assert num('$ID_NEW') > num('$ID_CC'), '$ID_NEW'
"

# ── 7. refus explicite : type non livré ───────────────────────────────────
head_ "7 · refus"
CODE=$(curl -s -o "$TMP/last.json" -w '%{http_code}' -m 5 -X POST "$BASE/api/widgets" \
        -H 'Content-Type: application/json' -d '{"op":"add","type":"fantome","host":"cc"}')
check "type inconnu → 400 + message" "
assert '$CODE' == '400', 'code $CODE'
d = json.load(open(sys.argv[1]))
assert d.get('ok') is False and d.get('error'), d
"

printf '\n%s : %d ok, %d échec(s)\n' "$(basename "$0")" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
