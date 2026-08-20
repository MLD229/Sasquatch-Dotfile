#!/bin/bash
# obsidian-toggle.sh — toggle Obsidian (Super+H)
#
# Le wrapper /usr/bin/obsidian (paquet extra) fait `exec electron43
# /usr/lib/obsidian/app.asar` → le process vivant s'appelle electron43,
# PAS obsidian. Test fiable : matcher l'argument app.asar via pgrep -f.
# Bracket [o] = anti self-match (cf. Lecons.md — pkill/pgrep self-match).
# Pattern "obsidian/app.asar" est unique à Obsidian (aucune autre app).

if pgrep -f "[o]bsidian/app.asar" >/dev/null; then
    # toggle OFF : fermer Obsidian
    pkill -f "[o]bsidian/app.asar"
    exit 0
fi

# toggle ON : lancer (détaché du shell Hyprland)
obsidian &
exit 0
