// forwarding_unit.v — Data Forwarding Unit
//
// Detects RAW hazards resolvable by forwarding and generates 2-bit MUX
// selectors for the ALU inputs and store data path.
//
// Encoding:  2'b00 = register file  (no forwarding)
//            2'b01 = MEM/WB result
//            2'b10 = EX/MEM result   (higher priority: more recent)

module forwarding_unit (
    input  wire [4:0]  id_ex_rs1,
    input  wire [4:0]  id_ex_rs2,

    input  wire [4:0]  ex_mem_rd,
    input  wire [4:0]  mem_wb_rd,

    input  wire        ex_mem_reg_write_en,
    input  wire        mem_wb_reg_write_en,

    output reg  [1:0]  forward_a,      // ALU operand A  (rs1)
    output reg  [1:0]  forward_b,      // ALU operand B  (rs2, before imm mux)
    output reg  [1:0]  forward_store   // Store data      (rs2, bypasses imm mux)
);

    localparam FWD_REG    = 2'b00;
    localparam FWD_MEM_WB = 2'b01;
    localparam FWD_EX_MEM = 2'b10;

    // forward_a: rs1
    always @(*) begin
        if (ex_mem_reg_write_en && ex_mem_rd != 5'b0 && ex_mem_rd == id_ex_rs1)
            forward_a = FWD_EX_MEM;
        else if (mem_wb_reg_write_en && mem_wb_rd != 5'b0 && mem_wb_rd == id_ex_rs1)
            forward_a = FWD_MEM_WB;
        else
            forward_a = FWD_REG;
    end

    // forward_b / forward_store: both depend on rs2; computed once, assigned twice
    always @(*) begin
        if (ex_mem_reg_write_en && ex_mem_rd != 5'b0 && ex_mem_rd == id_ex_rs2)
            {forward_b, forward_store} = {FWD_EX_MEM, FWD_EX_MEM};
        else if (mem_wb_reg_write_en && mem_wb_rd != 5'b0 && mem_wb_rd == id_ex_rs2)
            {forward_b, forward_store} = {FWD_MEM_WB, FWD_MEM_WB};
        else
            {forward_b, forward_store} = {FWD_REG, FWD_REG};
    end

endmodule
