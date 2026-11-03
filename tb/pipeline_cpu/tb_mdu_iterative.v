`timescale 1ns / 1ps
// V0.8 iterative MDU module-level regression.
// Verilog-2001 compatible; intended for Vivado 2019.1.
// This is a module testbench, not a CPU integration test.

module tb_mdu_iterative;
    localparam [2:0] MDU_MUL_W   = 3'b000;
    localparam [2:0] MDU_MULH_W  = 3'b001;
    localparam [2:0] MDU_MULH_WU = 3'b010;
    localparam [2:0] MDU_DIV_W   = 3'b011;
    localparam [2:0] MDU_DIV_WU  = 3'b100;
    localparam [2:0] MDU_MOD_W   = 3'b101;
    localparam [2:0] MDU_MOD_WU  = 3'b110;
    localparam [2:0] MDU_RSVD    = 3'b111;

    reg clk;
    reg rst;
    reg start;
    reg [2:0] op;
    reg [31:0] operand_a;
    reg [31:0] operand_b;
    reg result_ready;

    wire busy;
    wire done;
    wire [31:0] result;
    wire div_zero;

    integer checks;
    integer errors;
    integer case_count;

    mdu_iterative dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .op(op),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .result_ready(result_ready),
        .busy(busy),
        .done(done),
        .result(result),
        .div_zero(div_zero)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task check;
        input condition;
        input [8*120-1:0] message;
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL [%0d] @%0t: %0s", checks, $time, message);
            end else begin
                $display("PASS [%0d] @%0t: %0s", checks, $time, message);
            end
        end
    endtask

    task run_case;
        input [8*40-1:0] case_name;
        input [2:0] op_i;
        input [31:0] a_i;
        input [31:0] b_i;
        input [31:0] expected_result;
        input expected_div_zero;
        input integer expected_latency;
        integer cycles;
        integer j;
        begin
            @(negedge clk);
            op = op_i;
            operand_a = a_i;
            operand_b = b_i;
            result_ready = 1'b0;
            start = 1'b1;

            @(posedge clk);
            #1;
            start = 1'b0;
            case_count = case_count + 1;
            $display("CASE %0d: %0s", case_count, case_name);

            if (expected_latency == 0) begin
                check(done && !busy,
                      "operation completes on acceptance edge");
            end else begin
                check(busy && !done,
                      "operation enters busy state");
                cycles = 0;
                while (!done && cycles < 40) begin
                    @(posedge clk);
                    #1;
                    cycles = cycles + 1;
                end
                check(done,
                      "operation eventually asserts done");
                check(cycles == expected_latency,
                      "operation has exact iterative latency");
            end

            check(!busy && done,
                  "done is valid and busy is low");
            check(result === expected_result,
                  "result matches expected value");
            check(div_zero === expected_div_zero,
                  "div_zero matches expected status");

            // Backpressure: hold the completed result for three full clocks.
            // A new start presented while done is pending must be ignored.
            for (j = 0; j < 3; j = j + 1) begin
                @(negedge clk);
                start = 1'b1;
                op = MDU_MUL_W;
                operand_a = 32'd6;
                operand_b = 32'd7;
                result_ready = 1'b0;
                @(posedge clk);
                #1;
                start = 1'b0;
                check(done && !busy &&
                      result === expected_result &&
                      div_zero === expected_div_zero,
                      "result and status held under backpressure");
            end

            @(negedge clk);
            start = 1'b0;
            result_ready = 1'b1;
            @(posedge clk);
            #1;
            check(!done && !busy,
                  "result handshake releases MDU");
            result_ready = 1'b0;
        end
    endtask

    task test_start_ignored_while_busy;
        integer j;
        integer cycles;
        begin
            @(negedge clk);
            op = MDU_MUL_W;
            operand_a = 32'd6;
            operand_b = 32'd7;
            result_ready = 1'b0;
            start = 1'b1;
            @(posedge clk);
            #1;
            start = 1'b0;
            check(busy && !done, "busy-start test launches first request");

            // Try to launch a different operation while MUL is in progress.
            for (j = 0; j < 5; j = j + 1) begin
                @(negedge clk);
                op = MDU_DIV_WU;
                operand_a = 32'd99;
                operand_b = 32'd3;
                start = 1'b1;
                @(posedge clk);
                #1;
                start = 1'b0;
                check(busy && !done,
                      "start while busy is ignored; original operation continues");
            end

            cycles = 0;
            while (!done && cycles < 40) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
            end
            check(done && result === 32'd42 && !div_zero,
                  "ignored busy starts do not corrupt original MUL result");

            @(negedge clk);
            result_ready = 1'b1;
            @(posedge clk);
            #1;
            check(!done && !busy, "busy-start test result is consumed");
            result_ready = 1'b0;
        end
    endtask

    task test_reset_abort;
        integer j;
        begin
            @(negedge clk);
            op = MDU_DIV_WU;
            operand_a = 32'hFFFF_FFFF;
            operand_b = 32'd3;
            result_ready = 1'b0;
            start = 1'b1;
            @(posedge clk);
            #1;
            start = 1'b0;
            check(busy && !done, "reset-abort test starts a DIV");

            for (j = 0; j < 6; j = j + 1) begin
                @(posedge clk);
                #1;
            end
            check(busy && !done, "DIV remains active before reset");

            @(negedge clk);
            rst = 1'b1;
            @(posedge clk);
            #1;
            check(!busy && !done && result === 32'd0 && !div_zero,
                  "synchronous reset cancels active MDU operation");

            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    task test_reset_pending_result;
        begin
            @(negedge clk);
            op = MDU_DIV_W;
            operand_a = 32'd55;
            operand_b = 32'd0;
            result_ready = 1'b0;
            start = 1'b1;
            @(posedge clk);
            #1;
            start = 1'b0;
            check(done && !busy && div_zero &&
                  result === 32'hFFFF_FFFF,
                  "divide-by-zero creates a pending completed result");

            @(negedge clk);
            rst = 1'b1;
            @(posedge clk);
            #1;
            check(!busy && !done && result === 32'd0 && !div_zero,
                  "reset discards a completed but unconsumed result");

            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    initial begin
        rst = 1'b1;
        start = 1'b0;
        op = MDU_RSVD;
        operand_a = 32'd0;
        operand_b = 32'd0;
        result_ready = 1'b0;
        checks = 0;
        errors = 0;
        case_count = 0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        $display("==============================================");
        $display("V0.8 ITERATIVE MDU MODULE REGRESSION");
        $display("==============================================");

        run_case("MUL.W positive",       MDU_MUL_W,   32'd7,          32'd9,          32'd63,          1'b0, 32);
        run_case("MUL.W negative",       MDU_MUL_W,   32'hFFFF_FFF9,  32'd9,          32'hFFFF_FFC1,   1'b0, 32);
        run_case("MUL.W low overflow",   MDU_MUL_W,   32'hFFFF_FFFF,  32'd2,          32'hFFFF_FFFE,   1'b0, 32);
        run_case("MULH.W negative",      MDU_MULH_W,  32'hFFFF_FFFE,  32'd3,          32'hFFFF_FFFF,   1'b0, 32);
        run_case("MULH.W positive",      MDU_MULH_W,  32'h7FFF_FFFF,  32'd2,          32'd0,          1'b0, 32);
        run_case("MULH.WU unsigned",     MDU_MULH_WU, 32'hFFFF_FFFF,  32'hFFFF_FFFF,  32'hFFFF_FFFE,   1'b0, 32);

        run_case("DIV.W negative dividend", MDU_DIV_W, 32'hFFFF_FF9C, 32'd7,         32'hFFFF_FFF2,   1'b0, 32);
        run_case("DIV.W negative divisor",  MDU_DIV_W, 32'd100,       32'hFFFF_FFF9, 32'hFFFF_FFF2,   1'b0, 32);
        run_case("DIV.WU basic",            MDU_DIV_WU,32'd100,       32'd7,         32'd14,          1'b0, 32);
        run_case("DIV.WU large",            MDU_DIV_WU,32'hFFFF_FFFF, 32'd2,         32'h7FFF_FFFF,   1'b0, 32);

        run_case("MOD.W negative dividend", MDU_MOD_W, 32'hFFFF_FF9C, 32'd7,         32'hFFFF_FFFE,   1'b0, 32);
        run_case("MOD.W negative divisor",  MDU_MOD_W, 32'd100,       32'hFFFF_FFF9, 32'd2,          1'b0, 32);
        run_case("MOD.WU basic",            MDU_MOD_WU,32'd100,       32'd7,         32'd2,          1'b0, 32);

        run_case("DIV.W divide by zero",    MDU_DIV_W, 32'd1234,      32'd0,         32'hFFFF_FFFF,   1'b1, 0);
        run_case("MOD.WU divide by zero",   MDU_MOD_WU,32'd1234,      32'd0,         32'd1234,        1'b1, 0);

        run_case("DIV.W signed overflow",   MDU_DIV_W, 32'h8000_0000, 32'hFFFF_FFFF,32'h8000_0000,   1'b0, 32);
        run_case("MOD.W signed overflow",   MDU_MOD_W, 32'h8000_0000, 32'hFFFF_FFFF,32'd0,          1'b0, 32);
        run_case("DIV.W zero dividend",     MDU_DIV_W, 32'd0,         32'd7,         32'd0,          1'b0, 32);
        run_case("DIV.WU divisor larger",   MDU_DIV_WU,32'd5,         32'd9,         32'd0,          1'b0, 32);
        run_case("MOD.WU divisor larger",   MDU_MOD_WU,32'd5,         32'd9,         32'd5,          1'b0, 32);
        run_case("Reserved op",             MDU_RSVD,  32'd99,        32'd3,         32'd0,          1'b0, 0);

        test_start_ignored_while_busy();
        test_reset_abort();
        test_reset_pending_result();

        // A fresh operation after reset proves the old transaction did not
        // leave the unit busy or a stale result pending.
        run_case("post-reset MUL.W", MDU_MUL_W, 32'd11, 32'd13, 32'd143, 1'b0, 32);

        $display("----------------------------------------------");
        $display("MDU CASES=%0d CHECKS=%0d ERRORS=%0d",
                 case_count, checks, errors);
        if (errors == 0)
            $display("ALL TESTS PASSED (V0.8 iterative MDU module)");
        else
            $display("TESTS FAILED errors=%0d", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("FATAL TIMEOUT at %0t", $time);
        $finish;
    end
endmodule
