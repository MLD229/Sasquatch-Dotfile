#!/bin/bash

# ─────────────────────────────────────────
#   Sasquatch-Dotfile — install.sh
#   Adapté pour une fresh install Hyprland
#   v1.1 — symlinks corrigés (scripts/, rofi, set-wall)
# ─────────────────────────────────────────

set -uo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$HOME/.config"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warning() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
header()  { echo -e "\n${BOLD}${BLUE}━━━ $1 ━━━${NC}"; }

# ─── yay ───────────────────────────────
header "Vérification de yay"
if ! command -v yay &>/dev/null; then
    info "yay non trouvé — installation..."
    sudo pacman -S --needed git base-devel
    if [ -d /tmp/yay/.git ]; then
        info "/tmp/yay existe déjà — mise à jour..."
        git -C /tmp/yay pull --ff-only
    else
        git clone https://aur.archlinux.org/yay.git /tmp/yay
    fi
    cd /tmp/yay && makepkg -si --noconfirm
    cd "$DOTDIR"
    success "yay installé"
else
    success "yay présent"
fi

# ─── Dépendances ───────────────────────
header "Installation des dépendances"

PKGS=(
    ttf-jetbrains-mono-nerd
    waypaper

    eza
    bat
    brightnessctl
    playerctl
    libqalculate       # calculatrice rofi (calc.sh, SUPER+C)
    python-pillow

    # Presse-papier (clipboard.sh, SUPER+V) + captures (grim/slurp)
    cliphist
    wl-clipboard
    grim
    slurp
    libnotify

    # Réseau / BT
    iwd
    bluez
    bluez-utils
    blueman
    dolphin

    # Son (module pulseaudio waybar + pavucontrol)
    pipewire-pulse
    pavucontrol

    # Icônes / curseurs / thèmes (rofi + env.conf)
    papirus-icon-theme
    bibata-cursor-theme
    catppuccin-gtk-theme-mocha
    qt5ct
    kvantum

    # Portail XDG (partage d'écran, dialogues)
    xdg-desktop-portal-hyprland

    # Éditeur par défaut (config.fish EDITOR)
    neovim

    # Navigateurs (bind SUPER+W = brave ; windowrules firefox)
    brave
    firefox

    waybar
    rofi
    mako

    hyprland
    hyprpaper
    hyprlock
    hypridle

    kitty
    fish
    starship
    fastfetch

    xdg-user-dirs
    xdg-utils

    pipewire
    wireplumber

    polkit-gnome

    qt5-wayland
    qt6-wayland

    noto-fonts
    noto-fonts-emoji

    # IME japonais (fcitx5 + mozc) — bascule Ctrl+Shift+1
    fcitx5
    fcitx5-mozc
    fcitx5-configtool
    fcitx5-gtk
    fcitx5-qt
    noto-fonts-cjk
)

missing=()

for pkg in "${PKGS[@]}"; do
    if ! yay -Qi "$pkg" &>/dev/null; then
        missing+=("$pkg")
    else
        success "$pkg"
    fi
done

