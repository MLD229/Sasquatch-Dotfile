#!/usr/bin/env bash
# run-all.sh — vérification complète de la slide bar (headless).
#
#   1. qmllint Qt6 (sémantique) sur tous les .qml
#   2. qmllint Qt5 (syntaxe) — outil historique du système
#   3. tests déterministes chrono / timer / alarme
#   4. tests HTTP du backend (todo, persistance, modes, palette)
#   5. chargement QML réel (seulement si un compositeur Wayland est fourni)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
cd "$ROOT"
rc=0

echo "═══ 1. qmllint Qt6 (sémantique) ═══"
QMLLINT6=/usr/lib/qt6/bin/qmllint
[ -x "$QMLLINT6" ] || QMLLINT6="$(command -v qmllint6 || command -v qmllint)"
for f in shell.qml qml/*.qml; do
    printf '%-24s ' "$f"
    if "$QMLLINT6" -I /usr/lib/qt6/qml "$f"; then echo "OK"; else echo "FAIL"; rc=1; fi
done

echo
echo "═══ 2. qmllint Qt5 (syntaxe pure) ═══"
# Le qmllint du système appartient à qt5-declarative : il ne connaît pas
# « pragma ComponentBehavior » (pragma Qt6). On lui donne donc une copie SANS
# cette ligne — ce qui prouve la validité syntaxique pure du fichier.
TMPD="$(mktemp -d)"
cp -r qml "$TMPD/"
for f in shell.qml qml/*.qml; do
    printf '%-24s ' "$f"
    grep -v '^pragma ComponentBehavior' "$f" > "$TMPD/$(basename "$f")"
    if qmllint "$TMPD/$(basename "$f")"; then echo "OK"; else echo "FAIL"; rc=1; fi
done
rm -rf "$TMPD"

echo
echo "═══ 3. moteur temps (chrono/timer/alarme) ═══"
python3 tests/test_clock.py || rc=1

echo
echo "═══ 4. backend HTTP ═══"
python3 tests/test_backend.py || rc=1

echo
echo "═══ 5. chargement QML réel ═══"
bash tests/qml-load-test.sh 10 || {
    sub=$?
    if [ "$sub" -eq 77 ]; then echo "     (sauté : pas de compositeur Wayland)"
    else rc=1; fi
}

echo
if [ "$rc" -eq 0 ]; then echo "RÉSULTAT GLOBAL : OK"; else echo "RÉSULTAT GLOBAL : ÉCHEC"; fi
exit "$rc"
