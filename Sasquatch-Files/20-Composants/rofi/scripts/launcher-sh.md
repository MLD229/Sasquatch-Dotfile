---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-10-29
---

# rofi/scripts/launcher.sh

## Rattachements

**Composant parent** : [[20-Composants/rofi]]

**Lancé ici** :
- [[20-Composants/hypr/keybinds-conf]] — `bindr = SUPER, SUPER_L` (launcher rofi, toggle)

**Utilise** :
- [[20-Composants/rofi/themes/sasquatch-rasi]] — thème (variable THEME)
- plugin `rofi-calc` (`~/.local/lib/rofi/libcalc.so`) — mode `calc` natif
- [[20-Composants/kitty/kitty-conf]] — terminal par défaut (`-terminal "kitty"`)

## Options qui comptent

```bash
-plugin-path "$HOME/.local/lib/rofi"
-show combi -modi "combi,drun,run,window,calc"
-combi-modes "drun,calc" -combi-display-format "{text}"
-matching normal -sort -sorting-method fzf
-drun-match-fields "name,generic,exec,categories,keywords"
-no-drun-show-actions
```

- `-matching fuzzy` (ancien) faisait remonter Sober/Brave/Tor pour `chro` ;
  `normal` + `sorting-method fzf` ne laisse que Google Chrome.
- `-combi-display-format "{text}"` enlève le préfixe « drun » sur chaque ligne.
- `-no-drun-show-actions` supprime « New Window / New Incognito » (Brave).
- Sans `-plugin-path`, pas de mode `calc` (le plugin n'est pas dans `/usr/lib/rofi`).

## Calcul dans la liste

Le calcul n'est PAS un mode script : rofi 2.0 n'appelle un script qu'au
démarrage (`rofi-script(5)`), donc aucune recalcul possible pendant la frappe.
Le modi `calc` du plugin recalcule à chaque touche → « Result: 2+2 = 4 » en tête
de liste, Entrée copie (`-calc-command … wl-copy`).

⚠️ Dans le thème, `mainbox { children: [ inputbar, listview ] }` fait disparaître
cette ligne de résultat : ne pas remettre de `children:` explicite sur `mainbox`.
