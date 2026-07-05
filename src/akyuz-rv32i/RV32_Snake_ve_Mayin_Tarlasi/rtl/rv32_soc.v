// rv32_soc.v — RV32I SoC Wrapper (Nexys 4 / Artix-7)
//
// Wraps rv32_core with an address-decoded memory subsystem:
//
// Memory map:
//   0x0000_0000 – 0x0000_0FFF   Instruction BRAM (4 KB, inside rv32_core)
//   0x0001_0000 – 0x0001_0FFF   Data BRAM (4 KB, 1024 × 32-bit words)
//   0x0002_0000                 UART TX data register  (W: byte → send)
//   0x0002_0004                 UART TX status register (R: bit0 = tx_ready)
//   0x0002_0008                 LED register            (RW: 16-bit)
//   0x0002_000C                 Switch register         (R:  16-bit)
//   0x0002_0010                 Cycle counter           (R:  32-bit)
//   0x0003_0000 – 0x0003_257F   VGA char buffer (W: bits[7:0]=ASCII, [11:8]=fg, [15:12]=bg)
//
// Store (SW/SH/SB) to 0x0002_0000 sends the LSByte via UART.
// Load  (LW)       from 0x0002_0004 returns {31'd0, tx_ready}.
// Store (SW)       to  0x0002_0008 updates LED output register.
// Load  (LW)       from 0x0002_000C returns {16'd0, sw_in}.
// Store (SW)       to  0x0003_0000+(row*80+col)*4 writes a VGA character cell.
//
// The core runs at 50 MHz; UART baud = 115200 (CLK_DIV = 434).

