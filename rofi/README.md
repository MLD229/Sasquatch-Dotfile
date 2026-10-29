# 🎨 Sasquatch · Rofi

Launcher (apps + calculatrice), menu d'alimentation, thème **blur · arrondi · teal**.

```
rofi/
├── themes/
│   ├── sasquatch.rasi   ← thème principal (680px, fond quasi opaque)
│   ├── colors.rasi      ← palette générée (entre marqueurs SASQUATCH-PALETTE)
│   └── osd.rasi         ← OSD volume/luminosité
└── scripts/
    ├── launcher.sh      ← mode combi : apps (drun) + calcul (plugin rofi-calc)
    ├── icon-gen.sh      ← génère des icônes depuis les .desktop
    └── powermenu.sh     ← menu alimentation
```

---

## ⚡ Prérequis

| Paquet | Rôle |
|--------|------|
| `rofi` (2.0, fournit `rofi-wayland`) | le lanceur |
| `rofi-calc` | **plugin natif** du mode `calc` (résultat pendant la frappe) |
| `libqalculate` (`qalc`) | moteur de calcul, appelé par le plugin |
| `wl-clipboard` (`wl-copy`/`wl-paste`) | copie du résultat |
| `Papirus-Dark` | thème d'icônes |
| `JetBrainsMono Nerd Font` | police |

```bash
chmod +x scripts/*.sh
```

> `rofi/` est symlinké vers `~/.config/rofi` par `install.sh`. Le thème est passé
> explicitement avec `-theme` (pas de `config.rasi`).

### Plugin rofi-calc sans root

Le plugin est extrait du paquet officiel `extra/rofi-calc` dans
`~/.local/lib/rofi/libcalc.so` (pas besoin de `sudo pacman`), et chargé par
`-plugin-path "$HOME/.local/lib/rofi"` dans `launcher.sh` et `scripts/calc.sh`.

`qalc` vit dans `/usr/sbin`, absent du PATH d'une session Hyprland : sans
`export PATH="/usr/sbin:/sbin:$PATH"`, le plugin ne calcule **rien** (liste
muette).

---

## 🔧 Utilisation

```bash
# Launcher : apps + calcul, une seule fenêtre
./scripts/launcher.sh

# Menu alimentation
./scripts/powermenu.sh

# Générateur d'icônes
./scripts/icon-gen.sh | rofi -dmenu -show-icons -theme themes/sasquatch.rasi
```

### Launcher — recherche d'applications

```bash
rofi -plugin-path "$HOME/.local/lib/rofi" \
     -show combi \
     -modi "combi,drun,run,window,calc" \
     -combi-modes "drun,calc" -combi-display-format "{text}" \
     -matching normal -sort -sorting-method fzf \
     -drun-match-fields "name,generic,exec,categories,keywords" \
     -no-drun-show-actions \
     -theme themes/sasquatch.rasi -show-icons -icon-theme Papirus-Dark
```

- `-matching normal` + `-sorting-method fzf` : résultats pertinents (taper `chro`
  ne renvoie que Google Chrome, au lieu de Sober/Brave/Tor avec `fuzzy`).
- `-drun-match-fields` : on cherche aussi dans `exec`/`categories`/`keywords`.
- `-no-drun-show-actions` : supprime les entrées « New Window / New Incognito »
  déclarées par Brave.
- `-combi-display-format "{text}"` : sinon chaque ligne est préfixée du nom du mode.

### Calculatrice dans le launcher

C'est le **modi natif** du plugin (`-modi calc`), pas un script : le plugin
recalcule à chaque frappe. Taper `2+2` affiche `Result: 2+2 = 4` en tête de
liste, avant les apps. Entrée copie le résultat (`-calc-command … wl-copy`).

> ⚠️ **Un mode script ne peut PAS faire ça** : `rofi-script(5)` — « Rofi calls
> the executable without arguments on startup ». rofi 2.0 n'appelle le script
> qu'une fois, il ne lui transmet pas la requête tapée. Un `calc-modi.sh`
> n'affiche donc jamais de résultat en direct : il faut le plugin natif.

> ⚠️ **Ne jamais remettre `children: [ inputbar, listview ]` dans `mainbox`** :
> mesuré, cette liste explicite fait disparaître la ligne `Result: …` du plugin.
> L'ordre par défaut (inputbar, message, listview) l'affiche correctement.

---

## ⌨️ Super+U — calculatrice

`~/.config/scripts/calc.sh` (→ `scripts/calc.sh` du dotfile) ouvre
`rofi -show calc -modi calc` avec le plugin : résultat pendant la frappe,
Entrée copie. Super+U alors que la fenêtre est ouverte = toggle
(« pid vérifié avant `kill`).

---

## 🧹 Doublons / bruit dans la liste

- **Actions** (« New Window », « New Incognito ») : `-no-drun-show-actions`.
- Ne pas toucher aux entrées déjà en `NoDisplay=true` (Chrome, `krita_*`) :
  elles ne s'affichent pas.

---

## 🔑 Keybinds réels (hypr/keybinds.conf)

```ini
# Super seule (release) = launcher rofi (toggle)
bindr = SUPER, SUPER_L, exec, pkill rofi || ~/.config/rofi/scripts/launcher.sh
# Super+U = calculatrice (toggle)
bind  = $mod, U,       exec, ~/.config/scripts/calc.sh
# Super+C = sidebar Quickshell (déplacée depuis Super+U)
bind  = $mod, C,       exec, ~/.config/cc/sidebar/sidebar.sh
# Super+virgule = aide-mémoire des raccourcis
bind  = $mod, comma,   exec, pkill rofi || ~/.config/scripts/keybinds-reminder.sh
# Powermenu
bind  = $mod, Escape,  exec, ~/.config/rofi/scripts/powermenu.sh
```

> ⚠️ rofi 2.0 : `-no-custom` + stdin vide → sortie immédiate (menu vide).
> Les scripts qui pipent une liste (clipboard.sh, keybinds-reminder.sh)
> testent donc l'entrée AVANT d'appeler rofi.