if [ ${#missing[@]} -gt 0 ]; then
    warning "Paquets manquants : ${missing[*]}"
    read -rp "  Installer maintenant ? [Y/n] " confirm
    if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
        yay -S --needed --noconfirm "${missing[@]}" || {
            error "Échec de l'installation des paquets — corrige puis relance."
            exit 1
        }
    fi
fi

# ─── XDG ───────────────────────────────
header "Initialisation des dossiers XDG"
mkdir -p "$CONFIG"
mkdir -p "$HOME/.local/share/icons"
xdg-user-dirs-update
success "Dossiers XDG créés"

# ─── Fonction symlink ───────────────────
# Vérifie que la source EXISTE avant de créer le lien
# (évite les liens morts silencieux, cf. audit bug #9)
link() {
    local src="$1"
    local dst="$2"

    if [ ! -e "$src" ]; then
        warning "Source absente, lien ignoré : $src"
        return 1
    fi

    mkdir -p "$(dirname "$dst")"

    if [ -e "$dst" ] || [ -L "$dst" ]; then
        read -rp "  ⚠ '$dst' existe déjà. Écraser ? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { warning "Ignoré : $dst"; return; }
        rm -rf "$dst"
    fi

    ln -s "$src" "$dst"
    success "Lié : $dst"
}

# ─── Lock à la fermeture du capot ───────────────────────

header "Configuration lid switch lock"

# Backup avant modification (audit bug #27)
LOGIND=/etc/systemd/logind.conf
if [ ! -f "${LOGIND}.bak-sasquatch" ]; then
    sudo cp "$LOGIND" "${LOGIND}.bak-sasquatch"
    info "Backup créé : ${LOGIND}.bak-sasquatch"
fi

sudo sed -i \
    -e 's/^#HandleLidSwitch=.*/HandleLidSwitch=lock/' \
    -e 's/^#HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=lock/' \
    -e 's/^#HandleLidSwitchDocked=.*/HandleLidSwitchDocked=lock/' \
    "$LOGIND"

grep -q "^HandleLidSwitch=" "$LOGIND" || \
    echo "HandleLidSwitch=lock" | sudo tee -a "$LOGIND"

grep -q "^HandleLidSwitchExternalPower=" "$LOGIND" || \
    echo "HandleLidSwitchExternalPower=lock" | sudo tee -a "$LOGIND"

grep -q "^HandleLidSwitchDocked=" "$LOGIND" || \
    echo "HandleLidSwitchDocked=lock" | sudo tee -a "$LOGIND"

# ─── Symlinks ──────────────────────────
header "Création des symlinks"

link "$DOTDIR/hypr"                     "$CONFIG/hypr"
link "$DOTDIR/waybar"                   "$CONFIG/waybar"
link "$DOTDIR/rofi"                     "$CONFIG/rofi"
link "$DOTDIR/mako"                     "$CONFIG/mako"
link "$DOTDIR/kitty"                    "$CONFIG/kitty"
link "$DOTDIR/fcitx5"                   "$CONFIG/fcitx5"   # IME japonais (config+profile+conf)
link "$DOTDIR/fish"                     "$CONFIG/fish"
link "$DOTDIR/fastfetch"                "$CONFIG/fastfetch"
link "$DOTDIR/starship.toml"            "$CONFIG/starship.toml"
link "$DOTDIR/scripts"                  "$CONFIG/scripts"        # ← ajouté (bug #5)
link "$DOTDIR/themes/gtk/gtk-3.0"       "$CONFIG/gtk-3.0"
link "$DOTDIR/themes/gtk/gtk-4.0"       "$CONFIG/gtk-4.0"
link "$DOTDIR/themes/qt/kdeglobals"     "$CONFIG/kdeglobals"
# themes/icons et themes/cursors retirés : absents du repo (bug #9)
# Icônes/curseurs gérés par les paquets : papirus-icon-theme, bibata-cursor-theme

# ─── Scripts exécutables ───────────────
header "Permissions des scripts"
chmod +x "$DOTDIR"/scripts/*.sh
chmod +x "$DOTDIR"/hypr/scripts/*.sh
chmod +x "$DOTDIR"/rofi/scripts/*.sh      # ← ajouté (bug #31)
chmod +x "$DOTDIR"/set-wall.sh            # ← ajouté (bug #31)
success "Scripts rendus exécutables"

# ─── Fish comme shell par défaut ───────
header "Shell par défaut"
if [ "$SHELL" != "$(which fish)" ]; then
    read -rp "  Définir Fish comme shell par défaut ? [Y/n] " confirm
    if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
        chsh -s "$(which fish)"
        success "Fish défini comme shell par défaut"
    fi
else
    success "Fish déjà défini"
fi

echo -e "\n${GREEN}${BOLD}━━━ Sasquatch-Dotfile installé avec succès ! ━━━${NC}"
echo -e "${YELLOW}  → Redémarre ta session pour appliquer tous les changements.${NC}\n"
