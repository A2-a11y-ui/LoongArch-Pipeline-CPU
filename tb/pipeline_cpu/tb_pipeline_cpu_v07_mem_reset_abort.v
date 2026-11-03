`timescale 1ns / 1ps
// V0.7 whole-CPU reset-abort regression (Vivado 2019.1, Verilog-2001).
// NEW, test-only TB; does NOT change official RTL or the merged basic TB.
// Reuses the EXISTING, previously reviewed 18-word v07_mem_basic.mem program.
// The MEM_FILE path matches the original basic TB and may need editing
// on another workstation. All expected values are ISA-derived constants.
//
// Scenario A: Reset AFTER acceptance of the first ST.W [4]=10, but BEFORE
//             its response handshake. RAM[1] must remain zero.
// Scenario B: After restart, allow that ST.W to commit, then Reset AFTER
//             acceptance of LD.W [4], but BEFORE its response handshake.
//             RAM[1] must retain 10 through reset; canceled Load must not WB.
// Scenario C: Restart CPU again, run all 18 instructions and apply a strict
//             ordered WB/Store scoreboard with exactly-once transaction counts.
//
// Reset aborts pending requests. It does NOT clear RAM; it is not a rollback
// of already committed writes. This matches official dmem_latency semantics.
module tb_pipeline_cpu_v07_mem_reset_abort;
    parameter MEM_FILE = "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/v07_mem_basic.mem";
    localparam integer WORDS = 18;
    localparam integer N_WB  = 10;
    localparam integer N_ST  = 3;
    localparam integer MAX_WAIT_CYCLES = 2500;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg if_delivery_allow = 1'b0;

    wire if_valid, if_ready, if_req_fire, if_resp_fire, if_resp_hold;
    wire [31:0] if_pc, if_inst, if_req_pc, if_resp_pc;
    wire fetch_error_fire, adapter_busy;
    wire [31:0] cache_hits, cache_misses, cache_refills, backing_transactions;
    wire branch_resolve_valid, branch_redirect;
    wire [31:0] branch_redirect_pc;
    wire load_use_stall, id_unsupported, id_raw_hazard;
    wire wb_commit_valid, mem_store_commit_valid;
    wire [31:0] wb_commit_pc, wb_commit_data;
    wire [4:0] wb_commit_rd;
    wire [31:0] mem_store_commit_pc, mem_store_commit_addr, mem_store_commit_data;
    wire mem_stall, dmem_req_fire, dmem_resp_fire, mem_fault_valid;
    wire [31:0] mem_fault_pc, mem_fault_addr;
    wire mem_fault_store;

    pipeline_cpu_core_v07_mem #(
        .PC_BASE(32'h00001000),
        .PROGRAM_WORDS(WORDS),
        .IMEM_LATENCY(3),
        .IMEM_FILE(MEM_FILE),
        // Longer delays provide a deterministic window to abort a pending
        // request, without relying on a simulation-race-sensitive force.
        .DMEM_READ_LATENCY(9),
        .DMEM_WRITE_LATENCY(11),
        .DMEM_WORDS(256)
    ) dut (
        .clk(clk), .rst(rst), .if_delivery_allow(if_delivery_allow),
        .if_valid(if_valid), .if_pc(if_pc), .if_inst(if_inst),
        .if_ready(if_ready),
        .if_req_fire(if_req_fire), .if_req_pc(if_req_pc),
        .if_resp_fire(if_resp_fire), .if_resp_pc(if_resp_pc),
        .if_resp_hold(if_resp_hold),
        .fetch_error_fire(fetch_error_fire), .adapter_busy(adapter_busy),
        .cache_hits(cache_hits), .cache_misses(cache_misses),
        .cache_refills(cache_refills),
        .backing_transactions(backing_transactions),
        .branch_resolve_valid(branch_resolve_valid),
        .branch_redirect(branch_redirect),
        .branch_redirect_pc(branch_redirect_pc),
        .load_use_stall(load_use_stall),
        .id_unsupported(id_unsupported), .id_raw_hazard(id_raw_hazard),
        .wb_commit_valid(wb_commit_valid),
        .wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd),
        .wb_commit_data(wb_commit_data),
        .mem_store_commit_valid(mem_store_commit_valid),
        .mem_store_commit_pc(mem_store_commit_pc),
        .mem_store_commit_addr(mem_store_commit_addr),
        .mem_store_commit_data(mem_store_commit_data),
        .mem_stall(mem_stall), .dmem_req_fire(dmem_req_fire),
        .dmem_resp_fire(dmem_resp_fire),
        .mem_fault_valid(mem_fault_valid),
        .mem_fault_pc(mem_fault_pc), .mem_fault_addr(mem_fault_addr),
        .mem_fault_store(mem_fault_store)
    );

    reg [31:0] expected_wb_pc [0:N_WB-1];
    reg [31:0] expected_wb_data [0:N_WB-1];
    reg [4:0]  expected_wb_rd [0:N_WB-1];
    reg [31:0] expected_st_pc [0:N_ST-1];
    reg [31:0] expected_st_addr [0:N_ST-1];
    reg [31:0] expected_st_data [0:N_ST-1];

    integer phase = 0; // 0=abort store, 1=abort load, 2=final full run
    integer errors = 0;
    integer wb_count = 0, st_count = 0, req_count = 0, resp_count = 0;
    integer br_count = 0, stall_count = 0, cycles_final = 0;
    integer after_done = 0;
    reg req_outstanding = 1'b0;
    reg saw_aborted_store = 1'b0;
    reg saw_aborted_load  = 1'b0;
    reg saw_restarted_store = 1'b0;
    reg saw_final_complete = 1'b0;

    task expect_wb;
        input integer idx;
        input [31:0] pc;
        input [4:0] rd;
        input [31:0] data;
        begin
            expected_wb_pc[idx] = pc;
            expected_wb_rd[idx] = rd;
            expected_wb_data[idx] = data;
        end
    endtask
    task expect_st;
        input integer idx;
        input [31:0] pc;
        input [31:0] addr;
        input [31:0] data;
        begin
            expected_st_pc[idx] = pc;
            expected_st_addr[idx] = addr;
            expected_st_data[idx] = data;
        end
    endtask

    task fail_now;
        input [8*160-1:0] reason;
        begin
            errors = errors + 1;
            $display("FAIL RESET-ABORT: %0s at %0t phase=%0d", reason, $time, phase);
            $fatal(1, "V0.7 reset-abort regression failed");
        end
    endtask

    // Evaluate a request at its ACCEPTANCE clock edge (not merely req_valid).
    // Control reset only on the following negative edge, avoiding races with
    // the synchronous dmem_latency implementation.
    task wait_for_dmem_request;
        input expected_store;
        input [31:0] expected_addr;
        input [31:0] expected_pc;
        integer i;
        reg found;
        begin
            found = 1'b0;
            begin : request_wait
                for (i=0; i<MAX_WAIT_CYCLES; i=i+1) begin
                    @(posedge clk);
                    if (dmem_req_fire) begin
                        if (dut.u_cpu.mem_mem_write !== expected_store ||
                            dut.u_cpu.mem_alu_result !== expected_addr ||
                            dut.u_cpu.mem_pc !== expected_pc)
                            fail_now("Unexpected DMEM request before target");
                        found = 1'b1;
                        disable request_wait;
                    end
                end
            end
            if (!found)
                fail_now("Timeout waiting for target DMEM request");
        end
    endtask

    task wait_for_store_commit;
        input [31:0] expected_addr;
        input [31:0] expected_data;
        integer i;
        reg found;
        begin
            found = 1'b0;
            begin : store_wait
                for (i=0; i<MAX_WAIT_CYCLES; i=i+1) begin
                    @(posedge clk);
                    if (mem_store_commit_valid) begin
                        if (mem_store_commit_addr !== expected_addr ||
                            mem_store_commit_data !== expected_data)
                            fail_now("Unexpected Store before target commit");
                        found = 1'b1;
                        disable store_wait;
                    end
                end
            end
            if (!found)
                fail_now("Timeout waiting for restarted Store commit");
        end
    endtask

    task assert_reset_cleared_pipeline;
        input [31:0] expected_mem_word1;
        begin
            if (dut.u_cpu.u_dmem.mem[1] !== expected_mem_word1)
                fail_now("DMEM[1] not preserved/aborted as expected");
            if (dut.u_cpu.u_dmem.state !== 2'd0 ||
                dut.u_cpu.u_dmem.resp_valid !== 1'b0 ||
                dut.u_cpu.mem_request_accepted !== 1'b0 ||
                dut.u_cpu.mem_valid !== 1'b0 ||
                dut.u_cpu.wb_valid !== 1'b0 ||
                dmem_req_fire !== 1'b0 || dmem_resp_fire !== 1'b0 ||
                wb_commit_valid !== 1'b0 ||
                mem_store_commit_valid !== 1'b0)
                fail_now("Pipeline/DMEM retained pending valid across reset");
        end
    endtask

    initial begin : reset_scenarios
        // Identical expected program / retirement order to merged basic TB.
        expect_wb(0, 32'h1000, 5'd1, 32'd10);
        expect_wb(1, 32'h1004, 5'd2, 32'd20);
        expect_wb(2, 32'h100c, 5'd3, 32'd10);
        expect_wb(3, 32'h1010, 5'd4, 32'd30);
        expect_wb(4, 32'h1018, 5'd5, 32'd30);
        expect_wb(5, 32'h101c, 5'd6, 32'd31);
        expect_wb(6, 32'h102c, 5'd8, 32'd30);
        expect_wb(7, 32'h1030, 5'd9, 32'd32);
        expect_wb(8, 32'h1038, 5'd10, 32'd32);
        expect_wb(9, 32'h103c, 5'd11, 32'd31);
        expect_st(0, 32'h1008, 32'd4, 32'd10);
        expect_st(1, 32'h1014, 32'd8, 32'd30);
        expect_st(2, 32'h1034, 32'd16, 32'd32);

        repeat (4) @(negedge clk);
        rst = 1'b0;
        if_delivery_allow = 1'b1;
        $display("RESET-ABORT SCENARIO A: abort accepted Store before response");
        wait_for_dmem_request(1'b1, 32'd4, 32'h1008);
        @(negedge clk);
        if (dmem_resp_fire || mem_store_commit_valid)
            fail_now("Store response/commit occurred before abort");
        if (dut.u_cpu.u_dmem.mem[1] !== 32'd0)
            fail_now("Store wrote RAM before response handshake");
        rst = 1'b1;
        if_delivery_allow = 1'b0;
        repeat (3) @(posedge clk);
        #1;
        assert_reset_cleared_pipeline(32'd0);
        saw_aborted_store = 1'b1;
        $display("PASS STORE_ABORT: pending Store canceled, RAM[1]=0");

        @(negedge clk);
        phase = 1;
        rst = 1'b0;
        if_delivery_allow = 1'b1;
        $display("RESET-ABORT SCENARIO B: commit Store, abort subsequent Load");
        wait_for_store_commit(32'd4, 32'd10);
        saw_restarted_store = 1'b1;
        wait_for_dmem_request(1'b0, 32'd4, 32'h100c);
        @(negedge clk);
        if (dmem_resp_fire)
            fail_now("Load response occurred before abort");
        rst = 1'b1;
        if_delivery_allow = 1'b0;
        repeat (3) @(posedge clk);
        #1;
        assert_reset_cleared_pipeline(32'd10);
        saw_aborted_load = 1'b1;
        $display("PASS LOAD_ABORT: Load canceled, RAM[1] retained committed 10");

        // Start a fresh, complete run. Only THIS run is scored against the
        // canonical 10 WB / 3 Store / 7 DMEM request-response expectations.
        @(negedge clk);
        phase = 2;
        wb_count = 0; st_count = 0;
        req_count = 0; resp_count = 0; br_count = 0;
        stall_count = 0; cycles_final = 0; after_done = 0;
        req_outstanding = 1'b0;
        rst = 1'b0;
        if_delivery_allow = 1'b1;
        $display("RESET-ABORT SCENARIO C: full CPU restart and scoreboard");
    end

    always @(posedge clk) begin
        if (rst) begin
            if (wb_commit_valid || mem_store_commit_valid ||
                dmem_req_fire || dmem_resp_fire)
                fail_now("Architectural handshake active during reset");
        end else if (phase == 2 && !saw_final_complete) begin
            cycles_final = cycles_final + 1;
            if (fetch_error_fire) fail_now("Unexpected IF fetch error");
            if (mem_fault_valid) fail_now("Unexpected DMEM fault");
            if (mem_stall) stall_count = stall_count + 1;
            if (mem_stall && if_ready)
                fail_now("IF ready while MEM stalled");
            if (mem_stall && branch_redirect)
                fail_now("Redirect while MEM stalled");
            if (dmem_req_fire) begin
                req_count = req_count + 1;
                if (req_outstanding)
                    fail_now("Overlapping DMEM request");
                req_outstanding = 1'b1;
            end
            if (dmem_resp_fire) begin
                resp_count = resp_count + 1;
                if (!req_outstanding)
                    fail_now("DMEM response without request");
                req_outstanding = 1'b0;
            end
            if (branch_resolve_valid) begin
                br_count = br_count + 1;
                if (!branch_redirect || branch_redirect_pc !== 32'h102c)
                    fail_now("Wrong branch target or redirect signal");
            end
            if (wb_commit_valid) begin
                if (wb_count >= N_WB)
                    fail_now("Extra WB after restart");
                if (wb_commit_pc !== expected_wb_pc[wb_count] ||
                    wb_commit_rd !== expected_wb_rd[wb_count] ||
                    wb_commit_data !== expected_wb_data[wb_count])
                    fail_now("WB sequence/data mismatch after restart");
                wb_count = wb_count + 1;
            end
            if (mem_store_commit_valid) begin
                if (st_count >= N_ST)
                    fail_now("Extra Store after restart");
                if (mem_store_commit_pc !== expected_st_pc[st_count] ||
                    mem_store_commit_addr !== expected_st_addr[st_count] ||
                    mem_store_commit_data !== expected_st_data[st_count])
                    fail_now("Store sequence/data mismatch after restart");
                st_count = st_count + 1;
            end
            if (cycles_final > 5000)
                fail_now("Final run timed out");
            if (wb_count == N_WB && st_count == N_ST && br_count == 1)
                after_done = after_done + 1;
            else
                after_done = 0;
            if (after_done == 90) begin
                if (!saw_aborted_store || !saw_aborted_load ||
                    !saw_restarted_store ||
                    req_count != 7 || resp_count != 7 || req_outstanding ||
                    stall_count == 0 ||
                    dut.u_cpu.u_dmem.mem[1] !== 32'd10 ||
                    dut.u_cpu.u_dmem.mem[2] !== 32'd30 ||
                    dut.u_cpu.u_dmem.mem[3] !== 32'd0 ||
                    dut.u_cpu.u_dmem.mem[4] !== 32'd32 ||
                    dut.u_cpu.u_regfile.regs[7] !== 32'd0)
                    fail_now("Final memory/count/abort invariant mismatch");
                saw_final_complete = 1'b1;
                $display("V0.7 RESET-ABORT RESULT STORE_ABORT=1 LOAD_ABORT=1 RESTART=1 WB=%0d/%0d STORE=%0d/%0d BR=%0d DMEM_REQ=%0d DMEM_RESP=%0d STALL=%0d ERRORS=%0d",
                    wb_count, N_WB, st_count, N_ST, br_count,
                    req_count, resp_count, stall_count, errors);
                $display("ALL TESTS PASSED (V0.7 reset-abort CPU integration)");
                $finish;
            end
        end
    end

    // A hard wall-clock simulation timeout is independent of all scoreboards.
    initial begin
        #100000;
        if (!saw_final_complete)
            fail_now("Global simulation timeout");
    end
endmodule
