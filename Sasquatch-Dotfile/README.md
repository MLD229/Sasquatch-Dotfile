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

sudo pacman -S hyprland hyprlock hypridle hyprpaper waypaper \
xdg-desktop-portal-hyprland xdg-utils xdg-user-dirs \
waybar mako rofi \
python-gobject gtk-layer-shell \
kitty fish starship fastfetch \
ttf-jetbrains-mono-nerd \
noto-fonts noto-fonts-emoji noto-fonts-cjk \
brightnessctl playerctl \
pipewire pipewire-pulse wireplumber \
iwd bluez bluez-utils blueman \
polkit-gnome wl-clipboard cliphist \
grim slurp \
dolphin pavucontrol \
brave firefox \
papirus-icon-theme kvantum qt5ct \
catppuccin-gtk-theme-mocha bibata-cursor-theme \
python-pillow \
eza bat neovim \
nvidia-utils \
fcitx5 fcitx5-mozc fcitx5-configtool fcitx5-gtk fcitx5-qt \
libqalculate \
mpd cava alsa-utils songrec quickshell curl ffmpeg \
tesseract tesseract-data-fra

> Liste exhaustive : voir `requirements` (source de vérité, synchro avec install.sh).

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
│       ├── scroll-workspace.sh
│       └── wallpaper.sh          ← lanceur wallpaper (pkill hyprpaper + waypaper --restore)
├── kitty/
│   └── kitty.conf
├── mako/
│   └── config
├── mpd/
│   └── mpd.conf                 ← lecteur local + sortie FIFO (CC Capture → finder)
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
│   ├── style.css
│   └── scripts/
│       └── fastview.py          ← aperçu workspaces au survol (GTK layer-shell)
├── cc/                          ← Control Center (SUPER+G, Quickshell)
│   ├── cc.sh                    ← launcher toggle (serveur backend + fenêtre QS)
│   ├── server.py                ← point d'entrée HTTP (routes /api/*)
│   ├── config.py                ← constantes (port, MPD, traduction, albumart)
│   ├── metrics.py               ← métriques système + historique
│   ├── viz.py                   ← lecture fifo cava (égaliseur)
│   ├── mpd.py                   ← client MPD + notification changement de piste
│   ├── actions.py               ← capture, OCR/traduction, recherche image, finder
│   ├── palette.py               ← palette dynamique (lit qml/Palette.qml)
│   ├── translate.py             ← traduction (LibreTranslate → Google GTX)
│   ├── cava.py                  ← cycle de vie cava
│   ├── ocr.sh                   ← OCR écran (slurp + grim + tesseract → stdout)
│   ├── cava.conf                ← égaliseur (fifo raw, sortie audio)
│   └── qml/
│       ├── Palette.qml          ← couleurs (retinté par theme-apply, LU via /api/palette)
│       ├── Gauge.qml / IconButton.qml / Tile.qml / Sparkline.qml
│       └── (main.qml poll la palette toutes les 2 s → CC suit le thème)
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
- **Au login** : `hypr/scripts/wallpaper.sh` tue les éventuels hyprpaper
  orphelins (restés connectés à une ancienne session Hyprland → fond noir)
  puis relance `waypaper --restore`.
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
- **Music Finder** 🎤 : capture 8 s du **monitor PipeWire** (ffmpeg/pw-record —
  toute la sortie audio : MPD, navigateur…) → reconnaissance Shazam (`songrec`),
  retry 15 s si l'empreinte échoue → titre/artiste + pochettes. La FIFO MPD
  (`/tmp/mpd-cc.fifo`) ne sert qu'en secours, et seulement si MPD joue
  réellement (cc/actions.py) : le volume MPD est alors temporairement forcé à
  100 % (la FIFO transporte le signal APRÈS le volume logiciel) puis restauré.
  Si rien n'est audible → réponse « non reconnu » (pas de piste mensongère).
- **Screenshot** : zone / plein écran / fenêtre (grim + slurp), copié + sauvegardé.
- Fermeture : `Escape`, bouton ✕, ou re-appui `SUPER+G` (toggle).

Architecture : `cc.sh` lance le backend `server.py` (port 8765, localhost), puis la
fenêtre `cc/qml/main.qml` (titre `Sasquatch CC` → windowrule float + border 0 +
`move 0 0` pour couvrir tout l'écran malgré la zone réservée de waybar). À la
fermeture, le serveur est arrêté automatiquement. La palette est dynamique :
`cc/qml/Palette.qml` est retinté par theme-apply.py et pollé par le CC toutes
les 2 s → le panneau suit le thème du wallpaper. Le slider volume contrôle le
volume SYSTÈME (wpctl), pas le volume MPD. Les captures masquent le CC pendant
grim/slurp puis le restaurent.

Dépendances : `quickshell`, `mpd`, `cava`, `alsa-utils`, `songrec`, `tesseract`
(inclus dans install.sh). MPD expose une seule FIFO : `/tmp/mpd-cc.fifo`
(CC Capture → finder) — voir `mpd/mpd.conf`. L'égaliseur cava lit le monitor
PipeWire (`/tmp/sasquatch-audio.fifo`), pas une fifo MPD.
Aucun paquet pip requis : le backend est 100 % stdlib (PEP 668 OK).
