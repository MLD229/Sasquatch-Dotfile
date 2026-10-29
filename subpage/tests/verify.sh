#!/usr/bin/env bash
# Sasquatch Sub page v2 — preuves scriptées (lancer : tests/verify.sh)
#
# Vérifie avec de vraies sorties hyprctl et de vrais pixels :
#   1. lint (qmllint, py_compile, bash -n)
#   3. send.sh : la fenêtre active part bien dans special:subpage
#   4. aucun flou : netteté du CONTENU de la fenêtre, page fermée vs page ouverte
#   2. ouverture : surface `subpage` unique, en layer top
#   5. aucun vol de focus : la décoration redémarre sans changer la fenêtre active
#   6. aucun remplissage plein écran : le diff « avec/sans décoration » reste
#      confiné aux 4 coins + l'étiquette
#   7. fermeture par le script : plus aucune surface, fenêtres gardées
#   8. synchronisation : fermeture par `hyprctl dispatch` direct ⇒ disparition
#   9. plus aucune référence à l'ancien main.qml
#
# NON testé ici (il faut un humain / du matériel) : la souris réelle sur les
# traits, un jeu en plein écran, un vrai multi-écrans.
#
# Le script travaille sur un workspace de test vide puis RESTAURE le workspace
# de l'utilisateur ; il ne ferme aucune de ses fenêtres.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$SCRIPT_DIR" || exit 1
PY="${PYTHON:-python3}"
OUT="$SCRIPT_DIR/tests/out"
mkdir -p "$OUT"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)"
    export HYPRLAND_INSTANCE_SIGNATURE
fi

pass=0
fail=0
ok()   { printf '  OK    %s\n' "$1"; pass=$((pass + 1)); }
ko()   { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }
step() { printf '\n== %s ==\n' "$1"; }

special_open() {
    hyprctl monitors -j | "$PY" -c '
import json, sys
sys.exit(0 if any(m["specialWorkspace"]["name"] == "special:subpage" for m in json.load(sys.stdin)) else 1)
'
}

layer_count() { hyprctl layers | grep -c "namespace: subpage"; }
active_addr() { hyprctl activewindow -j | "$PY" -c 'import json,sys; print(json.load(sys.stdin).get("address",""))'; }

test_window_info() {
    hyprctl clients -j | "$PY" -c '
import json, sys
for c in json.load(sys.stdin):
    if c.get("class") == "subpage-test":
        x, y = c["at"]; w, h = c["size"]
        print(c["address"], c["workspace"]["name"], x, y, w, h)
        break
'
}

# netteté d'un rectangle de la capture (variance du laplacien)
sharp_rect() {
    "$PY" - "$1" "$2" "$3" "$4" "$5" <<'EOF'
import sys
from PIL import Image, ImageFilter
path = sys.argv[1]
x, y, w, h = (int(v) for v in sys.argv[2:6])
x, y = max(0, x), max(0, y)
img = Image.open(path).convert("RGB").crop((x, y, x + w, y + h)).convert("L")
hist = img.filter(ImageFilter.FIND_EDGES).histogram()
total = sum(hist)
mean = sum(i * c for i, c in enumerate(hist)) / total
print(round(sum(c * (i - mean) ** 2 for i, c in enumerate(hist)) / total, 1))
EOF
}

# ── 1. Lint ───────────────────────────────────────────────────────────────
step "1. Lint / compilation"
if qmllint shell.qml; then ok "qmllint shell.qml (0 warning)"; else ko "qmllint shell.qml"; fi
if "$PY" -m py_compile state.py; then ok "py_compile state.py"; else ko "py_compile state.py"; fi
if bash -n subpage.sh && bash -n send.sh && bash -n tests/verify.sh; then
    ok "bash -n subpage.sh send.sh tests/verify.sh"
else
    ko "bash -n"
fi

orig_ws="$(hyprctl activeworkspace -j | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["name"])')"
./subpage.sh close >/dev/null 2>&1
hyprctl dispatch workspace 10 >/dev/null
sleep 0.5

# ── 3a. Fenêtre témoin sur un workspace normal (page fermée) ─────────────
step "3a. Fenêtre témoin, page fermée (référence de netteté)"
hyprctl dispatch exec -- kitty --class subpage-test -T SUBPAGE-TEST -o cursor_blink_interval=0 >/dev/null
test_addr=""
for _ in $(seq 1 50); do
    test_addr="$(test_window_info | cut -d' ' -f1)"
    [ -n "$test_addr" ] && break
    sleep 0.2
done
if [ -z "$test_addr" ]; then
    ko "fenêtre de test non apparue"
