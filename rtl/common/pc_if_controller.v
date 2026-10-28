
module pc_if_controller #(
    parameter [31:0] RESET_PC = 32'h00000000
)(
    input  wire        clk,
    input  wire        rst,

    // Branch redirect from pipeline control
    input  wire        redirect,
    input  wire [31:0] redirect_pc,

    // Request interface to I-Cache Adapter
    output wire        if_req_valid,
    output wire [31:0] if_req_addr,
    input  wire        if_req_ready
);

    // PC of the next instruction request
    reg [31:0] next_req_pc;

    // A request is accepted only when both are high
    wire req_fire;

    assign if_req_valid = !rst && !redirect;
    assign if_req_addr  = next_req_pc;

    assign req_fire = if_req_valid && if_req_ready;

    always @(posedge clk) begin

        // Priority 1: synchronous reset
        if (rst) begin
            next_req_pc <= RESET_PC;
        end

        // Priority 2: branch redirect
        else if (redirect) begin
            next_req_pc <= redirect_pc;
        end

        // Priority 3: accepted request
        else if (req_fire) begin
            next_req_pc <= next_req_pc + 32'd4;
        end

        // Otherwise keep the current request PC.
    end

endmodule
