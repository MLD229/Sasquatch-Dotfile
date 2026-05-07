#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Sasquatch · Icon & Name Generator
#  Parcourt les fichiers .desktop, génère un menu rofi
#  avec icône auto-détectée + nom mis en forme
# ─────────────────────────────────────────────────────────────
#  Utilisation :
#    ./icon-gen.sh | rofi -dmenu -show-icons -theme sasquatch.rasi
# ─────────────────────────────────────────────────────────────

ICON_THEME="${ICON_THEME:-Papirus-Dark}"
ICON_SIZE="${ICON_SIZE:-32}"

# ── Nerd Font glyphs de fallback par catégorie ────────────────
declare -A CATEGORY_ICONS=(
    ["AudioVideo"]="󰝚"
    ["Audio"]="󰕾"
    ["Video"]="󰕧"
    ["Development"]="󰅨"
    ["Education"]="󱓇"
    ["Game"]="󰮗"
    ["Graphics"]="󰋩"
    ["Network"]="󰀂"
    ["Office"]="󰈙"
    ["Science"]="󰭒"
    ["Settings"]="󰒓"
    ["System"]="󰌢"
    ["Utility"]="󰏖"
    ["FileManager"]="󰉖"
    ["TerminalEmulator"]=""
    ["WebBrowser"]="󰖟"
    ["TextEditor"]="󰤌"
    ["Archiving"]="󰛫"
    ["Accessibility"]="󱋬"
    [""]="󰣆"   # fallback générique
)

# ── Résolution d'icône via gtk-query-settings ou find ─────────
resolve_icon() {
    local name="$1"
    [[ -z "$name" ]] && echo "" && return

    # Cherche d'abord dans le thème choisi
    local path
    path=$(find /usr/share/icons/"$ICON_THEME" \
                /usr/share/icons/hicolor \
                /usr/share/pixmaps \
                -name "${name}.png" -o -name "${name}.svg" \
                2>/dev/null | head -1)

    if [[ -n "$path" ]]; then
        echo "$path"
    else
        echo ""
    fi
}

# ── Mise en forme du nom (Title Case) ────────────────────────
format_name() {
    local raw="$1"
    # Supprime les [locale] entre crochets
    raw="${raw%%\[*}"
    # Title case simple
    echo "$raw" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print}'
}

# ── Glyph de fallback selon catégorie ─────────────────────────
category_glyph() {
    local cats="$1"
    for key in "${!CATEGORY_ICONS[@]}"; do
        if [[ "$cats" == *"$key"* ]]; then
            echo "${CATEGORY_ICONS[$key]}"
            return
        fi
    done
    echo "${CATEGORY_ICONS[""]}"
}

# ── Parcours des fichiers .desktop ────────────────────────────
parse_desktop() {
    local file="$1"

    local name icon exec categories hidden nodisplay
    name=$(grep -m1 "^Name=" "$file" | cut -d= -f2-)
    icon=$(grep -m1 "^Icon=" "$file" | cut -d= -f2-)
    exec=$(grep -m1 "^Exec=" "$file" | cut -d= -f2- | sed 's/ %[uUfF]//')
    categories=$(grep -m1 "^Categories=" "$file" | cut -d= -f2-)
    hidden=$(grep -m1 "^Hidden=" "$file" | cut -d= -f2-)
    nodisplay=$(grep -m1 "^NoDisplay=" "$file" | cut -d= -f2-)

    # Skip les entrées cachées
    [[ "$hidden" == "true" || "$nodisplay" == "true" ]] && return
    [[ -z "$name" || -z "$exec" ]] && return

    local display_name glyph icon_path
    display_name=$(format_name "$name")
    icon_path=$(resolve_icon "$icon")
    glyph=$(category_glyph "$categories")

    if [[ -n "$icon_path" ]]; then
        # Rofi dmenu avec icône fichier
        printf "%s %s\0icon\x1f%s\n" "$glyph" "$display_name" "$icon_path"
    else
        # Fallback glyph Nerd Font uniquement
        printf "%s %s\n" "$glyph" "$display_name"
    fi
}

# ── Main ──────────────────────────────────────────────────────
export -f resolve_icon format_name category_glyph parse_desktop

DESKTOP_DIRS=(
    "$HOME/.local/share/applications"
    "/usr/share/applications"
    "/usr/local/share/applications"
)

for dir in "${DESKTOP_DIRS[@]}"; do
    [[ -d "$dir" ]] || continue
    for desktop_file in "$dir"/*.desktop; do
        [[ -f "$desktop_file" ]] && parse_desktop "$desktop_file"
    done
done | sort -u