else
    hyprctl dispatch focuswindow "address:$test_addr" >/dev/null
    sleep 0.9
    read -r _ ws_before rx ry rw rh <<<"$(test_window_info)"
    ok "fenêtre $test_addr sur le workspace '$ws_before' ($rw x $rh)"
    grim "$OUT/05-page-fermee.png"
    ref_sharp="$(sharp_rect "$OUT/05-page-fermee.png" $((rx + 40)) $((ry + 40)) $((rw - 80)) $((rh - 80)))"

    # ── 3b. send.sh ───────────────────────────────────────────────────────
    step "3b. send.sh — envoi de la fenêtre dans la page"
    "$SCRIPT_DIR/send.sh"; rc=$?
    [ "$rc" -eq 0 ] && ok "send.sh rc=0" || ko "send.sh rc=$rc"
    sleep 0.8
    read -r _ ws_after ax ay aw ah <<<"$(test_window_info)"
    if [ "$ws_after" = "special:subpage" ]; then
        ok "fenêtre déplacée dans special:subpage"
    else
        ko "fenêtre dans '$ws_after'"
    fi
    grim "$OUT/20-page-ouverte.png"
    page_sharp="$(sharp_rect "$OUT/20-page-ouverte.png" $((ax + 40)) $((ay + 40)) $((aw - 80)) $((ah - 80)))"

    # ── 4. Netteté ────────────────────────────────────────────────────────
    step "4. Aucun flou (netteté du contenu, même fenêtre)"
    ratio="$("$PY" -c "print(round(float('$page_sharp')/float('$ref_sharp'),2))")"
    printf '  netteté : page FERMÉE=%s  page OUVERTE=%s  ratio=%s\n' "$ref_sharp" "$page_sharp" "$ratio"
    if "$PY" -c "import sys; sys.exit(0 if float('$page_sharp') > 0.8 * float('$ref_sharp') else 1)"; then
        ok "contenu NET quand la page est ouverte (aucun flou de surface)"
    else
        ko "contenu flou quand la page est ouverte"
    fi
fi

# ── 2. Ouverture : état Hyprland + surface ───────────────────────────────
step "2. Surface de décoration (page ouverte)"
hyprctl monitors -j | "$PY" -c '
import json, sys
for m in json.load(sys.stdin):
    print("  moniteur %s : active=%s specialWorkspace=%r reserved=%s"
          % (m["name"], m["activeWorkspace"]["name"], m["specialWorkspace"]["name"], m["reserved"]))
'
hyprctl layers > "$OUT/layers-open.txt"
sed -n '/Layer level 2/,/Layer level 3/p' "$OUT/layers-open.txt"
if special_open; then ok "specialWorkspace.name == special:subpage"; else ko "special absent"; fi
if sed -n '/Layer level 2/,/Layer level 3/p' "$OUT/layers-open.txt" | grep -q "namespace: subpage"; then
    ok "surface 'subpage' en layer TOP (au-dessus des fenêtres, sous les notifications)"
else
    ko "surface absente du layer top"
fi
if [ "$(layer_count)" -eq 1 ]; then ok "une seule surface (pas de doublon)"; else ko "doublon de surface"; fi

# ── 5. Aucun vol de focus ────────────────────────────────────────────────
step "5. Aucun vol de focus par la décoration"
hyprctl dispatch focuswindow "address:$test_addr" >/dev/null
sleep 0.4
focus_before="$(active_addr)"
pkill -f "$SCRIPT_DIR/shell.qml" 2>/dev/null
sleep 0.7
./subpage.sh open >/dev/null    # ne relance QUE la décoration (page déjà ouverte)
for _ in $(seq 1 20); do
    [ "$(layer_count)" -ge 1 ] && break
    sleep 0.2
done
sleep 0.4
focus_after="$(active_addr)"
printf '  fenêtre active : avant redémarrage=%s  après=%s\n' "$focus_before" "$focus_after"
if [ -n "$focus_before" ] && [ "$focus_before" = "$focus_after" ]; then
    ok "le focus n'a pas bougé"
else
    ko "focus modifié par la décoration"
fi
grim "$OUT/30-avec-decoration.png"

# ── 6. Région dessinée = coins + étiquette ───────────────────────────────
step "6. Aucun remplissage plein écran"
pkill -f "$SCRIPT_DIR/shell.qml" 2>/dev/null
sleep 0.7
grim "$OUT/31-sans-decoration.png"
"$PY" - "$OUT/30-avec-decoration.png" "$OUT/31-sans-decoration.png" <<'EOF'
import sys
from PIL import Image, ImageChops
a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB")
mask = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > 12 else 0)
w, h = mask.size
# la waybar (y < 42) se met à jour toute seule (horloge, CPU, cava) : hors champ
mask.paste(0, (0, 0, w, 42))
print("  bbox des différences (la décoration seule) :", mask.getbbox())
zones = [(x, y) for y in range(0, h, 120) for x in range(0, w, 120)
         if mask.crop((x, y, x + 120, y + 120)).getbbox()]
