`timescale 1ns/1ps

module riscv_alu_tb;
    reg [31:0] a;
    reg [31:0] b;
    reg [2:0]  op;
    wire [31:0] y;
    integer errors;

    riscv_alu dut (
        .a(a),
        .b(b),
        .op(op),
        .y(y)
    );

    task check;
        input [31:0] exp;
        input [255:0] name;
        begin
            #1;
            if (y !== exp) begin
                $display("FAIL %0s exp=%h got=%h", name, exp, y);
                errors = errors + 1;
            end else begin
                $display("PASS %0s y=%h", name, y);
            end
        end
    endtask

    initial begin
        errors = 0;
        a = 32'd10; b = 32'd7; op = 3'b000; check(32'd17, "ADD");
        a = 32'd10; b = 32'd7; op = 3'b001; check(32'd3, "SUB");
        a = 32'h0F0F; b = 32'h00FF; op = 3'b010; check(32'h000F, "AND");
        a = 32'h0F00; b = 32'h00F0; op = 3'b011; check(32'h0FF0, "OR");
        a = -32'sd3; b = 32'sd2; op = 3'b100; check(32'd1, "SLT signed");

        if (errors == 0) begin
            $display("SIM_PASS");
        end else begin
            $display("SIM_FAIL errors=%0d", errors);
        end
        $finish;
    end
endmodule
