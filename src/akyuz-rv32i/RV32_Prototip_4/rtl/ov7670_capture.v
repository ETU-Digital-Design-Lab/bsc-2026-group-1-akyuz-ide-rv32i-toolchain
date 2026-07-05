// Captures QQVGA 160x120 from OV7670. 8-bit luminance Y=(R+2G+B)/4.
// addr = row*160+col via shift-add, no DSP.
module ov7670_capture #(
    parameter SAMPLE_POSEDGE    = 1,
    parameter SWAP_RGB565_BYTES = 0
)(
    input  wire        pclk,
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        href,
    input  wire [7:0]  d,
    output reg  [14:0] fb_addr,
    output reg  [7:0]  fb_data,
    output reg         fb_we
);
    reg [7:0] x;
    reg [6:0] y;
    reg [7:0] byte_hi;
    reg       byte_sel;
    reg       href_d;
    wire [15:0] pix565 = SWAP_RGB565_BYTES ? {d, byte_hi} : {byte_hi, d};

    // RGB565: R[15:11] G[10:5] B[4:0]
    // Expand each channel to 8-bit then compute Y=(R+2G+B)/4
    wire [7:0] r8 = {pix565[15:11], pix565[15:13]};
    wire [7:0] g8 = {pix565[10:5],  pix565[10:9]};
    wire [7:0] b8 = {pix565[4:0],   pix565[4:2]};
    wire [9:0] ysum = {2'b0, r8} + {1'b0, g8, 1'b0} + {2'b0, b8};
    wire [7:0] lum8 = ysum[9:2]; // divide by 4, range 0-255

    wire [14:0] y15 = {8'b0, y};
    wire [14:0] addr_calc = (y15 << 7) + (y15 << 5) + {7'b0, x};

    always @(posedge pclk) begin
        if (!rst_n) begin
            x <= 0; y <= 0; byte_sel <= 0;
            fb_addr <= 0; fb_data <= 0; fb_we <= 0; href_d <= 0;
        end else begin
            href_d <= href;
            fb_we  <= 1'b0;

            if (vsync) begin
                x <= 0; y <= 0; byte_sel <= 0;
            end else if (href_d && !href) begin
                x <= 0; byte_sel <= 0;
                if (y < 119) y <= y + 1;
            end

            if (href) begin
                if (!byte_sel) begin
                    byte_hi  <= d;
                    byte_sel <= 1'b1;
                end else begin
                    byte_sel <= 1'b0;
                    if (x < 160 && y < 120) begin
                        fb_addr <= addr_calc;
                        fb_data <= lum8;
                        fb_we   <= 1'b1;
                    end
                    if (x < 8'd255) x <= x + 1;
                end
            end
        end
    end
endmodule
