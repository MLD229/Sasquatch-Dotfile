---
tags: [sasquatch-files, composants]
type: composant
updated: 2026-08-19
---

# waybar

## Rattachements

**Fichiers du composant** :
- [[20-Composants/waybar/config]] — modules de la barre (layout, modules custom, tooltips japonais)
- [[20-Composants/waybar/style-css]] — thème + bloc SASQUATCH-PALETTE
- [[20-Composants/waybar/ui-ja-json]] — dictionnaire des libellés japonais
- [[20-Composants/waybar/waybar-service]] — supervision systemd user (Restart=on-failure, reload SIGUSR2)
- [[20-Composants/waybar/scripts/clock-ja-py]] — horloge hiragana (module `custom/clock-ja`)
- [[20-Composants/waybar/scripts/fastview-py]] — aperçu des workspaces au survol (module `custom/fastview`)
- [[20-Composants/waybar/scripts/wallclock-ja-py]] — horloge flottante dans le wallpaper

**Interactions** :
- [[20-Composants/scripts/theme-apply-sh]] — lance/recharge la barre au login et à chaque thème (SIGUSR2)
- [[20-Composants/scripts/theme-apply-py]] — génère le bloc SASQUATCH-PALETTE de style.css
- [[20-Composants/scripts/waybar-toggle-sh]] — Super+J : SIGUSR1 toggle visible/invisible
- [[20-Composants/hypr/keybinds-conf]] — bind Super+J
- [[20-Composants/hypr/conf.d/rules-conf]] — `defaultName` des workspaces (いち…じゅう) affichés par le module workspaces
- [[20-Composants/hypr/scripts/autostart-sh]] — lance wallclock-ja.py au login

**Référencé par** :
- [[10-Fondations/install]] — install.sh place les symlinks (~/.config/waybar, waybar.service)
- [[10-Fondations/theme-dynamique]] — la palette de la barre suit le wallpaper
