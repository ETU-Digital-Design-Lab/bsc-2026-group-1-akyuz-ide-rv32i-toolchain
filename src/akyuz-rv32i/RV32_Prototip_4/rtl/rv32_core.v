// rv32_core.v — RV32I 5-Stage Pipelined Core
//
// Pipeline stages: IF → ID → EX → MEM → WB
//
// Hazard handling:
//   Load-use hazard  → 1-cycle stall (hazard_detection_unit)
//   Branch/JAL/JALR  → 2-cycle flush (resolved in EX stage)
//
// Data hazards for non-load RAW conflicts are resolved by forwarding
// (forwarding_unit). Remaining hazards (load-use) require a stall.
//
// Branch condition is evaluated in EX using ALU flags (zero, lt, ltu)
// and funct3_ex. The branch target is PC_EX + imm_ex (B-type immediate).
//
// WB write-back priority: PC+4 > mem_data > alu_result
// Load sign/zero extension is applied in WB based on funct3_wb and
// the two LSBs of alu_result_wb (effective byte address).


module rv32_core #(
    parameter XLEN       = 32,
    parameter IMEM_DEPTH = 1024,
    parameter DMEM_DEPTH = 1024,
    parameter IMEM_FILE  = "",
    parameter DMEM_FILE  = "",
    parameter EXT_DMEM   = 0    // 0 = internal DMEM; 1 = external DMEM bus
)(
    input  wire clk,
    input  wire rst_n,

    // IMEM Write Port (from HW Bootloader)
    input  wire        imem_we,
    input  wire [31:0] imem_waddr,
    input  wire [31:0] imem_wdata,

    // External DMEM bus (used when EXT_DMEM=1; exposed for monitoring when EXT_DMEM=0)
    output wire [XLEN-1:0] dmem_addr,      // effective address from ALU
    output wire [XLEN-1:0] dmem_wdata,     // store data
    output wire            dmem_we,        // write enable
    output wire [2:0]      dmem_funct3,    // width/sign encoding
    input  wire [XLEN-1:0] dmem_rdata_ext, // read data from external memory/peripheral

    // IMEM data read (CPU load from 0x0000_xxxx, used for .rodata)
    output wire [31:0]     imem_drdata,

    // Debug / observation outputs
    output wire [XLEN-1:0] debug_pc,
    output wire [31:0]     debug_instr,
    output wire [XLEN-1:0] debug_alu_result
);

    // =========================================================================
    // Local parameter aliases
    // =========================================================================
    localparam ALU_A_RS1  = 2'b00;
    localparam ALU_A_PC   = 2'b01;
    localparam ALU_A_ZERO = 2'b10;

    localparam FWD_REG    = 2'b00;
    localparam FWD_MEM_WB = 2'b01;
    localparam FWD_EX_MEM = 2'b10;

    // =========================================================================
    // IF Stage
    // =========================================================================
    wire [XLEN-1:0] pc_current;
    wire [XLEN-1:0] pc_plus_4_if = pc_current + 32'd4;

    // PC-next mux is driven by EX stage signals (computed below)
    wire [XLEN-1:0] pc_next;
    wire            pc_wen;     // from hazard_detection_unit

    pc #(.XLEN(XLEN)) u_pc (
        .clk      (clk),
        .rst_n    (rst_n),
        .write_en (pc_wen),
        .next     (pc_next),
        .current  (pc_current)
    );

    wire [31:0] instr_if;

    imem #(
        .XLEN    (XLEN),
        .DEPTH   (IMEM_DEPTH),
        .MEM_FILE(IMEM_FILE)
    ) u_imem (
        .clk   (clk),
        .addr  (pc_current),
        .data  (instr_if),
        .we    (imem_we),
        .waddr (imem_waddr),
        .wdata (imem_wdata),
        .daddr (alu_result_mem),
        .ddata (imem_drdata)
    );

    // =========================================================================
    // IF/ID Register
    // =========================================================================
    wire            if_id_flush;
    wire            if_id_stall;    // driven by hazard_detection_unit

    wire [XLEN-1:0] pc_id;
    wire [XLEN-1:0] pc_plus_4_id;
    wire [31:0]     instr_id;

    if_id_reg #(.XLEN(XLEN)) u_if_id (
        .clk         (clk),
        .rst_n       (rst_n),
        .flush       (if_id_flush),
        .stall       (if_id_stall),
        .pc_if       (pc_current),
        .pc_plus_4_if(pc_plus_4_if),
        .instr_if    (instr_if),
        .pc_id       (pc_id),
        .pc_plus_4_id(pc_plus_4_id),
        .instr_id    (instr_id)
    );

    // =========================================================================
    // ID Stage — Decode & Register Read
    // =========================================================================
    wire [4:0]       rs1_id, rs2_id, rd_id;
    wire [XLEN-1:0]  imm_id;
    wire [3:0]       alu_op_id;
    wire             alu_src_id;
    wire [1:0]       alu_a_sel_id;
    wire             reg_write_en_id;
    wire             dmem_we_id;
    wire             branch_en_id;
    wire             jal_en_id;
    wire             jalr_en_id;
    wire             pc_to_reg_id;
    wire             mem_to_reg_id;
    wire             uses_rs1_id;
    wire             uses_rs2_id;
    wire [2:0]       funct3_id = instr_id[14:12];

    rv32_control #(.XLEN(XLEN)) u_ctrl (
        .instruction (instr_id),
        .rs1         (rs1_id),
        .rs2         (rs2_id),
        .rd          (rd_id),
        .imm         (imm_id),
        .alu_op      (alu_op_id),
        .alu_src     (alu_src_id),
        .alu_a_sel   (alu_a_sel_id),
        .reg_write_en(reg_write_en_id),
        .dmem_we     (dmem_we_id),
        .branch_en   (branch_en_id),
        .jal_en      (jal_en_id),
        .jalr_en     (jalr_en_id),
        .pc_to_reg   (pc_to_reg_id),
        .mem_to_reg  (mem_to_reg_id),
        .uses_rs1    (uses_rs1_id),
        .uses_rs2    (uses_rs2_id)
    );

    // Register file is written by WB (signals defined after MEM/WB section)
    wire [XLEN-1:0] rs1_data_id;
    wire [XLEN-1:0] rs2_data_id;
    wire [4:0]      rd_wb;
    wire [XLEN-1:0] wb_data;
    wire            reg_write_en_wb;

    regfile #(.XLEN(XLEN)) u_regfile (
        .clk     (clk),
        .rst_n   (rst_n),
        .rs1_addr(rs1_id),
        .rs2_addr(rs2_id),
        .rs1_data(rs1_data_id),
        .rs2_data(rs2_data_id),
        .rd_addr (rd_wb),
        .rd_data (wb_data),
        .rd_we   (reg_write_en_wb)
    );

    // =========================================================================
    // Hazard Detection
    // =========================================================================
    wire             stall_hdu;
    wire             id_ex_flush_hdu;
    wire             if_id_stall_n;  // HDU output: 0 = stall (active-low enable)
    wire [4:0]       rd_ex;          // declared here; driven by id_ex_reg below
    wire             mem_to_reg_ex;  // declared here; driven by id_ex_reg below

    assign if_id_stall = ~if_id_stall_n;

    hazard_detection_unit u_hdu (
        .if_id_rs1      (rs1_id),
        .if_id_rs2      (rs2_id),
        .if_id_uses_rs1 (uses_rs1_id),
        .if_id_uses_rs2 (uses_rs2_id),
        .id_ex_rd       (rd_ex),
        .id_ex_mem_read (mem_to_reg_ex),
        .stall          (stall_hdu),
        .pc_write_en    (pc_wen),
        .if_id_write_en (if_id_stall_n),
        .id_ex_flush    (id_ex_flush_hdu)
    );

    // =========================================================================
    // ID/EX Register
    // =========================================================================

    wire [XLEN-1:0]  pc_ex, pc_plus_4_ex;
    wire [XLEN-1:0]  rs1_data_ex, rs2_data_ex, imm_ex;
    wire [4:0]       rs1_ex, rs2_ex;
    wire [2:0]       funct3_ex;
    wire [3:0]       alu_op_ex;
    wire             alu_src_ex;
    wire [1:0]       alu_a_sel_ex;
    wire             reg_write_en_ex;
    wire             dmem_we_ex;
    wire             branch_en_ex;
    wire             jal_en_ex;
    wire             jalr_en_ex;
    wire             pc_to_reg_ex;

    // flush = HDU flush OR branch/jump taken (computed in EX, see below)
    wire id_ex_flush;

    id_ex_reg #(.XLEN(XLEN)) u_id_ex (
        .clk            (clk),
        .rst_n          (rst_n),
        .flush          (id_ex_flush),
        .stall          (stall_hdu),
        .pc_id          (pc_id),
        .pc_plus_4_id   (pc_plus_4_id),
        .rs1_data_id    (rs1_data_id),
        .rs2_data_id    (rs2_data_id),
        .imm_id         (imm_id),
        .rs1_id         (rs1_id),
        .rs2_id         (rs2_id),
        .rd_id          (rd_id),
        .funct3_id      (funct3_id),
        .alu_op_id      (alu_op_id),
        .alu_src_id     (alu_src_id),
        .alu_a_sel_id   (alu_a_sel_id),
        .reg_write_en_id(reg_write_en_id),
        .dmem_we_id     (dmem_we_id),
        .branch_en_id   (branch_en_id),
        .jal_en_id      (jal_en_id),
        .jalr_en_id     (jalr_en_id),
        .pc_to_reg_id   (pc_to_reg_id),
        .mem_to_reg_id  (mem_to_reg_id),
        .pc_ex          (pc_ex),
        .pc_plus_4_ex   (pc_plus_4_ex),
        .rs1_data_ex    (rs1_data_ex),
        .rs2_data_ex    (rs2_data_ex),
        .imm_ex         (imm_ex),
        .rs1_ex         (rs1_ex),
        .rs2_ex         (rs2_ex),
        .rd_ex          (rd_ex),
        .funct3_ex      (funct3_ex),
        .alu_op_ex      (alu_op_ex),
        .alu_src_ex     (alu_src_ex),
        .alu_a_sel_ex   (alu_a_sel_ex),
        .reg_write_en_ex(reg_write_en_ex),
        .dmem_we_ex     (dmem_we_ex),
        .branch_en_ex   (branch_en_ex),
        .jal_en_ex      (jal_en_ex),
        .jalr_en_ex     (jalr_en_ex),
        .pc_to_reg_ex   (pc_to_reg_ex),
        .mem_to_reg_ex  (mem_to_reg_ex)
    );

    // =========================================================================
    // EX Stage — Forwarding, ALU, Branch Evaluation
    // =========================================================================

    // --- Forwarding ---
    wire [1:0]  forward_a, forward_b, forward_store;
    wire [4:0]  ex_mem_rd;
    wire        ex_mem_reg_write_en;
    wire [XLEN-1:0] alu_result_mem_fwd;    // EX/MEM ALU result for forwarding
    wire [XLEN-1:0] mem_wb_rd_data;        // MEM/WB write-back data for forwarding

    forwarding_unit u_fwd (
        .id_ex_rs1         (rs1_ex),
        .id_ex_rs2         (rs2_ex),
        .ex_mem_rd         (ex_mem_rd),
        .mem_wb_rd         (rd_wb),
        .ex_mem_reg_write_en(ex_mem_reg_write_en),
        .mem_wb_reg_write_en(reg_write_en_wb),
        .forward_a         (forward_a),
        .forward_b         (forward_b),
        .forward_store     (forward_store)
    );

    // rs1 forwarding mux
    reg [XLEN-1:0] rs1_fwd;
    always @(*) begin
        case (forward_a)
            FWD_EX_MEM: rs1_fwd = alu_result_mem_fwd;
            FWD_MEM_WB: rs1_fwd = mem_wb_rd_data;
            default:    rs1_fwd = rs1_data_ex;
        endcase
    end

    // rs2 forwarding mux (before ALU src mux)
    reg [XLEN-1:0] rs2_fwd;
    always @(*) begin
        case (forward_b)
            FWD_EX_MEM: rs2_fwd = alu_result_mem_fwd;
            FWD_MEM_WB: rs2_fwd = mem_wb_rd_data;
            default:    rs2_fwd = rs2_data_ex;
        endcase
    end

    // store data forwarding mux (rs2 bypassing imm mux)
    reg [XLEN-1:0] store_data_ex;
    always @(*) begin
        case (forward_store)
            FWD_EX_MEM: store_data_ex = alu_result_mem_fwd;
            FWD_MEM_WB: store_data_ex = mem_wb_rd_data;
            default:    store_data_ex = rs2_data_ex;
        endcase
    end

    // ALU operand A mux  (00=rs1, 01=PC, 10=zero)
    reg [XLEN-1:0] alu_in1;
    always @(*) begin
        case (alu_a_sel_ex)
            ALU_A_PC:   alu_in1 = pc_ex;
            ALU_A_ZERO: alu_in1 = {XLEN{1'b0}};
            default:    alu_in1 = rs1_fwd;
        endcase
    end

    // ALU operand B mux  (0=rs2, 1=imm)
    wire [XLEN-1:0] alu_in2 = alu_src_ex ? imm_ex : rs2_fwd;

    // --- ALU ---
    wire [XLEN-1:0] alu_result_ex;
    wire            alu_zero, alu_lt, alu_ltu;

    rv32_alu #(.XLEN(XLEN)) u_alu (
        .alu_in1   (alu_in1),
        .alu_in2   (alu_in2),
        .alu_op    (alu_op_ex),
        .alu_result(alu_result_ex),
        .zero      (alu_zero),
        .lt        (alu_lt),
        .ltu       (alu_ltu)
    );

    // --- Branch condition evaluation ---
    reg branch_taken;
    always @(*) begin
        case (funct3_ex)
            3'b000: branch_taken = alu_zero;          // BEQ
            3'b001: branch_taken = !alu_zero;         // BNE
            3'b100: branch_taken = alu_lt;            // BLT
            3'b101: branch_taken = !alu_lt;           // BGE
            3'b110: branch_taken = alu_ltu;           // BLTU
            3'b111: branch_taken = !alu_ltu;          // BGEU
            default: branch_taken = 1'b0;
        endcase
    end

    wire branch_taken_w = branch_en_ex && branch_taken;

    // --- PC next computation ---
    wire [XLEN-1:0] branch_target = pc_ex + imm_ex;
    wire [XLEN-1:0] jalr_target   = (rs1_fwd + imm_ex) & {{(XLEN-1){1'b1}}, 1'b0};

    assign pc_next = jalr_en_ex    ? jalr_target   :
                     jal_en_ex     ? branch_target  :  // JAL: PC + imm_j
                     branch_taken_w ? branch_target :
                     pc_plus_4_if;

    // Flush IF/ID and ID/EX on branch or jump (2-cycle penalty)
    wire ex_redirect = branch_taken_w || jal_en_ex || jalr_en_ex;

    assign if_id_flush  = ex_redirect;
    assign id_ex_flush  = ex_redirect || id_ex_flush_hdu;

    // =========================================================================
    // EX/MEM Register
    // =========================================================================
    wire [XLEN-1:0] pc_plus_4_mem;
    wire [XLEN-1:0] alu_result_mem;
    wire [XLEN-1:0] rs2_data_mem;
    wire [2:0]      funct3_mem;
    wire            dmem_we_mem;
    wire            pc_to_reg_mem;
    wire            mem_to_reg_mem;

    ex_mem_reg #(.XLEN(XLEN)) u_ex_mem (
        .clk            (clk),
        .rst_n          (rst_n),
        .flush          (1'b0),              // no flush needed at EX/MEM boundary
        .pc_plus_4_ex   (pc_plus_4_ex),
        .alu_result_ex  (alu_result_ex),
        .rs2_data_ex    (store_data_ex),
        .rd_ex          (rd_ex),
        .funct3_ex      (funct3_ex),
        .reg_write_en_ex(reg_write_en_ex),
        .dmem_we_ex     (dmem_we_ex),
        .pc_to_reg_ex   (pc_to_reg_ex),
        .mem_to_reg_ex  (mem_to_reg_ex),
        .pc_plus_4_mem  (pc_plus_4_mem),
        .alu_result_mem (alu_result_mem),
        .rs2_data_mem   (rs2_data_mem),
        .rd_mem         (ex_mem_rd),
        .funct3_mem     (funct3_mem),
        .reg_write_en_mem(ex_mem_reg_write_en),
        .dmem_we_mem    (dmem_we_mem),
        .pc_to_reg_mem  (pc_to_reg_mem),
        .mem_to_reg_mem (mem_to_reg_mem)
    );

    // Wire for forwarding unit (EX/MEM ALU result)
    assign alu_result_mem_fwd = alu_result_mem;

    // =========================================================================
    // MEM Stage — Data Memory
    // =========================================================================

    // External DMEM bus outputs (always driven from the MEM stage)
    assign dmem_addr   = alu_result_mem;
    assign dmem_wdata  = rs2_data_mem;
    assign dmem_we     = dmem_we_mem;
    assign dmem_funct3 = funct3_mem;

    // Internal DMEM is instantiated only when EXT_DMEM==0
    wire [XLEN-1:0] dmem_rdata_int;
    generate
        if (EXT_DMEM == 0) begin : gen_int_dmem
            dmem #(
                .XLEN    (XLEN),
                .DEPTH   (DMEM_DEPTH),
                .MEM_FILE(DMEM_FILE)
            ) u_dmem (
                .clk    (clk),
                .we     (dmem_we_mem),
                .funct3 (funct3_mem),
                .addr   (alu_result_mem),
                .wdata  (rs2_data_mem),
                .rdata  (dmem_rdata_int)
            );
        end else begin : gen_ext_dmem
            assign dmem_rdata_int = {XLEN{1'b0}}; // unused placeholder
        end
    endgenerate

    wire [XLEN-1:0] dmem_rdata_mem = (EXT_DMEM == 1) ? dmem_rdata_ext : dmem_rdata_int;

    // =========================================================================
    // MEM/WB Register
    // =========================================================================
    wire [XLEN-1:0] pc_plus_4_wb_r;
    wire [XLEN-1:0] alu_result_wb;
    wire [XLEN-1:0] dmem_rdata_wb;
    wire [2:0]      funct3_wb;
    wire            pc_to_reg_wb;
    wire            mem_to_reg_wb;

    mem_wb_reg #(.XLEN(XLEN)) u_mem_wb (
        .clk            (clk),
        .rst_n          (rst_n),
        .pc_plus_4_mem  (pc_plus_4_mem),
        .alu_result_mem (alu_result_mem),
        .dmem_rdata_mem (dmem_rdata_mem),
        .rd_mem         (ex_mem_rd),
        .funct3_mem     (funct3_mem),
        .reg_write_en_mem(ex_mem_reg_write_en),
        .pc_to_reg_mem  (pc_to_reg_mem),
        .mem_to_reg_mem (mem_to_reg_mem),
        .pc_plus_4_wb   (pc_plus_4_wb_r),
        .alu_result_wb  (alu_result_wb),
        .dmem_rdata_wb  (dmem_rdata_wb),
        .rd_wb          (rd_wb),
        .funct3_wb      (funct3_wb),
        .reg_write_en_wb(reg_write_en_wb),
        .pc_to_reg_wb   (pc_to_reg_wb),
        .mem_to_reg_wb  (mem_to_reg_wb)
    );

    // =========================================================================
    // WB Stage — Load Extension & Write-Back Mux
    // =========================================================================

    // Byte / halfword selection from the full word read by dmem.
    // alu_result_wb[1:0] carries the effective byte offset within the word.
    wire [1:0] byte_off = alu_result_wb[1:0];

    wire [7:0] byte_sel = (byte_off == 2'b00) ? dmem_rdata_wb[7:0]   :
                          (byte_off == 2'b01) ? dmem_rdata_wb[15:8]  :
                          (byte_off == 2'b10) ? dmem_rdata_wb[23:16] :
                                                dmem_rdata_wb[31:24];

    wire [15:0] half_sel = byte_off[1] ? dmem_rdata_wb[31:16] : dmem_rdata_wb[15:0];

    reg [XLEN-1:0] load_data;
    always @(*) begin
        case (funct3_wb)
            3'b000: load_data = {{24{byte_sel[7]}},  byte_sel};    // LB
            3'b001: load_data = {{16{half_sel[15]}}, half_sel};    // LH
            3'b010: load_data = dmem_rdata_wb;                     // LW
            3'b100: load_data = {24'b0, byte_sel};                 // LBU
            3'b101: load_data = {16'b0, half_sel};                 // LHU
            default: load_data = dmem_rdata_wb;
        endcase
    end

    // Write-back mux: PC+4 has highest priority (JAL/JALR), then load data, then ALU result
    assign wb_data = pc_to_reg_wb  ? pc_plus_4_wb_r :
                     mem_to_reg_wb ? load_data        :
                     alu_result_wb;

    // Forwarding from WB stage to EX stage forwarding muxes
    assign mem_wb_rd_data = wb_data;

    // =========================================================================
    // Debug outputs
    // =========================================================================
    assign debug_pc         = pc_current;
    assign debug_instr      = instr_if;
    assign debug_alu_result = alu_result_ex;

endmodule
