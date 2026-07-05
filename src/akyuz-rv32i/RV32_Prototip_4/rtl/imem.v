// imem.v — Instruction Memory (read/write, word-addressed)
//
// Port A: Asynchronous read for CPU instruction fetch
// Port B: Synchronous write for Hardware Bootloader

module imem #(
    parameter XLEN     = 32,
    parameter DEPTH    = 2048,      // words (8 KiB default)
    parameter MEM_FILE = ""
)(
    input  wire            clk,

    // Port A: Read (CPU fetch)
    input  wire [XLEN-1:0] addr,
    output wire [31:0]     data,

    // Port B: Write (Bootloader)
    input  wire            we,
    input  wire [XLEN-1:0] waddr,
    input  wire [31:0]     wdata,

    // Port C: Data read (CPU load from IMEM region, e.g. .rodata)
    input  wire [XLEN-1:0] daddr,
    output wire [31:0]     ddata
);

    localparam ADDR_W = $clog2(DEPTH);

    reg [31:0] mem [0:DEPTH-1];

    initial begin
        if (MEM_FILE != "")
            $readmemh(MEM_FILE, mem);
    end

    // Asynchronous read for CPU fetch
    assign data  = mem[addr[ADDR_W+1:2]];

    // Asynchronous data read (for .rodata / load instructions targeting IMEM)
    assign ddata = mem[daddr[ADDR_W+1:2]];
    
    // Synchronous write for Bootloader
    always @(posedge clk) begin
        if (we) begin
            mem[waddr[ADDR_W+1:2]] <= wdata;
        end
    end

endmodule
