`timescale 1ns / 1ps

// Standalone combinational testbench for pipeline_control_unit.
// Priority under test: reset > redirect > load-use > normal.
module tb_pipeline_control_unit;
    reg rst;
    reg branch_redirect;
    reg load_use_hazard;

    wire ifid_stall;
    wire ifid_flush;
    wire idex_flush;
    wire hold_fetch_issue_req;

    integer cases;
    integer checks;
    integer errors;

    pipeline_control_unit dut (
        .rst(rst),
        .branch_redirect(branch_redirect),
        .load_use_hazard(load_use_hazard),
        .ifid_stall(ifid_stall),
        .ifid_flush(ifid_flush),
        .idex_flush(idex_flush),
        .hold_fetch_issue_req(hold_fetch_issue_req)
    );

    task run_case;
        input [8*48-1:0] case_name;
        input test_rst;
        input test_redirect;
        input test_load_use;
        input exp_ifid_stall;
        input exp_ifid_flush;
        input exp_idex_flush;
        input exp_hold_fetch;
        begin
            rst = test_rst;
            branch_redirect = test_redirect;
            load_use_hazard = test_load_use;
            #1;
            cases = cases + 1;

            checks = checks + 1;
            if (ifid_stall !== exp_ifid_stall) begin
                errors = errors + 1;
                $display("FAIL [%0d] %0s: ifid_stall got=%b expected=%b",
                         cases, case_name, ifid_stall, exp_ifid_stall);
            end

            checks = checks + 1;
            if (ifid_flush !== exp_ifid_flush) begin
                errors = errors + 1;
                $display("FAIL [%0d] %0s: ifid_flush got=%b expected=%b",
                         cases, case_name, ifid_flush, exp_ifid_flush);
            end

            checks = checks + 1;
            if (idex_flush !== exp_idex_flush) begin
                errors = errors + 1;
                $display("FAIL [%0d] %0s: idex_flush got=%b expected=%b",
                         cases, case_name, idex_flush, exp_idex_flush);
            end

            checks = checks + 1;
            if (hold_fetch_issue_req !== exp_hold_fetch) begin
                errors = errors + 1;
                $display("FAIL [%0d] %0s: hold_fetch_issue_req got=%b expected=%b",
                         cases, case_name, hold_fetch_issue_req, exp_hold_fetch);
            end

            if (ifid_stall === exp_ifid_stall &&
                ifid_flush === exp_ifid_flush &&
                idex_flush === exp_idex_flush &&
                hold_fetch_issue_req === exp_hold_fetch)
                $display("PASS [%0d] %0s", cases, case_name);
        end
    endtask

    initial begin
        rst = 0;
        branch_redirect = 0;
        load_use_hazard = 0;
        cases = 0;
        checks = 0;
        errors = 0;

        // Inputs: rst, redirect, load_use.
        // Outputs: ifid_stall, ifid_flush, idex_flush, hold_fetch_issue_req.
        run_case("normal startup",           0,0,0, 0,0,0,0);
        run_case("load-use hazard",           0,0,1, 1,0,1,1);
        run_case("redirect only",             0,1,0, 0,1,1,0);
        run_case("redirect beats load-use",   0,1,1, 0,1,1,0);
        run_case("reset only",                1,0,0, 0,1,1,1);
        run_case("reset beats load-use",      1,0,1, 0,1,1,1);
        run_case("reset beats redirect",      1,1,0, 0,1,1,1);
        run_case("all three asserted",        1,1,1, 0,1,1,1);

        // Back-to-back transitions, including removing reset/redirect/stall.
        run_case("release reset to normal",  0,0,0, 0,0,0,0);
        run_case("enter hazard again",        0,0,1, 1,0,1,1);
        run_case("release hazard",            0,0,0, 0,0,0,0);
        run_case("redirect after normal",     0,1,0, 0,1,1,0);
        run_case("hazard during redirect",    0,1,1, 0,1,1,0);
        run_case("remove redirect",           0,0,1, 1,0,1,1);
        run_case("reset during hazard",       1,0,1, 0,1,1,1);
        run_case("reset with redirect",       1,1,1, 0,1,1,1);
        run_case("redirect after reset",      0,1,0, 0,1,1,0);
        run_case("redirect with hazard",      0,1,1, 0,1,1,0);
        run_case("back to hazard",            0,0,1, 1,0,1,1);
        run_case("finish at normal",          0,0,0, 0,0,0,0);

        $display("----------------------------------------");
        $display("Total cases = %0d, signal checks = %0d, errors = %0d",
                 cases, checks, errors);
        if (errors == 0 && cases == 20 && checks == 80)
            $display("ALL TESTS PASSED (20 cases, 80 signal checks)");
        else
            $display("TESTS FAILED");
        $finish;
    end
endmodule
