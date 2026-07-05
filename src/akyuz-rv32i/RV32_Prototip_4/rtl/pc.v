// pc.v — Program Counter
//
// Holds the current instruction address. Updates to `next` on each rising
// edge when `write_en` is asserted; holds otherwise (load-use stall).

module pc #(
    parameter XLEN = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              write_en,
    input  wire [XLEN-1:0]   next,
    output reg  [XLEN-1:0]   current
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)        current <= {XLEN{1'b0}};
        else if (write_en) current <= next;
    end

endmodule
