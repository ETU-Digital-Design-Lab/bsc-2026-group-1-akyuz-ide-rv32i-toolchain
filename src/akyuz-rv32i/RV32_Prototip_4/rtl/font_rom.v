// font_rom.v — 8×16 bitmap font ROM, 128 characters
//
// Layout: addr[10:4] = char index (0..127)
//         addr[3:0]  = row within character (0=top, 15=bottom)
// Total: 128 × 16 = 2048 entries × 8 bits
//
// Vivado infers this as distributed RAM (LUTRAM, ~16 Kbits).
// Asynchronous read: no pipeline stage required.

module font_rom #(
    parameter FONT_FILE = "font8x16.hex"
) (
    input  wire [10:0] addr,
    output wire  [7:0] data
);
    (* rom_style = "distributed" *)
    reg [7:0] rom [0:2047];

    initial
        if (FONT_FILE != "") $readmemh(FONT_FILE, rom);

    assign data = rom[addr];

endmodule
