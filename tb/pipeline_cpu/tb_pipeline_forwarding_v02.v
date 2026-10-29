`timescale 1ns / 1ps
// V0.2 integrated-CPU forwarding regression; Vivado 2019.1, Verilog-2001.
// Uses real 32-bit LoongArch encodings and an independent in-order WB scoreboard.
// PRECONDITION: team A's V0.2 core retains V0.1 external IF/WB port protocol.
// Do not run against V0.1: that core intentionally has NO forwarding.
// Override macro CPU_V02_TOP below if A chooses a different module name.
`ifndef CPU_V02_TOP
`define CPU_V02_TOP pipeline_cpu_core_v02
`endif
module tb_pipeline_forwarding_v02;
    parameter MEM_FILE =
        "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/forwarding_v02.mem";
    localparam [31:0] START_PC = 32'h00001000;
    localparam integer ROM_WORDS = 33;
    localparam integer EXPECTED_COMMITS = 32;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg if_valid = 1'b0;
    reg [31:0] if_pc = 32'd0;
    reg [31:0] if_inst = 32'd0;
    wire wb_commit_valid;
    wire [31:0] wb_commit_pc, wb_commit_data;
    wire [4:0] wb_commit_rd;

    // Only use the seven proven V0.1 external IF/WB ports.
    // If V0.2 adds if_ready/backpressure, update this driver to honor it.
    `CPU_V02_TOP dut (
        .clk(clk), .rst(rst), .if_valid(if_valid),
        .if_pc(if_pc), .if_inst(if_inst),
        .wb_commit_valid(wb_commit_valid),
        .wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd),
        .wb_commit_data(wb_commit_data)
    );

    reg [31:0] rom [0:ROM_WORDS-1];
    reg [31:0] expected_pc [0:EXPECTED_COMMITS-1];
    reg [4:0] expected_rd [0:EXPECTED_COMMITS-1];
    reg [31:0] expected_data [0:EXPECTED_COMMITS-1];
    integer expected_count = 0;
    integer commit_count = 0;
    integer errors = 0;
    integer i;
    reg completed = 1'b0;

    task expect_wb;
        input integer word_index;
        input [4:0] rd;
        input [31:0] data;
        begin
            expected_pc[expected_count] = START_PC + word_index * 4;
            expected_rd[expected_count] = rd;
            expected_data[expected_count] = data;
            expected_count = expected_count + 1;
        end
    endtask

    // Sample pre-edge WB: this is the record consumed by synchronous RegFile.
    always @(posedge clk) begin
        if (!rst && !completed && wb_commit_valid === 1'b1) begin
            if (commit_count >= EXPECTED_COMMITS) begin
                errors = errors + 1;
                $display("FAIL EXTRA WB @%0t: PC=%h rd=%0d data=%h",
                         $time, wb_commit_pc, wb_commit_rd, wb_commit_data);
            end else if (wb_commit_pc !== expected_pc[commit_count] ||
                         wb_commit_rd !== expected_rd[commit_count] ||
                         wb_commit_data !== expected_data[commit_count]) begin
                errors = errors + 1;
                $display("FAIL WB[%0d] @%0t: PC=%h rd=%0d data=%h; EXPECT PC=%h rd=%0d data=%h",
                         commit_count, $time, wb_commit_pc, wb_commit_rd, wb_commit_data,
                         expected_pc[commit_count], expected_rd[commit_count],
                         expected_data[commit_count]);
            end else begin
                $display("PASS WB[%0d] PC=%h r%0d=%h", commit_count,
                         wb_commit_pc, wb_commit_rd, wb_commit_data);
            end
            if (wb_commit_rd === 5'd0) begin
                errors = errors + 1;
                $display("FAIL r0 WRITE @%0t", $time);
            end
            commit_count = commit_count + 1;
        end
    end

    // Driving instructions only at falling edges avoids edge races.
    // No bubbles between RAW dependencies: forwarding is actually required.
    task drive_word;
        input integer word_index;
        begin
            @(negedge clk);
            if_valid = 1'b1;
            if_pc = START_PC + word_index * 4;
            if_inst = rom[word_index];
        end
    endtask

    task drive_bubble;
        begin
            @(negedge clk);
            if_valid = 1'b0;
            if_pc = 32'd0;
            if_inst = 32'd0;
        end
    endtask

    initial begin
        // The program is fixed for this independent regression. Fail fast if
        // $readmemh cannot find the file or loads the wrong old program.
        for (i=0;i<ROM_WORDS;i=i+1) rom[i]=32'hxxxxxxxx;
        $readmemh(MEM_FILE, rom);
        if (rom[0] !== 32'h02802801 ||
            rom[ROM_WORDS-1] !== 32'h0280001d) begin
            $display("TESTS FAILED: missing or wrong forwarding_v02.mem");
            $finish;
        end

        // Independent golden outcomes, not inferred from DUT outputs.
        expect_wb(0, 5'd1, 32'h0000000a); // ADDI.W r1, r0, 10
        expect_wb(1, 5'd2, 32'h00000014); // ADD.W r2, r1, r1 (EX/MEM both)
        expect_wb(2, 5'd3, 32'h0000000a); // SUB.W r3, r2, r1 (mixed forwarding)
        expect_wb(3, 5'd4, 32'h0000001e); // ADD.W r4, r3, r2 (continuous RAW)
        expect_wb(4, 5'd5, 32'h0000001f); // ADDI.W r5, r4, 1 (imm A forward)
        expect_wb(5, 5'd6, 32'h0000003e); // ADD.W r6, r5, r5 (both sources)
        expect_wb(6, 5'd7, 32'h00000003); // ADDI.W r7, r0, 3
        expect_wb(7, 5'd8, 32'h00000004); // ADDI.W r8, r0, 4
        expect_wb(8, 5'd9, 32'h00000007); // ADD.W r9, r7, r8 (WB + EXMEM)
        expect_wb(9, 5'd10, 32'h00000001); // ADDI.W r10, r0, 1
        expect_wb(10, 5'd10, 32'h00000003); // ADDI.W r10, r10, 2
        expect_wb(11, 5'd11, 32'h00000006); // ADD.W r11, r10, r10 (latest wins)
        expect_wb(12, 5'd12, 32'h00000064); // ADDI.W r12, r0, 100
        expect_wb(13, 5'd12, 32'h00000065); // ADDI.W r12, r12, 1
        expect_wb(14, 5'd12, 32'h00000067); // ADDI.W r12, r12, 2
        expect_wb(15, 5'd13, 32'h00000067); // ADD.W r13, r12, r0
        expect_wb(17, 5'd14, 32'h00000067); // ADD.W r14, r0, r12 (r0 stays 0)
        expect_wb(18, 5'd15, 32'hfffffff8); // ADDI.W r15, r0, -8
        expect_wb(19, 5'd16, 32'hffffffff); // SRA.W r16, r15, r7 (-8 >> 3)
        expect_wb(20, 5'd17, 32'h00000001); // SLT r17, r15, r7 (signed)
        expect_wb(21, 5'd18, 32'h00000000); // SLTU r18, r15, r7 (unsigned)
        expect_wb(22, 5'd19, 32'h00000000); // AND r19, r1, r2
        expect_wb(23, 5'd20, 32'h0000001e); // OR r20, r1, r2
        expect_wb(24, 5'd21, 32'h0000001e); // XOR r21, r1, r2
        expect_wb(25, 5'd22, 32'hffffffe1); // NOR r22, r1, r2
        expect_wb(26, 5'd23, 32'h00000030); // SLL.W r23, r7, r8 (3 << 4)
        expect_wb(27, 5'd24, 32'h00000006); // SRL.W r24, r23, r7 (48 >> 3)
        expect_wb(28, 5'd25, 32'h00000003); // SUB.W r25, r24, r7
        expect_wb(29, 5'd26, 32'h0000006a); // ADD.W r26, r25, r14
        expect_wb(30, 5'd27, 32'h00000064); // ADDI.W r27, r26, -6
        expect_wb(31, 5'd28, 32'h000000cb); // ADD.W r28, r27, r13
        expect_wb(32, 5'd29, 32'h00000000); // ADDI.W r29, r0, 0 (valid 0 result)
        if (expected_count != EXPECTED_COMMITS) begin
            $display("TESTS FAILED: scoreboard entries=%0d", expected_count);
            $finish;
        end
        $display("V0.2 INTEGRATED FORWARDING REGRESSION START");
        $display("ROM=%0d words; expected commits=%0d", ROM_WORDS, EXPECTED_COMMITS);
        // Hold synchronous reset over multiple rising edges.
        repeat (3) @(negedge clk);
        rst=1'b0;

        for (i=0;i<ROM_WORDS;i=i+1) drive_word(i);
        // Explicitly stop fetching; allow pipeline to drain without supplying
        // an accidental extra instruction from ROM.
        repeat (14) drive_bubble();
        @(negedge clk);
        completed=1'b1;
        if (commit_count != EXPECTED_COMMITS) begin
            errors=errors+1;
            $display("FAIL commit_count expected=%0d got=%0d", EXPECTED_COMMITS, commit_count);
        end
        $display("-------------------------------------------");
        $display("CPU V0.2 FORWARDING INTEGRATION REGRESSION");
        $display("instruction_words=%0d commits=%0d/%0d errors=%0d",
                 ROM_WORDS,commit_count,EXPECTED_COMMITS,errors);
        if (errors==0 && commit_count==EXPECTED_COMMITS)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED");
        $finish;
    end

    // Guard against a genuine hang without a false timeout on a second run.
    initial begin
        #20000;
        if (!completed) begin
            $display("TESTS FAILED: FATAL TIMEOUT (no normal finish)");
            $finish;
        end
    end
endmodule
