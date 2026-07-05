// uart_tx.v — Minimal UART Transmitter (8N1, no FIFO)
//
// Sends one byte when tx_valid is asserted and tx_ready is high.
// tx_ready goes low during transmission and returns high when done.
// Idle line state is 1 (mark).

module uart_tx #(
    parameter CLK_DIV = 868   // clk_freq / baud_rate  (868 = 100 MHz / 115200)
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    output reg        tx_ready,
    output reg        tx_out
);

    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0]              state;
    reg [$clog2(CLK_DIV):0] baud_cnt;
    reg [2:0]              bit_idx;
    reg [7:0]              shift_reg;

    wire baud_tick = (baud_cnt == CLK_DIV - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            baud_cnt  <= {($clog2(CLK_DIV)+1){1'b0}};
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
            tx_out    <= 1'b1;
            tx_ready  <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    tx_out   <= 1'b1;
                    tx_ready <= 1'b1;
                    baud_cnt <= {($clog2(CLK_DIV)+1){1'b0}};
                    if (tx_valid) begin
                        shift_reg <= tx_data;
                        tx_ready  <= 1'b0;
                        state     <= START;
                    end
                end

                START: begin
                    tx_out <= 1'b0;                   // start bit
                    if (baud_tick) begin
                        baud_cnt <= {($clog2(CLK_DIV)+1){1'b0}};
                        bit_idx  <= 3'd0;
                        state    <= DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                DATA: begin
                    tx_out <= shift_reg[0];
                    if (baud_tick) begin
                        baud_cnt  <= {($clog2(CLK_DIV)+1){1'b0}};
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        if (bit_idx == 3'd7) begin
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                STOP: begin
                    tx_out <= 1'b1;                   // stop bit
                    if (baud_tick) begin
                        baud_cnt <= {($clog2(CLK_DIV)+1){1'b0}};
                        state    <= IDLE;
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
