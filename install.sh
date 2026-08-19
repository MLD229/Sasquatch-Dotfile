#!/bin/bash

# ─────────────────────────────────────────
#   Sasquatch-Dotfile — install.sh
#   Adapté pour une fresh install Hyprland
#   v1.2 — paquets résilients (échec non bloquant) + flags --no-packages/--yes
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

# ─── Arguments ───────────────────────────
# install.sh [--clean|-c] [--no-packages] [--yes|-y]
#   --clean        : sauvegarde ~/.config → ~/.config.backup-<date> PUIS vide le
#                    dossier pour une réinstallation propre. À utiliser sur une
#                    machine/compte qui a déjà une vieille config (ex. test après
#                    une restructuration du repo) — sinon les symlinks existants
#                    ne sont pas remplacés et les nouvelles features manquent.
#   --no-packages  : saute l'installation des paquets (test du CÂBLAGE :
#                    symlinks, services, permissions — rien ne bloque sur un
#                    build AUR long comme llama.cpp-cuda).
#   --yes|-y       : réponse OUI automatique à tous les prompts (non-interactif,
#                    pratique pour l'automatisation / le test headless).
CLEAN=0
NO_PACKAGES=0
ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        --clean|-c) CLEAN=1 ;;
        --no-packages) NO_PACKAGES=1 ;;
        --yes|-y) ASSUME_YES=1 ;;
        -h|--help)
            echo "Usage : bash install.sh [--clean|-c] [--no-packages] [--yes|-y]"
            echo "  --clean        : backup ~/.config → ~/.config.backup-<date> puis réinstall propre"
            echo "  --no-packages  : saute l'installation des paquets (test câblage)"
            echo "  --yes|-y       : OUI automatique à tous les prompts"
            exit 0
            ;;
        *) warning "Argument inconnu ignoré : $arg (voir --help)" ;;
    esac
done

# Prompt OUI par défaut (Entrée = OUI) — courte-circuité par --yes.
confirm_yes() { # confirm_yes "message"
    if [ "$ASSUME_YES" = 1 ]; then return 0; fi
    local ans
    read -rp "  $1 [Y/n] " ans
    [[ ! "$ans" =~ ^[Nn]$ ]]
}

# Si --clean : backup complet puis dossier vide (réinstall propre).
if [ "$CLEAN" = 1 ]; then
    header "Nettoyage de l'ancienne configuration"
    TS="$(date +%Y%m%d-%H%M%S)"
    BACKUP="$CONFIG.backup-$TS"
    if [ -e "$CONFIG" ]; then
        if confirm_yes "Sauvegarder $CONFIG → $BACKUP puis vider ?"; then
            mv "$CONFIG" "$BACKUP"
            mkdir -p "$CONFIG"
            success "Ancienne config sauvegardée : $BACKUP"
            info "~/.config vidé — installation propre en cours..."
        else
            warning "Nettoyage annulé — installation sur la config existante (risque : anciennes features)"
        fi
    else
        success "Pas de ~/.config existant — rien à nettoyer"
    fi
fi

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

# Groupes de paquets (même set que requirements — source de vérité).
#   ESSENTIEL : base desktop — sans eux, pas de session utilisable.
#   FEATURES  : CC + panneaux Quickshell (Super+G/Y/P/I/N), musique, OCR.
#   OPTIONNEL : AUR longs/fragiles ou features indépendantes (tablette, Aiko).
# Un échec de paquet ne BLOQUE PLUS le reste (fix 2026-08-18 : avant,
# yay -S ... || exit 1 → le premier paquet qui foirait annulait le câblage
# complet : symlinks, services, permissions, hook waypaper, .desktop brave).

PKGS_ESSENTIAL=(
    ttf-jetbrains-mono-nerd

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

    # GPU NVIDIA
    nvidia-utils            # nvidia-smi (waybar GPU + metrics.py) — machine NVIDIA
    libva-nvidia-driver     # décodage VA-API NVIDIA (env.conf LIBVA_DRIVER_NAME=nvidia)
)

PKGS_FEATURES=(
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
    ffmpeg                  # fallback finder (si pw-record absent)
    python-gobject          # fastview.py (waybar/scripts) — bindings GTK Python
    gtk-layer-shell         # fastview.py (waybar/scripts) — GtkLayerShell typelib
)

PKGS_OPTIONAL=(
    code                    # VS Code — lecteur code/txt (mimeapps, bind $mod+O)
    opentabletdriver        # AUR — daemon tablette XP-Pen (service user activé plus bas)
    llama.cpp-cuda          # AUR — llama-server CUDA (aiko/, sidebar 愛子 Super+N) — build LONG
)

PKGS_FAILED=()

