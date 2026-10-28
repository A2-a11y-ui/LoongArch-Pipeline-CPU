`timescale 1ns / 1ps

// Independent functional test for IF/ID pipeline register.
// Expected priority: rst > flush > stall > normal capture.
module tb_if_id_reg;

    reg         clk;
    reg         rst;
    reg         stall;
    reg         flush;
    reg         if_valid;
    reg  [31:0] if_pc;
    reg  [31:0] if_inst;

    wire        id_valid;
    wire [31:0] id_pc;
    wire [31:0] id_inst;

    integer checks;
    integer errors;

    if_id_reg uut (
        .clk(clk),
        .rst(rst),
        .stall(stall),
        .flush(flush),
        .if_valid(if_valid),
        .if_pc(if_pc),
        .if_inst(if_inst),
        .id_valid(id_valid),
        .id_pc(id_pc),
        .id_inst(id_inst)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Drive inputs on falling edge; check outputs after rising edge.
    // Case-inequality (!==) also detects X/Z mismatches.
    task check_step;
        input        t_rst;
        input        t_stall;
        input        t_flush;
        input        t_if_valid;
        input [31:0] t_if_pc;
        input [31:0] t_if_inst;
        input        exp_valid;
        input [31:0] exp_pc;
        input [31:0] exp_inst;
        begin
            @(negedge clk);
            rst      = t_rst;
            stall    = t_stall;
            flush    = t_flush;
            if_valid = t_if_valid;
            if_pc    = t_if_pc;
            if_inst  = t_if_inst;

            @(posedge clk);
            #1;  // Allow nonblocking assignments to settle.
            checks = checks + 1;

            if ((id_valid !== exp_valid) ||
                (id_pc    !== exp_pc)    ||
                (id_inst  !== exp_inst)) begin
                errors = errors + 1;
                $display("FAIL [%0d] rst=%b stall=%b flush=%b if_valid=%b", 
                         checks, t_rst, t_stall, t_flush, t_if_valid);
                $display("  actual:   valid=%b pc=%h inst=%h", id_valid, id_pc, id_inst);
                $display("  expected: valid=%b pc=%h inst=%h", exp_valid, exp_pc, exp_inst);
            end else begin
                $display("PASS [%0d] valid=%b pc=%h inst=%h", 
                         checks, id_valid, id_pc, id_inst);
            end
        end
    endtask

    initial begin
        rst      = 1'b1;
        stall    = 1'b0;
        flush    = 1'b0;
        if_valid = 1'b0;
        if_pc    = 32'd0;
        if_inst  = 32'd0;
        checks   = 0;
        errors   = 0;

        // 1: reset clears all three outputs
        check_step(1,0,0,0,32'h0,        32'h0,        0,32'h0,        32'h0);
        // 2: capture an ordinary instruction
        check_step(0,0,0,1,32'h00000100, 32'h02800421, 1,32'h00000100, 32'h02800421);
        // 3-4: stall holds PC, instruction, and valid despite input changes
        check_step(0,1,0,1,32'h00000104, 32'h0010A083, 1,32'h00000100, 32'h02800421);
        check_step(0,1,0,0,32'h00000108, 32'hFFFFFFFF, 1,32'h00000100, 32'h02800421);
        // 5: flush wins over stall
        check_step(0,1,1,1,32'h0000010C, 32'h00110000, 0,32'h0,        32'h0);
        // 6: stalling an empty slot keeps it empty
        check_step(0,1,0,1,32'h00000110, 32'h00100000, 0,32'h0,        32'h0);
        // 7: normal capture resumes
        check_step(0,0,0,1,32'h00000104, 32'h0010A083, 1,32'h00000104, 32'h0010A083);
        // 8: invalid input inserts an empty bubble and clears data
        check_step(0,0,0,0,32'h00000999, 32'hFFFFFFFF, 0,32'h0,        32'h0);
        // 9: flush without stall clears even a valid incoming instruction
        check_step(0,0,1,1,32'h00000108, 32'h00120000, 0,32'h0,        32'h0);
        // 10: capture another instruction
        check_step(0,0,0,1,32'h00000200, 32'h00128000, 1,32'h00000200, 32'h00128000);
        // 11: reset wins over simultaneous flush and stall
        check_step(1,1,1,1,32'h00000204, 32'h00170000, 0,32'h0,        32'h0);
        // 12: check full 32-bit values are stored faithfully
        check_step(0,0,0,1,32'hFFFFFFFC, 32'hFFFFFFFF, 1,32'hFFFFFFFC, 32'hFFFFFFFF);
        // 13: valid=1 even when both data fields are zero
        check_step(0,0,0,1,32'h0,        32'h0,        1,32'h0,        32'h0);
        // 14: valid=0 always produces a cleared bubble
        check_step(0,0,0,0,32'h00000300, 32'h00178000, 0,32'h0,        32'h0);
        // 15: capture then stall across a changed input
        check_step(0,0,0,1,32'h00000300, 32'h00180000, 1,32'h00000300, 32'h00180000);
        check_step(0,1,0,1,32'h00000304, 32'h02800000, 1,32'h00000300, 32'h00180000);
        // 17: flush clears the held instruction
        check_step(0,0,1,0,32'h00000308, 32'h02800000, 0,32'h0,        32'h0);
        // 18: capture after flush
        check_step(0,0,0,1,32'h00000308, 32'h02800000, 1,32'h00000308, 32'h02800000);
        // 19-20: reset and remain invalid after reset release
        check_step(1,0,0,1,32'h0000030C, 32'h00100000, 0,32'h0,        32'h0);
        check_step(0,0,0,0,32'h00000310, 32'h00100000, 0,32'h0,        32'h0);

        $display("----------------------------------------");
        $display("Total checks = %0d, errors = %0d", checks, errors);
        if (errors == 0)
            $display("ALL TESTS PASSED (%0d checks)", checks);
        else
            $display("TESTS FAILED (%0d errors)", errors);
        $finish;
    end

endmodule
