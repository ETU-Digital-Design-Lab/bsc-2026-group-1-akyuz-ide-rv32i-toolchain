> **Not (arşiv):** Bu rapor 7 Haziran 2026 tarihli, tarihsel bir ara değerlendirmedir. Güncel ve kapsamlı mimari/kullanım dokümantasyonu için [`../../RV32_Prototip_4/README.md`](../../RV32_Prototip_4/README.md) dosyasına bakın. Bu dosya yalnızca geliştirme sürecinin kaydı olarak saklanmaktadır.

# RV32_Prototip_4 — İnceleme Raporu

**Tarih:** 7 Haziran 2026  
**Konum:** `RV32_Prototip_4/`  
**Amaç:** Prototip 3'ün sadeleştirilmiş ve optimize edilmiş kamera/VGA SoC versiyonu

---

## 1. Genel Özet

Prototip 4, Prototip 3'ün **kamera + VGA entegrasyonunu** yeniden düzenleyen, kaynak kullanımını azaltan ve kullanıcı deneyimini iyileştiren evrim aşamasıdır. İşlemci çekirdeği ve SoC bellek haritası Prototip 3 ile **aynıdır**; farklar üst seviye entegrasyon ve kamera pipeline'ında yoğunlaşır.

| Özellik | Değer |
|---------|-------|
| İşlemci | RV32I, 5 aşamalı pipeline (`rv32_core.v`) — P3 ile aynı |
| SoC | `rv32_soc.v` — P3 ile aynı bellek haritası |
| FPGA | Basys 3 (Artix-7 xc7a35tcpg236-1) |
| Top modül | `basys3_soc_cam_top.v` (tek top) |
| XDC | `basys3_soc_cam.xdc` (tek dosya) |
| Kamera | OV7670, 160×120 grayscale PIP |
| VGA | 80×30 terminal + kamera picture-in-picture |

---

## 2. Tasarım Amacı ve Ne Yapıyor?

Prototip 4 şu problemleri çözer:

1. **Bellek tasarrufu:** 320×240×12-bit framebuffer yerine 160×120×8-bit grayscale
2. **Eşzamanlı kullanım:** Kamera ve terminal aynı anda görünür (PIP overlay)
3. **Sadeleştirme:** Gereksiz top modüller ve 7-segment display kaldırıldı
4. **Kamera güvenilirliği:** Hard reset timer, freeze frame, gelişmiş XDC timing
5. **Görüntü kalitesi:** Gamma correction (sqrt) ile karanlık alanları güçlendirme

Kullanım senaryosu: İşlemci VGA terminalinde uygulama çalıştırırken, ekranın sağ üst köşesinde (400,50)–(560,170) canlı kamera görüntüsü görünür.

---

## 3. Dosya Yapısı

```
RV32_Prototip_4/
├── rtl/
│   ├── basys3_soc_cam_top.v    # Tek top-level (PIP + kamera)
│   ├── basys3_soc_cam.xdc      # Pin kısıtları
│   ├── rv32_core.v             # CPU (P3 ile aynı)
│   ├── rv32_soc.v              # SoC wrapper (P3 ile aynı)
│   ├── hw_bootloader.v         # UART bootloader
│   ├── imem.v, dmem.v          # Bellek
│   ├── vga_terminal.v          # Terminal kontrolcü
│   ├── vga_text_ctrl.v         # Font render
│   ├── vga_sync.v              # VGA timing
│   ├── char_buffer.v, font_rom.v
│   ├── ov7670_sccb_init.v      # Kamera config
│   ├── ov7670_capture.v        # 160×120 luminance capture
│   ├── cam_framebuffer.v       # 19200×8-bit BRAM
│   ├── vga_cam_display.v       # PIP window renderer
│   └── uart_tx.v, uart_rx.v
└── tests/
    ├── vga_test.hex
    └── c_toolchain/            # C derleme + upload
```

