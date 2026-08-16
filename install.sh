#!/bin/bash

# ─────────────────────────────────────────
#   Sasquatch-Dotfile — install.sh
#   Adapté pour une fresh install Hyprland
#   v1.1 — symlinks corrigés (scripts/, rofi, set-wall)
# ─────────────────────────────────────────
#   ⚠️ Quelques prompts interactifs (install paquets, écrasement
#   symlinks, chsh) : répondre Y / Entrée pour laisser faire.
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
    sudo pacman -S --needed git base-devel || {
        error "git/base-devel indisponibles (pacman en échec) — corrige puis relance."
        exit 1
    }
    if [ -d /tmp/yay/.git ]; then
        info "/tmp/yay existe déjà — mise à jour..."
        git -C /tmp/yay pull --ff-only || warning "Mise à jour yay impossible (build sur l'existant)"
    elif ! git clone https://aur.archlinux.org/yay.git /tmp/yay; then
        error "Échec du clone de yay — vérifie ta connexion puis relance."
        exit 1
    fi
    cd /tmp/yay && makepkg -si --noconfirm || {
        error "Échec du build/install de yay (makepkg) — corrige puis relance."
        exit 1
    }
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
    python-numpy           # wallclock-ja.py (position auto dans la zone plate du wallpaper)
    python-cairo           # wallclock-ja.py + fastview.py (dessin cairo GTK)

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
    mpv                     # lecteur par défaut audio/vidéo (mimeapps : mp3, mp4…)

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
    code                    # VS Code — lecteur code/txt (mimeapps, bind $mod+O)

    # Navigateurs (bind SUPER+W = brave ; windowrules firefox)
    # NOTE : le paquet AUR s'appelle brave-bin (pas "brave" — introuvable, cf. audit 2026-08-14)
    brave-bin
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

    # Control Center (Super+G, cc/) — UI Quickshell + backend python
    quickshell
    mpd                     # lecteur local + fifos (cava + finder) — REQUIS par le CC
    cava                    # égaliseur synchronisé (fifo raw)
    alsa-utils              # arecord (micro, Music Finder)
    songrec                 # reconnaissance Shazam (Music Finder)
    tesseract               # OCR écran (cc/ocr.sh)
    tesseract-data-fra      # langue française pour tesseract
    curl                    # healthcheck serveur (cc/cc.sh)
    jq                      # parsing JSON (lock-media.sh au lock, scripts)
    nvidia-utils            # nvidia-smi (waybar GPU + metrics.py) — machine NVIDIA
    libva-nvidia-driver     # décodage VA-API NVIDIA (env.conf LIBVA_DRIVER_NAME=nvidia)
    ffmpeg                  # fallback finder (si pw-record absent)
    python-gobject          # fastview.py (waybar/scripts) — bindings GTK Python
    gtk-layer-shell         # fastview.py (waybar/scripts) — GtkLayerShell typelib
    opentabletdriver        # AUR — daemon tablette XP-Pen (service user activé plus bas)
    llama.cpp-cuda          # AUR — llama-server CUDA (aiko/, sidebar 愛子 Super+N)
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
mkdir -p "$HOME/songs"                 # bibliothèque musicale (mpd.conf music_directory)
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

    # Déjà lié vers la même source ? Rien à faire (idempotent, sans prompt).
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        success "Déjà lié : $dst"
        return
    fi

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

# ─── Services systemd ──────────────────────
header "Activation des services systemd"

for svc in iwd systemd-networkd bluetooth; do
    if systemctl is-enabled "$svc" &>/dev/null; then
        success "$svc déjà activé"
    else
        info "Activation de $svc…"
        sudo systemctl enable --now "$svc" && success "$svc activé" || warning "Échec activation $svc (ignore)"
    fi
done

# Service USER mpd (lecteur du CC). Peut échouer hors session graphique
# (pas de XDG_RUNTIME_DIR) — c'est le cas d'une fresh install en TTY :
# on tente, sinon on prévient (autostart.sh le lancera au login).
if systemctl --user enable --now mpd 2>/dev/null; then
    success "mpd (service user) activé"
else
    warning "Service user mpd non activé (pas de session) — autostart.sh le lancera au login"
fi

# Service USER opentabletdriver (tablette graphique XP-Pen Star 03, 28bd:0907).
# Le kernel Arch n'a PAS hid_uclogic → OTD fait le relais tablette→libinput
# (Hyprland voit la tablette virtuelle, pression + tilt). Idempotent.
# ⚠️ PIÈGE 2026-08-16 : après un audit/test, le service peut rester arrêté
# (dead) alors qu'il est enabled → la tablette ne répond plus. On vérifie
# qu'il tourne VRAIMENT (is-active), pas juste qu'il est activé.
if systemctl --user enable --now opentabletdriver 2>/dev/null; then
    if systemctl --user is-active --quiet opentabletdriver; then
        success "opentabletdriver (service user) actif — tablette XP-Pen Star 03"
    else
        warning "opentabletdriver activé mais INACTIF (dead) — daemon crashé ? Vérifier : journalctl --user -u opentabletdriver"
    fi
else
    warning "Service user opentabletdriver non activé (pas de session) — à activer au login"
fi

