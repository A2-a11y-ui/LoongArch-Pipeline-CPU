// Uncached instruction fetch controller for imem_latency (benchmark baseline).
// A request stays stable until ready=1, then consumes one instruction.
// Combinational invalid-address response produces no backing transaction.
module if_direct_latency (
    input wire clk,
    input wire rst,
    input wire req_valid,
    input wire [31:0] req_addr,
    output wire [31:0] inst,
    output wire ready,
    output wire fetch_valid,
    output wire stall,
    output wire [31:0] mem_addr,
    output wire mem_req,
    input wire mem_ready,
    input wire [31:0] mem_rdata,
    input wire mem_addr_valid
);
    localparam S_IDLE=2'd0, S_SEND=2'd1, S_WAIT=2'd2, S_RESP=2'd3;
    reg [1:0] state;
    reg [31:0] addr_hold;
    reg [31:0] data_hold;
    reg valid_hold;
    wire req_legal=(req_addr[1:0] == 2'b00) &&
                   (req_addr[31:10] == 22'b0);

    assign ready = req_valid && ((state == S_RESP) ||
                                 ((state == S_IDLE) && !req_legal));
    assign fetch_valid = ready && ((state == S_RESP) ? valid_hold : 1'b0);
    assign stall = req_valid && !ready;
    assign inst = fetch_valid ? data_hold : 32'b0;
    assign mem_req = (state == S_SEND);
    assign mem_addr = (state == S_SEND) ? addr_hold : 32'b0;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            addr_hold <= 0;
            data_hold <= 0;
            valid_hold <= 0;
        end else begin
            case(state)
                S_IDLE: if(req_valid && req_legal) begin
                    addr_hold <= req_addr;
                    state <= S_SEND;
                end
                S_SEND: state <= S_WAIT;
                S_WAIT: if(mem_ready) begin
                    valid_hold <= mem_addr_valid;
                    data_hold <= mem_rdata;
                    state <= S_RESP;
                end
                S_RESP: if(req_valid) state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
