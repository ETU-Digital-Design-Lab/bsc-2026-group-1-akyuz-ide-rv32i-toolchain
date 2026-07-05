

module rv32_alu #(
    parameter XLEN = 32
)(
    input  wire [XLEN-1:0] alu_in1,
    input  wire [XLEN-1:0] alu_in2,
    input  wire [3:0]      alu_op,

    output reg  [XLEN-1:0] alu_result,
    output wire            zero,   // alu_result == 0
    output wire            lt,     // $signed(in1) < $signed(in2)
    output wire            ltu     // in1 < in2 (unsigned)
);

    localparam ALU_ADD    = 4'b0000;
    localparam ALU_SUB    = 4'b0001;
    localparam ALU_AND    = 4'b0010;
    localparam ALU_OR     = 4'b0011;
    localparam ALU_XOR    = 4'b0100;
    localparam ALU_SLT    = 4'b0101;
    localparam ALU_SLTU   = 4'b0110;
    localparam ALU_SLL    = 4'b0111;
    localparam ALU_SRL    = 4'b1000;
    localparam ALU_SRA    = 4'b1001;
    localparam ALU_PASS_B = 4'b1010;

    wire [4:0] shamt = alu_in2[4:0];

    always @(*) begin
        case (alu_op)
            ALU_ADD:    alu_result = alu_in1 + alu_in2;
            ALU_SUB:    alu_result = alu_in1 - alu_in2;
            ALU_AND:    alu_result = alu_in1 & alu_in2;
            ALU_OR:     alu_result = alu_in1 | alu_in2;
            ALU_XOR:    alu_result = alu_in1 ^ alu_in2;
            ALU_SLT:    alu_result = ($signed(alu_in1) < $signed(alu_in2))
                                     ? {{(XLEN-1){1'b0}}, 1'b1} : {XLEN{1'b0}};
            ALU_SLTU:   alu_result = (alu_in1 < alu_in2)
                                     ? {{(XLEN-1){1'b0}}, 1'b1} : {XLEN{1'b0}};
            ALU_SLL:    alu_result = alu_in1 << shamt;
            ALU_SRL:    alu_result = alu_in1 >> shamt;
            ALU_SRA:    alu_result = $signed(alu_in1) >>> shamt;
            ALU_PASS_B: alu_result = alu_in2;
            default:    alu_result = {XLEN{1'b0}};
        endcase
    end

    assign zero = (alu_result == {XLEN{1'b0}});
    assign lt   = ($signed(alu_in1) < $signed(alu_in2));
    assign ltu  = (alu_in1 < alu_in2);

endmodule
