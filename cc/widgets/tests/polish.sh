#!/usr/bin/env bash
# polish.sh — un contrôle par widget (brief polish §1/§2, livrable §5.3).
#
# Pour CHAQUE widget :
#   1. lit la ROUTE HTTP qui l'alimente (et échoue si le backend est mort) ;
#   2. charge le widget seul dans le harnais (polish-harness.qml, jamais le CC
#      plein écran) et récupère les textes RÉELLEMENT affichés ;
#   3. vérifie que la valeur servie par HTTP est bien celle qui est affichée,
#      et qu'aucun jargon interdit (§1) n'apparaît ;
#   4. enregistre un rendu PNG par widget dans $OUTDIR.
#
# Usage : bash cc/widgets/tests/polish.sh            (depuis n'importe où)
#         SASQUATCH_CC_PORT=8799 bash …/polish.sh    (backend isolé)
#
# Aucune écriture durable : la note de test est retirée, le favori inconnu de
# test est retiré de bar.json (bar.json sauvegardé/restauré).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC="$(cd "$HERE/../.." && pwd)"
MODULE="$CC/widgets/Sasquatch/Widgets"
PORT="${SASQUATCH_CC_PORT:-8765}"
API="http://127.0.0.1:$PORT"
export QML_IMPORT_PATH="$CC/widgets"
HARNESS="$HERE/polish-harness.qml"
OUTDIR="${SASQUATCH_POLISH_OUT:-$(mktemp -d)}"
mkdir -p "$OUTDIR"

pass=0
fail=0
ok() { printf '  OK   %s\n' "$1"; pass=$((pass + 1)); }
ko() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

TEXTS=""
PNG=""
WIDGET=""
VARIANT=""

# ── 0. Porte d'entrée : le backend doit servir NOS routes ──────────────────
echo "== 0. backend :8765 (brief §0) =="
code_w="$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$API/api/widgets")"
code_n="$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$API/api/notes")"
if [ "$code_w" = "200" ] && [ "$code_n" = "200" ]; then
    ok "/api/widgets et /api/notes répondent 200"
else
    ko "/api/widgets=$code_w /api/notes=$code_n — backend périmé : ne rien corriger côté QML"
    echo
    echo "== bilan : $pass OK / $fail FAIL =="
    exit 1
fi
ok "révision du board : $(curl -s "$API/api/widgets" | python3 -c 'import json,sys;print(json.load(sys.stdin)["revision"])')"

# ── 1. qmllint Qt6 (le binaire Qt5 de /usr/bin est muet) ──────────────────
echo
echo "== 1. qmllint Qt6 =="
QMLLINT="/usr/lib/qt6/bin/qmllint"
if [ ! -x "$QMLLINT" ]; then
    ko "qmllint Qt6 absent ($QMLLINT)"
else
    while IFS= read -r f; do
        out="$("$QMLLINT" -I /usr/lib/qt6/qml -I "$CC/widgets" "$f" 2>&1)"
        if printf '%s' "$out" | grep -q "Error:"; then
            ko "$(basename "$f") : $(printf '%s' "$out" | grep -m1 'Error:')"
        else
            ok "$(basename "$f")"
        fi
    done < <(find "$MODULE" "$HERE" -name '*.qml' | sort)
fi

