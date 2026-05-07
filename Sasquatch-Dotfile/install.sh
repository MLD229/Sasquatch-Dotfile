#!/bin/bash

# ─────────────────────────────────────────
#   Sasquatch-Dotfile — install.sh
#   Adapté pour une fresh install Hyprland
# ─────────────────────────────────────────

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
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay && makepkg -si --noconfirm
    cd "$DOTDIR"
    success "yay installé"
else
    success "yay présent"
fi

# ─── Dépendances ───────────────────────
header "Installation des dépendances"

PKGS=(
    hyprland hyprpaper hyprlock hypridle
    ttf-jetbrains-mono-nerd       # requis par waybar/style.css
    waypaper                      # GUI wallpaper manager
    waybar wofi mako
    kitty fish starship fastfetch
    xdg-user-dirs xdg-utils
    pipewire wireplumber          # audio
    polkit-gnome                  # authentification
    qt5-wayland qt6-wayland       # support Qt Wayland
    noto-fonts noto-fonts-emoji   # polices de base
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
        yay -S --needed --noconfirm "${missing[@]}"
    fi
fi

# ─── XDG ───────────────────────────────
header "Initialisation des dossiers XDG"
mkdir -p "$CONFIG"
mkdir -p "$HOME/.local/share/icons"
xdg-user-dirs-update
success "Dossiers XDG créés"

# ─── Fonction symlink ───────────────────
link() {
    local src="$1"
    local dst="$2"

    mkdir -p "$(dirname "$dst")"

    if [ -e "$dst" ] || [ -L "$dst" ]; then
        read -rp "  ⚠ '$dst' existe déjà. Écraser ? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { warning "Ignoré : $dst"; return; }
        rm -rf "$dst"
    fi

    ln -s "$src" "$dst"
    success "Lié : $dst"
}

# ─── Symlinks ──────────────────────────
header "Création des symlinks"

link "$DOTDIR/hypr"                     "$CONFIG/hypr"
link "$DOTDIR/waybar"                   "$CONFIG/waybar"
link "$DOTDIR/rofi"                     "$CONFIG/rofi"
link "$DOTDIR/mako"                     "$CONFIG/mako"
link "$DOTDIR/kitty"                    "$CONFIG/kitty"
link "$DOTDIR/fish"                     "$CONFIG/fish"
link "$DOTDIR/fastfetch"                "$CONFIG/fastfetch"
link "$DOTDIR/starship.toml"            "$CONFIG/starship.toml"
link "$DOTDIR/themes/gtk/gtk-3.0"       "$CONFIG/gtk-3.0"
link "$DOTDIR/themes/gtk/gtk-4.0"       "$CONFIG/gtk-4.0"
link "$DOTDIR/themes/qt/kdeglobals"     "$CONFIG/kdeglobals"
link "$DOTDIR/themes/icons"             "$HOME/.local/share/icons/sasquatch"
link "$DOTDIR/themes/cursors"           "$HOME/.local/share/icons/cursors-sasquatch"

# ─── Scripts exécutables ───────────────
header "Permissions des scripts"
chmod +x "$DOTDIR"/scripts/*.sh
chmod +x "$DOTDIR"/hypr/scripts/*.sh
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
