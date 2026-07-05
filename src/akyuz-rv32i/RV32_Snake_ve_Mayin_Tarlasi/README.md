# RV32 Snake & Mayın Tarlası (eski adı: RV32_Prototip_3)

5 aşamalı boru hattılı (pipelined), RV32I uyumlu bir RISC-V işlemci çekirdeği üzerine kurulmuş; VGA donanım terminali, Snake ve Mayın Tarlası oyunları, UART üzerinden yazılım yükleyen bir donanımsal bootloader ve tam bir C toolchain akışı içeren FPGA prototipi.

Bu klasör, [`akyuz-rv32i`](../README.md) bitirme projesindeki üç prototipten biridir (bkz. üst dizin README'si). Klasör başlangıçta **RV32_Prototip_3** adıyla, RV32I çekirdeğinin temel doğrulamasını yapan genel bir prototip olarak yola çıkmış; zamanla üzerine VGA terminal, oyun mantığı ve donanımsal bootloader eklenince projenin asıl kimliği "Snake & Mayın Tarlası" oyun konsoluna dönüşmüş ve klasör bu işlevi yansıtacak şekilde yeniden adlandırılmıştır. Eski isim, klasördeki en eski raporlarda (Mart 2026, Nexys 4 DDR kartı) hâlâ görülür; proje daha sonra hedef kartı **Basys 3**'e taşımıştır (bkz. aşağıdaki "Gelişim Süreci" ve raporlar).

## 1. Gelişim Süreci (özet kronoloji)

| Tarih | Aşama | Hedef Kart | Kaynak Rapor |
|---|---|---|---|
| 4 Mart 2026 | Çekirdek + SoC + VGA terminal ilk sentez/doğrulama; 50 MHz'e düşürülerek zamanlama sağlandı | Nexys 4 DDR (`xc7a100t`) | `docs/2026_03_04_Prototip3_FPGA_Rapor.md`, `docs/2026_03_04_FPGA_Rapor_v2.md`, `docs/2026-03-04_gelistirme_ve_referans_raporu.md` |
| 18 Mart 2026 | Kapsamlı doğrulama raporu: sentez, timing, güç, referans tasarımlarla karşılaştırma | Nexys 4 DDR | `2026-03-18_prototip3_rapor.md` |
| 24 Mart 2026 | Snake oyunu ile SoC/bellek haritası/çevre birimi dokümantasyonu | Nexys 4 DDR | `24-03-2026_Teknik_Rapor.md` |
| 9 Haziran 2026 | Basys 3'e geçiş, Snake + Mayın Tarlası + menü firmware'i, IMEM 16 KB'a çıkarıldı, IMEM BRAM'e taşındı (LUT %46.7 → %13.4) | **Basys 3 (`xc7a35t`)** | `DONANIM_VE_DERLEME_NOTLARI.md` |
| 10 Haziran 2026 | Vivado 2025.2 ile güncel bitstream üretimi (`clockInfo.txt` bu derlemeden kalan Vivado saat-yönlendirme hata ayıklama dosyasıdır) | Basys 3 | `clockInfo.txt` |

Klasörün **şu anki fiili durumu Basys 3 kartına göredir**: `rtl/basys3.xdc`, `rtl/basys3_soc_cam.xdc`, `build_basys3_top.tcl`, `program_basys3.tcl` hep Basys 3 (`xc7a35tcpg236-1`) hedefler; eski `nexys4.xdc` dosyası artık depoda yok. Nexys 4 raporları tarihsel doğrulama kaydı olarak saklanmaktadır.

## 2. Donanım Gereksinimleri

- **FPGA kartı:** Digilent **Basys 3** (Xilinx Artix-7, `xc7a35tcpg236-1`)
- **VGA çıkışı:** Basys 3'ün VGA konnektörü (4-bit/kanal direnç DAC) → standart bir VGA monitör ve VGA kablosu
- **UART:** Basys 3 üzerindeki USB-UART (CP2102) köprüsü, USB kablosu ile bilgisayara bağlı; PC tarafında bir COM port
- **Araçlar:** Xilinx Vivado (sentez/rapor dosyaları Vivado 2025.2 ile üretilmiş; erken raporlar 2024.1 ile), RISC-V GNU toolchain (`riscv64-unknown-elf-gcc`, rv32i/ilp32 hedefi), Python 3 + `pyserial` (bootloader yükleyici için)
- **Opsiyonel:** OV7670 kamera modülü — yalnızca `basys3_soc_cam_top.v` / `basys3_soc_cam.xdc` birleşik üst modülü kullanılırsa gereklidir (bkz. §4)

## 3. Özellikler

- **RV32I 5-aşamalı pipeline çekirdeği** (IF→ID→EX→MEM→WB), EX aşamasında dal çözümü (2 çevrim flush), forwarding birimi (EX/MEM ve MEM/WB önceliği) ve load-use hazard için 1 çevrim stall.
- **VGA donanım terminali** — 80×30 karakter, 16 renk (4-bit ön/arka plan), donanımsal imleç, CR/LF işleme, sanal kaydırma (scroll) ve tam ekran temizleme; CPU üç adet 32-bit MMIO yazmacı (DATA/CURSOR/CTRL) üzerinden sürer, adres hesaplaması ve piksel/font render tamamen donanımda yapılır.
- **Snake oyunu** ve **Mayın Tarlası (Minesweeper)** — ikisi de C ile yazılmış, VGA terminal üzerinde ayar ekranlı bir menüden başlatılır (bkz. `tests/c_toolchain/main.c`).
- **UART donanımsal bootloader** (`hw_bootloader.v`) — `0xDEADBEEF` sihirli dizisi + 4 baytlık uzunluk + payload alarak CPU'yu durdurup yeni programı doğrudan IMEM'e yazar; **bitstream'i yeniden yüklemeden** yalnızca yazılımı güncellemeyi sağlar.
- **C toolchain** — `riscv64-unknown-elf-gcc` ile derlenen freestanding (`-ffreestanding -nostdlib -nostartfiles`) firmware; `crt0.S` başlangıç kodu `.data`'yı IMEM'den DMEM'e kopyalar ve `.bss`'i sıfırlar; donanımsal çarpma/bölme birimi olmadığından yalnızca `__divsi3/__modsi3/__umodsi3` `libgcc`'den alınır.
- **(Bonus/ek) OV7670 kamera geçişi** — `basys3_soc_cam_top.v` adlı ayrı bir birleşik üst modül, RV32 SoC'yi bir OV7670 kamera yakalama/framebuffer/VGA gösterim hattıyla birleştirir; oyun mantığıyla doğrudan ilgili değildir ve `sw[15]` veya yazılımdaki `CAM_REG` (0x0002_0018) ile VGA çıkışına anahtarlanır. Bu, `build_basys3_top.tcl`'nin şu an gerçekte derlediği top modüldür (bkz. §5).

## 4. Mimari Genel Bakış

```
basys3_top.v  (sade SoC, kamerasız)         basys3_soc_cam_top.v  (SoC + OV7670 kamera, build_basys3_top.tcl'nin hedefi)
└─ rv32_soc.v ................ adres kod çözücü, MMIO, VGA yazma portu
   ├─ rv32_core.v ............ 5 aşamalı pipeline
   │  ├─ pc.v / if_id_reg.v / id_ex_reg.v / ex_mem_reg.v / mem_wb_reg.v .. pipeline register'ları
   │  ├─ rv32_control.v ...... komut çözücü (opcode/funct3/funct7)
   │  ├─ alu.v (rv32_alu) .... 10-11 işlem + PASS_B (LUI/AUIPC)
   │  ├─ regfile.v ........... 32×32 yazmaç dosyası (write-through WB→ID)
   │  ├─ forwarding_unit.v ... RAW yönlendirme (EX/MEM > MEM/WB)
   │  ├─ hazard_detection_unit.v .. load-use durdurma
   │  ├─ imem.v ............... komut belleği (16 KB, BRAM)
   │  └─ dmem.v ............... veri belleği (4 KB, LUTRAM, byte-enable)
   ├─ hw_bootloader.v ......... UART 0xDEADBEEF + uzunluk + payload → IMEM
   └─ uart_tx.v / uart_rx.v ... 115200 baud 8N1
vga_terminal.v .................. donanım terminal FSM (imleç, CR/LF, scroll, clear, graphics mode)
└─ char_buffer.v ............. 80×30 karakter+renk BRAM (true dual-port)
vga_text_ctrl.v .................. piksel üretimi: font_rom + char_buffer okuma + (opsiyonel) plazma efekti
├─ font_rom.v / font8x16.hex .. 8×16 bit font (distributed ROM/LUT)
└─ vga_sync.v ................. 640×480@60Hz zamanlama (hsync/vsync/active)

Yalnızca basys3_soc_cam_top.v içinde: ov7670_sccb_init.v, ov7670_capture.v,
cam_framebuffer.v, vga_cam_display.v (OV7670 kamera yakalama + görüntüleme hattı)
```

### Bellek Haritası (`rtl/rv32_soc.v`)

| Adres Aralığı | Kaynak | Erişim | Açıklama |
|---|---|---|---|
| `0x0000_0000` – `0x0000_3FFF` | IMEM (16 KB, BRAM) | R (fetch) + R (CPU load, `.rodata`) + W (bootloader) | Komut belleği; `.text`/`.rodata`/`.data` ilk-değer görüntüsü burada tutulur |
| `0x0001_0000` – `0x0001_0FFF` | DMEM (4 KB, LUTRAM) | R/W | Veri belleği; yığın (stack) tepe noktası `0x10FFC` |
| `0x0002_0000` | UART TX veri | W | Yazılan LSB byte UART üzerinden gönderilir |
| `0x0002_0004` | UART TX durum | R | bit0 = `tx_ready` |
| `0x0002_0008` | LED yazmacı | R/W | 16-bit |
| `0x0002_000C` | Switch yazmacı | R | 16-bit |
| `0x0002_0010` | Çevrim (cycle) sayacı | R | 32-bit, reset'ten beri geçen çevrim; zamanlama + rastgele sayı üretimi (seed) için kullanılır |
| `0x0002_0014` | Buton yazmacı | R | 5-bit (`BTN_L/R/D/U/C`) |
| `0x0002_0018` | Kamera etkin (`CAM_REG`) | R/W | Yalnızca `basys3_soc_cam_top` içinde anlamlı; bit0 = yazılımdan kamera görüntüsünü aç |
| `0x0003_0000` | VGA DATA | W | `[15:12]`=arka plan, `[11:8]`=ön plan, `[7:0]`=ASCII; yazınca imleç otomatik ilerler |
| `0x0003_0004` | VGA CURSOR | W | `[12:8]`=satır (0-29), `[6:0]`=sütun (0-79) |
| `0x0003_0008` | VGA CTRL | W | bit0 = ekranı temizle, bit1 = grafik/plazma modu |

Not: `clockInfo.txt`, Vivado 2025.2'nin `xc7a35t-cpg236-1` hedefi için üretmiş olduğu saat yönlendirme hata ayıklama (clock routing debug) dosyasıdır; kendisi ayrıntılı zamanlama verisi içermez, yalnızca derlemenin hangi araç/sürüm/parça ile yapıldığını doğrular. Ayrıntılı WNS/WHS/güç rakamları için §7'deki raporlara bakın.

## 5. Derleme ve FPGA'ya Yükleme

### 5.1 C Firmware'i Derleme

```bash
cd tests/c_toolchain
export PATH=~/2025.2/gnu/riscv/lin/bin:$PATH   # riscv64-unknown-elf-gcc PATH'e eklenir
make                                            # firmware.elf / .bin / .hex / .lst üretir
```

(Windows'ta alternatif olarak `build.bat` kullanılabilir; içindeki `GCC_BIN` yolunu kendi toolchain kurulumunuza göre düzenlemeniz gerekir.) Üretilen `.hex` çıktısı, IMEM'i doğrudan başlatmak için `tests/snake_mayin.hex` olarak Vivado sentezine parametre geçilir.

### 5.2 Vivado ile Bitstream Üretimi

`build_basys3_top.tcl`, tüm `rtl/*.v` dosyalarını okur, **`basys3_soc_cam_top`** modülünü top olarak sentezler (kamera dahil birleşik üst modül) ve `rtl/basys3_soc_cam.xdc` kısıt dosyasını kullanır; IMEM içeriği `tests/snake_mayin.hex`, font ROM içeriği `rtl/font8x16.hex` generic parametreleriyle geçilir:

```bash
vivado -mode batch -source build_basys3_top.tcl
# çıktı: vivado_build/snake_mayin.bit, vivado_build/timing.rpt, vivado_build/util.rpt
```

Yalnızca kamerasız, sade SoC'yi (`basys3_top.v` + `rtl/basys3.xdc`) hedeflemek isterseniz, aynı akışı bu modül/xdc çiftiyle elle çalıştırmanız gerekir (depodaki hazır `.tcl` betiği şu an `basys3_soc_cam_top`'u hedefliyor).

### 5.3 Bitstream'i Karta Yükleme

```bash
vivado -mode batch -source program_basys3.tcl
```

Bu betik `hw_server`'a (`localhost:3121`) bağlanır, ilk bulunan donanım cihazını seçer ve `vivado_build/snake_mayin.bit` dosyasını JTAG üzerinden programlar.

### 5.4 UART Bootloader ile Yazılım Güncelleme (bitstream'e dokunmadan)

Bitstream karta bir kez yüklendikten sonra, yeni bir C firmware'i tekrar bitstream üretmeden doğrudan IMEM'e yazmak için:

```bash
cd tests/c_toolchain
python upload.py COM12 firmware.bin   # COM12 yerine kartın gerçek portu
```

`upload.py`, sırasıyla `0xDE 0xAD 0xBE 0xEF` sihirli dizisini, 4 baytlık küçük-endian uzunluk alanını ve 4 bayta hizalanmış firmware payload'unu 115200 baud ile gönderir; `hw_bootloader.v` bu diziyi görünce CPU'yu durdurur, payload'u IMEM'e word word yazar ve bitirince CPU'yu adres 0'dan yeniden başlatır.

## 6. Kart Üzerinde Kullanım

- **Menü:** `BTNU`/`BTND` ile seçim, `BTNC` ile onay — `1.SNAKE`, `2.MAYIN TARLASI`.
- **Snake ayar ekranı:** `U`/`D` ile hız (1-9), `C` ile başlat; oyun içinde yön tuşları, `BTNC` = duraklat.
- **Mayın Tarlası ayar ekranı:** `U`/`D` ile alan boyutu (9×9/12×12/16×16 → 10/20/40 mayın), `C` ile başlat; yön tuşlarıyla gezinme, `BTNC` = aç, `SW[1] ON` iken `BTNC` bayrak koyar/kaldırır, `SW[2] ON` = menüye dön.
- **`SW[0]`** = reset. **LED**: Snake'te skor, Mayın Tarlası'nda kalan temiz hücre sayısı.
- Mayın yerleşimi her oyunda `CYCLE_REG` (çevrim sayacı) seed'i ile rastgele belirlenir.

## 7. Dosya / Klasör Yapısı

| Yol | İçerik |
|---|---|
| `rtl/` | Tüm Verilog kaynakları + XDC kısıt dosyaları (çekirdek, SoC, VGA, UART, bootloader, opsiyonel kamera) |
| `rtl/fonts/` | Font ROM kaynak verisi (`font8x16.hex`) ve üretim betiği (`generate_font.py`) |
| `sim/tb_rv32_core.v` | Çekirdek için davranışsal test bankı (behavioral testbench) |
| `tests/c_toolchain/` | Snake/Mayın Tarlası/menü C kaynağı (`main.c`), başlangıç kodu (`crt0.S`), linker script, `Makefile`/`build.bat`, UART yükleyici (`upload.py`) ve derlenmiş firmware çıktıları |
| `tests/*.hex` | IMEM başlatma dosyaları (çeşitli test programları + üretim `snake_mayin.hex`) |
| `tests/*.s`, `tests/gen_uart_dump.py`, `tests/send_firmware.py` | Yardımcı assembly test programı ve UART ile ilgili betikler |
| `build_basys3_top.tcl` | Vivado batch sentez/impl/bitstream akışı (top: `basys3_soc_cam_top`) |
| `program_basys3.tcl` | Vivado hardware manager ile bitstream'i karta yükleme betiği |
| `clockInfo.txt` | Vivado 2025.2 tarafından üretilen saat yönlendirme hata ayıklama dosyası (Basys 3, `xc7a35t`) |
| `performance_test_fixed.hex` | Kök dizindeki ek bir performans test görüntüsü |
| `2026-03-18_prototip3_rapor.md` | Detaylı rapor (bkz. §8) |
| `24-03-2026_Teknik_Rapor.md` | Detaylı rapor (bkz. §8) |
| `DONANIM_VE_DERLEME_NOTLARI.md` | Detaylı rapor (bkz. §8) |
| `docs/*.md` | Detaylı raporlar (bkz. §8) |

## 8. Bilinen Kısıtlamalar / Açık Noktalar

Aşağıdakiler ilgili raporlarda belgelenmiştir; güncel Basys 3 derlemesinde teyit edilmemiş, tarihsel (Nexys 4 DDR dönemi) bulgular da ayrıca belirtilmiştir:

- **CSR / trap desteği yok**, **FENCE.I NOP olarak işleniyor** (sıralı pipeline'da güvenli) — `docs/2026-03-04_gelistirme_ve_referans_raporu.md`.
- **Donanımsal çarpma/bölme birimi yok**; C kodunda `libgcc`'nin yazılımsal `__divsi3/__modsi3/__umodsi3` rutinleri kullanılıyor — `DONANIM_VE_DERLEME_NOTLARI.md`.
- Nexys 4 DDR döneminde `vga_g[2]` pini için Vivado 2024.1 veritabanı uyarısı (UCIO-1) alınmıştı; bu, o zamanki karta özgü bir bulguydu ve mevcut Basys 3 XDC dosyalarında (`rtl/basys3.xdc`, `rtl/basys3_soc_cam.xdc`) ayrı pin ataması kullanılıyor — güncel durumda bu uyarının geçerli olup olmadığı bu README'nin kapsamı dışında, en güncel Vivado impl raporuna bakılmalı.
- `build_basys3_top.tcl` şu an **kamera dahil birleşik top'u** (`basys3_soc_cam_top`) derliyor; sade SoC'yi (`basys3_top.v`) hedeflemek isteyen biri betiği elle uyarlamalıdır (bkz. §5.2).

## 9. Daha Fazla Bilgi / Detaylı Raporlar

Bu README, klasördeki dağınık raporların yerine geçen bir özet/giriş belgesidir. Süreç detayları, tasarım gerekçeleri, tam sentez/timing/güç rakamları ve referans tasarım karşılaştırmaları için:

- **`docs/2026-03-04_gelistirme_ve_referans_raporu.md`** — Referans alınan açık kaynak tasarımlar (CV32E40P, ultraembedded/riscv, pietroglyph vb.), mimari kararların gerekçeleri (dal çözümleme aşaması, write-through regfile, DMEM LUTRAM bankları, pclk üretimi, sanal scroll, senkron reset vb.), kronolojik geliştirme süreci (adım adım), dosya envanteri ve Phase 3 sentez sonuçları.
- **`docs/2026_03_04_FPGA_Rapor_v2.md`** ve **`docs/2026_03_04_Prototip3_FPGA_Rapor.md`** — Nexys 4 DDR üzerinde ilk sentez/timing deneyimi: 100 MHz'de başarısız zamanlama → 50 MHz'e düşürme, kaynak kullanımı ve güç analizi, simülasyon test sonuçları (bu iki dosya birbirine çok benzer içerik/taslak niteliğindedir).
- **`2026-03-18_prototip3_rapor.md`** — En kapsamlı tek tasarım doğrulama raporu: RTL modül/bellek haritası tabloları, davranışsal + post-synthesis timing simülasyon sonuçları (17/17 test), sentez/implementation kaynak ve zamanlama rakamları, altı açık kaynak RV32I tasarımıyla mimari karşılaştırma, kalan uyarılar listesi.
- **`24-03-2026_Teknik_Rapor.md`** — Snake oyunu bağlamında SoC mimarisi, bellek haritası, çevre birimleri (VGA terminal, UART, GPIO, cycle counter), bootloader mekanizması ve C geliştirme süreci özeti.
- **`DONANIM_VE_DERLEME_NOTLARI.md`** — **En güncel ve Basys 3'e özgü** rapor: firmware bölüm boyutları (`.text`/`.rodata`/`.data`/`.bss`), IMEM/DMEM/char_buffer/font_rom donanım eşlemeleri, post-route sentez/timing sonuçları (LUT %13.4, BRAM %20, WNS +9.109 ns @ 50 MHz), RTL modül haritası, kart üzerinde kullanım talimatları ve yeniden üretim (rebuild) adımları.

Herhangi bir raporda bu README ile çelişen bir ayrıntı görürseniz, **tarihi en yeni olan ve Basys 3'e atıfta bulunan** `DONANIM_VE_DERLEME_NOTLARI.md`'yi esas alın; Nexys 4 DDR dönemine ait raporlar tarihsel referans niteliğindedir.
