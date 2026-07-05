// 160x120 x 8-bit = 153,600 bits ~ 10x BRAM18 (out of 50 on Basys3)
module cam_framebuffer (
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [14:0] wr_addr,
    input  wire [7:0]  wr_data,
    input  wire        rd_clk,
    input  wire [14:0] rd_addr,
    output reg  [7:0]  rd_data
);
    (* ram_style = "block" *)
    reg [7:0] mem [0:19199];

    always @(posedge wr_clk) begin
        if (wr_en) mem[wr_addr] <= wr_data;
    end

    always @(posedge rd_clk) begin
        rd_data <= mem[rd_addr];
    end
endmodule
