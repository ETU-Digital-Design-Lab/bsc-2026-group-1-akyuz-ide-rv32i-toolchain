> **Not (arşiv):** Bu rapor 7 Haziran 2026 tarihli, tarihsel bir ara değerlendirmedir ve klasörün eski adı olan **`RV32_Prototip_3/`**'ü referans alır — bu klasör daha sonra **`RV32_Snake_ve_Mayin_Tarlasi/`** olarak yeniden adlandırılmıştır. Güncel ve kapsamlı mimari/kullanım dokümantasyonu için [`../../RV32_Snake_ve_Mayin_Tarlasi/README.md`](../../RV32_Snake_ve_Mayin_Tarlasi/README.md) dosyasına bakın. Bu dosya yalnızca geliştirme sürecinin kaydı olarak saklanmaktadır.

# RV32_Prototip_3 — İnceleme Raporu

**Tarih:** 7 Haziran 2026  
**Konum:** `RV32_Prototip_3/` (güncel adı: `RV32_Snake_ve_Mayin_Tarlasi/`)  
**Amaç:** Basys 3 FPGA üzerinde çalışan tam RV32I SoC + VGA terminal + OV7670 kamera + UART bootloader

---

## 1. Genel Özet

Prototip 3, işlemci tasarımını **gerçek FPGA donanımına** taşıyan ana prototiptir. Hedef kart **Digilent Basys 3** (Artix-7 `xc7a35tcpg236-1`), sistem saati 100 MHz'den 50 MHz'ye bölünür.

