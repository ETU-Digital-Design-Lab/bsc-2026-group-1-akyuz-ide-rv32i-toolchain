#!/usr/bin/env bash
# ================================================================
#  AkyuzIDE Kurulum Sihirbazı v2
#  Pop!_OS / Ubuntu / Debian tabanlı sistemler için
#  Kullanım: bash setup.sh [--dev] [--no-build] [--headless]
# ================================================================
set -uo pipefail

# ── Seçenekler ───────────────────────────────────────────────────
MODE_DEV=0; NO_BUILD=0; HEADLESS=0
for arg in "$@"; do
  case $arg in
    --dev)       MODE_DEV=1 ;;
    --no-build)  NO_BUILD=1 ;;
    --headless)  HEADLESS=1 ;;
  esac
done

# ── Renkler ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}   $1"; }
info() { echo -e "  ${BLUE}→${NC}  $1"; }
fail() { echo -e "  ${RED}✗${NC}  $1"; }
step() { echo -e "\n${BOLD}${CYAN}[$1/$TOTAL_STEPS]${NC} ${BOLD}$2${NC}"; }
ask()  { echo -e "  ${YELLOW}?${NC}  $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKIPPED=(); INSTALLED=(); MANUAL=(); WARNINGS=()
TOTAL_STEPS=11

# ── Yardımcılar ──────────────────────────────────────────────────
has_cmd()    { command -v "$1" &>/dev/null; }
version_ge() { printf '%s\n%s\n' "$2" "$1" | sort -V -C; }

apt_install() {
  info "Kuruluyor: $*"
  sudo apt-get install -y -qq "$@"
}

confirm() {
  # confirm "Soru?" → 0=evet 1=hayır
  [[ $HEADLESS -eq 1 ]] && return 0
  read -r -p "$(echo -e "  ${YELLOW}?${NC}  $1 [E/h] ")" ans
  case "${ans,,}" in h|no|n) return 1;; *) return 0;; esac
}

prompt_value() {
  # prompt_value "Açıklama" "varsayılan" → stdout
  [[ $HEADLESS -eq 1 ]] && { echo "$2"; return; }
  read -r -p "$(echo -e "  ${YELLOW}→${NC}  $1 [${2}]: ")" val
  echo "${val:-$2}"
}

# ================================================================
clear
echo -e "\n${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         AkyuzIDE Kurulum Sihirbazı v2            ║${NC}"
echo -e "${BOLD}║   RISC-V / FPGA / Verilog EDA Geliştirme IDE    ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}\n"

OS_ID=$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
echo -e "  Sistem  : $(uname -srm)"
echo -e "  Dağıtım : $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
echo -e "  Dizin   : $SCRIPT_DIR"
[[ $MODE_DEV -eq 1 ]] && echo -e "  Mod     : ${CYAN}Geliştirici (--dev)${NC}"
echo ""

# ================================================================
# ADIM 1 — Temel araçlar
# ================================================================
step "1" "Temel sistem araçları"

BASE_PKGS=()
has_cmd git        || { BASE_PKGS+=(git);            INSTALLED+=("git"); }
has_cmd curl       || { BASE_PKGS+=(curl);           INSTALLED+=("curl"); }
has_cmd wget       || { BASE_PKGS+=(wget);           INSTALLED+=("wget"); }
dpkg -l build-essential &>/dev/null || { BASE_PKGS+=(build-essential); INSTALLED+=("build-essential"); }
has_cmd jq         || { BASE_PKGS+=(jq);             INSTALLED+=("jq"); }

