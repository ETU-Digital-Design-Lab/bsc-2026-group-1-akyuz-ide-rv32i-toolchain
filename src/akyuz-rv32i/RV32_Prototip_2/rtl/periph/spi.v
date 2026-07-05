`timescale 1ns / 1ps

// spi.v
//
// SPI Master çevre birimi.
// Mode 0 (CPOL=0, CPHA=0) - SCK normalde düşük, veri yükselen kenarda örneklenir.
// 8-bit transfer, MSB first.
//
// Register Map (byte offset):
//   0x0  (R/W) CTRL    [7:0]  - [0]=EN, [1]=CPOL, [2]=CPHA, [3]=CS_AUTO
//   0x4  (R/W) DATA    [7:0]  - Yazınca transfer başlar, okununca alınan veri
//   0x8  (R)   STATUS  [7:0]  - [0]=BUSY, [1]=TX_DONE
//   0xC  (R/W) CLK_DIV [15:0] - SCK = clk / (2*(CLK_DIV+1))
//
// CS (Chip Select): CS_AUTO=1 ise transfer boyunca otomatik düşürülür.
//                   CS_AUTO=0 ise CPU manuel kontrol eder (CTRL[4] = CS_VAL).

module spi #(
    parameter XLEN = 32
)(
    input  wire        clk,
    input  wire        rst_n,

    // Bus Interface
    input  wire [3:0]  addr,
    input  wire [31:0] wdata,
    input  wire        we,
    output reg  [31:0] rdata,

    // SPI Pinleri
    output wire        spi_sck,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output reg         spi_cs_n,    // Active-low chip select

    // Interrupt
    output wire        irq          // Transfer tamamlandı
);

    // ============================================================
    // Register Adresleri
    // ============================================================
    localparam REG_CTRL    = 2'd0;  // 0x0
    localparam REG_DATA    = 2'd1;  // 0x4
    localparam REG_STATUS  = 2'd2;  // 0x8
    localparam REG_CLK_DIV = 2'd3;  // 0xC

    wire [1:0] reg_sel = addr[3:2];

    // ============================================================
    // Register'lar
    // ============================================================
    reg         spi_en;
    reg         cpol;
    reg         cpha;
    reg         cs_auto;
    reg         cs_manual_val;   // CS_AUTO=0 iken CPU kontrol
    reg [15:0]  clk_div_reg;
    reg [7:0]   rx_data_reg;
    reg         tx_done;
    reg         spi_busy;

    // ============================================================
    // SCK Üreteci
    // ============================================================
    reg [15:0]  sck_cnt;
    reg         sck_reg;
    wire        sck_tick = (sck_cnt == clk_div_reg);  // yarı periyot

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sck_cnt <= 16'd0;
        else if (!spi_busy)
            sck_cnt <= 16'd0;
        else if (sck_tick)
            sck_cnt <= 16'd0;
        else
            sck_cnt <= sck_cnt + 1'd1;
    end

    assign spi_sck = sck_reg ^ cpol;  // CPOL uygulaması

    // ============================================================
    // Shift Register & Transfer State Machine
    // ============================================================
    reg [7:0]  tx_shift;
    reg [7:0]  rx_shift;
    reg [3:0]  bit_cnt;      // 0..15 (her bit için 2 tick: sample + shift)
    reg        phase;         // 0=ilk kenar, 1=ikinci kenar

    reg irq_pulse;
    assign irq = irq_pulse;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_busy     <= 1'b0;
            sck_reg      <= 1'b0;
            tx_shift     <= 8'h00;
            rx_shift     <= 8'h00;
            rx_data_reg  <= 8'h00;
            bit_cnt      <= 4'd0;
            phase        <= 1'b0;
            tx_done      <= 1'b0;
            irq_pulse    <= 1'b0;
            spi_cs_n     <= 1'b1;
        end else begin
            irq_pulse <= 1'b0;
            tx_done   <= 1'b0;

            if (!spi_busy) begin
                sck_reg  <= 1'b0;
                bit_cnt  <= 4'd0;
                phase    <= 1'b0;

                // Transfer başlatma: DATA register'a yazılınca
                if (we && reg_sel == REG_DATA && spi_en) begin
                    tx_shift  <= wdata[7:0];
                    spi_busy  <= 1'b1;
                    if (cs_auto) spi_cs_n <= 1'b0;  // CS aşağı çek
                end else begin
                    // Manuel CS kontrolü
                    if (!cs_auto)
                        spi_cs_n <= ~cs_manual_val;
                end
            end else begin
                // Transfer devam
                if (sck_tick) begin
                    if (!phase) begin
                        // CPHA=0: veri yükselen kenarda örneklenir (SCK 0->1)
                        // CPHA=1: veri düşen kenarda örneklenir  (SCK 1->0)
                        sck_reg <= 1'b1;
                        if (!cpha) begin
                            // Örnekle (CPHA=0)
                            rx_shift <= {rx_shift[6:0], spi_miso};
                        end else begin
                            // Shift (CPHA=1)
                            tx_shift <= {tx_shift[6:0], 1'b0};
                        end
                        phase <= 1'b1;
                    end else begin
                        sck_reg <= 1'b0;
                        if (!cpha) begin
                            // Shift (CPHA=0)
                            tx_shift <= {tx_shift[6:0], 1'b0};
                        end else begin
                            // Örnekle (CPHA=1)
                            rx_shift <= {rx_shift[6:0], spi_miso};
                        end
                        phase   <= 1'b0;
                        bit_cnt <= bit_cnt + 1'd1;

                        if (bit_cnt == 4'd7) begin
                            // Transfer tamamlandı
                            spi_busy    <= 1'b0;
                            rx_data_reg <= rx_shift;
                            tx_done     <= 1'b1;
                            irq_pulse   <= 1'b1;
                            if (cs_auto) spi_cs_n <= 1'b1;  // CS yükselt
                        end
                    end
                end
            end
        end
    end

    assign spi_mosi = tx_shift[7];  // MSB first

    // ============================================================
    // Register Yazma (CTRL, CLK_DIV)
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_en        <= 1'b0;
            cpol          <= 1'b0;
            cpha          <= 1'b0;
            cs_auto       <= 1'b1;
            cs_manual_val <= 1'b0;
            clk_div_reg   <= 16'd4;   // Varsayılan: clk/10
        end else if (we) begin
            case (reg_sel)
                REG_CTRL: begin
                    spi_en        <= wdata[0];
                    cpol          <= wdata[1];
                    cpha          <= wdata[2];
                    cs_auto       <= wdata[3];
                    cs_manual_val <= wdata[4];
                end
                REG_CLK_DIV: clk_div_reg <= wdata[15:0];
                default: ;
            endcase
        end
    end

    // ============================================================
    // Register Okuma
    // ============================================================
    always @(*) begin
        case (reg_sel)
            REG_CTRL:    rdata = {27'h0, cs_manual_val, cs_auto, cpha, cpol, spi_en};
            REG_DATA:    rdata = {24'h0, rx_data_reg};
            REG_STATUS:  rdata = {30'h0, tx_done, spi_busy};
            REG_CLK_DIV: rdata = {16'h0, clk_div_reg};
            default:     rdata = 32'h0;
        endcase
    end

endmodule
