`timescale 1ns / 1ps
// Independent V0.1 CPU arithmetic writeback regression, Verilog-2001.
// Uses real instruction encodings from rtl/common/decoder.v.
// Five invalid input cycles between nonzero instruction words: no RAW hazard.
// This testbench is not yet confirmed with team A's unpublished V0.1 top RTL.
module tb_pipeline_cpu_basic;
    localparam integer PROGRAM_WORDS = 138;
    localparam integer EXPECTED_COMMITS = 21;
    localparam [31:0] BASE_PC = 32'h00001000;
    localparam integer MAX_DRAIN_CYCLES = 24;

    reg clk, rst;
    reg if_valid;
    reg [31:0] if_pc, if_inst;
    wire wb_commit_valid;
    wire [31:0] wb_commit_pc;
    wire [4:0]  wb_commit_rd;
    wire [31:0] wb_commit_data;

    reg [31:0] program [0:PROGRAM_WORDS-1];
    reg [31:0] exp_pc [0:EXPECTED_COMMITS-1];
    reg [4:0]  exp_rd [0:EXPECTED_COMMITS-1];
    reg [31:0] exp_data [0:EXPECTED_COMMITS-1];
    reg [8*512-1:0] program_path;
    integer fd, i, commits, errors, checks, cycles;
    reg checking_enabled;

    pipeline_cpu_core_v01 dut (
        .clk(clk), .rst(rst),
        .if_valid(if_valid), .if_pc(if_pc), .if_inst(if_inst),
        .wb_commit_valid(wb_commit_valid),
        .wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd),
        .wb_commit_data(wb_commit_data)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Monitor one posedge after NBAs. It must not share the drive edge.
    always @(posedge clk) begin
        #1;
        if (checking_enabled && !rst) begin
            checks = checks + 1;
            if (wb_commit_valid !== 1'b0 && wb_commit_valid !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL: wb_commit_valid is X/Z at %0t", $time);
            end
            if (wb_commit_valid === 1'b1) begin
                if (wb_commit_rd === 5'd0) begin
                    errors = errors + 1;
                    $display("FAIL: attempted r0 commit at %0t", $time);
                end
                if (commits >= EXPECTED_COMMITS) begin
                    errors = errors + 1;
                    $display("FAIL: unexpected extra commit PC=%h rd=%0d data=%h",
                             wb_commit_pc, wb_commit_rd, wb_commit_data);
                end else begin
                    checks = checks + 3;
                    if (wb_commit_pc !== exp_pc[commits]) begin
                        errors = errors + 1;
                        $display("FAIL commit[%0d] PC got=%h expected=%h",
                                 commits, wb_commit_pc, exp_pc[commits]);
                    end
                    if (wb_commit_rd !== exp_rd[commits]) begin
                        errors = errors + 1;
                        $display("FAIL commit[%0d] rd got=%0d expected=%0d",
                                 commits, wb_commit_rd, exp_rd[commits]);
                    end
                    if (wb_commit_data !== exp_data[commits]) begin
                        errors = errors + 1;
                        $display("FAIL commit[%0d] data got=%h expected=%h",
                                 commits, wb_commit_data, exp_data[commits]);
                    end
                    if (wb_commit_pc === exp_pc[commits] &&
                        wb_commit_rd === exp_rd[commits] &&
                        wb_commit_data === exp_data[commits])
                        $display("PASS commit[%0d]: PC=%h r%0d <- %h",
                                 commits, wb_commit_pc, wb_commit_rd, wb_commit_data);
                end
                commits = commits + 1;
            end
        end
    end

    initial begin
        rst = 1'b1;
        if_valid = 1'b0;
        if_pc = BASE_PC;
        if_inst = 32'b0;
        checks = 0;
        commits = 0;
        errors = 0;
        checking_enabled = 1'b0;

        // Use +PROGRAM=... if needed. Automatic fallback for Vivado XSIM
        // working directory and the user's existing Windows project path.
        if (!$value$plusargs("PROGRAM=%s", program_path)) begin
            program_path = "tb/pipeline_cpu/programs/arithmetic_basic.mem";
            fd = $fopen(program_path, "r");
            if (fd == 0) begin
                program_path = "../../../../../tb/pipeline_cpu/programs/arithmetic_basic.mem";
                fd = $fopen(program_path, "r");
            end
            if (fd == 0) begin
                program_path = "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/arithmetic_basic.mem";
                fd = $fopen(program_path, "r");
            end
        end else begin
            fd = $fopen(program_path, "r");
        end
        if (fd == 0) begin
            $display("FAIL: cannot open arithmetic_basic.mem; use +PROGRAM=full/path");
            $fatal(1, "Program file is missing");
        end
        $fclose(fd);
        for (i = 0; i < PROGRAM_WORDS; i = i+1)
            program[i] = 32'd0;
        $display("Loading test program from %0s", program_path);
        $readmemh(program_path, program);

        // Expected results are hard-coded independently of the memory file;
        // accidental corruption of .mem must not change the oracle.
        exp_pc[0]   = 32'h00001000; exp_rd[0] = 5'd1; exp_data[0] = 32'h00000005; // addi, program word 0
        exp_pc[1]   = 32'h00001018; exp_rd[1] = 5'd2; exp_data[1] = 32'h00000008; // addi, program word 6
        exp_pc[2]   = 32'h00001030; exp_rd[2] = 5'd3; exp_data[2] = 32'hFFFFFFFC; // addi, program word 12
        exp_pc[3]   = 32'h00001048; exp_rd[3] = 5'd4; exp_data[3] = 32'h00000001; // addi, program word 18
        exp_pc[4]   = 32'h00001060; exp_rd[4] = 5'd5; exp_data[4] = 32'h0000001F; // addi, program word 24
        exp_pc[5]   = 32'h00001078; exp_rd[5] = 5'd10; exp_data[5] = 32'h0000000D; // add, program word 30
        exp_pc[6]   = 32'h00001090; exp_rd[6] = 5'd11; exp_data[6] = 32'h00000003; // sub, program word 36
        exp_pc[7]   = 32'h000010A8; exp_rd[7] = 5'd12; exp_data[7] = 32'h00000000; // and, program word 42
        exp_pc[8]   = 32'h000010C0; exp_rd[8] = 5'd13; exp_data[8] = 32'h0000000D; // or, program word 48
        exp_pc[9]   = 32'h000010D8; exp_rd[9] = 5'd14; exp_data[9] = 32'h0000000D; // xor, program word 54
        exp_pc[10]   = 32'h000010F0; exp_rd[10] = 5'd15; exp_data[10] = 32'hFFFFFFF2; // nor, program word 60
        exp_pc[11]   = 32'h00001108; exp_rd[11] = 5'd16; exp_data[11] = 32'h0000000A; // sll, program word 66
        exp_pc[12]   = 32'h00001120; exp_rd[12] = 5'd17; exp_data[12] = 32'h0000000F; // srl, program word 72
        exp_pc[13]   = 32'h00001138; exp_rd[13] = 5'd18; exp_data[13] = 32'hFFFFFFFE; // sra, program word 78
        exp_pc[14]   = 32'h00001150; exp_rd[14] = 5'd19; exp_data[14] = 32'h00000003; // addi, program word 84
        exp_pc[15]   = 32'h00001168; exp_rd[15] = 5'd20; exp_data[15] = 32'h0000000F; // andi, program word 90
        exp_pc[16]   = 32'h00001180; exp_rd[16] = 5'd21; exp_data[16] = 32'h00000015; // ori, program word 96
        exp_pc[17]   = 32'h00001198; exp_rd[17] = 5'd22; exp_data[17] = 32'h0000000B; // xori, program word 102
        exp_pc[18]   = 32'h000011B0; exp_rd[18] = 5'd23; exp_data[18] = 32'h00000014; // slli, program word 108
        exp_pc[19]   = 32'h000011C8; exp_rd[19] = 5'd24; exp_data[19] = 32'h00000003; // srli, program word 114
        exp_pc[20]   = 32'h000011E0; exp_rd[20] = 5'd25; exp_data[20] = 32'hFFFFFFFE; // srai, program word 120

        repeat(3) @(negedge clk);
        rst = 1'b0;
        checking_enabled = 1'b1;

        // Drive on falling edge; CPU consumes external IF at next rising edge.
        // Invalid IF slots are actual bubbles and do not execute an opcode.
        for (i = 0; i < PROGRAM_WORDS; i = i+1) begin
            @(negedge clk);
            if_pc = BASE_PC + i * 4;
            if_inst = program[i];
            if_valid = (program[i] !== 32'd0);
        end

        @(negedge clk);
        if_valid = 1'b0;
        if_inst = 32'b0;
        for (cycles = 0; cycles < MAX_DRAIN_CYCLES; cycles = cycles+1)
            @(negedge clk);
        #2;
        checks = checks + 1;
        if (commits != EXPECTED_COMMITS) begin
            errors = errors + 1;
            $display("FAIL: commit count got=%0d expected=%0d",
                     commits, EXPECTED_COMMITS);
        end
        $display("==========================================");
        $display("CPU V0.1 INDEPENDENT ARITHMETIC REGRESSION");
        $display("Expected commits = %0d, actual commits = %0d",
                 EXPECTED_COMMITS, commits);
        $display("Checks = %0d, errors = %0d", checks, errors);
        if (errors == 0 && commits == EXPECTED_COMMITS)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED");
        $finish;
    end

    initial begin
        #30000;
        $fatal(1, "TIMEOUT: CPU V0.1 arithmetic regression");
    end
endmodule
