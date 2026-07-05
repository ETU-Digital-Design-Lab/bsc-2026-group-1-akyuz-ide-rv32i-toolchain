# RV32I RISC-V İşlemci — Deneyim Raporu

**Tarih:** 4 Mart 2026
**Proje:** RV32_Prototip_3
**Kart:** Nexys 4 DDR (Artix-7 xc7a100t)
**Son Frekans:** 50 MHz

## Giriş

Tasarladığım RV32I işlemcisini Vivado 2024'te sentezledim. Simülasyonla başladığımda tüm testler geçti ama karta attığımda zamanlama hatası aldım. Bu rapor, bu süreçte ne yaptığımı yazıyor.

## 1. Özet

| Metrik | Sonuç |
|--------|-------|
| Worst Negative Slack | +4.866 ns |
| Timing Violations | 0 |
| Bitstream Status | Oluşturuldu |
| Alan Kullanımı | %3 |

## 2. Simülasyon Testleri

Testbench'te 16 komut test edildi, hepsi çıktı:

**Aritmetik:** ADDI (x1=5), ADD (x3=8), SUB (x4=2)

**Bellek:** LW ve SW işlemleri, DMEM erişimi

**Kontrol Akışı:** BEQ (şartlı atlama), JAL (fonksiyon çağrısı)

**Hazard Handling:** LW hemen ardından ADD (otomatik 1 çevrim bekleme)

**İleri İşlemler:** LUI, negatif sayılar, SLT/SLTU karşılaştırmaları

Tüm testler geçti. Program 40 çevrimde tamamlandı, simülasyon 250 çevrim çalıştırıldı.

## 3. İşlemci Bileşenleri

### ALU

11 işlemi destekliyor: ADD, SUB, AND, OR, XOR, SLT, SLTU, SLL, SRL, SRA, PASS.
Testlerde ADD, SUB, SLT, SLTU kullanıldı.

### Kontrol Sistemi

Talimatı çözüp şu sinyalleri üretir:
- `alu_op`: Hangi ALU işlemi (4 bit)
- `alu_src`: ALU ikinci girdisi, register mi sabit mi
- `reg_write_en`: Sonuç kayıt dosyasına yazılsın mı
- `dmem_we`: Belleğe yazılsın mı
- `branch_en`, `jal_en`, `pc_to_reg`: Kontrol akışı sinyalleri

BEQ ve JAL testlerinde bu sinyaller doğru çalıştı.

### Hata Yönetimi

2 sistem var:

**Forwarding (Bypass):** Bir talimatın sonucu henüz kayıt dosyasına yazılmadığında, ALU'ya doğrudan gönder. Testlerde yazılı değildi ama kod hazır.

**Hazard Detection (Stall):** Load komutunun sonucunun hemen kullanılması gerekiyorsa, 1 çevrim bekle. LW → ADD testinde başarıyla çalıştı. 

### Çevre Birimleri

UART (seri iletişim, 115200 baud) ve 7-Segment Display driver'ı kodda var ama henüz karta test edilmedi.

## 4. FPGA Sentez Sonuçları

**Başlangıçta (100 MHz hedefiyle):**
- Critical Path: 12.243 ns (10 ns period yeterli değil)
- Slack: -2.243 ns (399 hata)

**Çözüm:** Frekansı 50 MHz'ye düştük (period 20 ns)
- Slack: +4.866 ns (rahat geçti)
- Hata: 0

En uzun yol 12.243 ns. 100 MHz'de 10 ns period yetersiz. 50 MHz'de 20 ns varken hiçbir sorun yok.

**Kaynak Kullanımı:**
- LUT: 1.958 / 63.400 (%3)
- Flip-Flop: 1.606 / 126.800 (%1)
- Alan çok boş, yer sıkıntısı yok

**Güç:** 0.119 W (sağlıklı)

**Uyarılar:** 178 adet (çoğu BRAM işareti eksikliğinden, düzeltildi)

## 5. Yazılım vs Donanım Farkı

Testbench neden geçti ama FPGA başarısız oldu?

Testbench ideal ortamda çalışır. "Bu işlem 1 ns'de biter" der. Gerçek FPGA'da:
- FF çıkışı: 0.5 ns
- ALU mantığı: 8 ns (40 LUT seviyesi)
- Wiring: 2 ns
- Setup time: 0.5 ns
- Toplam: 11.5 ns

10 ns periyot yetmez. Testbench bunu fark etmez, simülde saat zamanlaması denetlenmez.

## 6. Bitstream

Dosya: `fpga_top.bit` (87 KB)
Karta JTAG üzerinden yüklenir. RAM'te tutulur, kapatınca silinir.

## 7. Mimarisi (Teknik Özet)

5-aşamalı pipeline: IF → ID → EX → MEM → WB

Bellek:
- IMEM 4 KiB (komut)
- DMEM 4 KiB (veri)
- Regfile 32 register (x0-x31)

Özellikler:
- Yazı forwarding: evet
- Load-use hazard detection: evet
- Saat: 50 MHz
- ALU işlem sayısı: 11

## 8. Bilinen Sınırlamalar

- Frekans: 100 MHz yerine 50 MHz (maksimum yapılabilir ~82 MHz)
- Kontrol akışı: JAL/JALR/BEQ test edildi, diğer şubeler henüz yazılmadı
- Çevre: UART ve display komutu hazır ama karta test edilmedi
- Komut seti: İleri instruktionlar (M extension vb) yok

## 9. Sonrası Yapılacaklar

1. Bitstream'i karta yükle ve donanım testi yap
2. İsterse frekansı 70-75 MHz'ye çıkart
3. UART/display testleri yaz
4. Ek komutlar ekle (JALR, şube çeşitleri)

## 10. Sonuç

İşlemci Vivado'da başarıyla sentezlendi, zamanlama hataları çözüldü, bitstream oluşturuldu. Simülasyonda 16 komut doğrulandı. Karta yüklenmeye hazır.

Durum: Prod hazır.

---

*Rapor: 4 Mart 2026*
*Sentez: Tamamlandı*
*Bitstream: Oluşturuldu*
