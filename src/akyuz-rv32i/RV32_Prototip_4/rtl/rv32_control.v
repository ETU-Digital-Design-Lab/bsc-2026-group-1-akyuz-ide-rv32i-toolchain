// rv32_control.v — RV32I Dekoder ve Kontrol Birimi
//
// 32 bitlik bir RV32I talimatını çözer ve tüm pipeline kontrol
// sinyallerini üretir. Dal (branch) koşulu EX aşamasına ertelenir;
// bu modül sadece branch_en sinyalini aktifler ve alu_op = SUB ayarlar ki
// EX aşaması ALU'dan gelen zero/lt/ltu bayraklarını inceleyebilsin.
//
// FENCE ve SYSTEM (ECALL/EBREAK) NOP olarak işlenir. Tüm çıkışlar
// varsayılan olarak NOP değerindedir, bu yüzden tanınmayan opcode'lar da
// güvenlidir.

module rv32_control #(
    parameter XLEN = 32
)(
    input  wire [31:0]      instruction,

    // Çözümlenmiş kayıt adresleri
    output wire [4:0]       rs1,
    output wire [4:0]       rs2,
    output wire [4:0]       rd,

    // Sıfır genişletilmiş immediat (format opcode tarafından seçilir)
    output wire [XLEN-1:0]  imm,

    // ALU kontrolü
    output reg  [3:0]       alu_op,
    output reg              alu_src,    // 0 = rs2, 1 = imm
    output reg  [1:0]       alu_a_sel,  // 00 = rs1, 01 = PC, 10 = zero

    // Kayıt dosyası (register file)
    output reg              reg_write_en,

    // Data memory
    output reg              dmem_we,

    // Dal / atlama (branch / jump)
    output reg              branch_en,
    output reg              jal_en,
    output reg              jalr_en,
    output reg              pc_to_reg,  // write PC+4 to rd (JAL/JALR)

    // Load / store: funct3, talimat kelimesi üzerinden pipeline kayıtlarına
    // doğrudan iletilir; mem_to_reg LOAD opcode'undan yönlendirilir
    output reg              mem_to_reg,

    // Tehlike tespit birimi tarafından kullanılır
    output wire             uses_rs1,
    output wire             uses_rs2
);

    // -------------------------------------------------------------------------
    // Talimat alan çıkarımı
    // -------------------------------------------------------------------------
    wire [6:0] opcode = instruction[6:0];
    wire [2:0] funct3 = instruction[14:12];
    wire [6:0] funct7 = instruction[31:25];

    assign rd  = instruction[11:7];
    assign rs1 = instruction[19:15];
    assign rs2 = instruction[24:20];

    // -------------------------------------------------------------------------
    // Immediate (sabit) üretimi
    // -------------------------------------------------------------------------
    wire [XLEN-1:0] imm_i = {{20{instruction[31]}}, instruction[31:20]};
    wire [XLEN-1:0] imm_s = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
    wire [XLEN-1:0] imm_b = {{19{instruction[31]}}, instruction[31], instruction[7],
                              instruction[30:25], instruction[11:8], 1'b0};
    wire [XLEN-1:0] imm_j = {{11{instruction[31]}}, instruction[31], instruction[19:12],
                              instruction[20], instruction[30:21], 1'b0};
    wire [XLEN-1:0] imm_u = {instruction[31:12], 12'b0};

    localparam OPCODE_STORE  = 7'b0100011;
    localparam OPCODE_BRANCH = 7'b1100011;
    localparam OPCODE_JAL    = 7'b1101111;
    localparam OPCODE_LUI    = 7'b0110111;
    localparam OPCODE_AUIPC  = 7'b0010111;

    assign imm = (opcode == OPCODE_STORE)  ? imm_s :
                 (opcode == OPCODE_BRANCH) ? imm_b :
                 (opcode == OPCODE_JAL)    ? imm_j :
                 (opcode == OPCODE_LUI  )  ? imm_u :
                 (opcode == OPCODE_AUIPC)  ? imm_u :
                 imm_i;

    // -------------------------------------------------------------------------
    // ALU işlem kodları (alu.v ile eşleşmeli)
    // -------------------------------------------------------------------------
    localparam ALU_ADD    = 4'b0000;
    localparam ALU_SUB    = 4'b0001;
    localparam ALU_AND    = 4'b0010;
    localparam ALU_OR     = 4'b0011;
    localparam ALU_XOR    = 4'b0100;
    localparam ALU_SLT    = 4'b0101;
    localparam ALU_SLTU   = 4'b0110;
    localparam ALU_SLL    = 4'b0111;
    localparam ALU_SRL    = 4'b1000;
    localparam ALU_SRA    = 4'b1001;

    // -------------------------------------------------------------------------
    // Opcode sabitleri
    // -------------------------------------------------------------------------
    localparam OPCODE_RTYPE  = 7'b0110011;
    localparam OPCODE_ITYPE  = 7'b0010011;
    localparam OPCODE_LOAD   = 7'b0000011;
    // OPCODE_STORE / BRANCH / JAL / LUI / AUIPC defined above
    localparam OPCODE_JALR   = 7'b1100111;
    localparam OPCODE_FENCE  = 7'b0001111;
    localparam OPCODE_SYSTEM = 7'b1110011;

    // ALU A-girişi seçici
    localparam ALU_A_RS1  = 2'b00;
    localparam ALU_A_PC   = 2'b01;
    localparam ALU_A_ZERO = 2'b10;

    // -------------------------------------------------------------------------
    // Kayıt kullanımı (tehlike tespiti için)
    // -------------------------------------------------------------------------
    assign uses_rs1 = (opcode == OPCODE_RTYPE)  ||
                      (opcode == OPCODE_ITYPE)  ||
                      (opcode == OPCODE_LOAD)   ||
                      (opcode == OPCODE_STORE)  ||
                      (opcode == OPCODE_BRANCH) ||
                      (opcode == OPCODE_JALR);

    assign uses_rs2 = (opcode == OPCODE_RTYPE)  ||
                      (opcode == OPCODE_STORE)  ||
                      (opcode == OPCODE_BRANCH);

    // -------------------------------------------------------------------------
    // Kontrol sinyali üretimi
    // -------------------------------------------------------------------------
    always @(*) begin
        // NOP defaults
        alu_op       = ALU_ADD;
        alu_src      = 1'b0;
        alu_a_sel    = ALU_A_RS1;
        reg_write_en = 1'b0;
        dmem_we      = 1'b0;
        branch_en    = 1'b0;
        jal_en       = 1'b0;
        jalr_en      = 1'b0;
        pc_to_reg    = 1'b0;
        mem_to_reg   = 1'b0;

        case (opcode)

            OPCODE_LUI: begin
                alu_a_sel    = ALU_A_ZERO;
                alu_src      = 1'b1;
                reg_write_en = 1'b1;
            end

            OPCODE_AUIPC: begin
                alu_a_sel    = ALU_A_PC;
                alu_src      = 1'b1;
                reg_write_en = 1'b1;
            end

            OPCODE_RTYPE: begin
                reg_write_en = 1'b1;
                case (funct3)
                    3'b000: alu_op = funct7[5] ? ALU_SUB : ALU_ADD;
                    3'b001: alu_op = ALU_SLL;
                    3'b010: alu_op = ALU_SLT;
                    3'b011: alu_op = ALU_SLTU;
                    3'b100: alu_op = ALU_XOR;
                    3'b101: alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                    3'b110: alu_op = ALU_OR;
                    3'b111: alu_op = ALU_AND;
                    default: alu_op = ALU_ADD;
                endcase
            end

            OPCODE_ITYPE: begin
                alu_src      = 1'b1;
                reg_write_en = 1'b1;
                case (funct3)
                    3'b000: alu_op = ALU_ADD;
                    3'b001: alu_op = ALU_SLL;
                    3'b010: alu_op = ALU_SLT;
                    3'b011: alu_op = ALU_SLTU;
                    3'b100: alu_op = ALU_XOR;
                    3'b101: alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                    3'b110: alu_op = ALU_OR;
                    3'b111: alu_op = ALU_AND;
                    default: alu_op = ALU_ADD;
                endcase
            end

            OPCODE_LOAD: begin
                alu_src      = 1'b1;
                reg_write_en = 1'b1;
                mem_to_reg   = 1'b1;
            end

            OPCODE_STORE: begin
                alu_src = 1'b1;
                dmem_we = 1'b1;
            end

            OPCODE_BRANCH: begin
                branch_en = 1'b1;
                alu_op    = ALU_SUB;
            end

            OPCODE_JAL: begin
                jal_en       = 1'b1;
                pc_to_reg    = 1'b1;
                reg_write_en = 1'b1;
            end

            OPCODE_JALR: begin
                if (funct3 == 3'b000) begin
                    jalr_en      = 1'b1;
                    alu_src      = 1'b1;
                    pc_to_reg    = 1'b1;
                    reg_write_en = 1'b1;
                end
            end

            // FENCE, SYSTEM, and unknown opcodes fall through to NOP defaults.
            default: ;

        endcase
    end

endmodule
