# RV32 Snake & Mayın Tarlası — Donanım ve Derleme Notları

**Tarih:** 9 Haziran 2026
**Kart:** Digilent Basys 3 (Artix-7 `xc7a35tcpg236-1`)
**Araç:** Vivado 2025.2 + Vivado içi RISC-V GCC (`riscv64-unknown-elf-`, GCC 13.4.0)
**Top-level:** `basys3_top.v` &nbsp;|&nbsp; **XDC:** `rtl/basys3.xdc`
**Üretilen bitstream:** `vivado_build/snake_mayin.bit`

---

## 1. Yazılım (firmware) — ne yüklendi, kaç byte?

Kaynak: `tests/c_toolchain/main.c` (Snake + Mayın Tarlası + menü), `crt0.S`, linker: `prototip3_linker.ld`.

Derleme bayrakları: `-march=rv32i -mabi=ilp32 -Os -ffreestanding -nostdlib -nostartfiles -Wl,--no-relax -Wl,--build-id=none` + `libgcc.a` (rv32i/ilp32, sadece `__divsi3/__modsi3/__umodsi3` için).

| Bölüm | Boyut | Konum (VMA) | Açıklama |
|-------|------:|-------------|----------|
| `.text` | 8844 B | `0x0000_0000` | Komutlar (CPU IMEM'den fetch eder) |
| `.rodata` | 406 B | `0x0000_228C` | Sabitler/string'ler (IMEM data-port'tan okunur) |
| `.data` | 24 B | `0x0001_0000` (DMEM), LMA IMEM | İlk değerli globaller — **crt0 IMEM→DMEM kopyalar** |
| `.bss` | 1868 B | `0x0001_0018` (DMEM) | Sıfır globaller — crt0 sıfırlar |

- **IMEM'e gerçekten yüklenen:** `firmware.bin` = **9274 byte** (`.text + .rodata + .data` ilk-değer görüntüsü).
- 4 byte hizalı → **2319 word** (`tests/snake_mayin.hex`).
- IMEM kapasitesi: **16384 byte (4096 word)** → doluluk **%56.6**, boşta **1777 word**.

> Düzeltme 1 — boş ekran: İlk derlemede `.note.gnu.build-id` (alloc, 36 byte) `_start`'ı `0x24`'e itiyordu; program `0x0`'a yükleniyor ama `0x24`'e linklendiği için `.rodata` mutlak adresleri kayıyor ve ekran boş kalıyordu. `-Wl,--build-id=none` ile `_start` tekrar `0x0`'a çekildi.
>
> Düzeltme 2 — init'li globaller: `crt0.S` artık `.data`'yı IMEM(LMA)→DMEM(VMA) kopyalıyor ve `.bss`'i sıfırlıyor (linker `.data ... > DMEM AT > IMEM`). Böylece `speed_lvl=5`, tahta boyutu vb. doğru başlıyor.
>
> Düzeltme 3 — yer: Yeni özellikler (ayar ekranları, değişken tahta) için **IMEM 8 KB → 16 KB**'a çıkarıldı (`rv32_soc IMEM_DEPTH=4096`, linker `IMEM LENGTH=16K`).

### Yeniden derleme
```bash
export PATH=~/2025.2/gnu/riscv/lin/bin:$PATH
cd tests/c_toolchain && make            # firmware.elf/.bin/.hex/.lst
# IMEM hex (word/satır) üretimi tests/snake_mayin.hex içine yapılır
```

---

## 2. Bellek mimarisi (IMEM / DMEM / diğer)

| Blok | Boyut | FPGA'da gerçeklenme | Neden |
|------|-------|---------------------|-------|
| **IMEM** (`imem.v`) | 4096×32 = 16 KB | **Block RAM (true dual-port, ~8× RAMB36)** | Okuma `negedge clk` ile register'lı → BRAM çıkar, ama veri yine aynı çevrim içinde (posedge örneklemeden önce) hazır. Eski asenkron davranışla birebir aynı, pipeline değişmedi |
| **DMEM** (`dmem.v`) | 4 KB | **Distributed RAM (LUTRAM)**, 4×1K×8 şerit | Byte-enable (SB/SH) için 8-bit şeritler |
| **Char buffer** (`char_buffer.v`) | 4K×16 = 64 Kbit | **Block RAM (2× RAMB36E1)** | 80×30 karakter+renk, dual-port, senkron |
| **Font ROM** (`font_rom.v`) | 2048×8 = 16 Kbit | **Distributed ROM (LUT)** | `font8x16.hex`, asenkron LUT ROM |

Adres haritası (`rv32_soc.v`):

| Adres | Alan |
|-------|------|
| `0x0000_0000`–`0x0000_3FFF` | IMEM (16 KB) — fetch + `.rodata`/`.data` görüntüsü + bootloader yazma |
| `0x0001_0000`–`0x0001_0FFF` | DMEM (4 KB) — load/store, stack (`__stack_top=0x10FFC`) |
| `0x0002_0000` / `_0004` | UART TX data / status |
| `0x0002_0008` / `_000C` | LED (W) / Switch (R) |
| `0x0002_0010` / `_0014` | Cycle counter / Button |
| `0x0003_0000`–`0x0003_257F` | VGA karakter buffer |

---

## 3. Sentez & Implementation sonuçları (post-route)

Kaynak: `vivado_build/util.rpt`, `vivado_build/timing.rpt`.

### Kaynak kullanımı — `xc7a35t` (toplam: 20800 LUT, 41600 FF, 50 BRAM36)