if [[ ${#BASE_PKGS[@]} -gt 0 ]]; then
  sudo apt-get update -qq
  apt_install "${BASE_PKGS[@]}"
fi
ok "Temel araçlar hazır"

# ================================================================
# ADIM 2 — Node.js
# ================================================================
step "2" "Node.js >= 18"

if has_cmd node; then
  NODE_VER=$(node --version | tr -d 'v')
  if version_ge "$NODE_VER" "18.0.0"; then
    ok "Node.js v$NODE_VER zaten kurulu"; SKIPPED+=("nodejs")
  else
    warn "Node.js v$NODE_VER eski — v20'ye güncelleniyor..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - -q
    apt_install nodejs; INSTALLED+=("nodejs")
  fi
else
  info "Node.js bulunamadı — NodeSource v20 kuruluyor..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - -q
  apt_install nodejs; INSTALLED+=("nodejs")
fi

ok "Node.js $(node --version) | npm $(npm --version)"

# ================================================================
# ADIM 3 — Python 3
# ================================================================
step "3" "Python 3 >= 3.10"

if has_cmd python3; then
  PY_VER=$(python3 --version | awk '{print $2}')
  if version_ge "$PY_VER" "3.10"; then
    ok "Python $PY_VER zaten kurulu"; SKIPPED+=("python3")
  else
    warn "Python $PY_VER eski — python3.12 kuruluyor..."
    sudo add-apt-repository -y ppa:deadsnakes/ppa -q 2>/dev/null || true
    apt_install python3.12 python3.12-venv python3.12-dev; INSTALLED+=("python3.12")
  fi
else
  apt_install python3 python3-pip python3-venv python3-dev; INSTALLED+=("python3")
fi

python3 -m pip --version &>/dev/null || apt_install python3-pip
ok "Python $(python3 --version | awk '{print $2}') hazır"

# ── uv (hızlı paket yöneticisi) ─────────────────────────────────
if ! has_cmd uv; then
  info "uv kuruluyor (hızlı Python paket yöneticisi)..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
  ok "uv kuruldu"; INSTALLED+=("uv")
else
  ok "uv $(uv --version | awk '{print $2}') zaten kurulu"; SKIPPED+=("uv")
fi

# ================================================================
# ADIM 4 — Python backend sanal ortamı
# ================================================================
step "4" "Python backend sanal ortamı"

VENV_DIR="$SCRIPT_DIR/server/.venv"
if [[ ! -d "$VENV_DIR" ]]; then
  info "Sanal ortam oluşturuluyor → $VENV_DIR"
  python3 -m venv "$VENV_DIR"
  INSTALLED+=("backend-venv")
else
  ok "Sanal ortam zaten mevcut"; SKIPPED+=("backend-venv")
fi

info "Backend bağımlılıkları kuruluyor..."
"$VENV_DIR/bin/pip" install -q -r "$SCRIPT_DIR/server/requirements.txt"
ok "Backend bağımlılıkları kuruldu"

# ================================================================
# ADIM 5 — Icarus Verilog
# ================================================================
step "5" "Icarus Verilog (iverilog)"

if has_cmd iverilog; then
  IVER=$(iverilog -V 2>&1 | head -1 | grep -oP '\d+\.\d+' | head -1)
  ok "iverilog $IVER zaten kurulu"; SKIPPED+=("iverilog")
else
  apt_install iverilog; ok "iverilog kuruldu"; INSTALLED+=("iverilog")
fi

# ================================================================
# ADIM 6 — Ollama
# ================================================================
step "6" "Ollama (yerel AI motoru)"

if has_cmd ollama; then
  ok "Ollama $(ollama --version 2>/dev/null | head -1) zaten kurulu"; SKIPPED+=("ollama")
else
  info "Ollama kuruluyor..."
  curl -fsSL https://ollama.com/install.sh | sh
  ok "Ollama kuruldu"; INSTALLED+=("ollama")
fi

# Servis başlatılıyor mu?
if ! systemctl is-active --quiet ollama 2>/dev/null; then
  info "Ollama servisi başlatılıyor..."
  sudo systemctl enable --now ollama 2>/dev/null || ollama serve &>/dev/null &
  sleep 2
fi

# ── Model pull ────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Ollama model seçimi${NC}"
echo -e "  AkyuzIDE akıllı yönlendirme şeması:"
echo -e "    ${CYAN}Düşük/Basit${NC}  → llama3.1:8b  (4.9 GB, hızlı)"
echo -e "    ${CYAN}Yüksek/Karmaşık${NC} → akyuz-qwen25-coder:14b (15 GB, fine-tuned EDA)"
echo -e "    ${CYAN}Yüksek (base)${NC}  → qwen2.5-coder:14b (9 GB, base)"
echo ""

MODELS_TO_PULL=()

# llama3.1:8b (SIMPLE_MODEL)
if ollama list 2>/dev/null | grep -q "llama3.1:8b"; then
  ok "llama3.1:8b zaten mevcut"; SKIPPED+=("llama3.1:8b")
else
  if confirm "llama3.1:8b indirilsin mi? (4.9 GB — basit görevler için)"; then
    MODELS_TO_PULL+=("llama3.1:8b")
  else
    warn "llama3.1:8b atlandı — basit görevler yavaş çalışabilir"
    WARNINGS+=("llama3.1:8b kurulmadı")
  fi
fi

# qwen2.5-coder:14b veya fine-tuned
if ollama list 2>/dev/null | grep -q "akyuz-qwen25-coder:14b"; then
  ok "akyuz-qwen25-coder:14b (fine-tuned) zaten mevcut"; SKIPPED+=("akyuz-model")
elif ollama list 2>/dev/null | grep -q "qwen2.5-coder:14b"; then
  ok "qwen2.5-coder:14b zaten mevcut"; SKIPPED+=("qwen2.5-coder")
else
  echo ""
  echo -e "  ${BOLD}Karmaşık görevler için model seçin:${NC}"
  echo -e "  1) qwen2.5-coder:14b   — Orijinal base model (9 GB)"
  echo -e "  2) qwen3:latest        — Genel amaçlı Qwen3 (5.2 GB)"
  echo -e "  3) Atla               — Sonra manuel olarak yükle"
  [[ $HEADLESS -eq 1 ]] && ANS="1" || read -r -p "$(echo -e "  ${YELLOW}?${NC}  Seçim [1/2/3]: ")" ANS
  case "${ANS:-1}" in
    1) MODELS_TO_PULL+=("qwen2.5-coder:14b") ;;
    2) MODELS_TO_PULL+=("qwen3:latest") ;;
    *) warn "Model atlandı"; WARNINGS+=("Karmaşık görev modeli kurulmadı") ;;
  esac
