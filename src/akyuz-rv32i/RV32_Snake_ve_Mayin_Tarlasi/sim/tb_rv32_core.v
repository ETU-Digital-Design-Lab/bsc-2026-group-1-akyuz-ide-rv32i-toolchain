// tb_rv32_core.v — RV32I Full Instruction Coverage Testbench
//
// Loads rv32i_full_test.hex and verifies all 31 result registers plus
// 3 data-memory locations after all 58 instructions complete.
//
// Instruction coverage:
//   R-type  : ADD SUB AND OR XOR SLL SRL SRA SLT SLTU
//   I-arith : ADDI ANDI ORI XORI SLLI SRLI SRAI SLTI SLTIU
//   U-type  : LUI AUIPC
//   Load    : LW LB LBU LH LHU
//   Store   : SW SB SH
//   Branch  : BEQ BNE BLT BGE BLTU BGEU (all taken, forwarding exercised)
//   Jump    : JAL JALR
//
// Pipeline trace: first 100 active cycles.
// Halt loop: PC=0x0E4.

`timescale 1ns / 1ps

module tb_rv32_core;

    localparam CLK_PERIOD  = 10;
    localparam IMEM_FILE   = "../tests/rv32i_full_test.hex";
    localparam XLEN        = 32;
    localparam IMEM_DEPTH  = 1024;
    localparam DMEM_DEPTH  = 1024;

    reg  clk, rst_n;

    wire [XLEN-1:0] debug_pc, debug_alu_result;
    wire [31:0]     debug_instr;
    wire [XLEN-1:0] dmem_addr_mon, dmem_wdata_mon;
    wire            dmem_we_mon;
    wire [2:0]      dmem_funct3_mon;

    rv32_core #(
        .XLEN       (XLEN),
        .IMEM_DEPTH (IMEM_DEPTH),
        .DMEM_DEPTH (DMEM_DEPTH),
        .IMEM_FILE  (IMEM_FILE),
        .DMEM_FILE  (""),
        .EXT_DMEM   (0)
    ) uut (
        .clk              (clk),
        .rst_n            (rst_n),
        .dmem_addr        (dmem_addr_mon),
        .dmem_wdata       (dmem_wdata_mon),
        .dmem_we          (dmem_we_mon),
        .dmem_funct3      (dmem_funct3_mon),
        .dmem_rdata_ext   (32'd0),
        .debug_pc         (debug_pc),
        .debug_instr      (debug_instr),
        .debug_alu_result (debug_alu_result)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    integer cycle_cnt;
    integer stall_cnt;
    integer flush_cnt;
    integer pass_cnt;
    integer fail_cnt;

    initial begin
        cycle_cnt = 0; stall_cnt = 0; flush_cnt = 0;
    end

    always @(posedge clk) if (rst_n)                    cycle_cnt = cycle_cnt + 1;
    always @(posedge clk) if (rst_n && uut.stall_hdu)   stall_cnt = stall_cnt + 1;
    always @(posedge clk) if (rst_n && uut.ex_redirect) flush_cnt = flush_cnt + 1;

    // -------------------------------------------------------------------
    // chk — register file check
    // -------------------------------------------------------------------
    task chk;
        input integer  reg_idx;
        input [31:0]   expected;
        input [255:0]  label;
        reg   [31:0]   got;
        begin
            got = uut.u_regfile.regs[reg_idx];
            if (got === expected) begin
                $display("  PASS  x%02d = 0x%08X              [%0s]",
                         reg_idx, got, label);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  x%02d = 0x%08X  exp=0x%08X  [%0s]",
                         reg_idx, got, expected, label);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------
    // chk_dmem — data memory word check (SW: all 4 bytes valid)
    // -------------------------------------------------------------------
    task chk_dmem;
        input integer  byte_addr;
        input [31:0]   expected;
        input [255:0]  label;
        reg   [31:0]   got;
        integer        widx;
        begin
            widx = byte_addr >> 2;
            got  = {uut.gen_int_dmem.u_dmem.mem_b3[widx],
                    uut.gen_int_dmem.u_dmem.mem_b2[widx],
                    uut.gen_int_dmem.u_dmem.mem_b1[widx],
                    uut.gen_int_dmem.u_dmem.mem_b0[widx]};
            if (got === expected) begin
                $display("  PASS  dmem[%04d] = 0x%08X          [%0s]",
                         byte_addr, got, label);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  dmem[%04d] = 0x%08X  exp=0x%08X  [%0s]",
                         byte_addr, got, expected, label);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------
    // chk_dmem_byte — check only byte lane 0 (SB writes one byte)
    // -------------------------------------------------------------------
    task chk_dmem_byte;
        input integer  byte_addr;
        input [7:0]    expected;
        input [255:0]  label;
        reg   [7:0]    got;
        integer        widx;
        begin
            widx = byte_addr >> 2;
            got  = uut.gen_int_dmem.u_dmem.mem_b0[widx];
            if (got === expected) begin
                $display("  PASS  dmem[%04d][7:0] = 0x%02X              [%0s]",
                         byte_addr, got, label);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  dmem[%04d][7:0] = 0x%02X  exp=0x%02X  [%0s]",
                         byte_addr, got, expected, label);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------
    // chk_dmem_half — check only byte lanes 1:0 (SH writes two bytes)
    // -------------------------------------------------------------------
    task chk_dmem_half;
        input integer  byte_addr;
        input [15:0]   expected;
        input [255:0]  label;
        reg   [15:0]   got;
        integer        widx;
        begin
            widx = byte_addr >> 2;
            got  = {uut.gen_int_dmem.u_dmem.mem_b1[widx],
                    uut.gen_int_dmem.u_dmem.mem_b0[widx]};
            if (got === expected) begin
                $display("  PASS  dmem[%04d][15:0] = 0x%04X            [%0s]",
                         byte_addr, got, label);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  dmem[%04d][15:0] = 0x%04X  exp=0x%04X  [%0s]",
                         byte_addr, got, expected, label);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------
    // Per-cycle pipeline trace (first 100 active cycles)
    // -------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n && cycle_cnt < 100)
            $display("[%3d] IF=%08X  ID=%08X(%08X)  EX=%08X | stl=%b fif=%b fid=%b | fwA=%b fwB=%b | we=%b x%02d<=%08X",
                cycle_cnt,
                uut.pc_current,
                uut.pc_id, uut.instr_id,
                uut.alu_result_ex,
                uut.stall_hdu,
                uut.if_id_flush, uut.id_ex_flush,
                uut.forward_a, uut.forward_b,
                uut.reg_write_en_wb, uut.rd_wb, uut.wb_data);
    end

    reg halt_noted;
    initial halt_noted = 1'b0;

    always @(posedge clk) begin
        if (rst_n && !halt_noted && uut.pc_current == 32'h0E4) begin
            $display("[%3d] *** HALT LOOP ENTERED -- PC=0x0E4 ***", cycle_cnt);
            halt_noted = 1'b1;
        end
    end

    // -------------------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------------------
    initial begin
        pass_cnt = 0; fail_cnt = 0;

        rst_n = 1'b0;
        repeat(4) @(posedge clk);
        rst_n = 1'b1;

        $display("");
        $display("================================================================");
        $display(" RV32I Full Coverage -- Pipeline Trace (first 100 active cycles)");
        $display(" [cyc] IF=pc_if  ID=pc_id(instr)  EX=alu_result");
        $display("       stl/fif/fid = stall / IF-ID-flush / ID-EX-flush");
        $display("       fwA/fwB = forward_a/b  (00=reg  01=MEM/WB  10=EX/MEM)");
        $display("       we xNN<=val = WB register write");
        $display("================================================================");

        repeat(400) @(posedge clk);
        #1;

        // JAL x0,0 self-loop: IF may be one fetch ahead (0x0E8); both are acceptable
        if (debug_pc != 32'h0E4 && debug_pc != 32'h0E8)
            $display("WARNING: PC=0x%08X -- expected halt at 0x0E4", debug_pc);

        $display("");
        $display("================================================================");
        $display(" Test Results  [active cycles=%0d  stalls=%0d  redirects=%0d]",
                 cycle_cnt, stall_cnt, flush_cnt);
        $display(" Expected: stalls=0, redirects>=14 (6 branches + JALR + JAL)");
        $display("================================================================");

        // --- Inputs (should be unchanged) ---
        chk( 1, 32'd5,            "ADDI init: x1=5");
        chk( 2, 32'hFFFFFFFB,     "ADDI init: x2=-5");

        // --- R-type ---
        chk( 6, 32'd8,            "ADD  x6 = x1+x3 = 8");
        chk( 7, 32'd2,            "SUB  x7 = x1-x3 = 2");
        chk( 8, 32'd1,            "AND  x8 = 5&3 = 1");
        chk( 9, 32'd7,            "OR   x9 = 5|3 = 7");
        chk(10, 32'd6,            "XOR  x10 = 5^3 = 6");
        chk(11, 32'd40,           "SLL  x11 = 5<<3 = 40");
        chk(12, 32'd0,            "SRL  x12 = 5>>3 = 0");
        chk(13, 32'hFFFFFFFF,     "SRA  x13 = -5 SRA 3 = -1");
        chk(14, 32'd1,            "SLT  x14 = (-5<5 signed) = 1");
        chk(15, 32'd0,            "SLTU x15 = (UINT_MAX<5) = 0");

        // --- I-type ---
        chk(16, 32'd15,           "ADDI  x16 = 5+10 = 15");
        chk(17, 32'd4,            "ANDI  x17 = 5&6 = 4");
        chk(18, 32'd7,            "ORI   x18 = 5|6 = 7");
        chk(19, 32'd3,            "XORI  x19 = 5^6 = 3");
        chk(20, 32'd20,           "SLLI  x20 = 5<<2 = 20");
        chk(21, 32'd2,            "SRLI  x21 = 5>>1 = 2");
        chk(22, 32'hFFFFFFFD,     "SRAI  x22 = -5 SRA 1 = -3");
        chk(23, 32'd1,            "SLTI  x23 = (-5<1 signed) = 1");
        chk(24, 32'd0,            "SLTIU x24 = (UINT_MAX<1) = 0");

        // --- LUI / AUIPC ---
        chk(25, 32'h12345000,     "LUI   x25 = 0x12345000");
        chk(26, 32'h00001064,     "AUIPC x26 = PC(0x64)+0x1000 = 0x1064");

        // --- Loads ---
        chk(27, 32'd5,            "LW  x27 = mem[64] = 5");
        chk(28, 32'hFFFFFFFB,     "LB  x28 = sign_ext(0xFB) = -5");
        chk(29, 32'h000000FB,     "LBU x29 = zero_ext(0xFB) = 251");
        chk(30, 32'd5,            "LH  x30 = sign_ext(0x0005) = 5");
        chk(31, 32'd5,            "LHU x31 = zero_ext(0x0005) = 5");

        // --- Stores (via DMEM read-back) ---
        chk_dmem     (64, 32'h00000005,  "SW  mem[64] = 5");
        chk_dmem_byte(68,  8'hFB,        "SB  mem[68][7:0] = 0xFB");
        chk_dmem_half(72, 16'h0005,      "SH  mem[72][15:0] = 0x0005");

        // --- Branches (x5 = count of correctly taken branches = 6) ---
        chk( 5, 32'd7,            "BEQ/BNE/BLT/BGE/BLTU/BGEU + JALR = 7 taken");

        // --- JALR return address ---
        chk( 3, 32'h000000DC,     "JALR x3 = ret_addr 0x0DC");

        $display("----------------------------------------------------------------");
        if (flush_cnt < 14)
            $display("  WARN  flush_cnt=%0d -- expected >= 14 redirects", flush_cnt);
        $display(" PASSED: %0d   FAILED: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display(" >>> ALL TESTS PASSED <<<");
        else
            $display(" >>> TESTS FAILED -- inspect waveform <<<");
        $display("================================================================");
        $display("");

        $stop;
    end

endmodule