module rv32_soc #(
    parameter XLEN       = 32,
    parameter IMEM_DEPTH = 2048,
    parameter DMEM_DEPTH = 1024,
    parameter IMEM_FILE  = "",
    parameter UART_DIV   = 434    // 50 MHz / 115200
)(
    input  wire        clk,
    input  wire        rst_n,

    // Peripheral I/O
    input  wire [15:0] sw,         // switches (mapped to 0x0002_000C)
    input  wire [4:0]  btn,        // buttons  (mapped to 0x0002_0014)
    output reg  [15:0] led,        // LEDs     (mapped to 0x0002_0008)
    output wire        uart_tx,    // UART TX line
    input  wire        uart_rx,    // UART RX line

    // Debug observation
    output wire [31:0] debug_pc,
    output wire [31:0] debug_instr,
    output wire [31:0] debug_alu,

    // VGA char buffer write port (to char_buffer port A in fpga_top)
    output wire        vga_char_we,
    output wire [11:0] vga_char_addr,
    output wire [15:0] vga_char_wdata,
    
    // Bootloader status
    output wire        boot_loading,

    // Kamera goruntusu etkin (yazilim kontrollu, 0x0002_0018 bit0)
    output reg         cam_en
);

    // =========================================================================
    // Core (EXT_DMEM=1 — all memory accesses go through external bus)
    // =========================================================================
    wire [XLEN-1:0] dmem_addr;
    wire [XLEN-1:0] dmem_wdata;
    wire            dmem_we;
    wire [2:0]      dmem_funct3;
    wire [XLEN-1:0] dmem_rdata;

    // Bootloader signals
    wire        imem_we;
    wire [31:0] imem_waddr;
    wire [31:0] imem_wdata;
    wire        cpu_reset_n;
    wire        core_rst_n = rst_n & cpu_reset_n;

    wire [31:0] imem_drdata;

    rv32_core #(
        .XLEN       (XLEN),
        .IMEM_DEPTH (IMEM_DEPTH),
        .DMEM_DEPTH (DMEM_DEPTH),
        .IMEM_FILE  (IMEM_FILE),
        .DMEM_FILE  (""),
        .EXT_DMEM   (1)
    ) u_core (
        .clk              (clk),
        .rst_n            (core_rst_n),
        .imem_we          (imem_we),
        .imem_waddr       (imem_waddr),
        .imem_wdata       (imem_wdata),
        .dmem_addr        (dmem_addr),
        .dmem_wdata       (dmem_wdata),
        .dmem_we          (dmem_we),
        .dmem_funct3      (dmem_funct3),
        .dmem_rdata_ext   (dmem_rdata),
        .imem_drdata      (imem_drdata),
        .debug_pc         (debug_pc),
        .debug_instr      (debug_instr),
        .debug_alu_result (debug_alu)
    );

    // =========================================================================
    // Address decoder
    // =========================================================================
    // Region select (combinational)
    wire sel_dmem   = (dmem_addr[31:16] == 16'h0001);   // 0x0001_xxxx  (DMEM at 0x00010000)
    wire sel_periph = (dmem_addr[31:16] == 16'h0002);   // 0x0002_xxxx
    wire sel_vga    = (dmem_addr[31:16] == 16'h0003);   // 0x0003_xxxx
    wire sel_imem_d = (dmem_addr[31:16] == 16'h0000);   // 0x0000_xxxx
    wire [XLEN-1:0] imem_d_rdata = imem_drdata; // IMEM data read (for .rodata)

    // VGA char buffer write outputs (char_buffer port A driven from fpga_top)
    assign vga_char_we    = dmem_we & sel_vga;
    assign vga_char_addr  = dmem_addr[13:2];   // word-addressed → 12-bit cell index
    assign vga_char_wdata = dmem_wdata[15:0];  // bits[7:0]=ASCII, [11:8]=fg, [15:12]=bg

    // =========================================================================
    // Data BRAM (1024 × 32-bit, synchronous write / asynchronous read)
    // =========================================================================
    wire [XLEN-1:0] dmem_rdata_bram;

    dmem #(
        .XLEN    (XLEN),
        .DEPTH   (DMEM_DEPTH),
        .MEM_FILE("")
    ) u_dmem (
        .clk    (clk),
        .we     (dmem_we & sel_dmem),
        .funct3 (dmem_funct3),
        .addr   ({20'd0, dmem_addr[11:0]}),  // strip base 0x00010000, keep 12-bit byte offset
        .wdata  (dmem_wdata),
        .rdata  (dmem_rdata_bram)
    );

    // =========================================================================
    // UART TX peripheral
    // =========================================================================
    wire       uart_tx_ready;
    reg        uart_tx_valid;
    reg  [7:0] uart_tx_data;

    uart_tx #(.CLK_DIV(UART_DIV)) u_uart (
        .clk     (clk),
        .rst_n   (rst_n),
        .tx_data (uart_tx_data),
        .tx_valid(uart_tx_valid),
        .tx_ready(uart_tx_ready),
        .tx_out  (uart_tx)
    );

    // Write to 0x0002_0000: latch byte and pulse tx_valid for one cycle
    reg uart_write_d;  // previous cycle write flag to detect edge

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_tx_valid <= 1'b0;
            uart_tx_data  <= 8'd0;
            uart_write_d  <= 1'b0;
        end else begin
            uart_tx_valid <= 1'b0;  // default: deassert
            uart_write_d  <= dmem_we & sel_periph & (dmem_addr[7:0] == 8'h00);
            if (dmem_we & sel_periph & (dmem_addr[7:0] == 8'h00) & ~uart_write_d) begin
                if (uart_tx_ready) begin
                    uart_tx_data  <= dmem_wdata[7:0];
                    uart_tx_valid <= 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // LED register  (0x0002_0008)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            led <= 16'd0;
        else if (dmem_we & sel_periph & (dmem_addr[7:0] == 8'h08))
            led <= dmem_wdata[15:0];
    end

    // =========================================================================
    // Kamera enable register (0x0002_0018) — yazilim kamera goruntusunu acar
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cam_en <= 1'b0;
        else if (dmem_we & sel_periph & (dmem_addr[7:0] == 8'h18))
            cam_en <= dmem_wdata[0];
    end

    // =========================================================================
    // Cycle counter (0x0002_0010) — Counts cycles since reset
    // =========================================================================
    reg [31:0] cycle_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycle_cnt <= 32'd0;
        else        cycle_cnt <= cycle_cnt + 32'd1;
    end

    // =========================================================================
    // Read-data mux
    // =========================================================================
    reg [XLEN-1:0] periph_rdata;
    always @(*) begin
        case (dmem_addr[7:0])
            8'h04:   periph_rdata = {31'd0, uart_tx_ready};  // UART status
            8'h08:   periph_rdata = {16'd0, led};             // LED register
            8'h0C:   periph_rdata = {16'd0, sw};              // Switch register
            8'h10:   periph_rdata = cycle_cnt;              // Cycle counter
            8'h14:   periph_rdata = {27'd0, btn};             // Button register
            8'h18:   periph_rdata = {31'd0, cam_en};          // Kamera enable
            default: periph_rdata = {XLEN{1'b0}};
        endcase
    end

    // =========================================================================
    // Read-data mux (Peripheral vs DMEM vs IMEM_D)
    // =========================================================================
    assign dmem_rdata = sel_periph ? periph_rdata : 
                        sel_imem_d ? imem_d_rdata :
                        dmem_rdata_bram;

    // =========================================================================
    // UART RX & Hardware Bootloader
    // =========================================================================
    wire [7:0] rx_data;
    wire       rx_valid;

    uart_rx #(.CLK_DIV(UART_DIV)) u_uart_rx (
        .clk      (clk),
        .rst_n    (rst_n),
        .rx_in    (uart_rx),
        .rx_data  (rx_data),
        .rx_valid (rx_valid)
    );

    hw_bootloader u_hw_bootloader (
        .clk         (clk),
        .rst_n       (rst_n),
        .rx_data     (rx_data),
        .rx_valid    (rx_valid),
        .imem_we     (imem_we),
        .imem_waddr  (imem_waddr),
        .imem_wdata  (imem_wdata),
        .cpu_reset_n (cpu_reset_n),
        .is_loading  (boot_loading)
    );

endmodule
