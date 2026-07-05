# docs/

Bu klasör, tek bir alt projeye ait olmayan, **proje geneli** dokümantasyonu için ayrılmıştır: örneğin iki bileşenin (AkyuzIDE ve akyuz-rv32i) birlikte nasıl kullanıldığını gösteren uçtan uca bir senaryo, genel sistem mimarisi diyagramları, tasarım kararlarının gerekçeleri, literatür/referans karşılaştırmaları.

Alt projelere özgü teknik dokümantasyon zaten kendi klasörlerinde bulunuyor, buraya taşınmasına gerek yok:
- `src/AkyuzIDE/CLAUDE.md` ve `src/AkyuzIDE/README.md`
- `src/akyuz-rv32i/*/README.md` ve `src/akyuz-rv32i/*/docs/`

## Mevcut içerik

### `diyagramlar/` — Mimari ve iş akışı diyagramları

| Dosya | Açıklama |
|---|---|
| `agent_is_akisi.jpg` | AkyuzIDE agent'ının 7 adımlık çalışma akışı: İstek → Açıklama → Kod Üretimi → Simülasyon → Analiz → İyileştirme → Başarı. |
| `pipeline_5_asama.png` | RV32I 5 aşamalı pipeline'ın genel diyagramı (IF/ID/EX/MEM/WB, register file, ALU, control unit). |
| `prototip4_kamera_soc_mimarisi.png` | RV32_Prototip_4 kamera/VGA SoC'sinin blok diyagramı (kamera arayüzü, 5 aşamalı çekirdek, VGA terminal, Basys 3). |
| `basys3_on.png`, `basys3_arka.png` | Kullanılan Digilent Basys 3 FPGA geliştirme kartının ön ve arka yüz referans fotoğrafları. |

### `proje-planlama/` — Proje zaman çizelgesi

| Dosya | Açıklama |
|---|---|
| `is_paketleri_zaman_cizelgesi.jpg` | Proje iş paketlerinin (WP1: Literatür/TÜBİTAK hazırlığı, WP2: İşlemci çekirdeği, WP3: AkyuzIDE yazılımı, WP4: FPGA sentez/doğrulama, WP5: Raporlama/poster) Ekim 2025 – Haziran 2026 arası zaman çizelgesi. |
| `TUBITAK_2209_Raporu.pdf` | Projenin TÜBİTAK 2209-A (Üniversite Öğrencileri Araştırma Projeleri Destekleme Programı) kapsamında hazırlanan araştırma raporu. |
