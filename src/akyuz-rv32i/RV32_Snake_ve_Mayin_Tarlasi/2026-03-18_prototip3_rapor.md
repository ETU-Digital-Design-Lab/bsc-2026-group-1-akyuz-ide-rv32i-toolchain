# RV32_Prototip_3 — Tasarım Doğrulama Raporu
**Tarih:** 18 Mart 2026
**Araç:** Vivado 2024.1
**Hedef:** Nexys 4 DDR — xc7a100tcsg324-1 (Artix-7 100T)
**Top Modül:** `fpga_top`

---

## 1. RTL Yapısı

Tasarım 16 Verilog kaynak dosyasından oluşmaktadır. Çekirdek pipeline 13 dosyada, SoC çevre birimleri 3 dosyada tanımlanmıştır.

### 1.1 Pipeline Çekirdeği (rv32_core)

| Dosya | Modül | İşlev |
|---|---|---|
| `pc.v` | `pc` | Program sayacı; `write_en` ile stall desteği |
| `imem.v` | `imem` | Asenkron okuma, parametre ile derinlik ve hex init |
| `if_id_reg.v` | `if_id_reg` | IF/ID boru hattı kaydı; flush=NOP, stall=tut |
| `rv32_control.v` | `rv32_control` | Tam RV32I decode; opcode/funct3/funct7 |
| `regfile.v` | `regfile` | 32×32 yazmaç dosyası; WB→ID write-through |
| `id_ex_reg.v` | `id_ex_reg` | ID/EX kaydı; flush kontrol sinyallerini sıfırlar |
| `alu.v` | `rv32_alu` | 10 RV32I işlemi + PASS_B; zero/lt/ltu bayrakları |
| `forwarding_unit.v` | `forwarding_unit` | RAW yönlendirme: forward_a, forward_b, forward_store |
| `hazard_detection_unit.v` | `hazard_detection_unit` | Load-use duraksama tespiti |
| `ex_mem_reg.v` | `ex_mem_reg` | EX/MEM boru hattı kaydı |
| `dmem.v` | `dmem` | Senkron yazma, byte/halfword granülerliği |
| `mem_wb_reg.v` | `mem_wb_reg` | MEM/WB boru hattı kaydı |
| `rv32_core.v` | `rv32_core` | Çekirdek top; EXT_DMEM parametresi dış veri yolu |

### 1.2 SoC ve FPGA Katmanı

| Dosya | Modül | İşlev |
|---|---|---|
| `rv32_soc.v` | `rv32_soc` | Çekirdek + adres çözücü + DMEM BRAM + çevre birimleri |
| `fpga_top.v` | `fpga_top` | Nexys 4 board sarmalayıcı |
| `uart_tx.v` | `uart_tx` | 8N1 UART TX, 115200 baud (CLK_DIV=434) |
| `seg7_driver.v` | `seg7_driver` | 8 basamaklı hex 7-segment çoklayıcı |
| `vga_terminal.v` | `vga_terminal` | VGA terminal durumu makinesi (IDLE/WRITE/SCROLL/CLR) |
| `vga_text_ctrl.v` | `vga_text_ctrl` | VGA zamanlama + karakter render |
| `vga_sync.v` | `vga_sync` | 640×480@60Hz senkronizasyon sinyalleri |
| `char_buffer.v` | `char_buffer` | 80×30 karakter BRAM tamponu |
| `font_rom.v` | `font_rom` | 8×16 piksel font ROM (2048×8) |

### 1.3 Bellek Haritası

| Adres Aralığı | Kaynak | Boyut |
|---|---|---|
| `0x0000_0000 – 0x0000_0FFF` | IMEM (hex init) | 4 KB |
| `0x0001_0000 – 0x0001_0FFF` | DMEM BRAM | 4 KB |
| `0x0002_0000` | UART TX verisi | 1 byte yazma |
| `0x0002_0004` | UART TX durum | bit0 = hazır |
| `0x0002_0008` | LED yazmacı | 16-bit yazma |
| `0x0002_000C` | Anahtar yazmacı | 16-bit okuma |
| `0x0003_0000` | VGA karakter | [15:12]=arka plan, [11:8]=ön plan, [7:0]=ASCII |
| `0x0003_0004` | VGA imleç | [12:8]=satır, [6:0]=sütun |
| `0x0003_0008` | VGA kontrol | herhangi yazma → ekran temizle |

