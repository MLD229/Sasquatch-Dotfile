-- hyprland.lua — Sasquatch-Dotfile (Hyprland >= 0.57, format Lua)
-- Genere depuis les .conf par hypr-migrate, assemble en un seul fichier.
-- Les .conf d'origine sont conserves tels quels (rien supprime).
-- ═══════ ENVIRONNEMENT (conf.d/env.conf) ═══════
--
--

hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("__GL_GSYNC_ALLOWED", "1")
hl.env("__GL_VRR_ALLOWED", "1")
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")
hl.env("GTK_THEME", "catppuccin-mocha-blue-standard+default")
hl.env("GTK_APPLICATION_PREFER_DARK_THEME", "1")
hl.env("GTK_IM_MODULE", "fcitx")
hl.env("QT_IM_MODULE", "fcitx")
hl.env("XMODIFIERS", "@im=fcitx")
hl.env("SDL_IM_MODULE", "fcitx")
hl.env("GLFW_IM_MODULE", "ibus")

-- ═══════ MONITEURS (conf.d/monitors.conf) ═══════
-- monitors.conf : monitor = ,preferred,auto,1  → regle JOKER (output vide = tous
-- les ecrans), mode preferred, position auto, scale 1.
-- L'ancienne ligne ({ output = "eDP-1", scale = 1 }) ne concernait que l'ecran
-- interne : ni mode ni position, et aucune regle de repli pour un ecran HDMI/DP.

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- ═══════ GENERAL (conf.d/general.conf) ═══════
--
--

hl.config({
    general = {
        allow_tearing = false,
        border_size = 2,
        col = {
            active_border = { colors = { "rgba(460918ee)", "rgba(596371ee)" }, angle = 45 },
            inactive_border = "rgba(444444aa)",
        },
        gaps_in = 5,
        gaps_out = 10,
        layout = "dwindle",
        resize_on_border = true,
    },
    misc = {
        close_special_on_empty = false,
    },
})

-- ═══════ DECORATION (conf.d/decoration.conf) ═══════
--
--

hl.config({
    decoration = {
        active_opacity = 0.92,
        dim_inactive = true,
        dim_special = 0,
        dim_strength = 0.1,
        fullscreen_opacity = 1.0,
        inactive_opacity = 0.82,
        rounding = 12,
        shadow = {
            color = "rgba(00000066)",
            color_inactive = "rgba(00000033)",
            enabled = true,
            range = 20,
            render_power = 3,
        },
    },
})

-- ═══════ FLOU (conf.d/blur.conf) ═══════
--
--

hl.config({
    decoration = {
        blur = {
            brightness = 0.85,
            contrast = 0.9,
            enabled = true,
            ignore_opacity = true,
            new_optimizations = true,
            noise = 0.02,
            passes = 3,
            size = 8,
            vibrancy = 0.2,
            vibrancy_darkness = 0.3,
            xray = true,
        },
    },
})

-- ═══════ ANIMATIONS (conf.d/animations.conf) ═══════
--
--

hl.config({
    animations = {
        enabled = true,
    },
})

hl.curve("md3_decel", {
    type = "bezier",
    points = { {0.05, 0.7}, {0.1, 1.0} }
})
hl.curve("md3_accel", {
    type = "bezier",
    points = { {0.3, 0.0}, {0.8, 0.15} }
})
hl.curve("menu_decel", {
    type = "bezier",
    points = { {0.1, 1.0}, {0.0, 1.0} }
})
hl.curve("menu_accel", {
    type = "bezier",
    points = { {0.38, 0.04}, {1.0, 0.07} }
})
hl.curve("linear", {
    type = "bezier",
    points = { {0.0, 0.0}, {1.0, 1.0} }
})
hl.curve("md3_standard", {
    type = "bezier",
    points = { {0.2, 0.0}, {0.0, 1.0} }
})
hl.curve("overshot", {
    type = "bezier",
    points = { {0.05, 0.9}, {0.1, 1.1} }
})
hl.curve("crazyshot", {
    type = "bezier",
    points = { {0.1, 1.5}, {0.76, 0.92} }
})
hl.curve("hyprnostretch", {
    type = "bezier",
    points = { {0.05, 0.9}, {0.1, 1.0} }
})
hl.curve("easeInOutCirc", {
    type = "bezier",
    points = { {0.85, 0.0}, {0.15, 1.0} }
})
hl.curve("easeOutCirc", {
    type = "bezier",
    points = { {0.0, 0.55}, {0.45, 1.0} }
})
hl.curve("easeOutExpo", {
    type = "bezier",
    points = { {0.16, 1.0}, {0.3, 1.0} }
})
hl.curve("softAcDecel", {
    type = "bezier",
    points = { {0.26, 0.26}, {0.15, 1.0} }
})
hl.curve("md2", {
    type = "bezier",
    points = { {0.4, 0.0}, {0.2, 1.0} }
})

