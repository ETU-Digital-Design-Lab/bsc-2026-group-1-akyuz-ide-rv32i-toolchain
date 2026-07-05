`timescale 1ns / 1ps

// wb_interconnect.v
//
// Wishbone B4 Pipelined Bus Interconnect
// RV32I SoC icin gelismis bus sistemi.
//
// Ozellikler:
//   - Wishbone B4 protokolu (STB/CYC/ACK/ERR handshaking)
//   - Byte-enable (SEL) destegi (LB/LH/LW/SB/SH/SW)
//   - Bus hata yaniti (gecersiz adres icin ERR)
//   - Wait-state destegi (yavas periferaller icin)
//   - Pipelined bus islemleri
//
// Memory Map:
//   0x0000_0000 - 0x0000_0FFF  -> IMEM (4KB, sadece fetch - Harvard)
//   0x2000_0000 - 0x2000_0FFF  -> DMEM (4KB, load/store)
//   0x4000_0000 - 0x4000_000F  -> UART
//   0x4000_0010 - 0x4000_001F  -> GPIO
//   0x4000_0020 - 0x4000_002F  -> TIMER
//   0x4000_0030 - 0x4000_003F  -> SPI
//   0x4000_0040 - 0x4000_004F  -> SIM_EXIT (sadece simulasyon)
//
// Wishbone Sinyalleri:
//   Master -> Slave: ADR, DAT_O, WE, SEL, STB, CYC
//   Slave -> Master: DAT_I, ACK, ERR

module wb_interconnect #(
    parameter XLEN       = 32,
    parameter DMEM_WORDS = 1024   // 4KB
)(
    input  wire              clk,
    input  wire              rst_n,

    // ================================================================
    // CPU (Wishbone Master) Arayuzu
    // ================================================================
    input  wire [XLEN-1:0]   cpu_adr_i,     // Adres
    input  wire [31:0]       cpu_dat_i,     // Yazma verisi (CPU -> Bus)
    input  wire              cpu_we_i,      // Write Enable
    input  wire [3:0]        cpu_sel_i,     // Byte Select (byte-enable)
    input  wire              cpu_stb_i,     // Strobe (gecerli islem)
    input  wire              cpu_cyc_i,     // Bus cycle aktif
    output reg  [31:0]       cpu_dat_o,     // Okuma verisi (Bus -> CPU)
    output reg               cpu_ack_o,     // Acknowledge
    output reg               cpu_err_o,     // Bus hatasi (gecersiz adres)

    // ================================================================
    // DMEM Slave Arayuzu
    // ================================================================
    output wire [XLEN-1:0]   dmem_adr_o,
    output wire [31:0]       dmem_dat_o,
    output wire              dmem_we_o,
    output wire [3:0]        dmem_sel_o,
    output wire              dmem_stb_o,
    input  wire [31:0]       dmem_dat_i,
    input  wire              dmem_ack_i,

    // ================================================================
    // UART Slave Arayuzu
    // ================================================================
    output wire [3:0]        uart_adr_o,
    output wire [31:0]       uart_dat_o,
    output wire              uart_we_o,
    output wire              uart_stb_o,
    input  wire [31:0]       uart_dat_i,
    input  wire              uart_ack_i,

    // ================================================================
    // GPIO Slave Arayuzu
    // ================================================================
    output wire [3:0]        gpio_adr_o,
    output wire [31:0]       gpio_dat_o,
    output wire              gpio_we_o,
    output wire              gpio_stb_o,
    input  wire [31:0]       gpio_dat_i,
    input  wire              gpio_ack_i,

    // ================================================================
    // TIMER Slave Arayuzu
    // ================================================================
    output wire [3:0]        timer_adr_o,
    output wire [31:0]       timer_dat_o,
    output wire              timer_we_o,
    output wire              timer_stb_o,
    input  wire [31:0]       timer_dat_i,
    input  wire              timer_ack_i,

    // ================================================================
    // SPI Slave Arayuzu
    // ================================================================
    output wire [3:0]        spi_adr_o,
    output wire [31:0]       spi_dat_o,
    output wire              spi_we_o,
    output wire              spi_stb_o,
    input  wire [31:0]       spi_dat_i,
    input  wire              spi_ack_i,

    // ================================================================
    // SIM_EXIT (sadece simulasyon)
    // ================================================================
    output wire              sim_exit_we,
    output wire [31:0]       sim_exit_wdata
);

    // ================================================================
    // Adres Decode (Kombinasyonel)
    // ================================================================
    wire bus_active = cpu_stb_i & cpu_cyc_i;  // Gecerli bus islemi

    wire sel_dmem  = (cpu_adr_i[31:12] == 20'h20000);    // 0x2000_0xxx
    wire sel_uart  = (cpu_adr_i[31:4]  == 28'h4000000);  // 0x4000_000x
    wire sel_gpio  = (cpu_adr_i[31:4]  == 28'h4000001);  // 0x4000_001x
    wire sel_timer = (cpu_adr_i[31:4]  == 28'h4000002);  // 0x4000_002x
    wire sel_spi   = (cpu_adr_i[31:4]  == 28'h4000003);  // 0x4000_003x
    wire sel_sim   = (cpu_adr_i[31:4]  == 28'h4000004);  // 0x4000_004x

    // Hicbir slave secilmediyse -> bus hatasi
    wire sel_none  = ~(sel_dmem | sel_uart | sel_gpio | sel_timer | sel_spi | sel_sim);

    // ================================================================
    // Slave Strobe Sinyalleri
    // Her slave sadece kendi adresi secildiginde STB alir
    // ================================================================
    assign dmem_stb_o  = bus_active & sel_dmem;
    assign uart_stb_o  = bus_active & sel_uart;
    assign gpio_stb_o  = bus_active & sel_gpio;
    assign timer_stb_o = bus_active & sel_timer;
    assign spi_stb_o   = bus_active & sel_spi;

    // ================================================================
    // DMEM Baglantilari
    // ================================================================
    assign dmem_adr_o = cpu_adr_i;
    assign dmem_dat_o = cpu_dat_i;
    assign dmem_we_o  = cpu_we_i & sel_dmem;
    assign dmem_sel_o = cpu_sel_i;

    // ================================================================
    // UART Baglantilari
    // ================================================================
    assign uart_adr_o = cpu_adr_i[3:0];
    assign uart_dat_o = cpu_dat_i;
    assign uart_we_o  = cpu_we_i & sel_uart;

    // ================================================================
    // GPIO Baglantilari
    // ================================================================
    assign gpio_adr_o = cpu_adr_i[3:0];
    assign gpio_dat_o = cpu_dat_i;
    assign gpio_we_o  = cpu_we_i & sel_gpio;

    // ================================================================
    // TIMER Baglantilari
    // ================================================================
    assign timer_adr_o = cpu_adr_i[3:0];
    assign timer_dat_o = cpu_dat_i;
    assign timer_we_o  = cpu_we_i & sel_timer;

    // ================================================================
    // SPI Baglantilari
    // ================================================================
    assign spi_adr_o = cpu_adr_i[3:0];
    assign spi_dat_o = cpu_dat_i;
    assign spi_we_o  = cpu_we_i & sel_spi;

    // ================================================================
    // SIM_EXIT
    // ================================================================
    assign sim_exit_we    = cpu_we_i & bus_active & sel_sim;
    assign sim_exit_wdata = cpu_dat_i;

    // ================================================================
    // Read Data Mux & ACK/ERR (Kombinasyonel)
    // ================================================================
    // Wishbone B4: ACK 1 cycle icinde donmeli (senkron periferaller icin)
    // Yavas periferaller kendi ACK'lerini geciktirebilir (wait-state)
    always @(*) begin
        cpu_dat_o = 32'h0000_0000;
        cpu_ack_o = 1'b0;
        cpu_err_o = 1'b0;

        if (bus_active) begin
            if (sel_dmem) begin
                cpu_dat_o = dmem_dat_i;
                cpu_ack_o = dmem_ack_i;
            end
            else if (sel_uart) begin
                cpu_dat_o = uart_dat_i;
                cpu_ack_o = uart_ack_i;
            end
            else if (sel_gpio) begin
                cpu_dat_o = gpio_dat_i;
                cpu_ack_o = gpio_ack_i;
            end
            else if (sel_timer) begin
                cpu_dat_o = timer_dat_i;
                cpu_ack_o = timer_ack_i;
            end
            else if (sel_spi) begin
                cpu_dat_o = spi_dat_i;
                cpu_ack_o = spi_ack_i;
            end
            else if (sel_sim) begin
                // SIM_EXIT: yazma-only, okuma 0 doner
                cpu_dat_o = 32'h0;
                cpu_ack_o = 1'b1;  // Aninda ACK
            end
            else begin
                // Gecersiz adres -> BUS ERROR
                cpu_dat_o = 32'hDEAD_BEEF;
                cpu_err_o = 1'b1;
                cpu_ack_o = 1'b0;
            end
        end
    end

endmodule
