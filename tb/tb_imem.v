`timescale 1ns / 1ps

// Self-checking instruction-memory testbench. No external .mem path needed.
module tb_imem;
    reg  [31:0] addr;
    wire [31:0] inst;
    wire        addr_valid;
    integer tests;
    integer errors;
    integer k;

    imem dut (
        .addr(addr),
        .inst(inst),
        .addr_valid(addr_valid)
    );

    task check;
        input [31:0] test_addr;
        input [31:0] expected_inst;
        input        expected_valid;
        begin
            addr = test_addr;
            #1;
            tests = tests + 1;
            if ((inst !== expected_inst) || (addr_valid !== expected_valid)) begin
                errors = errors + 1;
                $display("FAIL addr=%08h inst=%08h expected=%08h valid=%b expected_valid=%b",
                         addr, inst, expected_inst, addr_valid, expected_valid);
            end else begin
                $display("PASS addr=%08h inst=%08h valid=%b",
                         addr, inst, addr_valid);
            end
        end
    endtask

    initial begin
        addr = 32'h00000000;
        tests = 0;
        errors = 0;
        #1; // allow ROM initialisation to complete

        // Write sample words through hierarchical reference (TESTBENCH ONLY).
        // Real CPU does not have a ROM write interface.
        dut.mem[0]   = 32'h14024681;
        dut.mem[1]   = 32'h03800022;
        dut.mem[2]   = 32'h29800023;
        dut.mem[3]   = 32'h28800024;
        dut.mem[7]   = 32'h001480A5;
        dut.mem[128] = 32'h001580C7;
        dut.mem[255] = 32'h00408020;

        // Address is BYTE address: each next instruction is +4.
        check(32'h00000000, 32'h14024681, 1'b1);
        check(32'h00000004, 32'h03800022, 1'b1);
        check(32'h00000008, 32'h29800023, 1'b1);
        check(32'h0000000C, 32'h28800024, 1'b1);
        check(32'h0000001C, 32'h001480A5, 1'b1);
        check(32'h00000200, 32'h001580C7, 1'b1);
        check(32'h000003FC, 32'h00408020, 1'b1);

        // Defined, untouched ROM locations read as zero.
        check(32'h00000010, 32'h00000000, 1'b1);
        check(32'h00000100, 32'h00000000, 1'b1);

        // Misaligned and out-of-range addresses must not alias valid words.
        check(32'h00000001, 32'h00000000, 1'b0);
        check(32'h00000002, 32'h00000000, 1'b0);
        check(32'h00000003, 32'h00000000, 1'b0);
        check(32'h00000005, 32'h00000000, 1'b0);
        check(32'h000003FF, 32'h00000000, 1'b0);
        check(32'h00000400, 32'h00000000, 1'b0);
        check(32'h00000404, 32'h00000000, 1'b0);
        check(32'h00001000, 32'h00000000, 1'b0);
        check(32'hFFFFFFFC, 32'h00000000, 1'b0);

        // Changing addresses without a clock updates combinational ROM read.
        check(32'h00000000, 32'h14024681, 1'b1);
        check(32'h000003FC, 32'h00408020, 1'b1);

        $display("-------------------------------------");
        $display("Total tests  = %0d", tests);
        $display("Total errors = %0d", errors);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end
endmodule
