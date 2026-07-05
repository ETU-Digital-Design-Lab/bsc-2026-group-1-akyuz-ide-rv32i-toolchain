module ov7670_capture #(
    parameter SAMPLE_POSEDGE = 1,
    parameter SWAP_RGB565_BYTES = 0
)(
    input  wire        pclk,
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        href,
    input  wire [7:0]  d,
    output reg  [16:0] fb_addr,
    output reg  [11:0] fb_data,
    output reg         fb_we
);
    reg [9:0] x;
    reg [8:0] y;
    reg [7:0] byte_hi;
    reg       byte_sel;
    reg       href_d;
    wire [15:0] pix565 = SWAP_RGB565_BYTES ? {d, byte_hi} : {byte_hi, d};

    generate
        if (SAMPLE_POSEDGE) begin : gen_sample_posedge
            always @(posedge pclk) begin
                if (!rst_n) begin
                    x        <= 10'd0;
                    y        <= 9'd0;
                    byte_hi  <= 8'd0;
                    byte_sel <= 1'b0;
                    fb_addr  <= 17'd0;
                    fb_data  <= 12'd0;
                    fb_we    <= 1'b0;
                    href_d   <= 1'b0;
                end else begin
                    href_d <= href;
                    fb_we  <= 1'b0;

                    if (vsync) begin
                        x        <= 10'd0;
                        y        <= 9'd0;
                        byte_sel <= 1'b0;
                    end else if (href_d && !href) begin
                        x        <= 10'd0;
                        byte_sel <= 1'b0;
                        if (y < 9'd479) y <= y + 9'd1;
                    end

                    if (href) begin
                        if (!byte_sel) begin
                            byte_hi  <= d;
                            byte_sel <= 1'b1;
                        end else begin
                            byte_sel <= 1'b0;
                            if ((x < 10'd640) && (y < 9'd480) && ((x >> 2) < 10'd160) && ((y >> 2) < 9'd120)) begin
                                fb_addr <= ({10'd0, y[8:2]} * 17'd160) + {9'd0, x[9:2]};
                                fb_data <= {pix565[15:12], pix565[10:7], pix565[4:1]}; // RGB565 -> RGB444
                                fb_we   <= 1'b1;
                            end
                            x <= x + 10'd2;
                        end
                    end
                end
            end
        end else begin : gen_sample_negedge
            always @(negedge pclk) begin
                if (!rst_n) begin
                    x        <= 10'd0;
                    y        <= 9'd0;
                    byte_hi  <= 8'd0;
                    byte_sel <= 1'b0;
                    fb_addr  <= 17'd0;
                    fb_data  <= 12'd0;
                    fb_we    <= 1'b0;
                    href_d   <= 1'b0;
                end else begin
                    href_d <= href;
                    fb_we  <= 1'b0;

                    if (vsync) begin
                        x        <= 10'd0;
                        y        <= 9'd0;
                        byte_sel <= 1'b0;
                    end else if (href_d && !href) begin
                        x        <= 10'd0;
                        byte_sel <= 1'b0;
                        if (y < 9'd479) y <= y + 9'd1;
                    end

                    if (href) begin
                        if (!byte_sel) begin
                            byte_hi  <= d;
                            byte_sel <= 1'b1;
                        end else begin
                            byte_sel <= 1'b0;
                            if ((x < 10'd640) && (y < 9'd480) && ((x >> 2) < 10'd160) && ((y >> 2) < 9'd120)) begin
                                fb_addr <= ({10'd0, y[8:2]} * 17'd160) + {9'd0, x[9:2]};
                                fb_data <= {pix565[15:12], pix565[10:7], pix565[4:1]}; // RGB565 -> RGB444
                                fb_we   <= 1'b1;
                            end
                            x <= x + 10'd2;
                        end
                    end
                end
            end
        end
    endgenerate
endmodule