hl.animation({
    leaf = "windows",
    enabled = true,
    speed = 3.0,
    bezier = "md3_decel",
    style = "popin 60%",
})
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 3.0,
    bezier = "md3_decel",
    style = "popin 60%",
})
hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 3.0,
    bezier = "md3_accel",
    style = "popin 60%",
})
hl.animation({
    leaf = "border",
    enabled = true,
    speed = 10.0,
    bezier = "default",
})
hl.animation({
    leaf = "fade",
    enabled = true,
    speed = 3.0,
    bezier = "md3_decel",
})
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 3.0,
    bezier = "menu_decel",
    style = "slide",
})
hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 1.6,
    bezier = "menu_accel",
})
hl.animation({
    leaf = "fadeLayersIn",
    enabled = true,
    speed = 2.0,
    bezier = "menu_decel",
})
hl.animation({
    leaf = "fadeLayersOut",
    enabled = true,
    speed = 4.5,
    bezier = "menu_accel",
})
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 7.0,
    bezier = "menu_decel",
    style = "slide",
})
hl.animation({
    leaf = "specialWorkspace",
    enabled = true,
    speed = 3.0,
    bezier = "md3_decel",
    style = "slidevert",
})

-- ═══════ DWRINDLE (conf.d/layout.conf) ═══════
--
--

hl.config({
    dwindle = {
        preserve_split = true,
        smart_resizing = true,
        smart_split = false,
    },
})

-- ═══════ ENTREE (conf.d/input.conf) ═══════
--
--

hl.config({
    input = {
        accel_profile = "flat",
        follow_mouse = 1,
        kb_layout = "fr",
        kb_options = "caps:escape",
        kb_variant = "azerty",
        sensitivity = 0.0,
        touchpad = {
            drag_lock = true,
            natural_scroll = true,
            ["tap_to_click"] = true,
        },
    },
})

-- ═══════ MISC + GESTURES (conf.d/misc.conf) ═══════
--
--

hl.config({
    misc = {
        animate_manual_resizes = true,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        enable_swallow = true,
        focus_on_activate = false,
        key_press_enables_dpms = true,
        mouse_move_enables_dpms = true,
        swallow_regex = "^(kitty)$",
    },
})

-- gestes trackpad (bloc gestures de misc.conf, perdu par le convertisseur)
-- workspace_swipe_use_r : coherent avec SUPER+fleches (relatif)
-- workspace_swipe_invert : swipe a droite = workspace precedent
hl.config({
    gestures = {
        workspace_swipe_use_r = true,
        workspace_swipe_invert = true,
        workspace_swipe_create_new = true,
        workspace_swipe_forever = true,
    },
})

-- ═══════ REGLES FENETRES / LAYERS / WORKSPACES (conf.d/rules.conf) ═══════
-- Traduction manuelle : le convertisseur ne comprend pas la syntaxe
-- "windowrule = match:<prop> <regex>, <effet>" de Hyprland 0.56.

local m = hl.window_rule
m({ name = "pavucontrol", match = { class = "^(pavucontrol)$" }, float = true, center = true, size = "800 600" })
m({ name = "blueman", match = { class = "^(blueman-manager)$" }, float = true, center = true, size = "900 650" })
m({ name = "nm-connection", match = { class = "^(nm-connection-editor)$" }, float = true })
m({ name = "file-roller", match = { class = "^(file-roller)$" }, float = true })
m({ name = "pip", match = { title = "^(Picture-in-Picture)$" }, float = true })
m({ name = "obsidian", match = { class = "^(md\\.obsidian\\.Obsidian)$" }, float = true, center = true, size = "1000 700" })

-- opacite
m({ name = "kitty-opacity", match = { class = "^(kitty)$" }, opacity = "0.92 0.82 override" })
m({ name = "firefox-opacity", match = { class = "^(firefox)$" }, opacity = "1.0 1.0 override" })

