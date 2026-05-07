# 🪶 Sasquatch-Dotfile

Dotfiles personnels pour un environnement **Hyprland** sur **Arch Linux**.

---

## ✨ Aperçu

| Composant        | Outil |
|------------------|-------|
| Compositeur      | Hyprland |
| Barre            | Waybar |
| Launcher         | Wofi |
| Notifications    | Mako |
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
waybar mako wofi \
kitty fish starship fastfetch \
ttf-jetbrains-mono-nerd \
noto-fonts noto-fonts-emoji ttf-font-awesome \
brightnessctl playerctl \
pipewire wireplumber \
networkmanager bluez bluez-utils blueman \
polkit-gnome wl-clipboard \
grim slurp \
nautilus file-roller pavucontrol \
papirus-icon-theme kvantum \
eza bat \
nvidia-utils

---

## 🚀 Installation

```bash
git clone https://github.com/MLD229/Sasquatch-Dotfile.git
cd ~/Sasquatch-Dotfile
bash install.sh
```

Redémarre ta session après l'installation.

---

## 📁 Structure


Sasquatch-Dotfile/
├── fastfetch/
│   └── config.jsonc
├── fish/
│   ├── config.fish
│   └── fish_variables
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
│   │   ├── rules.conf
│   │   └── scroll-workspace.sh
│   ├── hypridle.conf
│   ├── hyprland.conf
│   ├── hyprlock.conf
│   ├── hyprpaper.conf
│   ├── keybinds.conf
│   └── scripts/
│       ├── autostart.sh
│       └── wallpaper.sh
├── kitty/
│   └── kitty.conf
├── mako/
│   └── config
├── scripts/
│   ├── bluetooth.sh
│   ├── brightness.sh
│   ├── screenshot.sh
│   ├── volume.sh
│   └── wifi.sh
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
├── wofi/
│   ├── config
│   └── style.css
├── starship.toml
├── install.sh
└── README.md
