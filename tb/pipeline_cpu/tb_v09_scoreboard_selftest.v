`timescale 1ns/1ps
// V0.9 scoreboard SELF-TEST. Does not instantiate or test a CPU.
// Intentionally injects incorrect commit events and requires their detection.
module tb_v09_scoreboard_selftest;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg sb_rst = 1'b1;
    reg wb_valid = 1'b0;
    reg [31:0] wb_pc = 0;
    reg [4:0]  wb_rd = 0;
    reg [31:0] wb_data = 0;
    reg st_valid = 1'b0;
    reg [31:0] st_pc = 0;
    reg [31:0] st_addr = 0;
    reg [31:0] st_data = 0;
    reg check_finish = 1'b0;
    wire [31:0] wb_count, st_count, errors;
    wire check_done, check_pass;
    integer passed = 0;
    integer failed = 0;

    v09_commit_scoreboard #(.MAX_WB(16), .MAX_STORE(8)) dut (
        .clk(clk), .sb_rst(sb_rst),
        .wb_commit_valid(wb_valid), .wb_commit_pc(wb_pc),
        .wb_commit_rd(wb_rd), .wb_commit_data(wb_data),
        .store_commit_valid(st_valid), .store_commit_pc(st_pc),
        .store_commit_addr(st_addr), .store_commit_data(st_data),
        .check_finish(check_finish), .wb_count(wb_count),
        .store_count(st_count), .error_count(errors),
        .check_done(check_done), .check_pass(check_pass)
    );

    task reset_epoch;
    begin
        @(negedge clk);
        sb_rst = 1'b1;
        wb_valid = 1'b0;
        st_valid = 1'b0;
        check_finish = 1'b0;
        @(negedge clk);
        sb_rst = 1'b0;
    end
    endtask

    task send_wb;
        input [31:0] pc;
        input [4:0] rd;
        input [31:0] data;
    begin
        @(negedge clk);
        wb_valid = 1'b1;
        wb_pc = pc;
        wb_rd = rd;
        wb_data = data;
        @(negedge clk);
        wb_valid = 1'b0;
    end
    endtask

    task send_store;
        input [31:0] pc;
        input [31:0] addr;
        input [31:0] data;
    begin
        @(negedge clk);
        st_valid = 1'b1;
        st_pc = pc;
        st_addr = addr;
        st_data = data;
        @(negedge clk);
        st_valid = 1'b0;
    end
    endtask

    task send_both;
        input [31:0] wpc;
        input [4:0] wrd;
        input [31:0] wdata;
        input [31:0] spc;
        input [31:0] saddr;
        input [31:0] sdata;
    begin
        @(negedge clk);
        wb_valid = 1'b1;
        wb_pc = wpc;
        wb_rd = wrd;
        wb_data = wdata;
        st_valid = 1'b1;
        st_pc = spc;
        st_addr = saddr;
        st_data = sdata;
        @(negedge clk);
        wb_valid = 1'b0;
        st_valid = 1'b0;
    end
    endtask

    task finish_epoch;
    begin
        @(negedge clk);
        check_finish = 1'b1;
        @(negedge clk);
        check_finish = 1'b0;
        #1;
    end
    endtask

    task check_case;
        input integer id;
        input integer expect_pass;
    begin
        if (check_done !== 1'b1 || (expect_pass != 0 && (check_pass !== 1'b1 || errors !== 0)) ||
            (expect_pass == 0 && (check_pass !== 1'b0 || errors == 0))) begin
            $display("SELFTEST FAIL case=%0d expected_pass=%0d got_done=%b pass=%b errors=%0d",
                     id, expect_pass, check_done, check_pass, errors);
            failed = failed + 1;
        end else begin
            $display("SELFTEST PASS case=%0d (checker expected_pass=%0d, detected_errors=%0d)",
                     id, expect_pass, errors);
            passed = passed + 1;
        end
    end
    endtask

    initial begin
        #1; // avoid time-zero initialization race
        dut.clear_expectations;
        dut.expect_wb(32'h00001000, 5'd1, 32'd6);
        dut.expect_wb(32'h00001004, 5'd2, 32'd3);
        dut.expect_wb(32'h00001008, 5'd3, 32'd18);
        dut.expect_wb(32'h0000100c, 5'd4, 32'd21);
        dut.expect_store(32'h00001010, 32'd4, 32'd18);
        dut.expect_store(32'h00001014, 32'd8, 32'd21);

        // Case 1: completely correct stream, including WB + Store in one cycle.
        reset_epoch;
        send_wb(32'h1000, 5'd1, 32'd6);
        send_wb(32'h1004, 5'd2, 32'd3);
        send_both(32'h1008, 5'd3, 32'd18, 32'h1010, 32'd4, 32'd18);
        send_wb(32'h100c, 5'd4, 32'd21);
        send_store(32'h1014, 32'd8, 32'd21);
        repeat (3) @(negedge clk); // quiet observation window
        finish_epoch;
        check_case(1, 1);

        // Case 2: a repeated register write is an EXTRA commit.
        reset_epoch;
        send_wb(32'h1000, 5'd1, 32'd6);
        send_wb(32'h1004, 5'd2, 32'd3);
        send_both(32'h1008, 5'd3, 32'd18, 32'h1010, 32'd4, 32'd18);
        send_wb(32'h100c, 5'd4, 32'd21);
        send_store(32'h1014, 32'd8, 32'd21);
        send_wb(32'h100c, 5'd4, 32'd21);
        finish_epoch;
        check_case(2, 0);

        // Case 3: incorrect WB data must be detected.
        reset_epoch;
        send_wb(32'h1000, 5'd1, 32'd99);
        send_wb(32'h1004, 5'd2, 32'd3);
        send_both(32'h1008, 5'd3, 32'd18, 32'h1010, 32'd4, 32'd18);
        send_wb(32'h100c, 5'd4, 32'd21);
        send_store(32'h1014, 32'd8, 32'd21);
        finish_epoch;
        check_case(3, 0);

        // Case 4: missing Store must fail the final completeness check.
        reset_epoch;
        send_wb(32'h1000, 5'd1, 32'd6);
        send_wb(32'h1004, 5'd2, 32'd3);
        send_both(32'h1008, 5'd3, 32'd18, 32'h1010, 32'd4, 32'd18);
        send_wb(32'h100c, 5'd4, 32'd21);
        finish_epoch;
        check_case(4, 0);

        // Case 5: wrong WB sequence must fail even when values exist later.
        reset_epoch;
        send_wb(32'h1004, 5'd2, 32'd3);
        send_wb(32'h1000, 5'd1, 32'd6);
        send_both(32'h1008, 5'd3, 32'd18, 32'h1010, 32'd4, 32'd18);
        send_wb(32'h100c, 5'd4, 32'd21);
        send_store(32'h1014, 32'd8, 32'd21);
        finish_epoch;
        check_case(5, 0);

        // Case 6: wrong Store address must fail.
        reset_epoch;
        send_wb(32'h1000, 5'd1, 32'd6);
        send_wb(32'h1004, 5'd2, 32'd3);
        send_both(32'h1008, 5'd3, 32'd18, 32'h1010, 32'd12, 32'd18);
        send_wb(32'h100c, 5'd4, 32'd21);
        send_store(32'h1014, 32'd8, 32'd21);
        finish_epoch;
        check_case(6, 0);

        // Case 7: simultaneous WB and Store mistakes must count separately.
        reset_epoch;
        send_wb(32'h1000, 5'd1, 32'd6);
        send_wb(32'h1004, 5'd2, 32'd3);
        send_both(32'h1008, 5'd3, 32'd999, 32'h1010, 32'd4, 32'd999);
        send_wb(32'h100c, 5'd4, 32'd21);
        send_store(32'h1014, 32'd8, 32'd21);
        finish_epoch;
        if (errors < 2) begin
            $display("SELFTEST FAIL simultaneous errors not separately counted: %0d", errors);
            failed = failed + 1;
        end else check_case(7, 0);

        // Case 8: commits AFTER check_finish must invalidate an earlier PASS.
        reset_epoch;
        send_wb(32'h1000, 5'd1, 32'd6);
        send_wb(32'h1004, 5'd2, 32'd3);
        send_both(32'h1008, 5'd3, 32'd18, 32'h1010, 32'd4, 32'd18);
        send_wb(32'h100c, 5'd4, 32'd21);
        send_store(32'h1014, 32'd8, 32'd21);
        finish_epoch;
        check_case(8, 1);
        send_wb(32'h100c, 5'd4, 32'd21);
        #1;
        check_case(9, 0);

        // Case 10: duplicate Store must be flagged as an EXTRA commit.
        reset_epoch;
        send_wb(32'h1000, 5'd1, 32'd6);
        send_wb(32'h1004, 5'd2, 32'd3);
        send_both(32'h1008, 5'd3, 32'd18, 32'h1010, 32'd4, 32'd18);
        send_wb(32'h100c, 5'd4, 32'd21);
        send_store(32'h1014, 32'd8, 32'd21);
        send_store(32'h1014, 32'd8, 32'd21);
        finish_epoch;
        check_case(10, 0);

        // Case 11: an architectural write to r0 is invalid on this interface.
        reset_epoch;
        send_wb(32'h1000, 5'd0, 32'd6);
        send_wb(32'h1004, 5'd2, 32'd3);
        send_both(32'h1008, 5'd3, 32'd18, 32'h1010, 32'd4, 32'd18);
        send_wb(32'h100c, 5'd4, 32'd21);
        send_store(32'h1014, 32'd8, 32'd21);
        finish_epoch;
        check_case(11, 0);

        $display("V09 SCOREBOARD SELFTEST RESULT CASES=%0d PASS=%0d FAIL=%0d", passed+failed, passed, failed);
        if (failed != 0 || passed != 11)
            $fatal(1, "V09 SCOREBOARD SELFTEST FAILED");
        $display("ALL TESTS PASSED (V0.9 independent WB/Store scoreboard self-test)");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "V09 SCOREBOARD SELFTEST TIMEOUT");
    end
endmodule
