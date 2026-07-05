// ex_mem_reg.v — EX/MEM Pipeline Register
//
// flush kills all control signals (inserts a bubble).

module ex_mem_reg #(
    parameter XLEN = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              flush,

    // Data path inputs
    input  wire [XLEN-1:0]  pc_plus_4_ex,
    input  wire [XLEN-1:0]  alu_result_ex,
    input  wire [XLEN-1:0]  rs2_data_ex,   // store data
    input  wire [4:0]       rd_ex,
    input  wire [2:0]       funct3_ex,

    // Control inputs
    input  wire             reg_write_en_ex,
    input  wire             dmem_we_ex,
    input  wire             pc_to_reg_ex,
    input  wire             mem_to_reg_ex,

    // Data path outputs
    output reg  [XLEN-1:0]  pc_plus_4_mem,
    output reg  [XLEN-1:0]  alu_result_mem,
    output reg  [XLEN-1:0]  rs2_data_mem,
    output reg  [4:0]       rd_mem,
    output reg  [2:0]       funct3_mem,

    // Control outputs
    output reg              reg_write_en_mem,
    output reg              dmem_we_mem,
    output reg              pc_to_reg_mem,
    output reg              mem_to_reg_mem
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            pc_plus_4_mem    <= {XLEN{1'b0}};
            alu_result_mem   <= {XLEN{1'b0}};
            rs2_data_mem     <= {XLEN{1'b0}};
            rd_mem           <= 5'b0;
            funct3_mem       <= 3'b0;
            reg_write_en_mem <= 1'b0;
            dmem_we_mem      <= 1'b0;
            pc_to_reg_mem    <= 1'b0;
            mem_to_reg_mem   <= 1'b0;
        end else begin
            pc_plus_4_mem    <= pc_plus_4_ex;
            alu_result_mem   <= alu_result_ex;
            rs2_data_mem     <= rs2_data_ex;
            rd_mem           <= rd_ex;
            funct3_mem       <= funct3_ex;
            reg_write_en_mem <= reg_write_en_ex;
            dmem_we_mem      <= dmem_we_ex;
            pc_to_reg_mem    <= pc_to_reg_ex;
            mem_to_reg_mem   <= mem_to_reg_ex;
        end
    end

endmodule
