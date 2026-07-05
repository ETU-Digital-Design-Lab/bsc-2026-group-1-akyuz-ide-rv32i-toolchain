`timescale 1ns / 1ps

// rv32_core_pipelined.v - Prototip 2
//
// RV32I 5-Asamali Pipeline Islemci Cekirdegi
//
// Prototip-1'den Farklar:
//   1. Wishbone B4 Master arayuzu (STB/CYC/ACK/ERR)
//   2. Byte/Halfword Load destegi (LB/LBU/LH/LHU/LW)
//   3. Byte/Halfword Store destegi (SB/SH/SW)
//   4. funct3 MEM ve WB asamalarina tasinir
//   5. MEM asamasinda byte-enable uretimi (funct3 + adres[1:0])
//   6. MEM asamasinda store data alignment
//   7. WB asamasinda load sign-extension / zero-extension
//   8. Bus hata (ERR) algilamasi
//
// Pipeline: IF -> ID -> EX -> MEM -> WB
// Hazard: Forwarding + Load-use stall + Branch flush

module rv32_core_pipelined #(
    parameter XLEN = 32
)(
    input  wire              clk,
    input  wire              rst_n,

    // Instruction Memory (Harvard - ayri arayuz)
    output wire [XLEN-1:0]   imem_addr,
    input  wire [31:0]       imem_rdata,

    // Wishbone Master - Data Bus
    output wire [XLEN-1:0]   wb_adr_o,      // Adres
    output wire [31:0]       wb_dat_o,      // Yazma verisi
    output wire              wb_we_o,       // Write Enable
    output wire [3:0]        wb_sel_o,      // Byte Select
    output wire              wb_stb_o,      // Strobe
    output wire              wb_cyc_o,      // Cycle
    input  wire [31:0]       wb_dat_i,      // Okuma verisi
    input  wire              wb_ack_i,      // Acknowledge
    input  wire              wb_err_i,      // Bus Error

    // Debug
    output wire [7:0]        dbg_out
);

    // ============================================================
    // Sinyal Tanimlari
    // ============================================================
    wire [4:0]        rd_wb;
    wire [XLEN-1:0]   rd_data_wb;
    wire              reg_write_en_wb;
    wire [XLEN-1:0]   wb_data_wb;         // WB secilen veri
    wire [XLEN-1:0]   pc_plus_4_wb;
    wire [XLEN-1:0]   alu_result_wb;
    wire [XLEN-1:0]   dmem_rdata_wb;
    wire              pc_to_reg_wb;
    wire              mem_to_reg_wb;
    wire [2:0]        funct3_wb;           // YENI: WB'de load tipi icin

    // ============================================================
    // Stage 1: IF (Instruction Fetch)
    // ============================================================
    wire [XLEN-1:0] pc_current, pc_next, pc_plus_4_if;
    wire [XLEN-1:0] pc_next_calculated;
    wire            pc_write_en;

    assign pc_plus_4_if = pc_current + 32'd4;
    assign imem_addr = pc_current;

    // PC Stall Mantigi
    assign pc_next = (pc_write_en) ? pc_next_calculated : pc_current;

    pc #(
        .XLEN(XLEN)
    ) u_pc (
        .clk        (clk),
        .rst_n      (rst_n),
        .pc_next    (pc_next),
        .pc_current (pc_current)
    );

    // ============================================================
    // IF/ID Pipeline Register
    // ============================================================
    wire [XLEN-1:0] pc_plus_4_id, pc_id;
    wire [31:0]     instruction_id;
    wire            if_id_flush;
    wire            if_id_stall;

    if_id_reg #(
        .XLEN(XLEN)
    ) u_if_id_reg (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush           (if_id_flush),
        .stall           (if_id_stall),
        .pc_plus_4_if    (pc_plus_4_if),
        .instruction_if  (imem_rdata),
        .pc_if           (pc_current),
        .pc_plus_4_id    (pc_plus_4_id),
        .instruction_id  (instruction_id),
        .pc_id           (pc_id)
    );

    // ============================================================
    // Stage 2: ID (Instruction Decode)
    // ============================================================
    wire [4:0]        rs1_id, rs2_id, rd_id;
    wire [XLEN-1:0]   imm_id;
    wire [XLEN-1:0]   rs1_data_id, rs2_data_id;
    wire [2:0]        funct3_id;

    assign funct3_id = instruction_id[14:12];
    assign rs1_id = instruction_id[19:15];
    assign rs2_id = instruction_id[24:20];
    assign rd_id  = instruction_id[11:7];

    // Control Signals
    wire [3:0]        alu_op_id;
    wire              alu_src_id;
    wire [1:0]        alu_a_sel_id;
    wire              reg_write_en_id;
    wire              dmem_we_id;
    wire              branch_en_id;
    wire              branch_condition_id;
    wire              jal_en_id;
    wire              jalr_en_id;
    wire              pc_to_reg_id;
    wire              mem_to_reg_id;
    wire              uses_rs1_id, uses_rs2_id;

    rv32_control #(
        .XLEN(XLEN)
    ) u_ctrl (
        .instruction      (instruction_id),
        .alu_zero         (1'b0),
        .alu_lt           (1'b0),
        .alu_ltu          (1'b0),
        .rs1              (rs1_id),
        .rs2              (rs2_id),
        .rd               (rd_id),
        .imm              (imm_id),
        .alu_op           (alu_op_id),
        .alu_src          (alu_src_id),
        .alu_a_sel        (alu_a_sel_id),
        .reg_write_en     (reg_write_en_id),
        .dmem_we          (dmem_we_id),
        .branch_en        (branch_en_id),
        .branch_condition (branch_condition_id),
        .jal_en           (jal_en_id),
        .jalr_en          (jalr_en_id),
        .pc_to_reg        (pc_to_reg_id),
        .uses_rs1         (uses_rs1_id),
        .uses_rs2         (uses_rs2_id)
    );

    assign mem_to_reg_id = (instruction_id[6:0] == 7'b0000011);

    regfile #(
        .XLEN(XLEN),
        .REG_COUNT(32)
    ) u_regfile (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (rs1_id),
        .rs2_addr (rs2_id),
        .rs1_data (rs1_data_id),
        .rs2_data (rs2_data_id),
        .rd_addr  (rd_wb),
        .rd_data  (rd_data_wb),
        .rd_we    (reg_write_en_wb)
    );

    // Hazard Detection
    wire              hazard_stall;
    wire              if_id_write_en;
    wire              id_ex_mem_read;
    wire [4:0]        rd_ex;

    wire hazard_id_ex_flush;

    hazard_detection_unit u_hazard_detection (
        .if_id_rs1        (rs1_id),
        .if_id_rs2        (rs2_id),
        .if_id_uses_rs1   (uses_rs1_id),
        .if_id_uses_rs2   (uses_rs2_id),
        .id_ex_rd         (rd_ex),
        .id_ex_mem_read   (id_ex_mem_read),
        .stall            (hazard_stall),
        .pc_write_en      (pc_write_en),
        .if_id_write_en   (if_id_write_en),
        .id_ex_flush      (hazard_id_ex_flush)
    );

    assign if_id_stall = hazard_stall;

    // ============================================================
    // ID/EX Pipeline Register
    // ============================================================
    wire [XLEN-1:0]  pc_plus_4_ex, pc_ex;
    wire [XLEN-1:0]  rs1_data_ex, rs2_data_ex;
    wire [XLEN-1:0]  imm_ex;
    wire [4:0]       rs1_ex, rs2_ex;
    wire [3:0]       alu_op_ex;
    wire             alu_src_ex;
    wire [1:0]       alu_a_sel_ex;
    wire             reg_write_en_ex;
    wire             dmem_we_ex;
    wire             branch_en_ex;
    wire             jal_en_ex;
    wire             jalr_en_ex;
    wire             pc_to_reg_ex;
    wire             mem_to_reg_ex;
    wire [2:0]       funct3_ex;
    wire             id_ex_flush;

    assign id_ex_mem_read = mem_to_reg_ex;

    id_ex_reg #(
        .XLEN(XLEN)
    ) u_id_ex_reg (
        .clk              (clk),
        .rst_n            (rst_n),
        .flush            (id_ex_flush | hazard_id_ex_flush),
        .stall            (1'b0),
        .pc_plus_4_id     (pc_plus_4_id),
        .pc_id            (pc_id),
        .rs1_data_id      (rs1_data_id),
        .rs2_data_id      (rs2_data_id),
        .imm_id           (imm_id),
        .rs1_id           (rs1_id),
        .rs2_id           (rs2_id),
        .rd_id            (rd_id),
        .alu_op_id        (alu_op_id),
        .alu_src_id       (alu_src_id),
        .alu_a_sel_id     (alu_a_sel_id),
        .reg_write_en_id  (reg_write_en_id),
        .dmem_we_id       (dmem_we_id),
        .branch_en_id     (branch_en_id),
        .jal_en_id        (jal_en_id),
        .jalr_en_id       (jalr_en_id),
        .pc_to_reg_id     (pc_to_reg_id),
        .mem_to_reg_id    (mem_to_reg_id),
        .funct3_id        (funct3_id),
        .pc_plus_4_ex     (pc_plus_4_ex),
        .pc_ex            (pc_ex),
        .rs1_data_ex      (rs1_data_ex),
        .rs2_data_ex      (rs2_data_ex),
        .imm_ex           (imm_ex),
        .rs1_ex           (rs1_ex),
        .rs2_ex           (rs2_ex),
        .rd_ex            (rd_ex),
        .alu_op_ex        (alu_op_ex),
        .alu_src_ex       (alu_src_ex),
        .alu_a_sel_ex     (alu_a_sel_ex),
        .reg_write_en_ex  (reg_write_en_ex),
        .dmem_we_ex       (dmem_we_ex),
        .branch_en_ex     (branch_en_ex),
        .jal_en_ex        (jal_en_ex),
        .jalr_en_ex       (jalr_en_ex),
        .pc_to_reg_ex     (pc_to_reg_ex),
        .mem_to_reg_ex    (mem_to_reg_ex),
        .funct3_ex        (funct3_ex)
    );

    // ============================================================
    // Stage 3: EX (Execute)
    // ============================================================
    wire [XLEN-1:0]  alu_result_ex;
    wire             alu_zero_ex, alu_lt_ex, alu_ltu_ex;
    reg  [XLEN-1:0]  alu_in1_ex;
    wire [XLEN-1:0]  alu_in2_ex;
    wire [XLEN-1:0]  pc_jump_target_ex;
    wire             branch_taken_ex;
    reg              branch_condition_ex;

    // Forwarding Unit
    wire [1:0]       forward_a, forward_b, forward_store;
    wire [4:0]       rd_mem;
    wire             reg_write_en_mem;
    wire             pc_to_reg_mem;

    forwarding_unit u_forwarding (
        .id_ex_rs1            (rs1_ex),
        .id_ex_rs2            (rs2_ex),
        .ex_mem_rd            (rd_mem),
        .mem_wb_rd            (rd_wb),
        .ex_mem_reg_write_en  (reg_write_en_mem),
        .mem_wb_reg_write_en  (reg_write_en_wb),
        .forward_a            (forward_a),
        .forward_b            (forward_b),
        .forward_store        (forward_store)
    );

    // MUX Logic
    localparam FORWARD_NONE   = 2'b00;
    localparam FORWARD_MEM_WB = 2'b01;
    localparam FORWARD_EX_MEM = 2'b10;
    wire [XLEN-1:0] alu_result_mem;
    wire [XLEN-1:0] pc_plus_4_mem;

    // CRITICAL: EX/MEM forwarding must account for JAL/JALR
    wire [XLEN-1:0] ex_mem_forward_value;
    assign ex_mem_forward_value = (pc_to_reg_mem) ? pc_plus_4_mem : alu_result_mem;

    // ALU A select encoding
    localparam ALU_A_RS1  = 2'b00;
    localparam ALU_A_PC   = 2'b01;
    localparam ALU_A_ZERO = 2'b10;

    // Forwarding mux for rs1 data
    reg [XLEN-1:0] rs1_data_forwarded_ex;
    always @(*) begin
        case (forward_a)
            FORWARD_EX_MEM: rs1_data_forwarded_ex = ex_mem_forward_value;
            FORWARD_MEM_WB: rs1_data_forwarded_ex = wb_data_wb;
            default:        rs1_data_forwarded_ex = rs1_data_ex;
        endcase
    end

    // ALU A input selector (LUI/AUIPC)
    always @(*) begin
        case (alu_a_sel_ex)
            ALU_A_PC:   alu_in1_ex = pc_ex;
            ALU_A_ZERO: alu_in1_ex = {XLEN{1'b0}};
            default:    alu_in1_ex = rs1_data_forwarded_ex;
        endcase
    end

    reg [XLEN-1:0] rs2_data_forwarded_ex;
    always @(*) begin
        case (forward_b)
            FORWARD_EX_MEM: rs2_data_forwarded_ex = ex_mem_forward_value;
            FORWARD_MEM_WB: rs2_data_forwarded_ex = wb_data_wb;
            default:        rs2_data_forwarded_ex = rs2_data_ex;
        endcase
    end

    assign alu_in2_ex = (alu_src_ex) ? imm_ex : rs2_data_forwarded_ex;

    // Store-data forwarding
    reg [XLEN-1:0] store_data_forwarded_ex;
    always @(*) begin
        case (forward_store)
            FORWARD_EX_MEM: store_data_forwarded_ex = ex_mem_forward_value;
            FORWARD_MEM_WB: store_data_forwarded_ex = wb_data_wb;
            default:        store_data_forwarded_ex = rs2_data_ex;
        endcase
    end

    rv32_alu #(
        .XLEN(XLEN)
    ) u_alu (
        .alu_in1   (alu_in1_ex),
        .alu_in2   (alu_in2_ex),
        .alu_op    (alu_op_ex),
        .alu_result(alu_result_ex),
        .zero      (alu_zero_ex),
        .lt        (alu_lt_ex),
        .ltu       (alu_ltu_ex)
    );

    // Branch Logic
    always @(*) begin
        if (branch_en_ex) begin
            case (funct3_ex)
                3'b000: branch_condition_ex = alu_zero_ex;      // BEQ
                3'b001: branch_condition_ex = !alu_zero_ex;     // BNE
                3'b100: branch_condition_ex = alu_lt_ex;        // BLT
                3'b101: branch_condition_ex = !alu_lt_ex;       // BGE
                3'b110: branch_condition_ex = alu_ltu_ex;       // BLTU
                3'b111: branch_condition_ex = !alu_ltu_ex;      // BGEU
                default: branch_condition_ex = 1'b0;
            endcase
        end else begin
            branch_condition_ex = 1'b0;
        end
    end

    assign branch_taken_ex = branch_en_ex && branch_condition_ex;

    wire [XLEN-1:0] pc_jump_jal_ex, pc_jump_jalr_ex, pc_branch_target_ex;
    assign pc_jump_jal_ex    = pc_ex + imm_ex;
    assign pc_jump_jalr_ex   = alu_result_ex & ~32'h1;
    assign pc_branch_target_ex = pc_ex + imm_ex;

    // PC Next Logic
    assign pc_jump_target_ex = (jal_en_ex)       ? pc_jump_jal_ex :
                               (jalr_en_ex)      ? pc_jump_jalr_ex :
                               (branch_taken_ex) ? pc_branch_target_ex :
                               pc_plus_4_if;

    assign if_id_flush = (branch_taken_ex || jal_en_ex || jalr_en_ex);
    assign id_ex_flush = (branch_taken_ex || jal_en_ex || jalr_en_ex);

    assign pc_next_calculated = pc_jump_target_ex;

    // ============================================================
    // EX/MEM Pipeline Register
    // ============================================================
    wire [XLEN-1:0]  rs2_data_mem;
    wire             dmem_we_mem;
    wire             mem_to_reg_mem;
    wire [2:0]       funct3_mem;           // YENI

    wire flush_ex_mem;
    assign flush_ex_mem = branch_taken_ex;

    ex_mem_reg #(
        .XLEN(XLEN)
    ) u_ex_mem_reg (
        .clk              (clk),
        .rst_n            (rst_n),
        .flush_ex_mem     (flush_ex_mem),
        .pc_plus_4_ex     (pc_plus_4_ex),
        .alu_result_ex    (alu_result_ex),
        .rs2_data_ex      (store_data_forwarded_ex),
        .rd_ex            (rd_ex),
        .funct3_ex        (funct3_ex),       // YENI: funct3 MEM'e
        .reg_write_en_ex  (reg_write_en_ex),
        .dmem_we_ex       (dmem_we_ex),
        .pc_to_reg_ex     (pc_to_reg_ex),
        .mem_to_reg_ex    (mem_to_reg_ex),
        .pc_plus_4_mem    (pc_plus_4_mem),
        .alu_result_mem   (alu_result_mem),
        .rs2_data_mem     (rs2_data_mem),
        .rd_mem           (rd_mem),
        .funct3_mem       (funct3_mem),      // YENI
        .reg_write_en_mem (reg_write_en_mem),
        .dmem_we_mem      (dmem_we_mem),
        .pc_to_reg_mem    (pc_to_reg_mem),
        .mem_to_reg_mem   (mem_to_reg_mem)
    );

    // ============================================================
    // Stage 4: MEM (Memory Access) - Wishbone Master
    // ============================================================

    // --- Byte-Enable Uretimi (funct3 + adres[1:0]) ---
    // LB/SB:  funct3[1:0] = 00 -> 1 byte
    // LH/SH:  funct3[1:0] = 01 -> 2 byte
    // LW/SW:  funct3[1:0] = 10 -> 4 byte
    wire [1:0] mem_size    = funct3_mem[1:0];
    wire [1:0] byte_offset = alu_result_mem[1:0];  // Adresin alt 2 biti

    reg [3:0] mem_byte_en;
    always @(*) begin
        case (mem_size)
            2'b00: begin // Byte (LB/LBU/SB)
                case (byte_offset)
                    2'b00: mem_byte_en = 4'b0001;
                    2'b01: mem_byte_en = 4'b0010;
                    2'b10: mem_byte_en = 4'b0100;
                    2'b11: mem_byte_en = 4'b1000;
                endcase
            end
            2'b01: begin // Halfword (LH/LHU/SH)
                case (byte_offset[1])
                    1'b0: mem_byte_en = 4'b0011;
                    1'b1: mem_byte_en = 4'b1100;
                endcase
            end
            default: begin // Word (LW/SW)
                mem_byte_en = 4'b1111;
            end
        endcase
    end

    // --- Store Data Alignment ---
    // SB: veriyi byte pozisyonuna shiftle
    // SH: veriyi halfword pozisyonuna shiftle
    // SW: veri oldugu gibi
    reg [31:0] store_data_aligned;
    always @(*) begin
        case (mem_size)
            2'b00: begin // SB
                case (byte_offset)
                    2'b00: store_data_aligned = {24'h0, rs2_data_mem[7:0]};
                    2'b01: store_data_aligned = {16'h0, rs2_data_mem[7:0], 8'h0};
                    2'b10: store_data_aligned = {8'h0, rs2_data_mem[7:0], 16'h0};
                    2'b11: store_data_aligned = {rs2_data_mem[7:0], 24'h0};
                endcase
            end
            2'b01: begin // SH
                case (byte_offset[1])
                    1'b0: store_data_aligned = {16'h0, rs2_data_mem[15:0]};
                    1'b1: store_data_aligned = {rs2_data_mem[15:0], 16'h0};
                endcase
            end
            default: begin // SW
                store_data_aligned = rs2_data_mem;
            end
        endcase
    end

    // --- Wishbone Master Sinyalleri ---
    wire mem_active = dmem_we_mem | mem_to_reg_mem;  // Store veya Load

    assign wb_adr_o = alu_result_mem;
    assign wb_dat_o = store_data_aligned;
    assign wb_we_o  = dmem_we_mem;
    assign wb_sel_o = (mem_active) ? mem_byte_en : 4'b0000;
    assign wb_stb_o = mem_active;
    assign wb_cyc_o = mem_active;

    // ============================================================
    // MEM/WB Pipeline Register
    // ============================================================
    mem_wb_reg #(
        .XLEN(XLEN)
    ) u_mem_wb_reg (
        .clk              (clk),
        .rst_n            (rst_n),
        .pc_plus_4_mem    (pc_plus_4_mem),
        .alu_result_mem   (alu_result_mem),
        .dmem_rdata_mem   (wb_dat_i),        // Wishbone'dan gelen okuma verisi
        .rd_mem           (rd_mem),
        .funct3_mem       (funct3_mem),      // YENI
        .reg_write_en_mem (reg_write_en_mem),
        .pc_to_reg_mem    (pc_to_reg_mem),
        .mem_to_reg_mem   (mem_to_reg_mem),
        .pc_plus_4_wb     (pc_plus_4_wb),
        .alu_result_wb    (alu_result_wb),
        .dmem_rdata_wb    (dmem_rdata_wb),
        .rd_wb            (rd_wb),
        .funct3_wb        (funct3_wb),       // YENI
        .reg_write_en_wb  (reg_write_en_wb),
        .pc_to_reg_wb     (pc_to_reg_wb),
        .mem_to_reg_wb    (mem_to_reg_wb)
    );

    // ============================================================
    // Stage 5: WB (Writeback) - Load Sign/Zero Extension
    // ============================================================

    // --- Load Data Extraction ---
    // Bellekten okunan 32-bit veriden, funct3 ve adres offset'e gore
    // byte/halfword/word cikarma ve sign/zero extension
    wire [1:0] load_byte_offset = alu_result_wb[1:0];

    reg [XLEN-1:0] load_data_extended;
    always @(*) begin
        case (funct3_wb)
            3'b000: begin // LB (signed byte)
                case (load_byte_offset)
                    2'b00: load_data_extended = {{24{dmem_rdata_wb[7]}},  dmem_rdata_wb[7:0]};
                    2'b01: load_data_extended = {{24{dmem_rdata_wb[15]}}, dmem_rdata_wb[15:8]};
                    2'b10: load_data_extended = {{24{dmem_rdata_wb[23]}}, dmem_rdata_wb[23:16]};
                    2'b11: load_data_extended = {{24{dmem_rdata_wb[31]}}, dmem_rdata_wb[31:24]};
                endcase
            end
            3'b001: begin // LH (signed halfword)
                case (load_byte_offset[1])
                    1'b0: load_data_extended = {{16{dmem_rdata_wb[15]}}, dmem_rdata_wb[15:0]};
                    1'b1: load_data_extended = {{16{dmem_rdata_wb[31]}}, dmem_rdata_wb[31:16]};
                endcase
            end
            3'b010: begin // LW (word)
                load_data_extended = dmem_rdata_wb;
            end
            3'b100: begin // LBU (unsigned byte)
                case (load_byte_offset)
                    2'b00: load_data_extended = {24'h0, dmem_rdata_wb[7:0]};
                    2'b01: load_data_extended = {24'h0, dmem_rdata_wb[15:8]};
                    2'b10: load_data_extended = {24'h0, dmem_rdata_wb[23:16]};
                    2'b11: load_data_extended = {24'h0, dmem_rdata_wb[31:24]};
                endcase
            end
            3'b101: begin // LHU (unsigned halfword)
                case (load_byte_offset[1])
                    1'b0: load_data_extended = {16'h0, dmem_rdata_wb[15:0]};
                    1'b1: load_data_extended = {16'h0, dmem_rdata_wb[31:16]};
                endcase
            end
            default: begin
                load_data_extended = dmem_rdata_wb;
            end
        endcase
    end

    // --- Writeback Mux ---
    wire [XLEN-1:0] wb_data_core;
    assign wb_data_core = (mem_to_reg_wb) ? load_data_extended : alu_result_wb;
    assign rd_data_wb   = (pc_to_reg_wb)  ? pc_plus_4_wb      : wb_data_core;
    assign wb_data_wb   = rd_data_wb;

    // Debug
    assign dbg_out = pc_current[7:0];

endmodule
