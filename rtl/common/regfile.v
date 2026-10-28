
module regfile (
    input  wire        clk,
    input  wire        rst,

    input  wire [4:0]  raddr1,
    input  wire [4:0]  raddr2,

    output wire [31:0] rdata1,
    output wire [31:0] rdata2,

    input  wire        we,
    input  wire [4:0]  waddr,
    input  wire [31:0] wdata
);

    
    // 32 general-purpose registers, each 32 bits wide
    reg [31:0] regs [0:31];

    // Loop variable for synchronous reset
    integer i;

    // Synchronous reset and write
always @(posedge clk) begin

    if (rst) begin
        // Clear all 32 registers
        for (i = 0; i < 32; i = i + 1) begin
            regs[i] <= 32'b0;
        end
    end

    else if (we && (waddr != 5'd0)) begin
        // Write only when enabled and address is not r0
        regs[waddr] <= wdata;
    end

end

    // Two asynchronous read ports
assign rdata1 = (raddr1 == 5'd0) ? 32'b0 : regs[raddr1];

assign rdata2 = (raddr2 == 5'd0) ? 32'b0 : regs[raddr2];


endmodule