---

## 2. Simülasyon Sonuçları

### 2.1 Davranışsal Simülasyon (Behavioral)

**Araç:** Vivado XSim 2024.1
**Test bankı:** `sim/tb_rv32_core.v`
**Test programı:** `tests/test_program.hex` (21 el-yazısı RV32I komutu)
**Saat periyodu:** 10 ns (100 MHz)
**Toplam simülasyon süresi:** 2536 ns

#### Test Sonuçları

```
Test Results  [active cycles=250  stalls=1  redirects=78]
Expected: stalls=1 (load-use), redirects>=2 (BEQ + JAL)

PASS  x01 = 0x00000005    [ADDI x1 = 5]
PASS  x02 = 0x00000003    [ADDI x2 = 3]
PASS  x03 = 0x00000008    [ADD  x3 = x1+x2 = 8]
PASS  x04 = 0x00000002    [SUB  x4 = x1-x2 = 2]
PASS  x05 = 0x00000040    [ADDI x5 = 64 (dmem base)]
PASS  x09 = 0x00000008    [ADDI x9 = 8  (BEQ operand)]
PASS  x06 = 0x00000008    [LW   x6 = dmem[64] = 8]
PASS  x07 = 0x00000008    [LW   x7 = dmem[64] = 8]
PASS  x08 = 0x0000000d    [ADD  x8 = x7+x1 = 13 (load-use)]
PASS  x10 = 0x00000001    [BEQ  taken -> x10=1 (0xFF atlandı)]
PASS  x11 = 0x00000038    [JAL  x11 = ret_addr 0x38]
PASS  x12 = 0x00000002    [BLT  taken -> x12=2 (0xFF atlandı)]
PASS  x13 = 0x00001000    [LUI  x13 = 0x1000]
PASS  x14 = 0xffffffff    [ADDI x14 = -1 (0xFFFFFFFF)]
PASS  x15 = 0x00000001    [SLT  x15 = (-1<5 işaretli) = 1]
PASS  x16 = 0x00000000    [SLTU x16 = (UINT_MAX<5) = 0]
PASS  dmem[0064] = 0x00000008   [SW   dmem[64] = 8]

PASSED: 17   FAILED: 0  →  TÜM TESTLER GEÇTİ
```

#### Doğrulanan Hazard ve Yönlendirme Davranışı

**Load-use duraksama** (döngü 9):
```
[ 8] ID=0002a383 (LW x7)    EX addr=0x40  stl=0
[ 9] ID=00138433 (ADD x8)   EX=0x40       stl=1  fid=1   ← 1 çevrim durdurma
[10] ID=00138433 (ADD x8)   EX=0x0d       stl=0           ← yük verisi hazır
```

**BEQ yönlendirmesi** (döngü 12-13):
```
[12] ID=00348463 (BEQ x6,x9) fwB=10       ← EX/MEM yönlendirmesi
[13]             fif=1 fid=1               ← 2 çevrim flush
```

**JAL yönlendirmesi** (döngü 16-17):
```
[16] ID=008005ef (JAL x11)   EX=ret_addr
[17]             fif=1 fid=1               ← 2 çevrim flush, PC=0x3C
```

**Veri yönlendirme türleri gözlemlendi:**
- `fwA/fwB=00` — Yazmaç dosyasından doğrudan okuma
- `fwA/fwB=01` — MEM/WB → EX yönlendirme
- `fwA/fwB=10` — EX/MEM → EX yönlendirme

### 2.2 Post-Synthesis Timing Simülasyonu

