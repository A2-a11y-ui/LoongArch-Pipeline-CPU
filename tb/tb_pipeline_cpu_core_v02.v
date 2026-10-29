`timescale 1ns / 1ps
// V0.2 arithmetic forwarding integration self-check.
// 33 expected register commits from 38 consecutive IF instructions.
// No memory/branch/stall: tests ALU forwarding and same-edge WB-to-ID bypass.
module tb_pipeline_cpu_core_v02;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg if_valid = 1'b0;
    reg [31:0] if_pc = 32'd0, if_inst = 32'd0;
    wire wb_commit_valid, id_unsupported, id_raw_hazard;
    wire [31:0] wb_commit_pc, wb_commit_data;
    wire [4:0] wb_commit_rd;

    pipeline_cpu_core_v02 dut (
        .clk(clk), .rst(rst), .if_valid(if_valid), .if_pc(if_pc),
        .if_inst(if_inst), .wb_commit_valid(wb_commit_valid),
        .wb_commit_pc(wb_commit_pc), .wb_commit_rd(wb_commit_rd),
        .wb_commit_data(wb_commit_data), .id_unsupported(id_unsupported),
        .id_raw_hazard(id_raw_hazard)
    );

    integer errors=0, committed_count=0, expected_count=0;
    integer unsupported_count=0, raw_count=0;
    integer exmem_a_count=0, exmem_b_count=0;
    integer memwb_a_count=0, memwb_b_count=0;
    integer wb_id_bypass_count=0, simultaneous_count=0;
    reg [31:0] exp_pc [0:63];
    reg [4:0]  exp_rd [0:63];
    reg [31:0] exp_data [0:63];
    reg [31:0] next_pc = 32'h00001000;

    function [31:0] inst_r;
        input [31:0] op;
        input [4:0] rd, rj, rk;
        begin inst_r = op | {17'd0, rk, rj, rd}; end
    endfunction
    function [31:0] inst_i;
        input [31:0] op;
        input [4:0] rd, rj;
        input [11:0] imm;
        begin inst_i = op | {10'd0, imm, rj, rd}; end
    endfunction
    task send_write;
        input [31:0] inst, data;
        input [4:0] rd;
        begin
            @(negedge clk);
            exp_pc[expected_count] = next_pc;
            exp_rd[expected_count] = rd;
            exp_data[expected_count] = data;
            expected_count = expected_count + 1;
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
    task bubble;
        begin
            @(negedge clk);
            if_valid=1'b0; if_pc=next_pc; if_inst=32'd0;
        end
    endtask
    task drain;
        input integer n;
        integer j;
        begin for (j=0;j<n;j=j+1) bubble; end
    endtask

    // Observe the same transaction consumed by the synchronous regfile
    // at this rising edge, BEFORE nonblocking pipeline updates settle.
    always @(posedge clk) begin
        if (!rst) begin
            if (id_unsupported) unsupported_count = unsupported_count + 1;
            if (id_raw_hazard) raw_count = raw_count + 1;
            if (dut.id_rs1_wb_bypass_hit || dut.id_rs2_wb_bypass_hit)
                wb_id_bypass_count = wb_id_bypass_count + 1;
            if (dut.ex_valid) begin
                if (dut.forward_a == 2'b10) exmem_a_count = exmem_a_count + 1;
                if (dut.forward_b == 2'b10) exmem_b_count = exmem_b_count + 1;
                if (dut.forward_a == 2'b01) memwb_a_count = memwb_a_count + 1;
                if (dut.forward_b == 2'b01) memwb_b_count = memwb_b_count + 1;
                if ((dut.forward_a == 2'b10 && dut.forward_b == 2'b01) ||
                    (dut.forward_a == 2'b01 && dut.forward_b == 2'b10))
                    simultaneous_count = simultaneous_count + 1;
                if (dut.wait_a || dut.wait_b) begin
                    errors = errors + 1;
                    $display("FAIL unexpected forwarding wait at EX PC=%h", dut.ex_pc);
                end
            end
            if (wb_commit_valid) begin
                if (committed_count >= expected_count) begin
                    errors = errors + 1;
                    $display("FAIL extra commit PC=%h rd=%0d data=%h",
                             wb_commit_pc,wb_commit_rd,wb_commit_data);
                end else if ((wb_commit_pc !== exp_pc[committed_count]) ||
                             (wb_commit_rd !== exp_rd[committed_count]) ||
                             (wb_commit_data !== exp_data[committed_count])) begin
                    errors = errors + 1;
                    $display("FAIL commit[%0d]: got PC=%h rd=%0d data=%h; expected PC=%h rd=%0d data=%h",
                             committed_count, wb_commit_pc, wb_commit_rd, wb_commit_data,
                             exp_pc[committed_count], exp_rd[committed_count], exp_data[committed_count]);
                end
                committed_count = committed_count + 1;
            end
        end
    end

    initial begin
        repeat (2) @(negedge clk);
        rst=1'b0;
        // Stream instructions every cycle without intentionally inserted bubbles.
        send_write(inst_i(32'h02800000,5'd1,5'd0,12'h005),32'h00000005,5'd1); // ADDI r1 = 5
        send_write(inst_i(32'h02800000,5'd2,5'd0,12'h008),32'h00000008,5'd2); // ADDI r2 = 8
        send_write(inst_r(32'h00100000,5'd3,5'd1,5'd2),32'h0000000d,5'd3); // ADD r3 = r1+r2 (dual forwarding)
        send_write(inst_r(32'h00100000,5'd4,5'd3,5'd1),32'h00000012,5'd4); // ADD r4 = r3+r1
        send_write(inst_r(32'h00110000,5'd5,5'd4,5'd2),32'h0000000a,5'd5); // SUB r5 = r4-r2
        send_write(inst_i(32'h02800000,5'd6,5'd5,12'hffe),32'h00000008,5'd6); // ADDI r6 = r5-2
        send_write(inst_r(32'h00148000,5'd7,5'd6,5'd3),32'h00000008,5'd7); // AND r7 = r6&r3
        send_write(inst_r(32'h00150000,5'd8,5'd7,5'd1),32'h0000000d,5'd8); // OR r8 = r7|r1
        send_write(inst_r(32'h00158000,5'd9,5'd8,5'd2),32'h00000005,5'd9); // XOR r9 = r8^r2
        send_write(inst_i(32'h02800000,5'd10,5'd0,12'h001),32'h00000001,5'd10); // ADDI r10 = 1
        send_write(inst_i(32'h02800000,5'd10,5'd10,12'h002),32'h00000003,5'd10); // ADDI r10 = r10+2 (same rd)
        send_write(inst_i(32'h02800000,5'd10,5'd10,12'h003),32'h00000006,5'd10); // ADDI r10 = r10+3 (newer priority)
        send_write(inst_r(32'h00100000,5'd11,5'd10,5'd1),32'h0000000b,5'd11); // ADD r11 = r10+r1 (priority)
        send_no_write(inst_i(32'h02800000,5'd0,5'd0,12'h04d)); // ADDI r0 ignored
        send_write(inst_i(32'h02800000,5'd12,5'd0,12'h009),32'h00000009,5'd12); // ADDI r12 = r0+9 (r0 protection)
        send_write(inst_r(32'h00100000,5'd13,5'd11,5'd12),32'h00000014,5'd13); // ADD r13 = r11+r12
        send_write(inst_r(32'h00170000,5'd14,5'd13,5'd1),32'h00000280,5'd14); // SLL r14 = r13 << r1
        send_write(inst_r(32'h00178000,5'd15,5'd14,5'd1),32'h00000014,5'd15); // SRL r15 = r14 >> r1
        send_write(inst_r(32'h00110000,5'd16,5'd15,5'd13),32'h00000000,5'd16); // SUB r16 = r15-r13
        send_write(inst_r(32'h00140000,5'd17,5'd1,5'd2),32'hfffffff2,5'd17); // NOR r17 = ~(r1|r2)
        send_write(inst_r(32'h00120000,5'd18,5'd17,5'd2),32'h00000001,5'd18); // SLT r18 = signed(r17)<r2
        send_write(inst_r(32'h00128000,5'd19,5'd17,5'd2),32'h00000000,5'd19); // SLTU r19 = unsigned(r17)<r2
        send_write(inst_i(32'h02800000,5'd20,5'd0,12'h028),32'h00000028,5'd20); // ADDI r20 = 40
        send_write(inst_i(32'h02800000,5'd21,5'd0,12'h001),32'h00000001,5'd21); // ADDI r21 = 1
        send_write(inst_i(32'h02800000,5'd22,5'd0,12'h002),32'h00000002,5'd22); // ADDI r22 = 2
        send_write(inst_r(32'h00100000,5'd23,5'd20,5'd21),32'h00000029,5'd23); // ADD r23 = r20+r21 (WB->ID)
        send_write(inst_r(32'h00100000,5'd24,5'd23,5'd22),32'h0000002b,5'd24); // ADD r24 = r23+r22
        send_no_write(32'hffffffff); // illegal
        send_no_write(32'h28800009); // LD.W unsupported
        send_no_write(32'h29800009); // ST.W unsupported
        send_no_write(32'h50000000); // B unsupported
        send_write(inst_r(32'h00100000,5'd25,5'd24,5'd10),32'h00000031,5'd25); // ADD r25 = r24+r10
        send_write(inst_r(32'h00100000,5'd26,5'd25,5'd23),32'h0000005a,5'd26); // ADD r26 = r25+r23
        send_write(inst_r(32'h00110000,5'd27,5'd26,5'd25),32'h00000029,5'd27); // SUB r27 = r26-r25
        send_write(inst_r(32'h00148000,5'd28,5'd27,5'd1),32'h00000001,5'd28); // AND r28 = r27&r1
        send_write(inst_r(32'h00150000,5'd29,5'd28,5'd2),32'h00000009,5'd29); // OR r29 = r28|r2
        send_write(inst_r(32'h00158000,5'd30,5'd29,5'd1),32'h0000000c,5'd30); // XOR r30 = r29^r1
        send_write(inst_i(32'h02800000,5'd31,5'd30,12'hffc),32'h00000008,5'd31); // ADDI r31 = r30-4
        drain(10);
        if (committed_count != 33 || expected_count != 33) begin
            errors=errors+1;
            $display("FAIL commits: got=%0d expected=%0d",committed_count,expected_count);
        end
        if (unsupported_count != 4) begin
            errors=errors+1;
            $display("FAIL unsupported: got=%0d expected=4",unsupported_count);
        end
        if (raw_count==0 || exmem_a_count==0 || exmem_b_count==0 ||
            memwb_a_count==0 || memwb_b_count==0 ||
            wb_id_bypass_count==0 || simultaneous_count==0) begin
            errors=errors+1;
            $display("FAIL insufficient forwarding coverage: RAW=%0d EXMEM_A=%0d EXMEM_B=%0d MEMWB_A=%0d MEMWB_B=%0d WB_ID=%0d BOTH=%0d",
                raw_count,exmem_a_count,exmem_b_count,memwb_a_count,memwb_b_count,wb_id_bypass_count,simultaneous_count);
        end
        if (dut.u_regfile.regs[0] !== 32'd0 ||
            dut.u_regfile.regs[3] !== 32'd13 ||
            dut.u_regfile.regs[10] !== 32'd6 ||
            dut.u_regfile.regs[11] !== 32'd11 ||
            dut.u_regfile.regs[23] !== 32'd41 ||
            dut.u_regfile.regs[24] !== 32'd43 ||
            dut.u_regfile.regs[26] !== 32'd90 ||
            dut.u_regfile.regs[31] !== 32'd8) begin
            errors=errors+1;
            $display("FAIL final register-file contents");
        end
        $display("RESULT V0.2: commits=%0d/33 unsupported=%0d raw=%0d errors=%0d",
                 committed_count,unsupported_count,raw_count,errors);
        $display("COVERAGE: EXMEM_A=%0d EXMEM_B=%0d MEMWB_A=%0d MEMWB_B=%0d WB_ID=%0d BOTH=%0d",
                 exmem_a_count,exmem_b_count,memwb_a_count,memwb_b_count,
                 wb_id_bypass_count,simultaneous_count);
        if (errors==0) $display("ALL TESTS PASSED (pipeline CPU V0.2 arithmetic forwarding)");
        else           $display("TESTS FAILED (pipeline CPU V0.2)");
        $finish;
    end
    // A bounded watchdog prevents a silent hanging simulation.
    initial begin
        #2000;
        $display("FAIL WATCHDOG timeout at 2000 ns");
        $finish;
    end
endmodule