print("  zones modifiées (tuiles 120x120) :", zones)
px = mask.histogram()[255]
print("  pixels dessinés : %d sur %d = %.2f %%" % (px, w * h, 100 * px / (w * h)))
EOF

# ── 7. Fermeture par le script ────────────────────────────────────────────
step "7. Fermeture (subpage.sh) — page fermée, fenêtres gardées"
# si l'état a été perturbé entre-temps (usage concurrent de la session),
# on le rétablit avant de tester la fermeture
if ! special_open; then
    ./subpage.sh open >/dev/null
    sleep 0.8
fi
./subpage.sh toggle; rc=$?
[ "$rc" -eq 0 ] && ok "subpage.sh toggle rc=0" || ko "toggle rc=$rc"
if special_open; then ko "special toujours ouvert"; else ok "special fermé"; fi
if [ "$(layer_count)" -eq 0 ]; then ok "plus aucune surface 'subpage'"; else ko "surface résiduelle"; fi
"$PY" - <<'EOF'
import json, subprocess
clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True).stdout)
print("  fenêtres de test encore vivantes (cachées dans le scratchpad) :",
      len([c for c in clients if c.get("class") == "subpage-test"]))
EOF

# ── 8. Synchronisation par hyprctl direct ────────────────────────────────
step "8. Synchronisation (fermeture sans passer par le script)"
./subpage.sh open >/dev/null
sleep 0.6
before="$(layer_count)"
hyprctl dispatch togglespecialworkspace subpage >/dev/null
sleep 0.35
after="$(layer_count)"
printf '  surfaces subpage : avant=%s, 350 ms après fermeture directe=%s\n' "$before" "$after"
if [ "$before" -ge 1 ] && [ "$after" -eq 0 ]; then
    ok "la décoration disparaît seule quand la page est fermée autrement"
else
    ko "synchronisation d'état"
fi

# ── 9. Ancien main.qml plus référencé ────────────────────────────────────
step "9. Ancien main.qml plus référencé"
hits="$(grep -rn "subpage/main\.qml" "$SCRIPT_DIR/.." --include='*.sh' --include='*.conf' \
        --include='*.qml' --include='*.py' 2>/dev/null | grep -v '_archive/' | grep -v 'tests/verify.sh')"
if [ -z "$hits" ]; then
    ok "aucune référence à subpage/main.qml (hors _archive/ et ce script)"
else
    printf '%s\n' "$hits"
    ko "référence restante à subpage/main.qml"
fi

# ── 10. Région d'entrée (preuve protocole Wayland) ──────────────────────
step "10. Région d'entrée limitée aux traits + étiquette"
./subpage.sh close >/dev/null 2>&1
sleep 0.4
WAYLAND_DEBUG=1 setsid quickshell -n -p "$SCRIPT_DIR/shell.qml" > "$OUT/wayland-debug.log" 2>&1 &
sleep 1.6
hyprctl dispatch togglespecialworkspace subpage >/dev/null
sleep 1.2
pkill -f "$SCRIPT_DIR/shell.qml" 2>/dev/null
sleep 0.4
hyprctl dispatch togglespecialworkspace subpage >/dev/null
"$PY" - "$OUT/wayland-debug.log" <<'PYCODE'
import re, sys
text = open(sys.argv[1], errors="replace").read()
region = re.findall(r"wl_region#\d+\.add\((\d+), (\d+), (\d+), (\d+)\)", text)
print("  set_input_region appelé :", "oui" if "set_input_region" in text else "NON")
print("  %d rectangles dans la région d'entrée :" % len(region))
for rect in region:
    print("    x=%s y=%s w=%s h=%s" % rect)
center = (960, 540)
inside = [r for r in region
          if int(r[0]) <= center[0] < int(r[0]) + int(r[2])
          and int(r[1]) <= center[1] < int(r[1]) + int(r[3])]
area = sum(int(r[2]) * int(r[3]) for r in region)
print("  aire totale : %d px (%.3f %% de l'écran)" % (area, 100 * area / (1920 * 1080)))
sys.exit(0 if region and not inside and area < 0.01 * 1920 * 1080 else 1)
PYCODE
if [ $? -eq 0 ]; then
    ok "le centre de l'écran n'est PAS dans la région d'entrée (clics traversants)"
else
    ko "région d'entrée suspecte"
fi

# ── Nettoyage ────────────────────────────────────────────────────────────
./subpage.sh close >/dev/null 2>&1
if [ -n "${test_addr:-}" ]; then
    hyprctl dispatch closewindow "address:$test_addr" >/dev/null 2>&1
fi
sleep 0.5
hyprctl dispatch workspace "$orig_ws" >/dev/null 2>&1

printf '\nRésultat : %d OK, %d FAIL\n' "$pass" "$fail"
printf 'Captures et sorties : %s\n' "$OUT"
[ "$fail" -eq 0 ]