| Özellik | Değer |
|---------|-------|
| İşlemci | RV32I, 5 aşamalı pipeline (`rv32_core.v`) |
| Bus | MMIO adres decode (Wishbone yok) |
| FPGA | Basys 3, Vivado 2024.1 |
| Sistem saati | 50 MHz (100 MHz / 2) |
| Pixel saati | 25 MHz (VGA) |
| UART | 115200 baud |
| Sentez | Tamamlandı, WNS ≈ +5 ns |
| Bitstream | Üretildi (repo'da .gitignore ile hariç) |

**Yazılım hedefi:** VGA terminal üzerinde **Snake oyunu** (`tests/c_toolchain/main.c`).

---

## 2. Tasarım Amacı ve Ne Yapıyor?

Prototip 3 şunları başarır:

1. RV32I işlemcisini FPGA'da sentezleyip zamanlama doğrulaması yapmak
2. **80×30 karakter VGA terminali** ile metin tabanlı UI sunmak
3. **UART bootloader** ile bitstream yenilemeden yazılım güncellemek
4. **OV7670 kamera** modülünü SCCB ile yapılandırıp VGA'da görüntülemek
5. GPIO (LED, switch, button) ile etkileşimli uygulama (oyun) çalıştırmak
6. **C toolchain** (`riscv64-unknown-elf-gcc`) ile uygulama geliştirmek

---

## 3. Top-Level Modüller

Prototip 3'te **üç farklı top-level** tasarım vardır:

| Modül | XDC | Açıklama |
|-------|-----|----------|
| `basys3_top.v` | `basys3.xdc` | SoC + VGA + 7-segment display + UART debug |
| `basys3_soc_cam_top.v` | `basys3_soc_cam.xdc` | SoC + VGA + OV7670 kamera (SW15 ile kamera/metin geçişi) |
| `basys3_ov7670_vga_top.v` | `basys3_ov7670_vga.xdc` | Sadece kamera + VGA (işlemci yok) |

Ana entegrasyon noktası: **`basys3_soc_cam_top.v`**

---

## 4. RTL Modül Envanteri

### 4.1 İşlemci Çekirdeği

| Dosya | Açıklama |
|-------|----------|
| `rv32_core.v` | 5 aşamalı pipeline CPU; `EXT_DMEM=1` ile harici bellek bus'u |
| `rv32_control.v` | Komut dekoderi; FENCE/SYSTEM → NOP |
| `alu.v` | 11 ALU işlemi + zero/lt/ltu flag |
| `regfile.v` | 32×32-bit register file, x0 sabit 0 |
| `pc.v` | Program counter |
| `if_id_reg.v`, `id_ex_reg.v`, `ex_mem_reg.v`, `mem_wb_reg.v` | Pipeline register'ları |
| `forwarding_unit.v` | EX/MEM → EX bypass |
| `hazard_detection_unit.v` | Load-use stall |

**Özellikler:**
- Branch koşulu EX aşamasında ALU flag'leri ile değerlendirilir
- Load sign/zero extension WB'de `funct3_wb` + adres LSB'lerine göre
- IMEM write port: bootloader için Port B erişimi
- Debug çıkışları: `debug_pc`, `debug_instr`, `debug_alu_result`

### 4.2 Bellek

| Dosya | Açıklama |
|-------|----------|
| `imem.v` | 4–8 KB instruction BRAM, dual-port (CPU fetch + bootloader write) |
| `dmem.v` | 4 KB data RAM; 4×8-bit LUTRAM şeritleri (byte-enable uyumlu) |

### 4.3 SoC ve Bootloader

| Dosya | Açıklama |
|-------|----------|
| `rv32_soc.v` | Adres decode, periferik MMIO, VGA write port |
| `hw_bootloader.v` | UART RX → magic `0xDEADBEEF` → uzunluk → IMEM yazma |
| `uart_tx.v`, `uart_rx.v` | Seri haberleşme |

### 4.4 VGA Alt Sistemi

| Dosya | Açıklama |
|-------|----------|
| `vga_terminal.v` | Donanım terminal kontrolcüsü (cursor, scroll, `\n`/`\r`, clear) |
| `char_buffer.v` | 80×30 karakter + renk BRAM (dual-port) |
| `vga_text_ctrl.v` | Font ROM + pixel render |
| `vga_sync.v` | 640×480 @ 60 Hz timing |
| `font_rom.v` | 8×16 font, LUT tabanlı |
| `font8x16.hex` | Font verisi |

**VGA Terminal Register Map** (`0x0003_xxxx`, `cpu_reg = addr[1:0]`):

| Register | İşlev |
|----------|-------|
| `2'b00` DATA | Karakter yaz; [7:0]=ASCII, [11:8]=fg, [15:12]=bg |
| `2'b01` CURSOR | İmleç konumu: [12:8]=satır, [6:0]=sütun |
| `2'b10` CTRL | bit0=clear screen, bit1=graphics mode (plasma efekti) |

Virtual scroll: `scroll_base` ile satır kaydırma, veri kopyalamadan.

### 4.5 Kamera Alt Sistemi

| Dosya | Açıklama |
|-------|----------|
| `ov7670_sccb_init.v` | SCCB/I2C ile kamera register yapılandırması |
| `ov7670_capture.v` | RGB565 piksel yakalama, 320×240 downscale |
| `cam_framebuffer.v` | 76800×12-bit dual-clock BRAM |
| `vga_cam_display.v` | Tam ekran kamera görüntüsü (320×240, 12-bit renk) |

---

## 5. Bellek Haritası (`rv32_soc.v`)

| Adres | Register / Alan | Erişim |
|-------|-----------------|--------|
| `0x0000_0000` – `0x0000_0FFF` | IMEM (4 KB) | Fetch + bootloader write |
| `0x0001_0000` – `0x0001_0FFF` | DMEM (4 KB) | LW/SW/LB/SB/... |
| `0x0002_0000` | UART TX data | W: byte gönder |
| `0x0002_0004` | UART TX status | R: bit0 = tx_ready |
| `0x0002_0008` | LED register | RW: 16-bit |
| `0x0002_000C` | Switch register | R: 16-bit |
| `0x0002_0010` | Cycle counter | R: 32-bit |
| `0x0002_0014` | Button register | R: 5-bit |
| `0x0003_0000` – `0x0003_257F` | VGA char buffer | W: karakter hücresi |

C yazılımında kullanım (`main.c`):

```c
#define LED_REG    (*(volatile unsigned int *)0x00020008)
#define VGA_DATA   (*(volatile unsigned int *)0x00030000)
#define VGA_CURSOR (*(volatile unsigned int *)0x00030004)
#define VGA_CTRL   (*(volatile unsigned int *)0x00030008)
```

---

## 6. XDC Dosyaları

### 6.1 `basys3.xdc` — Ana SoC (7-segment dahil)

**Hedef:** `basys3_top.v`  
**FPGA:** xc7a35tcpg236-1

| Grup | Pinler | Notlar |
|------|--------|--------|
| Saat | W5 (`clk100`) | 100 MHz, `create_clock -period 10ns` |
| Butonlar | U18, T18, W19, T17, U17 | BTNC + yön tuşları |
| Switch | V17–R2 (SW0–SW15) | SW0 = reset |
| LED | U16–L1 (LD0–LD15) | Debug mux ile PC/ALU gösterimi |
| 7-Segment | U7–W7, V7 (dp), U2–W4 (an) | PC değeri gösterimi |
| UART | A18 (TX), B18 (RX) | CP2102 USB-serial |
| VGA | G19–J18 (RGB 4-bit), P19/R19 (sync) | Resistor-DAC, 16 renk |

Bitstream ayarları: `CFGBVS VCCO`, `CONFIG_VOLTAGE 3.3`

### 6.2 `basys3_soc_cam.xdc` — SoC + Kamera

**Hedef:** `basys3_soc_cam_top.v`

Yukarıdakilere ek olarak **OV7670** pinleri:

| Sinyal | Pin | Not |
|--------|-----|-----|
| `ov7670_pwdn` | A14 | Power down |
| `ov7670_reset` | A15 | Reset |
| `ov7670_xclk` | M18 | 25 MHz kamera saati |
| `ov7670_pclk` | M19 | Pixel clock (asenkron grup) |
| `ov7670_vsync` | P17 | Frame sync |
| `ov7670_href` | N17 | Line valid |
| `ov7670_sioc/siod` | R18/P18 | SCCB (I2C), pull-up |
| `ov7670_data[7:0]` | A16–L17 | 8-bit veri |

Özel kısıtlar:
- `CLOCK_DEDICATED_ROUTE FALSE` → `ov7670_pclk` (PMOD pin)
- `set_clock_groups -asynchronous` → sys_clk vs cam_pclk

### 6.3 `basys3_ov7670_vga.xdc`

Kamera-only top için ayrı XDC (işlemci olmadan kamera testi).

---

## 7. Saat Mimarisi

```
clk100 (100 MHz, board oscillator)
    │
    ├─► clk_div toggle → BUFG → clk_soc (50 MHz)  ← CPU, UART, terminal
    │
    └─► pclk_r toggle → BUFG → pclk (25 MHz)      ← VGA, kamera xclk
```

Reset: SW0 aktifken senkron reset (`rst_sync` 2-FF).

---

## 8. Kamera Entegrasyonu (`basys3_soc_cam_top.v`)

Akış:

1. `ov7670_sccb_init` → kamera register'larını 100 MHz'de yapılandırır
2. SCCB `done` sinyali `ov7670_pclk` domain'e sync edilir
3. `ov7670_capture` → RGB565 → 12-bit renk, 320×240 framebuffer
4. `cam_framebuffer` → dual-clock BRAM (wr: pclk, rd: pclk)
5. `vga_cam_display` → tam ekran kamera çıkışı
6. **SW[15]** = 1 → kamera görüntüsü; 0 → SoC VGA terminali

LED diagnostik:
- led[15]: heartbeat
- led[14]: bootloader aktif
- led[13]: SCCB ACK hatası
- led[12:2]: kamera pin monitörü
- led[1]: frame write
- led[0]: SCCB done

---

## 9. Bootloader (`hw_bootloader.v`)

Protokol:

1. UART'tan magic byte dizisi: `0xDE 0xAD 0xBE 0xEF`
2. 4 byte little-endian payload uzunluğu
3. CPU halt (`cpu_reset_n = 0`)
4. Payload byte'ları 32-bit word olarak IMEM'e yazılır
5. CPU reset release → yeni program çalışır

Python araçları: `tests/send_firmware.py`, `tests/c_toolchain/upload.py`

---

## 10. C Toolchain

```
tests/c_toolchain/
├── main.c              # Snake oyunu
├── btn_test.c          # Buton testi
├── crt0.S              # Startup
├── prototip3_linker.ld # Linker script
├── Makefile / build.bat
└── upload.py           # UART firmware yükleme
```

Derleme: `riscv64-unknown-elf-gcc` → `.elf` → `objcopy` → `.bin` → UART upload

---

## 11. Simülasyon

| Dosya | Açıklama |
|-------|----------|
| `sim/tb_rv32_core.v` | Core testbench |

Dokümantasyona göre:
- Davranışsal sim: **17/17 test geçti**
- Post-synthesis timing sim: **17/17 test geçti** (SDF annotated)

---

## 12. Sentez ve Implementation Sonuçları

Kaynak: `2026-03-18_prototip3_rapor.md`, `docs/2026_03_04_FPGA_Rapor_v2.md`

### 12.1 Zamanlama

| Metrik | Değer |
|--------|-------|
| Hedef frekans | 50 MHz (20 ns period) |
| WNS (Worst Negative Slack) | +4.866 ns ~ +5.17 ns |
| Timing violations | 0 |
| İlk deneme (100 MHz) | -2.243 ns slack → başarısız |

### 12.2 Kaynak Kullanımı (Post-Implementation)

| Kaynak | Kullanım | Oran |
|--------|----------|------|
| LUT | ~1932 / 63400 | %4 |
| FF | ~1700 / 126800 | %1 |
| BRAM (RAMB36) | 2 | %1 |
| LUTRAM (DMEM) | 128× RAM256X1S | %3 |
| IO | 67 / 210 | %31 |
| BUFG | 2 | %6 |
| Güç | ~0.12 W | — |

### 12.3 Bellek Çıkarımı

- **DMEM:** 4× 1K×8 LUTRAM şeridi (byte-write uyumlu)
- **Char buffer:** 4K×16 BRAM (dual-port)
- **Font ROM:** LUT tabanlı distributed ROM (~16 Kbit)
- **IMEM:** BRAM inference

### 12.4 Bilinen Uyarılar

- `vga_g[2]` A7 pini Vivado 2024.1'de geçersiz sayılıyor (Digilent XDC regresyonu)
- UCIO-1 severity Warning ile aşıldı
- 178 synthesis uyarısı (çoğu BRAM attribute, düzeltildi)

### 12.5 Bitstream

- Üretildi (`fpga_top.bit`, ~87 KB)
- Repo'da `.gitignore` ile hariç tutulmuş
- JTAG ile yükleme; kart kapanınca silinir

---

## 13. Test Dosyaları

| Dosya | Açıklama |
|-------|----------|
| `tests/vga_test.hex` | VGA terminal test programı |
| `tests/fpga_test.hex` | FPGA doğrulama |
| `tests/rv32i_full_test.hex` | Tam RV32I komut testi |
| `tests/uart_regdump.hex` | UART register dump |
| `tests/performance_test.hex` | Performans benchmark |
| `tests/performance_test.s` | Assembly kaynak |

---

## 14. Prototip 4 ile Farklar

| Özellik | Prototip 3 | Prototip 4 |
|---------|------------|------------|
| Top modüller | 3 farklı top (basys3, soc_cam, ov7670_only) | Sadece `basys3_soc_cam_top` |
| 7-segment | Var (`basys3_top`) | Yok |
| Kamera çözünürlük | 320×240, 12-bit RGB | 160×120, 8-bit grayscale |
| VGA kamera modu | Tam ekran (SW15 toggle) | PIP penceresi (400,50)–(560,170) |
| Framebuffer | 76800×12-bit | 19200×8-bit BRAM |
| Freeze frame | Yok | SW[1] |
| Kamera hard reset | Yok | Var (timer tabanlı) |
| Gamma correction | Yok | Var (sqrt LUT) |
| XDC | 3 dosya | 1 dosya |

---

## 15. Sonuç

**RV32_Prototip_3**, projenin **tam özellikli FPGA prototipi**dir. İşlemci sentezi doğrulanmış, VGA terminal ve UART bootloader ile gerçek uygulama (Snake oyunu) çalıştırılmış, OV7670 kamera entegrasyonu tamamlanmıştır. Kapsamlı dokümantasyon (teknik raporlar, sentez logları, geliştirme notları) mevcuttur. Prototip 4, bu tasarımın kamera/VGA tarafını sadeleştirip optimize eden evrim aşamasıdır.
