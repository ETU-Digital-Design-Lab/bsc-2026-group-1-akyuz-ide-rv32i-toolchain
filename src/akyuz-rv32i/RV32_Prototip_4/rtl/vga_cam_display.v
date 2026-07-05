// Displays 160x120 8-bit grayscale framebuffer in PIP window at (400,50)-(560,170).
// VGA output: R=G=B=fb_data[7:4] (top 4 bits to 4-bit VGA DAC).
module vga_cam_display (
    input  wire        pclk,
    input  wire        rst_n,
    input  wire [9:0]  hcount,
    input  wire [9:0]  vcount,
    input  wire        active,
    output wire [14:0] fb_addr,
    input  wire [7:0]  fb_data,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b
);
    wire in_window = (hcount >= 10'd400 && hcount < 10'd560 &&
                      vcount >= 10'd50  && vcount < 10'd170);

    wire [7:0] rel_x = hcount[7:0] - 8'd144; // hcount-400 in 8-bit modular
    wire [6:0] rel_y = vcount[6:0] - 7'd50;  // vcount-50  in 7-bit modular

    wire [14:0] ry15 = {8'b0, rel_y};
    assign fb_addr = in_window
        ? ((ry15 << 7) + (ry15 << 5) + {7'b0, rel_x})
        : 15'd0;

    // Gamma correction: gray = floor(sqrt(fb_data))
    // Boosts dark areas (faces, objects), keeps highlights bright.
    // 0-255 -> 0-15 via integer square root, no LUT needed.
    reg [3:0] gray;
    always @(*) begin
        if      (fb_data < 8'd1)   gray = 4'd0;
        else if (fb_data < 8'd4)   gray = 4'd1;
        else if (fb_data < 8'd9)   gray = 4'd2;
        else if (fb_data < 8'd16)  gray = 4'd3;
        else if (fb_data < 8'd25)  gray = 4'd4;
        else if (fb_data < 8'd36)  gray = 4'd5;
        else if (fb_data < 8'd49)  gray = 4'd6;
        else if (fb_data < 8'd64)  gray = 4'd7;
        else if (fb_data < 8'd81)  gray = 4'd8;
        else if (fb_data < 8'd100) gray = 4'd9;
        else if (fb_data < 8'd121) gray = 4'd10;
        else if (fb_data < 8'd144) gray = 4'd11;
        else if (fb_data < 8'd169) gray = 4'd12;
        else if (fb_data < 8'd196) gray = 4'd13;
        else if (fb_data < 8'd225) gray = 4'd14;
        else                       gray = 4'd15;
    end
    assign vga_r = (active && in_window) ? gray : 4'd0;
    assign vga_g = (active && in_window) ? gray : 4'd0;
    assign vga_b = (active && in_window) ? gray : 4'd0;
endmodule