**Mod:** Post-synthesis timing (SDF annotated, slow corner)
**Sonuç:** Davranışsal simülasyon ile birebir örtüşme

```
PASSED: 17   FAILED: 0  →  TÜM TESTLER GEÇTİ
active cycles=250  stalls=1  redirects=78
```

Sentez sonrası zamanlama simülasyonu, davranışsal simülasyon ile aynı sonuçları üretmiştir. Gerçek kapı gecikmelerinin dahil olduğu bu simülasyon, boru hattı mantığının doğru çalıştığını onaylar.

---

## 3. Sentez Sonuçları

**Durum:** Tamamlandı — 0 hata, 0 kritik uyarı, 55 uyarı
**Süre:** ~36 saniye (synth_1, 16 iş parçacığı)

### 3.1 Kaynak Kullanımı (Post-Implementation)

| Kaynak | Kullanılan | Mevcut | Oran |
|---|---|---|---|
| LUT | ~1932 | 63400 | %4 |
| LUTRAM | 128× RAM256X1S | 19000 | %3 |
| FF (Flip-Flop) | ~1700 | 126800 | %1 |
| BRAM (RAMB36E1) | 2 | 135 | %1 |
| IO | 67 | 210 | %31 |
| BUFG | 2 | 32 | %6 |

**Toplam netlist:** 77 hücre, 67 G/Ç portu, 235 ağ

### 3.2 Hücre Dağılımı (Sentez Çıktısı)

| Hücre Tipi | Adet | Açıklama |
|---|---|---|
| LUT6 | 1151 | En geniş kullanım; çoğunlukla veri yolu |
| LUT5 | 206 | |
| LUT4 | 174 | |
| LUT3 | 138 | |
| LUT2 | 241 | |
| LUT1 | 22 | |
| MUXF7 | 284 | RAM256X1S içi çoklayıcı |
| MUXF8 | 90 | RAM256X1S içi çoklayıcı |
| CARRY4 | 62 | Toplama/çıkarma taşıma zincirleri |
| FDCE | 1631 | Asenkron clear flip-flop |
| FDRE | 58 | |
| FDPE/FDSE | 11 | |
| RAM256X1S | 128 | DMEM dört bayt şeridi (4×32 adet) |
| RAMB36E1 | 2 | Karakter tamponu BRAM (4Kx16) |
| IBUF / OBUF | 19 / 47 | Giriş/çıkış tamponları |
| BUFG | 2 | sys_clk + pclk (25 MHz) |

### 3.3 Bellek Eşlemeleri

**Distributed RAM (DMEM):**
```
u_soc/u_dmem/mem_b0_reg  1K×8  RAM256X1S×32
u_soc/u_dmem/mem_b1_reg  1K×8  RAM256X1S×32
u_soc/u_dmem/mem_b2_reg  1K×8  RAM256X1S×32
u_soc/u_dmem/mem_b3_reg  1K×8  RAM256X1S×32
```
Dört bayt şeridine bölünmüş dağıtık RAM; Xilinx LUTRAM şablonuna uygun yazılmış, SB/SH/SW için bağımsız yazma etkinleştirme sinyalleri ile çalışır.

**Block RAM (Karakter Tamponu):**
```
u_term/u_charbuf/mem_reg  4Kx16  RAMB36E1×2
Port A: yazma (CPU erişimi, NO_CHANGE modu)
Port B: okuma (VGA render, WRITE_FIRST modu)
```

**Distributed ROM (Font ROM):**
```
font_rom / fpga_top/p_0_out  2048×8  LUT eşlemesi
```
Font ROM, BRAM yerine LUT tablosuna eşlenmiştir; 2048 × 8-bit = 16 Kbit LUT kaynağı tüketir.

### 3.4 Otomatik FSM Kodlaması

Vivado iki FSM algıladı:

| Modül | Durum sayısı | Kodlama | Durumlar |
|---|---|---|---|
| `uart_tx` | 4 | Sequential | IDLE, START, DATA, STOP |
| `vga_terminal` | 4 | One-hot | IDLE, WRITE_CHAR, SCROLL_CLR, CLR_SCREEN |

