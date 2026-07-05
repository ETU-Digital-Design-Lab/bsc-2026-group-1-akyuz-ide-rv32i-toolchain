module cam_framebuffer (
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [16:0] wr_addr,
    input  wire [11:0] wr_data,
    input  wire        rd_clk,
    input  wire [16:0] rd_addr,
    output reg  [11:0] rd_data
);
    // 160x120 = 19200 piksel (BRAM tasarrufu icin dusuk cozunurluk;
    // ekranda 4x buyutulerek 640x480 doldurulur)
    reg [11:0] mem [0:19199];

    always @(posedge wr_clk) begin
        if (wr_en) mem[wr_addr] <= wr_data;
    end

    always @(posedge rd_clk) begin
        rd_data <= mem[rd_addr];
    end
endmodule
