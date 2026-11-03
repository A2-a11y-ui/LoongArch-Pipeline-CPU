`timescale 1ns / 1ps
// V0.8 whole-CPU MDU reset-abort regression.
// Vivado 2019.1 / Verilog-2001. Test-only: no RTL is modified.
//
// Scenarios:
// A) Reset while MUL.W at PC 0x100c is actively iterating.
// B) Restart, then reset while DIV.W at PC 0x1014 is actively iterating.
// C) Restart, inject downstream MEM backpressure after MUL starts; wait for
//    MDU done, verify result is held and not transferred, then reset while
//    the result is pending.
// D) Restart once more and score the complete program exactly.
//
// The injected stall in C is intentionally applied only after the older LD
// has completed and EX/MEM is empty. This isolates the MDU done/result_ready
// hold contract without repeatedly committing an older held MEM slot.
// It is NOT evidence of natural MDU execution concurrent with a real DMEM
// transaction. The RTL currently gates MDU start with !mem_stall.
module tb_pipeline_cpu_v08_mdu_reset_abort;
    parameter MEM_FILE =
        "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/v08_mdu_reset_abort.mem";

    localparam integer PROGRAM_WORDS = 9;
    localparam integer N_WB = 7;
    localparam integer N_ST = 1;
    localparam integer N_MDU = 2;
    localparam integer MAX_WAIT_CYCLES = 5000;

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
    wire mdu_start_fire, mdu_busy, mdu_done, mdu_result_fire, mdu_div_zero;

    pipeline_cpu_core_v08_mdu #(
        .PC_BASE(32'h00001000),
        .PROGRAM_WORDS(PROGRAM_WORDS),
        .IMEM_LATENCY(3),
        .IMEM_FILE(MEM_FILE),
        .DMEM_READ_LATENCY(8),
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
        .cache_refills(cache_refills), .backing_transactions(backing_transactions),
        .branch_resolve_valid(branch_resolve_valid),
        .branch_redirect(branch_redirect), .branch_redirect_pc(branch_redirect_pc),
        .load_use_stall(load_use_stall), .id_unsupported(id_unsupported),
        .id_raw_hazard(id_raw_hazard),
        .wb_commit_valid(wb_commit_valid), .wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd), .wb_commit_data(wb_commit_data),
        .mem_store_commit_valid(mem_store_commit_valid),
        .mem_store_commit_pc(mem_store_commit_pc),
        .mem_store_commit_addr(mem_store_commit_addr),
        .mem_store_commit_data(mem_store_commit_data),
        .mem_stall(mem_stall), .dmem_req_fire(dmem_req_fire),
        .dmem_resp_fire(dmem_resp_fire),
        .mem_fault_valid(mem_fault_valid), .mem_fault_pc(mem_fault_pc),
        .mem_fault_addr(mem_fault_addr), .mem_fault_store(mem_fault_store),
        .mdu_start_fire(mdu_start_fire), .mdu_busy(mdu_busy),
        .mdu_done(mdu_done), .mdu_result_fire(mdu_result_fire),
        .mdu_div_zero(mdu_div_zero)
    );

    reg [31:0] expected_wb_pc [0:N_WB-1];
    reg [31:0] expected_wb_data [0:N_WB-1];
    reg [4:0]  expected_wb_rd [0:N_WB-1];
    reg [31:0] expected_st_pc [0:N_ST-1];
    reg [31:0] expected_st_addr [0:N_ST-1];
    reg [31:0] expected_st_data [0:N_ST-1];
    reg [31:0] expected_mdu_pc [0:N_MDU-1];
    reg [2:0]  expected_mdu_op [0:N_MDU-1];

    integer phase = 0; // 0=abort MUL, 1=abort DIV, 2=abort pending Done, 3=final run
    integer errors = 0;
    integer wb_count = 0, st_count = 0;
    integer mdu_start_count = 0, mdu_result_count = 0;
    integer req_count = 0, resp_count = 0, branch_count = 0;
    integer busy_cycles = 0, mem_stall_cycles = 0, if_resp_held_cycles = 0;
    integer unsupported_count = 0, cycles = 0, after_done = 0;
    integer active_mul_aborts = 0, active_div_aborts = 0, pending_done_aborts = 0;
    reg req_outstanding = 1'b0;
    reg final_complete = 1'b0;
    reg guard_active = 1'b0;
    reg [31:0] guard_pc = 32'd0;

    task fail_now;
        input [8*180-1:0] reason;
        begin
            errors = errors + 1;
            $display("FAIL V0.8 MDU RESET: %0s at %0t phase=%0d", reason, $time, phase);
            $fatal(1, "V0.8 MDU reset-abort regression failed");
        end
    endtask

    task assert_reset_cleared;
        begin
            if (mdu_busy !== 1'b0 || mdu_done !== 1'b0 ||
                mdu_start_fire !== 1'b0 || mdu_result_fire !== 1'b0 ||
                dut.u_cpu.u_mdu.state !== 2'd0 ||
                dut.u_cpu.u_mdu.result !== 32'd0 ||
                dut.u_cpu.u_mdu.div_zero !== 1'b0 ||
                dut.u_cpu.mdu_started !== 1'b0 ||
                dut.u_cpu.id_valid !== 1'b0 ||
                dut.u_cpu.ex_valid !== 1'b0 ||
                dut.u_cpu.mem_valid !== 1'b0 ||
                dut.u_cpu.wb_valid !== 1'b0 ||
                dut.u_cpu.mem_request_accepted !== 1'b0 ||
                dut.u_cpu.u_dmem.state !== 2'd0 ||
                dut.u_cpu.u_dmem.resp_valid !== 1'b0 ||
                if_req_fire || if_resp_fire ||
                dmem_req_fire || dmem_resp_fire ||
                wb_commit_valid || mem_store_commit_valid ||
                branch_redirect)
                fail_now("MDU/pipeline/DMEM retained active state across synchronous reset");

            if (dut.u_cpu.u_dmem.mem[1] !== 32'd0)
                fail_now("Unexpected RAM side effect before final full-program run");
        end
    endtask

    // Call only on a falling edge. Reset is synchronous and active high.
    task reset_cpu;
        input [31:0] aborted_pc;
        begin
            guard_pc = aborted_pc;
            guard_active = 1'b1;
            rst = 1'b1;
            if_delivery_allow = 1'b0;
            repeat (3) @(posedge clk);
            #1;
            assert_reset_cleared;
            @(negedge clk);
            rst = 1'b0;
            if_delivery_allow = 1'b1;
        end
    endtask

    // Observe the actual EX-stage MDU transaction, not merely a fetched word.
    task wait_for_mdu_busy;
        input [31:0] expected_pc;
        input [2:0] expected_op;
        integer i;
        reg found;
        begin
            found = 1'b0;
            begin : wait_mdu_loop
                for (i = 0; i < MAX_WAIT_CYCLES; i = i + 1) begin
                    @(negedge clk);
                    if (mdu_busy && dut.u_cpu.ex_valid &&
                        dut.u_cpu.ex_pc === expected_pc) begin
                        if (dut.u_cpu.ex_mdu_op !== expected_op)
                            fail_now("Unexpected MDU operation code at target EX PC");
                        if (mdu_done)
                            fail_now("Expected active MDU iteration, observed pending Done");
                        found = 1'b1;
                        disable wait_mdu_loop;
                    end
                end
            end
            if (!found)
                fail_now("Timeout waiting for requested MDU operation to become busy");
        end
    endtask

    task wait_for_mdu_done;
        integer i;
        reg found;
        begin
            found = 1'b0;
            begin : wait_done_loop
                for (i = 0; i < MAX_WAIT_CYCLES; i = i + 1) begin
                    @(negedge clk);
                    if (mdu_done) begin
                        found = 1'b1;
                        disable wait_done_loop;
                    end
                end
            end
            if (!found)
                fail_now("Timeout waiting for MDU Done");
        end
    endtask

    initial begin : reset_and_final_scenarios
        expected_wb_pc[0] = 32'h00001000; expected_wb_rd[0] = 5'd1; expected_wb_data[0] = 32'd6;
        expected_wb_pc[1] = 32'h00001004; expected_wb_rd[1] = 5'd2; expected_wb_data[1] = 32'd3;
        expected_wb_pc[2] = 32'h00001008; expected_wb_rd[2] = 5'd6; expected_wb_data[2] = 32'd0;
        expected_wb_pc[3] = 32'h0000100c; expected_wb_rd[3] = 5'd3; expected_wb_data[3] = 32'd18;
        expected_wb_pc[4] = 32'h00001010; expected_wb_rd[4] = 5'd4; expected_wb_data[4] = 32'd19;
        expected_wb_pc[5] = 32'h00001014; expected_wb_rd[5] = 5'd5; expected_wb_data[5] = 32'd6;
        expected_wb_pc[6] = 32'h0000101c; expected_wb_rd[6] = 5'd7; expected_wb_data[6] = 32'd6;

        expected_st_pc[0] = 32'h00001018;
        expected_st_addr[0] = 32'h00000004;
        expected_st_data[0] = 32'd6;

        expected_mdu_pc[0] = 32'h0000100c; expected_mdu_op[0] = 3'b000;
        expected_mdu_pc[1] = 32'h00001014; expected_mdu_op[1] = 3'b011;

        repeat (4) @(negedge clk);
        rst = 1'b0;
        if_delivery_allow = 1'b1;

        // A: cancel a genuinely active MUL.W after several iterative steps.
        $display("SCENARIO A: reset during active MUL.W at PC 0x100c");
        wait_for_mdu_busy(32'h0000100c, 3'b000);
        repeat (5) @(negedge clk);
        if (!mdu_busy || mdu_done)
            fail_now("MUL.W was not still active immediately before reset");
        reset_cpu(32'h0000100c);
        active_mul_aborts = active_mul_aborts + 1;
        $display("PASS: active MUL.W canceled; no pending result survived reset");

        // B: restart from PC_BASE, retire the MUL/ADD dependency, then cancel DIV.
        phase = 1;
        $display("SCENARIO B: reset during active DIV.W at PC 0x1014");
        wait_for_mdu_busy(32'h00001014, 3'b011);
        repeat (5) @(negedge clk);
        if (!mdu_busy || mdu_done)
            fail_now("DIV.W was not still active immediately before reset");
        reset_cpu(32'h00001014);
        active_div_aborts = active_div_aborts + 1;
        $display("PASS: active DIV.W canceled; no pending quotient survived reset");

        // C: let the first Load finish, then hold the empty EX/MEM slot to
        // exercise the MDU done/result_ready backpressure contract. Reset the
        // CPU while the completed result is pending and unconsumed.
        phase = 2;
        $display("SCENARIO C: reset while MUL.W Done is pending under injected MEM backpressure");
        wait_for_mdu_busy(32'h0000100c, 3'b000);
        if (dut.u_cpu.mem_valid !== 1'b0 || mem_stall !== 1'b0)
            fail_now("Expected preceding Load to be complete and EX/MEM to be empty before injected stall");
        force dut.u_cpu.mem_stall = 1'b1;
        wait_for_mdu_done;
        if (!mdu_done || mdu_busy || mdu_result_fire ||
            dut.u_cpu.u_mdu.result !== 32'd18 || mdu_div_zero !== 1'b0)
            fail_now("MDU Done/result was not held while downstream MEM backpressure was injected");
        repeat (3) begin
            @(negedge clk);
            if (!mdu_done || mdu_result_fire ||
                dut.u_cpu.u_mdu.result !== 32'd18 || mdu_div_zero !== 1'b0)
                fail_now("Pending MDU result changed or was consumed under backpressure");
        end

        guard_pc = 32'h0000100c;
        guard_active = 1'b1;
        rst = 1'b1;
        if_delivery_allow = 1'b0;
        @(posedge clk);
        #1;
        release dut.u_cpu.mem_stall;
        repeat (2) @(posedge clk);
        #1;
        assert_reset_cleared;
        pending_done_aborts = pending_done_aborts + 1;
        $display("PASS: completed MUL.W result canceled before result_ready handshake");

        @(negedge clk);
        phase = 3;
        wb_count = 0; st_count = 0;
        mdu_start_count = 0; mdu_result_count = 0;
        req_count = 0; resp_count = 0; branch_count = 0;
        busy_cycles = 0; mem_stall_cycles = 0; if_resp_held_cycles = 0;
        unsupported_count = 0; cycles = 0; after_done = 0;
        req_outstanding = 1'b0;
        rst = 1'b0;
        if_delivery_allow = 1'b1;
        $display("SCENARIO D: full restart with ordered WB/Store/MDU scoreboards");
    end

    always @(posedge clk) begin
        if (rst) begin
            if (wb_commit_valid || mem_store_commit_valid ||
                dmem_req_fire || dmem_resp_fire ||
                mdu_start_fire || mdu_result_fire)
                fail_now("Architectural/MDU handshake asserted during reset");
        end else begin
            // A canceled instruction must not write back before that exact
            // instruction has been fetched, decoded and started again.
            if (guard_active) begin
                if (wb_commit_valid && wb_commit_pc === guard_pc)
                    fail_now("Ghost WB from an aborted MDU transaction after reset");
                if (mdu_start_fire && dut.u_cpu.ex_pc === guard_pc)
                    guard_active = 1'b0;
            end

            if (phase == 3 && !final_complete) begin
                cycles = cycles + 1;
                if (fetch_error_fire || mem_fault_valid)
                    fail_now("Unexpected IF fetch error or DMEM fault in final run");
                if (branch_resolve_valid || branch_redirect)
                    fail_now("Unexpected Branch in reset-abort test program");
                if (mem_stall) mem_stall_cycles = mem_stall_cycles + 1;
                if (mdu_busy) busy_cycles = busy_cycles + 1;
                if (if_resp_hold) if_resp_held_cycles = if_resp_held_cycles + 1;
                if (id_unsupported) unsupported_count = unsupported_count + 1;

                if (mem_stall && if_ready)
                    fail_now("IF accepted a response during MEM Stall");
                if (mdu_busy && if_ready)
                    fail_now("IF accepted a response during MDU Busy");
                if (mdu_start_fire && mem_stall)
                    fail_now("MDU started while MEM was stalled");
                if (mdu_result_fire && !mdu_done)
                    fail_now("MDU result handshake occurred without Done");
                if (mdu_div_zero)
                    fail_now("Unexpected divide-by-zero indication");

                if (mdu_start_fire) begin
                    if (mdu_start_count >= N_MDU)
                        fail_now("Extra MDU start after expected program operations");
                    if (dut.u_cpu.ex_pc !== expected_mdu_pc[mdu_start_count] ||
                        dut.u_cpu.ex_mdu_op !== expected_mdu_op[mdu_start_count])
                        fail_now("MDU start PC/op sequence mismatch");
                    mdu_start_count = mdu_start_count + 1;
                end

                if (mdu_result_fire) begin
                    if (mdu_result_count >= N_MDU)
                        fail_now("Extra MDU result transfer");
                    if (dut.u_cpu.ex_pc !== expected_mdu_pc[mdu_result_count] ||
                        dut.u_cpu.ex_mdu_op !== expected_mdu_op[mdu_result_count])
                        fail_now("MDU result transfer PC/op sequence mismatch");
                    mdu_result_count = mdu_result_count + 1;
                end

                if (dmem_req_fire) begin
                    if (req_outstanding)
                        fail_now("Overlapping DMEM requests");
                    req_outstanding = 1'b1;
                    req_count = req_count + 1;
                end
                if (dmem_resp_fire) begin
                    if (!req_outstanding)
                        fail_now("DMEM response without accepted request");
                    req_outstanding = 1'b0;
                    resp_count = resp_count + 1;
                end

                if (wb_commit_valid) begin
                    if (wb_count >= N_WB)
                        fail_now("Extra WB after final restart");
                    if (wb_commit_pc !== expected_wb_pc[wb_count] ||
                        wb_commit_rd !== expected_wb_rd[wb_count] ||
                        wb_commit_data !== expected_wb_data[wb_count])
                        fail_now("WB PC/rd/data scoreboard mismatch");
                    wb_count = wb_count + 1;
                end

                if (mem_store_commit_valid) begin
                    if (st_count >= N_ST)
                        fail_now("Extra Store commit after final restart");
                    if (mem_store_commit_pc !== expected_st_pc[st_count] ||
                        mem_store_commit_addr !== expected_st_addr[st_count] ||
                        mem_store_commit_data !== expected_st_data[st_count])
                        fail_now("Store PC/address/data scoreboard mismatch");
                    st_count = st_count + 1;
                end

                if (cycles > 8000)
                    fail_now("Final complete-program run timed out");

                if (wb_count == N_WB && st_count == N_ST &&
                    mdu_start_count == N_MDU && mdu_result_count == N_MDU &&
                    req_count == 3 && resp_count == 3)
                    after_done = after_done + 1;
                else
                    after_done = 0;

                if (after_done == 80) begin
                    if (req_outstanding || guard_active ||
                        branch_count != 0 || busy_cycles == 0 ||
                        mem_stall_cycles == 0 ||
                        dut.u_cpu.u_dmem.mem[1] !== 32'd6 ||
                        dut.u_cpu.u_regfile.regs[3] !== 32'd18 ||
                        dut.u_cpu.u_regfile.regs[4] !== 32'd19 ||
                        dut.u_cpu.u_regfile.regs[5] !== 32'd6 ||
                        dut.u_cpu.u_regfile.regs[6] !== 32'd0 ||
                        dut.u_cpu.u_regfile.regs[7] !== 32'd6)
                        fail_now("Final counts, memory, register state or reset guard mismatch");

                    final_complete = 1'b1;
                    $display("V0.8 MDU RESET-ABORT RESULT ACTIVE_MUL_ABORT=%0d ACTIVE_DIV_ABORT=%0d PENDING_DONE_ABORT=%0d WB=%0d/%0d STORE=%0d/%0d MDU_START=%0d MDU_RESULT=%0d DMEM_REQ=%0d DMEM_RESP=%0d MDU_BUSY_CYCLES=%0d MEM_STALL_CYCLES=%0d IF_RESP_HELD=%0d UNSUPPORTED=%0d ERRORS=%0d",
                        active_mul_aborts, active_div_aborts, pending_done_aborts,
                        wb_count, N_WB, st_count, N_ST, mdu_start_count,
                        mdu_result_count, req_count, resp_count, busy_cycles,
                        mem_stall_cycles, if_resp_held_cycles, unsupported_count, errors);

                    if (active_mul_aborts != 1 || active_div_aborts != 1 ||
                        pending_done_aborts != 1 || wb_count != N_WB ||
                        st_count != N_ST || mdu_start_count != N_MDU ||
                        mdu_result_count != N_MDU || req_count != 3 ||
                        resp_count != 3 || unsupported_count != 1 || errors != 0)
                        fail_now("Final exact-count assertion failed");

                    $display("ALL TESTS PASSED (V0.8 MDU reset-abort CPU integration)");
                    $finish;
                end
            end
        end
    end

    initial begin
        #200000;
        if (!final_complete)
            fail_now("Global simulation timeout");
    end
endmodule
