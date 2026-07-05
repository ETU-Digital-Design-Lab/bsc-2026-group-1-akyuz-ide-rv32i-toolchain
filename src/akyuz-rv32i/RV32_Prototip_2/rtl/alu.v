/*
 * RISC-V ALU (Aritmetik ve Mantık Birimi)
 *
 * - Kombinasyonel bir birimdir (içinde saat/flip-flop yok).
 * - İki adet 32-bit giriş alır (alu_in1, alu_in2).
 * - alu_op sinyaline göre uygun işlemi seçer.
 * - Sonucu alu_result ile dışarı verir.
 * - Branch ve karşılaştırmalar için yardımcı flag çıkışları üretir:
 *     zero : sonuç 0 mı?
 *     lt   : signed karşılaştırma (alu_in1 <  alu_in2 ? 1 : 0)
 *     ltu  : unsigned karşılaştırma (alu_in1 <u alu_in2 ? 1 : 0)
 */

module rv32_alu #(
    parameter XLEN = 32
)(
    // ALU girişleri
    input  wire [XLEN-1:0] alu_in1,     // 1. operand (genelde rs1_data)
    input  wire [XLEN-1:0] alu_in2,     // 2. operand (rs2_data veya immediate)
    input  wire [3:0]      alu_op,      // Hangi işlemin yapılacağını seçen kontrol kodu

    // ALU çıkışları
    output reg  [XLEN-1:0] alu_result,  // İşlem sonucu
    output wire            zero,        // Sonuç 0 mı?
    output wire            lt,          // Signed karşılaştırma sonucu (alu_in1 < alu_in2)
    output wire            ltu          // Unsigned karşılaştırma sonucu (alu_in1 <u alu_in2)
);

    // ALU operasyon kodları (Control Unit buradaki kodları kullanacak)
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    localparam ALU_SLT  = 4'b0101;   // Signed karşılaştırma (set less than)
    localparam ALU_SLTU = 4'b0110;   // Unsigned karşılaştırma
    localparam ALU_SLL  = 4'b0111;   // Shift left logical
    localparam ALU_SRL  = 4'b1000;   // Shift right logical
    localparam ALU_SRA  = 4'b1001;   // Shift right arithmetic

    // Ana ALU işlemi (kombinasyonel mantık)
    always @(*) begin
        // Varsayılan değer (hiçbir case eşleşmezse 0 olsun)
        alu_result = {XLEN{1'b0}};

        case (alu_op)
            ALU_ADD:  alu_result = alu_in1 + alu_in2;
            ALU_SUB:  alu_result = alu_in1 - alu_in2;
            ALU_AND:  alu_result = alu_in1 & alu_in2;
            ALU_OR:   alu_result = alu_in1 | alu_in2;
            ALU_XOR:  alu_result = alu_in1 ^ alu_in2;

            ALU_SLT:  alu_result = ($signed(alu_in1) < $signed(alu_in2)) ? {{(XLEN-1){1'b0}}, 1'b1} 
                                                                          : {XLEN{1'b0}};
            ALU_SLTU: alu_result = (alu_in1 < alu_in2) ? {{(XLEN-1){1'b0}}, 1'b1}
                                                       : {XLEN{1'b0}};

            ALU_SLL:  alu_result = alu_in1 << alu_in2[4:0];  // 32-bit için en fazla 31 bit shift
            ALU_SRL:  alu_result = alu_in1 >> alu_in2[4:0];  // Logical right shift
            ALU_SRA:  alu_result = $signed(alu_in1) >>> alu_in2[4:0]; // Arithmetic right shift

            default:  alu_result = {XLEN{1'b0}}; // Güvenli default
        endcase
    end

    // Yardımcı flag’ler (branch için de ileride kullanılabilir)
    assign zero = (alu_result == {XLEN{1'b0}});
    assign lt   = ($signed(alu_in1) <  $signed(alu_in2));
    assign ltu  = (alu_in1 < alu_in2);

endmodule