# ── Outils de rendu ───────────────────────────────────────────────────────
# render <type> <variante> : charge le widget dans le harnais, pose TEXTS.
render() {
    WIDGET="$1"
    VARIANT="$2"
    local log="$OUTDIR/$WIDGET-$VARIANT.log"
    PNG="$OUTDIR/$WIDGET-$VARIANT.png"
    QML_IMPORT_PATH="$QML_IMPORT_PATH" \
    SASQUATCH_WIDGET="$WIDGET" SASQUATCH_VARIANT="$VARIANT" SASQUATCH_GRAB="$PNG" \
        timeout 30 quickshell -p "$HARNESS" > "$log" 2>&1
    if ! grep -q "POLISH-DONE" "$log"; then
        TEXTS=""
        ko "$WIDGET/$VARIANT : le harnais n'a pas rendu ($(grep -m1 -E 'Error|error' "$log" | cut -c1-90))"
        return 1
    fi
    if grep -qiE "is not a type|Cannot assign|is not defined|TypeError|Cannot read" "$log"; then
        TEXTS=""
        ko "$WIDGET/$VARIANT : erreur QML — $(grep -iE 'is not a type|Cannot assign|is not defined|TypeError|Cannot read' "$log" | head -1 | cut -c1-110)"
        return 1
    fi
    TEXTS="$(sed -n 's/.*POLISH-TEXT //p' "$log")"
    return 0
}

# want <libellé> <texte exact attendu>
want() {
    if printf '%s\n' "$TEXTS" | grep -Fxq -- "$2"; then
        ok "$1 : « $2 » affiché"
    else
        ko "$1 : « $2 » ABSENT (affiché : $(printf '%s' "$TEXTS" | tr '\n' '|' | cut -c1-150))"
    fi
}

# want_not <libellé> <texte interdit>
want_not() {
    if printf '%s\n' "$TEXTS" | grep -Fxq -- "$2"; then
        ko "$1 : « $2 » NE DOIT PAS apparaître"
    else
        ok "$1 : pas de « $2 »"
    fi
}

# vocab <libellé> : aucun mot technique interdit par le brief §1
VOCAB_KO="MPRIS|Pulse|open-meteo|wpctl|pipewire|makoctl|Hyprland|/home/"
vocab() {
    local hit
    hit="$(printf '%s\n' "$TEXTS" | grep -nE "$VOCAB_KO" | head -3 | tr '\n' ' ')"
    if [ -z "$hit" ]; then
        ok "$1 : aucun jargon technique visible"
    else
        ko "$1 : jargon visible → $hit"
    fi
}

jget() { curl -s -m 8 "$API$1"; }
jpy() { python3 -c "$1"; }

# ── 2. Média (route /api/music/status) ────────────────────────────────────
echo
echo "== 2. media =="
MEDIA_JSON="$(jget /api/music/status)"
if [ -n "$MEDIA_JSON" ]; then
    ok "GET /api/music/status → $(printf '%s' "$MEDIA_JSON" | cut -c1-80)…"
else
    ko "GET /api/music/status muet"
fi
if render media normal; then
    title="$(printf '%s' "$MEDIA_JSON" | jpy 'import json,sys;d=json.load(sys.stdin);print(d.get("title") or "")')"
    src="$(printf '%s' "$MEDIA_JSON" | jpy 'import json,sys;d=json.load(sys.stdin);print(d.get("source") or "none")')"
    player="$(printf '%s' "$MEDIA_JSON" | jpy 'import json,sys;d=json.load(sys.stdin);print((d.get("player") or "")[:1].upper()+(d.get("player") or "")[1:])')"
    case "$src" in
        mpris) label="${player:-Lecteur}" ;;
        mpd)   label="MPD" ;;
        pulse) label="Audio système" ;;
        web)   label="Navigateur" ;;
        *)     label="Aucun lecteur" ;;
    esac
    if [ -n "$title" ]; then
        want "média" "$title"
    else
        want "média" "Rien en lecture"
    fi
    want "média · lecteur nommé" "$label"
    want "média · pilule de source" "● $label"
    want_not "média · pas de « 0:00 / 0:00 »" "0:00 / 0:00"
    vocab "média"
    ok "rendu : $PNG"
fi
if render media hero; then
    want_not "média hero · pas de « 0:00 / 0:00 »" "0:00 / 0:00"
    vocab "média hero"
    ok "rendu : $PNG"
fi

