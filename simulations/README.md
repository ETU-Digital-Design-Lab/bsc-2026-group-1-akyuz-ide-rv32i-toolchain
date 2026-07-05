# simulations/

Bu klasör, projenin **konsolide edilmiş simülasyon çıktılarını** (dalga formu ekran görüntüleri, `.vcd` dosyaları, simülasyon log özetleri) barındırmak için ayrılmıştır.

Simülasyonu üreten kaynak dosyalar (testbench'ler, `.bat` çalıştırma betikleri) zaten alt projelerin kendi klasörlerinde bulunuyor:
- `src/akyuz-rv32i/RV32_Prototip_2/tests/tb_rv32_core.v` + `sim/run_sim.bat`
- `src/akyuz-rv32i/RV32_Snake_ve_Mayin_Tarlasi/sim/`

Önerilen kullanım: her prototip için simülasyonu çalıştırıp üretilen `.vcd` dalga formu dosyasını veya GTKWave/Vivado dalga formu ekran görüntüsünü buraya, prototip adına göre alt klasörler halinde (örn. `simulations/RV32_Prototip_2/`) ekleyin. Henüz içerik eklenmedi.
