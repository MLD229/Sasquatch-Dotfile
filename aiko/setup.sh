#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  愛子 (Aiko) — setup.sh
#  Télécharge le modèle par défaut (Qwen2.5-VL-3B-Instruct,
#  GGUF Q4_K_M + projecteur vision) et vérifie llama.cpp.
#
#  Usage :
#    bash setup.sh          # télécharge + vérifie
#    bash setup.sh --list   # liste les modèles dans models/
#
#  Le modèle par défaut vient du repo officiel ggml-org
#  (Qwen2.5-VL-3B-Instruct-GGUF), les poids sont ceux de Qwen
#  (Apache 2.0).
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$SCRIPT_DIR/models"
CONFIG="$SCRIPT_DIR/config.json"

# Modèle par défaut (repo ggml-org, conversion officielle llama.cpp)
REPO="ggml-org/Qwen2.5-VL-3B-Instruct-GGUF"
MODEL_FILE="Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf"          # 1.8 Go — le cerveau
MMPROJ_FILE="mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf"    # 806 Mo — la vision

# Couleurs
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${YELLOW}[aiko]${NC} $*"; }
ok()    { echo -e "${GREEN}[aiko]${NC} $*"; }
err()   { echo -e "${RED}[aiko] ERREUR:${NC} $*" >&2; }

mkdir -p "$MODELS_DIR"

if [ "${1:-}" = "--list" ]; then
    echo "Modèles disponibles dans $MODELS_DIR :"
    ls -lh "$MODELS_DIR"/*.gguf 2>/dev/null | awk '{print "  -", $9, "("$5")"}' || echo "  (aucun — lance bash setup.sh)"
    exit 0
fi

# ─── 1. Vérifier llama-server ───────────────────────────────
info "Vérification de llama-server..."
LLAMA_BIN=""
for cand in "$SCRIPT_DIR/llama-server" "$(command -v llama-server 2>/dev/null || true)"; do
    if [ -n "$cand" ] && [ -x "$cand" ]; then LLAMA_BIN="$cand"; break; fi
done

if [ -z "$LLAMA_BIN" ]; then
    # Cherche dans les backends LM Studio (CUDA)
    for b in ~/.lmstudio/extensions/backends/llama.cpp-linux-x86_64-nvidia-cuda12-avx2-*/llama-server; do
        [ -x "$b" ] && LLAMA_BIN="$b" && break
    done
fi

if [ -n "$LLAMA_BIN" ]; then
    ok "llama-server trouvé : $LLAMA_BIN"
else
    err "llama-server introuvable."
    echo "  Options :"
    echo "    1. Installer le paquet AUR : yay -S llama.cpp-cuda"
    echo "    2. Ou déposer le binaire dans : $SCRIPT_DIR/llama-server"
    exit 1
fi

# ─── 2. Télécharger le modèle (si absent) ───────────────────
dl_if_missing() {
    local file="$1" desc="$2"
    if [ -f "$MODELS_DIR/$file" ]; then
        ok "$desc présent : $file ($(du -h "$MODELS_DIR/$file" | cut -f1))"
    else
        info "Téléchargement $desc ($file) depuis huggingface.co/$REPO ..."
        curl -L --progress-bar \
            "https://huggingface.co/$REPO/resolve/main/$file" \
            -o "$MODELS_DIR/$file.part" && mv "$MODELS_DIR/$file.part" "$MODELS_DIR/$file"
        ok "$desc téléchargé : $file"
    fi
}

dl_if_missing "$MODEL_FILE"   "modèle principal"
dl_if_missing "$MMPROJ_FILE"  "projecteur vision"

# ─── 3. Vérifier config.json ────────────────────────────────
if [ -f "$CONFIG" ]; then
    ok "config.json présent"
else
    err "config.json manquant dans $SCRIPT_DIR — restore-le depuis git."
    exit 1
fi

# ─── 4. Résumé ──────────────────────────────────────────────
echo
ok "━━━ 愛子 est prête à tourner ! ━━━"
echo "  Modèle  : $MODELS_DIR/$MODEL_FILE"
echo "  Vision  : $MODELS_DIR/$MMPROJ_FILE"
echo "  Binaire : $LLAMA_BIN"
echo
echo "  Lance la sidebar avec Super+N (ou : quickshell -p $SCRIPT_DIR/main.qml)"
echo "  Pour ajouter un autre modèle : dépose le .gguf dans $MODELS_DIR puis"
echo "  édite model.model_file dans config.json."