# ── 3. Météo (route /api/weather) ─────────────────────────────────────────
echo
echo "== 3. weather =="
W_JSON="$(jget /api/weather)"
ok "GET /api/weather → $(printf '%s' "$W_JSON" | cut -c1-80)…"
if render weather normal; then
    temp="$(printf '%s' "$W_JSON" | jpy 'import json,sys;d=json.load(sys.stdin);print(round(d["temp"]))')"
    city="$(printf '%s' "$W_JSON" | jpy 'import json,sys;d=json.load(sys.stdin);print(d.get("city") or "")')"
    lab="$(printf '%s' "$W_JSON" | jpy 'import json,sys;d=json.load(sys.stdin);print(d.get("label") or "")')"
    want "météo · titre" "Météo"
    want "météo · température servie" "$temp"
    want "météo · sous-titre ville · ciel" "$city · $lab"
    vocab "météo"
    ok "rendu : $PNG"
fi
if render weather hero; then
    age="$(printf '%s' "$W_JSON" | jpy 'import json,sys;d=json.load(sys.stdin);s=round(d.get("age_s",0));print("actualisé à l\u0027instant" if s<60 else ("actualisé il y a "+str(round(s/60))+" min" if s<3600 else "actualisé il y a "+str(round(s/3600))+" h"))')"
    want "météo hero · fraîcheur en français" "$age"
    vocab "météo hero"
    ok "rendu : $PNG"
fi

# ── 4. Ressources (route /api/stats) ──────────────────────────────────────
echo
echo "== 4. resources =="
# La charge processeur est recalculée à chaque GET : on encadre le rendu par
# deux relevés et on accepte la valeur affichée si elle vient de l'un des deux.
S_JSON="$(jget /api/stats)"
ok "GET /api/stats → $(printf '%s' "$S_JSON" | cut -c1-70)…"
SAMPLES="$OUTDIR/stats-samples.txt"
: > "$SAMPLES"
# Échantillonnage PENDANT le rendu : /api/stats recalcule la charge à chaque
# appel, on accepte donc toute valeur réellement servie dans la fenêtre.
( for _ in $(seq 1 18); do
      curl -s -m 2 "$API/api/stats" | jpy 'import json,sys
d=json.load(sys.stdin)
print(round(d["cpu"]), round(d["ram"]["pct"]))' >> "$SAMPLES" 2>/dev/null
      sleep 0.35
  done ) &
SAMPLER=$!
if render resources normal; then
    wait "$SAMPLER" 2>/dev/null
    want "ressources · titre" "Utilisation"
    # Le rendu lui-même consomme du CPU/RAM : la valeur affichée doit tomber
    # dans la fenêtre des relevés (± bruit de mesure), pas à l'unité près.
    verdict="$(printf '%s\n' "$TEXTS" | SAMPLES="$SAMPLES" python3 -c '
import os, sys
texts = [l.strip() for l in sys.stdin if l.strip()]
nums = []
for l in texts:
    try:
        nums.append(int(l))
    except ValueError:
        pass
pairs = []
for line in open(os.environ["SAMPLES"]):
    p = line.split()
    if len(p) == 2:
        pairs.append((int(p[0]), int(p[1])))
def near(n, v):
    return abs(n - v) <= 2
cpu_ok = any(near(n, c) for n in nums for (c, r) in pairs)
ram_ok = any(near(n, r) for n in nums for (c, r) in pairs)
print(("1" if cpu_ok else "0") + ("1" if ram_ok else "0") + " " + ",".join(str(p[0]) for p in pairs[:6]))
')"
    case "$verdict" in
        11*) ok "ressources · processeur et mémoire : valeurs affichées cohérentes avec /api/stats ($(printf '%s' "$verdict" | cut -d' ' -f2-))" ;;
        10*) ko "ressources · mémoire : valeur affichée hors des relevés ($(printf '%s' "$verdict" | cut -d' ' -f2-))" ;;
        01*) ko "ressources · processeur : valeur affichée hors des relevés ($(printf '%s' "$verdict" | cut -d' ' -f2-))" ;;
        *)   ko "ressources : aucune valeur affichée ne correspond aux relevés" ;;
    esac
    want "ressources · légende" "Processeur"
    want "ressources · légende" "Mémoire"
    want "ressources · légende" "Carte graphique"
    vocab "ressources"
    ok "rendu : $PNG"
