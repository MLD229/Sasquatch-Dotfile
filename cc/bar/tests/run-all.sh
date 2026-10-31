#!/usr/bin/env bash
# run-all.sh — vérifications de la barre verticale (cc/bar).
#
# Non destructif : ne modifie ni bar.json ni l'état de la session (sauf
# ouverture/fermeture de popups via IPC, refermées à la fin).
#
#   bash tests/run-all.sh          # tout
#   bash tests/run-all.sh lint     # seulement qmllint + syntaxe
set -uo pipefail

BAR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
ok()   { printf '  OK    %s\n' "$1"; }
ko()   { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  SKIP  %s\n' "$1"; }
head_() { printf '\n== %s ==\n' "$1"; }

# ── 1. qmllint sur CHAQUE fichier QML ────────────────────────────────────
head_ "qmllint (tous les .qml)"
QML_FILES=$(find "$BAR_DIR" -name '*.qml' -not -path '*/node_modules/*' | sort)
for f in $QML_FILES; do
    rel="${f#$BAR_DIR/}"
    if out=$(qmllint "$f" 2>&1); then
        [ -z "$out" ] && ok "$rel" || { ok "$rel (warnings)"; printf '%s\n' "$out" | sed 's/^/        /'; }
    else
        ko "$rel"; printf '%s\n' "$out" | sed 's/^/        /'
    fi
done
printf '  → %d fichiers QML\n' "$(printf '%s\n' "$QML_FILES" | wc -l)"

# ── 1bis. qmldir ↔ pragma Singleton ──────────────────────────────────────
# Piège vécu (v3) : un fichier déclaré `singleton` dans qml/qmldir sans
# `pragma Singleton` fait échouer le chargement de TOUT le shell
# (« qmldir defines type as singleton, but no pragma Singleton found »),
# le service boucle puis s'arrête en start-limit-hit — écran sans barre.
head_ "qmldir / pragma Singleton"
_miss=0
while read -r _kind _name _ver _file; do
    [ "$_kind" = "singleton" ] || continue
    if ! grep -q "pragma Singleton" "$BAR_DIR/qml/$_file" 2>/dev/null; then
        ko "singleton ${_name} sans pragma Singleton (${_file})"
        _miss=$((_miss + 1))
    fi
done < <(grep -E "^singleton " "$BAR_DIR/qml/qmldir")
[ "$_miss" -eq 0 ] && ok "tous les singletons du qmldir portent pragma Singleton"

# ── 2. Syntaxe bash / python ─────────────────────────────────────────────
head_ "syntaxe des scripts"
for s in "$BAR_DIR/bar.sh" "$BAR_DIR/tests/run-all.sh" "$BAR_DIR/../..//install.sh"; do
    [ -f "$s" ] || continue
    if bash -n "$s" 2>/dev/null; then ok "bash -n ${s#$BAR_DIR/}"; else ko "bash -n $s"; bash -n "$s"; fi
done
for py in "$BAR_DIR/appindex.py" "$BAR_DIR/barjson.py"; do
    if python3 -m py_compile "$py" 2>/dev/null; then
        ok "py_compile ${py#$BAR_DIR/}"
    else
        ko "py_compile $py"
    fi
done

# ── 3. appindex.py ───────────────────────────────────────────────────────
head_ "appindex.py"
IDX=$(python3 "$BAR_DIR/appindex.py" --json 2>/dev/null)
if [ -n "$IDX" ]; then
    ok "index généré"
    printf '%s' "$IDX" | python3 -c '
import json,sys
d=json.load(sys.stdin)
apps=d["apps"]; cls=d["classes"]
print("        %d apps, %d classes, %d sans icône" % (
    len(apps), len(cls), sum(1 for a in apps.values() if not a["icon"])))
for k in ("spotify","discord","kitty"):
    print("        %-8s -> %s" % (k, apps.get(k,{}).get("icon","(absent)")))
'
else
    ko "index vide"
fi

# ── 4. Backend CC (source des données) ───────────────────────────────────
head_ "backend CC 8765"
API=http://127.0.0.1:8765
PAL=$(curl -s -m 2 "$API/api/palette")
STATS=$(curl -s -m 2 "$API/api/stats")
VOL=$(curl -s -m 2 "$API/api/system/volume")
BRIGHT=$(curl -s -m 2 "$API/api/system/brightness")
[ -n "$PAL" ] && ok "GET /api/palette" || ko "GET /api/palette"
[ -n "$STATS" ] && ok "GET /api/stats" || ko "GET /api/stats"
[ -n "$VOL" ] && ok "GET /api/system/volume  $VOL" || ko "GET /api/system/volume"
[ -n "$BRIGHT" ] && ok "GET /api/system/brightness  $BRIGHT" || ko "GET /api/system/brightness"

# ── 5. Surface de la barre (layer-shell) ─────────────────────────────────
head_ "surface layer-shell"
LAYER=$(hyprctl layers -j 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(1)
for mon,v in d.items():
    for lvl,arr in v["levels"].items():
        for l in arr:
            if l.get("namespace")=="sasquatch-bar":
                print("level=%s x=%s y=%s w=%s h=%s pid=%s" % (lvl,l["x"],l["y"],l["w"],l["h"],l["pid"]))
')
if [ -n "$LAYER" ]; then ok "$LAYER"; else ko "namespace sasquatch-bar absent de hyprctl layers"; fi
RES=$(hyprctl monitors -j 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["reserved"])')
BARW=$(python3 -c 'import json;d=json.load(open("'"$BAR_DIR"'/bar.json"));print(d["bar"]["width"]+d["bar"]["marginLeft"])')
echo "        monitors[0].reserved = $RES  (attendu : réservé gauche = $BARW)"

# ── 6. Croisement de valeurs affichées ↔ API ─────────────────────────────
head_ "croisement des valeurs (barre ↔ API)"
PID=$(pgrep -x quickshell | head -1)
# Le shell peut être en train de recharger (édition de fichiers) : on réessaie
# une fois après une courte pause plutôt que de conclure à une panne.
ST=""
for _try in 1 2 3; do
    [ -n "${PID:-}" ] || break
    ST=$(quickshell ipc --pid "$PID" call bar state 2>/dev/null)
    [ -n "$ST" ] && break
    sleep 1
done
if [ -n "${ST:-}" ]; then
    printf '%s\n' "$ST" | python3 -c '
import json,sys
try: st=json.load(sys.stdin)
except Exception as e:
    print("        état IPC illisible:", e); sys.exit(1)
print("        barre : volume=%s netUp=%s netDown=%s ramPct=%s" % (
    st.get("volume"), st.get("netUp"), st.get("netDown"), st.get("ramPct")))
'
else
    skip "IPC indisponible (barre non lancée ?)"
fi
printf '%s\n' "$STATS" | python3 -c '
import json,sys
d=json.load(sys.stdin)
print("        api   : net.up=%s net.down=%s ram.pct=%s" % (d["net"]["up"],d["net"]["down"],d["ram"]["pct"]))
' 2>/dev/null

# ── 7. Popups (ouverture/fermeture via IPC) ──────────────────────────────
head_ "popups (IPC)"
if [ -n "${PID:-}" ]; then
    for p in calendar volume network notifications windows; do
        quickshell ipc --pid "$PID" call bar popup "$p" >/dev/null 2>&1
        sleep 0.4
        if hyprctl layers -j | grep -q "sasquatch-bar-$p"; then ok "popup $p ouverte"; else ko "popup $p absente"; fi
        quickshell ipc --pid "$PID" call bar close >/dev/null 2>&1
        sleep 0.2
    done
else
    skip "barre non lancée"
fi

head_ "résultat"
if [ "$FAIL" -eq 0 ]; then
    echo "  Tout est vert."
else
    echo "  $FAIL échec(s)."
fi
exit "$FAIL"
