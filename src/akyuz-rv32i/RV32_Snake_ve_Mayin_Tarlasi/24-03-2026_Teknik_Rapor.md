# RV32I İşlemci ve SoC Tasarımı Teknik Raporu
**Tarih:** 24 Mart 2026
**Proje Adı:** RV32I Snake Game on Basys 3

## 1. İşlemci Mimarisi (CPU Architecture)
Sistem, RISC-V mimarisinin temel integer komut setini (RV32I) destekleyen bir işlemci çekirdeği üzerine kurulmuştur.

-   **Mimarisi Türü:** 32-bit RISC-V (RV32I - Base Integer Instruction Set).
-   **Yazmaçlar (Registers):** 32 adet 32-bit genel amaçlı yazmaç (x0 - x31). x0 donanımsal olarak 0'a sabitlenmiştir.
-   **Bellek Yapısı:** Harvard Mimarisi (Komut ve Veri yolları fiziksel olarak ayrılmıştır).
-   **İşlem Hızı:** 50 MHz (100 MHz ana saat bölünerek elde edilir).

## 2. Bellek Haritası (Memory Map)
Sistemde kullanılan bellek ve çevrebirimleri adres uzayında şu şekilde konumlandırılmıştır:

-   **Instruction RAM (IMEM):** 0x0000_0000 - 0x0000_0FFF (4 KB, BRAM).
-   **Data RAM (DMEM):** 0x0001_0000 - 0x0001_0FFF (4 KB, BRAM).
-   **Çevrebirimleri (MMIO):** 0x0002_0000 - 0x0002_0014.
-   **VGA Kontrol Birimi:** 0x0003_0000 - 0x0003_0008.

## 3. Bus Tipi ve İletişim
Sistemde veri transferi için **Memory-Mapped I/O (MMIO)** tabanlı bir adres kodlama sistemi (Address Decoding) kullanılmaktadır. Merkezi bir veri yolu (Bus) yerine, adresin üst bitlerine göre (`dmem_addr[31:16]`) ilgili birimi seçen bir dekoder yapısı mevcuttur.

## 4. Çevrebirimleri (Peripherals)
-   **VGA Terminal (80x30):** Metin modunda çalışan, 16 renk destekli bir ekran kontrolcüsüdür. Donanım seviyesinde "Graphics Bypass" modu eklenerek işlemciden bağımsız animasyon (Plasma efekti) üretme yeteneği kazandırılmıştır.
-   **UART (115200 Baud):** Seri haberleşme birimi. Hem hata ayıklama verilerini (PC dump) göndermek hem de Bootloader aracılığıyla yazılım yüklemek için kullanılır.
-   **GPIO Birimi:**
    -   **LEDs (16-bit):** Oyun skoru ve sistem durumu için kullanılır.
    -   **Switches (16-bit):** `SW0` (Reset), `SW1` (Ayarlar/Speed Menu) ve diğerleri.
    -   **Buttons (5-bit):** `BTNU/D/L/R` (Yön) ve `BTNC` (Pause/Resume).
-   **Cycle Counter (32-bit):** İşlemci çevrim sayısını tutarak mikrosaniye hassasiyetinde zamanlama ve rastgele sayı üretimi (Seed) sağlar.

## 5. Bootloader Mekanizması
Donanımsal Bootloader (`hw_bootloader.v`), UART üzerinden gelen verileri dinler. 
-   **Mekanizma:** "BOOT" (Magic sequence) komutu geldiğinde işlemciyi durdurur (halt).
-   **Yükleme:** Ardından gelen veriyi doğrudan BRAM (IMEM/DMEM) üzerine yazar. Yazma işlemi bittiğinde işlemciyi yeni kodla baştan başlatır. 
-   Bu sayede Bitstream yüklemeden sadece yazılım güncellenebilmektedir.

## 6. C Yazılım Geliştirme Süreci
Sistem için yazılan C kodları `riscv64-unknown-elf-gcc` aracı ile derlenmektedir.

-   **Hazırlık:** Kod yazarken `main.c` içine ilgili çevre birimlerinin adresleri `#define` ile tanımlanmalıdır.
-   **Derleme:** `build.bat` betiği, kodu `.elf` formatına derler ve ardından `objcopy` ile saf makine kodu olan `.bin` dosyasına dönüştürür.
-   **Yükleme:** `python upload.py [PORT] firmware.bin` komutu ile Bootloader tetiklenir ve kod karta atılır.
-   **Uyumluluk:** Yazılan herhangi bir C kodu, eğer 4 KB IMEM sınırını aşmıyorsa ve RV32I komutlarıyla (ayrı kütüphane gerektirmeyen) yazıldıysa sistemde çalışacaktır. Donanımsal çarpma/bölme birimi bulunmadığı için bu işlemler yazılım tabanlı (bit kaydırma) yapılmalıdır.

## 7. Donanım Kaynak Kullanımı (Vivado Tahminleri)
-   **LUT Kullanımı:** ~%18 (İşlemci ve VGA mantığı).
-   **BRAM Kullanımı:** %4 (IMEM, DMEM, Font ROM, Character Buffer).
-   **IO Kullanımı:** %67 (VGA pinleri, LED, Switch, Button).
