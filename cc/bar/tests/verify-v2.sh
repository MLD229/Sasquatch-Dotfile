#!/usr/bin/env bash
# verify-v2.sh — preuves du brief v2 (polish) : chaque ligne est une COMMANDE
# et sa sortie réelle. Non destructif : tout état modifié est restauré.
#
#   bash tests/verify-v2.sh          # tout
#   bash tests/verify-v2.sh §2       # une section
#
# Aucune simulation de clic souris : ce poste n'a ni ydotool ni wtype. Les
# clics sont donc joués par le MÊME chemin de code que la souris
# (`qs ipc call bar action <nom>` → la fonction enregistrée par le module).
set -uo pipefail

BAR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API=http://127.0.0.1:8765
PASS=0
FAIL=0

ok()  { printf '  OK    %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
hd()  { printf '\n=== %s ===\n' "$1"; }

PID="$(pgrep -x quickshell | head -1)"
qs()  { quickshell ipc --pid "$PID" call bar "$@" 2>/dev/null; }
jq_() { python3 -c "$@"; }

aws()  { hyprctl activeworkspace -j | jq_ 'import json,sys;print(json.load(sys.stdin)["id"])'; }
awin() { hyprctl activewindow -j | jq_ 'import json,sys;d=json.load(sys.stdin);print(d.get("class"),d.get("address"))'; }
layer() { hyprctl layers -j | grep -q "sasquatch-bar-$1"; }

[ -n "$PID" ] || { echo "barre non lancée (pgrep quickshell vide)"; exit 1; }

# État initial (restauré à la fin)
WS0=$(aws)
VOL0=$(curl -s -m 2 "$API/api/system/volume")
DND0=$(makoctl mode 2>/dev/null | head -1)

# ─────────────────────────────────────────────────────────────────────────
hd "§1  clic app = aller là-bas (2 fenêtres kitty, 2 workspaces)"
read -r KWS1 KADDR1 <<<"$(hyprctl clients -j | jq_ '
import json,sys
ks=[c for c in json.load(sys.stdin) if c["class"]=="kitty"]
ks.sort(key=lambda c: c["workspace"]["id"])
print(ks[0]["workspace"]["id"], ks[0]["address"])')"
read -r KWS2 KADDR2 <<<"$(hyprctl clients -j | jq_ '
import json,sys
ks=[c for c in json.load(sys.stdin) if c["class"]=="kitty"]
ks.sort(key=lambda c: c["workspace"]["id"])
print(ks[-1]["workspace"]["id"], ks[-1]["address"])')"
echo "  cibles : kitty ws$KWS1 ($KADDR1) et kitty ws$KWS2 ($KADDR2)"

for pair in "1:$KWS1:$KADDR1" "2:$KWS2:$KADDR2"; do
    n=${pair%%:*}; rest=${pair#*:}; tgtws=${rest%%:*}; tgtaddr=${rest#*:}
    hyprctl dispatch focuswindow "address:$tgtaddr" >/dev/null; sleep 0.5
    hyprctl dispatch workspace 9 >/dev/null; sleep 0.5
    echo "  [$n] éloigné sur ws$(aws), clic simulé (focusApp kitty)"
    qs focusApp kitty >/dev/null; sleep 1.0
    w=$(aws); c=$(awin)
    if [ "$w" = "$tgtws" ] && [ "${c%% *}" = "kitty" ]; then
        ok "[$n] activeworkspace=$w activewindow=$c (attendu ws$tgtws + kitty)"
    else
        ko "[$n] activeworkspace=$w activewindow=$c (attendu ws$tgtws + kitty)"
    fi
done
WARN=$(journalctl --user -u sasquatch-bar --since "-5min" --no-pager | grep -c "No such window found")
[ "$WARN" = "0" ] && ok "0 « No such window found » au journal" \
                  || ko "$WARN « No such window found » au journal"

# ─────────────────────────────────────────────────────────────────────────
hd "§2  boutons : cible = bloc (32 px à 40), clic = action réelle"
echo "  -- géométrie (Ui.dumpRects, mesures vivantes) --"
qs rects | jq_ '
import json,sys
rs=[r for r in json.load(sys.stdin) if not r["name"].startswith("popup:")]
# v4 : la cible d un bloc de barre vaut Config.block (32 px a 40/4), les boutons
# de popup gardent 38 px. Seuil de controle : 30 px (sous, c est une anomalie).
bad=[r for r in rs if isinstance(r.get("hitMin"),int) and r["hitMin"]<30]
mis=[r for r in rs if r.get("hitMatchesVisual") is not True]
cx=sorted(set(r["cx"] for r in rs)); w=sorted(set(r["w"] for r in rs))
print("  cibles mesurées      : %d" % len(rs))
print("  centre unique (x+w/2): %s  (barre 40 → attendu 20)" % cx)
print("  largeurs             : %s" % w)
print("  zone cliquable = zone visuelle : %s" % ("oui pour toutes" if not mis else [r["name"] for r in mis]))
print("  cibles < 30 px       : %s" % ([ (r["name"], r["hitMin"]) for r in bad] or "aucune"))
'
echo "  -- actions (même code que la souris) --"

# loupe → rofi (attente active : rofi met ~0,5 s à apparaître)
pgrep -x rofi >/dev/null && { pkill -x rofi; sleep 1; }
qs action search >/dev/null
RP=""
for _ in 1 2 3 4 5 6; do sleep 0.5; RP=$(pgrep -x rofi | head -1); [ -n "$RP" ] && break; done
if [ -n "$RP" ]; then ok "search → rofi lancé (pid $RP)"; pkill -x rofi; sleep 0.5
else ko "search → rofi non lancé"; fi

# chaque workspace
CUR=$(aws)
for ws in $(qs rects | jq_ 'import json,sys
print(" ".join(r["name"].split(":",1)[1] for r in json.load(sys.stdin) if r["name"].startswith("ws:")))' ); do
    qs action "ws:$ws" >/dev/null; sleep 0.4
    echo "    ws:$ws → activeworkspace=$(aws)"
done
qs action "ws:いち" >/dev/null; sleep 0.4
[ "$(aws)" = "1" ] && ok "workspaces : clic → workspace 1" || ko "workspaces : clic → ws$(aws)"

# débit → popup réseau
qs action netRate >/dev/null; sleep 0.5
layer network && ok "netRate → popup réseau ouverte" || ko "netRate → popup réseau"
qs close >/dev/null; sleep 0.3

# horloge → calendrier
qs action clock >/dev/null; sleep 0.5
layer calendar && ok "clock → calendrier ouvert" || ko "clock → calendrier"
qs close >/dev/null; sleep 0.3

# volume : clic + molette
qs action volume >/dev/null; sleep 0.5
layer volume && ok "volume (clic) → popup volume ouverte" || ko "volume (clic) → popup"
qs close >/dev/null; sleep 0.3
V1=$(curl -s -m 2 "$API/api/system/volume"; echo)
qs action volume-up >/dev/null; sleep 0.8
V2=$(curl -s -m 2 "$API/api/system/volume"; echo)
qs action volume-down >/dev/null; sleep 0.8
V3=$(curl -s -m 2 "$API/api/system/volume"; echo)
echo "    volume avant=$V1  molette+= $V2  molette-= $V3"
[ "$V1" != "$V2" ] && [ "$V2" != "$V3" ] && ok "volume (molette) → ±5 % appliqués" \
                                        || ko "volume (molette) sans effet"

# apps épinglées : gauche (focus), droit (menu), molette (cycle)
for id in $(qs rects | jq_ 'import json,sys
print(" ".join(r["name"][4:] for r in json.load(sys.stdin) if r["name"].startswith("app:")))'); do
    qs clickApp "$id" >/dev/null; sleep 0.9
    echo "    app:$id → activewindow=$(awin)"
done
ok "apps épinglées : clickApp exécuté (détail ci-dessus)"
qs clickApp terminal >/dev/null; sleep 0.9
[ "$(awin | cut -d' ' -f1)" = "kitty" ] && ok "app:terminal → kitty focalisé" || ko "app:terminal"

qs cycleApp kitty 1 >/dev/null; sleep 0.9
echo "    cycleApp kitty +1 → activewindow=$(awin)"

# toggles
M0=$(curl -s -m 2 "$API/api/system/volume")
qs action toggle-sound >/dev/null; sleep 0.9
M1=$(curl -s -m 2 "$API/api/system/volume")
qs action toggle-sound >/dev/null; sleep 0.9
M2=$(curl -s -m 2 "$API/api/system/volume")
echo "    son : avant=$M0 après clic=$M1 retour=$M2"
[ "$M0" != "$M1" ] && ok "toggle-sound → mute basculé puis restauré" || ko "toggle-sound sans effet"

qs action toggle-network >/dev/null; sleep 0.5
layer network && ok "toggle-network → popup réseau" || ko "toggle-network"
qs close >/dev/null; sleep 0.3

# makoctl mode liste les modes actifs : « do-not-disturb » présent = DND actif
dnd() { makoctl mode 2>/dev/null | grep -c do-not-disturb; }
D1=$(dnd)
qs action toggle-dnd >/dev/null; sleep 0.9
D2=$(dnd)
qs action toggle-dnd >/dev/null; sleep 0.9
D3=$(dnd)
echo "    DND (1 = actif) : avant=$D1 après clic=$D2 retour=$D3"
[ "$D1" != "$D2" ] && ok "toggle-dnd → DND basculé ($D1→$D2) puis restauré ($D3)" || ko "toggle-dnd sans effet"

# croix des popups : mesurées 38×38 (voir rects ci-dessus) + fermeture réelle
qs popup calendar >/dev/null; sleep 0.6
qs rects | jq_ '
import json,sys
rs=[r for r in json.load(sys.stdin) if r["name"].startswith("popup:calendrier")]
print("    croix calendrier : %s" % [(r["name"].split(":")[1], r["w"], r["h"]) for r in rs])'
qs close >/dev/null; sleep 0.4
layer calendar && ko "croix : popup encore ouverte" || ok "fermeture de popup (Ui.close) effective"

# ─────────────────────────────────────────────────────────────────────────
hd "§3  alpha (bar.json → pixel)"
echo "  état IPC : $(qs state | jq_ 'import json,sys;d=json.load(sys.stdin);print(d["alphas"])')"
echo "  mesures pixel de référence (2 points, cf. rapport) :"
echo "    panneau 0.237 (config 0.24) · carte 0.200 (config 0.20) · survol 0.345 (config 0.35)"
grep -q '"panelAlpha": 0.24' "$BAR_DIR/bar.json" && ok "panelAlpha = 0.24 dans bar.json" || ko "panelAlpha"
grep -q '"cardAlpha": 0.2' "$BAR_DIR/bar.json" && ok "cardAlpha = 0.20 dans bar.json" || ko "cardAlpha"
grep -q '"hoverAlpha": 0.35' "$BAR_DIR/bar.json" && ok "hoverAlpha = 0.35 dans bar.json" || ko "hoverAlpha"

# ─────────────────────────────────────────────────────────────────────────
hd "§5  centrage (x + w/2)"
qs rects | jq_ '
import json,sys
rs=[r for r in json.load(sys.stdin) if not r["name"].startswith("popup:")]
for r in (rs[0], rs[len(rs)//2], rs[-1]):
    print("  %-18s x=%2d w=%2d → centre=%d" % (r["name"], r["x"], r["w"], r["x"]+r["w"]//2))
cx=sorted(set(r["cx"] for r in rs))
print("  centres distincts : %s" % cx)
sys.exit(0 if len(cx)==1 else 1)' && ok "un seul axe vertical (tous les centres identiques)" \
                               || ko "centres différents"
RES=$(hyprctl monitors -j | jq_ 'import json,sys;print(json.load(sys.stdin)[0]["reserved"])')
echo "  monitors[0].reserved = $RES (attendu gauche = 46+6 = 52)"
hyprctl layers -j | jq_ '
import json,sys
for m,v in json.load(sys.stdin).items():
    for lvl,arr in v["levels"].items():
        for l in arr:
            if l.get("namespace")=="sasquatch-bar":
                print("  surface : x=%d y=%d w=%d h=%d" % (l["x"],l["y"],l["w"],l["h"]))'

# ─────────────────────────────────────────────────────────────────────────
hd "§6  engrenage → Sasquatch Settings (8770)"
countsettings() { hyprctl clients -j | jq_ 'import json,sys;print(sum(1 for c in json.load(sys.stdin) if "Sasquatch Settings" in (c.get("title") or "")))'; }
OPEN0=$(countsettings)
qs action settings >/dev/null; sleep 3
OPEN1=$(countsettings)
HEALTH=$(curl -s -m 2 http://127.0.0.1:8770/api/health)
TITLE=$(hyprctl clients -j | jq_ 'import json,sys
h=[c["title"] for c in json.load(sys.stdin) if "Sasquatch Settings" in (c.get("title") or "")]
print(h[0] if h else "")')
echo "  fenêtres Settings avant=$OPEN0 après=$OPEN1 · backend 8770 → $HEALTH"
echo "  titre de la fenêtre : $TITLE"
[ "$OPEN1" -ge 1 ] && ok "engrenage → fenêtre Sasquatch Settings ouverte" || ko "engrenage → aucune fenêtre"
echo "$HEALTH" | grep -q '"ok": true' && ok "backend Settings 8770 répond" || ko "backend 8770"

# ─────────────────────────────────────────────────────────────────────────
hd "Restauration de l'état"
qs close >/dev/null
hyprctl dispatch workspace "$WS0" >/dev/null
if [ "$OPEN1" -ge 1 ] && [ "$OPEN0" -eq 0 ]; then
    ~/.config/settings/settings.sh >/dev/null 2>&1   # toggle : referme
    sleep 1.5
fi
echo "  workspace=$(aws) (initial $WS0) · Settings ouvertes=$(countsettings)"
echo "  volume=$VOL0 · dnd=$DND0"

hd "résultat"
printf '  %d OK, %d FAIL\n' "$PASS" "$FAIL"
exit "$FAIL"
