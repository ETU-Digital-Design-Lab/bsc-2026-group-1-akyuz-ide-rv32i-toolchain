// vga_terminal.v — Hardware VGA terminal controller (80×30 text, virtual scroll)
//
// Abstracts the char_buffer so the CPU never computes VGA addresses.
//
// CPU Register Map (0x0003_xxxx, decoded by cpu_reg = addr[1:0]):
//   2'b00  DATA   (W): write char cell; [15:12]=bg, [11:8]=fg, [7:0]=ASCII
//                      cursor advances automatically; \n and \r handled in HW
//   2'b01  CURSOR (W): set cursor; [12:8]=row (0-29), [6:0]=col (0-79)
//   2'b10  CTRL   (W): bit[0] = clear screen, bit[1] = GRAPHICS MODE (Intro)
//
// Virtual scroll: scroll_base points to the physical char_buffer row that is
//   shown as display row 0.  No data is ever copied; the display simply reads
//   from a shifted window: phys_row = (display_row + scroll_base) % 30.
//   When cursor overflows row 29, scroll_base increments and the new bottom
//   row is erased (80 BRAM writes = 1.6 µs @ 50 MHz).
//
// Port B (pclk domain) is a direct pass-through to/from char_buffer for
//   vga_text_ctrl; vga_text_ctrl already accounts for scroll_base.

