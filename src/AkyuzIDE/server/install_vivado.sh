#!/bin/bash
# AkyuzIDE — Vivado Otomatik Kurulum Scripti
# Pop!_OS 24.04 LTS / Ubuntu 24.04
# ============================================================
# Kullanim:
#   chmod +x install_vivado.sh
#   ./install_vivado.sh [/path/to/installer.bin]
#
# Installer yoksa script seni indirme sayfasina yonlendirir.
# ============================================================

set -e

INSTALL_DIR="${VIVADO_INSTALL_DIR:-/tools/Xilinx}"
VERSION="${VIVADO_VERSION:-2025.2}"

# ─── Renk tanimlari ──────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[HATA]${NC}  $*"; exit 1; }

echo ""
echo "╔═══════════════════════════════════════════════════╗"
echo "║       AkyuzIDE Vivado Kurulum Asistani            ║"
echo "╚═══════════════════════════════════════════════════╝"
echo ""

# ─── 1. Sistem Gereksinimleri ─────────────────────────────────
info "Sistem gereksinimleri kontrol ediliyor..."

DISK_GB=$(df -BG "$HOME" | awk 'NR==2{print $4}' | tr -d 'G')
RAM_GB=$(free -g | awk '/^Mem:/{print $2}')

if [ "$DISK_GB" -lt 80 ]; then
    warn "Disk alani az: ${DISK_GB}GB (onerililen: 100GB+)"
else
    ok "Disk: ${DISK_GB}GB musait"
fi
if [ "$RAM_GB" -lt 8 ]; then
    warn "RAM az: ${RAM_GB}GB (onerililen: 16GB+)"
else
    ok "RAM: ${RAM_GB}GB"
fi

# ─── 2. Bağımlılıklar ─────────────────────────────────────────
info "Sistem bagimliliklari kuruluyor..."
sudo apt-get update -qq
sudo apt-get install -y \
    libncurses5 libstdc++6 libc6-dev \
    gcc g++ make git unzip \
    libssl-dev libffi-dev python3 \
    libx11-6 libxrender1 libxtst6 libxi6 \
    libglib2.0-0 libsm6 libxext6 \
    libtinfo5 2>/dev/null || true
ok "Bagimliliklar kuruldu"

# ─── 3. Installer Kontrolü ────────────────────────────────────
INSTALLER="${1:-}"

if [ -z "$INSTALLER" ]; then
    # Downloads klasorunde ara
    INSTALLER=$(find "$HOME/Downloads" -name "FPGAs_AdaptiveSoCs_Unified*.bin" \
                                      -o -name "FPGAs_AdaptiveSoCs_Unified_SDI*.bin" \
                                      -o -name "Vivado_${VERSION}*.bin" 2>/dev/null | head -1)
fi

if [ -z "$INSTALLER" ] || [ ! -f "$INSTALLER" ]; then
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║  Vivado installer bulunamadi. Asagidaki adimlari izle:        ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║                                                               ║"
    echo "║  1. Tarayicide ac:                                            ║"
    echo "║     https://www.xilinx.com/support/download.html              ║"
    echo "║                                                               ║"
    echo "║  2. AMD hesabi olustur (ucretsiz) ve giris yap               ║"
    echo "║                                                               ║"
    echo "║  3. 'Vivado ML Edition' → 'Linux Self Extracting Web          ║"
    echo "║     Installer' indir (≈300MB, kurulumda gerekenleri indirir) ║"
    echo "║     VEYA 'Vivado ML Edition - SFD' full ISO (≈45GB)          ║"
    echo "║                                                               ║"
    echo "║  4. Indirme tamamlaninca bu scripti tekrar calistir:          ║"
    echo "║     ./install_vivado.sh ~/Downloads/FPGAs_AdaptiveSoCs_*.bin ║"
    echo "║                                                               ║"
    echo "║  NOT: WebPACK lisansi ucretsiz.                               ║"
    echo "║       Basys3/Arty-A7 icin yeterli.                           ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""

    # Alternatif: Vivado 2023.1 doğrudan link (login gerektirmez bazen)
    info "Alternatif: tarayicide AMD hesabi olmadan deneyebilirsin:"
    echo "  https://account.amd.com/en/forms/downloads/xef.html?filename=FPGAs_AdaptiveSoCs_Unified_2024.2_1113_1001_Lin64.bin"
    exit 0
