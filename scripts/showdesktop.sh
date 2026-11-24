#!/usr/bin/env bash
# showdesktop.sh — « libérer le workspace » : cache toutes les fenêtres (toggle).
#
# Premier appel : chaque fenêtre mappée est déplacée SILENCIEUSEMENT vers un
# espace spécial (`special:desk`) ; le workspace courant devient donc vide et
# l'on voit le fond d'écran + les widgets. Le plan de retour (adresse →
# workspace d'origine) est écrit dans $XDG_RUNTIME_DIR.
#
# Second appel : chaque fenêtre revient exactement dans son workspace d'origine.
#
# Ne touche pas aux fenêtres déjà dans un espace spécial, ni aux scratchpads :
# elles ne sont pas comptées et donc pas déplacées.
#
# Appelé par : Super+X et le coin supérieur gauche (scripts/hotcorner.sh).
set -uo pipefail

STATE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sasquatch-showdesktop.json"
SPECIAL="desk"

clients_json() { hyprctl clients -j 2>/dev/null; }

if [ -f "$STATE" ]; then
    # ── Restauration ──────────────────────────────────────────────────────
    python3 - "$STATE" <<'PY'
import json, subprocess, sys, os
state = json.load(open(sys.argv[1], encoding="utf-8"))
back, missing = 0, 0
for win in state.get("windows", []):
    addr, ws = win.get("address"), win.get("workspace")
    if not addr or ws is None:
        continue
    # La fenêtre peut avoir été fermée entre-temps : le dispatcher répond
    # alors une erreur, qu'on ignore sans bruit.
    # 0.57 : plus de `hyprctl dispatch movetoworkspacesilent` — dispatcher Lua
    # window.move + sélecteur address:. `follow = false` = l'écran ne suit PAS
    # la fenêtre (c'est le sens de « silent » ; l'option `silent` n'existe plus
    # en 0.57, elle serait ignorée en silence).
    r = subprocess.run(["hyprctl", "eval",
                        'hl.dispatch(hl.dsp.window.move({window = "address:%s", '
                        'workspace = %d, follow = false}))' % (addr, int(ws))],
                       capture_output=True, text=True, timeout=5)
    if "ok" in r.stdout.lower():
        back += 1
    else:
        missing += 1
print(f"showdesktop: {back} fenêtre(s) restaurée(s), {missing} disparue(s)")
PY
    rm -f "$STATE"
    exit 0
fi

# ── Masquage ──────────────────────────────────────────────────────────────
python3 - "$STATE" "$SPECIAL" <<'PY'
import json, subprocess, sys

state_path, special = sys.argv[1], sys.argv[2]
out = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=5)
try:
    clients = json.loads(out.stdout)
except Exception:
    print("showdesktop: hyprctl illisible")
    sys.exit(1)

plan, moved = [], 0
for c in clients:
    if not c.get("mapped", True):
        continue
    ws = c.get("workspace", {}) or {}
    if ws.get("id", 0) < 0:          # déjà dans un espace spécial
        continue
    addr = c.get("address")
    if not addr:
        continue
    # follow = false : on cache les fenêtres sans que l'écran ne bascule sur
    # special:desk (sinon le « bureau vide » ne serait jamais affiché).
    r = subprocess.run(["hyprctl", "eval",
                        'hl.dispatch(hl.dsp.window.move({window = "address:%s", '
                        'workspace = "special:%s", follow = false}))' % (addr, special)],
                       capture_output=True, text=True, timeout=5)
    if "ok" in r.stdout.lower():
        plan.append({"address": addr, "workspace": ws.get("id", 1)})
        moved += 1

if not plan:
    print("showdesktop: aucune fenêtre à cacher")
    sys.exit(0)

json.dump({"windows": plan}, open(state_path, "w", encoding="utf-8"))
print(f"showdesktop: {moved} fenêtre(s) cachée(s) — rappelle pour restaurer")
PY
