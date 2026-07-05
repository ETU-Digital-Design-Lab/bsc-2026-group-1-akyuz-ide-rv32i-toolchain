// hw_bootloader.v
// Listens to UART RX. Detects Magic sequence (0xDE 0xAD 0xBE 0xEF).
// Receives length L (4 bytes, little endian).
// Asserts cpu_reset_n = 0 to halt CPU.
// Receives L bytes (Payload) and writes to IMEM as 32-bit words.
// Releases cpu_reset_n = 1 upon completion.

module hw_bootloader (
    input  wire        clk,
    input  wire        rst_n,

    // UART interface
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,

    // IMEM Write Interface (Port B)
    output reg         imem_we,
    output reg  [31:0] imem_waddr,
    output reg  [31:0] imem_wdata,

    // SoC Control (0: Halt/Reset CPU, 1: Run)
    output reg         cpu_reset_n,
    output wire        is_loading
);

    localparam S_WAIT_M0 = 0; // 0xDE
    localparam S_WAIT_M1 = 1; // 0xAD
    localparam S_WAIT_M2 = 2; // 0xBE
    localparam S_WAIT_M3 = 3; // 0xEF
    localparam S_LEN_0   = 4;
    localparam S_LEN_1   = 5;
    localparam S_LEN_2   = 6;
    localparam S_LEN_3   = 7;
    localparam S_PAYLOAD_0 = 8;
    localparam S_PAYLOAD_1 = 9;
    localparam S_PAYLOAD_2 = 10;
    localparam S_PAYLOAD_3 = 11;
    localparam S_WRITE     = 12;

    reg [3:0]  state;

    assign is_loading = (state != S_WAIT_M0);
    reg [31:0] payload_len;
    reg [31:0] byte_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_WAIT_M0;
            cpu_reset_n <= 1'b1; // CPU runs normally by default
            imem_we     <= 1'b0;
            imem_waddr  <= 32'd0;
            imem_wdata  <= 32'd0;
            payload_len <= 32'd0;
            byte_count  <= 32'd0;
        end else begin
            imem_we <= 1'b0; // default to no write
            
            if (rx_valid) begin
                case (state)
                    S_WAIT_M0: begin
                        if (rx_data == 8'hDE) state <= S_WAIT_M1;
                    end
                    S_WAIT_M1: begin
                        if (rx_data == 8'hAD) state <= S_WAIT_M2;
                        else if (rx_data == 8'hDE) state <= S_WAIT_M1;
                        else state <= S_WAIT_M0;
                    end
                    S_WAIT_M2: begin
                        if (rx_data == 8'hBE) state <= S_WAIT_M3;
                        else if (rx_data == 8'hDE) state <= S_WAIT_M1;
                        else state <= S_WAIT_M0;
                    end
                    S_WAIT_M3: begin
                        if (rx_data == 8'hEF) begin
                            state       <= S_LEN_0;
                            cpu_reset_n <= 1'b0; // Halt CPU immediately!
                            imem_waddr  <= 32'd0;
                            byte_count  <= 32'd0;
                        end else if (rx_data == 8'hDE) state <= S_WAIT_M1;
                        else state <= S_WAIT_M0;
                    end
                    
                    // Receive Length bytes (Little Endian)
                    S_LEN_0: begin
                        payload_len[7:0] <= rx_data;
                        state <= S_LEN_1;
                    end
                    S_LEN_1: begin
                        payload_len[15:8] <= rx_data;
                        state <= S_LEN_2;
                    end
                    S_LEN_2: begin
                        payload_len[23:16] <= rx_data;
                        state <= S_LEN_3;
                    end
                    S_LEN_3: begin
                        payload_len[31:24] <= rx_data;
                        if ({rx_data, payload_len[23:0]} == 0) begin
                            state <= S_WAIT_M0;
                            cpu_reset_n <= 1'b1; // Empty firmware, release CPU
                        end else begin
                            state <= S_PAYLOAD_0;
                        end
                    end
                    
                    // Receive Payload bytes (Little Endian RV32I instructions)
                    S_PAYLOAD_0: begin
                        imem_wdata[7:0] <= rx_data;
                        byte_count <= byte_count + 1'b1;
                        state <= S_PAYLOAD_1;
                    end
                    S_PAYLOAD_1: begin
                        imem_wdata[15:8] <= rx_data;
                        byte_count <= byte_count + 1'b1;
                        state <= S_PAYLOAD_2;
                    end
                    S_PAYLOAD_2: begin
                        imem_wdata[23:16] <= rx_data;
                        byte_count <= byte_count + 1'b1;
                        state <= S_PAYLOAD_3;
                    end
                    S_PAYLOAD_3: begin
                        imem_wdata[31:24] <= rx_data;
                        byte_count <= byte_count + 1'b1;
                        imem_we    <= 1'b1;  // Assert Write Enable for the upcoming S_WRITE cycle
                        state <= S_WRITE;
                    end
                    default: state <= S_WAIT_M0;
                endcase
            end
            
            // Unconditional cycle actions (don't wait for rx_valid)
            if (state == S_WRITE) begin
                // During this cycle, imem_we is HIGH, and waddr/wdata are stable.
                // At the end of this cycle, RAM will latch the data perfectly.
                // The default `imem_we <= 1'b0` at the top will de-assert WE for next cycle.
                
                if (byte_count >= payload_len) begin
                    state <= S_WAIT_M0;
                    cpu_reset_n <= 1'b1; // Release CPU, it will boot from 0
                end else begin
                    state <= S_PAYLOAD_0;
                    imem_waddr <= imem_waddr + 32'd4; // Advance address AFTER writing
                end
            end
        end
    end

endmodule
