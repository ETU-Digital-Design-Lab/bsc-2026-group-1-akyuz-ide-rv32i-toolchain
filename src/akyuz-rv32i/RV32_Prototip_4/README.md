# RV32_Prototip_4 — Kamera/VGA SoC (RISC-V RV32I)

Bu klasör, [akyuz-rv32i](../README.md) bitirme projesindeki üçüncü nesil donanım
prototipidir. Üst dizindeki tanıma göre: **"Prototip 3 üzerinde sadeleştirilmiş
kamera/VGA SoC"**. Somut olarak: `RV32_Prototip_2`'de geliştirilen 5 aşamalı
pipeline'lı RV32I çekirdeği ile `RV32_Snake_ve_Mayin_Tarlasi` (eski adıyla
Prototip 3) klasöründe eklenen Basys3 + VGA metin terminali + UART donanım
bootloader altyapısı burada yeniden kullanılıyor; oyun mantığı çıkarılıp
yerine bir **OV7670 kamera modülünden görüntü yakalayıp VGA ekrana aktaran**
basit bir kamera/VGA gösterim SoC'u eklenmiş durumda.

Ekranda iki şey aynı anda görünür:
- CPU'nun yazdığı 80x30 karakterlik metin ekranı (sistem durumu mesajları),
- Ekranın (400,50)-(560,170) bölgesinde sabit bir "resim içinde resim" (PIP)
  penceresinde, kameradan canlı gri tonlamalı 160x120 görüntü.

## Donanım gereksinimleri

- **Basys3** FPGA geliştirme kartı (Xilinx Artix-7, `xc7a35t`), 100 MHz sistem
  saati `clk100` pimi `W5` (bkz. `rtl/basys3_soc_cam.xdc`).
