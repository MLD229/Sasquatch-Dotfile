#!/bin/bash
# obsidian-toggle.sh — toggle Obsidian (Super+H).
#
# Le wrapper /usr/bin/obsidian (paquet extra) fait `exec electron43
# /usr/lib/obsidian/app.asar` → le process vivant s'appelle electron43,
# PAS obsidian. Test fiable : matcher l'argument app.asar via pgrep -f.
# Le crochet [o] est un anti self-match obligatoire (le pattern matcherait
# sinon la cmdline du shell qui le contient). "obsidian/app.asar" est
# unique à Obsidian.

if pgrep -f "[o]bsidian/app.asar" >/dev/null; then
    # Toggle OFF : fermer Obsidian
    pkill -f "[o]bsidian/app.asar"
    exit 0
fi

# Toggle ON : lancer (détaché du shell Hyprland)
if ! command -v obsidian >/dev/null 2>&1; then
    notify-send "Sasquatch" "Obsidian introuvable (Super+H)" -u critical 2>/dev/null || true
    exit 1
fi
obsidian &
notify-send "Sasquatch" "Obsidian ouvert" 2>/dev/null || true
exit 0
