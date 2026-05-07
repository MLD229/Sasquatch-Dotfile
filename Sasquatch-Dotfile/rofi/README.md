# 🎨 Sasquatch · Rofi Theme

Style **Blur · Arrondi · Noir/Gris Transparent** avec icônes auto et noms scriptés.

```
rofi/
├── themes/
│   ├── sasquatch.rasi   ← thème principal
│   └── colors.rasi      ← palette de couleurs
└── scripts/
    ├── launcher.sh      ← lance rofi (drun + icônes)
    ├── icon-gen.sh      ← génère icônes auto depuis .desktop
    └── powermenu.sh     ← menu alimentation
```

---

## ⚡ Prérequis

| Paquet | Rôle |
|--------|------|
| `rofi` ≥ 1.7 | le lanceur |
| `picom` (glx backend) | blur réel via `transparency = "real"` |
| `Papirus-Dark` | thème d'icônes (changeable dans launcher.sh) |
| `JetBrainsMono Nerd Font` | police avec glyphs |

---

## 🚀 Installation

```bash
# Rendre les scripts exécutables
chmod +x scripts/*.sh

# Symlink du thème dans la config rofi
mkdir -p ~/.config/rofi
ln -sf "$(pwd)/themes/sasquatch.rasi" ~/.config/rofi/config.rasi
```

---

## 🔧 Utilisation

```bash
# Lanceur d'applications (icônes auto)
./scripts/launcher.sh

# Menu alimentation
./scripts/powermenu.sh

# Générateur d'icônes (pipe vers dmenu)
./scripts/icon-gen.sh | rofi -dmenu -show-icons -theme themes/sasquatch.rasi
```

---

## 🎨 Personnalisation

Edite `themes/colors.rasi` pour changer les couleurs.  
Les valeurs `rgba(r, g, b, %)` permettent de jouer sur la transparence.

```rasi
bg-window:  rgba(10, 10, 12, 85%);   /* opacité de la fenêtre */
bg-selected: rgba(80, 80, 100, 55%); /* surbrillance sélection */
accent:      rgba(130, 140, 200, 100%); /* couleur d'accent */
```

> **Note blur** : la transparence réelle (`transparency = "real"`) nécessite  
> un compositor actif avec blur (ex: picom `--blur-method dual_kawase`).

---

## 🔑 Keybind suggéré (hyprland / sway / i3)

```
# Hyprland
bind = SUPER, SPACE, exec, ~/.config/rofi/scripts/launcher.sh
bind = SUPER, ESCAPE, exec, ~/.config/rofi/scripts/powermenu.sh
```