**Prototip 3'te olup P4'te olmayanlar:**
- `basys3_top.v` (7-segment)
- `basys3.xdc`
- `basys3_ov7670_vga_top.v`
- `basys3_ov7670_vga.xdc`
- `docs/` klasörü (sentez raporları)
- Snake oyunu kaynak kodu (`main.c` yok, sadece toolchain iskeleti)

---

## 4. Top-Level: `basys3_soc_cam_top.v`

### 4.1 Mimari Diyagram

```
                    ┌─────────────────────────────────────────┐
  clk100 ──────────►│ Saat bölücü → clk_soc (50MHz)          │
                    │              → pclk (25MHz)             │
                    │              → ov7670_xclk              │
                    └─────────────────────────────────────────┘
                                        │
        ┌───────────────────────────────┼───────────────────────────────┐
        ▼                               ▼                               ▼
   rv32_soc                      vga_terminal                      ov7670_sccb_init
   (CPU+MMIO)                   (char buffer)                     (kamera config)
        │                               │                               │
        │                               ▼                               ▼
        │                        vga_text_ctrl                    ov7670_capture
        │                        (soc_vga_r/g/b)                  (160×120 Y8)
        │                               │                               │
        │                               │                               ▼
        │                               │                        cam_framebuffer
        │                               │                               │
        │                               │                               ▼
        │                               │                        vga_cam_display
        │                               │                        (PIP window)
        │                               │                               │
        └───────────────────────────────┴─────────── PIP MUX ───────────┘
                                              │
                                              ▼
                                         VGA çıkışı
```

### 4.2 Saat ve Reset

- **clk_soc:** 50 MHz (100 MHz toggle + BUFG)
- **pclk:** 25 MHz (clk_soc toggle + BUFG)
- **ov7670_xclk:** pclk'e bağlı
- **Reset:** SW[0] ile senkron reset
- **Kamera hard reset:** 100 MHz'de sayaç; `cam_rst_cnt > 0x10000` sonrası `ov7670_reset` aktif
- **Kamera enable:** `cam_rst_n = rst_n_sync & cam_rst_n_reg & !btn_rst`

### 4.3 PIP (Picture-in-Picture) Mantığı

Kamera penceresi koordinatları: **(400, 50) – (560, 170)** → 160×120 piksel

```verilog
wire in_cam_window = (hcount >= 400 && hcount < 560 &&
                      vcount >= 50  && vcount < 170);

assign vga_r = in_cam_window ? cam_vga_r : soc_vga_r;
assign vga_g = in_cam_window ? cam_vga_g : soc_vga_g;
assign vga_b = in_cam_window ? cam_vga_b : soc_vga_b;
```

Prototip 3'teki SW[15] tam ekran geçişi yerine **her zaman overlay** kullanılır.

### 4.4 Kullanıcı Kontrolleri

