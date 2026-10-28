
`timescale 1ns / 1ps

module tb_logic_opcode;

    reg [31:0] inst;
    integer tests;
    integer errors;

    // 三寄存器指令的固定编码
    localparam [31:0] MASK     = 32'hFFFF8000;
    localparam [31:0] OP_NOR   = 32'h00140000;
    localparam [31:0] OP_AND   = 32'h00148000;
    localparam [31:0] OP_OR    = 32'h00150000;
    localparam [31:0] OP_XOR   = 32'h00158000;

    wire is_nor = ((inst & MASK) == OP_NOR);
    wire is_and = ((inst & MASK) == OP_AND);
    wire is_or  = ((inst & MASK) == OP_OR);
    wire is_xor = ((inst & MASK) == OP_XOR);

    // 检查指令识别结果
    task check;
        input [31:0] instruction;
        input [3:0] expected;
        reg [3:0] actual;
        begin
            inst = instruction;
            #1;

            actual = {is_nor, is_and, is_or, is_xor};
            tests = tests + 1;

            if (actual !== expected) begin
                errors = errors + 1;
                $display("FAIL: inst=%h expected=%b actual=%b",
                         inst, expected, actual);
            end else begin
                $display("PASS: inst=%h result=%b",
                         inst, actual);
            end
        end
    endtask

    initial begin
        inst = 0;
        tests = 0;
        errors = 0;

        // 基础识别
        check(OP_NOR, 4'b1000);
        check(OP_AND, 4'b0100);
        check(OP_OR,  4'b0010);
        check(OP_XOR, 4'b0001);

        // 修改寄存器字段，不应影响指令类型
        check(OP_AND | 32'h00007FFF, 4'b0100);
        check(OP_OR  | 32'h00001234, 4'b0010);
        check(OP_XOR | 32'h00005678, 4'b0001);
        check(OP_NOR | 32'h00000123, 4'b1000);

        // 非目标指令不得误识别
        check(32'h00000000, 4'b0000);
        check(32'hFFFFFFFF, 4'b0000);
        check(32'h00160000, 4'b0000);

        $display("--------------------------------");
        $display("Total tests  = %0d", tests);
        $display("Total errors = %0d", errors);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");

        $finish;
    end

endmodule
