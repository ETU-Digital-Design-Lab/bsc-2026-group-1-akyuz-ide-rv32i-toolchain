# AkyuzIDE & RV32I Processor Toolchain

**Erzurum Technical University — ETU Digital Design Lab — Bitirme Projesi (2026), Grup 1**

Bu depo, RISC-V mimarisi üzerine kurulu bir donanım geliştirme bitirme projesinin iki tamamlayıcı bileşenini bir arada barındırır:

1. **[AkyuzIDE](#1-akyuzide)** — RISC-V/FPGA geliştirme için yapay zekâ destekli, masaüstü bir Entegre Geliştirme Ortamı (IDE).
2. **[akyuz-rv32i](#2-akyuz-rv32i)** — RV32I komut kümesini uygulayan, 5 aşamalı (pipelined) bir RISC-V işlemci çekirdeğinin sıfırdan geliştirilme sürecini belgeleyen donanım prototipleri.

İkisi aynı problem uzayının farklı uçlarını kapsar: `akyuz-rv32i`, gerçek bir RISC-V çekirdeğinin (simülasyondan FPGA'ya kadar) nasıl tasarlanıp doğrulandığını somut bir örnekle gösterirken; `AkyuzIDE`, tam da bu tür projelerin (Verilog yazma, simüle etme, FPGA'ya sentezleme, seri port üzerinden yükleme) tek bir arayüzden, bir yapay zekâ ajanı yardımıyla yürütülebilmesi için geliştirilen bir araçtır.

---

## İçindekiler

- [1. AkyuzIDE](#1-akyuzide)
  - [1.1 Ne işe yarar](#11-ne-i̇şe-yarar)
  - [1.2 Öne çıkan özellikler](#12-öne-çıkan-özellikler)
  - [1.3 Mimari](#13-mimari)
  - [1.4 Kurulum ve çalıştırma](#14-kurulum-ve-çalıştırma)
- [2. akyuz-rv32i](#2-akyuz-rv32i)
  - [2.1 Ortak mimari temeller](#21-ortak-mimari-temeller)
  - [2.2 Prototip 2 — Wishbone SoC](#22-prototip-2--wishbone-soc)
  - [2.3 Snake & Mayın Tarlası — FPGA oyun konsolu](#23-snake--mayın-tarlası--fpga-oyun-konsolu)
  - [2.4 Prototip 4 — Kamera/VGA SoC](#24-prototip-4--kameravga-soc)
  - [2.5 Bilinen sorunlar ve eksikler](#25-bilinen-sorunlar-ve-eksikler)
- [3. Depo yapısı](#3-depo-yapısı)
- [4. Katkıda bulunan](#4-katkıda-bulunan)

---

## 1. AkyuzIDE

*(Kaynak kod: [`src/AkyuzIDE/`](src/AkyuzIDE/) — ayrıntılı README: [`src/AkyuzIDE/README.md`](src/AkyuzIDE/README.md))*

### 1.1 Ne işe yarar

RISC-V/FPGA donanım geliştirirken normalde birbirinden kopuk çalışan araçlar (Vivado, Icarus Verilog simülatörü, RISC-V derleyici toolchain'i, seri port yazılımları, metin editörü) kullanılır. AkyuzIDE bunları tek bir masaüstü uygulamasında toplar ve üzerine, dosya sistemine ve bu araçlara doğrudan erişebilen bir yapay zekâ ajanı ekler. Amaç, bir öğrenci ya da mühendisin "bir ALU modülü yaz ve simüle et" gibi bir isteği IDE içinde adım adım (editör, terminal, dalga formu görüntüleyici panelleri üzerinden) takip ederek gerçekleştirebilmesidir.

Klasik bir "kod tamamlama" chat botu değildir: dosya oluşturma/düzenleme gibi kritik işlemler öncesinde kullanıcıdan onay istenir (agent duraklar, kullanıcı onaylayana kadar bekler) — yani ajan hiçbir zaman kullanıcının haberi olmadan dosya değiştirmez.

### 1.2 Öne çıkan özellikler

| Özellik | Açıklama |
|---|---|
| **AI Agent (agent/ask/plan modları)** | Kullanıcı mesajı otomatik sınıflandırılır: `agent` = dosya/komut çalıştırabilen tam yetkili mod, `ask` = salt metinsel açıklama, `plan` = yalnızca read-only araçlarla çalışan güvenli keşif modu. |
| **Onay akışı** | Dosya değiştiren araçlar (`write_file`, `edit_file`, `delete_file`, vb.) çalıştırılmadan önce kullanıcıya onay sorulur. |
| **Çoklu LLM sağlayıcı** | Yerel Ollama (varsayılan), OpenRouter, Moonshot/Kimi arasında görev karmaşıklığına göre otomatik yönlendirme yapan bir "smart router". |
| **Verilog simülasyonu** | Icarus Verilog ile derleme/simülasyon; üretilen `.vcd` dalga formları IDE içinde görselleştirilir (`WaveformViewer`). |
| **Vivado FPGA akışı** | Sentez → implementasyon → bitstream üretimi tek TCL akışıyla; kaynak kullanımı ve zamanlama raporları ayrıştırılır. Basys 3, Arty A7-35T, Nexys A7-100T gibi kartlar desteklenir. |
| **RISC-V assembler** | RV32I komut setini destekleyen bir assembler; çıktıyı `readmemh` formatına çevirir. |
| **Donanım/seri port yönetimi** | Bağlı seri portları tarar, C kodunu RISC-V toolchain ile derler, üretilen ikiliyi karta yükler. |
| **Monaco editör + entegre terminal** | Çoklu sekme, dil algılama, backend üzerinden gerçek shell komutu çalıştıran terminal. |
| **Electron masaüstü paketleme** | Python backend'ini alt süreç olarak başlatan bir Electron kabuğu; Windows portable `.exe`, Linux `AppImage`/`.deb`. |
| **Fine-tuning altyapısı** (`training/`) | Ajanın `agent/ask/plan` davranışını öğretmek için JSONL veri seti + LoRA/QLoRA eğitim betikleri. |

### 1.3 Mimari

```
┌─────────────────────────────┐        HTTP/SSE (/api/*)        ┌───────────────────────────────┐
│  Frontend (React + Vite)    │ ───────────────────────────────▶│  Backend (Python FastAPI)      │
│  - Monaco Editor            │        :3001 → proxy → :8001    │  - REST + SSE endpoints         │
│  - ChatPanel (agent UI)     │◀─────────────────────────────── │  - Agent Engine (tool loop)     │
│  - VivadoPanel/HardwareBar  │        streaming events         │  - Icarus / Vivado / RISC-V      │
│  - WaveformViewer           │                                  │    toolchain çağrıları          │
└─────────────┬────────────────┘                                └───────────────┬─────────────────┘
              │ Electron paketlemesinde                                          │
              ▼                                                                  ▼
┌─────────────────────────────┐                                  Ollama (yerel) / OpenRouter /
│  Electron (masaüstü kabuğu) │ ─── child_process spawn ───────▶  Moonshot / (opsiyonel) Gemini
│  main.ts: pencere + backend │
│  süreç yönetimi              │
└─────────────────────────────┘
```

Uygulama her zaman iki sürecin birlikte çalışmasını gerektirir: **frontend** (Vite, geliştirmede `:3001`) ve **backend** (FastAPI, `:8001`). Tüm iş mantığı, araç çalıştırma ve LLM çağrıları backend'de yaşar; frontend yalnızca `src/services/api.ts` üzerinden bu backend'e istek atar.

### 1.4 Kurulum ve çalıştırma

**Gereksinimler:** Node.js ≥ 18, Python 3.10+, Icarus Verilog (simülasyon için), opsiyonel olarak Ollama, Xilinx Vivado, RISC-V GCC toolchain.

```bash
# 1) Ortam değişkenleri
cp src/AkyuzIDE/.env.example src/AkyuzIDE/.env    # gerekirse düzenleyin

# 2) Backend
cd src/AkyuzIDE/server
pip install -r requirements.txt
uvicorn main:app --reload --port 8001

# 3) Frontend (ayrı bir terminalde)
cd src/AkyuzIDE
npm install
npm run dev          # :3001, /api isteklerini :8001'e proxy'ler

# 4) Masaüstü paketi (opsiyonel)
npm run build:desktop   # → release/ klasörüne Windows/Linux paketi

# 5) Docker ile tek konteyner (opsiyonel)
docker compose up --build
```

Ayrıntılı kurulum seçenekleri (Linux otomatik kurulum betiği `setup.sh`, tüm `npm` script'leri, klasör yapısı) için bkz. [`src/AkyuzIDE/README.md`](src/AkyuzIDE/README.md).

---

## 2. akyuz-rv32i

*(Kaynak kod: [`src/akyuz-rv32i/`](src/akyuz-rv32i/) — ayrıntılı README: [`src/akyuz-rv32i/README.md`](src/akyuz-rv32i/README.md))*

RISC-V **RV32I** komut kümesini uygulayan, 5 aşamalı pipeline'lı bir işlemci çekirdeğinin geliştirilme sürecini üç ayrı evrim aşamasında (prototipte) belgeler: temel pipeline doğrulamasından başlayıp, bir Wishbone tabanlı SoC'ye, ardından FPGA üzerinde çalışan bir VGA/oyun konsoluna ve son olarak bir kamera/VGA gösterim sistemine kadar genişler.

### 2.1 Ortak mimari temeller

Üç prototip de aynı temel 5 aşamalı pipeline tasarımını paylaşır:

```
IF (Fetch) → ID (Decode) → EX (Execute) → MEM (Memory) → WB (Writeback)
```

- **Forwarding unit**: EX/MEM ve MEM/WB aşamalarındaki sonuçları, register dosyasına yazılmadan doğrudan EX aşamasına yönlendirerek çoğu veri bağımlılığını (RAW hazard) ekstra durdurma olmadan çözer.
- **Hazard detection unit**: Forwarding'in çözemediği tek durum olan load-use bağımlılığında pipeline'ı 1 çevrim durdurur (stall).
- **Branch/JAL/JALR**: Dal koşulu EX aşamasında çözülür; yanlış getirilen komutlar IF/ID ve ID/EX register'larına flush uygulanarak iptal edilir.

### 2.2 Prototip 2 — Wishbone SoC

*(bkz. [`src/akyuz-rv32i/RV32_Prototip_2/README.md`](src/akyuz-rv32i/RV32_Prototip_2/README.md))*

Çekirdeği bir **Wishbone B4** veri yolu üzerinden GPIO, UART, SPI ve Timer çevre birimlerine bağlayan, simülasyon odaklı bir SoC. Byte/halfword load-store desteği (LB/LH/LW/LBU/LHU, SB/SH/SW), 4KB IMEM + 4KB DMEM, adres kod çözümlü bir memory map (`0x4000_0000` bölgesinde çevre birimleri) içerir. Icarus Verilog ile çekirdek düzeyinde 8 test senaryosu (forwarding, load-use stall, branch flush, byte/halfword erişim) çalıştırılabilir.

### 2.3 Snake & Mayın Tarlası — FPGA oyun konsolu

*(bkz. [`src/akyuz-rv32i/RV32_Snake_ve_Mayin_Tarlasi/README.md`](src/akyuz-rv32i/RV32_Snake_ve_Mayin_Tarlasi/README.md), eski adı: RV32_Prototip_3)*

Çekirdeği gerçek bir **Digilent Basys 3** FPGA kartına taşıyan ana prototip: 80×30 karakterlik bir VGA donanım terminali, terminal üzerinden çalışan **Snake** ve **Mayın Tarlası** oyunları, bitstream'i yeniden yüklemeden yazılım güncellemesi yapan bir **UART donanım bootloader**'ı ve tam bir C toolchain akışı (`riscv64-unknown-elf-gcc` → `firmware.bin` → seri port ile yükleme) içerir. Proje başlangıçta Nexys 4 DDR kartında geliştirilmiş, sonrasında Basys 3'e taşınmıştır; kapsamlı sentez/timing/güç raporları mevcuttur (LUT %13.4, BRAM %20, WNS +9.109 ns @ 50 MHz).

### 2.4 Prototip 4 — Kamera/VGA SoC

*(bkz. [`src/akyuz-rv32i/RV32_Prototip_4/README.md`](src/akyuz-rv32i/RV32_Prototip_4/README.md))*

Snake/Mayın Tarlası altyapısı üzerine kurulmuş, sadeleştirilmiş bir **OV7670 kamera modülü + VGA gösterim** SoC'u. Kameradan alınan görüntü gri tonlamaya çevrilip bir "resim içinde resim" (PIP) penceresinde VGA ekranın metin katmanıyla birlikte gösterilir. Aynı UART donanım bootloader'ı ve C toolchain akışı burada da kullanılır.

### 2.5 Bilinen sorunlar ve eksikler

Kod incelemesi sırasında tespit edilen ve ilgili alt README'lerde ayrıntılandırılan noktalar:

- **Prototip 2**: `sim/run_soc_sim.bat` betiği var olmayan bir `tb_soc.v` dosyasını hedefliyor — SoC seviyesi simülasyon şu an çalışmıyor (çekirdek seviyesi simülasyon çalışıyor).
- **Prototip 4**: `main.c` ekranda "SW[15] ile kamera/metin geçişi" yazsa da donanımda `sw[15]` hiçbir yerde kullanılmıyor; kamera penceresi her zaman sabit konumda gösteriliyor.
- **akyuz-rv32i kökünde** üç adet tarihsel (7 Haziran 2026) inceleme raporu vardı; bunlar güncelliğini yitirdiği ve biri artık var olmayan bir klasör adına (`RV32_Prototip_3`) atıfta bulunduğu için [`src/akyuz-rv32i/docs/eski-raporlar/`](src/akyuz-rv32i/docs/eski-raporlar/) altına arşivlenmiş, güncel README'lere yönlendirme eklenmiştir.

---

## 3. Depo yapısı

```
.
├── README.md                  # Bu dosya — projenin tek ve ana giriş noktası
├── report.pdf                  # Nihai bitirme projesi raporu
├── src/
│   ├── AkyuzIDE/                # IDE kaynak kodu (React/Vite + FastAPI + Electron), kendi README.md'si var
│   └── akyuz-rv32i/             # RV32I çekirdek prototipleri (3 alt klasör), kendi README.md'si var
├── docs/
│   ├── diyagramlar/              # Mimari/iş akışı diyagramları, Basys3 referans fotoğrafları
│   └── proje-planlama/           # İş paketi zaman çizelgesi (TÜBİTAK 2209)
├── simulations/                 # Konsolide simülasyon çıktıları (bkz. simulations/README.md — henüz boş)
├── results/
│   ├── demo-fotograflari/        # Gerçek donanım üzerinde çalışan sistemin fotoğrafları
│   └── egitim-metrikleri/        # AkyuzIDE agent fine-tuning eğitim/TensorBoard sonuçları
└── presentation/
    └── ekran-goruntuleri/         # AkyuzIDE tanıtım/demo ekran görüntüleri
```

Alt klasörlerdeki README'ler (`src/AkyuzIDE/README.md`, `src/akyuz-rv32i/README.md` ve üç prototipin kendi README'leri), burada özetlenen her konuyu çok daha ayrıntılı olarak (mimari, register haritaları, dosya dosya kod açıklaması, kurulum adımları) ele alır — derinlemesine bilgi için bu belgelere bakın. Görsellerin açıklamaları için `docs/README.md`, `results/README.md` ve `presentation/README.md` dosyalarına bakın.

> **`simulations/` klasörü şu an boş** — içine ne konması gerektiği `simulations/README.md`'de açıklanmıştır.

---

## 4. Katkıda bulunan

**Taha Tahsin Akyüz**
E-posta: takyuz515@gmail.com
