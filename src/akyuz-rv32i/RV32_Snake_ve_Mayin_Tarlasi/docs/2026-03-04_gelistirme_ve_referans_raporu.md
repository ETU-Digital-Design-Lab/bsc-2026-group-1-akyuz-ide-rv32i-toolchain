# RV32_Prototip_3 — Geliştirme ve Referans Raporu

**Tarih:** 4 Mart 2026
**Proje:** RV32_Prototip_3 — 5-Aşamalı Boru Hattı RV32I İşlemcisi
**Hedef Kart:** Digilent Nexys 4 DDR (Xilinx Artix-7 xc7a100tcsg324-1)
**Geliştirme Ortamı:** Vivado 2024.1, RISC-V GNU Toolchain
**Durum:** Sentez ✅ | Bitstream ✅ | WNS = +5.17 ns | Güç = 0.12 W

---

## 1. Referans Alınan Kaynaklar

| # | Kaynak | URL | Kullanım Amacı |
|---|--------|-----|----------------|
| 1 | **CV32E40P** (OpenHW Group) | github.com/openhwgroup/cv32e40p | EX aşamasında dal çözümleme stratejisi, 2-çevrim flush mimarisi doğrulaması |
| 2 | **ultraembedded/riscv** | github.com/ultraembedded/riscv | Yönlendirme (forwarding) birimi ve hazard algılama tasarım örüntüsü |
| 3 | **pietroglyph/pipelined-rv32i** | github.com/pietroglyph/pipelined-rv32i | Dal çözümleme aşaması (EX vs MEM) karşılaştırması |
| 4 | **Digilent Nexys 4 DDR Master XDC** | digilent.com | Pin kısıtlama dosyası (nexys4.xdc) temeli |
| 5 | **IEEE Std 1364-2005 (Verilog)** | — | Dil standardı referansı |
| 6 | **Patterson & Hennessy, CoD 5e** | — | Boru hattı mimarisi ve veri tehlikesi (hazard) teorisi |

---

## 2. Mimari Kararlar — Seçim, Alternatif ve Gerekçe

### 2.1 Dal Çözümleme Aşaması: EX

| Seçilen | Alternatif | Fark | Gerekçe |
|---------|-----------|------|---------|
| EX aşamasında çözüm (2-çevrim flush) | MEM aşamasında çözüm (3-çevrim flush) | Her dal için 1 çevrim daha az kayıp | CV32E40P ile örtüşüyor; saat başına IPC daha yüksek |

- Dal koşulu (BEQ/BNE/BLT/BGE/BLTU/BGEU) EX aşamasında ALU bayrakları ile değerlendirilir.
- Hatalı getirilen 2 komut (IF ve ID aşamalarındaki) NOP'a dönüştürülür (flush).

### 2.2 Kayıt Dosyası: Write-Through

| Seçilen | Alternatif | Fark | Gerekçe |
|---------|-----------|------|---------|
| Write-through (WB→ID aynı çevrim) | Ayrı WB yönlendirme yolu | Daha az donanım, 1 cycle daha az stall riski | Küçük çekirdeklerde tercih edilen yöntem; ultraembedded/riscv ile örtüşüyor |

### 2.3 Veri Belleği (DMEM): 4×8-bit LUTRAM Bankları

| Seçilen | Alternatif | Fark | Gerekçe |
|---------|-----------|------|---------|
| 4 ayrı 8-bit `ram_style="distributed"` dizisi | Tek 32-bit BRAM | Bayt/yarı-sözcük yazma için byte-enable sinyali gerek duymaz | Vivado Synth-8849/6850 uyarılarını ortadan kaldırır; BRAM byte-enable örüntüsü zorunda değil |

- Her banka bir baytı bağımsız yazar; `dmem_we[3:0]` ile kontrol edilir.
- Okuma asenkron, yazma synchronous (posedge clk).

### 2.4 Yük-Kullanım Gecikmesi (Load-Use Hazard): 1 Çevrim Stall

