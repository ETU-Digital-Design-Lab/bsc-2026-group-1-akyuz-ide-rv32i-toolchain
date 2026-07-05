# RV32_Prototip_2

Bu klasör, RISC-V RV32I bitirme projesinin **ikinci prototipini** içerir: 5 aşamalı (5-stage) pipeline yapısına sahip bir RV32I işlemci çekirdeği ve bu çekirdeği **Wishbone B4** veri yolu üzerinden GPIO, UART, SPI ve Timer çevre birimlerine (peripheral) bağlayan bir SoC (System on Chip) bütünleşmesi.

Prototip-1'e göre neyin değiştiği `docs/DEGISIKLIK_RAPORU.md` içinde ayrıntılı olarak listelenmiştir (Wishbone B4 el sıkışma protokolü, byte/halfword load-store desteği, `funct3` sinyalinin MEM/WB aşamalarına taşınması vb.). Bu README, o rapora ek olarak, koda bakan bir dışarıdan gözlemcinin (jüri, başka bir öğrenci) mimariyi ve klasördeki dosyaları hızlıca anlamasını sağlamak için yazılmıştır.

## 1. İşlemci Çekirdeği: 5 Aşamalı Pipeline

Çekirdek (`rtl/rv32_core_pipelined.v`), klasik 5 aşamalı RISC mimarisini uygular:

```
IF (Fetch) -> ID (Decode) -> EX (Execute) -> MEM (Memory) -> WB (Writeback)
```

Aşamalar arasındaki pipeline register'ları ayrı Verilog modülleri olarak yazılmıştır:

| Modül | Taşıdığı bilgi |
|---|---|
| `rtl/if_id_reg.v` | `pc_plus_4`, ham `instruction`, `pc` — IF'ten ID'ye |
| `rtl/id_ex_reg.v` | rs1/rs2 verisi, immediate, `rd`, `funct3`, tüm ID kontrol sinyalleri — ID'den EX'e |
| `rtl/ex_mem_reg.v` | `alu_result`, store için `rs2_data`, `rd`, `funct3`, kontrol sinyalleri — EX'ten MEM'e |
| `rtl/mem_wb_reg.v` | `alu_result`, bellekten okunan veri, `rd`, `funct3`, kontrol sinyalleri — MEM'den WB'ye |

**IF aşaması:** `pc` modülü (`rtl/pc.v`) `posedge clk`'te `pc_next` değerini üstlenir; `rst_n=0` iken PC `0x00000000`'a döner. `pc_next`, hazard biriminden gelen `pc_write_en` sinyaline göre ya `pc_next_calculated` (EX aşamasından hesaplanan sonraki adres) ya da mevcut PC'nin kendisidir (stall durumunda PC dondurulur).

**ID aşaması:** `rtl/rv32_control.v` ham `instruction`'ı çözer: opcode/funct3/funct7 ayrıştırma, I/S/B/J/U tipi immediate üretimi (`imm_i`, `imm_s`, `imm_b`, `imm_j`, `imm_u`) ve ALU/kontrol sinyallerinin (`alu_op`, `alu_src`, `alu_a_sel`, `reg_write_en`, `dmem_we`, `branch_en`, `jal_en`, `jalr_en`, `pc_to_reg`) üretilmesinden sorumludur. Ayrıca `uses_rs1`/`uses_rs2` çıkışları hazard biriminin yanlış pozitif stall üretmesini önlemek için üretilir (örn. LUI/JAL rs1/rs2 kullanmaz). `rtl/regfile.v` 32 adet 32-bit register barındırır, x0 her zaman 0 döner ve WB aşaması aynı çevrimde aynı register'ı okuyorsa (`rd_we && rd_addr==rs1_addr`) kombinasyonel bir "write-through" ile en güncel veriyi ID okumasına yansıtır — bu, forwarding unit'ten bağımsız, register dosyasının kendi içindeki ayrı bir bypass mekanizmasıdır.

