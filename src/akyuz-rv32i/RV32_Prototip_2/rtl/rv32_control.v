/*
 * RISC-V Kontrol Birimi (Control Unit) - DÜZELTİLMİŞ VERSİYON
 */

module rv32_control #(
    parameter XLEN = 32
)(
    input  wire [31:0]       instruction,   // Ham RISC-V komutu

    // ALU flag'leri
    input  wire              alu_zero,
    input  wire              alu_lt,
    input  wire              alu_ltu,

    // Decode çıkışları
    output wire [4:0]        rs1,
    output wire [4:0]        rs2,
    output wire [4:0]        rd,
    output wire [XLEN-1:0]   imm,           // Immediate değer

    // Kontrol sinyalleri
    output reg  [3:0]        alu_op,
    output reg               alu_src,
    output reg  [1:0]        alu_a_sel,      // ALU A input selector: 00=rs1, 01=pc, 10=zero
    output reg               reg_write_en,
    output reg               dmem_we,
    output reg               branch_en,
    output reg               branch_condition,
    output reg               jal_en,
    output reg               jalr_en,
    output reg               pc_to_reg,
    output wire              uses_rs1,        // Instruction uses rs1 register
    output wire              uses_rs2         // Instruction uses rs2 register
);

    // Instruction alanlarını parçalayalım
    wire [6:0] opcode = instruction[6:0];
    wire [2:0] funct3 = instruction[14:12];
    wire [6:0] funct7 = instruction[31:25];

    // Register adreslerini çıkar
    assign rd  = instruction[11:7];
    assign rs1 = instruction[19:15];
    assign rs2 = instruction[24:20];

    // --- IMMEDIATE GENERATION (Düzeltildi: U-Type Eklendi) ---
    
    // I-type immediate
    wire [XLEN-1:0] imm_i = {{20{instruction[31]}}, instruction[31:20]};
    
    // S-type immediate
    wire [XLEN-1:0] imm_s = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
    
    // B-type immediate
    wire [12:0] imm_b_raw = {instruction[31], instruction[7], instruction[30:25], instruction[11:8], 1'b0};
    wire [XLEN-1:0] imm_b = {{19{imm_b_raw[12]}}, imm_b_raw};
    
    // J-type immediate
    wire [20:0] imm_j_raw = {instruction[31], instruction[19:12], instruction[20], instruction[30:21], 1'b0};
    wire [XLEN-1:0] imm_j = {{11{imm_j_raw[20]}}, imm_j_raw};

    // U-type immediate (LUI ve AUIPC için - YENİ EKLENDİ)
    // instruction[31:12] üstte, alt 12 bit sıfır
    wire [XLEN-1:0] imm_u = {instruction[31:12], 12'b0};
    
    // Opcode'a göre immediate seçimi
    assign imm = (opcode == 7'b0100011) ? imm_s :  // STORE -> imm_s
                 (opcode == 7'b1100011) ? imm_b :  // BRANCH -> imm_b
                 (opcode == 7'b1101111) ? imm_j :  // JAL -> imm_j
                 (opcode == 7'b0110111) ? imm_u :  // LUI -> imm_u (YENİ)
                 (opcode == 7'b0010111) ? imm_u :  // AUIPC -> imm_u (YENİ)
                 imm_i;                            // Diğerleri -> imm_i

    // ALU operasyon kodları
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    localparam ALU_SLT  = 4'b0101;
    localparam ALU_SLTU = 4'b0110;
    localparam ALU_SLL  = 4'b0111;
    localparam ALU_SRL  = 4'b1000;
    localparam ALU_SRA  = 4'b1001;

    // RISC-V opcode'ları
    localparam OPCODE_RTYPE  = 7'b0110011;
    localparam OPCODE_ITYPE  = 7'b0010011;
    localparam OPCODE_LOAD   = 7'b0000011;
    localparam OPCODE_STORE  = 7'b0100011;
    localparam OPCODE_BRANCH = 7'b1100011;
    localparam OPCODE_JAL    = 7'b1101111;
    localparam OPCODE_JALR   = 7'b1100111;
    localparam OPCODE_LUI    = 7'b0110111;
    localparam OPCODE_AUIPC  = 7'b0010111;
    
    // ALU A select encoding
    localparam ALU_A_RS1 = 2'b00;
    localparam ALU_A_PC  = 2'b01;
    localparam ALU_A_ZERO = 2'b10;

    // Determine which registers are used (for hazard detection)
    assign uses_rs1 = (opcode == OPCODE_RTYPE) ||  // R-type
                      (opcode == OPCODE_ITYPE) ||  // I-type
                      (opcode == OPCODE_LOAD) ||   // LOAD
                      (opcode == OPCODE_STORE) ||  // STORE
                      (opcode == OPCODE_BRANCH) || // BRANCH
                      (opcode == OPCODE_JALR);     // JALR
    
    assign uses_rs2 = (opcode == OPCODE_RTYPE) ||  // R-type
                      (opcode == OPCODE_STORE) ||  // STORE
                      (opcode == OPCODE_BRANCH);   // BRANCH
    
    // Kontrol sinyallerini üret
    always @(*) begin
        // Varsayılanlar
        alu_op            = ALU_ADD;
        alu_src           = 1'b0;
        alu_a_sel         = ALU_A_RS1;  // Default: use rs1
        reg_write_en      = 1'b0;
        dmem_we           = 1'b0;
        branch_en         = 1'b0;
        branch_condition  = 1'b0;
        jal_en            = 1'b0;
        jalr_en           = 1'b0;
        pc_to_reg         = 1'b0;

        case (opcode)
            // LUI: Load Upper Immediate
            // LUI: x[rd] = imm[31:12] << 12 (lower 12 bits are zero)
            // ALU: 0 + imm = imm (rs1 field is not a register in U-type)
            OPCODE_LUI: begin
                alu_src      = 1'b1;       // Immediate kullan
                alu_a_sel    = ALU_A_ZERO; // CRITICAL: Use zero, not rs1 (rs1 field is part of immediate)
                reg_write_en = 1'b1;       // RD'ye yaz
                alu_op       = ALU_ADD;    // 0 + imm = imm
            end
            
            // AUIPC: Add Upper Immediate to PC
            // AUIPC: x[rd] = pc + (imm[31:12] << 12)
            // ALU: pc + imm = pc + imm
            OPCODE_AUIPC: begin
                alu_src      = 1'b1;       // Immediate kullan
                alu_a_sel    = ALU_A_PC;   // CRITICAL: Use PC, not rs1 (rs1 field is part of immediate)
                reg_write_en = 1'b1;       // RD'ye yaz
                alu_op       = ALU_ADD;    // pc + imm
            end

            // R-type
            OPCODE_RTYPE: begin
                alu_src      = 1'b0;
                reg_write_en = 1'b1;
                case (funct3)
                    3'b000: begin
                        if (funct7 == 7'b0000000) alu_op = ALU_ADD;
                        else if (funct7 == 7'b0100000) alu_op = ALU_SUB;
                    end
                    3'b111: alu_op = ALU_AND;
                    3'b110: alu_op = ALU_OR;
                    3'b100: alu_op = ALU_XOR;
                    3'b010: alu_op = ALU_SLT;
                    3'b011: alu_op = ALU_SLTU;
                    3'b001: alu_op = ALU_SLL;
                    3'b101: begin
                        if (funct7 == 7'b0000000) alu_op = ALU_SRL;
                        else if (funct7 == 7'b0100000) alu_op = ALU_SRA;
                    end
                    default: ;
                endcase
            end

            // I-type
            OPCODE_ITYPE: begin
                alu_src      = 1'b1;
                reg_write_en = 1'b1;
                case (funct3)
                    3'b000: alu_op = ALU_ADD;
                    3'b010: alu_op = ALU_SLT;
                    3'b011: alu_op = ALU_SLTU;
                    3'b111: alu_op = ALU_AND;
                    3'b110: alu_op = ALU_OR;
                    3'b100: alu_op = ALU_XOR;
                    3'b001: alu_op = ALU_SLL;
                    3'b101: begin
                        if (funct7 == 7'b0000000) alu_op = ALU_SRL;
                        else if (funct7 == 7'b0100000) alu_op = ALU_SRA;
                    end
                    default: ;
                endcase
            end

            // LOAD
            OPCODE_LOAD: begin
                alu_src      = 1'b1;
                reg_write_en = 1'b1;
                alu_op       = ALU_ADD;
            end

            // STORE
            OPCODE_STORE: begin
                alu_src      = 1'b1;
                dmem_we      = 1'b1;
                alu_op       = ALU_ADD;
            end

            // BRANCH
            OPCODE_BRANCH: begin
                branch_en    = 1'b1;
                alu_op       = ALU_SUB;
                case (funct3)
                    3'b000: branch_condition = alu_zero;   // BEQ
                    3'b001: branch_condition = !alu_zero;  // BNE
                    3'b100: branch_condition = alu_lt;     // BLT
                    3'b101: branch_condition = !alu_lt;    // BGE
                    3'b110: branch_condition = alu_ltu;    // BLTU
                    3'b111: branch_condition = !alu_ltu;   // BGEU
                    default: branch_condition = 1'b0;
                endcase
            end

            // JAL
            OPCODE_JAL: begin
                jal_en       = 1'b1;
                pc_to_reg    = 1'b1;
                reg_write_en = 1'b1;
                alu_op       = ALU_ADD;
            end

            // JALR
            OPCODE_JALR: begin
                if (funct3 == 3'b000) begin
                    jalr_en      = 1'b1;
                    pc_to_reg    = 1'b1;
                    reg_write_en = 1'b1;
                    alu_src      = 1'b1;
                    alu_op       = ALU_ADD;
                end
            end

            default: begin
                // NOP
            end
        endcase
    end

endmodule