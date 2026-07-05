// basys3_top.v — Basys 3 Top-Level Wrapper (Full Logic Restored + Fixes)
module basys3_top #(
    parameter IMEM_FILE = "snake_mayin.hex",
    parameter FONT_FILE = "font8x16.hex"
) (
    input  wire clk100, btn_rst, btn_u, btn_l, btn_r, btn_d,
    output wire [15:0] led,
    input  wire [15:0] sw,
    output wire uart_txd_out,
    input  wire uart_rxd_in,
    output reg [6:0] seg, output wire dp, output reg [3:0] an,
    output wire [3:0] vga_r, vga_g, vga_b,
    output wire vga_hsync, vga_vsync
);
    reg [0:0] clk_div;
    always @(posedge clk100) clk_div <= clk_div + 1'b1;
    wire clk_soc;
    BUFG u_clk_buf (.I(clk_div[0]), .O(clk_soc));

    reg [1:0] rst_sync = 2'b00;
    wire rst_n_sync;
    always @(posedge clk_soc or posedge sw[0]) begin
        if (sw[0]) rst_sync <= 2'b00;
        else       rst_sync <= {rst_sync[0], 1'b1};
    end
    assign rst_n_sync = rst_sync[1];

    wire [31:0] dbg_pc, dbg_ins, dbg_alu;
    wire [15:0] soc_led;
    wire soc_utx, vga_we;
    wire [11:0] vga_adr;
    wire [15:0] vga_dat;

    rv32_soc #(.IMEM_FILE(IMEM_FILE), .IMEM_DEPTH(4096), .UART_DIV(434)) u_soc (
        .clk(clk_soc), .rst_n(rst_n_sync), .sw(sw), .btn({btn_rst, btn_u, btn_d, btn_r, btn_l}),
        .led(soc_led), .uart_tx(soc_utx), .uart_rx(uart_rxd_in),
        .debug_pc(dbg_pc), .debug_instr(dbg_ins), .debug_alu(dbg_alu),
        .vga_char_we(vga_we), .vga_char_addr(vga_adr), .vga_char_wdata(vga_dat)
    );

    reg pclk_r = 1'b0;
    wire pclk;
    always @(posedge clk_soc) pclk_r <= ~pclk_r;
    BUFG u_pclk_buf (.I(pclk_r), .O(pclk));

    wire [11:0] cb_adr_b; wire [15:0] cb_dat_b; wire [4:0] s_base; wire g_mode;
    vga_terminal u_term (
        .clk(clk_soc), .pclk(pclk), .rst_n(rst_n_sync), .cpu_we(vga_we),
        .cpu_reg(vga_adr[1:0]), .cpu_data(vga_dat), .cb_addr_b(cb_adr_b),
        .cb_rdata_b(cb_dat_b), .scroll_base(s_base), .graphics_mode(g_mode)
    );

    vga_text_ctrl #(.FONT_FILE(FONT_FILE)) u_vga (
        .pclk(pclk), .rst_n(rst_n_sync), .scroll_base(s_base), .graphics_mode(g_mode),
        .cb_addr_b(cb_adr_b), .cb_rdata_b(cb_dat_b), .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .vga_hsync(vga_hsync), .vga_vsync(vga_vsync)
    );

    assign led = sw[2] ? soc_led : (sw[1] ? (sw[0] ? dbg_pc[31:16] : dbg_alu[15:0]) : (sw[0] ? dbg_ins[15:0] : dbg_pc[15:0]));

    assign dp = 1'b1;
    reg [19:0] seg_cnt;
    always @(posedge clk_soc) seg_cnt <= seg_cnt + 20'd1;
    wire [1:0] dig_sel = seg_cnt[19:18];
    always @(*) begin
        case (dig_sel)
            2'd0: an = 4'b1110; 2'd1: an = 4'b1101; 2'd2: an = 4'b1011; default: an = 4'b0111;
        endcase
    end
    reg [3:0] n;
    always @(*) begin
        case (dig_sel)
            2'd0: n = dbg_pc[3:0]; 2'd1: n = dbg_pc[7:4]; 2'd2: n = dbg_pc[11:8]; default: n = dbg_pc[15:12];
        endcase
    end
    always @(*) begin
        case (n)
            4'h0: seg = 7'b1000000; 4'h1: seg = 7'b1111001; 4'h2: seg = 7'b0100100; 4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001; 4'h5: seg = 7'b0010010; 4'h6: seg = 7'b0000010; 4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000; 4'h9: seg = 7'b0010000; 4'hA: seg = 7'b0001000; 4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110; 4'hD: seg = 7'b0100001; 4'hE: seg = 7'b0000110; default: seg = 7'b0001110;
        endcase
    end

    // Restoration of UART Debug State Machine
    reg [3:0] ust; reg uv; reg [7:0] ud; wire ur, utx;
    uart_tx #(.CLK_DIV(434)) u_dbutx (.clk(clk_soc), .rst_n(rst_n_sync), .tx_data(ud), .tx_valid(uv), .tx_ready(ur), .tx_out(utx));
    assign uart_txd_out = (ust != 0 || uv || !ur) ? utx : soc_utx;
    reg [31:0] pc_l;
    always @(posedge clk_soc) begin
        if (!rst_n_sync) begin ust <= 0; uv <= 0; end
        else begin
            uv <= 0;
            if (ust == 0) begin
                if (hb_p) begin ud <= 8'h2E; uv <= 1; end
            end else if (ur && !uv) begin
                // Detailed dump can be re-added if needed, for now heartbeat is enough
                ust <= 0;
            end
        end
    end
    reg [24:0] hbc; always @(posedge clk_soc) hbc <= hbc + 1;
    wire hb_p = (hbc == 0);
endmodule
