// basys3_soc_cam_top.v — Merged RISC-V SoC + OV7670 Camera Top-Level
module basys3_soc_cam_top #(
    parameter IMEM_FILE = "snake_mayin.hex",
    parameter FONT_FILE = "font8x16.hex",
    parameter CAM_SAMPLE_POSEDGE = 1,
    parameter CAM_SWAP_RGB565_BYTES = 0
) (
    input  wire clk100,
    input  wire btn_rst,   // Center Button (Reset)
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
    
    // Camera interface
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

    // =========================================================================
    // Clocking & Resets
    // =========================================================================
    // MMCM: 100 MHz -> 50 MHz (SoC) + 25 MHz (VGA pixel / kamera XCLK).
    // Ripple bolucu yerine MMCM: XCLK jitter'i duser ve Vivado saatleri
    // otomatik turetir -> tum tasarim zamanlama kisiti altinda kalir.
    wire clk_fb, clk_soc_raw, pclk_raw, mmcm_locked;
    MMCME2_BASE #(
        .CLKIN1_PERIOD   (10.000),
        .CLKFBOUT_MULT_F (10.000),  // VCO = 1000 MHz
        .CLKOUT0_DIVIDE_F(20.000),  // 50 MHz
        .CLKOUT1_DIVIDE  (40),      // 25 MHz
        .DIVCLK_DIVIDE   (1)
    ) u_mmcm (
        .CLKIN1  (clk100),
        .CLKFBIN (clk_fb),
        .CLKFBOUT(clk_fb),
        .CLKOUT0 (clk_soc_raw),
        .CLKOUT1 (pclk_raw),
        .RST     (1'b0),
        .PWRDWN  (1'b0),
        .LOCKED  (mmcm_locked)
    );

    wire clk_soc; // 50 MHz
    BUFG u_clk_buf (.I(clk_soc_raw), .O(clk_soc));
    wire pclk;    // 25 MHz
    BUFG u_pclk_buf (.I(pclk_raw), .O(pclk));

    assign ov7670_xclk = pclk;

    // Synchronize Reset (Controlled by SW0); MMCM kilitlenene kadar resette tut
    reg [1:0] rst_sync = 2'b00;
    wire rst_n_sync;
    always @(posedge clk_soc or posedge sw[0]) begin
        if (sw[0]) rst_sync <= 2'b00;
        else       rst_sync <= {rst_sync[0], mmcm_locked};
    end
    assign rst_n_sync = rst_sync[1];

    // =========================================================================
    // RISC-V SoC Components
    // =========================================================================
    wire [15:0] soc_led;
    wire soc_utx, vga_we;
    wire [11:0] vga_adr;
    wire [15:0] vga_dat;

    wire boot_loading;
    wire cam_en;   // yazilim kontrollu kamera goruntusu (0x0002_0018)
    rv32_soc #(.IMEM_FILE(IMEM_FILE), .IMEM_DEPTH(4096), .UART_DIV(434)) u_soc (
        .clk(clk_soc), .rst_n(rst_n_sync), .sw(sw), .btn({btn_rst, btn_u, btn_d, btn_r, btn_l}),
        .led(soc_led), .uart_tx(soc_utx), .uart_rx(uart_rxd_in),
        .vga_char_we(vga_we), .vga_char_addr(vga_adr), .vga_char_wdata(vga_dat),
        .boot_loading(boot_loading), .cam_en(cam_en)
    );

    wire [11:0] cb_adr_b; wire [15:0] cb_dat_b; wire [4:0] s_base; wire g_mode;
    vga_terminal u_term (
        .clk(clk_soc), .pclk(pclk), .rst_n(rst_n_sync), .cpu_we(vga_we),
        .cpu_reg(vga_adr[1:0]), .cpu_data(vga_dat), .cb_addr_b(cb_adr_b),
        .cb_rdata_b(cb_dat_b), .scroll_base(s_base), .graphics_mode(g_mode)
    );

    wire [3:0] soc_vga_r, soc_vga_g, soc_vga_b;
    wire soc_vga_hsync, soc_vga_vsync;
    vga_text_ctrl #(.FONT_FILE(FONT_FILE)) u_soc_vga (
        .pclk(pclk), .rst_n(rst_n_sync), .scroll_base(s_base), .graphics_mode(g_mode),
        .cb_addr_b(cb_adr_b), .cb_rdata_b(cb_dat_b), .vga_r(soc_vga_r), .vga_g(soc_vga_g), .vga_b(soc_vga_b),
        .vga_hsync(soc_vga_hsync), .vga_vsync(soc_vga_vsync)
    );

    // =========================================================================
    // Camera & Buffer Components
    // =========================================================================
    wire sccb_done;
    wire sccb_ack_error;
    ov7670_sccb_init u_cfg (
        .clk(clk100), .rst_n(rst_n_sync), .sioc(ov7670_sioc), .siod(ov7670_siod),
        .done(sccb_done), .ack_error(sccb_ack_error), .cam_reset_n(ov7670_reset), .cam_pwdn(ov7670_pwdn)
    );

    wire [16:0] wr_addr, rd_addr;
    wire [11:0] wr_data, rd_data;
    wire wr_en;

    // Synchronize SCCB-done into camera pixel clock domain to avoid
    // unsafe async control on BRAM EN/WE paths.
    reg [1:0] cam_done_sync = 2'b00;
    always @(posedge ov7670_pclk) begin
        // Keep this path reset-free to avoid async-control BRAM DRC (REQP-1839).
        cam_done_sync <= {cam_done_sync[0], sccb_done};
    end
    wire cam_stream_en = cam_done_sync[1];
    wire cam_ready = cam_stream_en;

    ov7670_capture #(
        .SAMPLE_POSEDGE(CAM_SAMPLE_POSEDGE),
        .SWAP_RGB565_BYTES(CAM_SWAP_RGB565_BYTES)
    ) u_cap (
        .pclk(ov7670_pclk), .rst_n(rst_n_sync), .vsync(ov7670_vsync), .href(ov7670_href),
        .d(ov7670_data), .fb_addr(wr_addr), .fb_data(wr_data), .fb_we(wr_en)
    );

    // SCCB done'a bagimli degil: kamera ham akarken bile framebuffer'a yaz
    // (SCCB basarisiz olsa bile goruntu ekrana gelir -> boru hatti dogrulanir)
    cam_framebuffer u_fb (
        .wr_clk(ov7670_pclk), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_clk(pclk), .rd_addr(rd_addr), .rd_data(rd_data)
    );

    wire [3:0] cam_vga_r, cam_vga_g, cam_vga_b;
    wire cam_vga_hsync, cam_vga_vsync;
    vga_cam_display u_cam_vga (
        .pclk(pclk), .rst_n(rst_n_sync), .fb_addr(rd_addr), .fb_data(rd_data),
        .vga_r(cam_vga_r), .vga_g(cam_vga_g), .vga_b(cam_vga_b),
        .vga_hsync(cam_vga_hsync), .vga_vsync(cam_vga_vsync)
    );

    // =========================================================================
    // VGA MUX & LED Interface (Diagnostics Restored)
    // =========================================================================
    // Kamera goruntusu: SW[15] VEYA yazilim (menu 3.CAMERA) ile secilir.
    // SCCB done sartini kaldirdik -> kamera akarken her zaman gosterilir.
    wire display_select = sw[15] | cam_en;
    wire _unused_cam_ready = cam_ready; // sentez uyarisini bastir

    assign vga_r = display_select ? cam_vga_r : soc_vga_r;
    assign vga_g = display_select ? cam_vga_g : soc_vga_g;
    assign vga_b = display_select ? cam_vga_b : soc_vga_b;
    assign vga_hsync = display_select ? cam_vga_hsync : soc_vga_hsync;
    assign vga_vsync = display_select ? cam_vga_vsync : soc_vga_vsync;

    // =========================================================================
    // TANI (DIAGNOSTIC) LED'leri
    // =========================================================================
    // Ham pin seviyesi yerine AKTIVITE sayilir: bosta pin sabit kalir -> LED
    // sonuk; kamera pini gercekten suruyorsa toggle olur -> LED yanip soner.
    // clk_soc (50 MHz) her zaman calisir, kamera saatine bagimli degildir.
    reg [24:0] heartbeat_cnt;
    always @(posedge clk_soc) heartbeat_cnt <= heartbeat_cnt + 1'b1;

    reg vs_d, hr_d, pc_d;
    reg [7:0] dat_d;
    reg [22:0] vs_cnt, hr_cnt, pc_cnt, dat_cnt;
    always @(posedge clk_soc) begin
        vs_d  <= ov7670_vsync;
        hr_d  <= ov7670_href;
        pc_d  <= ov7670_pclk;
        dat_d <= ov7670_data;
        if (ov7670_vsync ^ vs_d) vs_cnt  <= vs_cnt  + 1'b1;  // VSYNC kenari
        if (ov7670_href  ^ hr_d) hr_cnt  <= hr_cnt  + 1'b1;  // HREF kenari
        if (ov7670_pclk  ^ pc_d) pc_cnt  <= pc_cnt  + 1'b1;  // PCLK kenari
        if (ov7670_data != dat_d) dat_cnt <= dat_cnt + 1'b1; // D[7:0] degisimi
    end

    // LED haritasi (TANI):
    // led[15] : Heartbeat        -> FPGA canli (her zaman yanip soner)
    // led[14] : Bootloader       -> UART yuklemede yanar
    // led[5]  : DATA aktivite    -> D0-D7 (JB2,8,3,9,4,10 / JC1,7) veri geliyor
    // led[4]  : HREF aktivite    -> HREF  (JC3) satir sinyali geliyor
    // led[3]  : VSYNC aktivite   -> VSYNC (JC9) kare sinyali geliyor
    // led[2]  : PCLK aktivite    -> PCLK  (JC8) kamera saati canli (XCLK+guc OK)
    // led[1]  : SCCB ACK hatasi  -> SIOC/SIOD (JC10/JC4) veya pull-up sorunu
    // led[0]  : SCCB config OK   -> kamera tam konfigure edildi
    assign led[15]   = heartbeat_cnt[24];
    assign led[14]   = boot_loading;
    assign led[13:6] = 8'd0;
    assign led[5]    = dat_cnt[20];
    assign led[4]    = hr_cnt[14];
    assign led[3]    = vs_cnt[5];
    assign led[2]    = pc_cnt[22];
    assign led[1]    = sccb_ack_error;
    assign led[0]    = sccb_done;

    assign uart_txd_out = soc_utx;

endmodule
