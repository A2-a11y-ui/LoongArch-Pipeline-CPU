// V0.9 TEST-ONLY integration: V0.8 fetch/control + official ID/EX register.
// Verilog-2001, Vivado 2019.1. Not a CPU top or instruction decoder.
// No stable RTL is modified. The V0.8 hold_fetch_issue_req remains advisory.
module ifetch_idex_integration_v09 (
    input  wire        clk,
    input  wire        rst,
    input  wire        branch_redirect,
    input  wire [31:0] redirect_pc,
    input  wire        load_use_hazard,
    input  wire        id_can_advance_external,
    input  wire        ifid_flush_external,

    output wire        ifid_stall,
    output wire        ifid_flush_ctrl,
    output wire        idex_flush,
    output wire        hold_fetch_issue_req,
    output wire        id_can_advance_effective,
    output wire        ifid_flush_effective,

    output wire        id_valid,
    output wire [31:0] id_pc,
    output wire [31:0] id_inst,
    output wire        fetch_error_fire,
    output wire [31:0] fetch_error_pc,
    output wire        req_fire,
    output wire        resp_fire,
    output wire [31:0] req_addr_debug,
    output wire [31:0] resp_pc_debug,
    output wire        adapter_busy,
    output wire [31:0] cache_hits,
    output wire [31:0] cache_misses,
    output wire [31:0] cache_refills,
    output wire [31:0] backing_transactions,

    output wire        idex_stall_effective,
    output wire        ex_valid,
    output wire [31:0] ex_pc,
    output wire [31:0] ex_pc_plus4,
    output wire [31:0] ex_inst,
    output wire [4:0] ex_rs1_addr,
    output wire [4:0] ex_rs2_addr,
    output wire [4:0] ex_rd_addr,
    output wire [31:0] ex_rs1_data,
    output wire [31:0] ex_rs2_data,
    output wire        ex_rs1_used,
    output wire        ex_rs2_used,
    output wire [31:0] ex_imm,
    output wire [3:0] ex_alu_op,
    output wire        ex_alu_src_imm,
    output wire [2:0] ex_branch_type,
    output wire [1:0] ex_wb_sel,
    output wire        ex_reg_write,
    output wire        ex_mem_read,
    output wire        ex_mem_write
);

    ifetch_pipeline_control_v08 u_v08 (
        .clk(clk),
        .rst(rst),
        .branch_redirect(branch_redirect),
        .redirect_pc(redirect_pc),
        .load_use_hazard(load_use_hazard),
        .id_can_advance_external(id_can_advance_external),
        .ifid_flush_external(ifid_flush_external),
        .ifid_stall(ifid_stall),
        .ifid_flush_ctrl(ifid_flush_ctrl),
        .idex_flush(idex_flush),
        .hold_fetch_issue_req(hold_fetch_issue_req),
        .id_can_advance_effective(id_can_advance_effective),
        .ifid_flush_effective(ifid_flush_effective),
        .id_valid(id_valid),
        .id_pc(id_pc),
        .id_inst(id_inst),
        .fetch_error_fire(fetch_error_fire),
        .fetch_error_pc(fetch_error_pc),
        .req_fire(req_fire),
        .resp_fire(resp_fire),
        .req_addr_debug(req_addr_debug),
        .resp_pc_debug(resp_pc_debug),
        .adapter_busy(adapter_busy),
        .cache_hits(cache_hits),
        .cache_misses(cache_misses),
        .cache_refills(cache_refills),
        .backing_transactions(backing_transactions)
    );

    // TEST-ONLY deterministic decode surrogate. These are NOT LoongArch
    // instructions and do not claim correctness of the real decoder.
    // Stable combinational ID fields make every ID/EX field observable.
    wire [4:0]  mock_rs1_addr = id_inst[9:5];
    wire [4:0]  mock_rs2_addr = id_inst[14:10];
    wire [4:0]  mock_rd_addr  = id_inst[4:0];
    wire [31:0] mock_rs1_data = id_inst ^ 32'h13579BDF;
    wire [31:0] mock_rs2_data = id_inst ^ 32'h2468ACE0;
    wire        mock_rs1_used = id_inst[15];
    wire        mock_rs2_used = id_inst[16];
    wire [31:0] mock_imm      = {16'b0, id_inst[15:0]};
    wire [3:0]  mock_alu_op   = id_inst[19:16];
    wire        mock_alu_src_imm = id_inst[20];
    wire [2:0]  mock_branch_type = id_inst[23:21];
    wire [1:0]  mock_wb_sel   = id_inst[25:24];
    wire        mock_reg_write = id_inst[26];
    wire        mock_mem_read  = id_inst[27];
    wire        mock_mem_write = id_inst[28];

    // External downstream backpressure holds both IF/ID and ID/EX.
    // Load-use uses FLUSH (bubble), not STALL, on ID/EX; flushing wins.
    // The actual EX/MEM pipeline register is not yet connected here.
    assign idex_stall_effective = !id_can_advance_external;

    id_ex_reg u_idex (
        .clk(clk),
        .rst(rst),
        .stall(idex_stall_effective),
        .flush(idex_flush),
        .id_valid(id_valid),
        .id_pc(id_pc),
        .id_pc_plus4(id_pc + 32'd4),
        .id_inst(id_inst),
        .id_rs1_addr(mock_rs1_addr),
        .id_rs2_addr(mock_rs2_addr),
        .id_rd_addr(mock_rd_addr),
        .id_rs1_data(mock_rs1_data),
        .id_rs2_data(mock_rs2_data),
        .id_rs1_used(mock_rs1_used),
        .id_rs2_used(mock_rs2_used),
        .id_imm(mock_imm),
        .id_alu_op(mock_alu_op),
        .id_alu_src_imm(mock_alu_src_imm),
        .id_branch_type(mock_branch_type),
        .id_wb_sel(mock_wb_sel),
        .id_reg_write(mock_reg_write),
        .id_mem_read(mock_mem_read),
        .id_mem_write(mock_mem_write),
        .ex_valid(ex_valid),
        .ex_pc(ex_pc),
        .ex_pc_plus4(ex_pc_plus4),
        .ex_inst(ex_inst),
        .ex_rs1_addr(ex_rs1_addr),
        .ex_rs2_addr(ex_rs2_addr),
        .ex_rd_addr(ex_rd_addr),
        .ex_rs1_data(ex_rs1_data),
        .ex_rs2_data(ex_rs2_data),
        .ex_rs1_used(ex_rs1_used),
        .ex_rs2_used(ex_rs2_used),
        .ex_imm(ex_imm),
        .ex_alu_op(ex_alu_op),
        .ex_alu_src_imm(ex_alu_src_imm),
        .ex_branch_type(ex_branch_type),
        .ex_wb_sel(ex_wb_sel),
        .ex_reg_write(ex_reg_write),
        .ex_mem_read(ex_mem_read),
        .ex_mem_write(ex_mem_write)
    );
endmodule
