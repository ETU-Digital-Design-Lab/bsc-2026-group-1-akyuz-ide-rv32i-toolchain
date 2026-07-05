#!/usr/bin/env bash
# AkyuzIDE Eğitim Ortamı Kurulumu
# RTX 5070 Ti (16 GB VRAM) + CUDA 12.x için optimize edilmiştir.
# Kullanım: bash setup_train_env.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$SCRIPT_DIR/train_env"

echo "========================================="
echo " AkyuzIDE Eğitim Ortamı Kurulumu"
echo "========================================="
echo "Hedef: $ENV_DIR"
echo ""

# ── 1. Sanal ortam ──────────────────────────────────────────
echo "[1/4] Sanal ortam oluşturuluyor (uv)..."
uv venv "$ENV_DIR" --python python3.12
source "$ENV_DIR/bin/activate"

# ── 2. PyTorch (CUDA 12.8 nightly — Blackwell sm_120 desteği) ──
echo "[2/4] PyTorch nightly cu128 kuruluyor (RTX 5070 Ti Blackwell sm_120)..."
uv pip install --pre "torch>=2.7" torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/nightly/cu128

# ── 3. Eğitim kütüphaneleri ─────────────────────────────────
echo "[3/4] Eğitim kütüphaneleri kuruluyor..."
uv pip install \
    transformers>=4.47.0 \
    peft>=0.14.0 \
    trl>=0.12.0 \
    bitsandbytes>=0.45.0 \
    datasets>=3.0.0 \
    accelerate>=1.0.0 \
    scipy \
    sentencepiece \
    protobuf \
    tensorboard \
    einops \
    packaging

# Flash Attention 2 — opsiyonel, başarısız olursa atla
echo "[3/4] Flash Attention 2 deneniyor (opsiyonel)..."
uv pip install flash-attn --no-build-isolation 2>/dev/null \
    && echo "  flash-attn kuruldu." \
    || echo "  flash-attn kurulamadı, standart attention kullanılacak."

# ── 4. Doğrulama ────────────────────────────────────────────
echo "[4/4] Doğrulama..."
python - <<'EOF'
import torch
print(f"  PyTorch   : {torch.__version__}")
print(f"  CUDA      : {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"  GPU       : {torch.cuda.get_device_name(0)}")
    print(f"  VRAM      : {torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f} GB")
import transformers, peft, trl, bitsandbytes
print(f"  transformers : {transformers.__version__}")
print(f"  peft         : {peft.__version__}")
print(f"  trl          : {trl.__version__}")
print(f"  bitsandbytes : {bitsandbytes.__version__}")
EOF

echo ""
echo "========================================="
echo " Kurulum tamamlandı."
echo " Aktif etmek için:"
echo "   source $ENV_DIR/bin/activate"
echo "========================================="
