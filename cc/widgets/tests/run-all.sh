#!/usr/bin/env bash
# run-all.sh — vérifications du socle widgets v1a (brief §7 point 7 / §8).
#
# 1. qmllint Qt6 (PAS /usr/bin/qmllint qui est Qt5 et muet)
# 2. chargement réel du harnais 900x620 (un fichier qui passe qmllint peut
#    tuer le shell au chargement — donc on charge vraiment)
# 3. API : GET, POST add / move / style / option / rm, bornes, refus, relecture
# 4. persistance après redémarrage du backend
# 5. bash -n sur les lanceurs
#
# Le widgets.json réel est SAUVEGARDÉ puis RESTAURÉ : le test ne laisse aucune
# instance de test derrière lui.
#
# Usage : bash cc/widgets/tests/run-all.sh      (depuis n'importe où)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC="$(cd "$HERE/../.." && pwd)"                 # cc/
MODULE="$CC/widgets/Sasquatch/Widgets"
WIDGETS="$CC/widgets.json"
PORT="${SASQUATCH_CC_PORT:-8765}"
API="http://127.0.0.1:$PORT"
QML_IMPORT_PATH="$CC/widgets${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
export QML_IMPORT_PATH
QMLLINT="/usr/lib/qt6/bin/qmllint"

pass=0
fail=0
ok() { printf '  OK   %s\n' "$1"; pass=$((pass + 1)); }
ko() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

# Vérifie une assertion python sur la dernière réponse HTTP : assert_json <nom> <json> <python>
assert_json() {
    local name="$1" payload="$2" expr="$3"
    if printf '%s' "$payload" | python3 -c "
import json, sys
d = json.load(sys.stdin)
ok = ($expr)
sys.exit(0 if ok else 1)
" 2>/dev/null; then
        ok "$name"
    else
        ko "$name  (réponse : ${payload:0:160})"
    fi
}

post() { curl -s -X POST -H 'Content-Type: application/json' -d "$1" "$API/api/widgets"; }

echo "== 1. qmllint Qt6 =="
if [ ! -x "$QMLLINT" ]; then
    ko "qmllint Qt6 absent ($QMLLINT)"
else
    while IFS= read -r f; do
        if out="$("$QMLLINT" -I /usr/lib/qt6/qml "$f" 2>&1)"; then
            # qmllint sort 0 même avec des avertissements : on veut zéro
            # ERREUR (les warnings de propriétés non qualifiées ne bloquent
            # pas le chargement, vérifié au point 2).
            if printf '%s' "$out" | grep -q "Error:"; then
                ko "$(basename "$f") : $(printf '%s' "$out" | grep -m1 'Error:')"
            else
                ok "$(basename "$f")"
            fi
        else
            ko "$(basename "$f") : qmllint a échoué"
        fi
    done < <(find "$MODULE" "$HERE" "$CC/background" -name '*.qml' | sort)
fi

echo
echo "== 2. chargement réel du harnais (900x620, layer Top) =="
log="$(mktemp)"
if QML_IMPORT_PATH="$QML_IMPORT_PATH" timeout 10 quickshell -p "$HERE/harness.qml" > "$log" 2>&1; then
    :
fi
if grep -q "Configuration Loaded" "$log"; then
    ok "Configuration Loaded"
else
    ko "le harnais n'a pas chargé : $(head -3 "$log")"
fi
if grep -qiE "is not a type|Cannot assign|is not defined|TypeError|unavailable" "$log"; then
    ko "erreurs QML au chargement : $(grep -iE 'is not a type|Cannot assign|is not defined|TypeError|unavailable' "$log" | head -2)"
else
    ok "aucune erreur QML dans la sortie"
fi
rm -f "$log"

echo
echo "== 3. API /api/widgets =="
if ! curl -s -o /dev/null -m 2 "$API/api/stats"; then
    ko "backend injoignable sur $PORT — systemctl --user start sasquatch-cc"
    echo
    echo "== bilan : $pass OK / $fail FAIL =="
    exit 1
fi

BACKUP="$(mktemp)"
cp "$WIDGETS" "$BACKUP"
restore() {
    cp "$BACKUP" "$WIDGETS"
    rm -f "$BACKUP"
}
trap restore EXIT