fi

for m in "${MODELS_TO_PULL[@]}"; do
  info "İndiriliyor: $m (bu işlem birkaç dakika sürebilir)..."
  ollama pull "$m" && ok "$m indirildi" || warn "$m indirilemedi"
  INSTALLED+=("ollama:$m")
done

# ================================================================
# ADIM 7 — Vivado
# ================================================================
step "7" "Xilinx Vivado (FPGA synthesizer)"

VIVADO_FOUND=""
has_cmd vivado && VIVADO_FOUND=$(command -v vivado)
if [[ -z "$VIVADO_FOUND" ]]; then
  VIVADO_FOUND=$(find /opt /tools /usr/local "$HOME" 2>/dev/null \
    -maxdepth 6 -path "*/Vivado/*/bin/vivado" -type f -print -quit 2>/dev/null || true)
fi

if [[ -n "$VIVADO_FOUND" ]]; then
  VIVADO_VER=$(echo "$VIVADO_FOUND" | grep -oP '\d{4}\.\d' | head -1)
  ok "Vivado ${VIVADO_VER:-'?'} bulundu: $VIVADO_FOUND"; SKIPPED+=("vivado")
  VIVADO_DIR=$(dirname "$(dirname "$VIVADO_FOUND")")
else
  warn "Vivado bulunamadı (lisanslı araç)"
  echo -e "     ${CYAN}AMD/Xilinx hesabıyla indirip kurabilirsiniz:${NC}"
  echo -e "     1) https://www.xilinx.com/support/download.html adresinden indirin"
  echo -e "     2) ${CYAN}bash $SCRIPT_DIR/server/install_vivado.sh ~/Downloads/FPGAs_AdaptiveSoCs_*.bin${NC}"
  MANUAL+=("Vivado — installer indirip: bash server/install_vivado.sh <installer.bin>")
fi

# ================================================================
# ADIM 8 — RISC-V GCC Toolchain
# ================================================================
step "8" "RISC-V GCC Toolchain"

RISCV_BINS=("riscv-none-elf-gcc" "riscv64-unknown-elf-gcc" "riscv32-unknown-elf-gcc")
RISCV_FOUND=""
for b in "${RISCV_BINS[@]}"; do has_cmd "$b" && { RISCV_FOUND="$b"; break; }; done
LOCAL_RISCV="$SCRIPT_DIR/toolchain/riscv/bin/riscv-none-elf-gcc"
[[ -f "$LOCAL_RISCV" ]] && RISCV_FOUND="$LOCAL_RISCV"

if [[ -n "$RISCV_FOUND" ]]; then
  ok "RISC-V GCC: $RISCV_FOUND"; SKIPPED+=("riscv-gcc")
else
  info "RISC-V GCC kuruluyor (apt)..."
  sudo apt-get install -y -qq gcc-riscv64-unknown-elf 2>/dev/null && {
    ok "riscv64-unknown-elf-gcc kuruldu"; INSTALLED+=("riscv-gcc")
    RISCV_FOUND="riscv64-unknown-elf-gcc"
  } || {
    warn "apt'de bulunamadı — xpack önerilen alternatif:"
    echo -e "     https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases"
    MANUAL+=("RISC-V GCC — https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack")
  }
