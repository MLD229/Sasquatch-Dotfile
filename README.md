<div align="center">
    <h1>【 Sasquatch-Dotfile 】</h1>
    <h3>Hyprland dotfiles — Arch Linux · thème adaptatif · immersion japonaise</h3>
</div>

<div align="center">

![](https://img.shields.io/github/last-commit/MLD229/Sasquatch-Dotfile?style=for-the-badge&color=FF9E64&logoColor=D9E0EE&labelColor=292324)
![](https://img.shields.io/github/stars/MLD229/Sasquatch-Dotfile?style=for-the-badge&logo=andela&color=FFB686&logoColor=D9E0EE&labelColor=292324)
[![](https://img.shields.io/github/repo-size/MLD229/Sasquatch-Dotfile?color=CAC992&label=SIZE&logo=googledrive&style=for-the-badge&logoColor=D9E0EE&labelColor=292324)](https://github.com/MLD229/Sasquatch-Dotfile)
![](https://img.shields.io/github/issues/MLD229/Sasquatch-Dotfile?style=for-the-badge&color=8BD5CA&logoColor=D9E0EE&labelColor=292324)

</div>

<div align="center">
    <h2>• overview •</h2>
</div>

<details>
  <summary>Notable features</summary>

  - **Thème adaptatif** — le fond d'écran pilote toutes les couleurs (waybar, kitty, bordures, hyprlock, mako, rofi, panneaux)
  - **Immersion japonaise** — waybar 100 % hiragana, workspaces `いち`〜`じゅう`, horloge flottante, hyprlock en japonais
  - **Panneaux Quickshell faits main** — Control Center (perf + musique + égaliseur), Settings, Sidebar IA 愛子, Playlist MPD
  - **IA locale avec vision (en développement)** — llama.cpp CUDA + Qwen2.5-VL, capture de zone → description
  - **MPD local** — socket user isolé, now-playing partout, cava synchronisé, Shazam intégré
  - **Raccourcis éditables** depuis le panneau Settings (57 binds, sans toucher aux fichiers)

</details>

<details>
  <summary>Installation</summary>

```bash
git clone https://github.com/MLD229/Sasquatch-Dotfile.git
cd Sasquatch-Dotfile
bash install.sh
```

Redémarre ta session après l'installation.

<details>
  <summary>⚠️ Réseau (machine neuve)</summary>

`install.sh` active `systemd-networkd` + `iwd`, mais il faut un fichier
`/etc/systemd/network/*.network` pour obtenir une IP. Exemple WiFi minimal :

```ini
# /etc/systemd/network/20-wlan.network
[Match]
Name=wlan0
[Network]
DHCP=yes
```

Sans ça : `iwctl station wlan0 connect <SSID>` associe le WiFi mais aucune IP n'est attribuée.
</details>

</details>

<details>
  <summary>Software overview</summary>

| Software | Purpose |
| ------------- | ------------- |
| [Hyprland](https://github.com/hyprwm/Hyprland) | The compositor (window manager) |
| [Waybar](https://github.com/Alexays/Waybar) | Status bar — 🇯🇵 100 % japonais, toggle FR |
| [Quickshell](https://github.com/Quickshell/Quickshell) | Widget system — Control Center, Settings, Aiko, Playlist, wallpaper picker |
| [Rofi](https://github.com/lbonn/rofi) | Launcher, powermenu, OSD, aide-mémoire |
| [Mako](https://github.com/emersion/mako) | Notifications |
| [Fcitx5 + Mozc](https://github.com/fcitx/fcitx5) | Japanese input method (`Ctrl+Shift+1`) |
| [Kitty + Fish + Starship](https://github.com/kovidgoyal/kitty) | Terminal / Shell / Prompt |
| [Hyprlock / Hypridle](https://github.com/hyprwm/hyprlock) | Lock screen (🇯🇵 hiragana + musique) / idle |
| [MPD + cava + songrec](https://musicpd.org/) | Local music server + equalizer + Shazam |
| [OpenTabletDriver](https://github.com/OpenTabletDriver/OpenTabletDriver) | Tablet (service user) |

- Liste exhaustive des dépendances : `requirements` (source de vérité, synchro avec install.sh).

</details>

<div align="center">
    <h2>• screenshots •</h2>
</div>

### 🎨 Thème adaptative (v2)

**Le wallpaper pilote toute l'interface — horloge flottante... 
![image](screenshots/adaptative-v2-betta.png)

**Kitty + fastfetch — terminal et prompt synchronisés sur la palette sombre**
![image](screenshots/adaptative-v2-fastfetch.png)

### 🧡 Ambiance

**Waybar  — barre épurée aux teintes adaptatif, intégrée au fond**
![image](screenshots/ambre-waybar.png)

**Terminal re-teinté — fastfetch affiche la palette active (bloc SASQUATCH-PALETTE)**
![image](screenshots/ambre-fastfetch.png)

**Sélecteur de fonds d'écran (`Super+Y`) — grille + bouton 🎲 ; changer l'image re-teinte toute l'interface**
![image](screenshots/ambre-wallpaper-picker.png)

**Panneau Settings (`Super+I`) — veille, apparence, horloge, raccourcis éditables, système**
![image](screenshots/ambre-settings.png)

### 🇯🇵 Immersion japonaise

**Workspaces japonais — `いち`〜`じゅう` renommés à chaud, date du jour en hiragana**
![image](screenshots/japonais-piliers.png)

**Waybar 100 % japonais — labels hiragana + tooltips avec épellation (yomi) et traduction française**
![image](screenshots/japonais-waybar.png)

### 🛠️ Widgets & outils

**Control Center (`Super+G`) — dashboard temps réel CPU/RAM/GPU/VRAM, now-playing MPD avec pochette, égaliseur cava synchronisé**
![image](screenshots/cc-dashboard.png)

**Control Center compact — contrôles musique + infos système au premier coup d'œil**
![image](screenshots/cc-compact.png)

**Dolphin + playlist MPD (`Super+P`) — playlist cliquable, toggles random/repeat/single, recherche**
![image](screenshots/dolphin-playlist.png)

**Aide-mémoire des raccourcis (`Super+,`) — tous les binds dans un launcher rofi**
![image](screenshots/rofi-raccourcis.png)

<details>
  <summary>Keybinds</summary>

Source de vérité : `hypr/keybinds.conf` (éditable via Settings → RACCOURCIS).

<details>
  <summary>Here's an image, just in case:</summary>

![image](screenshots/rofi-raccourcis.png)

</details>

| Touche | Action |
|--------|--------|
| **Super** (seule) | Launcher rofi (toggle) |
| **Super + ,** | Aide-mémoire des raccourcis (toggle) |
| **Super + T / W / E / O** | Terminal / Brave / Dolphin / VS Code |
| **Super + G / I / N** | Control Center / Settings / Sidebar Aiko |
| **Super + C / V** | Calculatrice rofi (qalc) / Presse-papier (cliphist) |
| **Super + B** | Bluetooth (blueman, wrapper anti-crash) |
| **Super + L / Escape** | Verrouiller / Powermenu |
| **Super + Q / Shift+M** | Fermer la fenêtre / Quitter la session |
| **Super + F / D** | Fullscreen / Agrandir |
| **Super + P / Shift+P** | Playlist MPD / Pseudo-tiling |
| **Super + R** | Toggle split |
| **Super + J** | Masquer/afficher la waybar |
| **Super + Shift+V** | Libre/flottant |
| **Super + S / Alt+S** | Scratchpad : toggle / envoyer dedans |
| **Super + H** | Obsidian (toggle, float) |
| **Super + Z / Shift+Z / Ctrl+Z** | Focus / déplacer / resize (Z,S,Q,D = haut,bas,gauche,droite) |
| **Super + 1..5 / Shift+1..5** | Workspace / déplacer vers workspace |
| **Super + ←/→ / molette** | Workspace précédent/suivant (boucle 1↔10) |
| **Super + Y** | Sélecteur de fonds d'écran (thème dynamique) |
| **Ctrl+Shift+1** | Bascule IME japonais |
| **XF86Audio\*** / **XF86MonBrightness\*** | Volume / luminosité + OSD |
| **Print / Super+Print** | Screenshot plein écran / zone |

</details>

<details>
  <summary>Thème dynamique</summary>

Le fond d'écran pilote les couleurs de **toute** l'interface : waybar, kitty,
bordures Hyprland, hyprlock, mako, rofi, CC, settings, fastfetch.

- `scripts/theme-apply.py` extrait la palette (PIL) — fond sombre teinté, texte
  clair, accent = couleur vive du fond, accent2 = complémentaire.
- `scripts/theme-apply.sh` orchestre (verrou `flock`, rechargement waybar sans flash).
- Zones retintées entre markers `SASQUATCH-PALETTE-BEGIN/END` dans 8 fichiers.
- **Hook auto** : `~/.config/waypaper/config.ini` →
  `post_command = ~/.config/scripts/theme-apply.sh $wallpaper`
- Manuelle : `./set-wall.sh <image>` change le wallpaper ET applique le thème.

</details>

<details>
  <summary>Modules Quickshell</summary>

**🎛️ Control Center — `Super+G`**
Dashboard temps réel : CPU/RAM/GPU/VRAM/températures/réseau, now-playing MPD
(pochette, seek, contrôles), **égaliseur cava synchronisé** sur la sortie audio
réelle, **Music Finder** (8 s de capture PipeWire → Shazam via songrec),
screenshot (zone/plein écran/fenêtre). Backend Python 100 % stdlib, service
systemd user permanent (`sasquatch-cc`, logs : `journalctl --user -u sasquatch-cc`).

**⚙️ Panneau Settings — `Super+I`**
Sections : **VEILLE** (timeouts hypridle), **APPARENCE** (palette auto/manuelle),
**HORLOGE** (format waybar + hyprlock), **RACCOURCIS** (57 binds éditables →
overrides dans `keybinds-user.conf`), **CONTROL PANEL**, **SYSTÈME** (gaps,
rounding, animations). Sauvegarde automatique dans `settings/settings.json`.

**🤖 Sidebar 愛子 Aiko — `Super+N`**
Chat IA **locale** avec vision : llama-server (llama.cpp CUDA) + Qwen2.5-VL-3B
GGUF, backend stdlib (SSE), capture de zone → vision, historique autosave.
Lazy : ne tourne que si la sidebar est ouverte. Setup : `aiko/setup.sh`.

**🎵 Playlist MPD — `Super+P`**
Toggles random/repeat/single, liste cliquable, recherche/ajout, dossier musique.
MPD isolé par utilisateur (socket unix, pas de port TCP partagé).

</details>

<details>
  <summary>Structure</summary>

```
Sasquatch-Dotfile/
├── aiko/          ← Sidebar 愛子 — chat IA locale + vision (Super+N)
│                   backend Python stdlib (8780) + llama-server CUDA (8781, lazy)
├── cc/            ← Control Center (Super+G) : dashboard perf, now-playing,
│                   Shazam, screenshot ; service user permanent `sasquatch-cc`
├── fastfetch/     ← logo + palette dynamique (bloc SASQUATCH-PALETTE)
├── fcitx5/        ← IME japonais (bascule Ctrl+Shift+1)
├── fish/          ← config.fish (alias, MPD_HOST socket user)
├── hypr/          ← hyprland.conf → conf.d/, keybinds.conf, hypridle/hyprlock/
│                   hyprpaper.conf + scripts (autostart, lock-ja, media-ctl…)
├── install.sh     ← installateur (symlinks + paquets + services)
├── kitty/ mako/   ← thèmes (bloc SASQUATCH-PALETTE)
├── mpd/           ← lecteur local, socket user + fifo CC Capture
├── pl/            ← Playlist MPD (Super+P) : random/repeat/single, recherche
├── rofi/          ← themes/ (sasquatch, osd, colors) + scripts (launcher, powermenu)
├── scripts/       ← theme-apply, volume, brightness, screenshot, calc, clipboard…
├── settings/      ← Panneau Settings (Super+I) : veille, apparence, horloge,
│                   raccourcis, système — sauvegarde auto
├── starship.toml
├── themes/        ← GTK (Catppuccin/Papirus) + Qt (Papirus-Dark)
├── waybar/        ← config 🇯🇵 japonais + style (palette) + scripts (clock-ja,
│                   wallclock-ja, fastview) ; service systemd user
└── wp/            ← Sélecteur de fonds d'écran (Super+Y) : grille + 🎲 aléatoire
```

</details>

<details>
  <summary>Veille / suspend (NVIDIA)</summary>

Gel GPU au réveil corrigé par `scripts/fix-suspend.sh` (à lancer en `sudo`) :
`nvidia_drm.modeset=1` (GRUB), `NVreg_PreserveVideoMemoryAllocations=1`
(modprobe) et services `nvidia-suspend` / `nvidia-resume` / `nvidia-hibernate`.

</details>
