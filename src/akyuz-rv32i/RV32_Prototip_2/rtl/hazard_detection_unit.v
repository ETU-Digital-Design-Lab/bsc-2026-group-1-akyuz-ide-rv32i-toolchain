/*
 * Hazard Detection Unit (Stall Unit)
 * 
 * Detects load-use hazards and generates stall signals.
 * 
 * Logic:
 * - Check if ID_EX_MemRead (instruction in EX is a Load) is true
 * - AND if the destination register (ID_EX_Rd) matches source registers in ID
 * - If detected, stall the pipeline
 */

module hazard_detection_unit (
    // Instruction in ID stage (current instruction being decoded)
    input  wire [4:0]  if_id_rs1,
    input  wire [4:0]  if_id_rs2,
    
    // Control signals indicating if ID stage instruction uses rs1/rs2
    input  wire        if_id_uses_rs1,  // 1 if instruction in ID uses rs1
    input  wire        if_id_uses_rs2,  // 1 if instruction in ID uses rs2
    
    // Instruction in EX stage
    input  wire [4:0]  id_ex_rd,
    input  wire        id_ex_mem_read,  // 1 if instruction in EX is a Load
    
    // Stall control signals
    output reg         stall,           // 1 = stall pipeline
    output reg         pc_write_en,      // 0 = disable PC update
    output reg         if_id_write_en,   // 0 = disable IF/ID register update
    output reg         id_ex_flush       // 1 = flush ID/EX register (inject bubble)
);

    always @(*) begin
        // Check for load-use hazard
        // Only check rs1/rs2 if the instruction actually uses them
        // This prevents false stalls for I-type instructions (rs2 is immediate)
        // and instructions like LUI/JAL that don't use rs1/rs2
        if (id_ex_mem_read && (id_ex_rd != 5'b0) && 
            ((if_id_uses_rs1 && (id_ex_rd == if_id_rs1)) || 
             (if_id_uses_rs2 && (id_ex_rd == if_id_rs2)))) begin
            // Load-use hazard detected
            stall = 1'b1;
            pc_write_en = 1'b0;      // Disable PC update
            if_id_write_en = 1'b0;   // Disable IF/ID register update
            id_ex_flush = 1'b1;      // CRITICAL: Inject bubble into ID/EX register
        end else begin
            // No hazard
            stall = 1'b0;
            pc_write_en = 1'b1;      // Enable PC update
            if_id_write_en = 1'b1;   // Enable IF/ID register update
            id_ex_flush = 1'b0;      // No flush needed
        end
    end

endmodule