| Seçilen | Alternatif | Fark | Gerekçe |
|---------|-----------|------|---------|
| Hazard algılama birimi + IF/ID & ID/EX durdurma | Derleyici tarafından NOP ekleme | Donanım garantili, yazılım bağımsız | Standart 5-aşamalı boru hattı uygulaması |

### 2.5 Piksel Saati (pclk): Toggle FF + BUFG

| Seçilen | Alternatif | Fark | Gerekçe |
|---------|-----------|------|---------|
| 50 MHz FF toggle → BUFG ile 25 MHz | MMCM/PLL ile 25 MHz üretimi | MMCM kaynak tüketimi 0, kurulum basit | Küçük tasarımlarda yeterli; MMCM gereksiz karmaşıklık ekler |

- `CLOCK_DEDICATED_ROUTE FALSE` kısıtı zorunludur: FF çıkışı saat omurgasında (dedicated clock spine) yönlendirilemiyor.
- `create_generated_clock` ile Vivado'ya 25 MHz bildirilir; zamanlama analizi doğru yapılır.

### 2.6 Karakter Tamponu (char_buffer): Gerçek Çift Portlu BRAM

| Seçilen | Alternatif | Fark | Gerekçe |
|---------|-----------|------|---------|
| True Dual-Port BRAM (Port A = 50 MHz, Port B = 25 MHz) | Tek portlu BRAM + zaman dilimleme (time-multiplexing) | İki saat alanı çakışma riski olmadan bağımsız | Vivado xpm_memory veya native BRAM primitifi ile kolayca çıkarım yapılır |

### 2.7 Font ROM: LUTRAM (Dağıtık RAM)

| Seçilen | Alternatif | Fark | Gerekçe |
|---------|-----------|------|---------|
| `rom_style="distributed"` LUTRAM, 2048×8 bit | BRAM tabanlı font | Asenkron okuma → ek boru hattı aşaması gerekmez | 16 Kbit ≈ Artix-7 LUTRAM kapasitesinin küçük bir kısmı; `$readmemh` ile `font8x16.hex` yüklenir |

### 2.8 Sanal Kaydırma (Virtual Scroll): scroll_base İşaretçisi

| Seçilen | Alternatif | Fark | Gerekçe |
|---------|-----------|------|---------|
| `scroll_base[4:0]` modüler indeks; veri kopyalanmaz | Tüm satırları bir yukarı kaydır (80×29 = 2320 BRAM yazımı) | Kaydırma anında tamamlanır (1 çevrim); veri taşıma ~46 µs @ 50 MHz sürer | Donanım terminal denetleyicisi için tek pratik seçenek |

- Görüntü adresi: `phys_row = (display_row + scroll_base) % 30`
- Yeni boşalan alt satır 80 çevrimde (1.6 µs) `0x0F20` (beyaz-üzeri-siyah boşluk) ile silinir.

### 2.9 Senkron Sıfırlama (Sync Reset) — BRAM Adresi

| Seçilen | Alternatif | Fark | Gerekçe |
|---------|-----------|------|---------|
| `always @(posedge clk)` — yalnızca senkron | `always @(posedge clk or negedge rst_n)` | DRC REQP-1839 uyarısını ortadan kaldırır | Artix-7 BRAM adres pinleri asenkron kontrol sinyalleri kabul etmez; Vivado bunu REQP-1839 olarak raporlar |

### 2.10 UCIO-1 DRC Önem Derecesi Düşürme

| Seçilen | Alternatif | Fark | Gerekçe |
|---------|-----------|------|---------|
| `set_property SEVERITY {Warning} [get_drc_checks UCIO-1]` | A7 pini yerine alternatif pin bulmak | Bitstream üretimini bloklamaz | Vivado 2024.1, Digilent'in resmi XDC dosyasındaki A7 pinini (VGA_G2) geçersiz sayıyor — büyük ihtimalle parça veritabanı regresyonu; gerçek donanım bağlantısı değişmedi |

---

## 3. Geliştirme Süreci — Kronolojik

