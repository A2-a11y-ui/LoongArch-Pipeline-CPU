// V0.7 official PC/IF integration harness, not the official CPU top.
// Uses the existing team-A if_id_reg, team-B icache_if_adapter, unchanged
// icache_2way_latency (inside adapter), and imem_latency behind it.
// Uses team-A official pc_if_controller, NOT V0.6 reference driver.
// Synchronous active-high reset across all modules.
module ifetch_subsystem_v07 (
    input  wire        clk,
    input  wire        rst,
    input  wire        redirect,
    input  wire [31:0] redirect_pc,
    input  wire        id_can_advance,
    input  wire        ifid_flush,
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
    wire        if_req_valid, if_req_ready;
    wire [31:0] if_req_addr;
    wire        if_resp_valid, if_resp_ready;
    wire [31:0] if_resp_pc, if_resp_inst;
    wire        if_resp_error;
    wire        mem_req, mem_ready, mem_addr_valid;
    wire [31:0] mem_addr, mem_rdata;

    pc_if_controller u_pc (
        .clk(clk), .rst(rst), .redirect(redirect), .redirect_pc(redirect_pc),
        .if_req_valid(if_req_valid), .if_req_addr(if_req_addr),
        .if_req_ready(if_req_ready)
    );

    icache_if_adapter u_adapter (
        .clk(clk), .rst(rst),
        .if_req_valid(if_req_valid), .if_req_addr(if_req_addr),
        .if_req_ready(if_req_ready),
        .if_resp_valid(if_resp_valid), .if_resp_ready(if_resp_ready),
        .if_resp_pc(if_resp_pc), .if_resp_inst(if_resp_inst),
        .if_resp_error(if_resp_error),
        .redirect(redirect), .busy(adapter_busy),
        .mem_req(mem_req), .mem_addr(mem_addr),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata),
        .mem_addr_valid(mem_addr_valid),
        .cache_hit_count(cache_hits), .cache_miss_count(cache_misses),
        .cache_refill_words(cache_refills)
    );

    imem_latency #(.LATENCY(3)) u_backing (
        .clk(clk), .rst(rst),
        .mem_req(mem_req), .mem_addr(mem_addr),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata),
        .mem_addr_valid(mem_addr_valid), .transactions(backing_transactions)
    );

    // Response may be consumed ONLY if IF/ID can capture or recognize it.
    assign if_resp_ready = !rst && !redirect && !ifid_flush && id_can_advance;
    assign req_fire = if_req_valid && if_req_ready;
    assign resp_fire = if_resp_valid && if_resp_ready;
    assign req_addr_debug = if_req_addr;
    assign resp_pc_debug = if_resp_pc;
    assign fetch_error_fire = resp_fire && if_resp_error;
    assign fetch_error_pc = if_resp_pc;

    // On advance without a valid response: deliberately insert a bubble.
    // On downstream stall: IF/ID retains old contents, adapter retains response.
    // Redirect/flush clears valid even if the ID stage is stalled.
    if_id_reg u_ifid (
        .clk(clk), .rst(rst), .stall(!id_can_advance),
        .flush(redirect || ifid_flush),
        .if_valid(resp_fire && !if_resp_error),
        .if_pc(if_resp_pc), .if_inst(if_resp_inst),
        .id_valid(id_valid), .id_pc(id_pc), .id_inst(id_inst)
    );
endmodule
