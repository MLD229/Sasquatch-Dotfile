#!/usr/bin/env bash
# install.sh — installe la slide bar Sasquatch depuis le dépôt.
#
#   1. ~/.config/cc/sidebar  →  SYMLINK vers ce dossier (source de vérité :
#      le dépôt). Une seule copie, donc aucune dérive possible.
#   2. service systemd user sasquatch-sidebar.service (backend permanent).
#   3. vérification de la palette + du bind clavier.
#
# Idempotent : on peut le relancer sans rien casser.
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.config/cc/sidebar"
UNIT_DIR="$HOME/.config/systemd/user"
PORT="${SASQUATCH_SIDEBAR_PORT:-8778}"

echo "== 1. miroir installé (symlink) =="
if [ -L "$DEST" ]; then
    echo "   symlink existant : $DEST → $(readlink "$DEST")"
    if [ "$(readlink -f "$DEST")" != "$SRC" ]; then
        echo "   ↻ reciblage vers $SRC"
        ln -sfn "$SRC" "$DEST"
    fi
elif [ -e "$DEST" ]; then
    echo "   ✗ $DEST existe et n'est PAS un symlink — je ne touche pas." >&2
    echo "     (déplace-le manuellement puis relance ce script)" >&2
    exit 1
else
    ln -sfn "$SRC" "$DEST"
    echo "   ✓ créé : $DEST → $SRC"
fi

echo "== 2. service systemd user =="
mkdir -p "$UNIT_DIR"
install -m 644 "$SRC/sasquatch-sidebar.service" "$UNIT_DIR/"
systemctl --user daemon-reload
systemctl --user enable --now sasquatch-sidebar.service >/dev/null 2>&1 \
    && echo "   ✓ sasquatch-sidebar.service actif" \
    || echo "   ✗ échec de démarrage — journalctl --user -u sasquatch-sidebar"

sleep 1
echo "== 3. backend =="
if curl -s -m 2 "http://127.0.0.1:$PORT/api/health"; then
    echo
    echo "   ✓ backend OK sur $PORT"
else
    echo "   ✗ backend muet sur $PORT" >&2
fi

echo "== 4. palette (exigence « fond adaptatif ») =="
if [ -f "$HOME/.config/cc/qml/Palette.qml" ]; then
    echo "   ✓ Palette.qml présent (régénéré par theme-apply.py)"
    curl -s -m 2 "http://127.0.0.1:$PORT/api/palette" | head -c 200; echo
else
    echo "   ✗ ~/.config/cc/qml/Palette.qml absent → lance apply-wallpaper.sh une fois" >&2
fi

echo "== 5. raccourci clavier =="
if grep -q "cc/sidebar/sidebar.sh" "$HOME/.config/hypr/keybinds.conf" 2>/dev/null; then
    echo "   ✓ bind présent dans keybinds.conf"
else
    echo "   ✗ bind absent — ajoute :"
    echo '     bind = $mod, U, exec, ~/.config/cc/sidebar/sidebar.sh'
fi

echo
echo "Lancement : ~/.config/cc/sidebar/sidebar.sh   (ou Super+U)"
echo "Prérequis optionnel : sudo pacman -S hyprsunset   (mode lumière bleue)"
