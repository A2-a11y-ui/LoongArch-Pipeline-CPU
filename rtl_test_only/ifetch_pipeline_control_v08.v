// V0.8 TEST-ONLY wrapper: team-A pipeline control + stable V0.7 IF subsystem.
// Not a CPU top. Does not modify or replace any official RTL.
// Compatible with Verilog-2001 and Vivado 2019.1.
//
// IMPORTANT PROTOCOL BOUNDARY:
// hold_fetch_issue_req is ADVISORY in this phase. It is NOT wired to
// pc_if_controller.if_req_valid or icache_if_adapter.if_req_valid.
// A previously asserted IF valid must remain stable until accepted, except
// when reset/redirect explicitly invalidates the old path.
//
// id_can_advance_external: test-only downstream accept capacity (1=advance).
// ifid_flush_external: test-only local IF/ID flush independent of redirect.
// In a full CPU these should be replaced by actual pipeline ready/flush logic.
module ifetch_pipeline_control_v08 (
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
    output wire [31:0] backing_transactions
);
    pipeline_control_unit u_pipeline_ctrl (
        .rst(rst),
        .branch_redirect(branch_redirect),
        .load_use_hazard(load_use_hazard),
        .ifid_stall(ifid_stall),
        .ifid_flush(ifid_flush_ctrl),
        .idex_flush(idex_flush),
        .hold_fetch_issue_req(hold_fetch_issue_req)
    );

    // Only IF/ID's advancement is gated by load-use at this stage.
    // The local flush remains independent (as proven in V0.7).
    assign id_can_advance_effective = id_can_advance_external && !ifid_stall;
    assign ifid_flush_effective = ifid_flush_external || ifid_flush_ctrl;

    ifetch_subsystem_v07 u_ifetch (
        .clk(clk),
        .rst(rst),
        .redirect(branch_redirect),
        .redirect_pc(redirect_pc),
        .id_can_advance(id_can_advance_effective),
        .ifid_flush(ifid_flush_effective),
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
endmodule
