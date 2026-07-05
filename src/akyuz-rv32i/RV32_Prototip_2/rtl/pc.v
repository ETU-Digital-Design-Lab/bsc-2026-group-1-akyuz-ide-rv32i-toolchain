/*
 * Program Sayacı (PC) Modülü
 * - Mevcut komut adresini tutar (pc_current)
 * - Her saat darbesinde pc_next değerine güncellenir
 * - Reset durumunda 0x00000000’dan başlar
 */

module pc #(
    parameter XLEN = 32          // Adres genişliği (32-bit)
)(
    input  wire              clk,        // Saat sinyali
    input  wire              rst_n,      // Aktif düşük reset
    input  wire [XLEN-1:0]   pc_next,    // Bir sonraki PC değeri
    output reg  [XLEN-1:0]   pc_current  // Mevcut PC değeri
);

    // PC register'ı: reset'te sıfırlanır, normalde pc_next'e güncellenir
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_current <= {XLEN{1'b0}};      // Reset anında PC = 0x00000000
        end else begin
            pc_current <= pc_next;           // Her clock'ta PC'yi güncelle
        end
    end

endmodule
