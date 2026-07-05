> **Not (arşiv):** Bu rapor 7 Haziran 2026 tarihli, tarihsel bir ara değerlendirmedir. Güncel ve kapsamlı mimari/kullanım dokümantasyonu için [`../../RV32_Prototip_2/README.md`](../../RV32_Prototip_2/README.md) dosyasına bakın. Bu dosya yalnızca geliştirme sürecinin kaydı olarak saklanmaktadır.

# RV32_Prototip_2 — İnceleme Raporu

**Tarih:** 7 Haziran 2026  
**Konum:** `RV32_Prototip_2/`  
**Amaç:** Simülasyon odaklı, Wishbone B4 bus'lı tam RV32I SoC prototipi

---

## 1. Genel Özet

Prototip 2, bitirme projesinin **simülasyon ve bus mimarisi** aşamasıdır. Prototip 1'den temel farkı:

- **Wishbone B4** pipelined bus protokolü (STB/CYC/ACK/ERR handshaking)
- **Tam byte/halfword load-store** desteği (LB/LBU/LH/LHU/SB/SH/SW)
- Modüler **periferik wrapper** yapısı

Bu prototip **FPGA'ya yönelik değildir**: XDC dosyası yok, top-level FPGA wrapper yok. Tüm doğrulama **Icarus Verilog** simülasyonu ile yapılır.

| Özellik | Değer |
|---------|-------|
| İşlemci | RV32I, 5 aşamalı pipeline |
| Bus | Wishbone B4 (master: CPU, slave: DMEM + periferikler) |
| Bellek mimarisi | Harvard (IMEM ayrı, DMEM bus üzerinden) |
| Hedef platform | Simülasyon (iverilog + vvp) |
| Sentez / bitstream | **Yok** |

---

## 2. Tasarım Amacı ve Ne Yapıyor?

Prototip 2 şunları hedefler:

1. **RV32I çekirdeğini** forwarding, hazard detection ve branch flush ile doğrulamak
2. Gerçek bir SoC bus protokolü (**Wishbone B4**) üzerinde bellek ve çevrebirim erişimini modellemek
3. RV32I'nin tam **bellek erişim genişliği** desteğini (byte/halfword) implemente etmek
4. UART, GPIO, Timer, SPI gibi çevrebirimleri bus üzerinden CPU'ya bağlamak

Kullanım senaryosu: `program.mem` dosyasına yüklenen RISC-V programı simülasyonda çalışır; UART üzerinden çıktı, GPIO üzerinden pin kontrolü, simülasyon çıkışı için `SIM_EXIT` adresi kullanılır.

---

## 3. Dosya Yapısı

```
RV32_Prototip_2/
├── rtl/
│   ├── rv32_core_pipelined.v   # Ana CPU (Wishbone master)
│   ├── rv32_soc.v              # SoC top-level
│   ├── rv32_control.v          # Komut dekoderi
│   ├── alu.v                   # ALU
│   ├── regfile.v, pc.v         # Kayıt dosyası, program sayacı
│   ├── if_id_reg.v, id_ex_reg.v, ex_mem_reg.v, mem_wb_reg.v
│   ├── forwarding_unit.v, hazard_detection_unit.v
│   └── periph/
│       ├── wb_interconnect.v   # Bus arbiter/decoder
│       ├── wb_slave_wrapper.v  # Periferik → Wishbone adaptörü
│       ├── wb_dmem.v           # 4KB data RAM (Wishbone slave)
│       ├── uart.v, gpio.v, timer.v, spi.v
├── tests/tb_rv32_core.v        # 8 testli testbench
├── sim/run_sim.bat             # Core simülasyonu
├── sim/run_soc_sim.bat         # Tam SoC simülasyonu
├── docs/DEGISIKLIK_RAPORU.md   # Prototip 1→2 geçiş raporu
└── program.mem                 # Simülasyon program belleği
```

---

## 4. İşlemci Çekirdeği (`rv32_core_pipelined.v`)

### 4.1 Pipeline

```
IF → ID → EX → MEM → WB
```

| Aşama | Görev |
|-------|-------|
| **IF** | PC'den komut adresi, IMEM okuma |
| **ID** | Decode, immediate üretimi, register okuma |
| **EX** | ALU, branch/jump kararı, forwarding |
| **MEM** | Wishbone bus erişimi, byte-enable, store alignment |
| **WB** | Load sign/zero extension, register write-back |

### 4.2 Hazard Yönetimi

- **Forwarding (bypass):** EX→EX ve MEM→EX yolları
- **Load-use stall:** LW sonrası 1 çevrim bekleme
- **Branch flush:** Branch/JAL/JALR alındığında 2 çevrim flush

### 4.3 Desteklenen Komutlar

`rv32_control.v` üzerinden tam RV32I base integer seti:

| Kategori | Komutlar |
|----------|----------|
| R-type | ADD, SUB, AND, OR, XOR, SLT, SLTU, SLL, SRL, SRA |
| I-type | ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI |
| Load | LB, LBU, LH, LHU, LW |
| Store | SB, SH, SW |
| Branch | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| Jump | JAL, JALR |
| Upper imm | LUI, AUIPC |

### 4.4 ALU (`alu.v`)

11 işlem: ADD, SUB, AND, OR, XOR, SLT, SLTU, SLL, SRL, SRA + flag çıkışları (zero, lt, ltu).

### 4.5 Wishbone Master Arayüzü

CPU'nun data bus sinyalleri:

