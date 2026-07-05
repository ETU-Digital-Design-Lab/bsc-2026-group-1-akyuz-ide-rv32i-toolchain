`timescale 1ns / 1ps

// gpio.v
//
// Genel Amaçlı I/O (GPIO) çevre birimi.
// 32 pin, her biri bağımsız yön kontrolü.
//
// Register Map (byte offset):
//   0x0  (R/W) DIR   [31:0] - 0=giriş, 1=çıkış
//   0x4  (R/W) OUT   [31:0] - çıkış değeri (DIR=1 olan pinler)
//   0x8  (R)   IN    [31:0] - giriş değeri (tüm pinler, senkronize)
//   0xC  (R/W) IEN   [31:0] - interrupt enable (0=devre dışı, 1=etkin)
//
// Interrupt: giriş pini değiştiğinde (rising/falling edge) irq çıkışı 1 pulse verir.

module gpio #(
    parameter XLEN    = 32,
    parameter N_PINS  = 32
)(
    input  wire              clk,
    input  wire              rst_n,

    // Bus Interface
    input  wire [3:0]        addr,
    input  wire [31:0]       wdata,
    input  wire              we,
    output reg  [31:0]       rdata,

    // GPIO Pinleri
    inout  wire [N_PINS-1:0] gpio_pin,

    // Interrupt
    output wire              irq
);

    // ============================================================
    // Register Adresleri
    // ============================================================
    localparam REG_DIR = 2'd0;  // 0x0
    localparam REG_OUT = 2'd1;  // 0x4
    localparam REG_IN  = 2'd2;  // 0x8
    localparam REG_IEN = 2'd3;  // 0xC

    wire [1:0] reg_sel = addr[3:2];

    // ============================================================
    // Register'lar
    // ============================================================
    reg [N_PINS-1:0] dir_reg;   // 1=output, 0=input
    reg [N_PINS-1:0] out_reg;
    reg [N_PINS-1:0] ien_reg;

    // Giriş senkronizasyonu (2-flop)
    reg [N_PINS-1:0] in_sync0, in_sync1, in_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_sync0 <= {N_PINS{1'b0}};
            in_sync1 <= {N_PINS{1'b0}};
            in_prev  <= {N_PINS{1'b0}};
        end else begin
            in_sync0 <= gpio_pin;
            in_sync1 <= in_sync0;
            in_prev  <= in_sync1;
        end
    end

    // ============================================================
    // Register Yazma
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dir_reg <= {N_PINS{1'b0}};  // Hepsi giriş
            out_reg <= {N_PINS{1'b0}};
            ien_reg <= {N_PINS{1'b0}};
        end else if (we) begin
            case (reg_sel)
                REG_DIR: dir_reg <= wdata[N_PINS-1:0];
                REG_OUT: out_reg <= wdata[N_PINS-1:0];
                REG_IEN: ien_reg <= wdata[N_PINS-1:0];
                default: ;
            endcase
        end
    end

    // ============================================================
    // GPIO Pin Sürme (tristate)
    // ============================================================
    genvar i;
    generate
        for (i = 0; i < N_PINS; i = i + 1) begin : gpio_pins
            assign gpio_pin[i] = dir_reg[i] ? out_reg[i] : 1'bz;
        end
    endgenerate

    // ============================================================
    // Register Okuma
    // ============================================================
    always @(*) begin
        case (reg_sel)
            REG_DIR: rdata = {{(32-N_PINS){1'b0}}, dir_reg};
            REG_OUT: rdata = {{(32-N_PINS){1'b0}}, out_reg};
            REG_IN:  rdata = {{(32-N_PINS){1'b0}}, in_sync1};
            REG_IEN: rdata = {{(32-N_PINS){1'b0}}, ien_reg};
            default: rdata = 32'h0;
        endcase
    end

    // ============================================================
    // Interrupt (herhangi bir giriş pini değişince)
    // ============================================================
    wire [N_PINS-1:0] edge_detect = (in_sync1 ^ in_prev) & ~dir_reg & ien_reg;
    assign irq = |edge_detect;

endmodule
