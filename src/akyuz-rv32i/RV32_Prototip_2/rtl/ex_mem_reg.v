`timescale 1ns / 1ps

// EX/MEM Pipeline Register - Prototip 2
//
// Degisiklik (Prototip-1'den farklar):
//   - funct3_ex -> funct3_mem eklendi (byte/halfword load/store icin)
//   - MEM asamasinda funct3 ile byte-enable ve load sign-extension yapilacak

module ex_mem_reg #(
    parameter XLEN = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              flush_ex_mem,

    // EX asamasindan gelenler
    input  wire [XLEN-1:0]  pc_plus_4_ex,
    input  wire [XLEN-1:0]  alu_result_ex,
    input  wire [XLEN-1:0]  rs2_data_ex,
    input  wire [4:0]       rd_ex,
    input  wire [2:0]       funct3_ex,        // YENI: funct3 MEM'e tasiniyor

    // Kontrol sinyalleri (EX)
    input  wire             reg_write_en_ex,
    input  wire             dmem_we_ex,
    input  wire             pc_to_reg_ex,
    input  wire             mem_to_reg_ex,

    // MEM asamasina cikislar
    output reg  [XLEN-1:0]  pc_plus_4_mem,
    output reg  [XLEN-1:0]  alu_result_mem,
    output reg  [XLEN-1:0]  rs2_data_mem,
    output reg  [4:0]       rd_mem,
    output reg  [2:0]       funct3_mem,       // YENI

    // Kontrol sinyalleri (MEM)
    output reg              reg_write_en_mem,
    output reg              dmem_we_mem,
    output reg              pc_to_reg_mem,
    output reg              mem_to_reg_mem
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_plus_4_mem    <= {XLEN{1'b0}};
            alu_result_mem   <= {XLEN{1'b0}};
            rs2_data_mem     <= {XLEN{1'b0}};
            rd_mem           <= 5'b0;
            funct3_mem       <= 3'b0;
            reg_write_en_mem <= 1'b0;
            dmem_we_mem      <= 1'b0;
            pc_to_reg_mem    <= 1'b0;
            mem_to_reg_mem   <= 1'b0;
        end else if (flush_ex_mem) begin
            // Flush: Kontrol sinyallerini sifirla
            reg_write_en_mem <= 1'b0;
            dmem_we_mem      <= 1'b0;
            pc_to_reg_mem    <= 1'b0;
            mem_to_reg_mem   <= 1'b0;
            rd_mem           <= 5'b0;
            funct3_mem       <= 3'b0;
            // Veri yollari gecebilir (kontrol 0 iken zararsiz)
            pc_plus_4_mem    <= pc_plus_4_ex;
            alu_result_mem   <= alu_result_ex;
            rs2_data_mem     <= rs2_data_ex;
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
