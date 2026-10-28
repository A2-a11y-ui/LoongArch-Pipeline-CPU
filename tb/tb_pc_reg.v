
`timescale 1ns / 1ps

module tb_pc_reg;

    reg clk;
    reg rst;
    reg pc_en;
    reg [31:0] next_pc;

    wire [31:0] pc;

    integer errors;
    integer checks;

    // Instantiate PC register
    pc_reg uut (
        .clk(clk),
        .rst(rst),
        .pc_en(pc_en),
        .next_pc(next_pc),
        .pc(pc)
    );

    // Clock period = 10 ns
    always #5 clk = ~clk;

    // Automatic checking task
    task check_pc;
        input [31:0] expected;
        begin
            #1;
            checks = checks + 1;

            if (pc !== expected) begin
                $display("FAIL: pc=%h expected=%h",
                         pc, expected);
                errors = errors + 1;
            end
            else begin
                $display("PASS: pc=%h", pc);
            end
        end
    endtask

    initial begin

        clk = 0;
        rst = 1;
        pc_en = 0;
        next_pc = 32'h00000000;
        errors = 0;
        checks = 0;

        // Test 1: synchronous reset
        @(posedge clk);
        check_pc(32'h00000000);

        // Test 2: update PC to 4
        @(negedge clk);
        rst = 0;
        pc_en = 1;
        next_pc = 32'h00000004;

        // PC must not update before rising edge
        check_pc(32'h00000000);

        @(posedge clk);
        check_pc(32'h00000004);

        // Test 3: PC hold when pc_en = 0
        @(negedge clk);
        pc_en = 0;
        next_pc = 32'h00000080;

        check_pc(32'h00000004);

        @(posedge clk);
        check_pc(32'h00000004);

        // Test 4: sequential PC update
        @(negedge clk);
        pc_en = 1;
        next_pc = 32'h00000008;

        @(posedge clk);
        check_pc(32'h00000008);

        // Test 5: jump to target address
        @(negedge clk);
        next_pc = 32'h00000100;

        @(posedge clk);
        check_pc(32'h00000100);

        // Test 6: reset priority over enable
        @(negedge clk);
        rst = 1;
        pc_en = 1;
        next_pc = 32'h00000200;

        // Before edge, PC keeps old value
        check_pc(32'h00000100);

        @(posedge clk);
        check_pc(32'h00000000);

        // Test 7: update to a high address
        @(negedge clk);
        rst = 0;
        pc_en = 1;
        next_pc = 32'hFFFFFFFC;

        @(posedge clk);
        check_pc(32'hFFFFFFFC);

        // Test 8: reset even when pc_en = 0
        @(negedge clk);
        rst = 1;
        pc_en = 0;
        next_pc = 32'h00000008;

        check_pc(32'hFFFFFFFC);

        @(posedge clk);
        check_pc(32'h00000000);

        // Final result
        if (errors == 0)
            $display("ALL TESTS PASSED (%0d checks)", checks);
        else
            $display("TESTS FAILED: %0d errors", errors);

        $finish;

    end

endmodule
