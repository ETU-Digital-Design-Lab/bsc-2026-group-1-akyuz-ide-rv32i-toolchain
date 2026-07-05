# RV32 Prototip-2 Degisiklik Raporu

## Prototip-1'den Prototip-2'ye Gecis

### 1. Wishbone B4 Bus Protokolu
**Onceki:** Basit kombinasyonel adres decoder (handshaking yok)
**Yeni:** Wishbone B4 pipelined bus protokolu

Yeni sinyaller:
- `STB` (Strobe): Gecerli bus islemi
- `CYC` (Cycle): Bus cycle aktif
- `ACK` (Acknowledge): Slave islem tamamladi
- `ERR` (Error): Gecersiz adres / bus hatasi
- `SEL` (Select): Byte-enable (4-bit)

Yeni moduller:
- `wb_interconnect.v` - Wishbone bus cozmek (adres decoder + mux)
- `wb_slave_wrapper.v` - Mevcut periferalleri Wishbone'a uyarlayan wrapper
- `wb_dmem.v` - Wishbone uyumlu data RAM

### 2. Byte/Halfword Load/Store Destegi
**Onceki:** Sadece LW/SW (word-level, dmem_be her zaman 4'b1111)
**Yeni:** Tam RV32I load/store destegi

| Komut | funct3 | Aciklama |
|-------|--------|----------|
| LB    | 000    | Signed byte load (sign-extension) |
| LH    | 001    | Signed halfword load (sign-extension) |
| LW    | 010    | Word load |
| LBU   | 100    | Unsigned byte load (zero-extension) |
| LHU   | 101    | Unsigned halfword load (zero-extension) |
| SB    | 000    | Byte store |
| SH    | 001    | Halfword store |
| SW    | 010    | Word store |

Degisiklikler:
- `funct3` sinyali EX -> MEM -> WB asamalarina tasinir
- MEM asamasinda `byte_offset = alu_result[1:0]` ile byte-enable uretimi
- MEM asamasinda store data alignment (SB: byte shift, SH: halfword shift)
- WB asamasinda load data extraction + sign/zero extension

### 3. Pipeline Register Degisiklikleri

**ex_mem_reg.v:**
- `funct3_ex -> funct3_mem` eklendi
- MEM asamasinda byte-enable ve store alignment icin kullanilir

**mem_wb_reg.v:**
- `funct3_mem -> funct3_wb` eklendi
- WB asamasinda load sign/zero extension icin kullanilir

### 4. Islemci Cekirdegi (rv32_core_pipelined.v) Degisiklikleri

**Wishbone Master arayuzu:**
- `dmem_addr/wdata/rdata/we/be` -> `wb_adr_o/dat_o/dat_i/we_o/sel_o/stb_o/cyc_o/ack_i/err_i`

**MEM asamasi (yeni):**
- Byte-enable uretici: `funct3[1:0]` + `alu_result[1:0]` -> `mem_byte_en[3:0]`
- Store data alignment: SB/SH icin veriyi dogru byte pozisyonuna shift
- `wb_stb_o` ve `wb_cyc_o` sadece load/store islemleri icin aktif

**WB asamasi (yeni):**
- Load data extraction: `funct3_wb` + `load_byte_offset` ile byte/halfword secimi
- Sign-extension (LB/LH) ve zero-extension (LBU/LHU) destegi

### 5. SoC Top-Level (rv32_soc.v) Degisiklikleri

- Tum periferal baglantilari `wb_slave_wrapper` uzerinden
- DMEM ayri `wb_dmem` modulu olarak
- Bus error sinyali (`cpu_wb_err`) destegi
- Daha modular yapi

### 6. Dosya Yapisi

```
RV32_Prototip_2/
  rtl/
    rv32_core_pipelined.v  (DEGISTI - Wishbone + byte load/store)
    rv32_soc.v             (DEGISTI - Wishbone SoC)
    rv32_control.v         (AYNI)
    alu.v                  (AYNI)
    regfile.v              (AYNI)
    pc.v                   (AYNI)
    if_id_reg.v            (AYNI)
    id_ex_reg.v            (AYNI - funct3 zaten vardi)
    ex_mem_reg.v           (DEGISTI - funct3 eklendi)
    mem_wb_reg.v           (DEGISTI - funct3 eklendi)
    forwarding_unit.v      (AYNI)
    hazard_detection_unit.v(AYNI)
    periph/
      wb_interconnect.v    (YENI - Wishbone bus)
      wb_slave_wrapper.v   (YENI - periferal wrapper)
      wb_dmem.v            (YENI - Wishbone DMEM)
      uart.v               (AYNI)
      gpio.v               (AYNI)
      timer.v              (AYNI)
      spi.v                (AYNI)
  tests/
    tb_rv32_core.v         (DEGISTI - byte/halfword testleri eklendi)
  sim/
    run_sim.bat            (YENI)
    run_soc_sim.bat        (YENI)
  docs/
    DEGISIKLIK_RAPORU.md   (BU DOSYA)
  program.mem
```

### 7. Test Suite

| Test | Aciklama | Durum |
|------|----------|-------|
| Test 1 | Basic 5-Stage Pipeline | Ayni |
| Test 2 | EX-to-EX Forwarding | Ayni |
| Test 3 | MEM-to-EX Forwarding | Ayni |
| Test 4 | Load-Use Hazard (LW) | Ayni |
| Test 5 | Branch Flush | Ayni |
| Test 6 | Byte Load/Store (LB/LBU/SB) | YENI |
| Test 7 | Halfword Load/Store (LH/LHU/SH) | YENI |
| Test 8 | Complete Demo (All Features) | YENI |

### 8. Memory Map (Degismedi)

| Adres Araligi | Boyut | Aciklama |
|---------------|-------|----------|
| 0x0000_0000 - 0x0000_0FFF | 4KB | IMEM (Program ROM) |
| 0x2000_0000 - 0x2000_0FFF | 4KB | DMEM (Data RAM) |
| 0x4000_0000 - 0x4000_000F | 16B | UART |
| 0x4000_0010 - 0x4000_001F | 16B | GPIO |
| 0x4000_0020 - 0x4000_002F | 16B | TIMER |
| 0x4000_0030 - 0x4000_003F | 16B | SPI |
| 0x4000_0040 - 0x4000_004F | 16B | SIM_EXIT |
