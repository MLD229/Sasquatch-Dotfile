#!/bin/bash
# apply-wallpaper.sh — applique un wallpaper SANS waypaper (binaire disparu).
#
# Usage :
#   apply-wallpaper.sh [chemin]   → applique le chemin donné (backend CC,
#                                   /api/wallpaper/apply → wallpaper.py).
#   apply-wallpaper.sh            → restaure le wallpaper de config.ini
#                                   (login : wallpaper.sh, ex-`waypaper --restore`).
#
# Chaîne (reproduit waypaper --restore sans la dépendance) :
#   1. tue les hyprpaper orphelins d'une session passée (bug 2026-08-14 :
#      un hyprpaper déjà vivant n'était pas remplacé → IPC mort → fond noir,
#      alors que la palette suivait quand même) ;
#   2. relance hyprpaper dans la session courante ;
#   3. wallpaper sur TOUS les monitors (preload silencieux pour vieilles
#      versions ; v0.8 n'en a pas besoin) ;
#   4. theme-apply.sh <wallpaper> (ex-post_command de waypaper : palette
#      waybar/kitty/hyprlock/…).
#
# Note service systemd : sasquatch-cc tourne SANS WAYLAND_DISPLAY ni
# HYPRLAND_INSTANCE_SIGNATURE (import-environment capricieux) → on les
# détecte ici, on ne dépend jamais de l'env hérité.
set -u

# ── Environnement (auto-détection) ────────────────────────────────
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | head -1 | xargs -r basename)
    export WAYLAND_DISPLAY
fi
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$XDG_RUNTIME_DIR"/hypr/ 2>/dev/null | head -1)
    export HYPRLAND_INSTANCE_SIGNATURE
fi
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    echo "apply-wallpaper: instance hyprland introuvable" >&2
    exit 1
fi

# ── Déterminer le wallpaper ────────────────────────────────────────
CONFIG_INI="$HOME/.config/waypaper/config.ini"
WALL="${1:-}"
if [ -z "$WALL" ] || [ ! -f "$WALL" ]; then
    # Restaure depuis config.ini (strippe préfixe moniteur façon waypaper :
    # "eDP-1:~/..." → "~/...").
    RAW=$(grep -m1 '^wallpaper' "$CONFIG_INI" 2>/dev/null | sed 's/^[^=]*= *//; s/^[^:~]*://')
    case "$RAW" in
        "~"*) WALL="$HOME${RAW#\~}" ;;
        *)    WALL="$RAW" ;;
    esac
fi
if [ -z "$WALL" ] || [ ! -f "$WALL" ]; then
    echo "apply-wallpaper: wallpaper introuvable: ${WALL:-vide}" >&2
    exit 1
fi

# ── 1. Tuer les hyprpaper orphelins + attendre la mort réelle ──────
pkill -x hyprpaper 2>/dev/null
for _ in $(seq 1 20); do
    pgrep -x hyprpaper >/dev/null 2>&1 || break
    sleep 0.1
done

# ── 2. Relancer hyprpaper + attendre le socket FRAIS ───────────────
SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.hyprpaper.sock"
# pkill tue le process mais PAS le fichier socket UNIX : le socket stale de
# l'ancien hyprpaper fait croire à la boucle -S que tout est prêt → hyprctl
# part dans le vide → fond noir (symptôme intermittent, surtout applies rapides).
rm -f "$SOCK"
hyprpaper >/dev/null 2>&1 &
HP_PID=$!
for _ in $(seq 1 30); do
    [ -S "$SOCK" ] && break
    kill -0 "$HP_PID" 2>/dev/null || break
    sleep 0.1
done
# Le socket peut exister avant que hyprpaper ait fini bind+listen : petit délai.
sleep 0.3

# ── 3. wallpaper sur tous les monitors ────────────────────────────
# v0.8 : PAS de preload nécessaire (refusé : "invalid hyprpaper request") ;
# le wallpaper accepte le path direct, espaces compris — passé en UN SEUL
# argument shell, SANS guillemets (hyprpaper les garderait littéraux).
# Le preload est conservé en tentative silencieuse pour les vieilles
# versions qui l'exigent (v0.7) ; son échec est ignoré.
hyprctl hyprpaper "preload $WALL" >/dev/null 2>&1
MONITORS=$(hyprctl monitors -j 2>/dev/null | python3 -c "import json,sys; print(' '.join(m['name'] for m in json.load(sys.stdin)))" 2>/dev/null)
# Retry ×3 : au tout début de vie de hyprpaper, la 1re commande peut partir
# avant que l'IPC soit prêt (surtout applies en rafale) ; les suivantes
# atterrissent.
if [ -n "$MONITORS" ]; then
    for MON in $MONITORS; do
        for _ in 1 2 3; do
            hyprctl hyprpaper "wallpaper $MON,$WALL" >/dev/null 2>&1
            sleep 0.3
        done
    done
else
    # Aucun monitor listé (rare) : on tente quand même le set générique.
    for _ in 1 2 3; do
        hyprctl hyprpaper "wallpaper ,$WALL" >/dev/null 2>&1
        sleep 0.3
    done
fi

# ── 4. Palette (ex-post_command waypaper) — fire & forget, le flock de
#      theme-apply.sh sérialise avec le login/les switchs rapides ────
"$HOME/.config/scripts/theme-apply.sh" "$WALL" >/dev/null 2>&1 &

exit 0
