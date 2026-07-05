// char_buffer.v — 80×30 VGA character + color buffer (true dual-port BRAM)
//
// Port A (clk_a, sys_clk): CPU write
// Port B (clk_b, pclk):    VGA read (synchronous, 1-cycle latency)
//
// Cell format [15:0]:
//   [7:0]   ASCII character code
//   [11:8]  foreground color (4-bit CGA index)
//   [15:12] background color (4-bit CGA index)
//
// Address space: 0..4095 (12-bit). Only 0..2399 are used
//   (80 columns × 30 rows). Unused entries are never accessed.

module char_buffer (
    // Port A — CPU write
    input  wire        clk_a,
    input  wire        we_a,
    input  wire [11:0] addr_a,
    input  wire [15:0] wdata_a,

    // Port B — VGA read
    input  wire        clk_b,
    input  wire [11:0] addr_b,
    output reg  [15:0] rdata_b
);
    (* ram_style = "block" *)
    reg [15:0] mem [0:4095];

    // Initialise to white-on-black space so display is blank at reset
    integer i;
    initial begin
        for (i = 0; i < 4096; i = i + 1)
            mem[i] = 16'h0F20;   // fg=white(0xF), bg=black(0x0), char=SPACE(0x20)
    end

    // Write port (sys_clk domain)
    always @(posedge clk_a) begin
        if (we_a)
            mem[addr_a] <= wdata_a;
    end

    // Read port (pixel clock domain)
    always @(posedge clk_b) begin
        rdata_b <= mem[addr_b];
    end

endmodule
