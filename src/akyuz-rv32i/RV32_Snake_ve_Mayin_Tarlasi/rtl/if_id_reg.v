// if_id_reg.v — IF/ID Pipeline Register
//
// flush inserts a NOP (ADDI x0, x0, 0) and clears the PC fields.
// stall holds the current values unchanged.
// flush takes priority over stall.

module if_id_reg #(
    parameter XLEN = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              flush,
    input  wire              stall,

    input  wire [XLEN-1:0]  pc_if,
    input  wire [XLEN-1:0]  pc_plus_4_if,
    input  wire [31:0]       instr_if,

    output reg  [XLEN-1:0]  pc_id,
    output reg  [XLEN-1:0]  pc_plus_4_id,
    output reg  [31:0]       instr_id
);

    localparam NOP = 32'h0000_0013; // ADDI x0, x0, 0

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            pc_id        <= {XLEN{1'b0}};
            pc_plus_4_id <= {XLEN{1'b0}};
            instr_id     <= NOP;
        end else if (!stall) begin
            pc_id        <= pc_if;
            pc_plus_4_id <= pc_plus_4_if;
            instr_id     <= instr_if;
        end
    end

endmodule