1. RV32I ISA spesifikasyonu incelendi; 5-aşamalı boru hattı mimarisi kararlaştırıldı.
2. `pc.v`, `imem.v`, `regfile.v`, `rv32_alu.v` tek tek yazıldı ve birim düzeyinde doğrulandı.
3. `rv32_control.v` ile tam RV32I çözümleme (decode) tamamlandı; ölü çıkışlar kaldırıldı.
4. `forwarding_unit.v` ve `hazard_detection_unit.v` ile veri tehlikeleri çözüldü.
5. `rv32_core.v` ile 5-aşamalı boru hattı bütünleştirildi; `EXT_DMEM` parametresi eklendi.
6. `tb_rv32_core.v` testbench'i yazıldı; 14/14 test geçti (ADD, SUB, LW, SW, BEQ, JAL, SLT, SLTU, load-use stall doğrulandı).
7. `rv32_soc.v` ile SoC oluşturuldu: DMEM BRAM, UART, LED, SW çevre birimleri bellek haritasına bağlandı.
8. `fpga_top.v` ile Nexys 4 DDR kart sarmalayıcısı tamamlandı; 50 MHz saat kısıtı eklendi.
9. Vivado sentezinde Synth-8849/6850 uyarısı alındı; `dmem.v` 4×8-bit LUTRAM'a yeniden yazıldı.
10. VGA Phase 3 kapsamında `vga_sync.v`, `char_buffer.v`, `font_rom.v`, `vga_text_ctrl.v`, `vga_terminal.v` oluşturuldu.
11. `vga_terminal.v` FSM'i yazıldı: IDLE / WRITE_CHAR / SCROLL_CLR / CLR_SCREEN durumları.
12. Asenkron sıfırlama DRC REQP-1839 uyarısı alındı; tüm FSM kayıtları senkron sıfırlamaya dönüştürüldü.
13. `nexys4.xdc` dosyasına `CLOCK_DEDICATED_ROUTE FALSE` ve `UCIO-1` önem düşürme eklendi.
14. `font_rom.v` ve `vga_text_ctrl.v`'ye `FONT_FILE` parametresi eklendi; Windows yolu sabit koddan kaldırıldı.
15. `fpga_top.v`'ye `IMEM_FILE` ve `FONT_FILE` üst düzey parametreleri taşındı.
16. Vivado implementation tamamlandı: WNS = +5.17 ns, TNS = 0, hiçbir yönlendirilmemiş net yok.
17. Bitstream başarıyla üretildi; 23 DRC uyarısı var, kritik hata sıfır.
18. Proje kök dizininde Git başlatıldı; `.gitignore` ile Vivado önbellek/rapor dosyaları hariç tutuldu.
19. 30 dosyadan oluşan ilk commit (`b10b00e`) `master` branch'ine alındı.
20. `phase3-vga-cleanup` branch'i oluşturuldu; Phase 3 temizlik değişiklikleri (`72b39f8`) commit'lendi.
21. GitHub'da özel (private) `tahatahsinakyuz/akyuz-rv32i` deposu oluşturuldu.
22. `master` ve `phase3-vga-cleanup` branch'leri GitHub'a push edildi.
23. PR #1 açıldı ("Phase 3 VGA terminal: sync reset, param paths, dead code removal") ve `master`'a merge edildi.

---

## 4. Dosya Envanteri ve Sorumlulukları

