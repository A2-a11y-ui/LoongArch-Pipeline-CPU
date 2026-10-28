// I-Cache V0.5: IF-side request/response adapter for legacy V0.3 2-way LRU.
// Verilog-2001; tested via intended Vivado 2019.1 behavioral testbench.
//
// IF request: accept at a rising edge iff if_req_valid && if_req_ready.
// IF response: consume at a rising edge iff if_resp_valid && if_resp_ready.
// Redirect (synchronous pulse) has priority over request, response and stall.
// After redirect, the IF controller MUST present a new request at target PC;
// this adapter DOES NOT autonomously fetch redirect_pc.
//
// Internally the legacy cache requires valid+address held until `ready=1`.
// A miss cannot be physically cancelled. On redirect, drain the old request,
// discard any stale response, then reopen request acceptance. One outstanding.
// Does NOT drive IF/ID.stall directly: IF/ID write/hold belongs to IF controller.
module icache_if_adapter (
    input  wire        clk,
    input  wire        rst,

    input  wire        if_req_valid,
    input  wire [31:0] if_req_addr,
    output wire        if_req_ready,

    output wire        if_resp_valid,
    input  wire        if_resp_ready,
    output wire [31:0] if_resp_pc,
    output wire [31:0] if_resp_inst,
    output wire        if_resp_error,

    input  wire        redirect,
    output wire        busy,

    output wire        mem_req,
    output wire [31:0] mem_addr,
    input  wire        mem_ready,
    input  wire [31:0] mem_rdata,
    input  wire        mem_addr_valid,

    output wire [31:0] cache_hit_count,
    output wire [31:0] cache_miss_count,
    output wire [31:0] cache_refill_words
);
    localparam [1:0] ST_IDLE=2'd0, ST_WAIT=2'd1,
                     ST_RESP=2'd2, ST_DRAIN=2'd3;

    reg [1:0] state;
    reg [31:0] pending_pc;
    reg [31:0] result_pc;
    reg [31:0] result_inst;
    reg        result_error;

    wire [31:0] cache_inst;
    wire cache_ready;
    wire cache_fetch_valid;
    wire cache_stall;
    wire cache_hit;
    wire cache_req_valid = (state == ST_WAIT) || (state == ST_DRAIN);

    assign if_req_ready  = (state == ST_IDLE) && !redirect && !rst;
    assign if_resp_valid = (state == ST_RESP) && !redirect && !rst;
    assign if_resp_pc    = result_pc;
    assign if_resp_inst  = result_inst;
    assign if_resp_error = result_error;
    assign busy = (state != ST_IDLE);

    icache_2way_latency u_icache (
        .clk(clk), .rst(rst),
        .req_valid(cache_req_valid), .req_addr(pending_pc),
        .inst(cache_inst), .ready(cache_ready),
        .fetch_valid(cache_fetch_valid),
        .stall(cache_stall), .hit(cache_hit),
        .mem_addr(mem_addr), .mem_req(mem_req),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata),
        .mem_addr_valid(mem_addr_valid),
        .hit_count(cache_hit_count),
        .miss_count(cache_miss_count),
        .refill_words(cache_refill_words)
    );

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            pending_pc <= 32'b0;
            result_pc <= 32'b0;
            result_inst <= 32'b0;
            result_error <= 1'b0;
        end else if (redirect) begin
            // Redirect is a synchronous event. Do not accept a simultaneous
            // old-path response or IF request. Legacy miss must be drained.
            case (state)
                ST_WAIT: state <= cache_ready ? ST_IDLE : ST_DRAIN;
                ST_DRAIN: state <= cache_ready ? ST_IDLE : ST_DRAIN;
                default: state <= ST_IDLE;
            endcase
            result_pc <= 32'b0;
            result_inst <= 32'b0;
            result_error <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (if_req_valid && if_req_ready) begin
                        pending_pc <= if_req_addr;
                        state <= ST_WAIT;
                    end
                end
                ST_WAIT: begin
                    if (cache_ready) begin
                        result_pc <= pending_pc;
                        result_inst <= cache_fetch_valid ? cache_inst : 32'b0;
                        result_error <= !cache_fetch_valid;
                        state <= ST_RESP;
                    end
                end
                ST_RESP: begin
                    if (if_resp_valid && if_resp_ready)
                        state <= ST_IDLE;
                end
                ST_DRAIN: begin
                    if (cache_ready)
                        state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
