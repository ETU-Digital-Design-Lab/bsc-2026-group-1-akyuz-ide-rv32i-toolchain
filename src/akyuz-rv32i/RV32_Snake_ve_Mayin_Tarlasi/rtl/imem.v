// imem.v — Instruction Memory (BRAM, word-addressed)
//
// Okuma portlari saatin DUSEN kenarinda (negedge) register'lanir. Boylece
// Vivado bunu Block RAM olarak cikarir (LUTRAM yerine), ama veri yine ayni
// cevrim icinde (CPU'nun posedge pipeline register'lari ornekleme yapmadan
// once) hazir olur -> eski asenkron okuma davranisiyla birebir ayni.
//
// Port A : CPU komut fetch (salt okuma)
// Port B : Bootloader yazma  VEYA  veri okuma (.rodata/.data goruntusu)

module imem #(
    parameter XLEN     = 32,
    parameter DEPTH    = 2048,      // words
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

    // Port B: Data read (CPU load from IMEM region, e.g. .rodata)
    input  wire [XLEN-1:0] daddr,
    output wire [31:0]     ddata
);

    localparam ADDR_W = $clog2(DEPTH);

    (* ram_style = "block" *) reg [31:0] mem [0:DEPTH-1];

    initial begin
        if (MEM_FILE != "")
            $readmemh(MEM_FILE, mem);
    end

    reg [31:0] data_r;
    reg [31:0] ddata_r;

    // Port A: fetch read (negedge -> BRAM, same-cycle ready)
    always @(negedge clk) begin
        data_r <= mem[addr[ADDR_W+1:2]];
    end

    // Port B: bootloader write OR data-side read (mutually exclusive)
    always @(negedge clk) begin
        if (we) mem[waddr[ADDR_W+1:2]] <= wdata;
        else    ddata_r <= mem[daddr[ADDR_W+1:2]];
    end

    assign data  = data_r;
    assign ddata = ddata_r;

endmodule
