/*
 * Forwarding Unit
 * 
 * Detects data hazards and generates forwarding control signals.
 * 
 * Logic:
 * - Compare ID_EX_Rs1/Rs2 with EX_MEM_Rd and MEM_WB_Rd
 * - If match and RegWrite is enabled, forward data from later stages
 * - Priority: EX_MEM > MEM_WB (EX_MEM is more recent)
 */

module forwarding_unit (
    // Register addresses from ID/EX stage (instruction in EX)
    input  wire [4:0]  id_ex_rs1,
    input  wire [4:0]  id_ex_rs2,
    
    // Register addresses from EX/MEM and MEM/WB stages
    input  wire [4:0]  ex_mem_rd,
    input  wire [4:0]  mem_wb_rd,
    
    // Control signals indicating if registers will be written
    input  wire        ex_mem_reg_write_en,
    input  wire        mem_wb_reg_write_en,
    
    // Forwarding control signals (2-bit MUX selectors)
    output reg  [1:0] forward_a,      // Forwarding for ALU input A (rs1)
    output reg  [1:0] forward_b,      // Forwarding for ALU input B (rs2)
    output reg  [1:0] forward_store   // Forwarding for store data (rs2)
);

    // Forwarding MUX encoding:
    // 00 = No forwarding (use register file data)
    // 01 = Forward from MEM/WB stage
    // 10 = Forward from EX/MEM stage
    // 11 = Reserved (not used)
    
    localparam FORWARD_NONE = 2'b00;
    localparam FORWARD_MEM_WB = 2'b01;
    localparam FORWARD_EX_MEM = 2'b10;

    // Forwarding for ALU input A (rs1)
    always @(*) begin
        // Priority: EX_MEM > MEM_WB
        if (ex_mem_reg_write_en && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs1)) begin
            // Forward from EX/MEM stage
            forward_a = FORWARD_EX_MEM;
        end else if (mem_wb_reg_write_en && (mem_wb_rd != 5'b0) && (mem_wb_rd == id_ex_rs1)) begin
            // Forward from MEM/WB stage
            forward_a = FORWARD_MEM_WB;
        end else begin
            // No forwarding (use register file)
            forward_a = FORWARD_NONE;
        end
    end

    // Forwarding for ALU input B (rs2)
    always @(*) begin
        // Priority: EX_MEM > MEM_WB
        if (ex_mem_reg_write_en && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs2)) begin
            // Forward from EX/MEM stage
            forward_b = FORWARD_EX_MEM;
        end else if (mem_wb_reg_write_en && (mem_wb_rd != 5'b0) && (mem_wb_rd == id_ex_rs2)) begin
            // Forward from MEM/WB stage
            forward_b = FORWARD_MEM_WB;
        end else begin
            // No forwarding (use register file)
            forward_b = FORWARD_NONE;
        end
    end

    // Forwarding for store data (rs2) - CRITICAL for store instructions
    // Store instructions need rs2 data to be written to memory
    // This is separate from forward_b because store data goes directly to memory,
    // not through ALU input B (which uses immediate for address calculation)
    always @(*) begin
        // Priority: EX_MEM > MEM_WB
        if (ex_mem_reg_write_en && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs2)) begin
            // Forward from EX/MEM stage
            forward_store = FORWARD_EX_MEM;
        end else if (mem_wb_reg_write_en && (mem_wb_rd != 5'b0) && (mem_wb_rd == id_ex_rs2)) begin
            // Forward from MEM/WB stage
            forward_store = FORWARD_MEM_WB;
        end else begin
            // No forwarding (use register file)
            forward_store = FORWARD_NONE;
        end
    end

endmodule
