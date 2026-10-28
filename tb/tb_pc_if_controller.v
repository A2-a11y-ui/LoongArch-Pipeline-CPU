`timescale 1ns / 1ps

// Standalone directed test for pc_if_controller (Verilog-2001).
// 40 scenarios x 4 external-output checks = 160 signal checks.
module tb_pc_if_controller;

    localparam [31:0] RESET_PC = 32'h0000_0100;

    reg         clk;
    reg         rst;
    reg         redirect;
    reg [31:0]  redirect_pc;
    reg         if_req_ready;
    wire        if_req_valid;
    wire [31:0] if_req_addr;

    integer cases;
    integer checks;
    integer errors;
    integer previous_errors;
    reg [31:0] expected_pc;

    pc_if_controller #(
        .RESET_PC(RESET_PC)
    ) dut (
        .clk(clk),
        .rst(rst),
        .redirect(redirect),
        .redirect_pc(redirect_pc),
        .if_req_valid(if_req_valid),
        .if_req_addr(if_req_addr),
        .if_req_ready(if_req_ready)
    );

    always #5 clk = ~clk;

    // Two assertions, using only publicly visible module ports.
    task check_outputs;
        input [8*72-1:0] description;
        input expected_valid;
        input [31:0] expected_addr;
        begin
            checks = checks + 1;
            if (if_req_valid !== expected_valid) begin
                errors = errors + 1;
                $display("FAIL [%0s] valid: expected=%b actual=%b at %0t",
                         description, expected_valid, if_req_valid, $time);
            end

            checks = checks + 1;
            if (if_req_addr !== expected_addr) begin
                errors = errors + 1;
                $display("FAIL [%0s] addr: expected=%h actual=%h at %0t",
                         description, expected_addr, if_req_addr, $time);
            end
        end
    endtask

    // Change inputs on falling edge, check just before and after rising edge.
    // The software reference updates only on reset, redirect, or req_fire.
    task run_case;
        input [8*72-1:0] description;
        input in_rst;
        input in_redirect;
        input [31:0] in_target;
        input in_ready;
        reg expected_valid;
        reg [31:0] new_expected_pc;
        begin
            @(negedge clk);
            rst = in_rst;
            redirect = in_redirect;
            redirect_pc = in_target;
            if_req_ready = in_ready;
            #1;

            cases = cases + 1;
            previous_errors = errors;
            expected_valid = !in_rst && !in_redirect;
            check_outputs(description, expected_valid, expected_pc);

            if (in_rst)
                new_expected_pc = RESET_PC;
            else if (in_redirect)
                new_expected_pc = in_target;
            else if (expected_valid && in_ready)
                new_expected_pc = expected_pc + 32'd4;
            else
                new_expected_pc = expected_pc;

            @(posedge clk);
            #1;
            expected_pc = new_expected_pc;
            check_outputs(description, expected_valid, expected_pc);

            if (errors == previous_errors)
                $display("PASS [%0d] %0s", cases, description);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        redirect = 1'b0;
        redirect_pc = 32'b0;
        if_req_ready = 1'b0;
        cases = 0;
        checks = 0;
        errors = 0;
        expected_pc = RESET_PC;

        // Initialize DUT through a real synchronous reset edge.
        @(posedge clk);
        #1;
        if (if_req_addr !== RESET_PC || if_req_valid !== 1'b0) begin
            $display("FATAL: initial synchronous reset did not initialize PC");
            $finish;
        end

        run_case("01 first handshake",        0, 0, 32'h0000_0000, 1);
        run_case("02 consecutive handshake",  0, 0, 32'h0000_0000, 1);
        run_case("03 hold not ready",         0, 0, 32'h0000_0000, 0);
        run_case("04 hold still not ready",   0, 0, 32'h0000_0000, 0);
        run_case("05 resume handshake",       0, 0, 32'h0000_0000, 1);
        run_case("06 next request accepted",  0, 0, 32'h0000_0000, 1);
        run_case("07 backpressure",           0, 0, 32'h0000_0000, 0);
        run_case("08 redirect while blocked", 0, 1, 32'h0000_0200, 0);
        run_case("09 target held 1",          0, 0, 32'h0000_0000, 0);
        run_case("10 target held 2",          0, 0, 32'h0000_0000, 0);
        run_case("11 target accepted",        0, 0, 32'h0000_0000, 1);
        run_case("12 subsequent request",     0, 0, 32'h0000_0000, 1);
        run_case("13 redirect beats ready",   0, 1, 32'h0000_0300, 1);
        run_case("14 redirect PC held",       0, 0, 32'h0000_0000, 0);
        run_case("15 redirect PC accepted",   0, 0, 32'h0000_0000, 1);
        run_case("16 redirect target A",      0, 1, 32'h0000_0400, 0);
        run_case("17 redirect target B",      0, 1, 32'h0000_0500, 1);
        run_case("18 redirect target C",      0, 1, 32'h0000_0600, 0);
        run_case("19 latest target held",     0, 0, 32'h0000_0000, 0);
        run_case("20 latest target accepted", 0, 0, 32'h0000_0000, 1);
        run_case("21 reset beats redirect",   1, 1, 32'h0000_0700, 1);
        run_case("22 after reset blocked",    0, 0, 32'h0000_0000, 0);
        run_case("23 after reset accepted",   0, 0, 32'h0000_0000, 1);
        run_case("24 reset while blocked",    1, 0, 32'h0000_0000, 0);
        run_case("25 redirect target zero",   0, 1, 32'h0000_0000, 0);
        run_case("26 accept zero address",    0, 0, 32'h0000_0000, 1);
        run_case("27 accept address four",    0, 0, 32'h0000_0000, 1);
        run_case("28 redirect near wrap",    0, 1, 32'hffff_fffc, 1);
        run_case("29 wrap target blocked",    0, 0, 32'h0000_0000, 0);
        run_case("30 accept wrap target",     0, 0, 32'h0000_0000, 1);
        run_case("31 wrapped PC accepted",    0, 0, 32'h0000_0000, 1);
        run_case("32 redirect to 0x800",      0, 1, 32'h0000_0800, 0);
        run_case("33 target 0x800 held",      0, 0, 32'h0000_0000, 0);
        run_case("34 reset while ready",      1, 0, 32'h0000_0000, 1);
        run_case("35 restart handshake",      0, 0, 32'h0000_0000, 1);
        run_case("36 redirect same target",   0, 1, 32'h0000_0100, 0);
        run_case("37 repeat redirect",        0, 1, 32'h0000_0100, 1);
        run_case("38 repeated target held",   0, 0, 32'h0000_0000, 0);
        run_case("39 repeated target accept", 0, 0, 32'h0000_0000, 1);
        run_case("40 final hold",             0, 0, 32'h0000_0000, 0);

        $display("-----------------------------------------------");
        $display("Total cases = %0d, signal checks = %0d, errors = %0d",
                 cases, checks, errors);
        if ((cases == 40) && (checks == 160) && (errors == 0))
            $display("ALL TESTS PASSED (40 cases, 160 signal checks)");
        else
            $display("TESTS FAILED");
        $finish;
    end
endmodule
