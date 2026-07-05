module ov7670_sccb_init (
    input  wire clk,
    input  wire rst_n,
    output reg  sioc,
    inout  wire siod,
    output reg  done,
    output reg  ack_error,
    output wire cam_reset_n,
    output wire cam_pwdn
);

    // SCCB clock: 100 MHz / 2000 = 50 kHz tick (safer speed)
    localparam CLK_DIV  = 16'd2000;
    localparam ROM_SIZE = 58;

    reg [15:0] cfg_rom [0:ROM_SIZE-1];
    initial begin
        // QQVGA 160x120 via DCW from QVGA, RGB565
        cfg_rom[0]  = 16'h1280; // COM7: software reset
        cfg_rom[1]  = 16'h1214; // COM7: QVGA + RGB565
        cfg_rom[2]  = 16'h1180; // CLKRC: XCLK direct
        cfg_rom[3]  = 16'h0C04; // COM3: scale enable
        cfg_rom[4]  = 16'h3E19; // COM14: PCLK /2
        cfg_rom[5]  = 16'h703A; // SCALING_XSC
        cfg_rom[6]  = 16'h7135; // SCALING_YSC
        cfg_rom[7]  = 16'h7211; // SCALING_DCWCTR: 2x H+V
        cfg_rom[8]  = 16'h73F1; // SCALING_PCLK_DIV: /2
        cfg_rom[9]  = 16'hA252; // SCALING_PCLK_DELAY
        cfg_rom[10] = 16'h40D0; // COM15: RGB565 full range
        cfg_rom[11] = 16'h8C00; // RGB444: off
        cfg_rom[12] = 16'h3A04; // TSLB
        cfg_rom[13] = 16'h1716; // HSTART: QVGA
        cfg_rom[14] = 16'h1804; // HSTOP:  QVGA
        cfg_rom[15] = 16'h3224; // HREF:   QVGA
        cfg_rom[16] = 16'h1902; // VSTART
        cfg_rom[17] = 16'h1A7A; // VSTOP
        cfg_rom[18] = 16'h030A; // VREF
        cfg_rom[19] = 16'h1418; // COM9: AGC 4x
        cfg_rom[20] = 16'h4F80; // MTX1
        cfg_rom[21] = 16'h5080; // MTX2
        cfg_rom[22] = 16'h5100; // MTX3
        cfg_rom[23] = 16'h5222; // MTX4
        cfg_rom[24] = 16'h535E; // MTX5
        cfg_rom[25] = 16'h5480; // MTX6
        cfg_rom[26] = 16'h589E; // MTXS
        cfg_rom[27] = 16'h3DC0;
        cfg_rom[28] = 16'h0E61;
        cfg_rom[29] = 16'h0F4B;
        cfg_rom[30] = 16'h1602;
        cfg_rom[31] = 16'h1E37; // MVFP
        cfg_rom[32] = 16'h2102;
        cfg_rom[33] = 16'h2291;
        cfg_rom[34] = 16'h2907;
        cfg_rom[35] = 16'h330B;
        cfg_rom[36] = 16'h350B;
        cfg_rom[37] = 16'h371D;
        cfg_rom[38] = 16'h3871;
        cfg_rom[39] = 16'h392A;
        cfg_rom[40] = 16'h3C78;
        cfg_rom[41] = 16'h4D40;
        cfg_rom[42] = 16'h4E20;
        cfg_rom[43] = 16'h6900;
        cfg_rom[44] = 16'h6B4A;
        cfg_rom[45] = 16'h7410;
        cfg_rom[46] = 16'h8D4F;
        cfg_rom[47] = 16'h8E00;
        cfg_rom[48] = 16'h8F00;
        cfg_rom[49] = 16'h9000;
        cfg_rom[50] = 16'h9100;
        cfg_rom[51] = 16'h9600;
        cfg_rom[52] = 16'h9A00;
        cfg_rom[53] = 16'hB084;
        cfg_rom[54] = 16'hB10C;
        cfg_rom[55] = 16'hB20E;
        cfg_rom[56] = 16'hB382;
        cfg_rom[57] = 16'h0400;
    end

    assign cam_reset_n = 1'b1;
    assign cam_pwdn    = 1'b0;

    reg siod_oe;
    reg siod_out;
    assign siod = siod_oe ? siod_out : 1'bz;
    wire siod_in = siod;

    reg [15:0] div_cnt;
    reg tick;
    always @(posedge clk) begin
        if (!rst_n) begin
            div_cnt <= 16'd0;
            tick    <= 1'b0;
        end else if (div_cnt == CLK_DIV-1) begin
            div_cnt <= 16'd0;
            tick    <= 1'b1;
        end else begin
            div_cnt <= div_cnt + 16'd1;
            tick    <= 1'b0;
        end
    end

    // Longer power-on delay (~20ms)
    reg [21:0] pwon_cnt;
    reg pwon_done;
    always @(posedge clk) begin
        if (!rst_n) begin
            pwon_cnt  <= 22'd0;
            pwon_done <= 1'b0;
        end else if (!pwon_done) begin
            pwon_cnt <= pwon_cnt + 22'd1;
            if (pwon_cnt == 22'h1FFFFF)
                pwon_done <= 1'b1;
        end
    end

    reg [7:0] rom_idx;
    reg [5:0] bit_idx;
    reg [3:0] state; // State debugging
    reg [23:0] shift;
    reg [1:0] phase;
    reg [15:0] delay_cnt;

    localparam ST_IDLE   = 4'd0;
    localparam ST_START  = 4'd1;
    localparam ST_SEND   = 4'd2;
    localparam ST_ACK    = 4'd3;
    localparam ST_STOP   = 4'd4;
    localparam ST_DELAY  = 4'd5;
    localparam ST_NEXT   = 4'd6;
    localparam ST_DONE   = 4'd7;

    always @(posedge clk) begin
        if (!rst_n) begin
            sioc         <= 1'b1;
            siod_oe      <= 1'b1;
            siod_out     <= 1'b1;
            done         <= 1'b0;
            ack_error    <= 1'b0;
            rom_idx      <= 8'd0;
            bit_idx      <= 6'd0;
            state        <= ST_IDLE;
            phase        <= 2'd0;
            shift        <= 24'd0;
            delay_cnt    <= 16'd0;
        end else if (tick) begin
            case (state)
                ST_IDLE: begin
                    if (pwon_done) begin
                        done     <= 1'b0;
                        sioc     <= 1'b1;
                        siod_oe  <= 1'b1;
                        siod_out <= 1'b1;
                        shift    <= {8'h42, cfg_rom[rom_idx]};
                        bit_idx  <= 6'd23;
                        phase    <= 2'd0;
                        state    <= ST_START;
                    end
                end

                ST_START: begin
                    if (phase == 0) begin
                        siod_out <= 1'b0; // SDA goes low
                        phase    <= 1;
                    end else begin
                        sioc     <= 1'b0; // SCL goes low
                        phase    <= 0;
                        state    <= ST_SEND;
                    end
                end

                ST_SEND: begin
                    if (phase == 0) begin
                        siod_oe  <= 1'b1;
                        siod_out <= shift[bit_idx];
                        phase    <= 1;
                    end else if (phase == 1) begin
                        sioc     <= 1'b1; // SCL high
                        phase    <= 2;
                    end else if (phase == 2) begin
                        phase    <= 3; // Keep SCL high
                    end else begin
                        sioc     <= 1'b0; // SCL low
                        phase    <= 0;
                        if (bit_idx[2:0] == 3'd0) state <= ST_ACK;
                        else bit_idx <= bit_idx - 6'd1;
                    end
                end

                ST_ACK: begin
                    if (phase == 0) begin
                        siod_oe <= 1'b0; // release SDA
                        phase   <= 1;
                    end else if (phase == 1) begin
                        sioc    <= 1'b1; // SCL high
                        phase   <= 2;
                    end else if (phase == 2) begin
                        if (siod_in) ack_error <= 1'b1; // Check ACK
                        phase   <= 3;
                    end else begin
                        sioc    <= 1'b0; // SCL low
                        phase   <= 0;
                        if (bit_idx == 0) state <= ST_STOP;
                        else begin
                            bit_idx <= bit_idx - 6'd1;
                            state   <= ST_SEND;
                        end
                    end
                end

                ST_STOP: begin
                    if (phase == 0) begin
                        siod_oe  <= 1'b1;
                        siod_out <= 1'b0;
                        phase    <= 1;
                    end else if (phase == 1) begin
                        sioc     <= 1'b1;
                        phase    <= 2;
                    end else begin
                        siod_out <= 1'b1; // SDA goes high while SCL high
                        phase    <= 0;
                        state    <= ST_DELAY;
                        delay_cnt <= 0;
                    end
                end

                ST_DELAY: begin
                    // After reset reg (idx=0): wait ~200ms (10000 ticks @ 50kHz)
                    // Other registers: wait ~2ms (100 ticks)
                    if (delay_cnt < (rom_idx == 0 ? 16'd10000 : 16'd100))
                        delay_cnt <= delay_cnt + 1;
                    else
                        state <= ST_NEXT;
                end

                ST_NEXT: begin
                    if (rom_idx == ROM_SIZE-1) state <= ST_DONE;
                    else begin
                        rom_idx <= rom_idx + 1;
                        state   <= ST_IDLE;
                    end
                end

                ST_DONE: begin
                    done <= 1'b1;
                end
            endcase
        end
    end
endmodule
