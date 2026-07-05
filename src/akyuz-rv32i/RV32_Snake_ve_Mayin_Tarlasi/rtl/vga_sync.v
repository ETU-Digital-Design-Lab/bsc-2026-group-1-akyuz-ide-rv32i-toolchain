// vga_sync.v — VGA 640×480 @ 60 Hz timing generator
//
// Pixel clock: 25 MHz
// H: 640 visible | 16 FP | 96 sync | 48 BP = 800 total
// V: 480 visible | 10 FP |  2 sync | 33 BP = 525 total
// Both sync pulses: negative polarity
//
// hcount/vcount are registered pixel counters (0..799, 0..524).
// hsync, vsync, active are combinational outputs derived from counters.

module vga_sync (
    input  wire        pclk,
    input  wire        rst_n,
    output reg  [9:0]  hcount,
    output reg  [9:0]  vcount,
    output wire        hsync,
    output wire        vsync,
    output wire        active
);
    localparam H_VIS  = 640;
    localparam H_FP   = 16;
    localparam H_SYNC = 96;
    localparam H_BP   = 48;
    localparam H_TOT  = 800;

    localparam V_VIS  = 480;
    localparam V_FP   = 10;
    localparam V_SYNC = 2;
    localparam V_BP   = 33;
    localparam V_TOT  = 525;

    always @(posedge pclk) begin
        if (hcount == H_TOT - 1) begin
            hcount <= 10'd0;
            vcount <= (vcount == V_TOT - 1) ? 10'd0 : vcount + 10'd1;
        end else begin
            hcount <= hcount + 10'd1;
        end
    end

    // Negative-polarity sync pulses (combinational)
    assign hsync  = ~((hcount >= H_VIS + H_FP) &&
                      (hcount <  H_VIS + H_FP + H_SYNC));
    assign vsync  = ~((vcount >= V_VIS + V_FP) &&
                      (vcount <  V_VIS + V_FP + V_SYNC));
    assign active =   (hcount < H_VIS) && (vcount < V_VIS);

endmodule
