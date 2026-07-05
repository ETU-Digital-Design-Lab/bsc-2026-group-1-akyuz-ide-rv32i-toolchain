// regfile.v — RV32I Register File (x0–x31)
//
// Two combinational read ports, one synchronous write port.
// x0 is hardwired to zero. Write-through: WB–ID same-cycle conflict
// is resolved by forwarding the write data directly to the read output.

module regfile #(
    parameter XLEN      = 32,
    parameter REG_COUNT = 32
)(
    input  wire              clk,
    input  wire              rst_n,

    input  wire [4:0]        rs1_addr,
    input  wire [4:0]        rs2_addr,
    output wire [XLEN-1:0]   rs1_data,
    output wire [XLEN-1:0]   rs2_data,

    input  wire [4:0]        rd_addr,
    input  wire [XLEN-1:0]   rd_data,
    input  wire              rd_we
);

    integer i;
    reg [XLEN-1:0] regs [0:REG_COUNT-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < REG_COUNT; i = i + 1)
                regs[i] <= {XLEN{1'b0}};
        end else begin
            if (rd_we && rd_addr != 5'd0)
                regs[rd_addr] <= rd_data;
        end
    end

    assign rs1_data = (rs1_addr == 5'd0)             ? {XLEN{1'b0}} :
                      (rd_we && rd_addr == rs1_addr) ? rd_data       :
                      regs[rs1_addr];

    assign rs2_data = (rs2_addr == 5'd0)             ? {XLEN{1'b0}} :
                      (rd_we && rd_addr == rs2_addr) ? rd_data       :
                      regs[rs2_addr];

endmodule