fi
if render resources compact; then
    want_not "ressources compact · pas de jargon" "GPU"
    vocab "ressources compact"
    ok "rendu : $PNG"
fi

# ── 5. Tâches (route /api/tasks) ──────────────────────────────────────────
echo
echo "== 5. tasks =="
T_JSON="$(jget /api/tasks)"
total="$(printf '%s' "$T_JSON" | jpy 'import json,sys;print(json.load(sys.stdin)["total"])')"
done="$(printf '%s' "$T_JSON" | jpy 'import json,sys;print(json.load(sys.stdin)["done"])')"
ok "GET /api/tasks → total=$total done=$done"
if render tasks normal; then
    want "tâches · titre" "Mes tâches"
    want "tâches · champ d'ajout explicite" "Ajouter une tâche…"
    want "tâches · bouton +" "+"
    if [ "$total" -eq 0 ]; then
        want "tâches · état vide" "Aucune tâche"
    else
        pending=$((total - done))
        if [ "$pending" -eq 0 ]; then
            want "tâches · compteur" "tout est fait"
        else
            want "tâches · compteur restant" "$pending restantes"
        fi
    fi
    vocab "tâches"
    ok "rendu : $PNG"
fi

# ── 6. Son / luminosité (routes /api/system/*) ────────────────────────────
echo
echo "== 6. volume =="
V_JSON="$(jget /api/system/volume)"
B_JSON="$(jget /api/system/brightness)"
vol="$(printf '%s' "$V_JSON" | jpy 'import json,sys;print(round(json.load(sys.stdin)["volume"]))')"
muted="$(printf '%s' "$V_JSON" | jpy 'import json,sys;print(json.load(sys.stdin).get("muted", False))')"
bri="$(printf '%s' "$B_JSON" | jpy 'import json,sys;print(round(json.load(sys.stdin)["brightness"]))')"
ok "GET /api/system/volume → $vol (muted=$muted) · brightness → $bri"
if render volume normal; then
    want "son · libellé" "Son"
    want "luminosité · libellé" "Luminosité"
    if [ "$muted" = "True" ]; then
        want "son · état coupé" "Son coupé"
    else
        want "son · valeur servie" "$vol %"
    fi
    want "luminosité · valeur servie" "$bri %"
    vocab "son"
    ok "rendu : $PNG"
fi

# ── 7. Batterie (sysfs BAT0, la source du widget) ─────────────────────────
echo
echo "== 7. battery =="
pct="$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "")"
state="$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "")"
if [ -n "$pct" ]; then
    ok "sysfs BAT0 → $pct % ($state)"
else
    ok "aucune BAT0 : état « Batterie non détectée » attendu"
fi
if render battery normal; then
    if [ -n "$pct" ]; then
        want "batterie · niveau réel" "$pct %"
        want_not "batterie · pas de « pleine »" "pleine"
        if [ "$state" = "Charging" ]; then
            want "batterie · état" "En charge"
        fi
    else
        want "batterie · absente" "Batterie non détectée"
    fi
    vocab "batterie"
    ok "rendu : $PNG"
fi

# ── 8. Playlist (routes /api/playlist/*) ──────────────────────────────────
echo
echo "== 8. playlist =="
P_JSON="$(jget /api/playlist/status)"
n_tracks="$(printf '%s' "$P_JSON" | jpy 'import json,sys;d=json.load(sys.stdin);print(d.get("playlistlength",0))' 2>/dev/null || echo 0)"
ok "GET /api/playlist/status → 200 (playlistlength=$n_tracks)"
if render playlist normal; then
    want "playlist · titre" "Ma musique"
    if [ "$n_tracks" = "0" ]; then
        want "playlist · un seul message vide" "Liste vide"
    else
        want "playlist · compteur accordé" "$n_tracks morceaux"
    fi
    vocab "playlist"
    ok "rendu : $PNG"
