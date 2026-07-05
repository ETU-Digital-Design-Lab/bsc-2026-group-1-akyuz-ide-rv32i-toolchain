`timescale 1ns / 1ps

// rv32_soc.v - Prototip 2
//
// RV32I SoC Top-Level Modulu (Wishbone B4 Bus)
//
// Prototip-1'den Farklar:
//   1. Wishbone B4 bus protokolu (STB/CYC/ACK/ERR handshaking)
//   2. Byte/Halfword Load/Store destegi (LB/LBU/LH/LHU/SB/SH/SW)
//   3. Bus hata yaniti (gecersiz adres icin ERR)
//   4. Wishbone slave wrapper ile periferal entegrasyonu
//   5. DMEM ayri Wishbone slave modulu (wb_dmem.v)
//
// Bilesenler:
//   - rv32_core_pipelined : 5-asamali pipeline islemci (Wishbone master)
//   - wb_interconnect     : Wishbone B4 bus cozmek
//   - wb_dmem             : 4KB data RAM (Wishbone slave)
//   - IMEM (ROM)          : 4KB program bellegi (Harvard, dogrudan)
//   - uart                : UART TX/RX (Wishbone slave via wrapper)
//   - gpio                : 32-pin GPIO (Wishbone slave via wrapper)
//   - timer               : 32-bit Timer/Counter (Wishbone slave via wrapper)
//   - spi                 : SPI Master (Wishbone slave via wrapper)
//
// Memory Map:
//   0x0000_0000 - 0x0000_0FFF  -> IMEM (4KB, sadece fetch - Harvard)
//   0x2000_0000 - 0x2000_0FFF  -> DMEM (4KB, load/store)
//   0x4000_0000 - 0x4000_000F  -> UART
//   0x4000_0010 - 0x4000_001F  -> GPIO
//   0x4000_0020 - 0x4000_002F  -> TIMER
//   0x4000_0030 - 0x4000_003F  -> SPI
//   0x4000_0040 - 0x4000_004F  -> SIM_EXIT (sadece simulasyon)

module rv32_soc #(
    parameter XLEN       = 32,
    parameter IMEM_WORDS = 1024,   // 4KB
    parameter DMEM_WORDS = 1024,   // 4KB
    parameter CLK_FREQ   = 50_000_000,
    parameter BAUD_RATE  = 115_200,
    parameter GPIO_PINS  = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // UART
    output wire                  uart_tx,
    input  wire                  uart_rx,

    // GPIO
    inout  wire [GPIO_PINS-1:0]  gpio,

    // SPI
    output wire                  spi_sck,
    output wire                  spi_mosi,
    input  wire                  spi_miso,
    output wire                  spi_cs_n,

    // Debug
    output wire [7:0]            dbg_out,

    // Interrupt (ileride kullanim icin)
    output wire                  irq_uart_tx,
    output wire                  irq_uart_rx,
    output wire                  irq_gpio,
    output wire                  irq_timer,
    output wire                  irq_spi
);

    // ============================================================
    // CPU <-> IMEM Arayuzu (Harvard - dogrudan)
    // ============================================================
    wire [XLEN-1:0]  imem_addr;
    wire [31:0]      imem_rdata;

    // IMEM (Program ROM)
    reg [31:0] imem [0:IMEM_WORDS-1];

    // IMEM init: program.mem dosyasindan yuklenir
    integer j;
    initial begin
        for (j = 0; j < IMEM_WORDS; j = j + 1)
            imem[j] = 32'h0000_0013;  // NOP
        $readmemh("program.mem", imem);
    end

    wire [XLEN-1:0] imem_word_idx = imem_addr >> 2;
    assign imem_rdata = (imem_word_idx < IMEM_WORDS) ? imem[imem_word_idx] : 32'h0000_0013;

    // ============================================================
    // CPU <-> Wishbone Bus Arayuzu
    // ============================================================
    wire [XLEN-1:0]  cpu_wb_adr;
    wire [31:0]      cpu_wb_dat_w;   // CPU -> Bus
    wire [31:0]      cpu_wb_dat_r;   // Bus -> CPU
    wire             cpu_wb_we;
    wire [3:0]       cpu_wb_sel;
    wire             cpu_wb_stb;
    wire             cpu_wb_cyc;
    wire             cpu_wb_ack;
    wire             cpu_wb_err;

    // ============================================================
    // RV32 Pipeline Core (Wishbone Master)
    // ============================================================
    rv32_core_pipelined #(
        .XLEN(XLEN)
    ) u_core (
        .clk        (clk),
        .rst_n      (rst_n),
        // IMEM
        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),
        // Wishbone Master
        .wb_adr_o   (cpu_wb_adr),
        .wb_dat_o   (cpu_wb_dat_w),
        .wb_we_o    (cpu_wb_we),
        .wb_sel_o   (cpu_wb_sel),
        .wb_stb_o   (cpu_wb_stb),
        .wb_cyc_o   (cpu_wb_cyc),
        .wb_dat_i   (cpu_wb_dat_r),
        .wb_ack_i   (cpu_wb_ack),
        .wb_err_i   (cpu_wb_err),
        // Debug
        .dbg_out    (dbg_out)
    );

    // ============================================================
    // Wishbone Bus Sinyalleri
    // ============================================================
    // DMEM
    wire [XLEN-1:0]  dmem_wb_adr;
    wire [31:0]       dmem_wb_dat_w;
    wire              dmem_wb_we;
    wire [3:0]        dmem_wb_sel;
    wire              dmem_wb_stb;
    wire [31:0]       dmem_wb_dat_r;
    wire              dmem_wb_ack;

    // UART
    wire [3:0]        uart_wb_adr;
    wire [31:0]       uart_wb_dat_w;
    wire              uart_wb_we;
    wire              uart_wb_stb;
    wire [31:0]       uart_wb_dat_r;
    wire              uart_wb_ack;

    // GPIO
    wire [3:0]        gpio_wb_adr;
    wire [31:0]       gpio_wb_dat_w;
    wire              gpio_wb_we;
    wire              gpio_wb_stb;
    wire [31:0]       gpio_wb_dat_r;
    wire              gpio_wb_ack;

    // TIMER
    wire [3:0]        timer_wb_adr;
    wire [31:0]       timer_wb_dat_w;
    wire              timer_wb_we;
    wire              timer_wb_stb;
    wire [31:0]       timer_wb_dat_r;
    wire              timer_wb_ack;

    // SPI
    wire [3:0]        spi_wb_adr;
    wire [31:0]       spi_wb_dat_w;
    wire              spi_wb_we;
    wire              spi_wb_stb;
    wire [31:0]       spi_wb_dat_r;
    wire              spi_wb_ack;

    // SIM_EXIT
    wire              sim_exit_we;
    wire [31:0]       sim_exit_wdata;

    // ============================================================
    // Wishbone B4 Bus Interconnect
    // ============================================================
    wb_interconnect #(
        .XLEN      (XLEN),
        .DMEM_WORDS(DMEM_WORDS)
    ) u_bus (
        .clk          (clk),
        .rst_n        (rst_n),
        // CPU Master
        .cpu_adr_i    (cpu_wb_adr),
        .cpu_dat_i    (cpu_wb_dat_w),
        .cpu_we_i     (cpu_wb_we),
        .cpu_sel_i    (cpu_wb_sel),
        .cpu_stb_i    (cpu_wb_stb),
        .cpu_cyc_i    (cpu_wb_cyc),
        .cpu_dat_o    (cpu_wb_dat_r),
        .cpu_ack_o    (cpu_wb_ack),
        .cpu_err_o    (cpu_wb_err),
        // DMEM Slave
        .dmem_adr_o   (dmem_wb_adr),
        .dmem_dat_o   (dmem_wb_dat_w),
        .dmem_we_o    (dmem_wb_we),
        .dmem_sel_o   (dmem_wb_sel),
        .dmem_stb_o   (dmem_wb_stb),
        .dmem_dat_i   (dmem_wb_dat_r),
        .dmem_ack_i   (dmem_wb_ack),
        // UART Slave
        .uart_adr_o   (uart_wb_adr),
        .uart_dat_o   (uart_wb_dat_w),
        .uart_we_o    (uart_wb_we),
        .uart_stb_o   (uart_wb_stb),
        .uart_dat_i   (uart_wb_dat_r),
        .uart_ack_i   (uart_wb_ack),
        // GPIO Slave
        .gpio_adr_o   (gpio_wb_adr),
        .gpio_dat_o   (gpio_wb_dat_w),
        .gpio_we_o    (gpio_wb_we),
        .gpio_stb_o   (gpio_wb_stb),
        .gpio_dat_i   (gpio_wb_dat_r),
        .gpio_ack_i   (gpio_wb_ack),
        // TIMER Slave
        .timer_adr_o  (timer_wb_adr),
        .timer_dat_o  (timer_wb_dat_w),
        .timer_we_o   (timer_wb_we),
        .timer_stb_o  (timer_wb_stb),
        .timer_dat_i  (timer_wb_dat_r),
        .timer_ack_i  (timer_wb_ack),
        // SPI Slave
        .spi_adr_o    (spi_wb_adr),
        .spi_dat_o    (spi_wb_dat_w),
        .spi_we_o     (spi_wb_we),
        .spi_stb_o    (spi_wb_stb),
        .spi_dat_i    (spi_wb_dat_r),
        .spi_ack_i    (spi_wb_ack),
        // SIM_EXIT
        .sim_exit_we  (sim_exit_we),
        .sim_exit_wdata(sim_exit_wdata)
    );

    // ============================================================
    // DMEM (Wishbone Slave - Byte-enable destekli)
    // ============================================================
    wb_dmem #(
        .XLEN      (XLEN),
        .DMEM_WORDS(DMEM_WORDS)
    ) u_dmem (
        .clk       (clk),
        .rst_n     (rst_n),
        .wb_adr_i  (dmem_wb_adr),
        .wb_dat_i  (dmem_wb_dat_w),
        .wb_we_i   (dmem_wb_we),
        .wb_sel_i  (dmem_wb_sel),
        .wb_stb_i  (dmem_wb_stb),
        .wb_dat_o  (dmem_wb_dat_r),
        .wb_ack_o  (dmem_wb_ack)
    );

    // ============================================================
    // UART Peripheral (Wishbone Slave via Wrapper)
    // ============================================================
    wire [3:0]  uart_periph_addr;
    wire [31:0] uart_periph_wdata;
    wire        uart_periph_we;
    wire [31:0] uart_periph_rdata;

    wb_slave_wrapper #(
        .ADDR_WIDTH(4)
    ) u_uart_wb (
        .clk          (clk),
        .rst_n        (rst_n),
        .wb_adr_i     (uart_wb_adr),
        .wb_dat_i     (uart_wb_dat_w),
        .wb_we_i      (uart_wb_we),
        .wb_stb_i     (uart_wb_stb),
        .wb_dat_o     (uart_wb_dat_r),
        .wb_ack_o     (uart_wb_ack),
        .periph_addr  (uart_periph_addr),
        .periph_wdata (uart_periph_wdata),
        .periph_we    (uart_periph_we),
        .periph_rdata (uart_periph_rdata)
    );

    uart #(
        .XLEN       (XLEN),
        .CLK_FREQ   (CLK_FREQ),
        .BAUD_RATE  (BAUD_RATE)
    ) u_uart (
        .clk     (clk),
        .rst_n   (rst_n),
        .addr    (uart_periph_addr),
        .wdata   (uart_periph_wdata),
        .we      (uart_periph_we),
        .rdata   (uart_periph_rdata),
        .uart_tx (uart_tx),
        .uart_rx (uart_rx),
        .tx_irq  (irq_uart_tx),
        .rx_irq  (irq_uart_rx)
    );

    // ============================================================
    // GPIO Peripheral (Wishbone Slave via Wrapper)
    // ============================================================
    wire [3:0]  gpio_periph_addr;
    wire [31:0] gpio_periph_wdata;
    wire        gpio_periph_we;
    wire [31:0] gpio_periph_rdata;

    wb_slave_wrapper #(
        .ADDR_WIDTH(4)
    ) u_gpio_wb (
        .clk          (clk),
        .rst_n        (rst_n),
        .wb_adr_i     (gpio_wb_adr),
        .wb_dat_i     (gpio_wb_dat_w),
        .wb_we_i      (gpio_wb_we),
        .wb_stb_i     (gpio_wb_stb),
        .wb_dat_o     (gpio_wb_dat_r),
        .wb_ack_o     (gpio_wb_ack),
        .periph_addr  (gpio_periph_addr),
        .periph_wdata (gpio_periph_wdata),
        .periph_we    (gpio_periph_we),
        .periph_rdata (gpio_periph_rdata)
    );

    gpio #(
        .XLEN  (XLEN),
        .N_PINS(GPIO_PINS)
    ) u_gpio (
        .clk      (clk),
        .rst_n    (rst_n),
        .addr     (gpio_periph_addr),
        .wdata    (gpio_periph_wdata),
        .we       (gpio_periph_we),
        .rdata    (gpio_periph_rdata),
        .gpio_pin (gpio),
        .irq      (irq_gpio)
    );

    // ============================================================
    // TIMER Peripheral (Wishbone Slave via Wrapper)
    // ============================================================
    wire [3:0]  timer_periph_addr;
    wire [31:0] timer_periph_wdata;
    wire        timer_periph_we;
    wire [31:0] timer_periph_rdata;

    wb_slave_wrapper #(
        .ADDR_WIDTH(4)
    ) u_timer_wb (
        .clk          (clk),
        .rst_n        (rst_n),
        .wb_adr_i     (timer_wb_adr),
        .wb_dat_i     (timer_wb_dat_w),
        .wb_we_i      (timer_wb_we),
        .wb_stb_i     (timer_wb_stb),
        .wb_dat_o     (timer_wb_dat_r),
        .wb_ack_o     (timer_wb_ack),
        .periph_addr  (timer_periph_addr),
        .periph_wdata (timer_periph_wdata),
        .periph_we    (timer_periph_we),
        .periph_rdata (timer_periph_rdata)
    );

    timer #(
        .XLEN(XLEN)
    ) u_timer (
        .clk   (clk),
        .rst_n (rst_n),
        .addr  (timer_periph_addr),
        .wdata (timer_periph_wdata),
        .we    (timer_periph_we),
        .rdata (timer_periph_rdata),
        .irq   (irq_timer)
    );

    // ============================================================
    // SPI Peripheral (Wishbone Slave via Wrapper)
    // ============================================================
    wire [3:0]  spi_periph_addr;
    wire [31:0] spi_periph_wdata;
    wire        spi_periph_we;
    wire [31:0] spi_periph_rdata;

    wb_slave_wrapper #(
        .ADDR_WIDTH(4)
    ) u_spi_wb (
        .clk          (clk),
        .rst_n        (rst_n),
        .wb_adr_i     (spi_wb_adr),
        .wb_dat_i     (spi_wb_dat_w),
        .wb_we_i      (spi_wb_we),
        .wb_stb_i     (spi_wb_stb),
        .wb_dat_o     (spi_wb_dat_r),
        .wb_ack_o     (spi_wb_ack),
        .periph_addr  (spi_periph_addr),
        .periph_wdata (spi_periph_wdata),
        .periph_we    (spi_periph_we),
        .periph_rdata (spi_periph_rdata)
    );

    spi #(
        .XLEN(XLEN)
    ) u_spi (
        .clk     (clk),
        .rst_n   (rst_n),
        .addr    (spi_periph_addr),
        .wdata   (spi_periph_wdata),
        .we      (spi_periph_we),
        .rdata   (spi_periph_rdata),
        .spi_sck (spi_sck),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_cs_n(spi_cs_n),
        .irq     (irq_spi)
    );

    // ============================================================
    // SIM_EXIT hook (sadece simulasyonda anlamli)
    // ============================================================
    // sim_exit_we ve sim_exit_wdata testbench tarafindan izlenir

endmodule
