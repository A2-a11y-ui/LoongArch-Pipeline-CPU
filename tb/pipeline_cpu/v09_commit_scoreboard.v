`timescale 1ns/1ps
// V0.9 independent architectural commit checker (Verilog-2001).
// Simulation-only. Connect only ONE-CYCLE commit EVENT pulses, never pipeline valid.
// Reference entries are configured by the testbench before releasing sb_rst.
// sb_rst resets this verification epoch; it need not equal the CPU reset.
module v09_commit_scoreboard #(
    parameter integer MAX_WB = 128,
    parameter integer MAX_STORE = 64
) (
    input  wire        clk,
    input  wire        sb_rst,
    input  wire        wb_commit_valid,
    input  wire [31:0] wb_commit_pc,
    input  wire [4:0]  wb_commit_rd,
    input  wire [31:0] wb_commit_data,
    input  wire        store_commit_valid,
    input  wire [31:0] store_commit_pc,
    input  wire [31:0] store_commit_addr,
    input  wire [31:0] store_commit_data,
    input  wire        check_finish,
    output reg  [31:0] wb_count,
    output reg  [31:0] store_count,
    output reg  [31:0] error_count,
    output reg         check_done,
    output reg         check_pass
);
    reg [31:0] golden_wb_pc   [0:MAX_WB-1];
    reg [4:0]  golden_wb_rd   [0:MAX_WB-1];
    reg [31:0] golden_wb_data [0:MAX_WB-1];
    reg [31:0] golden_st_pc   [0:MAX_STORE-1];
    reg [31:0] golden_st_addr [0:MAX_STORE-1];
    reg [31:0] golden_st_data [0:MAX_STORE-1];
    integer golden_wb_n;
    integer golden_st_n;

    // Blocking scratch variables make two failures in the same cycle count as TWO.
    integer next_errors;
    integer next_wb;
    integer next_st;

    initial begin
        golden_wb_n = 0;
        golden_st_n = 0;
        wb_count = 0;
        store_count = 0;
        error_count = 0;
        check_done = 0;
        check_pass = 0;
    end

    task clear_expectations;
    begin
        golden_wb_n = 0;
        golden_st_n = 0;
    end
    endtask

    task expect_wb;
        input [31:0] pc;
        input [4:0] rd;
        input [31:0] data;
    begin
        if (golden_wb_n >= MAX_WB)
            $fatal(1, "V09 SB CONFIG ERROR: WB reference capacity exceeded");
        golden_wb_pc[golden_wb_n]   = pc;
        golden_wb_rd[golden_wb_n]   = rd;
        golden_wb_data[golden_wb_n] = data;
        golden_wb_n = golden_wb_n + 1;
    end
    endtask

    task expect_store;
        input [31:0] pc;
        input [31:0] addr;
        input [31:0] data;
    begin
        if (golden_st_n >= MAX_STORE)
            $fatal(1, "V09 SB CONFIG ERROR: STORE reference capacity exceeded");
        golden_st_pc[golden_st_n]   = pc;
        golden_st_addr[golden_st_n] = addr;
        golden_st_data[golden_st_n] = data;
        golden_st_n = golden_st_n + 1;
    end
    endtask

    always @(posedge clk) begin
        if (sb_rst) begin
            wb_count     <= 0;
            store_count  <= 0;
            error_count  <= 0;
            check_done   <= 1'b0;
            check_pass   <= 1'b0;
        end else begin
            next_errors = error_count;
            next_wb     = wb_count;
            next_st     = store_count;

            if (wb_commit_valid === 1'b1) begin
                if (check_done) begin
                    $display("V09 SB FAIL: WB commit AFTER final check pc=%h", wb_commit_pc);
                    next_errors = next_errors + 1;
                end
                if (wb_commit_rd === 5'd0) begin
                    $display("V09 SB FAIL: architectural WB to r0 pc=%h", wb_commit_pc);
                    next_errors = next_errors + 1;
                end
                if (next_wb >= golden_wb_n) begin
                    $display("V09 SB FAIL: EXTRA WB[%0d] pc=%h rd=%0d data=%h",
                             next_wb, wb_commit_pc, wb_commit_rd, wb_commit_data);
                    next_errors = next_errors + 1;
                end else if (wb_commit_pc   !== golden_wb_pc[next_wb] ||
                             wb_commit_rd   !== golden_wb_rd[next_wb] ||
                             wb_commit_data !== golden_wb_data[next_wb]) begin
                    $display("V09 SB FAIL: WB[%0d] expected pc=%h rd=%0d data=%h; got pc=%h rd=%0d data=%h",
                             next_wb, golden_wb_pc[next_wb], golden_wb_rd[next_wb],
                             golden_wb_data[next_wb], wb_commit_pc, wb_commit_rd, wb_commit_data);
                    next_errors = next_errors + 1;
                end
                next_wb = next_wb + 1;
            end else if (wb_commit_valid !== 1'b0) begin
                $display("V09 SB FAIL: X/Z WB valid at time %0t", $time);
                next_errors = next_errors + 1;
            end

            if (store_commit_valid === 1'b1) begin
                if (check_done) begin
                    $display("V09 SB FAIL: STORE commit AFTER final check pc=%h", store_commit_pc);
                    next_errors = next_errors + 1;
                end
                if (next_st >= golden_st_n) begin
                    $display("V09 SB FAIL: EXTRA STORE[%0d] pc=%h addr=%h data=%h",
                             next_st, store_commit_pc, store_commit_addr, store_commit_data);
                    next_errors = next_errors + 1;
                end else if (store_commit_pc   !== golden_st_pc[next_st] ||
                             store_commit_addr !== golden_st_addr[next_st] ||
                             store_commit_data !== golden_st_data[next_st]) begin
                    $display("V09 SB FAIL: STORE[%0d] expected pc=%h addr=%h data=%h; got pc=%h addr=%h data=%h",
                             next_st, golden_st_pc[next_st], golden_st_addr[next_st],
                             golden_st_data[next_st], store_commit_pc, store_commit_addr, store_commit_data);
                    next_errors = next_errors + 1;
                end
                next_st = next_st + 1;
            end else if (store_commit_valid !== 1'b0) begin
                $display("V09 SB FAIL: X/Z STORE valid at time %0t", $time);
                next_errors = next_errors + 1;
            end

            if (check_finish === 1'b1) begin
                if (check_done) begin
                    $display("V09 SB FAIL: repeated final-check pulse");
                    next_errors = next_errors + 1;
                end
                if (next_wb != golden_wb_n) begin
                    $display("V09 SB FAIL: WB count expected=%0d actual=%0d", golden_wb_n, next_wb);
                    next_errors = next_errors + 1;
                end
                if (next_st != golden_st_n) begin
                    $display("V09 SB FAIL: STORE count expected=%0d actual=%0d", golden_st_n, next_st);
                    next_errors = next_errors + 1;
                end
                check_done <= 1'b1;
                check_pass <= (next_errors == 0);
                $display("V09 SB RESULT WB=%0d/%0d STORE=%0d/%0d ERRORS=%0d",
                         next_wb, golden_wb_n, next_st, golden_st_n, next_errors);
            end else if (check_finish !== 1'b0) begin
                $display("V09 SB FAIL: X/Z check_finish");
                next_errors = next_errors + 1;
            end

            if (next_errors != 0)
                check_pass <= 1'b0;
            wb_count    <= next_wb;
            store_count <= next_st;
            error_count <= next_errors;
        end
    end
endmodule
