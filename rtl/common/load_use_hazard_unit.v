
module load_use_hazard_unit (
    // Instruction currently in IF/ID (ID stage)
    input  wire        id_valid,
    input  wire [4:0]  id_rs1_addr,
    input  wire [4:0]  id_rs2_addr,
    input  wire        id_rs1_used,
    input  wire        id_rs2_used,

    // Older instruction currently in ID/EX (EX stage)
    input  wire        ex_valid,
    input  wire        ex_mem_read,
    input  wire [4:0]  ex_rd_addr,

    // Hazard detection result
    output wire        load_use_hazard,

    // Requests to the future pipeline control unit
    output wire        hold_if_req,
    output wire        hold_ifid_req,
    output wire        bubble_idex_req
);

    wire rs1_dependency;
    wire rs2_dependency;

    // Does the ID instruction need the EX load destination?
    assign rs1_dependency =
        id_rs1_used &&
        (id_rs1_addr == ex_rd_addr);

    assign rs2_dependency =
        id_rs2_used &&
        (id_rs2_addr == ex_rd_addr);

    // Detect a true load-use hazard.
    assign load_use_hazard =
        id_valid &&
        ex_valid &&
        ex_mem_read &&
        (ex_rd_addr != 5'd0) &&
        (rs1_dependency || rs2_dependency);

    // These are requests, NOT direct register controls.
    assign hold_if_req    = load_use_hazard;
    assign hold_ifid_req  = load_use_hazard;
    assign bubble_idex_req = load_use_hazard;

endmodule
