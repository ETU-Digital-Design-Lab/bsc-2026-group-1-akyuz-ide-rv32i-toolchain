module basys3_ov7670_vga_top (
    input  wire        clk100,
    input  wire        btn_rst,
    output wire [15:0] led,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hsync,
    output wire        vga_vsync,
    input  wire        ov7670_pclk,
    output wire        ov7670_xclk,
    input  wire        ov7670_vsync,
    input  wire        ov7670_href,
    input  wire [7:0]  ov7670_data,
    output wire        ov7670_sioc,
    inout  wire        ov7670_siod,
    output wire        ov7670_pwdn,
    output wire        ov7670_reset
);
    reg [1:0] div4;
    always @(posedge clk100) div4 <= div4 + 2'd1;
    assign ov7670_xclk = div4[1]; // 25 MHz

    wire pclk_vga = div4[1];
    wire rst_n = ~btn_rst;

    wire sccb_done;
    ov7670_sccb_init u_cfg (
        .clk(clk100),
        .rst_n(rst_n),
        .sioc(ov7670_sioc),
        .siod(ov7670_siod),
        .done(sccb_done),
        .cam_reset_n(ov7670_reset),
        .cam_pwdn(ov7670_pwdn)
    );

    wire [16:0] wr_addr;
    wire [11:0] wr_data;
    wire        wr_en;
    ov7670_capture u_cap (
        .pclk(ov7670_pclk),
        .rst_n(rst_n),
        .vsync(ov7670_vsync),
        .href(ov7670_href),
        .d(ov7670_data),
        .fb_addr(wr_addr),
        .fb_data(wr_data),
        .fb_we(wr_en)
    );

    wire [16:0] rd_addr;
    wire [11:0] rd_data;
    cam_framebuffer u_fb (
        .wr_clk(ov7670_pclk),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .rd_clk(pclk_vga),
        .rd_addr(rd_addr),
        .rd_data(rd_data)
    );

    vga_cam_display u_vga (
        .pclk(pclk_vga),
        .rst_n(rst_n),
        .fb_addr(rd_addr),
        .fb_data(rd_data),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync)
    );

    assign led[0] = sccb_done;
    assign led[1] = wr_en;
    assign led[15:2] = 14'd0;
endmodule