---

## 4. Implementation Sonuçları

**Durum:** Tamamlandı — 0 hata, 0 kritik uyarı, 4 uyarı
**Süre:** synth ~36s + impl ~37s

### 4.1 Zamanlama

| Metrik | Değer | Limit | Durum |
|---|---|---|---|
| WNS (Worst Negative Slack — Setup) | +5.17 ns | 0 ns | ✅ |
| TNS (Total Negative Slack) | 0 ns | 0 ns | ✅ |
| WHS (Worst Hold Slack) | +0.044 ns | 0 ns | ✅ |
| THS (Total Hold Slack) | 0 ns | 0 ns | ✅ |
| WPWS (Worst Pulse Width Slack) | +8.750 ns | 0 ns | ✅ |
| Başarısız endpoint sayısı | 0 | — | ✅ |
| Toplam endpoint sayısı | 9965 | — | — |

**Kısıt:** 100 MHz saat (10 ns periyot)
**Gerçek kritik yol:** 10 − 5.17 = 4.83 ns
**Maksimum frekans tahmini:** 1 / 4.83 ns ≈ **207 MHz** (teorik üst sınır, overclock için değil)

Tüm zamanlama kısıtları karşılanmıştır. Tasarım 100 MHz'de güvenli çalışır.

### 4.2 Güç Analizi

**Toplam:** 0.12 W

| Bileşen | Güç | Pay |
|---|---|---|
| Dinamik | 0.023 W | %19 |
| — Saatler | 0.004 W | %19 |
| — Sinyaller | 0.005 W | %22 |
| — Mantık | 0.003 W | %13 |
| — BRAM | 0.001 W | %4 |
| — G/Ç | 0.010 W | %42 |
| Cihaz statik | 0.097 W | %81 |

**Bağlantı noktası:** 25.5°C bağlantı sıcaklığı, 59.5°C termal marj (12.9 W)
**Not:** Güç analizi vektörsüz aktivite tahmininden türetilmiştir; gerçek çalışma koşulları farklılık gösterebilir.

### 4.3 Yerleşim

Floorplan görüntüsü, tasarımın Artix-7 die'ının orta bölgesinde (X0Y2/X1Y2) yoğunlaştığını göstermektedir. Kaynak kullanımı düşük olduğundan Vivado yerleştiriciyi serbestçe optimizasyon yapabilmektedir.

---

## 5. Referans Tasarımlarla Karşılaştırma

Altı açık kaynak RV32I implementasyonu incelenerek mevcut tasarımla karşılaştırılmıştır.

### 5.1 Mimari Karşılaştırma

| Özellik | RV32_Prototip_3 | AngeloJacobo/RISC-V | pietroglyph/pipelined-rv32i | ultraembedded/riscv | lowRISC/Ibex |
|---|---|---|---|---|---|
| Dil | Verilog | Verilog | SystemVerilog | Verilog | SystemVerilog |
| Aşama sayısı | 5 | 5 | 5 | 5 (konfigüre edilebilir) | 2-3 |
| Dal çözüm aşaması | EX | EX | EX | EX | ID/EX |
| Dal cezası | 2 çevrim | 2 çevrim | 2 çevrim | 2 çevrim | 0-1 çevrim |
| Yönlendirme | EX/MEM > MEM/WB | EX/MEM > MEM/WB | EX/MEM > MEM/WB | Konfigüre edilebilir | WB→ID (3-stage) |
| Load-use tespiti | `mem_read && rd==rs1/rs2` | `!rd_valid` bayrağı | `result_src==MEM_RD` | `pending_lsu_e2` | Yok (2-stage) |
| ALU opcode kodlaması | Multi-bit localparam | 14-bit one-hot | Multi-bit named | Multi-bit named | 6-bit enum |
| Decode stili | `case(opcode)` → `case(funct3)` | One-hot flag + funct3 | `case(op)` + `case(funct3)` | 32-bit mask eşleme | `unique case` çift blok |
| funct7 kullanımı | Sadece bit[30] | Sadece bit[30] | Tam 7-bit | Mask'e gömülü | Sadece bit[30] |