| Sinyal | Yön | Açıklama |
|--------|-----|----------|
| `wb_adr_o` | Out | Adres |
| `wb_dat_o` | Out | Yazma verisi |
| `wb_dat_i` | In | Okuma verisi |
| `wb_we_o` | Out | Write enable |
| `wb_sel_o[3:0]` | Out | Byte select (LB/SB için) |
| `wb_stb_o` | Out | Strobe |
| `wb_cyc_o` | Out | Cycle aktif |
| `wb_ack_i` | In | Slave onayı |
| `wb_err_i` | In | Bus hatası |

MEM aşamasında `funct3` + `alu_result[1:0]` ile byte-enable üretilir; WB aşamasında load sign/zero extension yapılır.

---

## 5. SoC (`rv32_soc.v`)

### 5.1 Bileşenler

| Modül | Rol |
|-------|-----|
| `rv32_core_pipelined` | CPU (Wishbone master) |
| `wb_interconnect` | Adres decode + mux |
| `wb_dmem` | 4KB data RAM |
| IMEM (inline reg array) | 4KB program ROM, `program.mem`'den yüklenir |
| `uart` | Seri haberleşme |
| `gpio` | 32-pin GPIO |
| `timer` | 32-bit sayaç |
| `spi` | SPI master |

### 5.2 Bellek Haritası

| Adres Aralığı | Boyut | Açıklama |
|---------------|-------|----------|
| `0x0000_0000` – `0x0000_0FFF` | 4 KB | IMEM (Harvard, doğrudan fetch) |
| `0x2000_0000` – `0x2000_0FFF` | 4 KB | DMEM (load/store) |
| `0x4000_0000` – `0x4000_000F` | 16 B | UART |
| `0x4000_0010` – `0x4000_001F` | 16 B | GPIO |
| `0x4000_0020` – `0x4000_002F` | 16 B | TIMER |
| `0x4000_0030` – `0x4000_003F` | 16 B | SPI |
| `0x4000_0040` – `0x4000_004F` | 16 B | SIM_EXIT (simülasyon sonlandırma) |

> **Not:** Prototip 3/4'teki adres haritası (`0x0001_xxxx` DMEM, `0x0002_xxxx` MMIO) burada **farklıdır**.

### 5.3 Wishbone Bus (`wb_interconnect.v`)

- Adres üst bitlerine göre slave seçimi
- Geçersiz adrese **ERR** yanıtı
- Byte-enable (`SEL`) tüm slave'lere iletilir
- Wait-state desteği (yavaş periferikler için)

### 5.4 Çevrebirimler

**UART** (`periph/uart.v`):
- Register: TX_DATA, RX_DATA, STATUS, BAUD_DIV
- 115200 baud (50 MHz varsayılan)
- TX/RX interrupt çıkışları

**GPIO** (`periph/gpio.v`):
- DIR, OUT, IN, IEN register'ları
- 32 pin, yön kontrolü, edge interrupt

**Timer** (`periph/timer.v`):
- 32-bit counter, prescaler, compare

**SPI** (`periph/spi.v`):
- SPI master, clock/data/CS kontrolü

---

## 6. XDC / FPGA Kısıtları

**Bu prototipte XDC dosyası bulunmuyor.**

FPGA pin ataması, sentez veya implementation yapılmamış. Tasarım tamamen RTL simülasyonu için optimize edilmiş.

---

## 7. Simülasyon ve Test

### 7.1 Araçlar

- **Derleyici:** Icarus Verilog (`iverilog -g2012`)
- **Simülatör:** `vvp`
- **Betikler:** `sim/run_sim.bat` (core), `sim/run_soc_sim.bat` (tam SoC)

### 7.2 Test Suite (`tests/tb_rv32_core.v`)

| Test | Açıklama |
|------|----------|
| 1 | Temel 5 aşamalı pipeline |
| 2 | EX→EX forwarding |
| 3 | MEM→EX forwarding |
| 4 | Load-use hazard (LW stall) |
| 5 | Branch flush |
| 6 | Byte load/store (LB/LBU/SB) — **yeni** |
| 7 | Halfword load/store (LH/LHU/SH) — **yeni** |
| 8 | Tüm özellikler demo — **yeni** |

---

## 8. Sentez Durumu

| Aşama | Durum |
|-------|-------|
| RTL sentezi | Yapılmamış |
| Place & Route | Yapılmamış |
| Bitstream | Yok |
| Vivado projesi | Yok |

`analiz.txt` dosyasında modül bazlı sentez karakteristikleri (tahmini LUT/FF sayıları, timing notları) mevcut; bunlar otomatik analiz çıktısıdır, gerçek Vivado raporu değildir.

---

## 9. Prototip 3/4 ile Karşılaştırma

| Özellik | Prototip 2 | Prototip 3/4 |
|---------|------------|--------------|
| Bus | Wishbone B4 | Basit adres decode (MMIO) |
| DMEM adresi | `0x2000_0000` | `0x0001_0000` |
| Periferik adresi | `0x4000_xxxx` | `0x0002_xxxx` |
| VGA | Yok | Var |
| Kamera | Yok | Var (P3/P4) |
| Bootloader | Yok | Var (UART) |
| FPGA | Yok | Basys 3 |
| Core modül adı | `rv32_core_pipelined` | `rv32_core` |

---

## 10. Sonuç

**RV32_Prototip_2**, işlemci çekirdeğinin doğruluğunu ve SoC bus mimarisini simülasyonda kanıtlamak için tasarlanmış **referans RTL** katmanıdır. Wishbone protokolü, tam bellek genişliği desteği ve modüler periferik yapısı güçlü yönleridir. FPGA entegrasyonu bir sonraki prototiplerde (3 ve 4) gerçekleştirilmiştir.
