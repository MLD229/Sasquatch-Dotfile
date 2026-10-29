#!/usr/bin/env bash
# capture.sh — preuve visuelle de 愛子 en 3 images + preuve du cycle de vie.
# À lancer DANS la session Hyprland déverrouillée (c'est le seul prérequis :
# hyprlock recouvre tous les outputs, donc grim ne verrait que la serrure).
#
#   bash ~/.config/aiko/tests/capture.sh
#
# Produit : /tmp/aiko-1-vide.png, /tmp/aiko-2-reponse.png, /tmp/aiko-3-ferme.png
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-/tmp}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
export HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE:-$(ls -t "$XDG_RUNTIME_DIR"/hypr 2>/dev/null | head -1)}"

geo() {   # "x,y wxh" de la surface layer aiko, ou rien
    hyprctl layers 2>/dev/null | awk '
        /namespace: aiko/ {
            for (i = 1; i <= NF; i++) if ($i == "xywh:") {
                printf "%s,%s %sx%s", $(i+1), $(i+2), $(i+3), $(i+4)
            }
        }'
}

if pgrep -f "hyprlock" >/dev/null 2>&1; then
    echo "✗ hyprlock tourne : déverrouille d'abord (la capture ne montrerait que la serrure)."
    exit 1
fi

echo "== 1. avant ouverture =="
echo "   llama-server aiko : $(pgrep -fc '[a]iko-ephemere' || true)"
echo "   VRAM              : $(nvidia-smi --query-gpu=memory.used --format=csv,noheader)"

# Panneau ouvert + message automatique (hook AIKO_DEMO)
# Note : pas d'apostrophe dans la valeur par défaut (dans ${VAR:-…} une quote
# non fermée casse tout le script).
AIKO_DEMO=1 AIKO_DEMO_TEXT="${AIKO_DEMO_TEXT:-Donne la commande pour lister les fenetres Hyprland en JSON, puis une ligne courte pour expliquer.}" \
    setsid "$DIR/aiko.sh" >/tmp/aiko-capture.log 2>&1 &

for _ in $(seq 1 50); do
    [ -n "$(geo)" ] && break
    sleep 0.1
done
G="$(geo)"
echo "== 2. panneau ouvert : layer à $G =="
sleep 0.8
grim -g "$G" "$OUT/aiko-1-vide.png" 2>/dev/null && echo "   → $OUT/aiko-1-vide.png"
echo "   (attente de la réponse…)"
for _ in $(seq 1 120); do
    st=$(curl -s -m1 http://127.0.0.1:8791/api/state | sed -n 's/.*"state": *"\([a-z]*\)".*/\1/p')
    toks=$(curl -s -m1 http://127.0.0.1:8791/api/state | sed -n 's/.*"tokens": *\([0-9]*\).*/\1/p')
    [ "${toks:-0}" -gt 5 ] && break
    sleep 0.3
done
sleep 1.2
grim -g "$G" "$OUT/aiko-2-reponse.png" 2>/dev/null && echo "   → $OUT/aiko-2-reponse.png"
echo "   llama-server : $(pgrep -fc '[a]iko-ephemere' || true) · VRAM : $(nvidia-smi --query-gpu=memory.used --format=csv,noheader)"

echo "== 3. fermeture =="
"$DIR/aiko.sh"
sleep 1.2
grim "$OUT/aiko-3-ferme.png" 2>/dev/null && echo "   → $OUT/aiko-3-ferme.png"
echo "   llama-server : $(pgrep -fc '[a]iko-ephemere' || true)"
echo "   backend      : $(pgrep -fc '[a]iko/server.py' || true)"
echo "   quickshell   : $(pgrep -fc '^quickshell -p .*aiko' || true)"
echo "   VRAM         : $(nvidia-smi --query-gpu=memory.used --format=csv,noheader)"
echo "   état sur disque : $(ls -A ~/.local/state/aiko 2>/dev/null | tr '\n' ' ' || true)(attendu : prefs.json seul, ou rien — jamais d'historique)"
