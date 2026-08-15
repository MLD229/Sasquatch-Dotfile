# fish/config.fish

# ── Starship ─────────────────────────────────
starship init fish | source

# ── Variables ────────────────────────────────
set -gx EDITOR nvim
set -gx BROWSER firefox
set -gx TERMINAL kitty

# ── MPD : socket unix PAR USER (mpd.conf bind_to_address) ────────
# mpc / ncmpc pointent vers SON socket (pas de port TCP partagé).
# Le CC (cc/) lit MPD_SOCKET dans cc/config.py — même chemin.
set -gx MPD_HOST "$HOME/.local/share/mpd/socket"

# ── Path ─────────────────────────────────────
fish_add_path ~/.local/bin
fish_add_path ~/.cargo/bin

# ── Aliases ──────────────────────────────────
alias ls   'eza --icons --group-directories-first'
alias ll   'eza -la --icons --group-directories-first'
alias lt   'eza --tree --icons -L 2'
alias cat  'bat --style=plain'
alias grep 'grep --color=auto'
alias cp   'cp -iv'
alias mv   'mv -iv'
alias rm   'rm -Iv'
alias ..   'cd ..'
alias ...  'cd ../..'

# Yay
alias yays 'yay -Ss'
alias yayi 'yay -S'
alias yayu 'yay -Syu'
alias yayr 'yay -Rns'

# ── Fastfetch au démarrage ───────────────────
if status is-interactive
    fastfetch
end
