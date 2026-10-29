`timescale 1ns / 1ps
// Independent arithmetic-only regression for A's pipeline_cpu_core_v01
// Verified against Git commit 13e02c2. Vivado 2019.1, Verilog-2001.
// The original team's TB uses inst_* functions; this one uses $readmemh
// and an independent expected-WB scoreboard.
module tb_pipeline_cpu_basic;
    parameter MEM_FILE =
        "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/arithmetic_basic.mem";
    localparam [31:0] START_PC = 32'h00001000;
    localparam integer ROM_WORDS = 24;
    localparam integer EXPECTED_COMMITS = 19;

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
        .clk(clk), .rst(rst), .if_valid(if_valid),
        .if_pc(if_pc), .if_inst(if_inst),
        .wb_commit_valid(wb_commit_valid),
        .wb_commit_pc(wb_commit_pc), .wb_commit_rd(wb_commit_rd),
        .wb_commit_data(wb_commit_data),
        .id_unsupported(id_unsupported), .id_raw_hazard(id_raw_hazard)
    );

    reg [31:0] rom [0:ROM_WORDS-1];
    reg [31:0] exp_pc [0:EXPECTED_COMMITS-1];
    reg [4:0] exp_rd [0:EXPECTED_COMMITS-1];
    reg [31:0] exp_data [0:EXPECTED_COMMITS-1];
    integer expected_count = 0;
    integer committed_count = 0;
    integer unsupported_count = 0;
    integer hazard_count = 0;
    integer errors = 0;
    integer idx;
    reg [31:0] next_pc = START_PC;

    task expect_write;
        input [31:0] pc;
        input [4:0] rd;
        input [31:0] data;
        begin
            exp_pc[expected_count] = pc;
            exp_rd[expected_count] = rd;
            exp_data[expected_count] = data;
            expected_count = expected_count + 1;
        end
    endtask

    // Samples WB before the rising-edge NBA update, exactly the register
    // record sampled by the synchronous RegFile at that same edge.
    always @(posedge clk) begin
        if (!rst) begin
            if (id_unsupported) unsupported_count = unsupported_count + 1;
            if (id_raw_hazard) begin
                hazard_count = hazard_count + 1;
                errors = errors + 1;
                $display("FAIL RAW at time=%0t, ID PC=%h", $time, dut.id_pc);
            end
            if (wb_commit_valid) begin
                if (committed_count >= EXPECTED_COMMITS) begin
                    errors = errors + 1;
                    $display("FAIL extra WB PC=%h rd=%0d data=%h",
                             wb_commit_pc, wb_commit_rd, wb_commit_data);
                end else if (wb_commit_pc !== exp_pc[committed_count] ||
                             wb_commit_rd !== exp_rd[committed_count] ||
                             wb_commit_data !== exp_data[committed_count]) begin
                    errors = errors + 1;
                    $display("FAIL WB[%0d] @%0t got PC=%h rd=%0d data=%h; expected PC=%h rd=%0d data=%h",
                        committed_count, $time, wb_commit_pc, wb_commit_rd,
                        wb_commit_data, exp_pc[committed_count],
                        exp_rd[committed_count], exp_data[committed_count]);
                end else begin
                    $display("PASS WB[%0d] PC=%h r%0d=%h", committed_count,
                             wb_commit_pc, wb_commit_rd, wb_commit_data);
                end
                if (wb_commit_rd == 5'd0) begin
                    errors = errors + 1;
                    $display("FAIL unexpected r0 commit");
                end
                committed_count = committed_count + 1;
            end
        end
    end

    task issue_word;
        input integer word_index;
        begin
            @(negedge clk);
            if_valid = 1'b1;
            if_pc = next_pc;
            if_inst = rom[word_index];
            next_pc = next_pc + 32'd4;
        end
    endtask

    task issue_bubble;
        begin
            @(negedge clk);
            if_valid = 1'b0;
            if_pc = next_pc;  // bubbles do not consume PC/ROM index
            if_inst = 32'd0;
        end
    endtask

    initial begin
        $readmemh(MEM_FILE, rom);
        // Expected results independently calculated from A's documented
        // 24-word program and the LoongArch arithmetic semantics.
        expect_write(32'h00001000, 5'd1,  32'd10);
        expect_write(32'h00001004, 5'd2,  32'd20);
        expect_write(32'h00001008, 5'd3,  32'hfffffffd);
        expect_write(32'h0000100c, 5'd4,  32'd1);
        expect_write(32'h00001010, 5'd5,  32'h000000aa);
        expect_write(32'h00001014, 5'd6,  32'h0000005a);
        expect_write(32'h00001018, 5'd7,  32'd0);
        expect_write(32'h0000101c, 5'd8,  32'h12345000);
        // 0x1020 writes r0 -> no commit. 0x1024..0x1030 -> 4 unsupported.
        expect_write(32'h00001034, 5'd20, 32'd30);
        expect_write(32'h00001038, 5'd21, 32'd10);
        expect_write(32'h0000103c, 5'd22, 32'd0);
        expect_write(32'h00001040, 5'd23, 32'd30);
        expect_write(32'h00001044, 5'd24, 32'd30);
        expect_write(32'h00001048, 5'd25, 32'd1);
        expect_write(32'h0000104c, 5'd26, 32'd0);
        expect_write(32'h00001050, 5'd27, 32'd1024);
        expect_write(32'h00001054, 5'd28, 32'd10);
        expect_write(32'h00001058, 5'd29, 32'hfffffffe);
        expect_write(32'h0000105c, 5'd30, 32'hffffffe1);

        if (expected_count != EXPECTED_COMMITS) begin
            $display("FAIL internal scoreboard count=%0d",expected_count);
            $fatal(1);
        end
        // Synchronous reset spans at least two positive edges.
        repeat (2) @(negedge clk);
        rst = 1'b0;
        // First group: 13 words at 0x1000..0x1030.
        for (idx = 0; idx < 13; idx = idx + 1) issue_word(idx);
        // Six empty IF slots: let RegFile commit before consuming the
        // dependency-bearing instructions beginning at 0x1034.
        repeat (6) issue_bubble();
        for (idx = 13; idx < ROM_WORDS; idx = idx + 1) issue_word(idx);
        // Drain pipeline and allow the last WB to be written into RegFile.
        repeat (10) issue_bubble();
        @(negedge clk);
        if (committed_count != EXPECTED_COMMITS) begin
            errors = errors + 1;
            $display("FAIL commits expected=%0d got=%0d",
                     EXPECTED_COMMITS,committed_count);
        end
        if (unsupported_count != 4) begin
            errors = errors + 1;
            $display("FAIL unsupported expected=4 got=%0d",unsupported_count);
        end
        if (hazard_count != 0) begin
            errors = errors + 1;
            $display("FAIL hazard count=%0d",hazard_count);
        end
        if (dut.u_regfile.regs[0] !== 32'd0 ||
            dut.u_regfile.regs[1] !== 32'd10 ||
            dut.u_regfile.regs[2] !== 32'd20 ||
            dut.u_regfile.regs[8] !== 32'h12345000 ||
            dut.u_regfile.regs[20] !== 32'd30 ||
            dut.u_regfile.regs[29] !== 32'hfffffffe ||
            dut.u_regfile.regs[30] !== 32'hffffffe1) begin
            errors = errors + 1;
            $display("FAIL RegFile final state");
        end
        $display("====================================================");
        $display("CPU V0.1 INDEPENDENT READMEMH REGRESSION");
        $display("commits=%0d/%0d unsupported=%0d hazards=%0d errors=%0d",
                 committed_count,EXPECTED_COMMITS,unsupported_count,hazard_count,errors);
        if (errors == 0 && committed_count == EXPECTED_COMMITS &&
            unsupported_count == 4 && hazard_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED");
        $finish;
    end

    initial begin
        #10000;
        $display("FATAL TIMEOUT: CPU V0.1 test did not finish");
        $fatal(1);
    end
endmodule