fi

ok "Installer bulundu: $INSTALLER"
info "Boyut: $(du -h "$INSTALLER" | cut -f1)"

# ─── 4. Kurulum Yanıt Dosyası ─────────────────────────────────
RESPONSE_FILE=$(mktemp /tmp/vivado_install_XXXX.txt)
cat > "$RESPONSE_FILE" << RESPONSE_EOF
#### Vivado ML Edition / WebPACK 2025.2
Edition=Vivado ML Standard

Product.Vivado=1
Product.DocNav=0
Product.Vitis=0
Product.Vitis_HLS=0
Product.Model_Composer=0

Modules.Artix-7=1
Modules.Kintex-7=1
Modules.Spartan-7=1
Modules.Zynq-7000=1
Modules.Artix UltraScale+=0
Modules.Kintex UltraScale=0
Modules.Kintex UltraScale+=0
Modules.Virtex UltraScale+=0
Modules.Zynq UltraScale+ MPSoC=0
Modules.Zynq UltraScale+ RFSoC=0
Modules.Alveo U200=0
Modules.Alveo U250=0

InstallOptions.Acquire or Manage a License Key=0
InstallOptions.Enable WebTalk=0

DesktopShortcut=0
StartMenuShortcut=0

InstallationDirectory=$INSTALL_DIR
RESPONSE_EOF

# ─── 5. Kurulumu Başlat ───────────────────────────────────────
info "Kurulum basliyor → $INSTALL_DIR"
info "Bu islem 30-60 dakika surebilir..."
sudo mkdir -p "$INSTALL_DIR"
chmod +x "$INSTALLER"

"$INSTALLER" --agree XilinxEULA,3rdPartyEULA \
              --batch Install \
              --config "$RESPONSE_FILE" 2>&1 | tee /tmp/vivado_install.log

rm -f "$RESPONSE_FILE"

# ─── 6. PATH Ayarları ─────────────────────────────────────────
VIVADO_BIN="$INSTALL_DIR/Vivado/${VERSION}/bin/vivado"

if [ ! -f "$VIVADO_BIN" ]; then
    # Versiyon klasorunu bul
    VIVADO_BIN=$(find "$INSTALL_DIR" -name "vivado" -type f 2>/dev/null | head -1)
fi

if [ -f "$VIVADO_BIN" ]; then
    ok "Vivado kuruldu: $VIVADO_BIN"
    VIVADO_DIR=$(dirname "$VIVADO_BIN")

    # .bashrc'ye ekle
    if ! grep -q "Xilinx/Vivado" ~/.bashrc 2>/dev/null; then
        echo "" >> ~/.bashrc
        echo "# Vivado — AkyuzIDE" >> ~/.bashrc
        echo "export PATH=\"$VIVADO_DIR:\$PATH\"" >> ~/.bashrc
        echo "source $INSTALL_DIR/Vivado/${VERSION}/settings64.sh 2>/dev/null || true" >> ~/.bashrc
    fi

    # AkyuzIDE .env dosyasini guncelle
    ENV_FILE="$(dirname "$0")/.env"
    if [ -f "$ENV_FILE" ]; then
        # Mevcut VIVADO_PATH satirini guncelle
        sed -i "s|^VIVADO_PATH=.*|VIVADO_PATH=$VIVADO_BIN|" "$ENV_FILE"
        if ! grep -q "VIVADO_PATH" "$ENV_FILE"; then
            echo "VIVADO_PATH=$VIVADO_BIN" >> "$ENV_FILE"
        fi
        ok ".env guncellendi: VIVADO_PATH=$VIVADO_BIN"
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  Vivado kurulumu basarili!                       ║"
    echo "║  Terminali yeniden ac veya:                      ║"
    echo "║    source ~/.bashrc                              ║"
    echo "║                                                  ║"
    echo "║  Test etmek icin:                                ║"
    echo "║    vivado -version                               ║"
    echo "╚══════════════════════════════════════════════════╝"
else
    err "Vivado kurulum basarisiz. Log: /tmp/vivado_install.log"
fi
