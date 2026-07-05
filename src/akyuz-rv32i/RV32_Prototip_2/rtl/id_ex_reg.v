`timescale 1ns / 1ps

// ID/EX Pipeline Register - Prototip 2
// Degisiklik: funct3 eklenmisti (Prototip-1'de de vardi), ayni kalir.

module id_ex_reg #(
    parameter XLEN = 32
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             flush,
    input  wire             stall,

    // IF/ID'den gelenler
    input  wire [XLEN-1:0]  pc_plus_4_id,
    input  wire [XLEN-1:0]  pc_id,
    input  wire [XLEN-1:0]  rs1_data_id,
    input  wire [XLEN-1:0]  rs2_data_id,
    input  wire [XLEN-1:0]  imm_id,
    input  wire [4:0]       rs1_id,
    input  wire [4:0]       rs2_id,
    input  wire [4:0]       rd_id,
    input  wire [2:0]       funct3_id,

    // Kontrol Sinyalleri (ID)
    input  wire [3:0]       alu_op_id,
    input  wire             alu_src_id,
    input  wire [1:0]       alu_a_sel_id,
    input  wire             reg_write_en_id,
    input  wire             dmem_we_id,
    input  wire             branch_en_id,
    input  wire             jal_en_id,
    input  wire             jalr_en_id,
    input  wire             pc_to_reg_id,
    input  wire             mem_to_reg_id,

    // EX Cikislari
    output reg  [XLEN-1:0]  pc_plus_4_ex,
    output reg  [XLEN-1:0]  pc_ex,
    output reg  [XLEN-1:0]  rs1_data_ex,
    output reg  [XLEN-1:0]  rs2_data_ex,
    output reg  [XLEN-1:0]  imm_ex,
    output reg  [4:0]       rs1_ex,
    output reg  [4:0]       rs2_ex,
    output reg  [4:0]       rd_ex,
    output reg  [2:0]       funct3_ex,

    // Kontrol Sinyalleri (EX)
    output reg  [3:0]       alu_op_ex,
    output reg              alu_src_ex,
    output reg  [1:0]       alu_a_sel_ex,
    output reg              reg_write_en_ex,
    output reg              dmem_we_ex,
    output reg              branch_en_ex,
    output reg              jal_en_ex,
    output reg              jalr_en_ex,
    output reg              pc_to_reg_ex,
    output reg              mem_to_reg_ex
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_plus_4_ex    <= 0;
            pc_ex           <= 0;
            rs1_data_ex     <= 0;
            rs2_data_ex     <= 0;
            imm_ex          <= 0;
            rs1_ex          <= 0;
            rs2_ex          <= 0;
            rd_ex           <= 0;
            funct3_ex       <= 0;

            alu_op_ex       <= 0;
            alu_src_ex      <= 0;
            alu_a_sel_ex    <= 0;
            reg_write_en_ex <= 0;
            dmem_we_ex      <= 0;
            branch_en_ex    <= 0;
            jal_en_ex       <= 0;
            jalr_en_ex      <= 0;
            pc_to_reg_ex    <= 0;
            mem_to_reg_ex   <= 0;

        end else if (flush) begin
            // Flush (Bubble): Kontrol sinyallerini OLDUR
            reg_write_en_ex <= 0;
            dmem_we_ex      <= 0;
            branch_en_ex    <= 0;
            jal_en_ex       <= 0;
            jalr_en_ex      <= 0;
            mem_to_reg_ex   <= 0;
            pc_to_reg_ex    <= 0;
            rd_ex           <= 0;
            alu_op_ex       <= 0;
            alu_a_sel_ex    <= 0;

        end else if (!stall) begin
            pc_plus_4_ex    <= pc_plus_4_id;
            pc_ex           <= pc_id;
            rs1_data_ex     <= rs1_data_id;
            rs2_data_ex     <= rs2_data_id;
            imm_ex          <= imm_id;
            rs1_ex          <= rs1_id;
            rs2_ex          <= rs2_id;
            rd_ex           <= rd_id;
            funct3_ex       <= funct3_id;

            alu_op_ex       <= alu_op_id;
            alu_src_ex      <= alu_src_id;
            alu_a_sel_ex    <= alu_a_sel_id;
            reg_write_en_ex <= reg_write_en_id;
            dmem_we_ex      <= dmem_we_id;
            branch_en_ex    <= branch_en_id;
            jal_en_ex       <= jal_en_id;
            jalr_en_ex      <= jalr_en_id;
            pc_to_reg_ex    <= pc_to_reg_id;
            mem_to_reg_ex   <= mem_to_reg_id;
        end
    end

endmodule
