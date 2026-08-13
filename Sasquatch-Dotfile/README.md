# 🪶 Sasquatch-Dotfile

Dotfiles personnels pour un environnement **Hyprland** sur **Arch Linux**.

---

## ✨ Aperçu

| Composant        | Outil |
|------------------|-------|
| Compositeur      | Hyprland |
| Barre            | Waybar |
| Launcher         | Rofi |
| OSD volume/luminosité | Rofi |
| Notifications    | Mako |
| IME japonais     | Fcitx5 + Mozc |
| Terminal         | Kitty |
| Shell            | Fish |
| Prompt           | Starship |
| Fond d’écran     | Waypaper / Hyprpaper |
| Verrouillage     | Hyprlock |
| Inactivité       | Hypridle |
| Sysinfo          | Fastfetch |

---
📦 Dépendances
Paquets principaux

sudo pacman -S hyprland hyprlock hypridle hyprpaper \
xdg-desktop-portal-hyprland \
waybar mako rofi \
kitty fish starship fastfetch \
ttf-jetbrains-mono-nerd \
noto-fonts noto-fonts-emoji noto-fonts-cjk ttf-font-awesome \
brightnessctl playerctl \
pipewire wireplumber \
iwd bluez bluez-utils blueman \
polkit-gnome wl-clipboard \
grim slurp \
dolphin pavucontrol \
papirus-icon-theme kvantum \
eza bat \
nvidia-utils \
fcitx5 fcitx5-mozc fcitx5-configtool fcitx5-gtk fcitx5-qt \
libqalculate

---

## 🚀 Installation

```bash
git clone https://github.com/MLD229/Sasquatch-Dotfile.git
cd ~/Sasquatch-Dotfile/Sasquatch-Dotfile
bash install.sh
```

Redémarre ta session après l'installation.

---

## 📁 Structure


Sasquatch-Dotfile/
├── fastfetch/
│   └── config.jsonc
├── fcitx5/
│   ├── config                  ← bascule IME : Ctrl+Shift+1 (Control+exclam)
│   ├── profile                 ← clavier fr + mozc (japonais)
│   └── conf/
│       ├── mozc.conf
│       └── notifications.conf
├── fish/
│   ├── config.fish
│   └── fish_variables          ← gitignoré (spécifique machine)
├── hypr/
│   ├── conf.d/
│   │   ├── animations.conf
│   │   ├── blur.conf
│   │   ├── decoration.conf
│   │   ├── env.conf
│   │   ├── general.conf
│   │   ├── input.conf
│   │   ├── layout.conf
│   │   ├── misc.conf
│   │   ├── monitors.conf
│   │   └── rules.conf
│   ├── hypridle.conf
│   ├── hyprland.conf
│   ├── hyprlock.conf
│   ├── hyprpaper.conf           ← wallpaper géré par waypaper
│   ├── keybinds.conf            ← gestures trackpad, SUPER+Q kill, SUPER+V presse-papier
│   └── scripts/
│       ├── autostart.sh
│       └── scroll-workspace.sh
├── kitty/
│   └── kitty.conf
├── mako/
│   └── config
├── rofi/
│   ├── themes/
│   │   ├── sasquatch.rasi
│   │   ├── osd.rasi             ← OSD volume/luminosité
│   │   └── colors.rasi          ← palette (retintée par theme-apply)
│   └── scripts/
│       ├── icon-gen.sh
│       ├── launcher.sh
│       └── powermenu.sh
├── scripts/
│   ├── bluetooth.sh
│   ├── brightness.sh
│   ├── calc.sh                 ← SUPER+C : calculatrice (rofi + qalc)
│   ├── clipboard.sh             ← SUPER+V : presse-papier (cliphist)
│   ├── osd.sh                   ← OSD générique
│   ├── screenshot.sh
│   ├── theme-apply.py           ← extraction palette + patch des markers
│   ├── theme-apply.sh           ← orchestrateur (flock + hook waypaper)
│   ├── volume.sh
│   └── wifi.sh
├── set-wall.sh                  ← change wallpaper + applique le thème
├── themes/
│   ├── gtk/
│   │   ├── gtk-3.0/
│   │   │   ├── gtk.css
│   │   │   └── settings.ini
│   │   └── gtk-4.0/
│   │       ├── gtk.css
│   │       └── settings.ini
│   └── qt/
│       └── kdeglobals
├── waybar/
│   ├── config
│   └── style.css
├── starship.toml
├── .gitignore
├── install.sh
└── README.md
```

---

## 🎨 Thème dynamique

Le fond d'écran pilote les couleurs de **toute** l'interface : waybar, kitty,
bordures Hyprland, hyprlock, mako et rofi.

- `scripts/theme-apply.py` extrait la palette (PIL) : fond sombre teinté, texte
  clair, accent = couleur vive du fond, accent2 = complémentaire.
- `scripts/theme-apply.sh` orchestre + relance waybar (verrou `flock`).
- Les zones retintées sont délimitées par des markers `SASQUATCH-PALETTE-BEGIN/END`
  dans 6 fichiers (waybar, kitty, hypr/general.conf, hyprlock, mako, rofi).
- **Hook automatique** : dans `~/.config/waypaper/config.ini` (fichier runtime,
  non versionné — à configurer après install) :
  `post_command = ~/.config/scripts/theme-apply.sh $wallpaper`
- Alternative manuelle : `./set-wall.sh <image>` change le wallpaper ET applique le thème.

Dépendance : `python-pillow` (inclus dans install.sh).

---

## 🇯🇵 IME japonais (fcitx5 + Mozc)

L'IME est intégré au dotfile (dossier `fcitx5/`, symlinké par install.sh) :

- **Bascule clavier normal ↔ japonais** : `Ctrl+Shift+1` (la touche `!` — `Control+exclam` dans fcitx5).
- Une fois l'IME actif, `Shift` bascule romaji/hiragana (comportement Mozc), `Escape` annule la pré-édition.
- Configuration complète : `fcitx5-configtool` (paquet inclus).

## 🧮 Calculatrice (SUPER+C)

`scripts/calc.sh` — calculatrice rofi basée sur `qalc` (libqalculate) :

1. `SUPER+C` → tape une expression (ex. `12*7+3`, `sqrt(144)`, `2^10`).
2. `Enter` → le résultat s'affiche dans rofi.
3. `Enter` à nouveau → le résultat est copié dans le presse-papier.
4. `SUPER+C` quand elle est ouverte → la referme (toggle).

Les notifications volume/luminosité utilisent le replace-id de mako : maintenir
la touche (auto-répétition) met à jour UNE seule notification, sans empilement.
