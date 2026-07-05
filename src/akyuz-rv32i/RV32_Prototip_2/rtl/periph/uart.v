`timescale 1ns / 1ps

// uart.v
//
// Basit UART çevre birimi - TX ve RX destekli.
// Baud rate = clk_freq / (BAUD_DIV * 16)
//
// Register Map (byte offset):
//   0x0  (R/W) TX_DATA   [7:0]  - Yazınca TX başlar, okuyunca son gönderilen
//   0x4  (R)   RX_DATA   [7:0]  - Alınan veri (okuyunca RX_VALID temizlenir)
//   0x8  (R/W) STATUS    [7:0]  - [0]=TX_BUSY, [1]=RX_VALID, [2]=RX_OVF
//   0xC  (R/W) BAUD_DIV  [15:0] - Baud rate bölücü (varsayılan: CLK_FREQ/16/BAUD_RATE)
//
// Kullanım örneği (100MHz, 115200 baud):
//   BAUD_DIV = 100_000_000 / 16 / 115_200 ≈ 54

module uart #(
    parameter XLEN         = 32,
    parameter CLK_FREQ     = 50_000_000,  // 50 MHz (FPGA varsayılanı)
    parameter BAUD_RATE    = 115_200,
    parameter DEFAULT_DIV  = CLK_FREQ / 16 / BAUD_RATE
)(
    input  wire        clk,
    input  wire        rst_n,

    // Bus Interface
    input  wire [3:0]  addr,     // [3:2] -> register seçimi
    input  wire [31:0] wdata,
    input  wire        we,
    output reg  [31:0] rdata,

    // UART Fiziksel Pinler
    output wire        uart_tx,
    input  wire        uart_rx,

    // Interrupt çıkışları
    output wire        tx_irq,   // TX tamamlandı
    output wire        rx_irq    // RX veri geldi
);

    // ============================================================
    // Register Adresleri
    // ============================================================
    localparam REG_TX_DATA  = 2'd0;  // 0x0
    localparam REG_RX_DATA  = 2'd1;  // 0x4
    localparam REG_STATUS   = 2'd2;  // 0x8
    localparam REG_BAUD_DIV = 2'd3;  // 0xC

    wire [1:0] reg_sel = addr[3:2];

    // ============================================================
    // Baud Rate Generator (16x oversampling)
    // ============================================================
    reg  [15:0] baud_div_reg;
    reg  [15:0] baud_cnt;
    wire        baud_tick;    // 16x baud clock

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            baud_div_reg <= DEFAULT_DIV[15:0];
        else if (we && reg_sel == REG_BAUD_DIV)
            baud_div_reg <= wdata[15:0];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            baud_cnt <= 16'd0;
        else if (baud_cnt == baud_div_reg - 1)
            baud_cnt <= 16'd0;
        else
            baud_cnt <= baud_cnt + 1'd1;
    end

    assign baud_tick = (baud_cnt == baud_div_reg - 1);

    // ============================================================
    // TX Bölümü
    // ============================================================
    // TX: 1 start bit (0), 8 data bit, 1 stop bit (1)
    reg  [7:0]  tx_shift;
    reg  [3:0]  tx_bit_cnt;   // 0..9 (0=start, 1..8=data, 9=stop)
    reg  [3:0]  tx_tick_cnt;  // 16x oversample sayacı
    reg         tx_busy;
    reg         tx_reg_out;
    reg         tx_done_pulse;

    assign uart_tx = tx_reg_out;
    assign tx_irq  = tx_done_pulse;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_busy       <= 1'b0;
            tx_reg_out    <= 1'b1;  // UART idle = high
            tx_bit_cnt    <= 4'd0;
            tx_tick_cnt   <= 4'd0;
            tx_done_pulse <= 1'b0;
        end else begin
            tx_done_pulse <= 1'b0;

            if (!tx_busy) begin
                tx_reg_out <= 1'b1;
                if (we && reg_sel == REG_TX_DATA) begin
                    tx_shift    <= wdata[7:0];
                    tx_busy     <= 1'b1;
                    tx_bit_cnt  <= 4'd0;
                    tx_tick_cnt <= 4'd0;
                end
            end else begin
                if (baud_tick) begin
                    if (tx_tick_cnt == 4'd15) begin
                        tx_tick_cnt <= 4'd0;
                        case (tx_bit_cnt)
                            4'd0: begin
                                tx_reg_out <= 1'b0;        // Start bit
                                tx_bit_cnt <= 4'd1;
                            end
                            4'd9: begin
                                tx_reg_out    <= 1'b1;     // Stop bit
                                tx_busy       <= 1'b0;
                                tx_done_pulse <= 1'b1;
                                tx_bit_cnt    <= 4'd0;
                            end
                            default: begin
                                tx_reg_out <= tx_shift[0]; // LSB first
                                tx_shift   <= {1'b0, tx_shift[7:1]};
                                tx_bit_cnt <= tx_bit_cnt + 1'd1;
                            end
                        endcase
                    end else begin
                        tx_tick_cnt <= tx_tick_cnt + 1'd1;
                    end
                end
            end
        end
    end

    // ============================================================
    // RX Bölümü (16x oversample)
    // ============================================================
    reg  [7:0]  rx_data_reg;
    reg         rx_valid;
    reg         rx_overflow;
    reg  [7:0]  rx_shift;
    reg  [3:0]  rx_bit_cnt;
    reg  [3:0]  rx_sample_cnt;  // 16x oversample
    reg         rx_busy;
    reg         rx_sync0, rx_sync1, rx_sync2;  // metastability sync
    wire        rx_in;
    wire        rx_irq_w;

    assign rx_in  = rx_sync2;
    assign rx_irq = rx_valid;

    // 2-flop synchronizer için RX
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync0 <= 1'b1;
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync0 <= uart_rx;
            rx_sync1 <= rx_sync0;
            rx_sync2 <= rx_sync1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_data_reg  <= 8'h00;
            rx_valid     <= 1'b0;
            rx_overflow  <= 1'b0;
            rx_shift     <= 8'h00;
            rx_bit_cnt   <= 4'd0;
            rx_sample_cnt<= 4'd0;
            rx_busy      <= 1'b0;
        end else begin
            // RX_DATA okununca valid temizle
            if (!we && reg_sel == REG_RX_DATA)
                rx_valid <= 1'b0;

            if (!rx_busy) begin
                // Start bit tespiti (falling edge = idle->0)
                if (!rx_in) begin
                    rx_busy       <= 1'b1;
                    rx_sample_cnt <= 4'd0;
                    rx_bit_cnt    <= 4'd0;
                end
            end else begin
                if (baud_tick) begin
                    rx_sample_cnt <= rx_sample_cnt + 1'd1;

                    // Ortada örnekle (sample_cnt == 7)
                    if (rx_sample_cnt == 4'd7) begin
                        if (rx_bit_cnt == 4'd0) begin
                            // Start bit doğrulama
                            if (rx_in) begin
                                // Yanlış start bit, iptal et
                                rx_busy <= 1'b0;
                            end
                        end else if (rx_bit_cnt <= 4'd8) begin
                            rx_shift <= {rx_in, rx_shift[7:1]};  // LSB first
                        end else begin
                            // Stop bit
                            rx_busy <= 1'b0;
                            if (rx_in) begin  // Stop bit valid
                                rx_data_reg <= rx_shift;
                                if (rx_valid)
                                    rx_overflow <= 1'b1;  // Önceki okunmadı
                                rx_valid <= 1'b1;
                            end
                        end
                    end

                    // Her 16 tick'te bir sonraki bit
                    if (rx_sample_cnt == 4'd15)
                        rx_bit_cnt <= rx_bit_cnt + 1'd1;
                end
            end

            // Overflow, STATUS okunduğunda temizlenir
            if (!we && reg_sel == REG_STATUS)
                rx_overflow <= 1'b0;
        end
    end

    // ============================================================
    // Register Read
    // ============================================================
    always @(*) begin
        case (reg_sel)
            REG_TX_DATA:  rdata = {24'h0, tx_shift};
            REG_RX_DATA:  rdata = {24'h0, rx_data_reg};
            REG_STATUS:   rdata = {29'h0, rx_overflow, rx_valid, tx_busy};
            REG_BAUD_DIV: rdata = {16'h0, baud_div_reg};
            default:      rdata = 32'h0;
        endcase
    end

endmodule
