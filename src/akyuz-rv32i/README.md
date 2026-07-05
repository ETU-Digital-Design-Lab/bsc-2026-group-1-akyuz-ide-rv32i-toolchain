# Akyuz RV32I — Bitirme Projesi

RISC-V **RV32I** komut kümesini uygulayan, 5 aşamalı (pipelined) bir işlemci çekirdeğinin sıfırdan geliştirilme sürecini belgeleyen bir bitirme projesi. Depo, çekirdeğin farklı evrim aşamalarını ayrı klasörlerde saklar: temel pipeline doğrulamasından başlayıp, bir Wishbone tabanlı SoC'ye, ardından FPGA üzerinde çalışan VGA/oyun konsoluna ve son olarak bir kamera/VGA gösterim sistemine kadar genişler.

## Prototipler

| Klasör | Açıklama | Durum |
|--------|----------|-------|
| [RV32_Prototip_2](RV32_Prototip_2/) | 5 aşamalı pipeline, forwarding unit, hazard detection unit, Wishbone B4 SoC (GPIO, UART, SPI, Timer çevre birimleri) | Çekirdek simülasyonu çalışıyor; SoC simülasyonu eksik bir test dosyası (`tb_soc.v`) nedeniyle şu an çalışmıyor — bkz. klasör README'si §5 |
| [RV32_Snake_ve_Mayin_Tarlasi](RV32_Snake_ve_Mayin_Tarlasi/) | FPGA (Basys 3), VGA donanım terminali, Snake & Mayın Tarlası oyunları, UART donanım bootloader, C toolchain (eski adı: RV32_Prototip_3, ilk olarak Nexys 4 DDR kartında geliştirildi) | Basys 3 üzerinde çalışır durumda; kapsamlı sentez/timing raporları mevcut |
| [RV32_Prototip_4](RV32_Prototip_4/) | Snake/Mayın Tarlası altyapısı üzerine kurulmuş, sadeleştirilmiş bir OV7670 kamera + VGA gösterim SoC'u | Çalışır durumda; `main.c`'deki bazı ekran metinleri (SW[15]) donanımdaki gerçek davranışla birebir örtüşmüyor — bkz. klasör README'si |

Her klasördeki README.md, o prototipin mimarisini (pipeline aşamaları, forwarding/hazard birimleri, bellek haritası, çevre birimleri), dosya yapısını ve derleme/simülasyon/FPGA'ya yükleme adımlarını ayrıntılı olarak açıklar. Kod ile mevcut raporlar arasında bulunan tutarsızlıklar da (uydurulmadan, doğrudan koddan doğrulanarak) ilgili README'lerde not edilmiştir.

## Ortak mimari temeller

Üç prototip de aynı temel RV32I pipeline tasarımını paylaşır ve üzerine farklı çevre donanımları ekler:

```
IF (Fetch) → ID (Decode) → EX (Execute) → MEM (Memory) → WB (Writeback)
```

- **Forwarding unit**: EX/MEM ve MEM/WB aşamalarındaki sonuçları, henüz register dosyasına yazılmadan EX aşamasına yönlendirerek çoğu veri bağımlılığını (RAW hazard) ekstra durdurma olmadan çözer.
- **Hazard detection unit**: Forwarding'in çözemediği tek durum olan load-use bağımlılığında pipeline'ı 1 çevrim durdurur (stall).
- **Branch/JAL/JALR**: Dal koşulu EX aşamasında çözülür; yanlış getirilen komutlar IF/ID ve ID/EX register'larına flush uygulanarak iptal edilir.

RV32_Prototip_2'de bu çekirdek bir **Wishbone B4** veri yoluna bağlıyken, Snake_ve_Mayin_Tarlasi ve Prototip_4'te daha basit, doğrudan adres kod çözümlü bir MMIO veri yolu kullanılır (VGA terminal, UART, GPIO/LED/switch/buton, çevrim sayacı).

## Hızlı başlangıç

Her prototip klasöründe `rtl/` (Verilog kaynakları), `sim/` ve/veya `tests/` (testbench, C toolchain, simülasyon betikleri) altında ilgili dosyalar bulunur. Simülasyon için Icarus Verilog (`iverilog`/`vvp`), FPGA'ya yükleme için Xilinx Vivado ve RISC-V C programları için `riscv64-unknown-elf-gcc` araç zinciri gereklidir. Adım adım talimatlar için ilgili prototip klasöründeki README.md dosyasına bakın.

## Arşiv

[`docs/eski-raporlar/`](docs/eski-raporlar/) klasörü, geliştirme sürecinin erken aşamalarında yazılmış üç inceleme raporunu (7 Haziran 2026 tarihli) tarihsel kayıt olarak saklar. Bu raporlar güncelliğini yitirmiştir — biri artık kullanılmayan bir klasör adına (`RV32_Prototip_3/`) atıfta bulunur. Güncel bilgi için her zaman ilgili prototip klasöründeki README.md dosyasını esas alın.
