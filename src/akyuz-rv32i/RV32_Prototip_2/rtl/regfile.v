/*
 * RISC-V Register Dosyası (x0 - x31)
 *
 * - Toplam 32 adet 32-bit register içerir.
 * - x0 register'ı her zaman 0'dır (yazılamaz).
 * - 2 adet okuma portu (rs1, rs2)
 * - 1 adet yazma portu (rd)
 *
 * Not:
 *  - Okumalar kombinasyoneldir (anlık olarak değer verir).
 *  - Yazma işlemi saat darbesi (clk) ile yapılır.
 */

module regfile #(
    parameter XLEN      = 32,  // Register genişliği
    parameter REG_COUNT = 32   // Register sayısı (RISC-V için 32)
)(
    input  wire              clk,        // Saat sinyali
    input  wire              rst_n,      // Aktif düşük reset

    // Okuma portları
    input  wire [4:0]        rs1_addr,   // 1. kaynak register adresi
    input  wire [4:0]        rs2_addr,   // 2. kaynak register adresi
    output wire [XLEN-1:0]   rs1_data,   // 1. kaynağın verisi
    output wire [XLEN-1:0]   rs2_data,   // 2. kaynağın verisi

    // Yazma portu
    input  wire [4:0]        rd_addr,    // Hedef register adresi
    input  wire [XLEN-1:0]   rd_data,    // Yazılacak veri
    input  wire              rd_we       // Yazma izni (1 = yaz, 0 = yazma)
);

    // Register dizisi: 32 adet 32-bit register
    reg [XLEN-1:0] regs [0:REG_COUNT-1];

    integer i;

    // Reset ve yazma mantığı
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset durumunda tüm register'ları 0 yap
            // (x0 zaten aşağıda okuma kısmında 0'a zorlanacak)
            for (i = 0; i < REG_COUNT; i = i + 1) begin
                regs[i] <= {XLEN{1'b0}};
            end
        end else begin
            // Yazma izni varsa ve hedef register x0 değilse yaz
            if (rd_we && (rd_addr != 5'd0)) begin
                regs[rd_addr] <= rd_data;
            end
        end
    end

    // Okuma portları (kombinasyonel, write-through destekli)
    // x0 register'ı her zaman 0 olmalı (RISC-V kuralı)
    // Write-through: WB aşaması aynı anda yazarken ID aynı register'ı okuyorsa
    // yeni değer direkt verilir (register dosyasındaki eski değer beklenmez)
    assign rs1_data = (rs1_addr == 5'd0)                          ? {XLEN{1'b0}} :
                      (rd_we && rd_addr == rs1_addr)              ? rd_data       :
                      regs[rs1_addr];

    assign rs2_data = (rs2_addr == 5'd0)                          ? {XLEN{1'b0}} :
                      (rd_we && rd_addr == rs2_addr)              ? rd_data       :
                      regs[rs2_addr];

endmodule
