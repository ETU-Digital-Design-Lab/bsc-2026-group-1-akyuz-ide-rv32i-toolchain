// uart_rx.v — Minimal UART Receiver (8N1)
// Receives one byte from rx_in and asserts rx_valid when complete.

module uart_rx #(
    parameter CLK_DIV = 434   // clk_freq / baud_rate  (434 = 50 MHz / 115200)
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx_in,
    output reg  [7:0] rx_data,
    output reg        rx_valid
);

    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0]              state;
    reg [$clog2(CLK_DIV):0] baud_cnt;
    reg [2:0]              bit_idx;
    reg [7:0]              shift_reg;
    
    // Double-flop synchronizer for RX pin to prevent metastability
    reg rx_sync1, rx_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx_in;
            rx_sync2 <= rx_sync1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            baud_cnt  <= 0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
            rx_data   <= 8'd0;
            rx_valid  <= 1'b0;
        end else begin
            rx_valid <= 1'b0; // Default: de-assert
            
            case (state)
                IDLE: begin
                    if (!rx_sync2) begin // RX line went low (Start bit detected)
                        baud_cnt <= CLK_DIV / 2; // Wait half a bit period to sample in the middle
                        state    <= START;
                    end
                end

                START: begin
                    if (baud_cnt == 0) begin
                        if (!rx_sync2) begin // Check if it's still low (valid start bit)
                            baud_cnt <= CLK_DIV - 1;
                            bit_idx  <= 3'd0;
                            state    <= DATA;
                        end else begin // False start (glitch)
                            state <= IDLE;
                        end
                    end else begin
                        baud_cnt <= baud_cnt - 1'b1;
                    end
                end

                DATA: begin
                    if (baud_cnt == 0) begin
                        baud_cnt  <= CLK_DIV - 1;
                        shift_reg <= {rx_sync2, shift_reg[7:1]}; // Shift in LSB first
                        if (bit_idx == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt - 1'b1;
                    end
                end

                STOP: begin
                    if (baud_cnt == 0) begin
                        if (rx_sync2) begin // Valid stop bit detected (high)
                            rx_data  <= shift_reg;
                            rx_valid <= 1'b1;
                        end
                        state <= IDLE;
                    end else begin
                        baud_cnt <= baud_cnt - 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
