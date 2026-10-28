// IF PC request driver -- V0.6 INTEGRATION TEST SUPPORT ONLY.
// NOT the team's future official IF control unit. Do not add to CPU27 top.
// Verilog-2001, compatible with Vivado 2019.1.
// One outstanding request is enforced by icache_if_adapter, not by this driver.
// The PC is advanced on accepted request, not when a response is received.
// Redirect captures a new target regardless of adapter busy; it is held
// at if_req_addr until the adapter accepts it.
module if_pc_driver_v06 #(
    parameter [31:0] RESET_PC = 32'h00000000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        redirect,
    input  wire [31:0] redirect_pc,
    output wire        if_req_valid,
    output wire [31:0] if_req_addr,
    input  wire        if_req_ready
);
    reg [31:0] next_pc;
    wire req_fire = if_req_valid && if_req_ready;
    assign if_req_valid = !rst && !redirect;
    assign if_req_addr = next_pc;

    always @(posedge clk) begin
        if (rst)
            next_pc <= RESET_PC;
        else if (redirect)
            next_pc <= redirect_pc;
        else if (req_fire)
            next_pc <= next_pc + 32'd4;
    end
endmodule