base_rev="$(curl -s "$API/api/widgets" | python3 -c 'import json,sys;print(json.load(sys.stdin)["revision"])')"
base_count="$(curl -s "$API/api/widgets" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)["data"]["instances"]))')"
ok "GET /api/widgets (révision $base_rev, $base_count instances)"

r="$(post '{"op":"add","type":"clock","host":"bar","variant":"compact"}')"
assert_json "POST add clock/bar" "$r" "d['ok'] is True and d['instance']['geo']['slot'] == 0 and d['revision'] == $base_rev + 1"
new_id="$(printf '%s' "$r" | python3 -c 'import json,sys;print(json.load(sys.stdin)["instance"]["id"])')"

r="$(post '{"op":"move","id":"clock-bg","geo":{"x":1.4}}')"
assert_json "POST move clock-bg x=1.4 → borné à 0.95" "$r" "d['ok'] is True and d['instance']['geo']['x'] == 0.95"

r="$(post '{"op":"style","id":"clock-bg","style":{"alpha":5,"radius":99,"blur":-3}}')"
assert_json "POST style hors bornes → 0.90 / 24 / 0" "$r" \
    "d['instance']['style']['alpha'] == 0.9 and d['instance']['style']['radius'] == 24 and d['instance']['style']['blur'] == 0"

r="$(post '{"op":"option","id":"clock-bg","key":"mode","value":"analog"}')"
assert_json "POST option clock.mode=analog" "$r" "d['ok'] is True and d['instance']['options']['mode'] == 'analog'"

code="$(curl -s -o /tmp/.rin-wj-err -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
        -d '{"op":"option","id":"clock-bg","key":"mode","value":"binaire"}' "$API/api/widgets")"
assert_json "POST option invalide → 400" "$(cat /tmp/.rin-wj-err)" "d['ok'] is False and d['error']"
if [ "$code" = "400" ]; then ok "code HTTP 400 sur option invalide"; else ko "code HTTP $code au lieu de 400"; fi

code="$(curl -s -o /tmp/.rin-wj-err -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
        -d '{"op":"move","id":"clock-bg","geo":{"z":1}}' "$API/api/widgets")"
if [ "$code" = "400" ] && python3 -c "
import json, sys
try:
    msg = json.load(open('/tmp/.rin-wj-err'))['error']
except Exception:
    sys.exit(1)
sys.exit(0 if 'geo inconnue' in msg else 1)
"; then
    ok "POST clé geo inconnue → 400 + message"
else
    ko "clé geo inconnue : code $code / $(head -c 120 /tmp/.rin-wj-err)"
fi

# Relecture : le fichier sur disque doit porter la révision renvoyée.
disk_rev="$(python3 -c 'import json;print(json.load(open("'"$WIDGETS"'"))["revision"])')"
api_rev="$(curl -s "$API/api/widgets" | python3 -c 'import json,sys;print(json.load(sys.stdin)["revision"])')"
if [ "$disk_rev" = "$api_rev" ]; then ok "relecture : révision disque == API ($disk_rev)"; else ko "révision disque $disk_rev ≠ API $api_rev"; fi

r="$(post "{\"op\":\"rm\",\"id\":\"$new_id\"}")"
assert_json "POST rm $new_id" "$r" "d['ok'] is True"

count="$(curl -s "$API/api/widgets" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)["data"]["instances"]))')"
if [ "$count" = "$base_count" ]; then ok "$count instances après rm (état initial restauré)"; else ko "$count instances après rm (attendu $base_count)"; fi

echo
echo "== 4. persistance après redémarrage du backend =="
before="$(curl -s "$API/api/widgets" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["revision"], [i["geo"] for i in d["data"]["instances"]])')"
if systemctl --user restart sasquatch-cc 2>/dev/null; then
    for _ in $(seq 1 40); do
        curl -s -o /dev/null -m 1 "$API/api/widgets" && break
        sleep 0.2
    done
    after="$(curl -s "$API/api/widgets" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["revision"], [i["geo"] for i in d["data"]["instances"]])')"
    if [ "$before" = "$after" ]; then ok "mêmes révision + géométries après restart"; else ko "état changé : $before → $after"; fi
else
    ko "systemctl --user restart sasquatch-cc a échoué"
fi

echo
echo "== 5. média v1b (Music, sources, épingle de source) =="

# 5.1 sources détectées
src="$(curl -s -m 6 "$API/api/music/sources")"
assert_json "GET /api/music/sources" "$src" \
    "d['ok'] is True and isinstance(d['sources'], list) and 'pinned' in d and 'pinnedActive' in d"

