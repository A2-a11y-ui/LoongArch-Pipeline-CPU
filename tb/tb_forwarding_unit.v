`timescale 1ns / 1ps

// Forwarding Unit directed verification, Verilog-2001, Vivado 2019.1.
// Each scenario checks four outputs: forward_a, forward_b, wait_a, wait_b.
module tb_forwarding_unit;

    reg        ex_valid;
    reg [4:0]  ex_rs1_addr, ex_rs2_addr;
    reg        ex_rs1_used, ex_rs2_used;
    reg        exmem_valid, exmem_reg_write;
    reg [4:0]  exmem_rd_addr;
    reg        exmem_result_ready;
    reg        memwb_valid, memwb_reg_write;
    reg [4:0]  memwb_rd_addr;
    wire [1:0] forward_a, forward_b;
    wire       wait_a, wait_b;

    integer cases, checks, errors;

    forwarding_unit dut (
        .ex_valid(ex_valid),
        .ex_rs1_addr(ex_rs1_addr), .ex_rs2_addr(ex_rs2_addr),
        .ex_rs1_used(ex_rs1_used), .ex_rs2_used(ex_rs2_used),
        .exmem_valid(exmem_valid), .exmem_reg_write(exmem_reg_write),
        .exmem_rd_addr(exmem_rd_addr),
        .exmem_result_ready(exmem_result_ready),
        .memwb_valid(memwb_valid), .memwb_reg_write(memwb_reg_write),
        .memwb_rd_addr(memwb_rd_addr),
        .forward_a(forward_a), .forward_b(forward_b),
        .wait_a(wait_a), .wait_b(wait_b)
    );

    task defaults;
    begin
        ex_valid = 1'b1;
        ex_rs1_addr = 5'd3;
        ex_rs2_addr = 5'd4;
        ex_rs1_used = 1'b1;
        ex_rs2_used = 1'b1;
        exmem_valid = 1'b0;
        exmem_reg_write = 1'b0;
        exmem_rd_addr = 5'd0;
        exmem_result_ready = 1'b0;
        memwb_valid = 1'b0;
        memwb_reg_write = 1'b0;
        memwb_rd_addr = 5'd0;
    end
    endtask

    task check_case;
        input [8*72-1:0] description;
        input [1:0] expected_a, expected_b;
        input       expected_wait_a, expected_wait_b;
        integer previous_errors;
    begin
        #1; // Allow combinational signals to settle.
        cases = cases + 1;
        checks = checks + 4;
        previous_errors = errors;
        if (forward_a !== expected_a) errors = errors + 1;
        if (forward_b !== expected_b) errors = errors + 1;
        if (wait_a !== expected_wait_a) errors = errors + 1;
        if (wait_b !== expected_wait_b) errors = errors + 1;
        if (errors == previous_errors)
            $display("PASS [%0d] %0s", cases, description);
        else
            $display("FAIL [%0d] %0s: got a=%b b=%b wa=%b wb=%b, expected a=%b b=%b wa=%b wb=%b",
                     cases, description, forward_a, forward_b, wait_a, wait_b,
                     expected_a, expected_b, expected_wait_a, expected_wait_b);
    end
    endtask

    initial begin
        cases = 0;
        checks = 0;
        errors = 0;

        defaults();
        check_case("No producer: use original operands", 2'b00, 2'b00, 0, 0); // 1

        defaults();
        ex_valid = 0;
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 3; exmem_result_ready = 1;
        check_case("Invalid EX instruction must not forward", 2'b00, 2'b00, 0, 0); // 2

        defaults();
        ex_rs1_used = 0; ex_rs2_used = 0;
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 3; exmem_result_ready = 1;
        check_case("Unused sources ignored", 2'b00, 2'b00, 0, 0); // 3

        defaults();
        ex_rs1_addr = 0;
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 0; exmem_result_ready = 1;
        check_case("r0 never forwards to source A", 2'b00, 2'b00, 0, 0); // 4

        defaults();
        ex_rs2_addr = 0;
        memwb_valid = 1; memwb_reg_write = 1; memwb_rd_addr = 0;
        check_case("r0 never forwards to source B", 2'b00, 2'b00, 0, 0); // 5

        defaults();
        exmem_valid = 1; exmem_reg_write = 0; exmem_rd_addr = 3; exmem_result_ready = 1;
        check_case("EX/MEM non-writer ignored", 2'b00, 2'b00, 0, 0); // 6

        defaults();
        exmem_valid = 0; exmem_reg_write = 1; exmem_rd_addr = 3; exmem_result_ready = 1;
        check_case("EX/MEM invalid producer ignored", 2'b00, 2'b00, 0, 0); // 7

        defaults();
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 0; exmem_result_ready = 1;
        check_case("EX/MEM destination r0 ignored", 2'b00, 2'b00, 0, 0); // 8

        defaults();
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 3; exmem_result_ready = 1;
        check_case("EX/MEM forwards to A", 2'b10, 2'b00, 0, 0); // 9

        defaults();
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 4; exmem_result_ready = 1;
        check_case("EX/MEM forwards to B", 2'b00, 2'b10, 0, 0); // 10

        defaults();
        ex_rs2_addr = 3;
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 3; exmem_result_ready = 1;
        check_case("EX/MEM forwards to both sources", 2'b10, 2'b10, 0, 0); // 11

        defaults();
        memwb_valid = 1; memwb_reg_write = 1; memwb_rd_addr = 3;
        check_case("MEM/WB forwards to A", 2'b01, 2'b00, 0, 0); // 12

        defaults();
        memwb_valid = 1; memwb_reg_write = 1; memwb_rd_addr = 4;
        check_case("MEM/WB forwards to B", 2'b00, 2'b01, 0, 0); // 13

        defaults();
        ex_rs2_addr = 3;
        memwb_valid = 1; memwb_reg_write = 1; memwb_rd_addr = 3;
        check_case("MEM/WB forwards to both sources", 2'b01, 2'b01, 0, 0); // 14

        defaults();
        memwb_valid = 0; memwb_reg_write = 1; memwb_rd_addr = 3;
        check_case("MEM/WB invalid producer ignored", 2'b00, 2'b00, 0, 0); // 15

        defaults();
        memwb_valid = 1; memwb_reg_write = 0; memwb_rd_addr = 3;
        check_case("MEM/WB non-writer ignored", 2'b00, 2'b00, 0, 0); // 16

        defaults();
        ex_rs1_addr = 0; memwb_valid = 1; memwb_reg_write = 1; memwb_rd_addr = 0;
        check_case("MEM/WB destination r0 ignored", 2'b00, 2'b00, 0, 0); // 17

        defaults();
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 3; exmem_result_ready = 1;
        memwb_valid = 1; memwb_reg_write = 1; memwb_rd_addr = 3;
        check_case("EX/MEM wins over MEM/WB for A", 2'b10, 2'b00, 0, 0); // 18

        defaults();
        ex_rs2_addr = 3;
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 3; exmem_result_ready = 1;
        memwb_valid = 1; memwb_reg_write = 1; memwb_rd_addr = 3;
        check_case("EX/MEM wins for both sources", 2'b10, 2'b10, 0, 0); // 19

        defaults();
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 3; exmem_result_ready = 1;
        memwb_valid = 1; memwb_reg_write = 1; memwb_rd_addr = 4;
        check_case("Different producers: A from EX/MEM, B from MEM/WB", 2'b10, 2'b01, 0, 0); // 20

        defaults();
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 4; exmem_result_ready = 1;
        memwb_valid = 1; memwb_reg_write = 1; memwb_rd_addr = 3;
        check_case("Different producers: A from MEM/WB, B from EX/MEM", 2'b01, 2'b10, 0, 0); // 21

        defaults();
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 3; exmem_result_ready = 0;
        check_case("Unready EX/MEM A: wait, no wrong forwarding", 2'b00, 2'b00, 1, 0); // 22

        defaults();
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 4; exmem_result_ready = 0;
        check_case("Unready EX/MEM B: wait, no wrong forwarding", 2'b00, 2'b00, 0, 1); // 23

        defaults();
        ex_rs2_addr = 3;
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 3; exmem_result_ready = 0;
        check_case("Unready EX/MEM both sources must wait", 2'b00, 2'b00, 1, 1); // 24

        defaults();
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 3; exmem_result_ready = 0;
        memwb_valid = 1; memwb_reg_write = 1; memwb_rd_addr = 3;
        check_case("Newest A unready: cannot use stale MEM/WB A", 2'b00, 2'b00, 1, 0); // 25

        defaults();
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 4; exmem_result_ready = 0;
        memwb_valid = 1; memwb_reg_write = 1; memwb_rd_addr = 4;
        check_case("Newest B unready: cannot use stale MEM/WB B", 2'b00, 2'b00, 0, 1); // 26

        defaults();
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 3; exmem_result_ready = 0;
        memwb_valid = 1; memwb_reg_write = 1; memwb_rd_addr = 4;
        check_case("Wait on A while forwarding B from MEM/WB", 2'b00, 2'b01, 1, 0); // 27

        defaults();
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 4; exmem_result_ready = 0;
        memwb_valid = 1; memwb_reg_write = 1; memwb_rd_addr = 3;
        check_case("Forward A from MEM/WB while waiting on B", 2'b01, 2'b00, 0, 1); // 28

        defaults();
        ex_rs2_used = 0;
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 3; exmem_result_ready = 1;
        check_case("Unused source B remains original", 2'b10, 2'b00, 0, 0); // 29

        defaults();
        ex_rs1_used = 0;
        memwb_valid = 1; memwb_reg_write = 1; memwb_rd_addr = 4;
        check_case("Unused source A remains original", 2'b00, 2'b01, 0, 0); // 30

        defaults();
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 5; exmem_result_ready = 1;
        memwb_valid = 1; memwb_reg_write = 1; memwb_rd_addr = 3;
        check_case("EX/MEM different destination: MEM/WB A eligible", 2'b01, 2'b00, 0, 0); // 31

        defaults();
        exmem_valid = 1; exmem_reg_write = 0; exmem_rd_addr = 3; exmem_result_ready = 0;
        memwb_valid = 1; memwb_reg_write = 1; memwb_rd_addr = 3;
        check_case("EX/MEM non-writer does not block MEM/WB A", 2'b01, 2'b00, 0, 0); // 32

        defaults();
        exmem_valid = 0; exmem_reg_write = 1; exmem_rd_addr = 3; exmem_result_ready = 0;
        memwb_valid = 1; memwb_reg_write = 1; memwb_rd_addr = 3;
        check_case("EX/MEM invalid stage does not block MEM/WB A", 2'b01, 2'b00, 0, 0); // 33

        defaults();
        exmem_valid = 1; exmem_reg_write = 1; exmem_rd_addr = 3; exmem_result_ready = 0;
        check_case("Unready dependence asserted", 2'b00, 2'b00, 1, 0); // 34
        exmem_result_ready = 1;
        check_case("Ready transition replaces wait with forwarding", 2'b10, 2'b00, 0, 0); // 35

        defaults();
        ex_valid = 0;
        memwb_valid = 1; memwb_reg_write = 1; memwb_rd_addr = 3;
        check_case("Invalid EX suppresses MEM/WB forwarding", 2'b00, 2'b00, 0, 0); // 36

        $display("----------------------------------------------");
        $display("Total cases = %0d, signal checks = %0d, errors = %0d", cases, checks, errors);
        if ((errors == 0) && (cases == 36) && (checks == 144))
            $display("ALL TESTS PASSED (36 cases, 144 signal checks)");
        else
            $display("TESTS FAILED");
        $finish;
    end
endmodule
