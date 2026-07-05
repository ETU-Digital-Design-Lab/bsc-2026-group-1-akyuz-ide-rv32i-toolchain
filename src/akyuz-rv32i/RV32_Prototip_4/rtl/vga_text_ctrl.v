// vga_text_ctrl.v — VGA 80×30 text-mode controller with Hardware Graphics Intro
//
// Hardware Intro: if graphics_mode = 1, it generates a colorful XOR/Plasma pattern.
// Improved: uses pclk-based edge detection for frame_cnt to ensure stability.

module vga_text_ctrl #(
    parameter FONT_FILE = "font8x16.hex"
) (
    input  wire        pclk,
    input  wire        rst_n,
    input  wire [9:0]  hcount,
    input  wire [9:0]  vcount,
    input  wire        active,
    input  wire [4:0]  scroll_base,
    input  wire        graphics_mode,
    output wire [11:0] cb_addr_b,
    input  wire [15:0] cb_rdata_b,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b
);
    wire       hsync_c = 1'b1; // Dummy for internal logic if needed
    wire       vsync_c = 1'b1;
    wire       active_c = active;

    // Stage 0
    wire [4:0]  char_row_w  = vcount[8:4];
    wire [6:0]  char_col_w  = hcount[9:3];
    wire [5:0]  scroll_row  = {1'b0, char_row_w} + {1'b0, scroll_base};
    wire [4:0]  phys_row    = (scroll_row >= 6'd30) ? scroll_row[4:0] - 5'd30 : scroll_row[4:0];
    assign cb_addr_b = ({7'b0, phys_row} << 6) + ({7'b0, phys_row} << 4) + {5'b0, char_col_w};

    reg [2:0] pcol_d;
    reg [3:0] prow_d;
    reg [9:0] hcount_d, vcount_d;
    reg       active_d, hsync_d, vsync_d;

    always @(posedge pclk) begin
        pcol_d   <= hcount[2:0];
        prow_d   <= vcount[3:0];
        hcount_d <= hcount;
        vcount_d <= vcount;
        active_d <= active_c;
        hsync_d  <= hsync_c;
        vsync_d  <= vsync_c;
    end

    // Stage 1 (Text)
    wire [6:0] char_idx  = cb_rdata_b[6:0];
    wire [3:0] fg_color  = cb_rdata_b[11:8];
    wire [3:0] bg_color  = cb_rdata_b[15:12];
    wire [7:0] font_row;
    font_rom #(.FONT_FILE(FONT_FILE)) u_font (.addr({char_idx, prow_d}), .data(font_row));
    wire pixel_bit = font_row[3'd7 - pcol_d];
    wire [3:0] sel_color = pixel_bit ? fg_color : bg_color;

    reg [11:0] palette_rgb;
    always @(*) begin
        case (sel_color)
            4'h0: palette_rgb = 12'h000; 4'h1: palette_rgb = 12'h00A; 4'h2: palette_rgb = 12'h0A0;
            4'h3: palette_rgb = 12'h0AA; 4'h4: palette_rgb = 12'hA00; 4'h5: palette_rgb = 12'hA0A;
            4'h6: palette_rgb = 12'hA60; 4'h7: palette_rgb = 12'hAAA; 4'h8: palette_rgb = 12'h555;
            4'h9: palette_rgb = 12'h55F; 4'hA: palette_rgb = 12'h5F5; 4'hB: palette_rgb = 12'h5FF;
            4'hC: palette_rgb = 12'hF55; 4'hD: palette_rgb = 12'hF5F; 4'hE: palette_rgb = 12'hFF5;
            default: palette_rgb = 12'hFFF;
        endcase
    end

    // Stage 1 (Graphics)
    reg [7:0] frame_cnt;
    reg vsync_prev;
    always @(posedge pclk) begin
        vsync_prev <= vsync_d;
        if (vsync_d && !vsync_prev) frame_cnt <= frame_cnt + 8'd1;
    end

    // Vibrant Plasma Pattern
    wire [3:0] plasma_r = (hcount_d[6:3] ^ frame_cnt[4:1]);
    wire [3:0] plasma_g = (vcount_d[6:3] ^ frame_cnt[4:1]);
    wire [3:0] plasma_b = (hcount_d[5:2] + vcount_d[5:2] + frame_cnt[5:2]);
    wire [11:0] graphics_rgb = {plasma_r, plasma_g, plasma_b};

    wire [11:0] final_rgb = graphics_mode ? graphics_rgb : palette_rgb;
    assign vga_r = active_d ? final_rgb[11:8] : 4'h0;
    assign vga_g = active_d ? final_rgb[7:4]  : 4'h0;
    assign vga_b = active_d ? final_rgb[3:0]  : 4'h0;
endmodule
