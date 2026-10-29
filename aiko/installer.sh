#!/usr/bin/env bash
# installer.sh — vérifie les prérequis de 愛子 (aiko) et télécharge les GGUF.
# Aiko ne s'installe pas : il vit dans ~/.config/aiko (lien vers ce dépôt).
#
#   bash ~/.config/aiko/installer.sh             # vérifs + GGUF 3B manquant
#   bash ~/.config/aiko/installer.sh --check      # vérifs seules (rien d'écrit)
#   bash ~/.config/aiko/installer.sh --with-7b    # télécharge aussi le 7B (~4,7 Go)
#
# Ordre des vérifications (celui du brief) :
#   1. llama-server  2. GGUF dans ~/models  3. wl-copy/curl/python3  4. keybind Super+N
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${AIKO_MODELS_DIR:-$HOME/models}"
CHECK_ONLY=0
WITH_7B=0
for arg in "$@"; do
    case "$arg" in
        --check)   CHECK_ONLY=1 ;;
        --with-7b) WITH_7B=1 ;;
        -h|--help) sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "argument inconnu : $arg" >&2; exit 2 ;;
    esac
done

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
info() { printf '  · %s\n' "$*"; }

FAIL=0
echo "=== 愛子 (aiko) — vérification des prérequis ==="

# ── 1. llama-server ───────────────────────────────────────────────────────
# Ordre identique à llm.py::find_llama_server : $AIKO_LLAMA_SERVER, PATH, LM Studio.
LLAMA="${AIKO_LLAMA_SERVER:-$(command -v llama-server || true)}"
if [ -z "$LLAMA" ]; then
    LM=$(ls -d "$HOME"/.lmstudio/extensions/backends/llama.cpp-*/llama-server 2>/dev/null | tail -1)
    [ -n "$LM" ] && LLAMA="$LM"
fi
if [ -n "$LLAMA" ] && [ -x "$LLAMA" ]; then
    ok "llama-server : $LLAMA"
    info "  $("$LLAMA" --version 2>&1 | head -1)"
    DEVS=$("$LLAMA" --list-devices 2>&1 | grep -E "Vulkan|CUDA|ROCm|Metal|SYCL" || true)
    if [ -n "$DEVS" ]; then
        ok "GPU visible : $(echo "$DEVS" | tr '\n' ' ')"
    else
        warn "aucun GPU visible → inférence CPU : ~12,8 tok/s mesurés sur le 3B"
        case "$LLAMA" in
            /usr/bin/llama-server|/usr/sbin/llama-server)
                warn "  ce binaire vient du paquet Arch extra/llama-cpp = CPU ONLY"
                info "  pour ~80 tok/s : build Vulkan/CUDA précompilé dans ~/.local/bin" ;;
        esac
    fi
else
    bad "llama-server introuvable → 2 options, dans cet ordre :"
    info "  1) build Vulkan précompilé (recommandé) : ~/.local/bin/llama-server"
    info "     (llama.cpp release Vulkan, extrait dans ~/.local/share/aiko/llama/)"
    info "  2) sudo pacman -S llama-cpp   ← paquet Arch, CPU SEUL : 12,8 tok/s"
    info "     contre ~80 tok/s en Vulkan sur le 3B (mesuré, GTX 1660 Ti)"
    info "  puis vérifier : llama-server --list-devices  → doit lister Vulkan1"
    FAIL=1
fi

# ── 2. modèles GGUF dans ~/models ─────────────────────────────────────────
echo
echo "=== Modèles ($MODELS_DIR) ==="
if [ "$CHECK_ONLY" = 0 ]; then
    mkdir -p "$MODELS_DIR"
fi
python3 - "$SCRIPT_DIR/models.json" "$MODELS_DIR" "$CHECK_ONLY" "$WITH_7B" <<'PY'
import json, os, subprocess, sys

cfg_path, dst, check_only, with_7b = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4] == "1"
cfg = json.load(open(cfg_path, encoding="utf-8"))
default = cfg.get("default", "rapide")
todo = []
for key, p in cfg["profiles"].items():
    path = os.path.join(dst, p["file"])
    required = (key == default)
    url = ("https://huggingface.co/bartowski/"
           + p["file"].replace("-Q4_K_M.gguf", "-GGUF")
           + "/resolve/main/" + p["file"])
    if os.path.isfile(path):
        size = os.path.getsize(path) / 1e9
        print(f"  \033[32m✓\033[0m {key:6s} {p['file']} ({size:.2f} Go)")
        continue
    tag = "OBLIGATOIRE" if required else "facultatif"
    print(f"  \033[31m✗\033[0m {key:6s} {p['file']} MANQUANT ({tag})")
    print(f"          curl -fL -C - -o \"{path}\" \"{url}\"")
    if required or with_7b:
        todo.append((key, path, url))
    else:
        print(f"          (facultatif : --with-7b pour le télécharger maintenant)")

if not todo:
    if check_only:
        missing = [p for p in cfg["profiles"].values()
                   if not os.path.isfile(os.path.join(dst, p["file"]))]
        sys.exit(3 if missing else 0)
    sys.exit(0)