fi

# ── 9. Calendrier (mois local + /api/tasks) ───────────────────────────────
echo
echo "== 9. calendar =="
month="$(LC_ALL=C.UTF-8 date '+%-d')"
mois="$(python3 -c 'import datetime;n=["janvier","février","mars","avril","mai","juin","juillet","août","septembre","octobre","novembre","décembre"];d=datetime.date.today();print(n[d.month-1]+" "+str(d.year))')"
if render calendar normal; then
    want "calendrier · titre" "Calendrier"
    want "calendrier · mois en toutes lettres" "$mois"
    want "calendrier · jour du jour" "$month"
    if [ "$total" -eq 0 ]; then
        want "calendrier · rien de prévu" "Rien de prévu"
    fi
    vocab "calendrier"
    ok "rendu : $PNG"
fi

# ── 10. Connexions (Quickshell + `wpctl status`) ──────────────────────────
echo
echo "== 10. connectivity =="
sink="$(wpctl status 2>/dev/null | sed -n '/Sinks:/,/Sources:/p' | grep '^\s*[│|]*\s*\*' | sed 's/^[^*]*\*//' | sed 's/^\s*[0-9]*\.\s*//' | sed 's/\[[^]]*\]//g' | sed 's/\s\+/ /g' | sed 's/^ //;s/ $//' | head -1)"
if [ -n "$sink" ]; then
    ok "wpctl status → périphérique « $sink »"
fi
if render connectivity normal; then
    want "connexions · titre" "Connexions"
    want "connexions · une ligne par info (Bluetooth)" "Bluetooth · Activé"
    if [ -n "$sink" ]; then
        want "connexions · audio réel" "Son · $sink"
    fi
    want_not "connexions · pas de doublon « adaptateur actif »" "adaptateur actif"
    vocab "connexions"
    ok "rendu : $PNG"
fi

# ── 11. Modes rapides (route /api/modes) ──────────────────────────────────
echo
echo "== 11. toggles =="
M_JSON="$(jget /api/modes)"
ok "GET /api/modes → $(printf '%s' "$M_JSON" | cut -c1-70)…"
if render toggles normal; then
    want "modes · titre" "Modes rapides"
    want "modes · libellé" "Ne pas déranger"
    want "modes · libellé" "Flou"
    want "modes · libellé" "Mode nuit"
    want "modes · libellé" "Mode léger"
    want_not "modes · ancien libellé banni" "Lumière chaude"
    vocab "modes"
    ok "rendu : $PNG"
fi
# L'état relu par le widget (Modes.flag) doit être EXACTEMENT celui servi.
SLOG="$OUTDIR/state-tests.log"
QML_IMPORT_PATH="$QML_IMPORT_PATH" timeout 30 quickshell -p "$HERE/state-tests.qml" > "$SLOG" 2>&1
GOT="$(sed -n 's/.*STATE modes //p' "$SLOG" | head -1)"
WANTED="$(printf '%s' "$M_JSON" | jpy 'import json,sys
d=json.load(sys.stdin)["real"]
print(json.dumps({k: d.get(k) for k in ("dnd","blur","bluesun","lite")}, separators=(",",":")))')"
if [ -n "$GOT" ] && [ "$GOT" = "$WANTED" ]; then
    ok "modes · état relu = état servi ($GOT)"
else
    ko "modes · état relu ($GOT) ≠ servi ($WANTED)"
fi

if render toggles compact; then
    want_not "modes compact · pas de « DND »" "DND"
    vocab "modes compact"
    ok "rendu : $PNG"
