#!/bin/bash
# keybinds-reminder.sh — rappel des raccourcis clavier (Super + virgule)
#
# Affiche la liste des raccourcis du dotfile dans rofi (menu simple, non
# interactif — juste un aide-mémoire visuel). Bindé sur Super+virgule.
# Le launcher rofi vit sur Super seule (release).

ROFI_THEME="$HOME/.config/rofi/themes/sasquatch.rasi"

LIST="Super          → Launcher rofi (apps)
Super + ,        → Aide-mémoire des raccourcis (ce menu)
Super + T        → Terminal (kitty)
Super + W        → Navigateur Brave (extension CC)
Super + E        → Dolphin (fichiers)
Super + O        → Code / éditeur
Super + B        → Bluetooth (toggle blueman-manager)
Super + G        → Control Center (Quickshell)
Super + I        → Panneau Settings
Super + N        → Sidebar 愛子 Aiko (chat IA)
Super + C        → Calculatrice rofi (qalc)
Super + V        → Presse-papier (cliphist)
Super + F        → Fullscreen (complet)
Super + D        → Agrandir la fenêtre (internal, barre visible)
Super + P        → Pseudo-tiling
Super + J        → Masquer la waybar (toggle)
Super + R        → Toggle split
Super + Shift+V  → Libre / flottant (togglefloating)
Super + Q        → Fermer la fenêtre (killactive)
Super + L        → Verrouiller (hyprlock)
Super + Escape   → Powermenu
Super + Print    → Capture zone
Print            → Capture plein écran
Super + Z/S      → Focus haut/bas
Super + Shift+Z/S/Q/D → Déplacer fenêtre haut/bas/gauche/droite
Super + Ctrl+Z/S/Q/D  → Resize fenêtre
Super + Gauche/Droite → Workspace précédent/suivant
Super + 1..5     → Workspaces 1..5
Super + Shift+1..5    → Déplacer fenêtre vers workspace
Super + Y        → Waypaper (fond d'écran)
Molette (Super)  → Workspace suivant/précédent
Ctrl+Shift+1     → IME japonais (fcitx5/Mozc)"

rofi -dmenu -theme "$ROFI_THEME" -p "  ⌨️  Super+" -no-custom -i <<< "$LIST"