| Kaynak | Kullanım | Toplam | Oran | Nerede |
|--------|---------:|-------:|-----:|--------|
| **Slice LUT** | 2779 | 20800 | **%13.4** | mantık + bellek |
| — LUT as Logic | 2267 | 20800 | %10.9 | CPU, VGA, kontrol |
| — LUT as Memory (LUTRAM) | 512 | 9600 | %5.3 | sadece DMEM (4K) |
| **Slice Register (FF)** | 1947 | 41600 | %4.7 | pipeline reg, durum |
| **Block RAM (RAMB36)** | 10 | 50 | **%20.0** | IMEM (16K, ~8) + char buffer (2) |
| **IOB (pin)** | 66 | 106 | %62.3 | clk, btn, sw, led, uart, vga, 7-seg |
| **BUFG (clock buffer)** | 3 | 32 | %9.4 | clk_soc, pclk + 1 |

> IMEM optimizasyonu: `imem.v` okuması `negedge clk` ile register'lanarak Block RAM'e taşındı. Sonuç: **LUT %46.7 → %13.4**, LUTRAM %64 → %5.3, BRAM 2 → 10. Pipeline'a dokunulmadı (negedge yarım-çevrim okuma eski asenkron davranışı korur). Geri kalan LUTRAM yalnızca byte-write'lı DMEM'den.

### Zamanlama (timing) — KARŞILANDI

| Saat | Frekans | Periyot |
|------|--------:|--------:|
| `clk_soc` (CPU/UART/terminal) | 50 MHz | 20 ns |
| `pclk` (VGA piksel) | 25 MHz | 40 ns |

| Metrik | Değer | Durum |
|--------|------:|-------|
| **WNS** (setup) | **+9.109 ns** | ✅ ihlal yok |
| **WHS** (hold) | +0.210 ns | ✅ ihlal yok |
| **WPWS** (pulse width) | +4.500 ns | ✅ |
| Failing endpoints | 0 | ✅ |

Saat üretimi: `clk100 → ÷2 → BUFG → clk_soc (50MHz) → ÷2 → BUFG → pclk (25MHz)`.

---

## 4. Tasarımda ne nerede? (modül haritası)

```
basys3_top.v ........... üst sarmal: saat bölücü, reset sync, LED/7-seg mux, UART debug
└─ rv32_soc.v .......... adres decode, MMIO (UART/LED/SW/timer/button), VGA write port
   ├─ rv32_core.v ...... 5 aşamalı pipeline CPU
   │  ├─ pc.v / if_id / id_ex / ex_mem / mem_wb_reg.v ... PC + pipeline register'ları
   │  ├─ rv32_control.v . komut dekoderi (FENCE/SYSTEM→NOP)
   │  ├─ alu.v / regfile.v ... ALU (11 işlem) + 32×32 register dosyası
   │  ├─ forwarding_unit.v / hazard_detection_unit.v ... bypass + load-use stall
   │  ├─ imem.v ......... 8 KB komut belleği (LUTRAM)  ← snake_mayin.hex
   │  └─ dmem.v ......... 4 KB veri belleği (LUTRAM)
   ├─ hw_bootloader.v ... UART magic 0xDEADBEEF + uzunluk + payload → IMEM
   └─ uart_tx.v / uart_rx.v ... 115200 baud
vga_terminal.v ......... donanım terminali (cursor, scroll, clear, graphics mode)
└─ char_buffer.v ....... 80×30 karakter+renk (BRAM, 2× RAMB36)
vga_text_ctrl.v ........ font render + dahili VGA sync
├─ font_rom.v / font8x16.hex ... 8×16 font (distributed ROM)
└─ vga_sync.v .......... 640×480@60Hz timing
```

Kamera modülleri (`ov7670_*`, `cam_framebuffer`, `vga_cam_display`) `basys3_top` hiyerarşisinde **kullanılmıyor**, sentezde elenir.

---

## 5. Kart üzerinde kullanım

- **Menü:** BTNU/BTND seçim, BTNC onay. `1.SNAKE`, `2.MAYIN TARLASI`.
- **Snake ayar ekranı (oyun öncesi):** U/D ile hız (1–9), C ile başla.
- **Snake:** yön tuşları ile git; **BTNC = DURAKLAT** (devam/çıkış menüsü). Geri sayımda SW14 ile hız ayarı.
- **Mayın ayar ekranı (oyun öncesi):** U/D ile alan boyutu (9×9 / 12×12 / 16×16, mayın 10/20/40), C ile başla.
- **Mayın Tarlası:** yön tuşlarıyla gez, **BTNC = aç**; **SW[1] ON** iken BTNC bayrak (`P`) koyar/kaldırır; **SW[2] ON = menüye dön**. Üstte MAYIN / BAYRAK / KALAN sayaçları canlı güncellenir. Her oyunda mayınlar `CYCLE_REG` seed'i ile **rastgele** yerleşir.
- **SW[0] = reset.**
- **LED:** Snake'te skor, Mayın'da kalan temiz hücre sayısı.

## 6. Tekrar üretmek için

```bash
source ~/2025.2/Vivado/settings64.sh
# 1) firmware
export PATH=~/2025.2/gnu/riscv/lin/bin:$PATH
cd tests/c_toolchain && make && cd ../..
# (tests/snake_mayin.hex üretimi)
# 2) bitstream
vivado -mode batch -source build_basys3_top.tcl
# 3) karta yükleme (hw_server çalışır olmalı)
vivado -mode batch -source program_basys3.tcl
```