# Services USER audio (PipeWire/WirePlumber) — SANS EUX : pas de son, wpctl/pactl
# échouent (volume.sh, waybar pulseaudio, CC volume morts). Les sockets ne sont
# pas activées par défaut sur une machine neuve → on les active explicitement.
if systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber 2>/dev/null; then
    success "Services user audio activés (pipewire/pulse/wireplumber)"
else
    warning "Services user audio non activés (pas de session graphique ?) — à activer au login"
fi

# Service USER sasquatch-cc (backend du Control Center, port 8765).
# Permanent + Restart=always → le serveur survit aux relogins (cleanup-orphans
# ne le tue pas : pas de signature Hyprland) et un crash ne le tue plus en
# silence. Idempotent : daemon-reload puis enable --now.
SD_USER="$CONFIG/systemd/user"
mkdir -p "$SD_USER"
link "$DOTDIR/cc/sasquatch-cc.service" "$SD_USER/sasquatch-cc.service"
systemctl --user daemon-reload 2>/dev/null || true
if systemctl --user enable --now sasquatch-cc 2>/dev/null; then
    success "sasquatch-cc (service user) activé"
else
    warning "Service user sasquatch-cc non activé (pas de session) — cc.sh le lancera au besoin"
fi
# ─── Hook thème dynamique (waypaper) ─────────
# Le post_command applique la palette au changement de wallpaper. Sans lui,
# seule l'appli au login joue (filet autostart.sh) — le thème ne suivrait plus
# les changements de fond. Idempotent : ne touche pas une config existante
# qui a déjà le hook (ex. config live de momo).
header "Hook waypaper (thème dynamique)"
WP_CFG="$CONFIG/waypaper/config.ini"
WP_HOOK='post_command = ~/.config/scripts/theme-apply.sh $wallpaper'
mkdir -p "$(dirname "$WP_CFG")"
if [ ! -f "$WP_CFG" ]; then
    printf '[settings]\n%s\n' "$WP_HOOK" > "$WP_CFG"
    success "config.ini waypaper créé avec le hook thème"
elif ! grep -q '^post_command' "$WP_CFG"; then
    if grep -q '^\[settings\]' "$WP_CFG"; then
        sed -i '/^\[settings\]/a post_command = ~/.config/scripts/theme-apply.sh $wallpaper' "$WP_CFG"
    else
        printf '\n[settings]\n%s\n' "$WP_HOOK" >> "$WP_CFG"
    fi
    success "Hook thème ajouté à waypaper"
else
    success "Hook thème déjà présent"
fi

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
link "$DOTDIR/cc"                       "$CONFIG/cc"             # Control Center (Quickshell, Super+G)
link "$DOTDIR/aiko"                     "$CONFIG/aiko"           # Sidebar 愛子 Aiko (Quickshell chat IA, Super+N)
link "$DOTDIR/mpd"                      "$CONFIG/mpd"            # mpd.conf + fifo CC Capture (finder)
link "$DOTDIR/settings"                 "$CONFIG/settings"       # Panneau Settings (Quickshell, Super+I)
link "$DOTDIR/themes/gtk/gtk-3.0"       "$CONFIG/gtk-3.0"
link "$DOTDIR/themes/gtk/gtk-4.0"       "$CONFIG/gtk-4.0"
link "$DOTDIR/themes/qt/kdeglobals"     "$CONFIG/kdeglobals"
link "$DOTDIR/mimeapps.list"            "$CONFIG/mimeapps.list"   # associations par défaut (code/mpv)
# themes/icons et themes/cursors retirés : absents du repo (bug #9)
# Icônes/curseurs gérés par les paquets : papirus-icon-theme, bibata-cursor-theme

# ─── Scripts exécutables ───────────────
header "Permissions des scripts"
chmod +x "$DOTDIR"/scripts/*.sh
chmod +x "$DOTDIR"/hypr/scripts/*.sh
chmod +x "$DOTDIR"/rofi/scripts/*.sh      # ← ajouté (bug #31)
chmod +x "$DOTDIR"/cc/*.sh                # ← Control Center (cc.sh, ocr.sh)
chmod +x "$DOTDIR"/aiko/*.sh              # ← Sidebar 愛子 Aiko (aiko.sh, setup.sh)
chmod +x "$DOTDIR"/settings/*.sh          # ← Panneau Settings (settings.sh)
chmod +x "$DOTDIR"/set-wall.sh            # ← ajouté (bug #31)
success "Scripts rendus exécutables"

# ─── Fish comme shell par défaut ───────
header "Shell par défaut"
if command -v fish >/dev/null 2>&1 && [ "$SHELL" != "$(command -v fish)" ]; then
    read -rp "  Définir Fish comme shell par défaut ? [Y/n] " confirm
    if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
        chsh -s "$(command -v fish)" && success "Fish défini comme shell par défaut" \
            || warning "chsh a échoué (mot de passe ?) — à faire manuellement"
    fi
else
    success "Fish déjà défini (ou absent)"
fi

echo -e "\n${GREEN}${BOLD}━━━ Sasquatch-Dotfile installé avec succès ! ━━━${NC}"
echo -e "${YELLOW}  → Redémarre ta session pour appliquer tous les changements.${NC}\n"
