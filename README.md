# 🪶 Sasquatch-Dotfile

Dotfiles personnels pour un environnement **Hyprland** sur **Arch Linux**.

---

## ✨ Aperçu

| Composant        | Outil |
|------------------|-------|
| Compositeur      | Hyprland |
| Barre            | Waybar (🇯🇵 100 % japonais) |
| Launcher         | Rofi (Super seule, toggle) |
| OSD volume/luminosité | Rofi |
| Notifications    | Mako |
| IME japonais     | Fcitx5 + Mozc |
| Terminal         | Kitty |
| Shell            | Fish |
| Prompt           | Starship |
| Fond d’écran     | Picker `wp/` (Quickshell, Super+Y) + waypaper/hyprpaper |
| Verrouillage     | Hyprlock (🇯🇵 heure/date hiragana + musique) |
| Inactivité       | Hypridle |
| Sysinfo          | Fastfetch |
| Control Center   | Quickshell (`cc/`, Super+G) |
| Panneau Settings | Quickshell (`settings/`, Super+I) |
| Sidebar chat IA  | Quickshell + llama.cpp (`aiko/`, Super+N) |
| Playlist MPD     | Quickshell (`pl/`, Super+P) — toggles random/repeat/single, liste cliquable, recherche/ajout, dossier musique |
| Tablette graphique | OpenTabletDriver (service user) |

---

## ⌨️ Raccourcis clavier (layout AZERTY)

Source de vérité : `hypr/keybinds.conf` (édition possible depuis Settings → RACCOURCIS).

| Touche | Action |
|--------|--------|
| **Super** (seule, release) | Launcher rofi (toggle) |
| **Super + ,** | Aide-mémoire des raccourcis (reminder, toggle) |
| **Super + T / W / E / O** | Terminal kitty / Brave (extension CC) / Dolphin / VS Code |
| **Super + G** | Control Center (Quickshell) |
| **Super + I** | Panneau Settings |
| **Super + N** | Sidebar 愛子 Aiko (chat IA) |
| **Super + C / V** | Calculatrice rofi (qalc) / Presse-papier (cliphist) |
| **Super + B** | Bluetooth : toggle blueman-manager (wrapper anti-crash) |
| **Super + L / Escape** | Verrouiller (hyprlock) / Powermenu rofi |
| **Super + Q / Shift+M** | Fermer la fenêtre (killactive) / Quitter la session |
| **Super + F / D** | Fullscreen / **Agrandir** (internal, barre visible) |
| **Super + P / Shift+P** | Playlist MPD (panneau Quickshell) / Pseudo-tiling |
| **Super + R** | Toggle split (layoutmsg togglesplit) |
| **Super + J** | Masquer/afficher la waybar (SIGUSR1) |
| **Super + Shift+V** | Libre/flottant (togglefloating) |
| **Super + Z / S** | Focus haut / bas |
| **Super + Shift + Z/S/Q/D** | Déplacer la fenêtre haut/bas/gauche/droite |
| **Super + Ctrl + Z/S/Q/D** | Resize 30 px |
| **Super + 1..5** | Workspaces 1..5 (`& é " ' (`) |
| **Super + Shift + 1..5** | Déplacer la fenêtre vers workspace |
| **Super + ←/→** | Workspace précédent/suivant |
| **Super + molette** | Workspace suivant/précédent (r±1 natif, **boucle 1↔10**) |
| **Super + Y** | Sélecteur de fonds d'écran (`wp/`, Quickshell → thème dynamique) |
| **Ctrl+Shift+1** | Bascule IME japonais (fcitx5/Mozc) |
| **XF86Audio*** | Volume/mute/play/next/prev (volume.sh, media-ctl.sh) |
| **XF86MonBrightness*** | Luminosité (brightness.sh + OSD) |
| **Print / Super+Print** | Screenshot plein écran / zone |

> **Scroll workspaces** : `r±1` natif boucle de 1 à 10. Pour un blocage strict
> (pas de boucle), le script `hypr/scripts/scroll-workspace.sh up|down` est
> disponible — les binds correspondants sont commentés dans keybinds.conf
> (décision : comportement actuel conservé).