# 5.2 les 4 variantes rendues + clamp fraction + arrêt des timers
log="$(mktemp)"
QML_IMPORT_PATH="$QML_IMPORT_PATH" timeout 14 quickshell -p "$HERE/media-variants.qml" > "$log" 2>&1
if grep -q "Configuration Loaded" "$log"; then
    ok "media-variants.qml : Configuration Loaded"
else
    ko "media-variants.qml n'a pas chargé : $(head -3 "$log")"
fi
if grep -qiE "is not a type|Cannot assign|is not defined|TypeError|unavailable" "$log"; then
    ko "erreurs QML (média) : $(grep -iE 'is not a type|Cannot assign|is not defined|TypeError|unavailable' "$log" | head -2)"
else
    ok "média : aucune erreur QML au chargement"
fi
if grep -q "fraction retenue = 0.5333333333333333" "$log" && grep -q "x + w = 900" "$log"; then
    ok "clamp fraction 0.62 / 420 px sur 900 px → 0.5333 (x + w = 900)"
else
    ko "clamp fraction : $(grep 'fraction retenue' "$log" | head -1)"
fi
if grep -q "delta status=0 delta viz=0" "$log"; then
    ok "surface cachée → timers status + viz arrêtés"
else
    ko "timers : $(grep 'après masquage' "$log" | head -1)"
fi
rm -f "$log"

# 5.3 épingle : POST → fichier → survit au redémarrage → source inconnue refusée
#     → retour auto. Le fichier ~/.config/cc/music.json est sauvegardé/restauré.
PINF="$HOME/.config/cc/music.json"
PINBAK="$(mktemp)"
had_pin=0
if [ -f "$PINF" ]; then
    cp "$PINF" "$PINBAK"
    had_pin=1
fi
pin_name="$(printf '%s' "$src" | python3 -c 'import json,sys
d = json.load(sys.stdin)
s = d["sources"]
print(s[0]["name"] if s else "")')"
if [ -z "$pin_name" ]; then
    ko "aucune source détectée : épingle non testable (rien ne joue / aucun lecteur)"
else
    r="$(curl -s -m 6 -X POST -H 'Content-Type: application/json' \
            -d "{\"name\":\"$pin_name\"}" "$API/api/music/source")"
    assert_json "POST /api/music/source $pin_name → épinglée" "$r" \
        "d['ok'] is True and d['pinned'] == '$pin_name' and d['pinnedActive'] is True"

    if python3 -c "
import json, sys
sys.exit(0 if json.load(open('$PINF'))['source'] == '$pin_name' else 1)
"; then
        ok "$PINF écrit (source = $pin_name)"
    else
        ko "$PINF non écrit"
    fi

    systemctl --user restart sasquatch-cc 2>/dev/null
    for _ in $(seq 1 40); do
        curl -s -o /dev/null -m 1 "$API/api/stats" && break
        sleep 0.2
    done
    r="$(curl -s -m 6 "$API/api/music/sources")"
    assert_json "épingle conservée après redémarrage du backend" "$r" \
        "d['pinned'] == '$pin_name' and d['pinnedActive'] is True"

    r="$(curl -s -m 6 -X POST -H 'Content-Type: application/json' \
            -d '{"name":"source-inexistante"}' "$API/api/music/source")"
    assert_json "POST source inconnue → refus explicite" "$r" \
        "d['ok'] is False and 'inconnue' in d['error']"

    r="$(curl -s -m 6 -X POST -H 'Content-Type: application/json' \
            -d '{"name":""}' "$API/api/music/source")"
    assert_json "POST name vide → retour auto" "$r" "d['ok'] is True and d['pinned'] == ''"
fi
if [ "$had_pin" = "1" ]; then cp "$PINBAK" "$PINF"; else rm -f "$PINF"; fi
rm -f "$PINBAK"

echo
echo "== 6. bash -n (lanceurs) =="
for s in "$CC/cc.sh" "$CC/background/background.sh" "$CC/bar/bar.sh"; do
    if bash -n "$s" 2>/dev/null; then ok "bash -n $(basename "$s")"; else ko "bash -n $(basename "$s")"; fi
done

echo
echo "== bilan : $pass OK / $fail FAIL =="
[ "$fail" -eq 0 ]
