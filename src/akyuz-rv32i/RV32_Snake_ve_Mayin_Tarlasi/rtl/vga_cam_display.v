module vga_cam_display (
    input  wire        pclk,
    input  wire        rst_n,
    output wire [16:0] fb_addr,
    input  wire [11:0] fb_data,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hsync,
    output wire        vga_vsync
);
    wire [9:0] hcount;
    wire [9:0] vcount;
    wire active;

    wire hsync_c, vsync_c, active_c;
    reg  hsync_r, vsync_r, active_r;

    vga_sync u_sync (
        .pclk(pclk),
        .rst_n(rst_n),
        .hcount(hcount),
        .vcount(vcount),
        .hsync(hsync_c),
        .vsync(vsync_c),
        .active(active_c)
    );

    always @(posedge pclk) begin
        if (!rst_n) begin
            hsync_r  <= 1'b1;
            vsync_r  <= 1'b1;
            active_r <= 1'b0;
        end else begin
            hsync_r  <= hsync_c;
            vsync_r  <= vsync_c;
            active_r <= active_c;
        end
    end

    assign vga_hsync = hsync_r;
    assign vga_vsync = vsync_r;

    // 160x120 buffer'i 4x buyut: her piksel ekranda 4x4 bloga yayilir
    assign fb_addr = ({10'd0, vcount[8:2]} * 17'd160) + {9'd0, hcount[9:2]};

    assign vga_r = active_r ? fb_data[11:8] : 4'd0;
    assign vga_g = active_r ? fb_data[7:4]  : 4'd0;
    assign vga_b = active_r ? fb_data[3:0]  : 4'd0;
endmodule
