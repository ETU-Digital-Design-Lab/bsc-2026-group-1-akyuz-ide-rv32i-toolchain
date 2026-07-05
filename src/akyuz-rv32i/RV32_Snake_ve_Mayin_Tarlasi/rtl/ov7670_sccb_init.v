module ov7670_sccb_init (
    input  wire clk,
    input  wire rst_n,
    output reg  sioc,
    inout  wire siod,
    output reg  done,
    output reg  ack_error,
    output wire cam_reset_n,
    output wire cam_pwdn
);
    // SCCB clock yavaslatildi (~100 kHz @100 MHz) -> zayif pull-up'ta ACK daha
    // guvenilir okunur. tick periyodu = CLK_DIV cycle.
    localparam CLK_DIV  = 500;
    localparam ROM_SIZE = 39;
    localparam WAIT_TICKS = 16'd400;  // ~2 ms (guc-acilis ve reset sonrasi bekleme)

    // Bilinen-iyi OV7670 VGA RGB565 konfigurasyonu (OmniVision app-note /
    // Linux ov7670.c kokenli). Her register TEK kez yazilir; saat ayarlarini
    // degistiren registerlara (CLKRC harici, DBLV/PLL) dokunulmaz.
    reg [15:0] cfg_rom [0:ROM_SIZE-1];
    initial begin
        cfg_rom[0]  = 16'h1280; // COM7: soft reset (ardindan ~2 ms beklenir)
        cfg_rom[1]  = 16'h1204; // COM7: RGB output mode
        cfg_rom[2]  = 16'h1140; // CLKRC: harici saat dogrudan (prescale yok)
        cfg_rom[3]  = 16'h0C00; // COM3: olcekleme yok
        cfg_rom[4]  = 16'h3E00; // COM14: downsample yok
        cfg_rom[5]  = 16'h8C00; // RGB444 kapali
        cfg_rom[6]  = 16'h0400; // COM1: satir atlama yok
        cfg_rom[7]  = 16'h40D0; // COM15: RGB565, tam aralik (tek yazim — tekrar EZILMEZ)
        cfg_rom[8]  = 16'h3A04; // TSLB: cikis sirasi
        cfg_rom[9]  = 16'h1418; // COM9: AGC tavani 4x
        cfg_rom[10] = 16'h4FB3; // MTX1 (RGB565 renk matrisi)
        cfg_rom[11] = 16'h50B3; // MTX2
        cfg_rom[12] = 16'h5100; // MTX3
        cfg_rom[13] = 16'h523D; // MTX4
        cfg_rom[14] = 16'h53A7; // MTX5
        cfg_rom[15] = 16'h54E4; // MTX6
        cfg_rom[16] = 16'h589E; // MTXS
        cfg_rom[17] = 16'h3DC0; // COM13: gamma + UV doygunluk
        // VGA (640x480) yakalama penceresi — datasheet/Linux suruculerindeki set
        cfg_rom[18] = 16'h1713; // HSTART
        cfg_rom[19] = 16'h1801; // HSTOP
        cfg_rom[20] = 16'h32B6; // HREF  (kenar ince ayari)
        cfg_rom[21] = 16'h1902; // VSTRT
        cfg_rom[22] = 16'h1A7A; // VSTOP
        cfg_rom[23] = 16'h030A; // VREF  (kenar ince ayari)
        // Goruntu kalitesi icin app-note "magic" degerleri (saatten bagimsiz)
        cfg_rom[24] = 16'h0E61; // COM5
        cfg_rom[25] = 16'h0F4B; // COM6
        cfg_rom[26] = 16'h1602; // (reserved)
        cfg_rom[27] = 16'h1E07; // MVFP
        cfg_rom[28] = 16'h330B; // CHLF
        cfg_rom[29] = 16'h3C78; // COM12: HREF her zaman
        cfg_rom[30] = 16'h6900; // GFIX
        cfg_rom[31] = 16'h7410; // REG74
        cfg_rom[32] = 16'hB084; // ABLC (renk dogrulugu icin gerekli)
        cfg_rom[33] = 16'hB10C; // ABLC ctrl
        cfg_rom[34] = 16'hB20E; // (reserved)
        cfg_rom[35] = 16'hB380; // THL_ST
        // Test deseni KAPALI: 0x70/0x71 bit7=0 -> gercek kamera goruntusu
        cfg_rom[36] = 16'h703A; // SCALING_XSC (test pattern off)
        cfg_rom[37] = 16'h7135; // SCALING_YSC (test pattern off)
        cfg_rom[38] = 16'h0000; // END marker
    end

    assign cam_reset_n = 1'b1;
    assign cam_pwdn    = 1'b0;

    reg siod_oe;
    reg siod_out;
    assign siod = siod_oe ? siod_out : 1'bz;
    wire siod_in = siod;

    reg [15:0] div_cnt;
    reg tick;
    always @(posedge clk) begin
        if (!rst_n) begin
            div_cnt <= 16'd0;
            tick    <= 1'b0;
        end else if (div_cnt == CLK_DIV-1) begin
            div_cnt <= 16'd0;
            tick    <= 1'b1;
        end else begin
            div_cnt <= div_cnt + 16'd1;
            tick    <= 1'b0;
        end
    end

    reg [7:0] rom_idx;
    reg [5:0] bit_idx;
    reg [3:0] state;
    reg [23:0] shift;
    reg [1:0] phase;
    reg [15:0] wait_cnt;

    localparam ST_IDLE    = 4'd0;
    localparam ST_START   = 4'd1;
    localparam ST_SEND    = 4'd2;
    localparam ST_ACK     = 4'd3;
    localparam ST_STOP    = 4'd4;
    localparam ST_NEXT    = 4'd5;
    localparam ST_DONE    = 4'd6;
    localparam ST_PWRUP   = 4'd7;  // guc-acilis bekleme (SCCB oncesi)
    localparam ST_RSTWAIT = 4'd8;  // COM7 soft-reset sonrasi bekleme

    always @(posedge clk) begin
        if (!rst_n) begin
            sioc     <= 1'b1;
            siod_oe  <= 1'b1;
            siod_out <= 1'b1;
            done     <= 1'b0;
            ack_error<= 1'b0;
            rom_idx  <= 8'd0;
            bit_idx  <= 6'd0;
            state    <= ST_PWRUP;
            phase    <= 2'd0;
            shift    <= 24'd0;
            wait_cnt <= 16'd0;
        end else if (tick) begin
            case (state)
                ST_PWRUP: begin
                    // Kamera guc-acilis/reset sonrasi oturma suresi
                    if (wait_cnt >= WAIT_TICKS) begin
                        wait_cnt <= 16'd0;
                        state    <= ST_IDLE;
                    end else begin
                        wait_cnt <= wait_cnt + 16'd1;
                    end
                end
                ST_RSTWAIT: begin
                    // COM7=0x80 yazildiktan sonra >1 ms bekle
                    if (wait_cnt >= WAIT_TICKS) begin
                        wait_cnt <= 16'd0;
                        state    <= ST_IDLE;
                    end else begin
                        wait_cnt <= wait_cnt + 16'd1;
                    end
                end
                ST_IDLE: begin
                    done     <= 1'b0;
                    sioc     <= 1'b1;
                    siod_oe  <= 1'b1;
                    siod_out <= 1'b1;
                    shift    <= {8'h42, cfg_rom[rom_idx]};
                    bit_idx  <= 6'd23;
                    phase    <= 2'd0;
                    state    <= ST_START;
                end
                ST_START: begin
                    siod_oe  <= 1'b1;
                    siod_out <= 1'b0;
                    sioc     <= 1'b1;
                    state    <= ST_SEND;
                end
                ST_SEND: begin
                    if (phase == 2'd0) begin
                        sioc     <= 1'b0;
                        siod_oe  <= 1'b1;
                        siod_out <= shift[bit_idx];
                        phase    <= 2'd1;
                    end else begin
                        sioc  <= 1'b1;
                        phase <= 2'd0;
                        // After last bit of each byte (bit_idx divisible by 8: 16,8,0)
                        // insert a don't-care/ACK clock (9th bit per byte)
                        if (bit_idx[2:0] == 3'd0) begin
                            state <= ST_ACK;
                        end else begin
                            bit_idx <= bit_idx - 6'd1;
                        end
                    end
                end
                ST_ACK: begin
                    // 9. bit: hatti BIRAK (tristate) -> kamera ACK icin LOW
                    // cekebilsin. Onceden master HIGH suruyordu; kamera ayni
                    // anda LOW cekince bus cakismasi oluyordu. Pull-up XDC'de
                    // (PULLUP TRUE) tanimli. ACK ayrica ornekleniyor: herhangi
                    // bir bayt ACK'lenmezse ack_error kalici olarak set edilir.
                    if (phase == 2'd0) begin
                        sioc    <= 1'b0;
                        siod_oe <= 1'b0;       // hatti birak
                        phase   <= 2'd1;
                    end else if (phase == 2'd1) begin
                        sioc  <= 1'b1;
                        phase <= 2'd2;
                    end else begin
                        if (siod_in) ack_error <= 1'b1;  // ACK gelmedi
                        phase <= 2'd0;
                        if (bit_idx == 0) begin
                            state <= ST_STOP;   // all 3 bytes sent
                        end else begin
                            bit_idx <= bit_idx - 6'd1;
                            state   <= ST_SEND; // continue with next byte
                        end
                    end
                end
                ST_STOP: begin
                    sioc     <= 1'b1;
                    siod_oe  <= 1'b1;
                    siod_out <= 1'b1;
                    state    <= ST_NEXT;
                end
                ST_NEXT: begin
                    if (rom_idx == ROM_SIZE-1) begin
                        // done, ack_error'dan BAGIMSIZ: ACK gelmese bile dizi
                        // tamamlandi -> goruntu akisi engellenmez, led[1] taniyi verir.
                        done  <= 1'b1;
                        state <= ST_DONE;
                    end else if (rom_idx == 8'd0) begin
                        // Ilk komut COM7 soft-reset idi -> oturmasi icin bekle
                        rom_idx  <= 8'd1;
                        wait_cnt <= 16'd0;
                        state    <= ST_RSTWAIT;
                    end else begin
                        rom_idx <= rom_idx + 8'd1;
                        state   <= ST_IDLE;
                    end
                end
                ST_DONE: begin
                    done <= 1'b1;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