fi

# ================================================================
# ADIM 9 — .env dosyası
# ================================================================
step "9" ".env yapılandırması"

ENV_FILE="$SCRIPT_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  ok ".env zaten mevcut"; SKIPPED+=(".env")
  # Eksik anahtarları kontrol et
  grep -q "OLLAMA_HOST" "$ENV_FILE" || echo "OLLAMA_HOST=http://127.0.0.1:11434" >> "$ENV_FILE"
  grep -q "REMOTE_AI_HOST" "$ENV_FILE" || echo "REMOTE_AI_HOST=http://127.0.0.1:11434" >> "$ENV_FILE"
  grep -q "APP_URL" "$ENV_FILE" || echo "APP_URL=http://127.0.0.1:3001" >> "$ENV_FILE"
else
  echo ""
  info ".env dosyası oluşturuluyor..."

  GEMINI_KEY=$(prompt_value "Gemini API Key (opsiyonel, boş bırakılabilir)" "")
  OLLAMA_HOST_VAL=$(prompt_value "Ollama Host" "http://127.0.0.1:11434")

  # Tailscale IP bul
  TAILSCALE_IP=$(ip addr show tailscale0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 || echo "")
  if [[ -n "$TAILSCALE_IP" ]]; then
    if confirm "Tailscale IP $TAILSCALE_IP tespit edildi. Remote AI Host olarak kullanılsın mı?"; then
      REMOTE_HOST="http://$TAILSCALE_IP:11434"
    else
      REMOTE_HOST="$OLLAMA_HOST_VAL"
    fi
  else
    REMOTE_HOST="$OLLAMA_HOST_VAL"
  fi

  cat > "$ENV_FILE" <<EOF
GEMINI_API_KEY=$GEMINI_KEY
OLLAMA_HOST=$OLLAMA_HOST_VAL
REMOTE_AI_HOST=$REMOTE_HOST
APP_URL=http://127.0.0.1:3001
WORKSPACE_DIR=$SCRIPT_DIR/workspace
EOF

  [[ -n "$VIVADO_DIR" ]] && echo "VIVADO_PATH=$VIVADO_DIR" >> "$ENV_FILE"
  [[ -n "$RISCV_FOUND" ]] && echo "RISCV_GCC_PATH=$(command -v $RISCV_FOUND 2>/dev/null || echo $RISCV_FOUND)" >> "$ENV_FILE"

  ok ".env oluşturuldu"; INSTALLED+=(".env")
fi

# ================================================================
# ADIM 10 — npm + Build
# ================================================================
step "10" "npm bağımlılıkları"

cd "$SCRIPT_DIR"
info "npm install çalışıyor..."
npm install --silent
ok "npm paketleri kuruldu"

if [[ $NO_BUILD -eq 0 ]]; then
  if [[ $MODE_DEV -eq 1 ]]; then
    ok "Dev modu — build atlandı (npm run dev ile başlat)"
  else
    info "Electron uygulaması build ediliyor (bu birkaç dakika sürebilir)..."
    npm run build:desktop 2>&1 | tail -5
    APPIMAGE=$(find "$SCRIPT_DIR/release" -name "*.AppImage" 2>/dev/null | head -1)
    DEB=$(find "$SCRIPT_DIR/release" -name "*.deb" 2>/dev/null | head -1)
    [[ -n "$APPIMAGE" ]] && { ok "AppImage: $APPIMAGE"; chmod +x "$APPIMAGE"; INSTALLED+=("AppImage"); }
    [[ -n "$DEB" ]]      && { ok ".deb: $DEB"; INSTALLED+=(".deb"); }
  fi
else
  ok "Build atlandı (--no-build)"
fi

# ================================================================
# ADIM 11 — Opsiyonel araçlar
# ================================================================
step "11" "Opsiyonel araçlar"

# GitHub CLI
if has_cmd gh; then
  ok "GitHub CLI $(gh --version | head -1 | awk '{print $3}') zaten kurulu"; SKIPPED+=("gh-cli")
elif confirm "GitHub CLI kurulsun mu? (PR/issue yönetimi için)"; then
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt-get update -qq && apt_install gh
  ok "GitHub CLI kuruldu"; INSTALLED+=("gh-cli")
else
  SKIPPED+=("gh-cli")
fi

