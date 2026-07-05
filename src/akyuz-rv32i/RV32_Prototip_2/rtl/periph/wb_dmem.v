`timescale 1ns / 1ps

// wb_dmem.v
//
// Wishbone B4 uyumlu Data Memory (DMEM) modulu.
// Byte-enable (SEL) destekli, tek-cycle yanit.
//
// Ozellikler:
//   - 4KB (1024 x 32-bit) RAM
//   - Byte-enable ile LB/LH/LW/SB/SH/SW destegi
//   - Kombinasyonel okuma, senkron yazma
//   - Wishbone ACK: STB geldiginde hemen ACK

module wb_dmem #(
    parameter XLEN       = 32,
    parameter DMEM_WORDS = 1024   // 4KB
)(
    input  wire              clk,
    input  wire              rst_n,

    // Wishbone Slave Arayuzu
    input  wire [XLEN-1:0]   wb_adr_i,
    input  wire [31:0]       wb_dat_i,
    input  wire              wb_we_i,
    input  wire [3:0]        wb_sel_i,     // Byte-enable
    input  wire              wb_stb_i,
    output wire [31:0]       wb_dat_o,
    output wire              wb_ack_o
);

    // ================================================================
    // RAM Dizisi
    // ================================================================
    reg [31:0] mem [0:DMEM_WORDS-1];

    // Baslangic: RAM'i sifirla (simulasyon icin)
    integer j;
    initial begin
        for (j = 0; j < DMEM_WORDS; j = j + 1)
            mem[j] = 32'h0;
    end

    // ================================================================
    // Adres Hesaplama
    // ================================================================
    // DMEM base: 0x2000_0000, oradan word index hesapla
    wire [XLEN-1:0] local_addr = wb_adr_i - 32'h2000_0000;
    wire [XLEN-1:0] word_idx   = local_addr >> 2;
    wire             addr_valid = (word_idx < DMEM_WORDS);

    // ================================================================
    // Kombinasyonel Okuma
    // ================================================================
    assign wb_dat_o = (addr_valid) ? mem[word_idx] : 32'h0;

    // ================================================================
    // Senkron Yazma (Byte-Enable destekli)
    // ================================================================
    always @(posedge clk) begin
        if (wb_stb_i && wb_we_i && addr_valid) begin
            if (wb_sel_i[0]) mem[word_idx][ 7: 0] <= wb_dat_i[ 7: 0];
            if (wb_sel_i[1]) mem[word_idx][15: 8] <= wb_dat_i[15: 8];
            if (wb_sel_i[2]) mem[word_idx][23:16] <= wb_dat_i[23:16];
            if (wb_sel_i[3]) mem[word_idx][31:24] <= wb_dat_i[31:24];
        end
    end

    // ================================================================
    // Wishbone ACK (tek-cycle)
    // ================================================================
    assign wb_ack_o = wb_stb_i;

endmodule
