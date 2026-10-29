`timescale 1ns / 1ps
// Self-checking, arithmetic-only, NON-DEPENDENT instruction-stream test.
module tb_pipeline_cpu_core_v01;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg if_valid = 1'b0;
    reg [31:0] if_pc = 32'd0;
    reg [31:0] if_inst = 32'd0;
    wire wb_commit_valid, id_unsupported, id_raw_hazard;
    wire [31:0] wb_commit_pc, wb_commit_data;
    wire [4:0] wb_commit_rd;

    pipeline_cpu_core_v01 dut (
        .clk(clk), .rst(rst), .if_valid(if_valid), .if_pc(if_pc),
        .if_inst(if_inst), .wb_commit_valid(wb_commit_valid),
        .wb_commit_pc(wb_commit_pc), .wb_commit_rd(wb_commit_rd),
        .wb_commit_data(wb_commit_data), .id_unsupported(id_unsupported),
        .id_raw_hazard(id_raw_hazard)
    );

    integer errors=0, expected_count=0, committed_count=0;
    integer unsupported_count=0, hazard_count=0;
    reg [31:0] exp_pc [0:63];
    reg [4:0]  exp_rd [0:63];
    reg [31:0] exp_data [0:63];
    reg [31:0] next_pc = 32'h00001000;

    // Testbench instruction encoders, aligned with the supplied decoder.v.
    function [31:0] inst_r;
        input [31:0] op;
        input [4:0] rd, rj, rk;
        begin inst_r = op | {17'd0,rk,rj,rd}; end
    endfunction
    function [31:0] inst_i;
        input [31:0] op;
        input [4:0] rd, rj;
        input [11:0] imm;
        begin inst_i = op | {10'd0,imm,rj,rd}; end
    endfunction
    function [31:0] inst_u;
        input [31:0] op;
        input [4:0] rd;
        input [19:0] imm20;
        begin inst_u = op | {7'd0,imm20,rd}; end
    endfunction

    // Scoreboard entries are inserted BEFORE the instruction is issued.
    task expect_write;
        input [31:0] pc, data;
        input [4:0] rd;
        begin
            exp_pc[expected_count] = pc;
            exp_rd[expected_count] = rd;
            exp_data[expected_count] = data;
            expected_count = expected_count + 1;
        end
    endtask
    task send_write;
        input [31:0] inst, data;
        input [4:0] rd;
        begin
            @(negedge clk);
            expect_write(next_pc, data, rd);
            if_valid=1'b1; if_pc=next_pc; if_inst=inst;
            next_pc=next_pc+32'd4;
        end
    endtask
    task send_no_write;
        input [31:0] inst;
        begin
            @(negedge clk);
            if_valid=1'b1; if_pc=next_pc; if_inst=inst;
            next_pc=next_pc+32'd4;
        end
    endtask
    task send_bubble;
        begin
            @(negedge clk);
            if_valid=1'b0; if_inst=32'd0; if_pc=next_pc;
        end
    endtask
    task wait_bubbles;
        input integer n;
        integer j;
        begin for (j=0;j<n;j=j+1) send_bubble(); end
    endtask

    // Sample registered WB BEFORE the edge updates its contents: this is
    // exactly the transaction the regfile will consume on this edge.
    always @(posedge clk) begin
        if (!rst) begin
            if (id_unsupported) unsupported_count = unsupported_count + 1;
            if (id_raw_hazard) begin
                hazard_count = hazard_count + 1;
                errors = errors + 1;
                $display("FAIL RAW hazard detected at ID PC=%h", dut.id_pc);
            end
            if (wb_commit_valid) begin
                if (committed_count >= expected_count) begin
                    errors = errors + 1;
                    $display("FAIL unexpected WB: PC=%h rd=%d data=%h",
                             wb_commit_pc, wb_commit_rd, wb_commit_data);
                end else if ((wb_commit_pc !== exp_pc[committed_count]) ||
                             (wb_commit_rd !== exp_rd[committed_count]) ||
                             (wb_commit_data !== exp_data[committed_count])) begin
                    errors = errors + 1;
                    $display("FAIL WB[%0d] got PC=%h rd=%0d data=%h; expected PC=%h rd=%0d data=%h",
                        committed_count, wb_commit_pc, wb_commit_rd, wb_commit_data,
                        exp_pc[committed_count], exp_rd[committed_count],
                        exp_data[committed_count]);
                end
                committed_count = committed_count + 1;
            end
        end
    end

    initial begin
        // Reset is synchronous, so hold it across two rising edges.
        repeat (2) @(negedge clk);
        rst=1'b0;

        // First group only reads r0: no RAW hazards.
        send_write(inst_i(32'h02800000,5'd1,5'd0,12'd10), 32'd10,5'd1);       // ADDI.W r1, r0, 10
        send_write(inst_i(32'h02800000,5'd2,5'd0,12'd20), 32'd20,5'd2);       // ADDI.W r2, r0, 20
        send_write(inst_i(32'h02800000,5'd3,5'd0,12'hffd),32'hfffffffd,5'd3); // ADDI.W r3,r0,-3
        send_write(inst_i(32'h02800000,5'd4,5'd0,12'd1),  32'd1,5'd4);
        send_write(inst_i(32'h03800000,5'd5,5'd0,12'h0aa),32'h000000aa,5'd5); // ORI
        send_write(inst_i(32'h03c00000,5'd6,5'd0,12'h05a),32'h0000005a,5'd6); // XORI
        send_write(inst_i(32'h03400000,5'd7,5'd0,12'h0ff),32'd0,5'd7);         // ANDI
        send_write(inst_u(32'h14000000,5'd8,20'h12345),32'h12345000,5'd8);    // LU12I.W
        // Zero-register write should not commit.
        send_no_write(inst_i(32'h02800000,5'd0,5'd0,12'd77));
        // Invalid, load, store, and branch must be visible unsupported bubbles.
        send_no_write(32'hffffffff);
        send_no_write(inst_i(32'h28800000,5'd9,5'd0,12'd0)); // LD.W (unsupported)
        send_no_write(inst_i(32'h29800000,5'd9,5'd0,12'd0)); // ST.W (unsupported)
        send_no_write(32'h50000000); // B (unsupported)
        wait_bubbles(6);

        // Second group reads the now committed first group results.
        // Results are independent of one another to avoid EX-stage hazards.
        send_write(inst_r(32'h00100000,5'd20,5'd1,5'd2),32'd30,5'd20);   // ADD.W
        send_write(inst_r(32'h00110000,5'd21,5'd2,5'd1),32'd10,5'd21);   // SUB.W
        send_write(inst_r(32'h00148000,5'd22,5'd1,5'd2),32'd0,5'd22);    // AND
        send_write(inst_r(32'h00150000,5'd23,5'd1,5'd2),32'd30,5'd23);   // OR
        send_write(inst_r(32'h00158000,5'd24,5'd1,5'd2),32'd30,5'd24);   // XOR
        send_write(inst_r(32'h00120000,5'd25,5'd3,5'd1),32'd1,5'd25);    // SLT signed
        send_write(inst_r(32'h00128000,5'd26,5'd3,5'd1),32'd0,5'd26);    // SLTU unsigned
        send_write(inst_r(32'h00170000,5'd27,5'd4,5'd1),32'd1024,5'd27); // SLL.W 1<<10
        send_write(inst_r(32'h00178000,5'd28,5'd2,5'd4),32'd10,5'd28);   // SRL.W 20>>1
        send_write(inst_r(32'h00180000,5'd29,5'd3,5'd4),32'hfffffffe,5'd29); // SRA.W -3>>1
        send_write(inst_r(32'h00140000,5'd30,5'd1,5'd2),~32'd30,5'd30); // NOR
        wait_bubbles(9);

        if (committed_count != expected_count) begin
            errors=errors+1;
            $display("FAIL commits: expected=%0d actual=%0d",expected_count,committed_count);
        end
        if (unsupported_count != 4) begin
            errors=errors+1;
            $display("FAIL unsupported count: expected 4, got %0d",unsupported_count);
        end
        if (dut.u_regfile.regs[0] !== 32'd0 ||
            dut.u_regfile.regs[1] !== 32'd10 ||
            dut.u_regfile.regs[2] !== 32'd20 ||
            dut.u_regfile.regs[20] !== 32'd30 ||
            dut.u_regfile.regs[29] !== 32'hfffffffe) begin
            errors=errors+1;
            $display("FAIL final register-file state");
        end
        $display("RESULT: commits=%0d/%0d, unsupported=%0d, hazards=%0d, errors=%0d",
                 committed_count,expected_count,unsupported_count,hazard_count,errors);
        if (errors==0) $display("ALL TESTS PASSED (pipeline CPU V0.1 arithmetic-only)");
        else           $display("TESTS FAILED");
        $finish;
    end
endmodule
