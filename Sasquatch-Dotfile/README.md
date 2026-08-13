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
├── cc/                          ← Control Center (SUPER+G, Quickshell)
│   ├── cc.sh                    ← launcher toggle (serveur backend + fenêtre QS)
│   ├── server.py                ← backend stdlib : métriques, MPD, cava, Shazam
│   ├── main.qml                 ← UI single-file "Sasquatch CC" (dashboard complet)
│   ├── ocr.sh                   ← OCR écran → traduction / recherche d'images
│   ├── cava.conf                ← égaliseur (fifo raw, sortie audio)
│   └── qml/
│       └── Palette.qml          ← couleurs (retinté par theme-apply, non lu par main.qml)
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
  dans 7 fichiers (waybar, kitty, hypr/general.conf, hyprlock, mako, rofi, cc/qml/Palette.qml).
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

---

## 🎛️ Control Center (SUPER+G)

Dashboard **Quickshell** (`cc/`) — UI native Qt Quick + backend Python stdlib :

- **Performance** temps réel : CPU (jauge + cœurs), RAM, GPU/VRAM, températures,
  réseau, uptime, refresh rate — graphiques 1 s.
- **Now Playing** (MPD) : pochette (`albumart`), titre/artiste/album, timeline
  cliquable (seek), contrôles ⏮ ▶ ⏭, volume, et **égaliseur animé synchronisé**
  sur la sortie audio réelle (cava → fifo → `/api/viz`).
- **Music Finder** 🎤 : écoute le micro 6 s (arecord) → reconnaissance Shazam
  (`songrec`) → titre/artiste/album/pochette + liens Shazam & YouTube.
- **Screenshot** : zone / plein écran / fenêtre (grim + slurp), copié + sauvegardé.
- Fermeture : `Escape`, bouton ✕, ou re-appui `SUPER+G` (toggle).

Architecture : `cc.sh` lance le backend `server.py` (port 8765, localhost), puis la
fenêtre `cc/qml/main.qml` (titre `Sasquatch CC` → windowrule float + border 0 +
`move 0 0` pour couvrir tout l'écran malgré la zone réservée de waybar). À la
fermeture, le serveur est arrêté automatiquement. La palette Catppuccin est en
dur dans main.qml (le thème dynamique via `cc/qml/Palette.qml` n'est pas suivi
pour l'instant ; le fichier est gardé car theme-apply.py continue de l'écrire).
Les captures masquent le CC pendant grim/slurp puis le restaurent.

Dépendances : `quickshell`, `cava`, `alsa-utils`, `songrec` (inclus dans install.sh).