---

📦 Dépendances
Paquets principaux

```bash
# Officiel (pacman)
sudo pacman -S hyprland hyprlock hypridle hyprpaper waypaper \
xdg-desktop-portal-hyprland xdg-utils xdg-user-dirs \
waybar mako rofi \
python-gobject gtk-layer-shell python-pillow python-numpy python-cairo \
kitty fish starship fastfetch \
ttf-jetbrains-mono-nerd \
noto-fonts noto-fonts-emoji noto-fonts-cjk \
brightnessctl playerctl \
pipewire pipewire-pulse wireplumber \
qt5-wayland qt6-wayland libnotify \
iwd bluez bluez-utils blueman \
polkit-gnome wl-clipboard cliphist \
grim slurp jq \
dolphin pavucontrol \
firefox \
papirus-icon-theme kvantum qt5ct \
eza bat neovim code mpv \
nvidia-utils libva-nvidia-driver \
fcitx5 fcitx5-mozc fcitx5-configtool fcitx5-gtk fcitx5-qt \
libqalculate \
mpd cava alsa-utils songrec quickshell curl ffmpeg \
tesseract tesseract-data-fra

# AUR (via yay — install.sh le fait automatiquement)
yay -S brave-bin catppuccin-gtk-theme-mocha bibata-cursor-theme \
opentabletdriver llama.cpp-cuda
```