# Installe un groupe SANS bloquer : échec → warning + collecte + CONTINUE.
install_group() {
    local label="$1"; shift
    local missing=() pkg
    for pkg in "$@"; do
        if ! yay -Qi "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done
    if [ ${#missing[@]} -eq 0 ]; then
        success "$label : déjà présents"
        return 0
    fi
    if [ "$NO_PACKAGES" = 1 ]; then
        warning "$label : ${missing[*]} — non installés (--no-packages)"
        PKGS_FAILED+=("${missing[@]}")
        return 1
    fi
    warning "$label manquants : ${missing[*]}"
    if yay -S --needed --noconfirm "${missing[@]}" 2>/dev/null; then
        success "$label installés"
        return 0
    fi
    # Échec (partiel ou total) : on identifie ce qui manque encore.
    local still=()
    for pkg in "${missing[@]}"; do
        yay -Qi "$pkg" &>/dev/null || still+=("$pkg")
    done
    if [ ${#still[@]} -gt 0 ]; then
        error "$label : échec sur ${still[*]} — je continue, à réinstaller ensuite"
        PKGS_FAILED+=("${still[@]}")
        return 1
    fi
    success "$label installés (retour non-zéro mais tout présent)"
    return 0
}

install_group "Essentiel" "${PKGS_ESSENTIAL[@]}"
install_group "Features"  "${PKGS_FEATURES[@]}"
install_group "Optionnel" "${PKGS_OPTIONAL[@]}"

# ─── XDG ───────────────────────────────
header "Initialisation des dossiers XDG"
mkdir -p "$CONFIG"
mkdir -p "$HOME/.local/share/icons"
mkdir -p "$HOME/songs"                 # bibliothèque musicale (mpd.conf music_directory)
mkdir -p "$HOME/.local/share/mpd/playlists"   # MPD : socket + state PAR USER (mpd.conf) — sinon mpd refuse de démarrer
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
        if [ "$CLEAN" != 1 ]; then
            warning "  → Ancien clone ou structure périmée ? Relance avec : bash install.sh --clean"
        fi
        return 1
    fi

    mkdir -p "$(dirname "$dst")"

    # Déjà lié vers la même source ? Rien à faire (idempotent, sans prompt).
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        success "Déjà lié : $dst"
        return
    fi

    if [ -e "$dst" ] || [ -L "$dst" ]; then
        if [ "$ASSUME_YES" = 1 ]; then
            rm -rf "$dst"
        else
            read -rp "  ⚠ '$dst' existe déjà. Écraser ? [y/N] " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] || { warning "Ignoré : $dst"; return; }
            rm -rf "$dst"
        fi
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

# ─── Hook thème dynamique (config waypaper) ──
# Le fichier config.ini sert de « souvenir » du dossier/wallpaper courants
# (lu par le backend CC et apply-wallpaper.sh). Le thème est appliqué par
# apply-wallpaper.sh directement (hyprpaper + theme-apply.sh) — plus aucune
# dépendance au binaire waypaper (retiré des paquets 2026-08-19).
# Idempotent : ne touche pas une config existante.
header "Hook thème dynamique"
WP_CFG="$CONFIG/waypaper/config.ini"
WP_HOOK='post_command = ~/.config/scripts/theme-apply.sh $wallpaper'
mkdir -p "$(dirname "$WP_CFG")"
# Dossier de wallpapers par défaut (vide, idempotent) : sans clé folder=,
# waypaper retombe sur ~/Pictures → le sélecteur affiche des images jamais
# choisies. Vide → "aucune image" tant que l'user ne choisit pas un dossier.
mkdir -p ~/Wall-E-Desk
if [ ! -f "$WP_CFG" ]; then
    printf '[settings]\nfolder = ~/Wall-E-Desk\n%s\n' "$WP_HOOK" > "$WP_CFG"
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

# Garde configs existantes : sans clé folder=, waypaper retombe sur ~/Pictures
# → le sélecteur affiche des images jamais choisies par l'user. On force le
# dossier par défaut juste après [settings] (idempotent via le grep).
if ! grep -q '^folder' "$WP_CFG"; then
    sed -i '/^\[settings\]/a folder = ~/Wall-E-Desk' "$WP_CFG"
    success "folder par défaut Wall-E-Desk ajouté à waypaper"
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
link "$DOTDIR/wp"                       "$CONFIG/wp"             # Sélecteur de fonds d'écran (Quickshell, Super+Y)
link "$DOTDIR/pl"                       "$CONFIG/pl"             # Playlist MPD (Quickshell, Super+P)
link "$DOTDIR/aiko"                     "$CONFIG/aiko"           # Sidebar 愛子 Aiko (Quickshell chat IA, Super+N)
link "$DOTDIR/mpd"                      "$CONFIG/mpd"            # mpd.conf + fifo CC Capture (finder)
link "$DOTDIR/settings"                 "$CONFIG/settings"       # Panneau Settings (Quickshell, Super+I)
link "$DOTDIR/themes/gtk/gtk-3.0"       "$CONFIG/gtk-3.0"
link "$DOTDIR/themes/gtk/gtk-4.0"       "$CONFIG/gtk-4.0"
link "$DOTDIR/themes/qt/kdeglobals"     "$CONFIG/kdeglobals"
link "$DOTDIR/mimeapps.list"            "$CONFIG/mimeapps.list"   # associations par défaut (code/mpv)
# themes/icons et themes/cursors retirés : absents du repo (bug #9)
# Icônes/curseurs gérés par les paquets : papirus-icon-theme, bibata-cursor-theme

# ─── .desktop Brave + extension CC ────────
# L'extension maison browser-bridge (cc/browser-bridge) fait le pont
# YouTube→CC (MPRIS natif absent sur certains Chromium). Le keybind Super+W
# passe --load-extension, mais un lancement depuis rofi/drun utilise le
# .desktop SANS l'extension → le pont ne se charge pas. On copie le .desktop
# système vers ~/.local/share/applications avec Exec patché (idempotent).
# ⚠️ Exec de .desktop N'expand PAS ~ → chemin absolu $HOME ici.
header "Extension CC dans le .desktop Brave"
BRAVE_DESKTOP_SRC="/usr/share/applications/brave-browser.desktop"
BRAVE_DESKTOP_DST="$HOME/.local/share/applications/brave-browser.desktop"
if [ -f "$BRAVE_DESKTOP_SRC" ]; then
    mkdir -p "$(dirname "$BRAVE_DESKTOP_DST")"
    if [ ! -f "$BRAVE_DESKTOP_DST" ] || ! grep -q 'load-extension' "$BRAVE_DESKTOP_DST"; then
        cp "$BRAVE_DESKTOP_SRC" "$BRAVE_DESKTOP_DST"
        sed -i "s|^Exec=brave |Exec=brave --load-extension=$HOME/.config/cc/browser-bridge |" "$BRAVE_DESKTOP_DST"
        success "brave-browser.desktop patché (extension CC chargée)"
    else
        success "brave-browser.desktop déjà patché"
    fi
else
    warning ".desktop brave-browser introuvable (brave-bin pas installé ?) — Super+W garde l'extension, rofi non"
fi

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

# Service USER waybar (supervision de la barre). Restart=on-failure → un crash
# relance la barre tout seul (avant : morte jusqu'au relogin) ; theme-apply.sh
# recharge le CSS via `systemctl --user reload waybar` (SIGUSR2, zéro flash).
# Le user manager expose WAYLAND_DISPLAY + HYPRLAND_INSTANCE_SIGNATURE →
# waybar du service est reconnu par waybar_current_session() (skip idempotent).
link "$DOTDIR/waybar/waybar.service" "$SD_USER/waybar.service"
systemctl --user daemon-reload 2>/dev/null || true
if systemctl --user enable --now waybar 2>/dev/null; then
    success "waybar (service user) activé"
else
    warning "Service user waybar non activé (pas de session) — theme-apply.sh le lancera au besoin"
fi

# ─── Scripts exécutables ───────────────
header "Permissions des scripts"
chmod +x "$DOTDIR"/scripts/*.sh
chmod +x "$DOTDIR"/hypr/scripts/*.sh
chmod +x "$DOTDIR"/rofi/scripts/*.sh      # ← ajouté (bug #31)
chmod +x "$DOTDIR"/cc/*.sh                # ← Control Center (cc.sh, ocr.sh)
chmod +x "$DOTDIR"/aiko/*.sh              # ← Sidebar 愛子 Aiko (aiko.sh, setup.sh)
chmod +x "$DOTDIR"/settings/*.sh          # ← Panneau Settings (settings.sh)
chmod +x "$DOTDIR"/pl/*.sh                # ← Playlist MPD (pl.sh)
chmod +x "$DOTDIR"/set-wall.sh            # ← ajouté (bug #31)
success "Scripts rendus exécutables"

# ─── Fish comme shell par défaut ───────
header "Shell par défaut"
if command -v fish >/dev/null 2>&1 && [ "$SHELL" != "$(command -v fish)" ]; then
    if confirm_yes "Définir Fish comme shell par défaut ?"; then
        chsh -s "$(command -v fish)" && success "Fish défini comme shell par défaut" \
            || warning "chsh a échoué (mot de passe ?) — à faire manuellement"
    fi
else
    success "Fish déjà défini (ou absent)"
fi

# ─── Récapitulatif ─────────────────────
header "Récapitulatif"
if [ ${#PKGS_FAILED[@]} -gt 0 ]; then
    warning "Paquets NON installés (${#PKGS_FAILED[@]}) : ${PKGS_FAILED[*]}"
    warning "  → Relance : yay -S --needed --noconfirm ${PKGS_FAILED[*]}"
else
    success "Tous les paquets requis sont présents"
fi
if ! ls "$DOTDIR"/aiko/models/*.gguf &>/dev/null; then
    info "Aiko (Super+N) : aucun modèle GGUF — lance : bash $DOTDIR/aiko/setup.sh (téléchargement ~2-4 Go)"
fi

echo -e "\n${GREEN}${BOLD}━━━ Sasquatch-Dotfile installé avec succès ! ━━━${NC}"
echo -e "${YELLOW}  → Redémarre ta session pour appliquer tous les changements.${NC}\n"