# Ollama Monitor systemd servisi
if confirm "Ollama Monitor (proxy+dashboard) sistem başlangıcında otomatik başlasın mı?"; then
  VENV_PYTHON="$SCRIPT_DIR/server/.venv/bin/python"
  has_cmd python3 && MONITOR_PYTHON=$(command -v python3)
  [[ -f "$VENV_PYTHON" ]] && MONITOR_PYTHON="$VENV_PYTHON"

  # aiohttp gerekli
  "$MONITOR_PYTHON" -c "import aiohttp" 2>/dev/null || \
    "$MONITOR_PYTHON" -m pip install -q aiohttp

  sudo tee /etc/systemd/system/akyuz-monitor.service > /dev/null <<EOF
[Unit]
Description=AkyuzIDE Ollama Monitor
After=network.target ollama.service
Wants=ollama.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$SCRIPT_DIR
ExecStart=$MONITOR_PYTHON $SCRIPT_DIR/ollama_monitor.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now akyuz-monitor
  ok "akyuz-monitor servisi aktif (port 11435/11436)"; INSTALLED+=("akyuz-monitor.service")
else
  info "Manuel başlatmak için: python3 $SCRIPT_DIR/ollama_monitor.py"
fi

# Tailscale Ollama erişimi
TAILSCALE_IP=$(ip addr show tailscale0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 || echo "")
if [[ -n "$TAILSCALE_IP" ]]; then
  if ! ss -tlnp 2>/dev/null | grep -q "0.0.0.0:11434\|\*:11434"; then
    if confirm "Ollama Tailscale üzerinden ($TAILSCALE_IP) erişilebilir hale getirilsin mi?"; then
      sudo mkdir -p /etc/systemd/system/ollama.service.d
      printf '[Service]\nEnvironment="OLLAMA_HOST=0.0.0.0:11434"\n' | \
        sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null
      sudo systemctl daemon-reload && sudo systemctl restart ollama
      ok "Ollama Tailscale'den erişilebilir: http://$TAILSCALE_IP:11434"
      INSTALLED+=("ollama-tailscale")
    fi
  else
    ok "Ollama zaten 0.0.0.0:11434 üzerinde dinliyor"
  fi
fi

# ================================================================
# ÖZET
# ================================================================
echo -e "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║                  Kurulum Özeti                  ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${NC}\n"

if [[ ${#INSTALLED[@]} -gt 0 ]]; then
  echo -e "${GREEN}${BOLD}Yüklenenler:${NC}"
  for i in "${INSTALLED[@]}"; do echo -e "  ${GREEN}✓${NC} $i"; done
fi

if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo -e "\n${BLUE}${BOLD}Zaten mevcuttu:${NC}"
  for i in "${SKIPPED[@]}"; do echo -e "  ${BLUE}·${NC} $i"; done
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo -e "\n${YELLOW}${BOLD}Uyarılar:${NC}"
  for i in "${WARNINGS[@]}"; do echo -e "  ${YELLOW}⚠${NC}  $i"; done
fi

if [[ ${#MANUAL[@]} -gt 0 ]]; then
  echo -e "\n${YELLOW}${BOLD}Manuel kurulum gerekiyor:${NC}"
  for i in "${MANUAL[@]}"; do echo -e "  ${YELLOW}⚠${NC}  $i"; done
fi

echo ""
echo -e "${BOLD}Başlatma komutları:${NC}"

if [[ $MODE_DEV -eq 1 ]]; then
  echo -e "\n  ${BOLD}Geliştirici modu:${NC}"
  echo -e "  Terminal 1 → ${CYAN}cd $SCRIPT_DIR && python3 server/main.py${NC}"
  echo -e "  Terminal 2 → ${CYAN}cd $SCRIPT_DIR && npm run dev${NC}"
else
  APPIMAGE=$(find "$SCRIPT_DIR/release" -name "*.AppImage" 2>/dev/null | head -1)
  DEB=$(find "$SCRIPT_DIR/release" -name "*.deb" 2>/dev/null | head -1)
  [[ -n "$APPIMAGE" ]] && echo -e "  ${CYAN}$APPIMAGE${NC}"
  [[ -n "$DEB" ]]      && echo -e "  ${CYAN}sudo dpkg -i $DEB && akyuzide${NC}"
fi

[[ -n "$TAILSCALE_IP" ]] && echo -e "\n  ${BOLD}Ollama Monitor:${NC} http://$TAILSCALE_IP:11436"

echo -e "\n${GREEN}${BOLD}✓ Kurulum tamamlandı!${NC}\n"
