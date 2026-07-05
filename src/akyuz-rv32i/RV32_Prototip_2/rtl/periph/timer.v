`timescale 1ns / 1ps

// timer.v
//
// 32-bit Timer/Counter çevre birimi.
// Prescaler, compare match ve overflow interrupt destekli.
//
// Register Map (byte offset):
//   0x0  (R/W) CTRL     [7:0]  - [0]=EN (timer etkin), [1]=AUTO_RELOAD, [2]=IRQ_EN
//   0x4  (R/W) PRESCALE [15:0] - Prescaler değeri (0=bypass, N=N+1 bölme)
//   0x8  (R/W) COUNT    [31:0] - Mevcut sayaç değeri (yazınca sıfırlanır/yüklenir)
//   0xC  (R/W) CMP      [31:0] - Karşılaştırma değeri (compare match interrupt)
//
// Davranış:
//   - COUNT her (PRESCALE+1) clock'ta 1 artar
//   - COUNT == CMP olunca irq üretir
//   - AUTO_RELOAD=1 ise COUNT sıfırlanır, =0 ise devam eder (overflow=wraparound)

module timer #(
    parameter XLEN = 32
)(
    input  wire        clk,
    input  wire        rst_n,

    // Bus Interface
    input  wire [3:0]  addr,
    input  wire [31:0] wdata,
    input  wire        we,
    output reg  [31:0] rdata,

    // Interrupt
    output wire        irq
);

    // ============================================================
    // Register Adresleri
    // ============================================================
    localparam REG_CTRL     = 2'd0;  // 0x0
    localparam REG_PRESCALE = 2'd1;  // 0x4
    localparam REG_COUNT    = 2'd2;  // 0x8
    localparam REG_CMP      = 2'd3;  // 0xC

    wire [1:0] reg_sel = addr[3:2];

    // ============================================================
    // Register'lar
    // ============================================================
    reg         timer_en;
    reg         auto_reload;
    reg         irq_en;
    reg [15:0]  prescale_reg;
    reg [31:0]  count_reg;
    reg [31:0]  cmp_reg;

    // ============================================================
    // Prescaler
    // ============================================================
    reg [15:0]  pre_cnt;
    wire        pre_tick = (pre_cnt == prescale_reg);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pre_cnt <= 16'd0;
        else if (!timer_en)
            pre_cnt <= 16'd0;
        else if (pre_tick)
            pre_cnt <= 16'd0;
        else
            pre_cnt <= pre_cnt + 1'd1;
    end

    // ============================================================
    // Counter
    // ============================================================
    reg  irq_reg;
    wire match = (count_reg == cmp_reg);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count_reg <= 32'd0;
            irq_reg   <= 1'b0;
        end else begin
            irq_reg <= 1'b0;  // pulse

            if (we && reg_sel == REG_COUNT) begin
                count_reg <= wdata;  // CPU tarafından yükleme
            end else if (timer_en && pre_tick) begin
                if (match) begin
                    irq_reg <= irq_en;
                    if (auto_reload)
                        count_reg <= 32'd0;
                    else
                        count_reg <= count_reg + 32'd1;  // overflow devam
                end else begin
                    count_reg <= count_reg + 32'd1;
                end
            end
        end
    end

    assign irq = irq_reg;

    // ============================================================
    // Register Yazma (CTRL, PRESCALE, CMP)
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_en     <= 1'b0;
            auto_reload  <= 1'b0;
            irq_en       <= 1'b0;
            prescale_reg <= 16'd0;
            cmp_reg      <= 32'hFFFF_FFFF;
        end else if (we) begin
            case (reg_sel)
                REG_CTRL: begin
                    timer_en    <= wdata[0];
                    auto_reload <= wdata[1];
                    irq_en      <= wdata[2];
                end
                REG_PRESCALE: prescale_reg <= wdata[15:0];
                REG_CMP:      cmp_reg      <= wdata;
                default: ;
            endcase
        end
    end

    // ============================================================
    // Register Okuma
    // ============================================================
    always @(*) begin
        case (reg_sel)
            REG_CTRL:     rdata = {29'h0, irq_en, auto_reload, timer_en};
            REG_PRESCALE: rdata = {16'h0, prescale_reg};
            REG_COUNT:    rdata = count_reg;
            REG_CMP:      rdata = cmp_reg;
            default:      rdata = 32'h0;
        endcase
    end

endmodule