| Giriş | İşlev |
|-------|-------|
| SW[0] | Sistem reset |
| SW[1] | Freeze frame (kamera buffer'a yazmayı durdur) |
| BTNC (`btn_rst`) | Kamera reset'i tetikler |
| BTNU/D/L/R | SoC button register'a bağlı |

---

## 5. Kamera Pipeline (P3'ten Farklar)

### 5.1 `ov7670_capture.v`

| Özellik | Prototip 3 | Prototip 4 |
|---------|------------|------------|
| Çözünürlük | 320×240 | **160×120 (QQVGA)** |
| Çıkış formatı | 12-bit RGB (`fb_data[11:0]`) | **8-bit luminance** |
| Renk dönüşümü | RGB565 → 12-bit direkt | RGB565 → Y = (R+2G+B)/4 |
| Adres genişliği | 17-bit (76800 pixel) | 15-bit (19200 pixel) |
| Adres hesabı | `y*320 + x` | `(y<<7)+(y<<5)+x` (shift-add, DSP yok) |

Luminance hesabı:
```verilog
wire [7:0] r8 = {pix565[15:11], pix565[15:13]};
wire [7:0] g8 = {pix565[10:5],  pix565[10:9]};
wire [7:0] b8 = {pix565[4:0],   pix565[4:2]};
wire [9:0] ysum = r8 + (g8<<1) + b8;
wire [7:0] lum8 = ysum[9:2];  // /4
```

### 5.2 `cam_framebuffer.v`

| Özellik | Prototip 3 | Prototip 4 |
|---------|------------|------------|
| Derinlik | 76800 × 12-bit | **19200 × 8-bit** |
| Bellek tipi | Generic array | `(* ram_style = "block" *)` BRAM |
| Tahmini BRAM | ~1152 Kbit | **~153 Kbit (~10× BRAM18)** |

### 5.3 `vga_cam_display.v`

Prototip 3: Tam ekran 320×240 render, kendi `vga_sync` instance'ı.

Prototip 4:
- Paylaşımlı `vga_sync` (top-level'dan `hcount`, `vcount`, `active` alır)
- Sadece PIP penceresi içinde render
- **Gamma correction:** 0–255 → 0–15 sqrt tablosu (karanlık detayları güçlendirir)
- VGA çıkışı: R=G=B=gray (monokrom)

---

## 6. İşlemci ve SoC (Prototip 3 ile Aynı)

### 6.1 `rv32_core.v`

5 aşamalı pipeline, forwarding, hazard detection, byte/halfword load-store. Değişiklik yok.

### 6.2 `rv32_soc.v` Bellek Haritası

| Adres | İşlev |
|-------|-------|
| `0x0000_0000` – `0x0000_0FFF` | IMEM 4 KB |
| `0x0001_0000` – `0x0001_0FFF` | DMEM 4 KB |
| `0x0002_0000` | UART TX |
| `0x0002_0004` | UART status |
| `0x0002_0008` | LED |
| `0x0002_000C` | Switch |
| `0x0002_0010` | Cycle counter |
| `0x0002_0014` | Button |
| `0x0003_0000` – `0x0003_257F` | VGA terminal |

### 6.3 Bootloader

`hw_bootloader.v`: Magic `0xDEADBEEF` + uzunluk + payload → IMEM. Prototip 3 ile aynı protokol.

---

## 7. VGA Alt Sistemi

Prototip 3 ile aynı modüller:

- `vga_terminal.v` — 80×30 terminal, virtual scroll, graphics mode
- `char_buffer.v` — dual-port BRAM
- `vga_text_ctrl.v` — font render
- `vga_sync.v` — 640×480 timing
- `font_rom.v` + `font8x16.hex`

**Fark:** `vga_text_ctrl` artık top-level'dan `hcount`, `vcount`, `active` sinyallerini alır (paylaşımlı sync).

---

## 8. XDC: `basys3_soc_cam.xdc`

Prototip 3'ün `basys3_soc_cam.xdc` dosyasına çok benzer; ek iyileştirmeler:

| İyileştirme | Açıklama |
|-------------|----------|
| `create_clock -period 40ns` | `ov7670_pclk` için 25 MHz kamera clock tanımı |
| `set_clock_groups -asynchronous` | sys_clk ↔ cam_pclk asenkron gruplar |
| `PULLUP TRUE` | Hem `ov7670_siod` hem `ov7670_sioc` |

### Pin Özeti

| Grup | Pin Sayısı |
|------|------------|
| Saat | 1 (W5) |
| Butonlar | 5 |
| Switch | 16 |
| LED | 16 |
| UART | 2 |
| VGA RGB + sync | 14 |
| OV7670 | 16 (pwdn, reset, xclk, pclk, vsync, href, sioc, siod, data[7:0]) |

**Eksik (P3'te var, P4'te yok):** 7-segment display pinleri

---

## 9. LED Diagnostik

```verilog
assign led = {hb[24], boot_loading, sccb_ack_error,
              ov7670_vsync, ov7670_href, ov7670_pclk,
              ov7670_data[7:0], wr_en, sccb_done};
```

| Bit | Anlam |
|-----|-------|
| [15] | Heartbeat |
| [14] | Bootloader aktif |
| [13] | SCCB ACK hatası |
| [12] | VSYNC |
| [11] | HREF |
| [10] | PCLK |
| [9:2] | DATA[7:0] |
| [1] | Frame write enable |
| [0] | SCCB config tamamlandı |

---

## 10. C Toolchain

```
tests/c_toolchain/
├── main.c                  # Basit test (P3'teki Snake yok)
├── crt0.S
├── prototip4_linker.ld     # P4 linker script
├── Makefile / build.bat
└── upload.py
```

Derleme akışı Prototip 3 ile aynı: `riscv64-unknown-elf-gcc` → `.bin` → UART bootloader.

---

## 11. Simülasyon

Prototip 4'te ayrı `sim/` klasörü **yok**. Core simülasyonu için Prototip 3'ün `sim/tb_rv32_core.v` kullanılabilir (aynı `rv32_core.v`).

---

## 12. Sentez Durumu

Prototip 4 klasöründe **sentez raporu veya Vivado projesi bulunmuyor**. Ancak:

- RTL, Vivado-friendly pattern'ler içeriyor (`ram_style = "block"`, LUTRAM DMEM şablonu)
- XDC timing kısıtları Prototip 3'ten geliştirilmiş
- Kaynak kullanımı P3'e göre **daha düşük** olması beklenir:
  - Framebuffer: 153 Kbit vs ~922 Kbit (12-bit × 76800)
  - Tek top → daha az IO (7-seg yok)
  - PIP → paylaşımlı vga_sync

**Tahmini sentez sonuçları** (P3 verilerinden extrapolasyon):

| Kaynak | P3 | P4 (tahmin) |
|--------|-----|-------------|
| LUT | %4 | %3–4 |
| BRAM | 2 + büyük cam FB | 2 + ~10 BRAM18 |
| IO | %31 | ~%25 (7-seg yok) |

Gerçek sentez için Vivado'da `basys3_soc_cam_top` + `basys3_soc_cam.xdc` ile implementation gerekir.

---

## 13. Prototip 3 → 4 Evrim Özeti

| Konu | Prototip 3 | Prototip 4 |
|------|------------|------------|
| **Felsefe** | Tam özellikli, çoklu top | Tek top, odaklı |
| **VGA + kamera** | SW15 ile tam ekran geçiş | PIP overlay (eşzamanlı) |
| **Kamera FB** | 76800×12-bit | 19200×8-bit BRAM |
| **Renk** | 12-bit RGB | 8-bit grayscale + gamma |
| **7-segment** | Var | Kaldırıldı |
| **Freeze frame** | Yok | SW[1] |
| **Cam hard reset** | Yok | Timer tabanlı |
| **XDC** | 3 dosya | 1 dosya (geliştirilmiş timing) |
| **Dokümantasyon** | Kapsamlı (5+ rapor) | Yok (bu rapor ilk analiz) |
| **Uygulama** | Snake oyunu | Toolchain iskeleti |

---

## 14. Sonuç

**RV32_Prototip_4**, Prototip 3'ün işlemci ve SoC altyapısını koruyarak **kamera/VGA entegrasyonunu optimize eden** sadeleştirilmiş versiyondur. PIP modu, küçük grayscale framebuffer ve gamma correction ile hem bellek hem kullanıcı deneyimi iyileştirilmiştir. Sentez doğrulaması henüz bu klasörde dokümante edilmemiş; RTL ve XDC Prototip 3'ün başarılı sentez deneyimine dayanarak hazırlanmıştır.

**Önerilen sonraki adımlar:**
1. Vivado'da P4 top'unu sentezleyip kaynak raporu almak
2. PIP penceresinde kamera + terminal birlikte donanım testi
3. SW[1] freeze frame ve hard reset davranışını doğrulamak
