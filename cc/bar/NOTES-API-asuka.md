# NOTES API — vérifiées par Asuka sur le poste (2026-10-31)

À lire avant d'écrire du QML. Chaque ligne a été vérifiée sur la machine, pas lue dans un blog.

## Hyprland (Quickshell 0.3.2) — `import Quickshell.Hyprland`

- `Hyprland.toplevels` : liste de `HyprlandToplevel`.
- **`HyprlandToplevel` n'expose PAS `class` / `title` / `address` directement.**
  Les données IPC sont dans **`lastIpcObject`** (objet dynamique) :
  `toplevel.lastIpcObject.class`, `.title`, `.address`, `.workspace.name`, `.floating`,
  `.fullscreen`, `.mapped`, `.xwayland`. Pour la surface Wayland : `toplevel.wayland`.
- `Hyprland.workspaces` (liste de `HyprlandWorkspace`, avec `.id` / `.name`),
  `Hyprland.focusedWorkspace`, `Hyprland.focusedMonitor`, `Hyprland.monitors`.
- Passer un workspace au premier plan : `hyprctl dispatch workspace N` (via `Quickshell.Io.Process`).

## Modules réellement présents dans ce build

```
Quickshell.Hyprland        Hyprland.*
Quickshell.Networking      Network*, Wifi*, Wired*   ← binde NetworkManager
Quickshell.Bluetooth       Bluetooth*
Quickshell.Services.Mpris / UPower / Notifications / SystemTray / Pipewire / Pam / Greetd / Polkit
```

**Piège** : `Quickshell.Networking` parle à NetworkManager, or **NM est inactif** ici
(`systemctl is-active NetworkManager` → inactive). Le Wi-Fi est piloté par
**iwd + systemd-networkd** (`wlan0` = 192.168.1.44). Donc : pas de SSID/état via ce module
→ lire le backend CC, ou `iwctl station wlan0 show`.

## Backend CC (service déjà actif)

```
GET  /api/palette        bg bgSolid card cardSolid text textDim accent accent2 overlay good warn hot
GET  /api/stats          cpu cores load ram{used,total,pct} gpu{util,vram_*,temp} cpu_temp net{up,down,iface} uptime
GET  /api/system/volume      {"volume":41,"muted":false}          ← PLAT, pas imbriqué
GET  /api/system/brightness
GET  /api/music/status   POST /api/music/toggle|next|prev|seek|stop
```

`net.up` / `net.down` sont déjà calculés (delta `/proc/net/dev`, Ko/s) : ne pas refaire la sonde.
Les routes POST ne répondent pas en GET (404 trompeur) — lire `cc/server.py` avant d'appeler.

## Palette

`GET /api/palette` lit `cc/qml/Palette.qml`, régénéré par `theme-apply.py` à chaque wallpaper.
Accent actuel `#dddddd` sur wallpaper monochrome → relever vers `text` si trop proche du fond.

## Divers

- `rofi` en `/usr/bin/rofi`, `makoctl mode do-not-disturb` disponible, `grim` pour les captures.
- `qmllint` est le seul contrôle statique fiable (pas de `qmlformat --check`).
- `PanelWindow` (layer surface) n'apparaît jamais dans `hyprctl clients` → `hyprctl layers`.
