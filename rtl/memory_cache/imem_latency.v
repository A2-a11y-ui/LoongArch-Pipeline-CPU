// Fixed-latency, single-outstanding, 1 KiB instruction backing memory.
// Verilog-2001, Vivado 2019.1. FOR FAIR SIMULATION COMPARISON ONLY.
// Request: one-cycle mem_req pulse while idle. Response: one-cycle mem_ready
// pulse with stable registered mem_rdata and mem_addr_valid.
// Both cached and uncached paths instantiate this SAME model and LATENCY.
module imem_latency #(
    parameter integer LATENCY = 3,
    parameter INIT_FILE = ""
) (
    input wire clk,
    input wire rst,
    input wire mem_req,
    input wire [31:0] mem_addr,
    output reg mem_ready,
    output reg [31:0] mem_rdata,
    output reg mem_addr_valid,
    output reg [31:0] transactions
);
    reg [31:0] rom [0:255];
    reg busy;
    reg [31:0] pending_addr;
    integer remaining;
    integer k;
    wire legal = (pending_addr[31:10] == 22'b0) &&
                 (pending_addr[1:0] == 2'b00);

    initial begin
        for (k=0; k<256; k=k+1)
            rom[k] = 32'hA5000000 | k;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, rom);
    end

    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            pending_addr <= 32'b0;
            remaining <= 0;
            mem_ready <= 1'b0;
            mem_rdata <= 32'b0;
            mem_addr_valid <= 1'b0;
            transactions <= 32'b0;
        end else begin
            mem_ready <= 1'b0;
            if (!busy && mem_req) begin
                // Valid because the two controllers issue a one-cycle pulse.
                busy <= 1'b1;
                pending_addr <= mem_addr;
                remaining <= LATENCY;
                transactions <= transactions + 32'd1;
            end else if (busy) begin
                if (remaining <= 1) begin
                    busy <= 1'b0;
                    mem_ready <= 1'b1;
                    mem_addr_valid <= legal;
                    mem_rdata <= legal ? rom[pending_addr[9:2]] : 32'b0;
                end else begin
                    remaining <= remaining - 1;
                end
            end
        end
    end
endmodule