- **OV7670** kamera modülü (SCCB/I2C kayıt arayüzlü, paralel 8-bit veri
  çıkışlı). Basys3 üzerindeki PMOD kamera bağlantı noktasına takılır; XDC'de
  kamera sinyalleri için ayrılan pimler: `ov7670_pclk` (M19), `ov7670_xclk`
  (M18, FPGA'dan kameraya saat verilir), `ov7670_vsync` (P17), `ov7670_href`
  (N17), `ov7670_data[7:0]` (A16/A17/B15/C15/B16/C16/K17/L17), `ov7670_sioc`
  (R18), `ov7670_siod` (P18, `PULLUP TRUE`), `ov7670_reset` (A15),
  `ov7670_pwdn` (A14).
- **VGA monitör + VGA kablosu**, Basys3'ün standart 4-bit R/G/B + HSYNC/VSYNC
  VGA konektörüne bağlanır (XDC'de `vga_r[3:0]`, `vga_g[3:0]`, `vga_b[3:0]`,
  `vga_hsync`, `vga_vsync`).
- USB-UART (Basys3'ün üzerindeki USB-Seri köprüsü, `uart_txd_out`=A18,
  `uart_rxd_in`=B18) — C firmware'ini yüklemek ve LED/switch/UART TX ile
  etkileşim için kullanılır.

## Mimari

### 1) RV32I çekirdeği (`rv32_core.v`) ve SoC sarmalayıcısı (`rv32_soc.v`)

`rv32_core.v`, klasik 5 aşamalı bir pipeline'dır: **IF → ID → EX → MEM → WB**.
Kullanılan alt modüller: `pc.v`, `if_id_reg.v`, `rv32_control.v` (dekoder),
`regfile.v`, `id_ex_reg.v`, `forwarding_unit.v`, `hazard_detection_unit.v`,
`alu.v` (`rv32_alu`), `ex_mem_reg.v`, `mem_wb_reg.v`. Tehlike/veri yönlendirme
mantığı Prototip 2 ile aynı yaklaşımı izler:
- **Load-use tehlikesi** → `hazard_detection_unit` tarafından 1 çevrimlik
  durdurma (stall): PC ve IF/ID kaydı dondurulur, ID/EX'e bubble enjekte
  edilir.
- **Branch/JAL/JALR** → dal koşulu EX aşamasında ALU bayraklarıyla (zero, lt,
  ltu) değerlendirilir; alınan dal/atlamalarda IF/ID ve ID/EX 2 çevrimlik
  temizlenir (flush).
- **RAW veri tehlikeleri** (load-use dışında) → `forwarding_unit` ile
  EX/MEM veya MEM/WB sonuçları doğrudan EX aşamasına yönlendirilir (rs1, rs2
  ve store verisi için ayrı yönlendirme yolları).

`rv32_core` parametresi `EXT_DMEM=1` ile örneklenir (bkz. `rv32_soc.v`), yani
tüm veri belleği erişimleri çekirdek dışına, adres kod çözücüsüne çıkar.
`rv32_soc.v` bu veri veri-yolunu şu bellek haritasına adres-kod çözerek dağıtır:

| Adres aralığı | İçerik |
|---|---|
| `0x0000_0000 – 0x0000_0FFF` | Talimat belleği (IMEM), 4 KB (CPU fetch + `.rodata` okuma) |
| `0x0001_0000 – 0x0001_0FFF` | Veri belleği (DMEM), 1024 × 32-bit |
| `0x0002_0000` | UART TX veri kaydı (yazma → byte gönder) |
| `0x0002_0004` | UART TX durum kaydı (okuma → bit0 = `tx_ready`) |
| `0x0002_0008` | LED kaydı (16-bit, okunur/yazılır) |
| `0x0002_000C` | Switch kaydı (16-bit, salt okunur) |
| `0x0002_0010` | Çevrim sayacı (32-bit, salt okunur) |
| `0x0002_0014` | Buton kaydı (5-bit, salt okunur; `rv32_soc.v` içindeki okuma mux'unda `8'h14` adresi) |
| `0x0003_0000 – 0x0003_257F` | VGA karakter tamponu yazma portu ([7:0]=ASCII, [11:8]=ön plan, [15:12]=arka plan) |

Çekirdek 50 MHz'de çalışır (`clk_soc`), UART baud hızı 115200 (`UART_DIV=434`
= 50 MHz / 115200).

### 2) Kamera yakalama hattı

- `ov7670_sccb_init.v`: OV7670'in dahili kayıtlarını yazılım-bit-bang SCCB
  (I2C benzeri) protokolüyle programlar. 58 kayıtlık bir ROM (`cfg_rom`)
  kamerayı **QQVGA 160×120, RGB565** çıkışına göre yapılandırır (QVGA'dan
  DCW ile 2x ölçekleyerek). `clk100` (100 MHz) ile çalışır, `CLK_DIV=2000`
  ile ~50 kHz SCCB saati üretir; güç-açılış gecikmesi (~20 ms) ve kayıt
  başına ~2 ms (reset kaydı için ~200 ms) bekleme içerir. Bitince `done=1`.
- `ov7670_capture.v`: Kameranın kendi piksel saati `ov7670_pclk` alanında
  çalışır. Her pikselin RGB565 baytlarını (`href` yüksekken 2 bayt/piksel)
  toplar, **Y = (R + 2G + B) / 4** formülüyle 8-bit gri ton (luminans)
  hesaplar ve `fb_addr = y*160 + x` adresine `fb_we` ile yazar (160×120
  çözünürlük, taşma/çerçeve sınırları `x<160 && y<120` ile korunur).
- `cam_framebuffer.v`: 160×120×8-bit = 19.200 bayt (~10 adet BRAM18, Basys3'te
  toplam 50 BRAM18 mevcut) çift saatli (`wr_clk`=kamera pclk, `rd_clk`=VGA
  pclk) basit dual-port bellek; kamera alanından VGA alanına köprü görevi
  görür.
- `vga_cam_display.v`: `cam_framebuffer`'dan okunan 8-bit gri değeri, sqrt
  tabanlı bir gama düzeltmesiyle (karanlık bölgeleri parlaklaştırma) 4-bit
  VGA R=G=B değerine indirger ve yalnızca ekranın (400,50)-(560,170)
  penceresinde gösterir.

Kamera saat alanı (`ov7670_pclk`, XDC'de `create_clock -period 40.000`, yani
25 MHz) ile sistem saati (`sys_clk_pin`) arasında **asenkron saat grubu**
tanımlanmıştır (`set_clock_groups -asynchronous`), çünkü kamera saatinin fazı
FPGA'nın kendi ürettiği `pclk` ile hizalı değildir (CDC, `cam_framebuffer`
dual-clock BRAM'i üzerinden yönetilir).

### 3) VGA zamanlama ve metin katmanı

- `vga_sync.v`: Standart 640×480 @ 60 Hz VGA zamanlayıcı, 25 MHz piksel
  saati (`pclk`), negatif polariteli h/v-sync, `hcount`/`vcount` sayaçları.
- `char_buffer.v`: 80×30 hücrelik gerçek çift-portlu karakter+renk tamponu
  (Port A = CPU yazma @ `clk` 50 MHz, Port B = VGA okuma @ `pclk` 25 MHz).
  Her hücre 16 bit: `[7:0]` ASCII, `[11:8]` ön plan rengi, `[15:12]` arka
  plan rengi (4-bit CGA benzeri palet).
- `vga_terminal.v`: CPU tarafındaki durum makinesi; imleç ilerletme, `\r`/`\n`
  işleme, 30. satırdan taşınca **sanal kaydırma** (scroll_base ile fiziksel
  satır kaydırma, veri kopyalanmaz) ve ekran temizleme (`CTRL` kaydı bit0)
  içerir. CPU'nun kayıt arayüzü `cpu_reg` ile seçilir: `00`=DATA, `01`=CURSOR,
  `10`=CTRL (bit1 = donanım "grafik modu" / giriş ekranı).
- `vga_text_ctrl.v`: Piksel saat alanında, `char_buffer`'dan okunan hücreye
  göre `font_rom.v` (`font8x16.hex`, 128 karakter × 16 satır × 8 bit) bitmap
  fontundan piksel üretir; `graphics_mode=1` iken CPU'dan bağımsız donanım
  içi bir "plazma" desen üretici (XOR tabanlı renkli animasyon) devrededir.
- `basys3_soc_cam_top.v` içinde, kamera PIP penceresi ile metin katmanı
  aynı VGA çıkışında birleştirilir: `in_cam_window` bölgesindeyse kamera
  RGB'si, değilse metin/plazma katmanının RGB'si sürülür.

### 4) Üst modül ve saat ağacı (`basys3_soc_cam_top.v`)

`clk100` (100 MHz) bir `BUFG` üzerinden ikiye bölünerek `clk_soc` (50 MHz,
çekirdek ve VGA metin/UART mantığı) elde edilir; bu da tekrar ikiye
bölünerek `pclk` (25 MHz, VGA piksel saati ve kameraya verilen `ov7670_xclk`)
üretilir. `sw[0]` yazılım sıfırlama (senkronize edilmiş `rst_n_sync`) olarak
kullanılır; ayrıca kamera için 100 MHz alanında ~10 ms'lik bir "donanım sert
reset" sayaç mantığı (`cam_rst_cnt`) kamera reset pimini kontrol eder.
`sw[1]` dondurma/still-foto anahtarıdır (`freeze_frame`, kamera tamponuna
yazmayı durdurur). `led[15:0]` çıkışı hata ayıklama amaçlı çeşitli iç
sinyalleri (heartbeat biti, `boot_loading`, `sccb_ack_error`, kamera
sinyalleri, `wr_en`, `sccb_done`) gösterir.

> Not (kodda gözlemlenen tutarsızlık, uydurulmamıştır): `main.c` ekrana
> "Camera stream: Active on SW[15]" ve "Use SW[15] to toggle..." yazıyor,
> ancak `basys3_soc_cam_top.v` içinde `sw[15]` hiçbir yerde kullanılmıyor —
> kamera PIP penceresi her zaman sabit ekran koordinatlarında gösteriliyor.
> Yani bu metin şu anki donanım davranışını değil, muhtemelen planlanan/eski
> bir özelliği yansıtıyor.

## UART donanım bootloader (`hw_bootloader.v`, `uart_rx.v`, `uart_tx.v`)

`rv32_soc.v` içine gömülü `hw_bootloader`, `uart_rx` çıkışını dinler ve bir
durum makinesiyle şu protokolü uygular:

1. **Magic dizisi** `0xDE 0xAD 0xBE 0xEF` beklenir (yanlış bayt gelirse baştan
   başlanır, ancak `0xDE` görülürse dizinin yeniden başlangıcı olarak kabul
   edilip `S_WAIT_M1`'e geçilir).
2. Magic tamamlanınca **CPU anında durdurulur** (`cpu_reset_n <= 0`,
   `rv32_soc.v` içinde `core_rst_n = rst_n & cpu_reset_n` ile çekirdeğin
   reset'ine bağlanır).
3. **4 bayt uzunluk alanı** (little-endian, `payload_len`) okunur. Uzunluk
   0 ise CPU hemen serbest bırakılır.
4. **Payload** 4'er baytlık (32-bit, little-endian) kelimeler halinde IMEM'e
   `imem_we`/`imem_waddr`/`imem_wdata` portu (imem.v Port B) üzerinden adres
   0'dan başlayarak +4 artışlarla yazılır.
5. Tüm bayt sayısı (`byte_count`) `payload_len`'e ulaşınca `cpu_reset_n <= 1`
   yapılır ve CPU adres 0'dan yeni programı çalıştırmaya başlar.

`uart_rx.v` ve `uart_tx.v` basit 8N1 UART modülleridir (start/data/stop bit,
çift flip-flop senkronizörlü RX girişi); `rv32_soc.v` içinde her ikisi de
`UART_DIV=434` (50 MHz / 115200 baud) parametresiyle örneklenir.

## C araç zinciri (`tests/c_toolchain/`)

- **`main.c`**: LED, switch, buton, çevrim sayacı ve VGA karakter tamponu
  kayıtlarına doğrudan bellek-eşlemeli işaretçilerle erişen basit bir
  gösterim programı. Ekranı temizler, birkaç durum satırı yazar
  (`draw_text`/`vga_putc`/`vga_cursor` yardımcı fonksiyonlarıyla), sonra
  sonsuz döngüde switch değerlerini LED'lere yansıtır (`LED_REG = SWITCH_REG`).
- **`crt0.S`**: Program girişi (`_start`). Yığın işaretçisini (`sp`) linker
  betiğinde tanımlanan `__stack_top`'a ayarlar, ardından `main()`'e dallanır;
  `main` dönerse sonsuz döngüye (`end_loop`) girer.
- **`prototip4_linker.ld`**: Bellek düzenini tanımlar — `IMEM` 0x0000_0000
  başlangıçlı 8 KB (`.text`, `.rodata`), `DMEM` 0x0001_0000 başlangıçlı 4 KB
  (`.data`, `.bss`); yığın, DMEM'in en üstünde (`ORIGIN(DMEM)+LENGTH(DMEM)-4`)
  konumlandırılır.
- **`build.bat`** / **`Makefile`**: `riscv64-unknown-elf-gcc` ile
  `-march=rv32i -mabi=ilp32 -Os -ffreestanding -nostdlib -nostartfiles`
  bayraklarıyla `crt0.S` + `main.c` derlenip `firmware.elf` üretilir; ardından
  `objcopy -j .text -j .rodata -O binary` ile yalnızca kod+salt-okunur veri
  kesitleri `firmware.bin`'e (bootloader'a yüklenecek ham ikili) dönüştürülür.
  (`build.bat` içindeki `GCC_BIN` yolu belirli bir kullanıcıya özeldir; kendi
  ortamınızdaki araç zinciri yoluna göre düzenlenmelidir. `Makefile` ayrıca
  `firmware.hex` ve `firmware.lst` (disassembly) hedeflerini de üretir.)
- **`upload.py`**: `firmware.bin`'i seri port üzerinden 115200 baud ile
  gönderir: önce `0xDEADBEEF` magic, sonra dosya uzunluğu (4 bayt,
  little-endian), sonra 4 bayt hizası için sıfırla doldurulmuş (`pad`)
  firmware verisi. Bu, `hw_bootloader.v`'nin beklediği protokolle birebir
  eşleşir.

> Not: `firmware.bin` yalnızca `.text` ve `.rodata` kesitlerini içerir; `.data`
> kesitindeki (ilklendirilmiş global değişkenler) içerik bootloader ile
> yüklenmez — DMEM donanımda sıfırdan başlar (`dmem.v` her zaman boş/sıfır
> başlar), bu yüzden pratikte ilklendirilmiş global değişken kullanılmamalı
> ya da `.bss` gibi ele alınmalıdır.

## `tests/vga_test.hex` ne işe yarar?

`basys3_soc_cam_top.v` üst modülünün `IMEM_FILE` parametresinin **varsayılan
değeri** `"vga_test.hex"`'tir; bu dosya `imem.v` içindeki
`$readmemh(MEM_FILE, mem)` ile **sentez sırasında IMEM'e (talimat belleğine)
gömülen varsayılan/açılış firmware'idir** — yani Vivado ile bit akışı
(bitstream) üretilirken FPGA'ya otomatik olarak yüklenen, UART üzerinden
herhangi bir program yüklenmeden önce çalışan ilk programdır. Dosya, adres
etiketi (`@...`) içermeyen, satır başına bir 32-bit makine kodu kelimesi olan
düz `$readmemh` formatındadır (289 satır → ~1156 bayt/289 talimat), isminden
("vga_test") ve rv32_soc.v'nin VGA kayıtlarını hedef aldığından, muhtemelen
`main.c`'nin derlenmiş haliyle aynı ya da ona çok yakın bir VGA/metin ekranı
test programıdır.

## Dosya / klasör yapısı

| Yol | Açıklama |
|---|---|
| `rtl/pc.v` | Program sayacı |
| `rtl/if_id_reg.v` | IF/ID hattı kaydı |
| `rtl/id_ex_reg.v` | ID/EX hattı kaydı |
| `rtl/ex_mem_reg.v` | EX/MEM hattı kaydı |
| `rtl/mem_wb_reg.v` | MEM/WB hattı kaydı |
| `rtl/rv32_control.v` | Talimat dekoderi / kontrol birimi |
| `rtl/rv32_core.v` | 5 aşamalı RV32I çekirdeği (üst modül) |
| `rtl/alu.v` | ALU (`rv32_alu`) |
| `rtl/regfile.v` | Kayıt dosyası (x0-x31) |
| `rtl/forwarding_unit.v` | Veri yönlendirme birimi |
| `rtl/hazard_detection_unit.v` | Load-use tehlike tespiti |
| `rtl/imem.v` | Talimat belleği (CPU okuma + bootloader yazma) |
| `rtl/dmem.v` | Veri belleği (byte-adreslenebilir LUTRAM) |
| `rtl/rv32_soc.v` | SoC sarmalayıcı: çekirdek + adres kod çözücü + çevre birimleri |
| `rtl/basys3_soc_cam_top.v` | FPGA üst modülü: saat ağacı, SoC, kamera, VGA birleştirme |
| `rtl/basys3_soc_cam.xdc` | Basys3 pim/saat kısıtlama dosyası |
| `rtl/hw_bootloader.v` | UART üzerinden IMEM'e program yükleyen donanım bootloader |
| `rtl/uart_rx.v` | UART alıcı (8N1) |
| `rtl/uart_tx.v` | UART verici (8N1) |
| `rtl/ov7670_capture.v` | Kamera piksel yakalama + gri tonlama dönüşümü |
| `rtl/ov7670_sccb_init.v` | OV7670 SCCB (I2C benzeri) kayıt yapılandırma |
| `rtl/cam_framebuffer.v` | 160×120×8-bit kamera çerçeve tamponu (çift saat) |
| `rtl/vga_sync.v` | 640×480@60Hz VGA zamanlama üretici |
| `rtl/vga_cam_display.v` | Kamera görüntüsünü PIP penceresinde VGA'ya render eder |
| `rtl/vga_terminal.v` | CPU tarafı metin terminali durum makinesi (imleç/kaydırma) |
| `rtl/vga_text_ctrl.v` | Piksel tarafı metin/font render + donanım grafik modu |
| `rtl/char_buffer.v` | 80×30 karakter+renk tamponu (çift port BRAM) |
| `rtl/font_rom.v` | 8×16 bitmap font ROM |
| `rtl/font8x16.hex` | Font ROM ilk verisi |
| `tests/vga_test.hex` | Bitstream'e gömülü varsayılan/açılış firmware'i (IMEM_FILE) |
| `tests/c_toolchain/main.c` | Örnek C demo programı (VGA metin + LED/switch) |
| `tests/c_toolchain/crt0.S` | C çalışma zamanı başlangıcı (`_start`) |
| `tests/c_toolchain/prototip4_linker.ld` | Bellek haritası / bağlayıcı betiği |
| `tests/c_toolchain/build.bat` | Windows derleme betiği |
| `tests/c_toolchain/Makefile` | Make tabanlı derleme (elf/bin/hex/lst) |
| `tests/c_toolchain/upload.py` | Seri port üzerinden bootloader'a firmware yükleme betiği |

## Kurulum / çalıştırma adımları

### 1. FPGA bit akışını (bitstream) üretme

1. Vivado'da yeni bir proje açın (hedef parça: Basys3'ün Artix-7'si,
   `xc7a35tcpg236-1`).
2. `rtl/` altındaki tüm `.v` dosyalarını ve `font8x16.hex` dosyasını tasarım
   kaynağı (design source) olarak ekleyin; `tests/vga_test.hex` dosyasını da
   simülasyon/sentez sırasında `$readmemh` bulabilsin diye proje kök dizinine
   veya IP arama yoluna ekleyin (Vivado ayarlarında "Simulation/Synthesis
   sources" için hex arama yolu tanımlanmalı).
3. **Üst modül (top module)** olarak `basys3_soc_cam_top` seçin.
4. Kısıtlama dosyası olarak `rtl/basys3_soc_cam.xdc` dosyasını ekleyin (bu
   dosya Basys3'ün clk100, buton, switch, LED, UART, VGA ve OV7670 kamera
   pimlerinin tamamını tanımlar).
5. Sentez (Synthesis) → Uygulama (Implementation) → Bit akışı üret (Generate
   Bitstream) adımlarını çalıştırın.
6. Hardware Manager ile Basys3'e bağlanıp bit akışını karta (FPGA'ya) yükleyin
   (JTAG üzerinden, Digilent USB-JTAG).
7. Kamera modülünü PMOD portuna, VGA kablosunu monitöre takın; kart açıldığında
   `tests/vga_test.hex` içindeki varsayılan program otomatik çalışır ve
   ekranda metin + (kamera bağlıysa) canlı görüntü penceresi görünür.

### 2. Kendi C programınızı derleyip yükleme

1. `tests/c_toolchain/` klasörüne gidin.
2. `riscv64-unknown-elf-gcc` araç zincirinin kurulu olduğundan emin olun
   (Windows'ta `build.bat` içindeki `GCC_BIN` yolunu kendi kurulumunuza göre
   düzenleyin; Linux/Make kullanıyorsanız `Makefile`'daki `PREFIX`
   değişkenini kullanın).
3. Derleyin:
   - Windows: `build.bat` çalıştırın → `firmware.bin` üretilir.
   - Make: `make` çalıştırın → `firmware.elf`, `firmware.bin`, `firmware.hex`,
     `firmware.lst` üretilir.
4. Basys3'ün USB-UART portunun Windows'ta hangi COM portuna karşılık
   geldiğini belirleyin (Aygıt Yöneticisi).
5. `pyserial` kurulu olduğundan emin olun (`pip install pyserial`).
6. Yükleyin: `python upload.py COM<N> firmware.bin` (`<N>` kendi COM
   numaranız). Betik önce magic dizisini + uzunluğu + dolgu eklenmiş ikiliyi
   gönderir; `hw_bootloader.v` bunu alıp CPU'yu durdurur, IMEM'e yazar ve
   CPU'yu adres 0'dan yeniden başlatır.
7. Yeni program otomatik olarak çalışmaya başlar (kart resetlenmeden).

### İlgili anahtar/buton özet tablosu (donanımda gerçekten bağlı olanlar)

| Giriş | İşlev |
|---|---|
| `sw[0]` | Yazılım sıfırlama (senkronize `rst_n_sync`, ayrıca kamera reset zincirine de etki eder) |
| `sw[1]` | Dondurma / still-foto (kamera tamponuna yazmayı durdurur) |
| `sw[2..15]` | CPU tarafından `SWITCH_REG` (`0x0002_000C`) üzerinden okunabilir, donanımda özel bir işlevi yok |
| `btn_rst` | Kamera resetini de zorlayan donanım reset butonu (`cam_rst_n` hesaplamasında kullanılır) |
| `btn_u/l/r/d` | CPU'ya `BUTTON_REG` (`0x0002_0014`) olarak iletilir; üst modülde başka bir donanım işlevi yok |
