`timescale 1ns / 1ps

/*
 * RISC-V 5-Stage Pipeline Testbench - Prototip 2
 *
 * Prototip-1'deki testlere ek olarak:
 * - Byte Load/Store (LB/LBU/SB) testleri
 * - Halfword Load/Store (LH/LHU/SH) testleri
 * - Wishbone bus handshaking dogrulamasi
 * - Bus error testi
 *
 * TEST 1: Basic 5-Stage Pipeline Flow
 * TEST 2: Data Hazard with Forwarding (EX-to-EX)
 * TEST 3: Data Hazard with Forwarding (MEM-to-EX)
 * TEST 4: Load-Use Hazard with Stall
 * TEST 5: Branch Taken with Flush
 * TEST 6: Byte Load/Store (LB/LBU/SB) - YENI
 * TEST 7: Halfword Load/Store (LH/LHU/SH) - YENI
 * TEST 8: Complete Demonstration (All Features)
 */

module tb_rv32_core;
    parameter XLEN  = 32;
    parameter CYCLE = 10;

    // DUT signals
    reg                     clk;
    reg                     rst_n;
    wire [XLEN-1:0]         imem_addr;
    wire [31:0]             imem_rdata;

    // Wishbone bus signals
    wire [XLEN-1:0]         wb_adr;
    wire [31:0]             wb_dat_w;
    wire                    wb_we;
    wire [3:0]              wb_sel;
    wire                    wb_stb;
    wire                    wb_cyc;
    wire [31:0]             wb_dat_r;
    wire                    wb_ack;
    wire                    wb_err;

    wire [7:0]              dbg_out;

    // Memory
    reg [31:0] imem [0:1023];
    reg [31:0] dmem [0:1023];

    // Test tracking
    integer cycle_count;
    integer test_number;
    integer errors;
    integer i;

    // Pipeline visibility
    wire [31:0] if_pc;
    wire [31:0] id_pc;
    wire [31:0] ex_pc;

    wire stall_detected;
    wire flush_detected;
    wire [1:0] forward_a;
    wire [1:0] forward_b;

    // Register file values
    wire [31:0] reg_x1, reg_x2, reg_x3, reg_x4, reg_x5, reg_x6;
    wire [31:0] reg_x7, reg_x8, reg_x9, reg_x10;

    // Internal signal assignments
    assign if_pc = u_core.pc_current;
    assign id_pc = u_core.pc_id;
    assign ex_pc = u_core.pc_ex;

    assign stall_detected = u_core.hazard_stall;
    assign flush_detected = u_core.if_id_flush;

    assign forward_a = u_core.u_forwarding.forward_a;
    assign forward_b = u_core.u_forwarding.forward_b;

    assign reg_x1  = u_core.u_regfile.regs[1];
    assign reg_x2  = u_core.u_regfile.regs[2];
    assign reg_x3  = u_core.u_regfile.regs[3];
    assign reg_x4  = u_core.u_regfile.regs[4];
    assign reg_x5  = u_core.u_regfile.regs[5];
    assign reg_x6  = u_core.u_regfile.regs[6];
    assign reg_x7  = u_core.u_regfile.regs[7];
    assign reg_x8  = u_core.u_regfile.regs[8];
    assign reg_x9  = u_core.u_regfile.regs[9];
    assign reg_x10 = u_core.u_regfile.regs[10];

    //==========================================================================
    // INSTRUCTION ENCODING FUNCTIONS
    //==========================================================================
    function [31:0] encode_r_type;
        input [6:0] opcode;
        input [4:0] rd;
        input [2:0] funct3;
        input [4:0] rs1;
        input [4:0] rs2;
        input [6:0] funct7;
    begin
        encode_r_type = {funct7, rs2, rs1, funct3, rd, opcode};
    end
    endfunction

    function [31:0] encode_i_type;
        input [6:0] opcode;
        input [4:0] rd;
        input [2:0] funct3;
        input [4:0] rs1;
        input [11:0] imm;
    begin
        encode_i_type = {imm, rs1, funct3, rd, opcode};
    end
    endfunction

    function [31:0] encode_s_type;
        input [6:0] opcode;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rs2;
        input [11:0] imm;
    begin
        encode_s_type = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
    end
    endfunction

    function [31:0] encode_b_type;
        input [6:0] opcode;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rs2;
        input [12:0] imm;
    begin
        encode_b_type = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
    end
    endfunction

    // Opcodes
    localparam OP_R = 7'b0110011;
    localparam OP_I = 7'b0010011;
    localparam OP_L = 7'b0000011;
    localparam OP_S = 7'b0100011;
    localparam OP_B = 7'b1100011;

    localparam F3_ADD_SUB = 3'b000;
    localparam F3_AND     = 3'b111;
    localparam F3_OR      = 3'b110;

    localparam F7_ADD = 7'b0000000;
    localparam F7_SUB = 7'b0100000;

    localparam F3_BEQ = 3'b000;
    localparam F3_BNE = 3'b001;

    // Load funct3
    localparam F3_LB  = 3'b000;
    localparam F3_LH  = 3'b001;
    localparam F3_LW  = 3'b010;
    localparam F3_LBU = 3'b100;
    localparam F3_LHU = 3'b101;

    // Store funct3
    localparam F3_SB  = 3'b000;
    localparam F3_SH  = 3'b001;
    localparam F3_SW  = 3'b010;

    //==========================================================================
    // TASKS
    //==========================================================================
    task clear_memories;
        integer k;
    begin
        for (k = 0; k < 1024; k = k + 1) begin
            imem[k] = 32'h0000_0013;  // NOP
            dmem[k] = 32'h0;
        end
    end
    endtask

    task reset_processor;
    begin
        $display("\n===== RESET =====");
        rst_n = 1'b0;
        cycle_count = 0;
        repeat(3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        $display("Reset complete\n");
    end
    endtask

    task run_cycles;
        input integer num_cycles;
    begin
        repeat(num_cycles) @(posedge clk);
    end
    endtask

    task check_reg;
        input [255:0] name;
        input [31:0] actual;
        input [31:0] expected;
    begin
        if (actual === expected)
            $display("  [PASS] %0s = 0x%08x", name, actual);
        else begin
            $display("  [FAIL] %0s = 0x%08x (beklenen: 0x%08x)", name, actual, expected);
            errors = errors + 1;
        end
    end
    endtask

    //==========================================================================
    // TEST 1: BASIC 5-STAGE PIPELINE
    //==========================================================================
    task test_1_basic_pipeline;
    begin
        test_number = 1;
        $display("\n================================================================================");
        $display("TEST 1: BASIC 5-STAGE PIPELINE FLOW");
        $display("================================================================================");

        clear_memories;

        imem[0] = encode_i_type(OP_I, 5'd1, F3_ADD_SUB, 5'd0, 12'd10);
        imem[1] = encode_i_type(OP_I, 5'd2, F3_ADD_SUB, 5'd0, 12'd20);
        imem[2] = encode_i_type(OP_I, 5'd3, F3_ADD_SUB, 5'd0, 12'd30);
        imem[3] = encode_i_type(OP_I, 5'd4, F3_ADD_SUB, 5'd0, 12'd40);
        imem[4] = encode_i_type(OP_I, 5'd5, F3_ADD_SUB, 5'd0, 12'd50);
        imem[5] = encode_i_type(OP_I, 5'd6, F3_ADD_SUB, 5'd0, 12'd60);

        reset_processor;
        run_cycles(12);

        $display("===== SONUCLAR =====");
        check_reg("x1", reg_x1, 32'd10);
        check_reg("x2", reg_x2, 32'd20);
        check_reg("x3", reg_x3, 32'd30);
        check_reg("x4", reg_x4, 32'd40);
        check_reg("x5", reg_x5, 32'd50);
        check_reg("x6", reg_x6, 32'd60);
    end
    endtask

    //==========================================================================
    // TEST 2: DATA HAZARD WITH FORWARDING (EX-to-EX)
    //==========================================================================
    task test_2_forwarding_ex_to_ex;
    begin
        test_number = 2;
        $display("\n================================================================================");
        $display("TEST 2: DATA HAZARD WITH FORWARDING (EX-to-EX)");
        $display("================================================================================");

        clear_memories;

        imem[0] = encode_i_type(OP_I, 5'd1, F3_ADD_SUB, 5'd0, 12'd100);
        imem[1] = encode_r_type(OP_R, 5'd3, F3_ADD_SUB, 5'd1, 5'd0, F7_ADD);
        imem[2] = encode_i_type(OP_I, 5'd4, F3_ADD_SUB, 5'd3, 12'd50);
        imem[3] = encode_i_type(OP_I, 5'd5, F3_ADD_SUB, 5'd0, 12'd999);

        reset_processor;
        run_cycles(12);

        $display("===== SONUCLAR =====");
        check_reg("x1", reg_x1, 32'd100);
        check_reg("x3", reg_x3, 32'd100);
        check_reg("x4", reg_x4, 32'd150);
        check_reg("x5", reg_x5, 32'd999);
    end
    endtask

    //==========================================================================
    // TEST 3: DATA HAZARD WITH FORWARDING (MEM-to-EX)
    //==========================================================================
    task test_3_forwarding_mem_to_ex;
    begin
        test_number = 3;
        $display("\n================================================================================");
        $display("TEST 3: DATA HAZARD WITH FORWARDING (MEM-to-EX)");
        $display("================================================================================");

        clear_memories;

        imem[0] = encode_i_type(OP_I, 5'd1, F3_ADD_SUB, 5'd0, 12'd200);
        imem[1] = encode_i_type(OP_I, 5'd2, F3_ADD_SUB, 5'd0, 12'd5);
        imem[2] = encode_r_type(OP_R, 5'd3, F3_ADD_SUB, 5'd1, 5'd2, F7_ADD);
        imem[3] = encode_i_type(OP_I, 5'd4, F3_ADD_SUB, 5'd0, 12'd777);

        reset_processor;
        run_cycles(12);

        $display("===== SONUCLAR =====");
        check_reg("x1", reg_x1, 32'd200);
        check_reg("x2", reg_x2, 32'd5);
        check_reg("x3", reg_x3, 32'd205);
        check_reg("x4", reg_x4, 32'd777);
    end
    endtask

    //==========================================================================
    // TEST 4: LOAD-USE HAZARD WITH STALL (LW)
    //==========================================================================
    task test_4_load_use_stall;
    begin
        test_number = 4;
        $display("\n================================================================================");
        $display("TEST 4: LOAD-USE HAZARD WITH STALL (LW)");
        $display("================================================================================");

        clear_memories;

        // DMEM base: 0x2000_0000
        dmem[0] = 32'd555;

        // LUI x1, 0x20000 (x1 = 0x20000000)
        imem[0] = {20'h20000, 5'd1, 7'b0110111};   // LUI x1, 0x20000
        imem[1] = encode_i_type(OP_L, 5'd2, F3_LW, 5'd1, 12'd0);          // x2 = mem[x1+0] = 555
        imem[2] = encode_i_type(OP_I, 5'd3, F3_ADD_SUB, 5'd2, 12'd100);   // x3 = x2 + 100 (STALL!)
        imem[3] = encode_i_type(OP_I, 5'd4, F3_ADD_SUB, 5'd0, 12'd888);

        reset_processor;
        run_cycles(14);

        $display("===== SONUCLAR =====");
        check_reg("x1", reg_x1, 32'h2000_0000);
        check_reg("x2", reg_x2, 32'd555);
        check_reg("x3", reg_x3, 32'd655);
        check_reg("x4", reg_x4, 32'd888);
    end
    endtask

    //==========================================================================
    // TEST 5: BRANCH TAKEN WITH FLUSH
    //==========================================================================
    task test_5_branch_flush;
    begin
        test_number = 5;
        $display("\n================================================================================");
        $display("TEST 5: BRANCH TAKEN WITH FLUSH");
        $display("================================================================================");

        clear_memories;

        imem[0] = encode_i_type(OP_I, 5'd1, F3_ADD_SUB, 5'd0, 12'd50);
        imem[1] = encode_i_type(OP_I, 5'd2, F3_ADD_SUB, 5'd0, 12'd50);
        imem[2] = encode_b_type(OP_B, 5'd1, F3_BEQ, 5'd2, 13'd16);       // BEQ x1,x2,+16 -> [0x18]
        imem[3] = encode_i_type(OP_I, 5'd3, F3_ADD_SUB, 5'd0, 12'd111);   // FLUSH!
        imem[4] = encode_i_type(OP_I, 5'd4, F3_ADD_SUB, 5'd0, 12'd222);   // FLUSH!
        imem[5] = encode_i_type(OP_I, 5'd5, F3_ADD_SUB, 5'd0, 12'd333);   // FLUSH!
        imem[6] = encode_i_type(OP_I, 5'd6, F3_ADD_SUB, 5'd0, 12'd444);   // Branch target

        reset_processor;
        run_cycles(14);

        $display("===== SONUCLAR =====");
        check_reg("x1", reg_x1, 32'd50);
        check_reg("x2", reg_x2, 32'd50);
        check_reg("x3", reg_x3, 32'd0);     // FLUSH!
        check_reg("x6", reg_x6, 32'd444);   // Branch target
    end
    endtask

    //==========================================================================
    // TEST 6: BYTE LOAD/STORE (LB/LBU/SB) - YENI
    //==========================================================================
    task test_6_byte_load_store;
    begin
        test_number = 6;
        $display("\n================================================================================");
        $display("TEST 6: BYTE LOAD/STORE (LB/LBU/SB) - YENI OZELLIK");
        $display("================================================================================");
        $display("AMAC: Byte bazinda bellek erisimini test etmek");
        $display("  - SB: tek byte yazar");
        $display("  - LB: signed byte okur (sign-extension)");
        $display("  - LBU: unsigned byte okur (zero-extension)");
        $display("================================================================================");

        clear_memories;

        // DMEM'e test verisi yaz
        dmem[0] = 32'hDEAD_BEEF;

        // x1 = 0x2000_0000 (DMEM base)
        imem[0] = {20'h20000, 5'd1, 7'b0110111};   // LUI x1, 0x20000

        // LBU x2, 0(x1)  -> byte[0] = 0xEF -> zero-ext -> 0x000000EF
        imem[1] = encode_i_type(OP_L, 5'd2, F3_LBU, 5'd1, 12'd0);

        // LBU x3, 1(x1)  -> byte[1] = 0xBE -> zero-ext -> 0x000000BE
        imem[2] = encode_i_type(OP_L, 5'd3, F3_LBU, 5'd1, 12'd1);

        // LBU x4, 2(x1)  -> byte[2] = 0xAD -> zero-ext -> 0x000000AD
        imem[3] = encode_i_type(OP_L, 5'd4, F3_LBU, 5'd1, 12'd2);

        // LBU x5, 3(x1)  -> byte[3] = 0xDE -> zero-ext -> 0x000000DE
        imem[4] = encode_i_type(OP_L, 5'd5, F3_LBU, 5'd1, 12'd3);

        // LB x6, 0(x1)  -> byte[0] = 0xEF -> sign-ext -> 0xFFFFFFEF (negatif!)
        imem[5] = encode_i_type(OP_L, 5'd6, F3_LB, 5'd1, 12'd0);

        // LB x7, 1(x1)  -> byte[1] = 0xBE -> sign-ext -> 0xFFFFFFBE (negatif!)
        imem[6] = encode_i_type(OP_L, 5'd7, F3_LB, 5'd1, 12'd1);

        // SB: x8 = 0x42, store byte to offset 4
        imem[7] = encode_i_type(OP_I, 5'd8, F3_ADD_SUB, 5'd0, 12'h42);     // x8 = 0x42
        imem[8] = encode_s_type(OP_S, 5'd1, F3_SB, 5'd8, 12'd4);           // SB x8, 4(x1) -> mem[0x2000_0004] byte[0] = 0x42

        // LW x9, 4(x1)  -> word tamamini oku (sadece byte[0] = 0x42, geri kalan 0)
        imem[9]  = encode_i_type(OP_L, 5'd9, F3_LW, 5'd1, 12'd4);

        reset_processor;
        run_cycles(20);

        $display("===== SONUCLAR =====");
        $display("DMEM[0] = 0x%08x (0xDEADBEEF)", dmem[0]);
        check_reg("x2 (LBU byte0)", reg_x2, 32'h000000EF);
        check_reg("x3 (LBU byte1)", reg_x3, 32'h000000BE);
        check_reg("x4 (LBU byte2)", reg_x4, 32'h000000AD);
        check_reg("x5 (LBU byte3)", reg_x5, 32'h000000DE);
        check_reg("x6 (LB  byte0)", reg_x6, 32'hFFFFFFEF);
        check_reg("x7 (LB  byte1)", reg_x7, 32'hFFFFFFBE);
        check_reg("x9 (LW after SB)", reg_x9, 32'h00000042);
    end
    endtask

    //==========================================================================
    // TEST 7: HALFWORD LOAD/STORE (LH/LHU/SH) - YENI
    //==========================================================================
    task test_7_halfword_load_store;
    begin
        test_number = 7;
        $display("\n================================================================================");
        $display("TEST 7: HALFWORD LOAD/STORE (LH/LHU/SH) - YENI OZELLIK");
        $display("================================================================================");
        $display("AMAC: Halfword (16-bit) bazinda bellek erisimini test etmek");
        $display("  - SH: 2 byte yazar");
        $display("  - LH: signed halfword okur (sign-extension)");
        $display("  - LHU: unsigned halfword okur (zero-extension)");
        $display("================================================================================");

        clear_memories;

        // DMEM'e test verisi: 0xCAFE_8080
        dmem[2] = 32'hCAFE_8080;  // Adres: 0x2000_0008

        // x1 = 0x2000_0000 (DMEM base)
        imem[0] = {20'h20000, 5'd1, 7'b0110111};   // LUI x1, 0x20000

        // LHU x2, 8(x1) -> lower halfword = 0x8080 -> zero-ext -> 0x00008080
        imem[1] = encode_i_type(OP_L, 5'd2, F3_LHU, 5'd1, 12'd8);

        // LHU x3, 10(x1) -> upper halfword = 0xCAFE -> zero-ext -> 0x0000CAFE
        imem[2] = encode_i_type(OP_L, 5'd3, F3_LHU, 5'd1, 12'd10);

        // LH x4, 8(x1) -> lower halfword = 0x8080 -> sign-ext -> 0xFFFF8080 (negatif!)
        imem[3] = encode_i_type(OP_L, 5'd4, F3_LH, 5'd1, 12'd8);

        // LH x5, 10(x1) -> upper halfword = 0xCAFE -> sign-ext -> 0xFFFFCAFE (negatif!)
        imem[4] = encode_i_type(OP_L, 5'd5, F3_LH, 5'd1, 12'd10);

        // SH: x6 = 0xABCD, store halfword to offset 12
        imem[5] = encode_i_type(OP_I, 5'd6, F3_ADD_SUB, 5'd0, 12'hABC);    // x6 = 0xABC (not full, use LUI+ADDI)

        // Daha basit: x6 = 0x1234 (12-bit immediate ile)
        imem[5] = encode_i_type(OP_I, 5'd6, F3_ADD_SUB, 5'd0, 12'h234);    // x6 = 0x234
        imem[6] = encode_s_type(OP_S, 5'd1, F3_SH, 5'd6, 12'd12);          // SH x6, 12(x1) -> mem[0x200_000C] lower half = 0x0234

        // LW x7, 12(x1) -> word = 0x00000234
        imem[7] = encode_i_type(OP_L, 5'd7, F3_LW, 5'd1, 12'd12);

        reset_processor;
        run_cycles(18);

        $display("===== SONUCLAR =====");
        $display("DMEM[2] = 0x%08x (0xCAFE8080)", dmem[2]);
        check_reg("x2 (LHU lower)", reg_x2, 32'h00008080);
        check_reg("x3 (LHU upper)", reg_x3, 32'h0000CAFE);
        check_reg("x4 (LH  lower)", reg_x4, 32'hFFFF8080);
        check_reg("x5 (LH  upper)", reg_x5, 32'hFFFFCAFE);
        check_reg("x7 (LW after SH)", reg_x7, 32'h00000234);
    end
    endtask

    //==========================================================================
    // TEST 8: COMPLETE DEMONSTRATION
    //==========================================================================
    task test_8_complete_demo;
    begin
        test_number = 8;
        $display("\n================================================================================");
        $display("TEST 8: COMPLETE DEMONSTRATION - ALL FEATURES");
        $display("================================================================================");
        $display("AMAC: Tum pipeline ozelliklerini + byte/halfword erisimi bir arada");
        $display("================================================================================");

        clear_memories;

        // Prepare memory
        dmem[0] = 32'h00000055;   // 0x2000_0000 = 0x55
        dmem[1] = 32'hFFFF_AABB;  // 0x2000_0004 = 0xFFFFAABB

        // x1 = 0x2000_0000
        imem[0]  = {20'h20000, 5'd1, 7'b0110111};

        // x2 = 5 (immediate)
        imem[1]  = encode_i_type(OP_I, 5'd2, F3_ADD_SUB, 5'd0, 12'd5);

        // x3 = x2 + x2 = 10 (EX-to-EX forwarding)
        imem[2]  = encode_r_type(OP_R, 5'd3, F3_ADD_SUB, 5'd2, 5'd2, F7_ADD);

        // LW x4, 0(x1) = 0x55 (word load)
        imem[3]  = encode_i_type(OP_L, 5'd4, F3_LW, 5'd1, 12'd0);

        // x5 = x4 + x3 (load-use STALL + forwarding)
        imem[4]  = encode_r_type(OP_R, 5'd5, F3_ADD_SUB, 5'd4, 5'd3, F7_ADD);

        // LBU x6, 4(x1) = byte[0] of 0xFFFFAABB = 0xBB -> 0x000000BB
        imem[5]  = encode_i_type(OP_L, 5'd6, F3_LBU, 5'd1, 12'd4);

        // LB x7, 5(x1) = byte[1] of 0xFFFFAABB = 0xAA -> sign-ext -> 0xFFFFFFAA
        imem[6]  = encode_i_type(OP_L, 5'd7, F3_LB, 5'd1, 12'd5);

        // SB x2, 8(x1) -> store byte 0x05 to 0x2000_0008
        imem[7]  = encode_s_type(OP_S, 5'd1, F3_SB, 5'd2, 12'd8);

        // LW x8, 8(x1) -> verify SB wrote correctly
        imem[8]  = encode_i_type(OP_L, 5'd8, F3_LW, 5'd1, 12'd8);

        reset_processor;
        run_cycles(22);

        $display("===== SONUCLAR =====");
        check_reg("x1 (base addr)",  reg_x1, 32'h2000_0000);
        check_reg("x2 (imm 5)",      reg_x2, 32'd5);
        check_reg("x3 (fwd 5+5)",    reg_x3, 32'd10);
        check_reg("x4 (LW 0x55)",    reg_x4, 32'h55);
        check_reg("x5 (stall+fwd)",  reg_x5, 32'h5F);  // 0x55 + 10 = 0x5F = 95
        check_reg("x6 (LBU 0xBB)",   reg_x6, 32'h000000BB);
        check_reg("x7 (LB  0xAA)",   reg_x7, 32'hFFFFFFAA);
        check_reg("x8 (LW after SB)", reg_x8, 32'h00000005);
    end
    endtask

    //==========================================================================
    // Memory Interface (Wishbone-compatible)
    //==========================================================================
    // IMEM: dogrudan (Harvard)
    assign imem_rdata = imem[imem_addr >> 2];

    // DMEM: Wishbone slave emulation
    // Byte-enable destekli okuma/yazma
    reg [31:0] dmem_read_data;
    wire [31:0] dmem_word_addr = (wb_adr - 32'h2000_0000) >> 2;
    wire dmem_addr_valid = (wb_adr >= 32'h2000_0000) && (wb_adr < 32'h2000_1000);

    always @(*) begin
        if (dmem_addr_valid)
            dmem_read_data = dmem[dmem_word_addr];
        else
            dmem_read_data = 32'hDEAD_BEEF;
    end

    always @(posedge clk) begin
        if (wb_stb && wb_cyc && wb_we && dmem_addr_valid) begin
            if (wb_sel[0]) dmem[dmem_word_addr][ 7: 0] <= wb_dat_w[ 7: 0];
            if (wb_sel[1]) dmem[dmem_word_addr][15: 8] <= wb_dat_w[15: 8];
            if (wb_sel[2]) dmem[dmem_word_addr][23:16] <= wb_dat_w[23:16];
            if (wb_sel[3]) dmem[dmem_word_addr][31:24] <= wb_dat_w[31:24];
        end
    end

    assign wb_dat_r = dmem_read_data;
    assign wb_ack   = wb_stb & wb_cyc & dmem_addr_valid;
    assign wb_err   = wb_stb & wb_cyc & ~dmem_addr_valid;

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    rv32_core_pipelined #(
        .XLEN(XLEN)
    ) u_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),
        .wb_adr_o   (wb_adr),
        .wb_dat_o   (wb_dat_w),
        .wb_we_o    (wb_we),
        .wb_sel_o   (wb_sel),
        .wb_stb_o   (wb_stb),
        .wb_cyc_o   (wb_cyc),
        .wb_dat_i   (wb_dat_r),
        .wb_ack_i   (wb_ack),
        .wb_err_i   (wb_err),
        .dbg_out    (dbg_out)
    );

    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial begin
        clk = 1'b0;
        forever #(CYCLE/2) clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end

    //==========================================================================
    // Pipeline Monitor
    //==========================================================================
    always @(posedge clk) begin
        if (rst_n) begin
            $display("[Cyc %3d] IF:0x%02x ID:0x%02x EX:0x%02x | Fwd:%b/%b | Stall:%b Flush:%b | WB: sel=%b we=%b stb=%b ack=%b",
                     cycle_count, if_pc[7:0], id_pc[7:0], ex_pc[7:0],
                     forward_a, forward_b, stall_detected, flush_detected,
                     wb_sel, wb_we, wb_stb, wb_ack);
        end
    end

    //==========================================================================
    // Main Test Execution
    //==========================================================================
    initial begin
        cycle_count = 0;
        test_number = 0;
        errors = 0;

        for (i = 0; i < 1024; i = i + 1) begin
            imem[i] = 32'h0000_0013;  // NOP
            dmem[i] = 32'h0;
        end

        $display("\n");
        $display("################################################################################");
        $display("##                                                                            ##");
        $display("##   RISC-V 5-STAGE PIPELINED PROCESSOR - PROTOTIP 2 TEST SUITE              ##");
        $display("##                                                                            ##");
        $display("##   Yeni Ozellikler:                                                         ##");
        $display("##     - Wishbone B4 Bus Protokolu                                            ##");
        $display("##     - Byte Load/Store (LB/LBU/SB)                                          ##");
        $display("##     - Halfword Load/Store (LH/LHU/SH)                                      ##");
        $display("##     - Bus Error Algilama                                                    ##");
        $display("##                                                                            ##");
        $display("################################################################################");
        $display("\n");

        #50;

        test_1_basic_pipeline;      #100;
        test_2_forwarding_ex_to_ex; #100;
        test_3_forwarding_mem_to_ex;#100;
        test_4_load_use_stall;      #100;
        test_5_branch_flush;        #100;
        test_6_byte_load_store;     #100;
        test_7_halfword_load_store; #100;
        test_8_complete_demo;       #100;

        // Final summary
        $display("\n");
        $display("################################################################################");
        if (errors == 0) begin
            $display("##        TUM TESTLER BASARILI! Hata sayisi: 0                               ##");
        end else begin
            $display("##        HATALI TEST VAR! Toplam hata: %0d                                    ##", errors);
        end
        $display("################################################################################");
        $display("\n");

        #200;
        $finish;
    end

    //==========================================================================
    // Waveform dump
    //==========================================================================
    initial begin
        $dumpfile("tb_rv32_core.vcd");
        $dumpvars(0, tb_rv32_core);
    end

endmodule