-- overlays Quickshell (plein ecran, position 0,0, pas de bord ni d'anim)
for _, title in ipairs({ "Sasquatch CC", "Sasquatch Settings", "Sasquatch Wallpaper", "Sasquatch Playlist" }) do
    local rule = {
        name = "overlay-" .. title:gsub("%s", "-"),
        match = { title = "^(" .. title:gsub("%p", "%%%0") .. ")$" },
        float = true,
        border_size = 0,
        rounding = 0,
        no_anim = true,
    }
    -- rules.conf ne met `move 0 0` que sur CC / Settings / Wallpaper.
    -- Pour Playlist la position est injectee par pl/pl.sh (panneau a droite) :
    -- un move 0 0 la collerait en haut a gauche.
    if title ~= "Sasquatch Playlist" then
        rule.move = "0 0"
    end
    m(rule)
end

-- application sur un workspace dedie
m({ name = "firefox-ws2", match = { class = "^(firefox)$" }, workspace = "2" })
m({ name = "discord-ws3", match = { class = "^(discord)$" }, workspace = "3" })
m({ name = "spotify-ws4", match = { class = "^(spotify)$" }, workspace = "4" })
-- fix tearing NVIDIA
m({ name = "steam-immediate", match = { class = "^(steam_app_.*)$" }, immediate = true })

-- layer rules (flou derriere aiko et rofi)
hl.layer_rule({ name = "aiko-blur", match = { namespace = "^(aiko)$" }, blur = true })
hl.layer_rule({ name = "rofi-blur", match = { namespace = "^(rofi)$" }, blur = true })

-- workspace rules
hl.workspace_rule({ workspace = "special:subpage", gaps_out = 16, gaps_in = 6 })
for i = 1, 10 do
    hl.workspace_rule({ workspace = tostring(i), persistent = true })
end

-- ═══════ KEYBINDS (keybinds.conf) ═══════
-- Traduction manuelle : dispatchers hl.dsp.* de Hyprland 0.57.
local mod = "SUPER"

-- Essentiels
hl.bind(mod .. " + t", hl.dsp.exec_cmd("kitty"))
hl.bind(mod .. " + b", hl.dsp.exec_cmd("~/.config/scripts/bluetooth-manager.sh"))
hl.bind(mod .. " + e", hl.dsp.exec_cmd("dolphin"))
hl.bind(mod .. " + o", hl.dsp.exec_cmd("code"))
hl.bind(mod .. " + y", hl.dsp.exec_cmd("~/.config/wp/wp.sh"))
hl.bind(mod .. " + p", hl.dsp.exec_cmd("~/.config/pl/pl.sh"))
hl.bind(mod .. " + w", hl.dsp.exec_cmd("brave --load-extension=~/.config/cc/browser-bridge"))
hl.bind(mod .. " + H", hl.dsp.exec_cmd("~/.config/scripts/obsidian-toggle.sh"))
hl.bind(mod .. " + S", hl.dsp.exec_cmd("~/.config/subpage/subpage.sh"))
hl.bind(mod .. " + ALT + S", hl.dsp.exec_cmd("~/.config/subpage/send.sh"))
-- Super seule (relachement) = launcher rofi
hl.bind(mod .. " + Super_L", hl.dsp.exec_cmd("pkill rofi || ~/.config/rofi/scripts/launcher.sh"), { release = true })
hl.bind(mod .. " + comma", hl.dsp.exec_cmd("pkill rofi || ~/.config/scripts/keybinds-reminder.sh"))
hl.bind(mod .. " + L", hl.dsp.exec_cmd("hyprlock"))
hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + SHIFT + M", hl.dsp.exit())
hl.bind(mod .. " + Escape", hl.dsp.exec_cmd("~/.config/rofi/scripts/powermenu.sh"))

-- Fenetres
-- keybinds.conf:29 `fullscreen` sans argument = TOGGLE plein ecran classique
-- (mode 0). Sans action explicite le dispatch est un `set` : la fenetre passait
-- en plein ecran mais ne revenait jamais (2e appui sans effet).
hl.bind(mod .. " + F", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind(mod .. " + V", hl.dsp.exec_cmd("~/.config/scripts/clipboard.sh"))
hl.bind(mod .. " + SHIFT + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + SHIFT + P", hl.dsp.window.pseudo())
hl.bind(mod .. " + R", hl.dsp.layout("togglesplit"))
hl.bind(mod .. " + J", hl.dsp.exec_cmd("~/.config/cc/bar/bar.sh"))
hl.bind(mod .. " + U", hl.dsp.exec_cmd("~/.config/scripts/calc.sh"))

-- Focus (ZQSD azerty)
hl.bind(mod .. " + Z", hl.dsp.focus({ direction = "up" }))
-- Super+D : agrandissement interne (barre visible) = fullscreen mode 1
hl.bind(mod .. " + D", hl.dsp.window.fullscreen({ action = "toggle", mode = "maximized" }))

-- Deplacement de fenetre
hl.bind(mod .. " + SHIFT + Z", hl.dsp.window.move({ direction = "up" }))
hl.bind(mod .. " + SHIFT + S", hl.dsp.window.move({ direction = "down" }))
hl.bind(mod .. " + SHIFT + Q", hl.dsp.window.move({ direction = "left" }))
hl.bind(mod .. " + SHIFT + D", hl.dsp.window.move({ direction = "right" }))

-- Workspaces (touches azerty 1..5)
local ws_keys = { "ampersand", "eacute", "quotedbl", "apostrophe", "parenleft" }
for i, key in ipairs(ws_keys) do
    hl.bind(mod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i, follow = true }))
