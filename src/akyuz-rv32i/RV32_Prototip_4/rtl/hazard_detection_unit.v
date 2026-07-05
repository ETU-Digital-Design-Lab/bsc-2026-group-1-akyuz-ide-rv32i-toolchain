// hazard_detection_unit.v — Load-Use Hazard Detection
//
// When a load in EX is followed immediately by an instruction in ID that
// consumes the load's destination, a one-cycle stall is inserted:
//   - PC and IF/ID register are held (write_en = 0)
//   - ID/EX register is flushed (bubble injected)
//
// uses_rs1 / uses_rs2 prevent false stalls for instructions that do not
// read rs1 or rs2 (e.g. LUI, JAL).

module hazard_detection_unit (
    input  wire [4:0]  if_id_rs1,
    input  wire [4:0]  if_id_rs2,
    input  wire        if_id_uses_rs1,
    input  wire        if_id_uses_rs2,

    input  wire [4:0]  id_ex_rd,
    input  wire        id_ex_mem_read,

    output reg         stall,
    output reg         pc_write_en,
    output reg         if_id_write_en,
    output reg         id_ex_flush
);

    always @(*) begin
        if (id_ex_mem_read && id_ex_rd != 5'b0 &&
            ((if_id_uses_rs1 && id_ex_rd == if_id_rs1) ||
             (if_id_uses_rs2 && id_ex_rd == if_id_rs2)))
        begin
            stall          = 1'b1;
            pc_write_en    = 1'b0;
            if_id_write_en = 1'b0;
            id_ex_flush    = 1'b1;
        end else begin
            stall          = 1'b0;
            pc_write_en    = 1'b1;
            if_id_write_en = 1'b1;
            id_ex_flush    = 1'b0;
        end
    end

endmodule