**EX aşaması:** `rtl/alu.v` (`rv32_alu`) 10 adet kombinasyonel işlem yapar: ADD, SUB, AND, OR, XOR, SLT, SLTU, SLL, SRL, SRA; `zero`/`lt`/`ltu` flag'lerini üretir. Branch koşulu (`branch_condition_ex`) bu flag'lerden `funct3`'e göre (BEQ/BNE/BLT/BGE/BLTU/BGEU) EX aşamasında hesaplanır. JAL/JALR/branch hedef adresleri de burada hesaplanır (`pc_jump_jal_ex = pc_ex + imm_ex`, `pc_jump_jalr_ex = alu_result_ex & ~32'h1`).

**MEM aşaması:** Bellek erişimi artık doğrudan bir dizi değil, Wishbone Master arayüzü (`wb_adr_o/dat_o/we_o/sel_o/stb_o/cyc_o` çıkışları, `wb_dat_i/ack_i/err_i` girişleri) üzerinden yapılır. `funct3_mem` ve `alu_result_mem[1:0]` (byte_offset) kombinasyonundan 4-bit `mem_byte_en` (Wishbone `SEL`) üretilir; store verisi de (`store_data_aligned`) byte/halfword pozisyonuna göre kaydırılır.

**WB aşaması:** `funct3_wb` ve adresin alt 2 bitine (`load_byte_offset`) göre bellekten gelen 32-bit kelimeden ilgili byte/halfword çıkarılır ve LB/LH için sign-extension, LBU/LHU için zero-extension uygulanır (`load_data_extended`). Yazılacak veri; `pc_to_reg_wb` ise `pc+4` (JAL/JALR), değilse ALU sonucu veya bellek verisi (`mem_to_reg_wb`) olarak seçilir.

### Desteklenen komutlar (kontrol biriminden çıkarılmıştır)

- R-type: ADD, SUB, AND, OR, XOR, SLT, SLTU, SLL, SRL, SRA
- I-type (ALU): ADDI, SLTI, SLTIU, ANDI, ORI, XORI, SLLI, SRLI, SRAI
- Load: LB, LH, LW, LBU, LHU (byte-enable + sign/zero-extension ile)
- Store: SB, SH, SW (byte-enable + veri hizalama ile)
- Branch: BEQ, BNE, BLT, BGE, BLTU, BGEU
- JAL, JALR
- LUI, AUIPC (U-type immediate, ALU giriş A seçici `alu_a_sel` ile 0 veya PC kullanılarak)

RV32M (çarpma/bölme) ve RV32B (bit manipülasyonu) uzantıları koda **dahil değildir**.

## 2. Forwarding Unit ve Hazard Detection Unit

Pipeline'lı bir işlemcide art arda gelen komutlar arasında veri bağımlılığı (data hazard) oluşur; bu projede iki ayrı birim bu sorunu çözer:

**`rtl/forwarding_unit.v`** — EX aşamasındaki komutun `rs1`/`rs2` kaynaklarını, henüz register dosyasına yazılmamış ama pipeline'da ilerideki (EX/MEM ve MEM/WB) sonuçlarla karşılaştırır:
- `ex_mem_rd == id_ex_rs1/rs2` ve `ex_mem_reg_write_en=1` ise **EX/MEM aşamasından** ileri besleme yapılır (öncelikli, çünkü daha yeni sonuç).
- Aksi halde `mem_wb_rd == id_ex_rs1/rs2` ve `mem_wb_reg_write_en=1` ise **MEM/WB aşamasından** ileri besleme yapılır.
- `forward_a` (ALU girişi rs1), `forward_b` (ALU girişi rs2) ve ayrıca **store verisi için ayrı bir `forward_store` sinyali** üretilir; çünkü store komutunda rs2 verisi ALU'ya değil doğrudan belleğe yazılacak veriye gider ve ALU girişi B immediate tarafından kullanılıyor olabilir.
- `rv32_core_pipelined.v` içinde, EX/MEM aşamasından beslenen değer JAL/JALR sonucu (`pc_to_reg_mem`) ise `pc_plus_4_mem`, değilse `alu_result_mem` olarak seçilir (`ex_mem_forward_value`) — bu, JAL/JALR hedefinin de doğru şekilde ileri beslenebilmesi içindir.

**`rtl/hazard_detection_unit.v`** — forwarding'in çözemediği tek durum olan **load-use hazard**'ı yakalar: EX aşamasındaki komut bir LOAD ise (`id_ex_mem_read=1`, yani sonucu henüz MEM aşamasından gelmemiştir) ve ID aşamasındaki komut bu yükün hedef register'ını (`id_ex_rd`) kaynak olarak kullanıyorsa, pipeline bir çevrim **durdurulur (stall)**:
- `pc_write_en=0` → PC dondurulur (yeni komut getirilmez)
- `if_id_write_en=0` (`stall` sinyali IF/ID register'ına gider) → IF/ID register'ı aynı komutu tutar
- `id_ex_flush=1` → ID/EX register'ına bir "bubble" (NOP) enjekte edilir, böylece EX aşamasına yanlışlıkla ikinci bir komut ilerlemez

`id_ex_mem_read`, koddaki `mem_to_reg_ex` sinyaline eşittir (yani "EX aşamasındaki komut bellekten okuyacak" anlamına gelir).

Branch/JAL/JALR alındığında ise farklı bir mekanizma devreye girer: `if_id_flush` ve `id_ex_flush`, `branch_taken_ex || jal_en_ex || jalr_en_ex` olduğunda 1 olur ve IF/ID ile ID/EX register'larına NOP enjekte edilerek yanlış getirilen komutlar iptal edilir (flush).

## 3. Wishbone Tabanlı SoC

`rtl/rv32_soc.v`, işlemci çekirdeğini bir IMEM (Harvard, doğrudan erişim) ve Wishbone B4 tabanlı bir veri yoluna (`rtl/periph/wb_interconnect.v`) bağlar. Wishbone el sıkışması `STB` (strobe/geçerli işlem), `CYC` (bus cycle aktif), `ACK` (slave işlemi tamamladı), `ERR` (geçersiz adres) ve `SEL` (4-bit byte-enable) sinyalleriyle yürütülür.

`wb_interconnect.v` adres decode işini üst bitlere bakarak yapar:

| Adres Aralığı | Boyut | Birim |
|---|---|---|
| `0x0000_0000` - `0x0000_0FFF` | 4KB | IMEM (Program ROM, sadece fetch, Harvard — Wishbone'a dahil değil) |
| `0x2000_0000` - `0x2000_0FFF` | 4KB | DMEM (`wb_dmem.v`, load/store) |
| `0x4000_0000` - `0x4000_000F` | 16B | UART |
| `0x4000_0010` - `0x4000_001F` | 16B | GPIO |
| `0x4000_0020` - `0x4000_002F` | 16B | TIMER |
| `0x4000_0030` - `0x4000_003F` | 16B | SPI |
| `0x4000_0040` - `0x4000_004F` | 16B | SIM_EXIT (sadece simülasyonda anlamlı, yazma-only) |

Adres hiçbir slave'e denk gelmezse (`sel_none`) `cpu_err_o=1` olur ve okuma verisi `0xDEAD_BEEF` döner.

`rtl/periph/wb_slave_wrapper.v`, UART/GPIO/TIMER/SPI gibi zaten senkron ve tek-çevrimli olan basit periferalleri Wishbone slave arayüzüne uyarlar (STB geldiği çevrimde hemen ACK üretir). `rtl/periph/wb_dmem.v` ise 1024x32-bit (4KB) veri RAM'idir; `SEL` sinyaliyle byte bazında yazma yapabilir, okuma kombinasyoneldir.

### Çevre Birimleri (`rtl/periph/`)

| Birim | Dosya | İşlevi | Register Haritası (byte offset) |
|---|---|---|---|
| GPIO | `gpio.v` | 32 pinli genel amaçlı giriş/çıkış; her pin bağımsız yönlendirilebilir (2 flip-flop ile giriş senkronizasyonu), giriş pini değişince kesme (irq) üretir | `0x0` DIR, `0x4` OUT, `0x8` IN (R), `0xC` IEN |
| UART | `uart.v` | Basit TX/RX seri haberleşme birimi, 16x oversampling ile baud rate üretimi, TX ve RX tamamlandığında ayrı kesmeler | `0x0` TX_DATA, `0x4` RX_DATA (R), `0x8` STATUS (TX_BUSY/RX_VALID/RX_OVF), `0xC` BAUD_DIV |
| TIMER | `timer.v` | Prescaler'lı 32-bit sayaç; `COUNT==CMP` olduğunda kesme üretir, `AUTO_RELOAD` ile sıfırlanır ya da taşarak (overflow) devam eder | `0x0` CTRL (EN/AUTO_RELOAD/IRQ_EN), `0x4` PRESCALE, `0x8` COUNT, `0xC` CMP |
| SPI | `spi.v` | Mode 0 (CPOL=0/CPHA=0 varsayılan, ikisi de yapılandırılabilir), 8-bit MSB-first SPI Master; CS otomatik veya manuel kontrol edilebilir | `0x0` CTRL (EN/CPOL/CPHA/CS_AUTO/CS_VAL), `0x4` DATA (yazınca transfer başlar), `0x8` STATUS (BUSY/TX_DONE), `0xC` CLK_DIV |

Tüm periferallerin `irq` çıkışları SoC üst modülünde `irq_uart_tx/rx`, `irq_gpio`, `irq_timer`, `irq_spi` olarak dışarı verilir (ileride bir kesme denetleyicisi eklenmesi için hazırlanmıştır; şu an işlemci çekirdeğine bağlanmamıştır).

## 4. Dosya ve Klasör Yapısı

| Yol | İçerik |
|---|---|
| `rtl/pc.v` | Program sayacı |
| `rtl/if_id_reg.v`, `id_ex_reg.v`, `ex_mem_reg.v`, `mem_wb_reg.v` | Pipeline register'ları |
| `rtl/rv32_control.v` | Komut çözücü + kontrol sinyali üreteci |
| `rtl/alu.v` | Aritmetik/Mantık Birimi (`rv32_alu`) |
| `rtl/regfile.v` | 32x32-bit register dosyası |
| `rtl/forwarding_unit.v` | EX-EX / MEM-EX ileri besleme birimi |
| `rtl/hazard_detection_unit.v` | Load-use stall birimi |
| `rtl/rv32_core_pipelined.v` | Tüm aşamaları birleştiren üst-düzey çekirdek modülü |
| `rtl/rv32_soc.v` | Çekirdek + IMEM + Wishbone bus + periferaller (SoC üst modülü) |
| `rtl/periph/wb_interconnect.v` | Wishbone B4 adres decode + bus mux |
| `rtl/periph/wb_slave_wrapper.v` | Basit periferalleri Wishbone slave'e uyarlayan jenerik wrapper |
| `rtl/periph/wb_dmem.v` | Wishbone uyumlu veri RAM (byte-enable destekli) |
| `rtl/periph/gpio.v`, `uart.v`, `timer.v`, `spi.v` | Çevre birimleri |
| `tests/tb_rv32_core.v` | Çekirdek-seviyesi testbench (Wishbone bus'ı davranışsal olarak taklit eder) |
| `sim/run_sim.bat` | Çekirdek testbench'ini derleyip çalıştıran Icarus Verilog betiği |
| `sim/run_soc_sim.bat` | SoC testbench'ini derleyip çalıştırmayı hedefleyen betik (bkz. Bölüm 5 — şu an eksik dosya nedeniyle çalışmıyor) |
| `docs/DEGISIKLIK_RAPORU.md` | Prototip-1 → Prototip-2 arası değişikliklerin raporu |
| `analiz.txt` | Koda dair ayrıntılı, karşılaştırmalı teknik analiz notları |
| `program.mem` | SoC'nin IMEM'ini `$readmemh` ile başlatan makine kodu dosyası |

## 5. Simülasyonun Çalıştırılması

Simülatör olarak **Icarus Verilog (`iverilog`/`vvp`)** kullanılır; `-g2012` bayrağıyla SystemVerilog-2012 dil desteği açılır. Sisteminizde Icarus Verilog kurulu ve `PATH` üzerinde erişilebilir olmalıdır (`iverilog -V` ile sürüm kontrol edilebilir).

**Çekirdek testi (`sim/run_sim.bat`) — çalışır durumda:**

```
cd sim
run_sim.bat
```

Bu betik `tests/tb_rv32_core.v` dosyasını çekirdeğin tüm RTL dosyalarıyla (`rv32_core_pipelined.v`, `rv32_control.v`, `alu.v`, `regfile.v`, `pc.v`, pipeline register'ları, forwarding/hazard birimleri) birlikte derler ve `vvp` ile çalıştırır. Testbench, Wishbone veri yolunu kendi içinde davranışsal olarak taklit eder (bkz. Bölüm 6) ve programı doğrudan `imem`/`dmem` dizilerine komut kodlayarak (`encode_r_type`, `encode_i_type` vb. fonksiyonlarla) yükler — yani bu test **`program.mem` dosyasını kullanmaz**. Sekiz test senaryosu sırayla çalıştırılır (temel pipeline akışı, EX-EX ve MEM-EX forwarding, load-use stall, branch flush, byte load/store, halfword load/store, tüm özelliklerin bir arada olduğu demo) ve sonuçlar `$display` ile konsola, dalga formu ise `tb_rv32_core.vcd` dosyasına yazılır.

**SoC testi (`sim/run_soc_sim.bat`) — şu an çalışmıyor:**

Bu betik `sim/tb_soc.v` adlı bir testbench dosyasını derlemeyi hedefler, ancak bu dosya ne `sim/` klasöründe ne de projenin başka bir yerinde mevcuttur — depoda bulunmuyor. Bu nedenle betik çalıştırıldığında derleme aşamasında (`iverilog`) dosya bulunamadı hatası verir. SoC'yi simüle edebilmek için önce bu testbench dosyasının yazılması (SoC'nin `clk`/`rst_n`/UART/GPIO/SPI portlarını süren ve periferalleri test eden bir üst modül) gerekir. Ayrıca `rtl/rv32_soc.v` içinde `$readmemh("program.mem", imem)` çağrısı **çalışma dizinine göreli** bir yol kullandığından (betik `cd /d "%~dp0"` ile `sim/` dizinine geçtiği için), `program.mem` dosyasının simülasyon sırasında `sim/` klasöründen erişilebilir olması gerekir (proje kökünde duran mevcut kopyanın `sim/` içine kopyalanması ya da testbench çalıştırılırken çalışma dizininin proje kökü olarak ayarlanması gerekir).

## 6. `program.mem` Dosyası

`program.mem`, yalnızca **SoC üst modülü** (`rtl/rv32_soc.v`) tarafından kullanılır: modülün başlatma (`initial`) bloğunda önce IMEM'in tamamı NOP (`32'h0000_0013`) ile doldurulur, ardından `$readmemh("program.mem", imem)` çağrısıyla bu dosyadaki satırlar sırayla IMEM kelimelerinin üzerine yazılır. Dosya, `//` ile başlayan yorum satırları hariç, satır başına bir adet 32-bit makine kodunu **hexadecimal** olarak içerir (adres belirtilmemişse sırayla `0x00000000`'dan başlanır; `$readmemh` standart olarak `@adres` satırlarıyla belirli bir adresten başlamayı da destekler).

Şu anki içeriği (yalnızca 4 adet NOP komutu) yer tutucu niteliğindedir:

```
00000013
00000013
00000013
00000013
```

Gerçek bir test programı yüklemek için: derlenmiş/elle yazılmış RV32I makine kodu, her komut ayrı bir satırda 8 haneli hex olacak şekilde bu dosyaya yazılmalıdır (örn. `LUI x1, 0x20000` → `00020137` gibi). Çekirdek-seviyesi testbench (`tests/tb_rv32_core.v`) bu dosyayı **kullanmaz**; kendi test komutlarını doğrudan Verilog içinde kodlayarak `imem` dizisine yükler.