if check_only:
    print("\n  → relancer installer.sh sans --check pour télécharger.")
    sys.exit(3)
for key, path, url in todo:
    print(f"\n  téléchargement {key} : {url}")
    rc = subprocess.call(["curl", "-fL", "-C", "-", "--retry", "3",
                          "--progress-bar", "-o", path, url])
    if rc != 0:
        print(f"  \033[31m✗\033[0m échec du téléchargement de {key} (code {rc}).")
        print("    Commande exacte :")
        print(f"    curl -fL -C - -o \"{path}\" \"{url}\"")
        sys.exit(4)
    print(f"  \033[32m✓\033[0m {key} téléchargé")
PY
rc=$?
case "$rc" in
    0) ;;
    3) warn "modèle(s) manquant(s) — voir les commandes curl ci-dessus"; FAIL=1 ;;
    *) bad "téléchargement incomplet (code $rc)"; FAIL=1 ;;
esac

# ── 3. outils du cycle de vie ─────────────────────────────────────────────
echo
echo "=== Outils ==="
if python3 -c 'import sys; assert sys.version_info >= (3, 10)' 2>/dev/null; then
    ok "python3 $(python3 -c 'import platform;print(platform.python_version())')"
else
    bad "python3 >= 3.10 requis"; FAIL=1
fi
if command -v quickshell >/dev/null 2>&1; then
    ok "quickshell $(quickshell --version 2>/dev/null | head -1 | awk '{print $2}')"
else
    bad "quickshell absent → sudo pacman -S quickshell (le panneau ne s'affiche pas)"
    FAIL=1
fi
for tool in wl-copy curl pgrep; do
    if command -v "$tool" >/dev/null 2>&1; then
        ok "$tool"
    else
        case "$tool" in
            wl-copy) bad "wl-copy absent → sudo pacman -S wl-clipboard (bouton copier)" ;;
            curl)    bad "curl absent → sudo pacman -S curl (téléchargement + healthcheck)" ;;
            pgrep)   bad "pgrep absent → sudo pacman -S procps-ng (cycle de vie)" ;;
        esac
        FAIL=1
    fi
done
for tool in nvidia-smi grim notify-send ss; do
    if command -v "$tool" >/dev/null 2>&1; then
        ok "$tool"
    else
        info "$tool absent (facultatif : VRAM/tests/notifications/ports)"
    fi
done

# ── 4. keybind Super+N ────────────────────────────────────────────────────
echo
echo "=== Keybind Super+N ==="
KEYBINDS=""
for cand in "$HOME/.config/hypr/keybinds.conf" \
            "$SCRIPT_DIR/../hypr/keybinds.conf"; do
    if [ -f "$cand" ]; then KEYBINDS="$cand"; break; fi
done
if [ -z "$KEYBINDS" ]; then
    warn "hypr/keybinds.conf introuvable — ajouter à la main :"
    info '  bind = $mod, N, exec, ~/.config/aiko/aiko.sh'
elif grep -Eq '^[[:space:]]*bind[a-z]*[[:space:]]*=[[:space:]]*\$?mod[^,]*,[[:space:]]*N,[[:space:]]*exec,.*aiko\.sh' "$KEYBINDS"; then
    ok "déjà présent dans $KEYBINDS"
elif [ "$CHECK_ONLY" = 1 ]; then
    warn "Super+N absent de $KEYBINDS — relancer sans --check pour l'ajouter"
    FAIL=1
else
    {
        printf '\n# 愛子 (aiko) — sidebar gauche, LLM local éphémère\n'
        printf 'bind = $mod, N, exec, ~/.config/aiko/aiko.sh\n'
    } >> "$KEYBINDS"
    ok "ajouté à $KEYBINDS : bind = \$mod, N, exec, ~/.config/aiko/aiko.sh"
    info "  (hyprctl reload pour l'activer tout de suite)"
fi

# ── Préférence mémorisée (seul état persisté) ─────────────────────────────
echo
echo "=== Préférence de modèle (seul fichier persisté) ==="
python3 - "$SCRIPT_DIR" <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[1])
import llm
prefs = llm.load_prefs()
cfg = llm.load_models()
prof, note = llm.resolve_profile(cfg)
labels = {k: v.get("label") for k, v in cfg["profiles"].items()}
if prefs.get("model"):
    print(f"  · {llm.PREFS_FILE} → model={prefs['model']}"
          f" ({labels.get(prefs['model'], '?')})")
else:
    print(f"  · {llm.PREFS_FILE} absent → défaut {prof}"
          f" ({labels.get(prof, '?')}) : rien n'a encore été choisi")
if note:
    print(f"  ! {note}")
print("  · la conversation, elle, n'est jamais écrite (RAM seulement)")
PY

echo
if [ "$FAIL" -eq 0 ]; then
    echo "Tout est prêt. Ouvrir la sidebar : Super+N  (ou ~/.config/aiko/aiko.sh)"
else
    echo "Corriger les lignes ✗ ci-dessus, puis relancer ce script."
fi
exit "$FAIL"