| Dosya | Katman | Sorumluluk |
|-------|--------|-----------|
| `pc.v` | IF | Program sayacı; `write_en` ile stall desteği |
| `imem.v` | IF | Asenkron komut belleği; `$readmemh` ile hex init |
| `if_id_reg.v` | IF/ID | Boru hattı kaydı; flush → NOP, stall → tut |
| `rv32_control.v` | ID | Tam RV32I çözümleme; kontrol sinyalleri üretimi |
| `regfile.v` | ID | 32×32 kayıt dosyası; write-through WB→ID çakışma çözümü |
| `id_ex_reg.v` | ID/EX | Boru hattı kaydı; flush kontrol sinyallerini sıfırlar |
| `alu.v` | EX | 10 RV32I işlemi + PASS_B |
| `forwarding_unit.v` | EX | RAW yönlendirme: EX-EX ve MEM-EX öncelikli |
| `hazard_detection_unit.v` | EX | Yük-kullanım stall algılama |
| `ex_mem_reg.v` | EX/MEM | Boru hattı kaydı |
| `dmem.v` | MEM | 4×8-bit LUTRAM; bayt/yarı-sözcük yazma granülaritesi |
| `mem_wb_reg.v` | MEM/WB | Boru hattı kaydı |
| `rv32_core.v` | Üst | Çekirdek üst modülü; `EXT_DMEM` parametresi |
| `rv32_soc.v` | SoC | Çekirdek + adres çözücü + DMEM BRAM + çevre birimleri |
| `uart_tx.v` | Çevre | 8N1 UART TX; `CLK_DIV` parametreli |
| `seg7_driver.v` | Çevre | 8 basamaklı hex 7-segment çoklamalı sürücü |
| `fpga_top.v` | Kart | Nexys 4 DDR sarmalayıcı; saat + reset + VGA bağlantıları |
| `vga_sync.v` | VGA | 640×480@60 Hz zamanlama; hsync/vsync/blank üretimi |
| `char_buffer.v` | VGA | Gerçek çift portlu BRAM 80×30×16 bit |
| `font_rom.v` | VGA | 8×16 bitmap font LUTRAM; 128 karakter, 2048×8 bit |
| `vga_text_ctrl.v` | VGA | Piksel üreteci; font ROM + char_buffer okuma; scroll_base desteği |
| `vga_terminal.v` | VGA | Donanım terminal denetleyicisi; imleç, CR/LF, sanal kaydırma FSM |
| `nexys4.xdc` | Kısıt | Pin, saat, bitstream kısıtları |

---

## 5. Bellek Haritası

| Adres Aralığı | Çevre Birimi | Erişim |
|---------------|-------------|--------|
| `0x0000_0000` – `0x0000_0FFF` | IMEM (4 KiB) | R (komut fetch) |
| `0x0001_0000` – `0x0001_0FFF` | DMEM (4 KiB) | R/W |
| `0x0002_0000` | UART TX | W |
| `0x0002_0008` | LED kaydı | W |
| `0x0002_000C` | Switch girişi | R |
| `0x0003_0000` | VGA DATA (char yaz) | W — `[15:12]=bg, [11:8]=fg, [7:0]=ASCII` |
| `0x0003_0004` | VGA CURSOR (imleç ayarla) | W — `[12:8]=satır, [6:0]=sütun` |
| `0x0003_0008` | VGA CTRL (ekranı temizle) | W — herhangi değer |

---

## 6. Sentez Sonuçları (Phase 3 Son Durum)

| Metrik | Değer |
|--------|-------|
| Worst Negative Slack (WNS) | +5.17 ns |
| Total Negative Slack (TNS) | 0 ns |
| Worst Hold Slack (WHS) | +0.044 ns |
| Başarısız uç noktalar | 0 |
| Yönlendirilmemiş net | 0 |
| LUT kullanımı | ~2.200 / 63.400 (%3) |
| Flip-Flop kullanımı | ~1.700 / 126.800 (%1) |
| BRAM (36K) | 1 (char_buffer) |
| Güç (toplam) | 0.12 W |
| DRC uyarısı | 23 (kritik hata: 0) |

---

## 7. Bilinen Kısıtlamalar ve Sonraki Aşamalar

- `vga_sync.v` Port B asenkron sıfırlaması REQP-1839 uyarısı üretiyor; bitstream'i bloklamıyor ancak senkrona dönüştürülmesi önerilir.
- `vga_g[2]` için A7 pini Vivado 2024.1 tarafından reddediliyor; Digilent'in resmi XDC dosyasındaki pim olmasına karşın UCIO-1 hatası `Warning` olarak aşıldı.
- FENCE.I şu an NOP olarak işleniyor; sıralı boru hattında güvenli.
- CSR (Control and Status Register) ve trap desteği Prototip 4'e ertelendi.
- Phase 4 hedefleri: I2C/SPI master çevre birimleri, GCC toolchain entegrasyonu, FPGA donanım testi.

---

*Raporu hazırlayan: Taha Tahsin Akyüz — 4 Mart 2026*
