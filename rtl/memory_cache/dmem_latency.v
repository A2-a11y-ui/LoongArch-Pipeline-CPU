`timescale 1ns / 1ps
// V0.7-MEM: synthesizable, single-outstanding, variable-latency data memory.
//
// Request channel:
//   req_fire = req_valid && req_ready (sampled on posedge clk).
//   The requester must hold req_valid and all request payload fields stable
//   until req_fire. req_addr is a byte address. V0.7 supports aligned 32-bit
//   LD.W/ST.W accesses only.
//
// Response channel:
//   resp_fire = resp_valid && resp_ready (sampled on posedge clk).
//   Every accepted request produces exactly one response, including errors.
//   resp_valid, resp_rdata and resp_error remain stable until resp_fire.
//   No new request is accepted while a response is outstanding.
//
// Store semantics:
//   A valid Store changes RAM exactly once, on resp_fire. Thus a Store whose
//   response is backpressured has not yet changed RAM. Reset before resp_fire
//   aborts the transaction without a Store side effect.
//
// Error semantics:
//   Unaligned or out-of-range accesses return resp_error=1 and resp_rdata=0.
//   An errored Store never changes RAM. The CPU must consume the error
//   response, suppress the instruction's architectural side effects, and
//   expose diagnostic/fault status; exception/trap handling is outside V0.7.
//
// Latency:
//   READ_LATENCY / WRITE_LATENCY count rising edges after request acceptance
//   until resp_valid is first asserted. Minimum effective latency is 1.
//   For example, LATENCY=1 means resp_valid appears just after the next rising
//   edge, never combinationally in the same request-acceptance cycle.
//
// Reset:
//   Synchronous, active high. Reset aborts any request/response not yet
//   completed by resp_fire. RAM contents are initialized at configuration /
//   simulation time and are not cleared by reset.
//
// The internal store_commit_fire wire is a verification observation point;
// it is not a module port.
module dmem_latency #(
    parameter integer READ_LATENCY  = 3,
    parameter integer WRITE_LATENCY = 3,
    parameter integer WORDS         = 256,
    parameter INIT_FILE = ""
)(
    input  wire        clk,
    input  wire        rst,

    input  wire        req_valid,
    output wire        req_ready,
    input  wire        req_write,
    input  wire [31:0] req_addr,
    input  wire [31:0] req_wdata,

    output reg         resp_valid,
    input  wire        resp_ready,
    output reg  [31:0] resp_rdata,
    output reg         resp_error
);

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_WAIT = 2'd1;
    localparam [1:0] ST_RESP = 2'd2;

    localparam integer EFFECTIVE_READ_LATENCY =
        (READ_LATENCY < 1) ? 1 : READ_LATENCY;
    localparam integer EFFECTIVE_WRITE_LATENCY =
        (WRITE_LATENCY < 1) ? 1 : WRITE_LATENCY;

    reg [1:0]  state;
    reg [31:0] wait_count;

    reg        pending_write;
    reg [31:0] pending_addr;
    reg [31:0] pending_wdata;

    reg [31:0] mem [0:WORDS-1];
    integer init_index;

    wire pending_addr_aligned;
    wire pending_addr_in_range;
    wire pending_addr_valid;
    wire store_commit_fire;

    assign req_ready = (state == ST_IDLE) && !rst;

    assign pending_addr_aligned   = (pending_addr[1:0] == 2'b00);
    assign pending_addr_in_range = (pending_addr[31:2] < WORDS);
    assign pending_addr_valid     = pending_addr_aligned &&
                                    pending_addr_in_range;

    // A Store is committed only when its response is actually consumed.
    // This guarantees no repeated side effect under response backpressure.
    assign store_commit_fire =
        (state == ST_RESP) &&
        resp_valid &&
        resp_ready &&
        pending_write &&
        pending_addr_valid &&
        !resp_error &&
        !rst;

    initial begin
        for (init_index = 0; init_index < WORDS; init_index = init_index + 1)
            mem[init_index] = 32'd0;

        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) begin
        if (rst) begin
            state         <= ST_IDLE;
            wait_count    <= 32'd0;
            pending_write <= 1'b0;
            pending_addr  <= 32'd0;
            pending_wdata <= 32'd0;
            resp_valid    <= 1'b0;
            resp_rdata    <= 32'd0;
            resp_error    <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (req_valid && req_ready) begin
                        pending_write <= req_write;
                        pending_addr  <= req_addr;
                        pending_wdata <= req_wdata;
                        if (req_write)
                            wait_count <= EFFECTIVE_WRITE_LATENCY;
                        else
                            wait_count <= EFFECTIVE_READ_LATENCY;
                        state <= ST_WAIT;
                    end
                end

                ST_WAIT: begin
                    if (wait_count > 32'd1) begin
                        wait_count <= wait_count - 1'b1;
                    end else begin
                        wait_count <= 32'd0;

                        if (!pending_addr_valid) begin
                            resp_rdata <= 32'd0;
                            resp_error <= 1'b1;
                        end else if (pending_write) begin
                            // Store side effect is deferred until resp_fire.
                            resp_rdata <= 32'd0;
                            resp_error <= 1'b0;
                        end else begin
                            // Capture Load data once; hold it through backpressure.
                            resp_rdata <= mem[pending_addr[31:2]];
                            resp_error <= 1'b0;
                        end

                        resp_valid <= 1'b1;
                        state      <= ST_RESP;
                    end
                end

                ST_RESP: begin
                    if (resp_valid && resp_ready) begin
                        if (store_commit_fire)
                            mem[pending_addr[31:2]] <= pending_wdata;

                        resp_valid    <= 1'b0;
                        resp_rdata    <= 32'd0;
                        resp_error    <= 1'b0;
                        pending_write <= 1'b0;
                        pending_addr  <= 32'd0;
                        pending_wdata <= 32'd0;
                        state         <= ST_IDLE;
                    end
                end

                default: begin
                    state         <= ST_IDLE;
                    wait_count    <= 32'd0;
                    pending_write <= 1'b0;
                    resp_valid    <= 1'b0;
                    resp_rdata    <= 32'd0;
                    resp_error    <= 1'b0;
                end
            endcase
        end
    end

endmodule
