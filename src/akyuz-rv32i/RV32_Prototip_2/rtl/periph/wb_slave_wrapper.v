`timescale 1ns / 1ps

// wb_slave_wrapper.v
//
// Basit periferal modulleri (uart, gpio, timer, spi) icin
// Wishbone B4 slave arayuzu saglayan generic wrapper.
//
// Mevcut periferaller senkron ve tek-cycle yanitli oldugu icin
// STB geldiginde hemen ACK uretir.
// Ileride yavas periferaller icin wait-state eklenebilir.
//
// Kullanim:
//   wb_slave_wrapper u_uart_wb (
//       .clk(clk), .rst_n(rst_n),
//       .wb_adr_i(uart_adr), .wb_dat_i(uart_dat_w),
//       .wb_we_i(uart_we), .wb_stb_i(uart_stb),
//       .wb_dat_o(uart_dat_r), .wb_ack_o(uart_ack),
//       .periph_addr(uart_addr), .periph_wdata(uart_wdata),
//       .periph_we(uart_we_int), .periph_rdata(uart_rdata)
//   );

module wb_slave_wrapper #(
    parameter ADDR_WIDTH = 4   // Periferal ic adres genisligi (varsayilan 4-bit = 16 byte)
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // Wishbone Slave Arayuzu
    input  wire [ADDR_WIDTH-1:0]   wb_adr_i,     // Adres (periferal ofseti)
    input  wire [31:0]             wb_dat_i,     // Yazma verisi
    input  wire                    wb_we_i,      // Write Enable
    input  wire                    wb_stb_i,     // Strobe
    output wire [31:0]             wb_dat_o,     // Okuma verisi
    output wire                    wb_ack_o,     // Acknowledge

    // Periferal Arayuzu (mevcut modullerin basit arayuzu)
    output wire [ADDR_WIDTH-1:0]   periph_addr,
    output wire [31:0]             periph_wdata,
    output wire                    periph_we,
    input  wire [31:0]             periph_rdata
);

    // Basit periferaller senkron ve tek-cycle:
    // STB geldigi cycle'da islem yapilir, ACK ayni cycle'da doner
    assign periph_addr  = wb_adr_i;
    assign periph_wdata = wb_dat_i;
    assign periph_we    = wb_we_i & wb_stb_i;

    // Okuma verisi dogrudan periferal cikisini yansitir
    assign wb_dat_o = periph_rdata;

    // Tek-cycle ACK: STB aktifse hemen ACK ver
    assign wb_ack_o = wb_stb_i;

endmodule
