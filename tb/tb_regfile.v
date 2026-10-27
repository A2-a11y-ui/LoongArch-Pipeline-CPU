
`timescale 1ns / 1ps

module tb_regfile;

reg clk;
reg rst;

reg  [4:0]  raddr1;
reg  [4:0]  raddr2;
wire [31:0] rdata1;
wire [31:0] rdata2;

reg         we;
reg  [4:0]  waddr;
reg  [31:0] wdata;

integer errors;
integer checks;

// Instantiate the register file
regfile uut (
    .clk(clk),
    .rst(rst),
    .raddr1(raddr1),
    .raddr2(raddr2),
    .rdata1(rdata1),
    .rdata2(rdata2),
    .we(we),
    .waddr(waddr),
    .wdata(wdata)
);

// Generate a clock with a 10 ns period
always #5 clk = ~clk;

// Check both read ports
task check_reads;
    input [31:0] expected1;
    input [31:0] expected2;

    begin
        #1;
        checks = checks + 1;

        if ((rdata1 !== expected1) ||
            (rdata2 !== expected2)) begin

            $display("FAIL: rdata1=%h expected1=%h, rdata2=%h expected2=%h",
                     rdata1, expected1, rdata2, expected2);

            errors = errors + 1;
        end
        else begin
            $display("PASS: rdata1=%h rdata2=%h",
                     rdata1, rdata2);
        end
    end
endtask

initial begin

    clk = 0;
    rst = 0;
    we = 0;

    raddr1 = 0;
    raddr2 = 0;
    waddr = 0;
    wdata = 0;

    errors = 0;
    checks = 0;

    // Test 1: r0 always reads zero
    check_reads(32'd0, 32'd0);

    // Test 2: synchronous reset
    rst = 1;
    @(posedge clk);
    #1;
    rst = 0;

    raddr1 = 5;
    raddr2 = 31;
    check_reads(32'd0, 32'd0);

    // Test 3: write r5
    @(negedge clk);
    we = 1;
    waddr = 5;
    wdata = 32'h12345678;
    raddr1 = 5;
    raddr2 = 0;

    // Data must not change before rising edge
    check_reads(32'd0, 32'd0);

    @(posedge clk);
    check_reads(32'h12345678, 32'd0);

    // Test 4: write r31
    @(negedge clk);
    waddr = 31;
    wdata = 32'hDEADBEEF;
    raddr1 = 5;
    raddr2 = 31;

    check_reads(32'h12345678, 32'd0);

    @(posedge clk);
    check_reads(32'h12345678, 32'hDEADBEEF);

    // Test 5: asynchronous read address change
    raddr1 = 31;
    raddr2 = 5;
    check_reads(32'hDEADBEEF, 32'h12345678);

    // Test 6: writing r0 must have no effect
    @(negedge clk);
    waddr = 0;
    wdata = 32'hFFFFFFFF;
    raddr1 = 0;
    raddr2 = 31;

    @(posedge clk);
    check_reads(32'd0, 32'hDEADBEEF);

    // Test 7: we = 0 must prevent writing
    @(negedge clk);
    we = 0;
    waddr = 5;
    wdata = 32'hAAAAAAAA;
    raddr1 = 5;
    raddr2 = 31;

    @(posedge clk);
    check_reads(32'h12345678, 32'hDEADBEEF);

    // Test 8: reset has priority over write
    @(negedge clk);
    rst = 1;
    we = 1;
    waddr = 5;
    wdata = 32'hBBBBBBBB;

    // Synchronous reset: old data remains before edge
    check_reads(32'h12345678, 32'hDEADBEEF);

    @(posedge clk);
    check_reads(32'd0, 32'd0);

    // Final result
    if (errors == 0)
        $display("ALL TESTS PASSED (%0d checks)", checks);
    else
        $display("TESTS FAILED: %0d errors", errors);

    $finish;

end

endmodule