fi

# ── 12. Notifications (route /api/notifications) ──────────────────────────
echo
echo "== 12. notifications =="
N_JSON="$(jget /api/notifications)"
N_COUNT="$(printf '%s' "$N_JSON" | jpy 'import json,sys;print(json.load(sys.stdin).get("count",0))')"
ok "GET /api/notifications → count=$N_COUNT"
if render notifications normal; then
    want "notifications · titre" "Notifications"
    if [ "$N_COUNT" -gt 0 ]; then
        want "notifications · compteur" "$N_COUNT nouvelles"
    else
        want "notifications · état vide" "Aucune notification"
    fi
    if printf '%s\n' "$TEXTS" | grep -qE '\.(png|jpg|jpeg)$|notify-send'; then
        ko "notifications : nom de fichier affiché tel quel"
    else
        ok "notifications : aucun nom de fichier à l'écran"
    fi
    vocab "notifications"
    ok "rendu : $PNG"
fi

# ── 13. Bureaux (Hyprland IPC) ────────────────────────────────────────────
echo
echo "== 13. workspaces =="
if command -v hyprctl >/dev/null 2>&1 && hyprctl -j workspaces >/dev/null 2>&1; then
    wins="$(hyprctl -j workspaces 2>/dev/null | jpy '
import json,sys
d=json.load(sys.stdin)
n=0
for w in d:
    if 1 <= w.get("id",0) <= 10:
        n += w.get("windows",0)
print(n)')"
    ok "hyprctl → $wins fenêtres sur les bureaux 1..10"
else
    wins=""
    ok "Hyprland injoignable (widget doit dire « Bureaux indisponibles »)"
fi
if render workspaces normal; then
    want "bureaux · titre" "Bureaux"
    if [ -n "$wins" ]; then
        if [ "$wins" -eq 0 ]; then
            want "bureaux · aucune fenêtre" "Aucune fenêtre"
        elif [ "$wins" -eq 1 ]; then
            want "bureaux · compteur" "1 fenêtre"
        else
            want "bureaux · compteur" "$wins fenêtres"
        fi
    fi
    vocab "bureaux"
    ok "rendu : $PNG"
fi

# ── 14. Favoris (bar.json + appindex.py) ──────────────────────────────────
echo
echo "== 14. apps =="
BAR="$CC/bar/bar.json"
BARBAK="$(mktemp)"
cp "$BAR" "$BARBAK"
restore_bar() { cp "$BARBAK" "$BAR"; rm -f "$BARBAK"; }
trap restore_bar EXIT
first_app="$(python3 -c 'import json;d=json.load(open("'"$BAR"'"));a=(d.get("apps") or [{}])[0];print((a.get("desktop") or a.get("id") or "").replace(".desktop",""))')"
if render apps normal; then
    if [ -n "$first_app" ]; then
        want "favoris · nom servi" "$(python3 -c 'print("'"$first_app"'".replace("-"," ").replace("_"," ").title())')"
    fi
    want "favoris · titre" "Favoris"
    vocab "favoris"
    ok "rendu : $PNG"
fi
# App introuvable : on ajoute un favori bidon (sauvegardé/restauré) — le widget
# doit afficher la pastille + le nom propre + l'action « Retirer ».
python3 -c '
import json
p="'"$BAR"'"
d=json.load(open(p))
d.setdefault("apps",[]).append({"id":"explorer.exe","desktop":"explorer.exe",
                                "class":"explorer.exe","enabled":True})
json.dump(d,open(p,"w"),indent=4,ensure_ascii=False)
'
if render apps normal; then
    want "favoris · app introuvable nommée proprement" "Explorer"
    want "favoris · action Retirer" "Retirer"
    ok "rendu (app introuvable) : $PNG"
fi
restore_bar
trap - EXIT