> Liste exhaustive : voir `requirements` (source de vérité, synchro avec install.sh).
> `jq` (lock-media.sh), `python-numpy`/`python-cairo` (wallclock-ja, fastview),
> `code`/`mpv` (mimeapps), `opentabletdriver` (tablette XP-Pen),
> `llama.cpp-cuda` (Aiko).

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
├── aiko/                        ← Sidebar 愛子 — chat IA locale (Super+N)
│   ├── aiko.sh                  ← toggle fenêtre (pidfile)
│   ├── server.py                ← backend HTTP (port 8780, stdlib, SSE)
│   ├── main.qml + qml/          ← UI Quickshell (glass, palette dynamique)
│   ├── config.json              ← modèle, chemins runtime
│   ├── setup.sh                 ← télécharge les GGUF (gitignorés, ~2,6 Go)
│   └── sessions/                ← historique autosave (gitignoré)
├── cc/                          ← Control Center (Super+G, Quickshell)
│   ├── cc.sh                    ← toggle fenêtre + start service systemd
│   ├── server.py                ← point d'entrée HTTP (port 8765, stdlib)
│   ├── config.py / metrics.py / viz.py / mpd.py / actions.py
│   ├── palette.py / translate.py / player.py / cava.py / web_bridge.py
│   ├── ocr.sh                   ← OCR écran (slurp + grim + tesseract)
│   ├── cava.conf                ← égaliseur (fifo raw)
│   ├── sasquatch-cc.service     ← service user permanent (backend)
│   ├── browser-bridge/          ← extension Brave → now-playing web
│   └── qml/                     ← Gauge, IconButton, Tile, Sparkline,
│                                   Palette.qml (généré par theme-apply, gitignoré)
├── fastfetch/
│   ├── config.jsonc             ← logo + palette dynamique (bloc SASQUATCH-PALETTE)
│   └── arch.png                 ← logo kitty (fallback ; builtin arch par défaut)
├── fcitx5/                      ← IME japonais (bascule Ctrl+Shift+1)
│   ├── config / profile
│   └── conf/ (mozc.conf, notifications.conf ; cached_layouts gitignoré)
├── fish/
│   ├── config.fish              ← alias, MPD_HOST (socket user)
│   └── fish_variables           ← gitignoré (spécifique machine)
├── hypr/
│   ├── conf.d/                  ← env, monitors, general, decoration, blur,
│   │                              animations, layout, input, misc, rules
│   ├── hyprland.conf            ← point d'entrée (sources conf.d/ + keybinds)
│   ├── keybinds.conf            ← tous les raccourcis ($mod = SUPER, AZERTY)
│   ├── keybinds-user.conf       ← overrides utilisateur (via Settings, versionné)
│   ├── hypridle.conf            ← régénéré par settings.py (veille)
│   ├── hyprlock.conf            ← 🇯🇵 lock-ja + musique (bloc SASQUATCH-PALETTE)
│   ├── hyprpaper.conf           ← fallback wallpaper (waypaper gère)
│   └── scripts/
│       ├── autostart.sh         ← purge orphelins + lancement session
│       ├── cleanup-orphans.sh   ← purge process de l'ancienne session Hyprland
│       ├── wallpaper.sh         ← pkill hyprpaper + waypaper --restore
│       ├── scroll-workspace.sh  ← ws bloqué 1..10 (binds commentés, r±1 natif actif)
│       ├── lock-ja.py           ← heure/date hiragana pour hyprlock
│       ├── lock-media.sh        ← now-playing CC pour hyprlock (jq)
│       └── media-ctl.sh         ← contrôle musique (CC API → fallback playerctl)
├── install.sh                   ← installateur (symlinks + paquets + services)
├── kitty/
│   └── kitty.conf               ← thème (bloc SASQUATCH-PALETTE)
├── mako/
│   └── config                   ← notifications (bloc SASQUATCH-PALETTE)
├── mimeapps.list                ← associations (code/*, mpv/*)
├── mpd/
│   └── mpd.conf                 ← lecteur local, socket user + fifo CC Capture
├── README.md
├── requirements                 ← dépendances (source de vérité, 75 paquets)
├── rofi/
│   ├── themes/
│   │   ├── sasquatch.rasi       ← thème principal (importe colors.rasi)
│   │   ├── osd.rasi             ← OSD volume/luminosité
│   │   └── colors.rasi          ← palette (retinté par theme-apply)
│   └── scripts/
│       ├── launcher.sh          ← Super seule (toggle)
│       ├── powermenu.sh         ← Super+Escape (toggle)
│       └── icon-gen.sh          ← générateur d'icônes (doc only, non bindé)
├── scripts/
│   ├── bluetooth.sh             ← CLI bluetoothctl (non bindé, utilitaire)
│   ├── bluetooth-manager.sh     ← Super+B : toggle blueman (retry anti-crash)
│   ├── brightness.sh            ← luminosité + OSD (XF86MonBrightness*)
│   ├── calc.sh                  ← Super+C : calculatrice (rofi + qalc)
│   ├── clipboard.sh             ← Super+V : presse-papier (cliphist)
│   ├── fix-suspend.sh           ← veille NVIDIA (GRUB modeset, à lancer en sudo)
│   ├── keybinds-reminder.sh     ← Super+, : aide-mémoire rofi
│   ├── osd.sh                   ← OSD générique (anti-superposition)
│   ├── screenshot.sh            ← grim + slurp (Print / Super+Print)
│   ├── theme-apply.py           ← extraction palette + patch markers
│   ├── theme-apply.sh           ← orchestrateur (flock, hook waypaper)
│   ├── volume.sh                ← volume + OSD (XF86Audio*)
│   ├── waybar-toggle.sh         ← Super+J : SIGUSR1 waybar de l'instance courante
│   └── wifi.sh                  ← CLI iwd/iwctl (non bindé, utilitaire)
├── set-wall.sh                  ← change wallpaper + applique le thème
├── settings/                    ← Panneau Settings (Super+I, Quickshell)
│   ├── settings.sh              ← toggle fenêtre
│   ├── settings.py              ← backend HTTP (port 8770, stdlib)
│   ├── main.qml + qml/          ← UI (Section, Toggle, SliderRow, ColorSwatch…)
│   └── settings.json            ← config utilisateur (sauvegarde auto)
├── starship.toml
├── themes/
│   ├── gtk/gtk-3.0/ + gtk-4.0/  ← thèmes GTK (Catppuccin/Papirus, sombre)
│   └── qt/kdeglobals            ← Qt (Papirus-Dark)
├── waybar/
│   ├── config                   ← 🇯🇵 100 % japonais (modules + tooltips)
│   ├── style.css                ← thème (bloc SASQUATCH-PALETTE)
│   ├── waybar.service           ← supervision systemd (Restart=on-failure + reload SIGUSR2)
│   ├── ui-ja.json               ← dictionnaire japonais (labels/tooltips)
│   └── scripts/
│       ├── clock-ja.py          ← heure en hiragana (module custom/clock-ja)
│       ├── wallclock-ja.py      ← horloge flottante dans le wallpaper
│       └── fastview.py          ← aperçu workspaces au survol (GTK layer-shell)
├── pl/                          ← Gestionnaire de playlist MPD (Super+P, Quickshell)
│   ├── pl.sh                    ← toggle fenêtre (pattern wp.sh, position droite injectée)
│   ├── main.qml + qml/          ← toggles random/repeat/single, liste cliquable, recherche, dossier
│   └── (backend : routes /api/playlist* dans cc/server.py)
└── wp/                          ← Sélecteur de fonds d'écran (Super+Y, Quickshell)
    ├── wp.sh                    ← toggle fenêtre (pattern cc.sh : window_open + pkill)
    ├── main.qml + qml/          ← UI grille wallpapers + bouton 🎲 aléatoire
    └── (backend : routes /api/wallpaper* dans cc/server.py)
```

---

## 🛠️ Utilitaires non bindés (usage manuel)

Scripts présents mais sans touche assignée (décision : pas de keybind pour ne
pas encombrer) — utilisables depuis un terminal :

- `scripts/wifi.sh {toggle|status|menu}` — WiFi via `iwctl` (iwd + systemd-networkd).
- `scripts/bluetooth.sh {toggle|status|menu}` — Bluetooth CLI rapide
  (`bluetoothctl`). L'UI complète (blueman) vit sur **Super+B** via
  `bluetooth-manager.sh`.
- `rofi/scripts/icon-gen.sh` — générateur d'icônes pour le launcher rofi (doc only).
- `hypr/scripts/scroll-workspace.sh up|down` — workspace bloqué 1..10 (remplace
  la boucle r±1, binds commentés dans keybinds.conf).

---

## 🎨 Thème dynamique

Le fond d'écran pilote les couleurs de **toute** l'interface : waybar, kitty,
bordures Hyprland, hyprlock, mako et rofi.

- `scripts/theme-apply.py` extrait la palette (PIL) : fond sombre teinté, texte
  clair, accent = couleur vive du fond, accent2 = complémentaire.
- `scripts/theme-apply.sh` orchestre le thème (verrou `flock`) : recharge waybar
  via `systemctl --user reload waybar` (SIGUSR2, zéro flash) si le service
  `waybar/waybar.service` est actif, sinon pkill + relance (fallback).
- Les zones retintées sont délimitées par des markers `SASQUATCH-PALETTE-BEGIN/END`
  dans 8 fichiers (waybar, kitty, hypr/general.conf, hyprlock, mako, rofi, cc/qml/Palette.qml, fastfetch/config.jsonc).
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

## 🇯🇵 UI japonaise (immersion + tooltips)

L'interface du desktop est passée en **japonais** (hiragana surtout, kanji/katakana rarement) avec tooltips au survol = épellation (yomi) + traduction française. Spec : hiragana surtout, kanji rarement (pour habituer), katakana rarement ; si kanji/katakana → yomi en hiragana ; TOUJOURS la traduction. Dictionnaire de référence : `waybar/ui-ja.json`.

- **Waybar 100 % japonais** : workspaces (ワークスペース), mpris (おんがく), cpu (シーピーユー), gpu (ジーピーユー), memory (メモリー), network (ワイファイ), battery (でんち), pulseaudio (おんりょう), brightness (あかるさ), bluetooth (ブルートゥース), clipboard (クリップボード) — labels courts + tooltips complets (yomi + trad fr).
- **Heure en hiragana** : `waybar/scripts/clock-ja.py` (module `custom/clock-ja`, return-type json) — じゅうにじ さんじゅうごふん, tooltip avec date + mini calendrier.
- **Workspaces japonais** : `hypr/conf.d/rules.conf` → `workspace = N, defaultName:いち..じゅう` (⚠️ `defaultName:` PAS `name:` — non supporté en 0.56 hyprlang). `fastview.py` affiche `ワークスペース X — espace de travail N`.
- **Horloge flottante** : `waybar/scripts/wallclock-ja.py` — heure hiragana dans le fond d'écran (layer-shell BOTTOM, sous les fenêtres), position auto dans la zone plate du wallpaper (analyse variance, grille 48×27), glisse avec animation quand le wallpaper change, couleur adaptée à la zone (35 % plus light si fond sombre). Lancé par autostart.sh.
- **Hyprlock japonais** : `hypr/scripts/lock-ja.py` (heure + date en hiragana, sortie PLAIN TEXT — ⚠️ jamais de Pango dans les `cmd[]` de hyprlock, lock cassé sinon) + `lock-media.sh` (now playing `♫ titre — artiste` depuis le CC). Police obligatoire : `Noto Sans CJK JP` (JetBrains Mono = tofu hiragana).

Dépendances : `python-numpy`, `python-cairo` (wallclock/fastview), `jq` (lock-media.sh) — inclus dans install.sh.

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
  (`~/.local/share/mpd/cc.fifo`) ne sert qu'en secours, et seulement si MPD joue
  réellement (cc/actions.py) : le volume MPD est alors temporairement forcé à
  100 % (la FIFO transporte le signal APRÈS le volume logiciel) puis restauré.
  Si rien n'est audible → réponse « non reconnu » (pas de piste mensongère).
- **Screenshot** : zone / plein écran / fenêtre (grim + slurp), copié + sauvegardé.
- Fermeture : `Escape`, bouton ✕, ou re-appui `SUPER+G` (toggle).

Architecture : `cc.sh` toggles la fenêtre `cc/qml/main.qml` (titre `Sasquatch CC` →
windowrule float + border 0 + `move 0 0` pour couvrir tout l'écran malgré la zone
réservée de waybar). Le backend `server.py` (port 8765, localhost) est un
**service systemd user `sasquatch-cc`** : permanent, `Restart=always`, logs dans
journald (`journalctl --user -u sasquatch-cc`). Il survit aux relogins
(cleanup-orphans.sh ne le tue pas : pas de signature Hyprland dans son environ)
→ fini les crashs silencieux, les cava orphelins et le « serveur injoignable ».
La fermeture du CC ne tue plus le serveur. La palette est dynamique :
`cc/qml/Palette.qml` est retinté par theme-apply.py et pollé par le CC toutes
les 2 s → le panneau suit le thème du wallpaper. Le slider volume contrôle le
volume SYSTÈME (wpctl), pas le volume MPD. Les captures masquent le CC pendant
grim/slurp puis le restaurent.

**Media sync unifié** : `cc/player.py` lit MPRIS (playerctl — Brave, mpv…), MPD
(socket user) et le pont navigateur. Les navigateurs Chromium modernes (Brave)
exposent un **MPRIS natif** quand la page utilise la MediaSession API → la source
web (`cc/browser-bridge/`) n'est utilisée qu'en FALLBACK pour les sites SANS
MediaSession (lecteurs `<video>` custom), sinon doublon (le serveur ignore la
source web quand un MPRIS est actif). `/api/music/status` est caché 500 ms pour
ne pas re-fork playerctl à chaque poll du QML. cava est **lazy** : lancé par
`/api/viz` quand le CC est visible, arrêté par un idle watchdog ~8 s après la
fermeture (le serveur permanent ne fait plus tourner ffmpeg H24).

Dépendances : `quickshell`, `mpd`, `cava`, `alsa-utils`, `songrec`, `tesseract`
(inclus dans install.sh). MPD est **isolé par utilisateur** : socket unix
`~/.local/share/mpd/socket` (pas de port TCP partagé → chaque user pilote SON
MPD, le CC n'affiche plus la musique d'un autre). mpc/ncmpc pointent dessus via
`MPD_HOST` (fish/config.fish), le CC via `cc/config.py` → `MPD_SOCKET`. MPD
expose une seule FIFO : `~/.local/share/mpd/cc.fifo` (CC Capture → finder) —
voir `mpd/mpd.conf`. L'égaliseur cava lit le monitor PipeWire (fifos par user
dans `$XDG_RUNTIME_DIR`, voir `cc/cava.py`), pas une fifo MPD.
Aucun paquet pip requis : le backend est 100 % stdlib (PEP 668 OK).

## ⚙️ Panneau Settings (SUPER+I)

Panneau de configuration **Quickshell** (`settings/`) — même architecture que le CC :
UI glass adaptative (palette dynamique pollée toutes les 2 s) + backend Python stdlib
(`settings.py`, port 8770, `settings.sh` toggle). Fenêtre titrée `Sasquatch Settings`
(windowrules float + border 0 + `move 0 0`). Sauvegarde **automatique** à chaque
modification dans `settings/settings.json`.

Sections :

- **VEILLE** — toggle hypridle (désactivation immédiate `pkill hypridle`) + timeouts
  dim / lock / écran off / suspend en minutes. Régénère `hypr/conf.d/../hypridle.conf`
  (secondes = minutes × 60) et relance/arrête hypridle selon l'état.
- **APPARENCE** — palette auto (wallpaper) ou manuelle : grille de 12 couleurs +
  champ hex pour accent/accent2 → `theme-apply.sh` re-teinte tout le desktop
  (waybar, rofi, hyprlock, GTK…).
- **HORLOGE** — format waybar (module `clock` de `waybar/config`) + hyprlock
  12/24 h + date (lus par `theme-apply.py` via settings.json).
- **RACCOURCIS** — liste complète des binds parsée depuis `hypr/keybinds.conf`
  (57 binds, `$mod` → SUPER) ; édition de la commande d'un bind → écrit dans
  `hypr/keybinds-user.conf` (overrides, dernier gagnant) + `hyprctl reload` ;
  bouton « Réinitialiser les overrides ».
- **CONTROL PANEL** — cava on/off, langue OCR (fra/eng), cover art : écrits dans
  settings.json, lus par `cc/server.py` / `cc/ocr.sh` au démarrage.
- **SYSTÈME** — gaps intérieur/extérieur, rounding, animations (patch
  `general.conf` / `decoration.conf` / `animations.conf` + `hyprctl reload`) et
  bouton « Choisir un wallpaper » (ouvre waypaper, toggle comme SUPER+Y).

## 🤖 Sidebar 愛子 Aiko (SUPER+N)

Sidebar **Quickshell** (`aiko/`) — chat IA locale avec vision : backend Python stdlib
(`aiko/server.py`, port 8780) + `llama-server` (llama.cpp CUDA, port 8781, lazy — ne
tourne que si la sidebar est ouverte). Modèle : **Qwen2.5-VL-3B-Instruct** (GGUF Q4_K_M
+ mmproj vision) — téléchargé par `aiko/setup.sh` (les `.gguf` sont gitignorés, jamais
versionnés). Fonctions : chat persistant (historique autosave), capture de zone
d'écran → vision, gestion auto du contexte (fenêtre glissante 12 messages + dédup
anti-répétition), streaming SSE. Toggle : `aiko/aiko.sh` (pidfile). Si la VRAM est
trop juste, Aiko préempte Rin (llama-server déchargé puis rechargé).

Dépendances : `llama.cpp-cuda` (AUR) + le setup du modèle — voir `aiko/setup.sh`.

## 🌙 Veille / suspend (NVIDIA)

Le gel GPU au réveil (écran noir → reboot) est corrigé par
`scripts/fix-suspend.sh` (à lancer en `sudo`) : active `nvidia_drm.modeset=1`
(GRUB), `NVreg_PreserveVideoMemoryAllocations=1` (modprobe) et les services
`nvidia-suspend` / `nvidia-resume` / `nvidia-hibernate`.
