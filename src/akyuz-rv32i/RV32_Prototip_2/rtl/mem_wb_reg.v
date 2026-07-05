`timescale 1ns / 1ps

// MEM/WB Pipeline Register - Prototip 2
//
// Degisiklik (Prototip-1'den farklar):
//   - funct3_mem -> funct3_wb eklendi (load sign-extension icin)
//   - WB asamasinda funct3 ile LB/LBU/LH/LHU/LW ayirt edilecek

module mem_wb_reg #(
    parameter XLEN = 32
)(
    input  wire              clk,
    input  wire              rst_n,

    // MEM asamasindan gelenler
    input  wire [XLEN-1:0]  pc_plus_4_mem,
    input  wire [XLEN-1:0]  alu_result_mem,
    input  wire [XLEN-1:0]  dmem_rdata_mem,
    input  wire [4:0]       rd_mem,
    input  wire [2:0]       funct3_mem,       // YENI

    // Kontrol sinyalleri (MEM)
    input  wire             reg_write_en_mem,
    input  wire             pc_to_reg_mem,
    input  wire             mem_to_reg_mem,

    // WB asamasina cikislar
    output reg  [XLEN-1:0]  pc_plus_4_wb,
    output reg  [XLEN-1:0]  alu_result_wb,
    output reg  [XLEN-1:0]  dmem_rdata_wb,
    output reg  [4:0]       rd_wb,
    output reg  [2:0]       funct3_wb,        // YENI

    // Kontrol sinyalleri (WB)
    output reg              reg_write_en_wb,
    output reg              pc_to_reg_wb,
    output reg              mem_to_reg_wb
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_plus_4_wb    <= {XLEN{1'b0}};
            alu_result_wb   <= {XLEN{1'b0}};
            dmem_rdata_wb   <= {XLEN{1'b0}};
            rd_wb           <= 5'b0;
            funct3_wb       <= 3'b0;
            reg_write_en_wb <= 1'b0;
            pc_to_reg_wb    <= 1'b0;
            mem_to_reg_wb   <= 1'b0;
        end else begin
            pc_plus_4_wb    <= pc_plus_4_mem;
            alu_result_wb   <= alu_result_mem;
            dmem_rdata_wb   <= dmem_rdata_mem;
            rd_wb           <= rd_mem;
            funct3_wb       <= funct3_mem;
            reg_write_en_wb <= reg_write_en_mem;
            pc_to_reg_wb    <= pc_to_reg_mem;
            mem_to_reg_wb   <= mem_to_reg_mem;
        end
    end

endmodule