# ── 15. Notes : ajout, affichage, suppression, persistance ────────────────
echo
echo "== 15. notes =="
NOTE_TEXT="note de contrôle polish $(date '+%H:%M:%S')"
ADD="$(curl -s -m 5 -X POST -H 'Content-Type: application/json' \
        -d "{\"op\":\"add\",\"text\":\"$NOTE_TEXT\"}" "$API/api/notes")"
NOTE_ID="$(printf '%s' "$ADD" | jpy 'import json,sys;d=json.load(sys.stdin);print((d.get("notes") or [{}])[-1].get("id",""))')"
N_GET="$(jget /api/notes)"
N_COUNT2="$(printf '%s' "$N_GET" | jpy 'import json,sys;print(json.load(sys.stdin).get("count",0))')"
if printf '%s' "$N_GET" | NOTE="$NOTE_TEXT" python3 -c '
import json, os, sys
d = json.load(sys.stdin)
want = os.environ["NOTE"]
sys.exit(0 if any((n or {}).get("text") == want for n in d.get("notes") or []) else 1)
'; then
    ok "POST /api/notes add → relu par GET (count=$N_COUNT2)"
else
    ko "POST /api/notes add : la note n'est pas relue"
fi
if render notes normal; then
    want "notes · titre" "Mes notes"
    want "notes · note servie affichée" "$NOTE_TEXT"
    want "notes · compteur" "$N_COUNT2 note"
    want "notes · champ d'ajout explicite" "Ajouter une note…"
    vocab "notes"
    ok "rendu : $PNG"
fi
# Persistance : la note doit survivre à un redémarrage du backend (§2 #14).
if systemctl --user restart sasquatch-cc 2>/dev/null; then
    for _ in $(seq 1 40); do
        curl -s -o /dev/null -m 1 "$API/api/notes" && break
        sleep 0.25
    done
    if jget /api/notes | NOTE="$NOTE_TEXT" python3 -c '
import json, os, sys
d = json.load(sys.stdin)
want = os.environ["NOTE"]
sys.exit(0 if any((n or {}).get("text") == want for n in d.get("notes") or []) else 1)
'; then
        ok "notes · la note survit au redémarrage du backend"
    else
        ko "notes · la note a disparu après redémarrage"
    fi
else
    ko "notes · systemctl --user restart sasquatch-cc a échoué"
fi

DEL="$(curl -s -m 5 -X POST -H 'Content-Type: application/json' \
        -d "{\"op\":\"rm\",\"id\":\"$NOTE_ID\"}" "$API/api/notes")"
if printf '%s' "$DEL" | NOTE="$NOTE_TEXT" python3 -c '
import json, os, sys
d = json.load(sys.stdin)
want = os.environ["NOTE"]
sys.exit(0 if any((n or {}).get("text") == want for n in d.get("notes") or []) else 1)
'; then
    ko "POST /api/notes rm : la note est encore là"
else
    ok "POST /api/notes rm → note retirée (id $NOTE_ID)"
fi

# ── 16. Microcopie des notifications (règles non visibles à l'écran) ──────
echo
echo "== 16. copy-tests (titres humains) =="
COPY_LOG="$OUTDIR/copy-tests.log"
QML_IMPORT_PATH="$QML_IMPORT_PATH" timeout 30 quickshell -p "$HERE/copy-tests.qml" > "$COPY_LOG" 2>&1
while IFS= read -r line; do ok "${line#COPY-OK }"; done < <(sed -n 's/.*COPY-OK //p' "$COPY_LOG")
while IFS= read -r line; do ko "${line#COPY-FAIL }"; done < <(sed -n 's/.*COPY-FAIL //p' "$COPY_LOG")
grep -q "COPY-DONE 0" "$COPY_LOG" || ko "copy-tests : au moins un cas échoue"

echo
echo "== bilan : $pass OK / $fail FAIL — rendus dans $OUTDIR =="
[ "$fail" -eq 0 ]
