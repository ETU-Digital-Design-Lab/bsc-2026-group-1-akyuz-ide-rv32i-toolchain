/*
 * IF/ID Pipeline Register
 * 
 * Holds instruction and PC+4 from Instruction Fetch stage
 * to Instruction Decode stage.
 */

module if_id_reg #(
    parameter XLEN = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              flush,      // Flush signal (for branch/jump)
    input  wire              stall,      // Stall signal (for load-use hazard)
    
    // Inputs from IF stage
    input  wire [XLEN-1:0]  pc_plus_4_if,
    input  wire [31:0]       instruction_if,
    input  wire [XLEN-1:0]  pc_if,          // Actual PC value (for jump calculations)
    
    // Outputs to ID stage
    output reg  [XLEN-1:0]  pc_plus_4_id,
    output reg  [31:0]       instruction_id,
    output reg  [XLEN-1:0]  pc_id           // Actual PC value
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_plus_4_id  <= {XLEN{1'b0}};
            instruction_id <= 32'h00000013;  // NOP instruction (ADDI x0, x0, 0)
            pc_id          <= {XLEN{1'b0}};
        end else if (flush || stall) begin
            // Flush: Clear pipeline register (insert NOP)
            // Stall: Keep current values (don't update)
            if (flush) begin
                pc_plus_4_id  <= {XLEN{1'b0}};
                instruction_id <= 32'h00000013;  // NOP
                pc_id          <= {XLEN{1'b0}};
            end
            // If stall, don't update (keep current values)
        end else begin
            // Normal operation: pass data through
            pc_plus_4_id  <= pc_plus_4_if;
            instruction_id <= instruction_if;
            pc_id          <= pc_if;
        end
    end

endmodule