module vga_terminal (
    input  wire        clk,          // sys_clk (50 MHz)
    input  wire        pclk,         // pixel clock (25 MHz) for char_buffer port B
    input  wire        rst_n,

    // CPU write interface (from rv32_soc via fpga_top)
    input  wire        cpu_we,       // single-cycle write strobe
    input  wire [1:0]  cpu_reg,      // register select: 0=data, 1=cursor, 2=ctrl
    input  wire [15:0] cpu_data,     // write data

    // char_buffer port B — pass-through for vga_text_ctrl
    input  wire [11:0] cb_addr_b,    // scroll-adjusted address from vga_text_ctrl
    output wire [15:0] cb_rdata_b,   // char+color data back to vga_text_ctrl

    // Scroll state output — consumed by vga_text_ctrl for address adjustment
    output wire [4:0]  scroll_base,
    output wire        graphics_mode // bit[1] of CTRL register
);

    // =========================================================================
    // State machine
    // =========================================================================
    localparam [1:0]
        IDLE       = 2'd0,
        WRITE_CHAR = 2'd1,
        SCROLL_CLR = 2'd2,
        CLR_SCREEN = 2'd3;

    reg [1:0]  state;

    // Cursor and scroll state
    reg [6:0]  cursor_x;       // 0..79
    reg [4:0]  cursor_y;       // 0..29
    reg [4:0]  scroll_base_r;  // 0..29
    reg        graphics_mode_r;

    // Latched CPU write data
    reg [15:0] char_data_r;

    // Clear / scroll helpers
    reg [4:0]  clr_row_r;      // physical row being cleared (SCROLL_CLR)
    reg [6:0]  clr_col_r;      // column counter (SCROLL_CLR)
    reg [11:0] clr_idx_r;      // absolute address counter (CLR_SCREEN, 0..2399)

    assign scroll_base = scroll_base_r;
    assign graphics_mode = graphics_mode_r;

    // =========================================================================
    // Physical write address helpers
    // =========================================================================
    // Cursor → physical BRAM row (scroll-adjusted)
    wire [5:0] wr_phys_sum = {1'b0, cursor_y} + {1'b0, scroll_base_r};
    wire [4:0] wr_phys_row = (wr_phys_sum >= 6'd30) ? wr_phys_sum[4:0] - 5'd30
                                                     : wr_phys_sum[4:0];
    // BRAM address for normal char write
    wire [11:0] wr_addr = ({7'b0, wr_phys_row} << 6)
                        + ({7'b0, wr_phys_row} << 4)
                        + {5'b0, cursor_x};

    // BRAM address for row-clear (SCROLL_CLR)
    wire [11:0] clr_row_addr = ({7'b0, clr_row_r} << 6)
                              + ({7'b0, clr_row_r} << 4)
                              + {5'b0, clr_col_r};

    // Character type flags (combinational from latched data)
    wire is_cr = (char_data_r[7:0] == 8'h0D);
    wire is_lf = (char_data_r[7:0] == 8'h0A);

    // =========================================================================
    // char_buffer port A drive (combinational from state)
    // =========================================================================
    reg        cb_we_a;
    reg [11:0] cb_addr_a;
    reg [15:0] cb_wdata_a;

    always @(*) begin
        case (state)
            WRITE_CHAR: begin
                cb_we_a    = ~is_cr & ~is_lf;  // no BRAM write for CR/LF
                cb_addr_a  = wr_addr;
                cb_wdata_a = char_data_r;
            end
            SCROLL_CLR: begin
                cb_we_a    = 1'b1;
                cb_addr_a  = clr_row_addr;
                cb_wdata_a = 16'h0F20;          // white-on-black space
            end
            CLR_SCREEN: begin
                cb_we_a    = 1'b1;
                cb_addr_a  = clr_idx_r;
                cb_wdata_a = 16'h0F20;
            end
            default: begin
                cb_we_a    = 1'b0;
                cb_addr_a  = 12'd0;
                cb_wdata_a = 16'h0F20;
            end
        endcase
    end

    // =========================================================================
    // char_buffer instantiation
    // =========================================================================
    char_buffer u_charbuf (
        .clk_a  (clk),
        .we_a   (cb_we_a),
        .addr_a (cb_addr_a),
        .wdata_a(cb_wdata_a),
        .clk_b  (pclk),
        .addr_b (cb_addr_b),
        .rdata_b(cb_rdata_b)
    );

    // =========================================================================
    // State machine (sys_clk domain)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            state         <= IDLE;
            cursor_x      <= 7'd0;
            cursor_y      <= 5'd0;
            scroll_base_r <= 5'd0;
            char_data_r   <= 16'h0F20;
            clr_row_r     <= 5'd0;
            clr_col_r     <= 7'd0;
            clr_idx_r     <= 12'd0;
            graphics_mode_r <= 1'b0;
        end else begin
            case (state)

                // ---------------------------------------------------------
                IDLE: begin
                    if (cpu_we) begin
                        case (cpu_reg)
                            2'b01: begin  // SET_CURSOR
                                cursor_x <= cpu_data[6:0];
                                cursor_y <= cpu_data[12:8];
                            end
                            2'b10: begin  // CTRL (bit[0]=clear, bit[1]=intro_graphics)
                                graphics_mode_r <= cpu_data[1];
                                if (cpu_data[0]) begin
                                    scroll_base_r <= 5'd0;
                                    cursor_x      <= 7'd0;
                                    cursor_y      <= 5'd0;
                                    clr_idx_r     <= 12'd0;
                                    state         <= CLR_SCREEN;
                                end
                            end
                            default: begin  // 2'b00 DATA
                                char_data_r <= cpu_data;
                                state       <= WRITE_CHAR;
                            end
                        endcase
                    end
                end

                // ---------------------------------------------------------
                WRITE_CHAR: begin
                    if (is_cr) begin
                        cursor_x <= 7'd0;
                        state    <= IDLE;
                    end else if (is_lf) begin
                        cursor_x <= 7'd0;
                        if (cursor_y == 5'd29) begin
                            clr_row_r     <= scroll_base_r;
                            scroll_base_r <= (scroll_base_r == 5'd29) ? 5'd0
                                                                        : scroll_base_r + 5'd1;
                            clr_col_r     <= 7'd0;
                            state         <= SCROLL_CLR;
                        end else begin
                            cursor_y <= cursor_y + 5'd1;
                            state    <= IDLE;
                        end
                    end else begin
                        if (cursor_x == 7'd79) begin
                            cursor_x <= 7'd0;
                            if (cursor_y == 5'd29) begin
                                clr_row_r     <= scroll_base_r;
                                scroll_base_r <= (scroll_base_r == 5'd29) ? 5'd0
                                                                            : scroll_base_r + 5'd1;
                                clr_col_r     <= 7'd0;
                                state         <= SCROLL_CLR;
                            end else begin
                                cursor_y <= cursor_y + 5'd1;
                                state    <= IDLE;
                            end
                        end else begin
                            cursor_x <= cursor_x + 7'd1;
                            state    <= IDLE;
                        end
                    end
                end

                // ---------------------------------------------------------
                SCROLL_CLR: begin
                    if (clr_col_r == 7'd79)
                        state <= IDLE;
                    else
                        clr_col_r <= clr_col_r + 7'd1;
                end

                // ---------------------------------------------------------
                CLR_SCREEN: begin
                    if (clr_idx_r == 12'd2399)
                        state <= IDLE;
                    else
                        clr_idx_r <= clr_idx_r + 12'd1;
                end

            endcase
        end
    end

endmodule