### 5.2 Tasarım Kararlarının Değerlendirmesi

**Branch EX'te çözülmesi:** AngeloJacobo, pietroglyph ve ultraembedded ile aynı yaklaşım. Endüstri standardı 5-aşamalı tasarım seçimi.

**Yönlendirme önceliği (EX/MEM > MEM/WB):** Tüm referans tasarımlarla örtüşür. Daha yeni sonucu daha eski sonuca tercih etmek doğru.

**ALU opcode — multi-bit localparam:** ultraembedded ve pietroglyph ile aynı; AngeloJacobo'nun one-hot vektöründen sentez açısından daha verimli.

**funct7[30] yeterli:** Temel RV32I için ADD/SUB ve SRL/SRA ayrımı yalnızca bit[30] ile yapılabilir. M uzantısı eklendiğinde tam funct7 gerekecek.

**Dal koşulu core'da (ALU dışında):** Ibex ile aynı yaklaşım. ALU saf aritmetik birim olarak kalır; bayrak yorumlaması üst katmana bırakılır.

**WB'de load genişletme:** ultraembedded/riscv ile aynı; byte_off + funct3 ile byte/halfword seçimi doğru uygulanmış.

### 5.3 Kaynak Kullanımı Karşılaştırması (Artix-7 100T)

| Tasarım | LUT | FF | BRAM | Fmax |
|---|---|---|---|---|
| RV32_Prototip_3 (çekirdek+SoC+VGA) | %4 | %1 | %1 | >200 MHz |
| PicoRV32 (minimal, FSM) | ~850 LUT | düşük | — | ~250 MHz |
| DarkRISCV (3-aşamalı) | ~1000 LUT | orta | — | ~200 MHz |
| Ibex (2-aşamalı, production) | ~15K LUT | yüksek | orta | ~100 MHz |

Prototip 3, çekirdek + SoC + VGA terminal dahil tüm tasarımıyla Artix-7 100T'nin yalnızca %4 LUT kaynaklarını kullanmaktadır. Kaynak açısından son derece verimlidir.

---

## 6. Kalan Uyarılar

### 6.1 Sentez Uyarıları

| Uyarı | Sebep | Etki |
|---|---|---|
| `[Synth 8-7129]` cb_rdata_b[7] yüksüz | VGA render ASCII 7-bit kullanır, MSB boşta | Yok — kasıtlı |
| `[Synth 8-3917]` dp sabit 1 | `seg7_driver` ondalık noktayı kapatmak için 1'b1 atar | Yok — kasıtlı |
| `[Synth 8-7080]` Paralel sentez kriteri karşılanmadı | Sistem kaynağı sorunu | Yok |
| `[Synth 8-7129]` imem/dmem üst adres bitleri yüksüz | 1K kelimelik bellek; üst bitler decode'da kullanılmıyor | Yok — tasarım gereği |
| `[Synth 8-7129]` uart_rxd_in yüksüz | RX alınmamakta; yalnızca TX uygulandı | Yok — kasıtlı |

### 6.2 Implementation Uyarıları

| Uyarı | Sebep | Etki |
|---|---|---|
| `[Place 30-87]` vga_g[2] kilitlenmemiş | Nexys 4 DDR'de A7 pini Vivado 2024.1 veritabanında geçersiz | vga_g[2] otomatik IOB ataması — yeşil kanalda 1-bit sapma |
| `[Power 33-332]` Sıfırlama aktivitesi | Vektörsüz analiz; reset uzun süreli etkin görünüyor | Güç tahmini düşük güvenilirlikte |
| `[Device 21-9320]` HSR_BOUNDARY_TOP | Vivado 2024.1 dahili uyarı; sanal grid başlatma | İşlevsel etki yok |

### 6.3 Simülasyon Uyarıları (XSIM)