end

-- Fleches : workspaces relatifs, SANS debordement.
-- En 0.57 `focus({workspace = "e-1"})` depuis le workspace 1 saute au 10
-- (comportement cyclique) : plus de « blockage » au premier. On borne donc
-- explicitement entre WS_MIN et WS_MAX, et on ne dispatche rien au bord.
local WS_MIN, WS_MAX = 1, 10
local function ws_clamp(delta)
    return function()
        local cur = hl.get_active_workspace()
        local id = cur and cur.id or WS_MIN
        local target = math.max(WS_MIN, math.min(WS_MAX, id + delta))
        if target ~= id then
            hl.dispatch(hl.dsp.focus({ workspace = target }))
        end
    end
end
local function win_clamp(delta)
    return function()
        local cur = hl.get_active_workspace()
        local id = cur and cur.id or WS_MIN
        local target = math.max(WS_MIN, math.min(WS_MAX, id + delta))
        if target ~= id then
            hl.dispatch(hl.dsp.window.move({ workspace = target, follow = true }))
        end
    end
end
hl.bind(mod .. " + Left", ws_clamp(-1))
hl.bind(mod .. " + Right", ws_clamp(1))
hl.bind(mod .. " + SHIFT + Left", win_clamp(-1))
hl.bind(mod .. " + SHIFT + Right", win_clamp(1))

-- Molette : workspace suivant / precedent (direction inversee), bornee aussi
hl.bind(mod .. " + mouse_down", ws_clamp(1))
hl.bind(mod .. " + mouse_up", ws_clamp(-1))

-- Gestures trackpad
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })

-- Resize (binde = repetition)
hl.bind(mod .. " + CTRL + D", hl.dsp.window.resize({ x = 30, y = 0 }), { repeating = true })
hl.bind(mod .. " + CTRL + Q", hl.dsp.window.resize({ x = -30, y = 0 }), { repeating = true })
hl.bind(mod .. " + CTRL + Z", hl.dsp.window.resize({ x = 0, y = -30 }), { repeating = true })
hl.bind(mod .. " + CTRL + S", hl.dsp.window.resize({ x = 0, y = 30 }), { repeating = true })

-- Media / son
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("~/.config/scripts/volume.sh up"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("~/.config/scripts/volume.sh down"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("~/.config/scripts/volume.sh mute"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("~/.config/hypr/scripts/media-ctl.sh toggle"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("~/.config/hypr/scripts/media-ctl.sh next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("~/.config/hypr/scripts/media-ctl.sh prev"), { locked = true })

-- Luminosite (bindel = repeat + locked)
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("~/.config/scripts/brightness.sh up"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("~/.config/scripts/brightness.sh down"), { locked = true, repeating = true })

-- Screenshot
hl.bind("Print", hl.dsp.exec_cmd("~/.config/scripts/screenshot.sh full"))
hl.bind(mod .. " + Print", hl.dsp.exec_cmd("~/.config/scripts/screenshot.sh area"))

-- Panneaux
hl.bind(mod .. " + G", hl.dsp.exec_cmd("~/.config/cc/cc.sh"))
hl.bind(mod .. " + X", hl.dsp.exec_cmd("~/.config/scripts/showdesktop.sh"))
hl.bind(mod .. " + C", hl.dsp.exec_cmd("~/.config/cc/sidebar/sidebar.sh"))
hl.bind(mod .. " + I", hl.dsp.exec_cmd("~/.config/settings/settings.sh"))
hl.bind(mod .. " + N", hl.dsp.exec_cmd("~/.config/aiko/aiko.sh"))

-- Souris : deplacer / redimensionner
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- ═══════ OVERRIDES UTILISATEUR (générés) ═══════
-- keybinds-user.lua : surcharges de binds + options système du panneau Settings
-- (réécrit en entier par settings/settings.py, puis hyprctl reload).

-- ═══════ AUTOSTART (exec-once de hyprland.conf) ═══════
hl.on("hyprland.start", function()
    hl.exec_cmd("~/.config/hypr/scripts/autostart.sh")
end)

-- ═══════ FICHIERS GÉNÉRÉS (absents tolérés) ═══════
-- theme.lua         : bordures de la palette wallpaper (scripts/theme-apply.py)
-- keybinds-user.lua : surcharges du panneau Settings (settings/settings.py)
-- pcall : premier login, ou fichier supprimé → on continue sans.
local H = (os.getenv("HOME") or "/home/momo") .. "/.config/hypr/"
pcall(dofile, H .. "theme.lua")
pcall(dofile, H .. "keybinds-user.lua")
