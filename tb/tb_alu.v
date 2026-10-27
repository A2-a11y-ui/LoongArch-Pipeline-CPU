
`timescale 1ns / 1ps

module tb_alu;

// 1. Define input and output signals
reg  [31:0] a;
reg  [31:0] b;
reg  [3:0]  alu_op;
wire [31:0] result;

integer errors;

// 2. Instantiate the ALU module
alu uut (
    .a(a),
    .b(b),
    .alu_op(alu_op),
    .result(result)
);

// 3. Define a reusable test task
task check;
    input [31:0] test_a;
    input [31:0] test_b;
    input [3:0]  test_op;
    input [31:0] expected;

    begin
        a = test_a;
        b = test_b;
        alu_op = test_op;

        #10;

        if (result !== expected) begin
            $display("FAIL: op=%h a=%h b=%h result=%h expected=%h",
                     alu_op, a, b, result, expected);
            errors = errors + 1;
        end
        else begin
            $display("PASS: op=%h a=%h b=%h result=%h",
                     alu_op, a, b, result);
        end
    end
endtask

// 4. Run all test cases
initial begin

    errors = 0;

    // ADD
    check(32'd3, 32'd5, 4'h0, 32'd8);
    check(32'hFFFFFFFF, 32'd1, 4'h0, 32'd0);

    // SUB
    check(32'd8, 32'd3, 4'h1, 32'd5);
    check(32'd3, 32'd8, 4'h1, 32'hFFFFFFFB);

    // AND
    check(32'hF0, 32'h0F, 4'h2, 32'h00);

    // OR
    check(32'hF0, 32'h0F, 4'h3, 32'hFF);

    // XOR
    check(32'hAA, 32'h55, 4'h4, 32'hFF);
	
	// NOR
    check(32'h000000F0, 32'h0000000F, 4'h5, 32'hFFFFFF00);

    check(32'h00000000, 32'h00000000, 4'h5, 32'hFFFFFFFF);

    // PASS_B
    check(32'h12345678, 32'h89ABCDEF, 4'hB, 32'h89ABCDEF);

    // Default operation
    check(32'd8, 32'd3, 4'hF, 32'd0);

    // 5. Print the final result
    if (errors == 0)
        $display("ALL TESTS PASSED");
    else
        $display("TESTS FAILED: %0d", errors);

    $finish;

end

endmodule