# results/

Bu klasör, projenin **ölçülmüş/üretilmiş nihai sonuçlarını** barındırmak için ayrılmıştır: Vivado sentez ve implementation raporları (kaynak kullanımı, timing, güç), FPGA'ya yüklenen bitstream dosyaları, karşılaştırma tabloları, ekran görüntüleri/videolar.

Bu sonuçların anlatı/analiz kısmı zaten şu raporlarda mevcut:
- `src/akyuz-rv32i/RV32_Snake_ve_Mayin_Tarlasi/DONANIM_VE_DERLEME_NOTLARI.md` (en güncel Basys 3 sentez/timing sonuçları: LUT %13.4, BRAM %20, WNS +9.109 ns @ 50 MHz)
- `src/akyuz-rv32i/RV32_Snake_ve_Mayin_Tarlasi/2026-03-18_prototip3_rapor.md`
- `src/akyuz-rv32i/docs/eski-raporlar/` (tarihsel ara raporlar)

Önerilen kullanım: ham rapor dosyalarını (`timing.rpt`, `util.rpt`, `.bit` dosyaları) ve varsa demo görüntü/videolarını buraya, prototip adına göre alt klasörler halinde ekleyin.

## Mevcut içerik

### `demo-fotograflari/` — Gerçek donanım üzerinde çalışan sistem kanıtı

| Dosya | Açıklama |
|---|---|
| `snake_oyunu_demo.jpg` | Basys 3 kartına bağlı monitörde çalışan Snake oyununun fotoğrafı (skor ve duraklatma göstergesi ekranda görünüyor). |
| `kamera_vga_demo.jpg` | RV32_Prototip_4'ün OV7670 kamera modülünden aldığı canlı görüntüyü VGA terminal üzerinde gösteren fotoğraf. |
| `ana_menu_demo.jpg` | Snake/Mayın Tarlası donanım konsolunun ana menü ekranı (SNAKE / CAMERA / SETTINGS seçenekleri). |

### `egitim-metrikleri/` — AkyuzIDE agent fine-tuning eğitim sonuçları

| Dosya | Açıklama |
|---|---|
| `tensorboard_eval_metrikleri.png` | TensorBoard değerlendirme (eval) metrikleri: entropy, loss, mean_token_accuracy, num_tokens, runtime, samples/steps per second. |
| `tensorboard_train_metrikleri.png` | TensorBoard eğitim (train) metrikleri: entropy, epoch, grad_norm, learning_rate, loss, mean_token_accuracy, num_tokens. |
| `sistem_izleme_egitim_sirasinda.png` | Eğitim sırasında GPU/CPU kullanımını ve eğitim log çıktısını gösteren sistem izleme ekran görüntüsü (btop). |
| `train_loss_detay.png` | `train/loss` grafiğinin yakınlaştırılmış hali (1600 adımda ~0.35'e yakınsıyor). |