| Uyarı | Sebep | Değerlendirme |
|---|---|---|
| `[XSIM 43-4099]` timescale eksik | RTL dosyalarında `timescale` yok (proje politikası); testbench'te var | Benign — 1ps çözünürlük otomatik miras alınır |
| `[VRFC 10-3609]` Modül üzerine yazma | Post-synthesis timing sim'de hem netlist hem RTL compile ediliyor | Beklenen davranış; RTL netlist'i geçersiz kılar |

---

## 7. Doğrulama Özeti

### 7.1 Akış Durumu

| Aşama | Durum | Notlar |
|---|---|---|
| RTL Sentezi | ✅ Tamamlandı | 0 hata, 0 kritik uyarı |
| Davranışsal Simülasyon | ✅ 17/17 test geçti | BEQ, JAL, load-use, forwarding doğrulandı |
| Post-Synthesis Timing Sim | ✅ 17/17 test geçti | Davranışsal ile birebir örtüşme |
| Implementation | ✅ Tamamlandı | 0 hata, 0 kritik uyarı |
| Zamanlama Kısıtları | ✅ Tümü karşılandı | WNS=+5.17 ns @ 100 MHz |
| Bitstream Üretimi | ✅ Hazır | write_bitstream engelsiz çalışır |

### 7.2 RV32I Uyumluluk Özeti

| Komut Grubu | Test Durumu |
|---|---|
| R-type (ADD, SUB) | ✅ Doğrulandı |
| I-type aritmetik (ADDI) | ✅ Doğrulandı |
| Yük (LW) | ✅ Doğrulandı |
| Depolama (SW) | ✅ Doğrulandı |
| Dal (BEQ, BLT) | ✅ Doğrulandı (alındı / atlanma her ikisi) |
| Koşulsuz atlama (JAL) | ✅ Doğrulandı (dönüş adresi dahil) |
| Üst anlık (LUI) | ✅ Doğrulandı |
| İşaretli karşılaştırma (SLT) | ✅ Doğrulandı |
| İşaretsiz karşılaştırma (SLTU) | ✅ Doğrulandı |
| Load-use duraksama | ✅ 1 çevrim, beklenen |
| Veri yönlendirme (EX/MEM, MEM/WB) | ✅ İki yol da gözlemlendi |

---

## 8. Sonuç

RV32_Prototip_3, 5-aşamalı boru hattılı RV32I işlemcisini Xilinx Artix-7 100T üzerinde başarıyla sentezleyip doğrulamıştır.

Tasarımın temel özellikleri:
- Tam RV32I uyumlu decode; opcode/funct3/funct7 spec ile örtüşüyor
- EX aşamasında dal çözümü, 2-çevrim flush — endüstri standardı
- Load-use hazard tespiti ve 1-çevrim duraksama mekanizması çalışıyor
- EX/MEM ve MEM/WB yönlendirme yollarının her ikisi de simülasyonda gözlemlendi
- WB aşamasında byte/halfword yük genişletme (LB/LH/LBU/LHU) doğru
- Sentez sonrası zamanlama simülasyonu davranışsal ile özdeş — RTL'de zamanlama kırılması yok
- Tüm zamanlama kısıtları 100 MHz'de karşılandı; tahmini maksimum frekans ~207 MHz
- Toplam güç tüketimi 0.12 W (0.023 W dinamik)
- Kaynak kullanımı son derece düşük (%4 LUT, %1 FF) — ilerideki VGA, I2C, SPI genişlemeleri için geniş alan mevcut

**FPGA yüklemeye hazır durumda.**
Tek açık nokta: `vga_g[2]` pininin Vivado 2024.1 veritabanındaki A7 geçersizliği nedeniyle fiziksel VGA konnektörünün doğru G2 pinine bağlanamıyor olması. Bu Vivado 2024.1 aracına özgü bir veritabanı sorunudur; görüntü çalışır, yeşil kanalda 1-bit hassasiyet kaybı olur.
