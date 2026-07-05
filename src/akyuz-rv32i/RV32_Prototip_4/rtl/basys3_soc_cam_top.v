// basys3_soc_cam_top.v - PIP Mode & Hard Reset + Freeze Frame
module basys3_soc_cam_top #(
    parameter IMEM_FILE = "vga_test.hex",
    parameter FONT_FILE = "font8x16.hex",
    parameter CAM_SAMPLE_POSEDGE = 0,
    parameter CAM_SWAP_RGB565_BYTES = 0
) (
    input  wire clk100,
    input  wire btn_rst,   
    input  wire btn_u, btn_l, btn_r, btn_d,
    output wire [15:0] led,
    input  wire [15:0] sw,
    output wire uart_txd_out,
    input  wire uart_rxd_in,
    output wire [3:0] vga_r,
    output wire [3:0] vga_g,
    output wire [3:0] vga_b,
    output wire vga_hsync,
    output wire vga_vsync,
    
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

    // Clocking
    reg clk_div = 1'b0;
    always @(posedge clk100) clk_div <= ~clk_div;
    wire clk_soc;
    BUFG u_clk_buf (.I(clk_div), .O(clk_soc));

    reg pclk_r = 1'b0;
    always @(posedge clk_soc) pclk_r <= ~pclk_r;
    wire pclk;
    BUFG u_pclk_buf (.I(pclk_r), .O(pclk));
    assign ov7670_xclk = pclk;

    // Reset Sync
    reg [1:0] rst_sync = 2'b00;
    wire rst_n_sync;
    always @(posedge clk_soc or posedge sw[0]) begin
        if (sw[0]) rst_sync <= 2'b00;
        else       rst_sync <= {rst_sync[0], 1'b1};
    end
    assign rst_n_sync = rst_sync[1];

    // --- HARD RESET TIMER FOR CAMERA ---
    reg [19:0] cam_rst_cnt = 0;
    reg cam_rst_n_reg = 0;
    always @(posedge clk100) begin
        if (!rst_n_sync) begin
            cam_rst_cnt <= 0;
            cam_rst_n_reg <= 0;
        end else if (cam_rst_cnt < 20'hFFFFF) begin
            cam_rst_cnt <= cam_rst_cnt + 1;
            cam_rst_n_reg <= (cam_rst_cnt > 20'h10000);
        end
    end
    assign ov7670_reset = cam_rst_n_reg;
    assign ov7670_pwdn  = 1'b0;
    wire cam_rst_n = rst_n_sync & cam_rst_n_reg & !btn_rst;
    // -----------------------------------

    // VGA Sync
    wire [9:0] vga_hcount, vga_vcount;
    wire vga_hsync_gen, vga_vsync_gen, vga_active_gen;
    vga_sync u_vga_sync (
        .pclk(pclk), .rst_n(rst_n_sync),
        .hcount(vga_hcount), .vcount(vga_vcount),
        .hsync(vga_hsync_gen), .vsync(vga_vsync_gen), .active(vga_active_gen)
    );

    // SoC
    wire [15:0] soc_led; wire soc_utx, vga_we, boot_loading;
    wire [11:0] vga_adr; wire [15:0] vga_dat;
    rv32_soc #(.IMEM_FILE(IMEM_FILE), .UART_DIV(434)) u_soc (
        .clk(clk_soc), .rst_n(rst_n_sync), .sw(sw), .btn({btn_rst, btn_u, btn_d, btn_r, btn_l}),
        .led(soc_led), .uart_tx(soc_utx), .uart_rx(uart_rxd_in),
        .vga_char_we(vga_we), .vga_char_addr(vga_adr), .vga_char_wdata(vga_dat), .boot_loading(boot_loading)
    );

    wire [11:0] cb_adr_b; wire [15:0] cb_dat_b; wire [4:0] s_base; wire g_mode;
    vga_terminal u_term (
        .clk(clk_soc), .pclk(pclk), .rst_n(rst_n_sync), .cpu_we(vga_we),
        .cpu_reg(vga_adr[1:0]), .cpu_data(vga_dat), .cb_addr_b(cb_adr_b),
        .cb_rdata_b(cb_dat_b), .scroll_base(s_base), .graphics_mode(g_mode)
    );

    wire [3:0] soc_vga_r, soc_vga_g, soc_vga_b;
    vga_text_ctrl #(.FONT_FILE(FONT_FILE)) u_soc_vga (
        .pclk(pclk), .rst_n(rst_n_sync), .hcount(vga_hcount), .vcount(vga_vcount), .active(vga_active_gen),
        .scroll_base(s_base), .graphics_mode(g_mode),
        .cb_addr_b(cb_adr_b), .cb_rdata_b(cb_dat_b), .vga_r(soc_vga_r), .vga_g(soc_vga_g), .vga_b(soc_vga_b)
    );

    // Camera Config
    wire sccb_done, sccb_ack_error;
    ov7670_sccb_init u_cfg (
        .clk(clk100), .rst_n(cam_rst_n), .sioc(ov7670_sioc), .siod(ov7670_siod),
        .done(sccb_done), .ack_error(sccb_ack_error), 
        .cam_reset_n(), .cam_pwdn()
    );

    // Capture & Buffer (Optimized for 160x120 4-bit)
    wire [14:0] wr_addr, rd_addr; wire [7:0] wr_data, rd_data; wire wr_en;
    reg [1:0] cam_done_sync = 2'b00;
    always @(posedge ov7670_pclk) cam_done_sync <= {cam_done_sync[0], sccb_done};
    wire cam_stream_en = cam_done_sync[1];

    ov7670_capture #(.SAMPLE_POSEDGE(CAM_SAMPLE_POSEDGE), .SWAP_RGB565_BYTES(CAM_SWAP_RGB565_BYTES)) u_cap (
        .pclk(ov7670_pclk), .rst_n(rst_n_sync), .vsync(ov7670_vsync), .href(ov7670_href),
        .d(ov7670_data), .fb_addr(wr_addr), .fb_data(wr_data), .fb_we(wr_en)
    );

    // sw[1] = freeze frame (stop writing to buffer = still photo)
    wire freeze_frame = sw[1];

    cam_framebuffer u_fb (
        .wr_clk(ov7670_pclk), .wr_en(wr_en & cam_stream_en & ~freeze_frame), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_clk(pclk), .rd_addr(rd_addr), .rd_data(rd_data)
    );

    wire [3:0] cam_vga_r, cam_vga_g, cam_vga_b;
    vga_cam_display u_cam_vga (
        .pclk(pclk), .rst_n(rst_n_sync), .hcount(vga_hcount), .vcount(vga_vcount), .active(vga_active_gen),
        .fb_addr(rd_addr), .fb_data(rd_data),
        .vga_r(cam_vga_r), .vga_g(cam_vga_g), .vga_b(cam_vga_b)
    );

    // VGA PIP OVERLAY LOGIC
    // Window is at (400, 50) to (560, 170)
    wire in_cam_window = (vga_hcount >= 10'd400 && vga_hcount < 10'd560 && vga_vcount >= 10'd50 && vga_vcount < 10'd170);
    
    assign vga_r = (in_cam_window) ? cam_vga_r : soc_vga_r;
    assign vga_g = (in_cam_window) ? cam_vga_g : soc_vga_g;
    assign vga_b = (in_cam_window) ? cam_vga_b : soc_vga_b;
    assign vga_hsync = vga_hsync_gen;
    assign vga_vsync = vga_vsync_gen;

    reg [24:0] hb; always @(posedge pclk) hb <= hb + 1;
    assign led = {hb[24], boot_loading, sccb_ack_error, ov7670_vsync, ov7670_href, ov7670_pclk, ov7670_data[7:0], wr_en, sccb_done};
    assign uart_txd_out = soc_utx;
endmodule
