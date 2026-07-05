// dmem.v — Data Memory (byte-addressable, synchronous write, async read)
//
// Organised as four independent 8-bit LUTRAM banks with byte-level write
// enables.  This is the pattern Vivado (and other Xilinx tools) correctly
// infer as distributed RAM (LUTRAM) — avoiding the "Infeasible ram_style=block"
// warning that arises when a single 32-bit array is written with arbitrary
// bit-level masking.
//
// Async read is required because the pipeline expects the result the same
// cycle as the address is presented (no extra pipeline stage added).
//
// funct3 encoding (RV32I stores):
//   3'b000 — SB   (1 byte,  any alignment)
//   3'b001 — SH   (2 bytes, halfword-aligned)
//   3'b010 — SW   (4 bytes, word-aligned)

module dmem #(
    parameter XLEN     = 32,
    parameter DEPTH    = 1024,      // words (4 KiB default)
    parameter MEM_FILE = ""         // unused (DMEM always initialises to 0)
)(
    input  wire              clk,
    input  wire              we,        // write enable (gated by address decoder)
    input  wire [2:0]        funct3,
    input  wire [XLEN-1:0]   addr,
    input  wire [XLEN-1:0]   wdata,
    output wire [XLEN-1:0]   rdata
);

    // Four byte-lane LUTRAMs — each 8 bits wide × DEPTH words.
    // Separate arrays with individual enables are the canonical Xilinx
    // LUTRAM template; they synthesise without warnings.
    (* ram_style = "distributed" *) reg [7:0] mem_b0 [0:DEPTH-1];
    (* ram_style = "distributed" *) reg [7:0] mem_b1 [0:DEPTH-1];
    (* ram_style = "distributed" *) reg [7:0] mem_b2 [0:DEPTH-1];
    (* ram_style = "distributed" *) reg [7:0] mem_b3 [0:DEPTH-1];

    wire [XLEN-3:0] word_addr = addr[XLEN-1:2];
    wire [1:0]      byte_off  = addr[1:0];

    // =========================================================================
    // Byte-write enable decode
    // =========================================================================
    reg [3:0] byte_we;
    always @(*) begin
        byte_we = 4'b0000;
        if (we) begin
            case (funct3[1:0])
                2'b00: // SB — one byte at byte_off
                    case (byte_off)
                        2'b00: byte_we = 4'b0001;
                        2'b01: byte_we = 4'b0010;
                        2'b10: byte_we = 4'b0100;
                        2'b11: byte_we = 4'b1000;
                    endcase
                2'b01: // SH — two bytes (halfword-aligned)
                    byte_we = byte_off[1] ? 4'b1100 : 4'b0011;
                2'b10: // SW — full word
                    byte_we = 4'b1111;
                default: byte_we = 4'b0000;
            endcase
        end
    end

    // =========================================================================
    // Write-data per byte lane
    //
    // SB: replicate wdata[7:0] to every lane (byte_we selects which writes)
    // SH: lower half → lanes {1,0} = wdata[15:0];
    //     upper half → lanes {3,2} = wdata[15:0] (same source, different we)
    // SW: natural byte assignment
    // =========================================================================
    wire [7:0] wd_0 = wdata[7:0];
    wire [7:0] wd_1 = (funct3[1:0] == 2'b00) ? wdata[7:0]  : wdata[15:8];
    wire [7:0] wd_2 = (funct3[1:0] == 2'b10) ? wdata[23:16] : wdata[7:0];
    wire [7:0] wd_3 = (funct3[1:0] == 2'b00) ? wdata[7:0]  :
                      (funct3[1:0] == 2'b01) ? wdata[15:8]  : wdata[31:24];

    // =========================================================================
    // Synchronous writes — one always block per lane (Vivado LUTRAM template)
    // =========================================================================
    always @(posedge clk) if (byte_we[0]) mem_b0[word_addr] <= wd_0;
    always @(posedge clk) if (byte_we[1]) mem_b1[word_addr] <= wd_1;
    always @(posedge clk) if (byte_we[2]) mem_b2[word_addr] <= wd_2;
    always @(posedge clk) if (byte_we[3]) mem_b3[word_addr] <= wd_3;

    // =========================================================================
    // Combinational read (WB stage handles sign/zero extension for LB/LH)
    // =========================================================================
    assign rdata = {mem_b3[word_addr], mem_b2[word_addr],
                    mem_b1[word_addr], mem_b0[word_addr]};

endmodule
