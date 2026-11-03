`timescale 1ns / 1ps
// V0.8 integrated MDU stress regression.
// Vivado 2019.1 / Verilog-2001. Test-only; no RTL changes.
// Covers:
//  - all seven MDU operations, including signed high product and negative DIV/MOD;
//  - consecutive MDU instructions and MDU->ALU / MDU->Store / MDU->Branch forwarding;
//  - Load-use interlocks before MDU and ALU consumers;
//  - observes (but does not require) Store/MDU overlap in the serialized I-Cache path;
//  - I-Cache response hold while MDU is busy;
//  - completed MDU result held under injected MEM backpressure, then consumed once;
//  - taken Branch flushes wrong-path MDU and Store.
// IMPORTANT: this RTL gates mdu_start_fire with !mem_stall. Therefore an MDU
// does NOT run concurrently with a real pending DMEM transaction. This test
// checks that an MDU waits in EX behind an older Store, and separately injects
// MEM backpressure after MDU Done to test result hold/release. It does not
// claim natural simultaneous MDU iteration and real DMEM transaction.
module tb_pipeline_cpu_v08_mdu_stress;
    parameter MEM_FILE =
        "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/v08_mdu_stress.mem";

    localparam integer PROGRAM_WORDS = 42;
    localparam integer N_WB = 31;
    localparam integer N_ST = 7;
    localparam integer N_MDU = 13;
    localparam integer N_DMEM = 14;
    localparam integer MAX_CYCLES = 12000;

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
        .if_resp_hold(if_resp_hold), .fetch_error_fire(fetch_error_fire),
        .adapter_busy(adapter_busy), .cache_hits(cache_hits),
        .cache_misses(cache_misses), .cache_refills(cache_refills),
        .backing_transactions(backing_transactions),
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
        .dmem_resp_fire(dmem_resp_fire), .mem_fault_valid(mem_fault_valid),
        .mem_fault_pc(mem_fault_pc), .mem_fault_addr(mem_fault_addr),
        .mem_fault_store(mem_fault_store),
        .mdu_start_fire(mdu_start_fire), .mdu_busy(mdu_busy),
        .mdu_done(mdu_done), .mdu_result_fire(mdu_result_fire),
        .mdu_div_zero(mdu_div_zero)
    );

    reg [31:0] expected_wb_pc [0:N_WB-1];
    reg [4:0]  expected_wb_rd [0:N_WB-1];
    reg [31:0] expected_wb_data [0:N_WB-1];
    reg [31:0] expected_st_pc [0:N_ST-1];
    reg [31:0] expected_st_addr [0:N_ST-1];
    reg [31:0] expected_st_data [0:N_ST-1];
    reg [31:0] expected_mdu_pc [0:N_MDU-1];
    reg [2:0]  expected_mdu_op [0:N_MDU-1];
    reg [31:0] expected_mdu_result [0:N_MDU-1];

    integer wb_count = 0;
    integer st_count = 0;
    integer mdu_start_count = 0;
    integer mdu_done_count = 0;
    integer mdu_result_count = 0;
    integer req_count = 0;
    integer resp_count = 0;
    integer branch_count = 0;
    integer unsupported_count = 0;
    integer load_use_events = 0;       // asserted load-use stall cycles
    integer load_use_episodes = 0;     // rising-edge episodes
    integer raw_hazard_events = 0;
    reg prev_load_use_stall = 1'b0;
    integer mem_stall_cycles = 0;
    integer mdu_busy_cycles = 0;
    integer mdu_wait_mem_cycles = 0;
    integer mdu_done_hold_cycles = 0;
    integer if_resp_hold_cycles = 0;
    integer if_resp_hold_during_mdu = 0;
    integer cycles = 0;
    integer after_done = 0;
    integer errors = 0;

    reg req_outstanding = 1'b0;
    reg prev_mdu_done = 1'b0;
    reg prev_if_resp_hold = 1'b0;
    reg [31:0] prev_if_resp_pc = 32'd0;
    reg [31:0] prev_if_resp_inst = 32'd0;
    reg forced_hold_completed = 1'b0;
    reg final_complete = 1'b0;

    integer wait_i;
    integer hold_i;
    reg found;

    task fail_now;
        input [8*180-1:0] reason;
        begin
            errors = errors + 1;
            $display("FAIL V0.8 MDU STRESS: %0s at %0t", reason, $time);
            $fatal(1, "V0.8 MDU integrated stress regression failed");
        end
    endtask

    task set_wb;
        input integer index;
        input [31:0] pc;
        input [4:0] rd;
        input [31:0] value;
        begin
            expected_wb_pc[index] = pc;
            expected_wb_rd[index] = rd;
            expected_wb_data[index] = value;
        end
    endtask

    task set_store;
        input integer index;
        input [31:0] pc;
        input [31:0] addr;
        input [31:0] value;
        begin
            expected_st_pc[index] = pc;
            expected_st_addr[index] = addr;
            expected_st_data[index] = value;
        end
    endtask

    task set_mdu;
        input integer index;
        input [31:0] pc;
        input [2:0] op;
        input [31:0] value;
        begin
            expected_mdu_pc[index] = pc;
            expected_mdu_op[index] = op;
            expected_mdu_result[index] = value;
        end
    endtask

    initial begin : initialize_scoreboards_and_inject_backpressure
        // Expected in-order architectural WB sequence.
        set_wb(0,  32'h00001000, 5'd1,  32'd7);
        set_wb(1,  32'h00001004, 5'd2,  32'd3);
        set_wb(2,  32'h00001008, 5'd3,  32'd21);
        set_wb(3,  32'h0000100c, 5'd4,  32'd28);
        set_wb(4,  32'h00001014, 5'd5,  32'd21);
        set_wb(5,  32'h00001018, 5'd6,  32'd7);
        set_wb(6,  32'h0000101c, 5'd7,  32'd28);
        set_wb(7,  32'h00001024, 5'd8,  32'd7);
        set_wb(8,  32'h00001028, 5'd9,  32'd1);
        set_wb(9,  32'h0000102c, 5'd10, 32'd2);
        set_wb(10, 32'h00001030, 5'd11, 32'd0);
        set_wb(11, 32'h00001034, 5'd12, 32'd23);
        set_wb(12, 32'h0000103c, 5'd13, 32'd2);
        set_wb(13, 32'h00001040, 5'd14, 32'd6);
        set_wb(14, 32'h00001048, 5'd15, 32'd21);
        set_wb(15, 32'h0000104c, 5'd16, 32'd28);
        set_wb(16, 32'h00001050, 5'd17, 32'd6);
        set_wb(17, 32'h00001054, 5'd18, 32'd13);
        set_wb(18, 32'h00001058, 5'd19, 32'd39);
        set_wb(19, 32'h00001060, 5'd20, 32'd39);
        set_wb(20, 32'h00001064, 5'd21, 32'd0);
        set_wb(21, 32'h00001074, 5'd23, 32'd99);
        set_wb(22, 32'h0000107c, 5'd24, 32'd99);
        set_wb(23, 32'h00001080, 5'd25, 32'd297);
        set_wb(24, 32'h00001084, 5'd26, 32'd304);
        set_wb(25, 32'h00001088, 5'd27, 32'hfffffff9);
        set_wb(26, 32'h0000108c, 5'd28, 32'hffffffff);
        set_wb(27, 32'h00001090, 5'd29, 32'hfffffffe);
        set_wb(28, 32'h00001094, 5'd30, 32'hffffffff);
        set_wb(29, 32'h0000109c, 5'd31, 32'hffffffff);
        set_wb(30, 32'h000010a0, 5'd4,  32'd6);

        // Expected Store commit sequence (commit occurs on DMEM response fire).
        set_store(0, 32'h00001010, 32'h00000000, 32'd21);
        set_store(1, 32'h00001020, 32'h00000004, 32'd7);
        set_store(2, 32'h00001038, 32'h00000008, 32'd2);
        set_store(3, 32'h00001044, 32'h00000010, 32'd6);
        set_store(4, 32'h0000105c, 32'h0000000c, 32'd39);
        set_store(5, 32'h00001078, 32'h00000014, 32'd99);
        set_store(6, 32'h00001098, 32'h00000018, 32'hffffffff);

        // Expected MDU starts, completions and results in program order.
        set_mdu(0,  32'h00001008, 3'b000, 32'd21);          // MUL.W
        set_mdu(1,  32'h00001018, 3'b011, 32'd7);           // DIV.W
        set_mdu(2,  32'h00001028, 3'b101, 32'd1);           // MOD.W
        set_mdu(3,  32'h0000102c, 3'b100, 32'd2);           // DIV.WU
        set_mdu(4,  32'h00001030, 3'b010, 32'd0);           // MULH.WU
        set_mdu(5,  32'h00001040, 3'b000, 32'd6);           // MUL.W
        set_mdu(6,  32'h00001048, 3'b000, 32'd21);          // MUL.W after Store stall
        set_mdu(7,  32'h00001058, 3'b000, 32'd39);          // MUL.W
        set_mdu(8,  32'h00001064, 3'b110, 32'd0);           // MOD.WU -> BEQ
        set_mdu(9,  32'h00001080, 3'b000, 32'd297);         // MUL.W
        set_mdu(10, 32'h0000108c, 3'b001, 32'hffffffff);    // MULH.W signed negative
        set_mdu(11, 32'h00001090, 3'b011, 32'hfffffffe);    // DIV.W -7/3
        set_mdu(12, 32'h00001094, 3'b101, 32'hffffffff);    // MOD.W -7%3

        repeat (4) @(negedge clk);
        rst = 1'b0;
        if_delivery_allow = 1'b1;

        // Inject a short IF-delivery backpressure window while the selected
        // MDU is busy. The I-Cache adapter must retain its pending response.
        found = 1'b0;
        begin : wait_selected_mdu_busy
            for (wait_i = 0; wait_i < MAX_CYCLES; wait_i = wait_i + 1) begin
                @(negedge clk);
                if (mdu_busy && dut.u_cpu.ex_valid &&
                    dut.u_cpu.ex_pc === 32'h00001048) begin
                    found = 1'b1;
                    disable wait_selected_mdu_busy;
                end
            end
        end
        if (!found)
            fail_now("Timeout waiting for selected MUL.W to become busy");

        if_delivery_allow = 1'b0;
        hold_i = 0;
        repeat (8) begin
            @(posedge clk);
            #1;
            if (if_resp_hold && mdu_busy)
                hold_i = hold_i + 1;
        end
        @(negedge clk);
        if_delivery_allow = 1'b1;
        if (hold_i == 0)
            fail_now("No I-Cache response was held during the selected MDU busy window");

        // Wait for the selected MDU Done, then inject MEM backpressure before
        // the EX/MEM acceptance edge. This is intentionally testbench-only.
        found = 1'b0;
        begin : wait_selected_mdu_done
            for (wait_i = 0; wait_i < MAX_CYCLES; wait_i = wait_i + 1) begin
                @(negedge clk);
                if (mdu_done && dut.u_cpu.ex_valid &&
                    dut.u_cpu.ex_pc === 32'h00001048) begin
                    found = 1'b1;
                    disable wait_selected_mdu_done;
                end
            end
        end
        if (!found)
            fail_now("Timeout waiting for selected MUL.W Done");

        if (dut.u_cpu.mem_valid !== 1'b0 ||
            dut.u_cpu.mem_access !== 1'b0 || mem_stall !== 1'b0)
            fail_now("Selected MDU Done did not reach an empty MEM slot before injected hold");

        force dut.u_cpu.mem_stall = 1'b1;
        #1;
        if (dut.u_cpu.mem_stall !== 1'b1 || !mdu_done || mdu_result_fire ||
            dut.u_cpu.u_mdu.result !== 32'd21)
            fail_now("MDU result was not held when injected MEM backpressure asserted");

        repeat (4) begin
            @(posedge clk);
            #1;
            if (!mdu_done || mdu_result_fire ||
                dut.u_cpu.u_mdu.result !== 32'd21 ||
                mdu_div_zero !== 1'b0)
                fail_now("Pending MDU Done/result changed or was consumed under backpressure");
        end

        @(negedge clk);
        release dut.u_cpu.mem_stall;
        #1;
        if (!mdu_done || !mdu_result_fire ||
            dut.u_cpu.u_mdu.result !== 32'd21)
            fail_now("MDU result did not become ready for exactly-once transfer after release");
        forced_hold_completed = 1'b1;
        $display("PASS: MDU Done/result held for four cycles and released for one transfer");
    end

    // Handshake-level and architectural scoreboard. All counters sample the
    // active values immediately before the accepting rising edge.
    always @(posedge clk) begin
        if (rst) begin
            prev_mdu_done = 1'b0;
            prev_if_resp_hold = 1'b0;
            prev_load_use_stall = 1'b0;
            if (wb_commit_valid || mem_store_commit_valid ||
                dmem_req_fire || dmem_resp_fire ||
                mdu_start_fire || mdu_result_fire)
                fail_now("Architectural or MDU handshake asserted during reset");
        end else if (!final_complete) begin
            cycles = cycles + 1;

            if (fetch_error_fire || mem_fault_valid)
                fail_now("Unexpected I-Cache fetch error or DMEM fault");

            if (id_unsupported)
                unsupported_count = unsupported_count + 1;
            if (load_use_stall) begin
                load_use_events = load_use_events + 1;
                if (!prev_load_use_stall) begin
                    load_use_episodes = load_use_episodes + 1;
                    $display("LOAD_USE_EPISODE[%0d] t=%0t ID_PC=%08h ID_INST=%08h ID_ACCEPT=%b ID_RS1=%0d/%b ID_RS2=%0d/%b EX_PC=%08h EX_INST=%08h EX_RD=%0d EX_MEM_READ=%b RAW=%b",
                        load_use_episodes, $time,
                        dut.u_cpu.id_pc, dut.u_cpu.id_inst, dut.u_cpu.id_accept,
                        dut.u_cpu.d_rs1_addr, dut.u_cpu.d_rs1_used,
                        dut.u_cpu.d_rs2_addr, dut.u_cpu.d_rs2_used,
                        dut.u_cpu.ex_pc, dut.u_cpu.ex_inst,
                        dut.u_cpu.ex_rd_addr, dut.u_cpu.ex_mem_read,
                        dut.u_cpu.raw_load_use);
                end
            end
            prev_load_use_stall = load_use_stall;
            if (dut.u_cpu.ex_valid && dut.u_cpu.ex_mem_read &&
                (dut.u_cpu.ex_rd_addr != 5'd0) && dut.u_cpu.id_valid &&
                ((dut.u_cpu.d_rs1_used && (dut.u_cpu.d_rs1_addr == dut.u_cpu.ex_rd_addr)) ||
                 (dut.u_cpu.d_rs2_used && (dut.u_cpu.d_rs2_addr == dut.u_cpu.ex_rd_addr))) &&
                !load_use_stall) begin
                $display("LOAD_USE_CANDIDATE_WITHOUT_STALL t=%0t ID_PC=%08h ID_INST=%08h ACCEPT=%b SUPPORTED=%b ID_RS1=%0d/%b ID_RS2=%0d/%b EX_PC=%08h EX_INST=%08h EX_RD=%0d RAW=%b",
                    $time, dut.u_cpu.id_pc, dut.u_cpu.id_inst,
                    dut.u_cpu.id_accept, dut.u_cpu.supported_instruction,
                    dut.u_cpu.d_rs1_addr, dut.u_cpu.d_rs1_used,
                    dut.u_cpu.d_rs2_addr, dut.u_cpu.d_rs2_used,
                    dut.u_cpu.ex_pc, dut.u_cpu.ex_inst,
                    dut.u_cpu.ex_rd_addr, dut.u_cpu.raw_load_use);
            end
            if (id_raw_hazard)
                raw_hazard_events = raw_hazard_events + 1;
            if (mem_stall)
                mem_stall_cycles = mem_stall_cycles + 1;
            if (mdu_busy)
                mdu_busy_cycles = mdu_busy_cycles + 1;
            if (if_resp_hold)
                if_resp_hold_cycles = if_resp_hold_cycles + 1;
            if (if_resp_hold && mdu_busy)
                if_resp_hold_during_mdu = if_resp_hold_during_mdu + 1;
            if (mdu_done && !mdu_result_fire)
                mdu_done_hold_cycles = mdu_done_hold_cycles + 1;

            // An older Store occupies MEM while the following MDU waits in EX.
            if (dut.u_cpu.ex_valid && dut.u_cpu.ex_is_mdu &&
                mem_stall && !dut.u_cpu.mdu_started)
                mdu_wait_mem_cycles = mdu_wait_mem_cycles + 1;

            if (mem_stall && if_ready)
                fail_now("IF accepted a new instruction while MEM was stalled");
            if (mdu_busy && if_ready)
                fail_now("IF accepted a new instruction while MDU was busy");
            if (mdu_start_fire && mem_stall)
                fail_now("MDU started before the older MEM transaction completed");
            if (mdu_result_fire && !mdu_done)
                fail_now("MDU result transferred without Done");
            if (mdu_div_zero)
                fail_now("Unexpected divide-by-zero indication in stress program");
            if (mdu_busy && branch_redirect)
                fail_now("Branch redirect asserted while an MDU operation was busy");

            // A held I-Cache response must retain the same PC/instruction.
            if (prev_if_resp_hold && if_resp_hold &&
                (if_resp_pc !== prev_if_resp_pc || if_inst !== prev_if_resp_inst))
                fail_now("I-Cache pending response changed while held");
            if (if_resp_hold && if_resp_fire)
                fail_now("I-Cache response marked both held and consumed");
            prev_if_resp_hold = if_resp_hold;
            prev_if_resp_pc = if_resp_pc;
            prev_if_resp_inst = if_inst;

            // Count each MDU Done event once, even when Done is held for several cycles.
            if (mdu_done && !prev_mdu_done) begin
                if (mdu_done_count >= N_MDU)
                    fail_now("Extra MDU Done event");
                if (dut.u_cpu.ex_pc !== expected_mdu_pc[mdu_done_count] ||
                    dut.u_cpu.ex_mdu_op !== expected_mdu_op[mdu_done_count] ||
                    dut.u_cpu.u_mdu.result !== expected_mdu_result[mdu_done_count])
                    fail_now("MDU Done PC/op/result scoreboard mismatch");
                mdu_done_count = mdu_done_count + 1;
            end
            prev_mdu_done = mdu_done;

            if (mdu_start_fire) begin
                if (mdu_start_count >= N_MDU)
                    fail_now("Extra MDU start; possible wrong-path or duplicate launch");
                if (dut.u_cpu.ex_pc !== expected_mdu_pc[mdu_start_count] ||
                    dut.u_cpu.ex_mdu_op !== expected_mdu_op[mdu_start_count])
                    fail_now("MDU start PC/op sequence mismatch");
                if (dut.u_cpu.ex_pc === 32'h0000106c)
                    fail_now("Wrong-path MDU at PC 0x106c was started");
                mdu_start_count = mdu_start_count + 1;
            end

            if (mdu_result_fire) begin
                if (mdu_result_count >= N_MDU)
                    fail_now("Extra MDU result transfer");
                if (dut.u_cpu.ex_pc !== expected_mdu_pc[mdu_result_count] ||
                    dut.u_cpu.ex_mdu_op !== expected_mdu_op[mdu_result_count] ||
                    dut.u_cpu.u_mdu.result !== expected_mdu_result[mdu_result_count])
                    fail_now("MDU result transfer PC/op/value mismatch");
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
                    fail_now("DMEM response without an accepted request");
                req_outstanding = 1'b0;
                resp_count = resp_count + 1;
            end

            if (branch_resolve_valid) begin
                branch_count = branch_count + 1;
                if (!branch_redirect ||
                    branch_redirect_pc !== 32'h00001074)
                    fail_now("Expected MDU-dependent BEQ redirect to PC 0x1074");
            end
            if (branch_redirect && !branch_resolve_valid)
                fail_now("Branch redirect occurred without a valid EX branch");

            if (wb_commit_valid) begin
                if (wb_count >= N_WB)
                    fail_now("Extra WB commit; possible duplicate or wrong-path retirement");
                if (wb_commit_pc !== expected_wb_pc[wb_count] ||
                    wb_commit_rd !== expected_wb_rd[wb_count] ||
                    wb_commit_data !== expected_wb_data[wb_count])
                    fail_now("WB PC/rd/data scoreboard mismatch");
                wb_count = wb_count + 1;
            end

            if (mem_store_commit_valid) begin
                if (st_count >= N_ST)
                    fail_now("Extra Store commit; possible wrong-path or repeated Store");
                if (mem_store_commit_pc !== expected_st_pc[st_count] ||
                    mem_store_commit_addr !== expected_st_addr[st_count] ||
                    mem_store_commit_data !== expected_st_data[st_count])
                    fail_now("Store PC/address/data scoreboard mismatch");
                st_count = st_count + 1;
            end

            if (cycles > MAX_CYCLES)
                fail_now("Global stress program timeout");

            if (wb_count == N_WB && st_count == N_ST &&
                mdu_start_count == N_MDU && mdu_done_count == N_MDU &&
                mdu_result_count == N_MDU && req_count == N_DMEM &&
                resp_count == N_DMEM && branch_count == 1 &&
                forced_hold_completed)
                after_done = after_done + 1;
            else
                after_done = 0;

            if (after_done == 80) begin
                if (req_outstanding)
                    fail_now("DMEM request remained outstanding at completion");
                if (unsupported_count != 1)
                    fail_now("Expected exactly one unsupported sentinel instruction");
                $display("LOAD_USE_DEBUG: stall_cycles=%0d episodes=%0d raw_hazard_cycles=%0d",
                    load_use_events, load_use_episodes, raw_hazard_events);
                // This is the full CPU + serialized I-Cache integration test.
                // icache_if_adapter permits only one outstanding IF request and
                // does not accept the next instruction until the current
                // response is consumed. Therefore adjacent program words are
                // NOT guaranteed to be adjacent in ID/EX and IF/ID. A minimum
                // load-use stall count is not a valid acceptance criterion here.
                // Natural back-to-back load-use interlocks are checked by the
                // separate V0.8 datapath-level streaming testbench.
                $display("LOAD_USE_NOTE: full I-Cache integration path observed %0d stall cycles / %0d episodes; see datapath-level test for forced back-to-back coverage",
                    load_use_events, load_use_episodes);
                $display("STORE_MDU_WAIT_NOTE: full serialized I-Cache path observed %0d EX-wait cycles; directed direct-datapath test checks forced Store/MDU overlap", mdu_wait_mem_cycles);
                if (mdu_done_hold_cycles < 4)
                    fail_now("Expected at least four cycles of held MDU Done");
                if (if_resp_hold_during_mdu == 0)
                    fail_now("No I-Cache response hold overlapped MDU Busy");
                if (mdu_busy_cycles == 0 || mem_stall_cycles == 0 ||
                    if_resp_hold_cycles == 0)
                    fail_now("Required MDU/MEM/I-Cache stall coverage was not observed");

                if (dut.u_cpu.u_dmem.mem[0] !== 32'd21 ||
                    dut.u_cpu.u_dmem.mem[1] !== 32'd7 ||
                    dut.u_cpu.u_dmem.mem[2] !== 32'd2 ||
                    dut.u_cpu.u_dmem.mem[3] !== 32'd39 ||
                    dut.u_cpu.u_dmem.mem[4] !== 32'd6 ||
                    dut.u_cpu.u_dmem.mem[5] !== 32'd99 ||
                    dut.u_cpu.u_dmem.mem[6] !== 32'hffffffff)
                    fail_now("Final DMEM contents mismatch");

                if (dut.u_cpu.u_regfile.regs[22] !== 32'd0 ||
                    dut.u_cpu.u_regfile.regs[23] !== 32'd99 ||
                    dut.u_cpu.u_regfile.regs[25] !== 32'd297 ||
                    dut.u_cpu.u_regfile.regs[26] !== 32'd304 ||
                    dut.u_cpu.u_regfile.regs[28] !== 32'hffffffff ||
                    dut.u_cpu.u_regfile.regs[29] !== 32'hfffffffe ||
                    dut.u_cpu.u_regfile.regs[30] !== 32'hffffffff ||
                    dut.u_cpu.u_regfile.regs[31] !== 32'hffffffff ||
                    dut.u_cpu.u_regfile.regs[4]  !== 32'd6)
                    fail_now("Final register contents or wrong-path MDU suppression mismatch");

                if (mdu_start_count != N_MDU ||
                    mdu_done_count != N_MDU ||
                    mdu_result_count != N_MDU ||
                    wb_count != N_WB || st_count != N_ST ||
                    req_count != N_DMEM || resp_count != N_DMEM ||
                    branch_count != 1 || errors != 0)
                    fail_now("Final exact-count assertion failed");

                final_complete = 1'b1;
                $display("V0.8 MDU STRESS RESULT WB=%0d/%0d STORE=%0d/%0d MDU_START=%0d DONE=%0d RESULT=%0d DMEM_REQ=%0d RESP=%0d BRANCH=%0d LOAD_USE=%0d MDU_WAIT_MEM=%0d MDU_BUSY=%0d MDU_DONE_HOLD=%0d IF_HOLD=%0d IF_HOLD_DURING_MDU=%0d MEM_STALL=%0d UNSUPPORTED=%0d ERRORS=%0d",
                    wb_count, N_WB, st_count, N_ST,
                    mdu_start_count, mdu_done_count, mdu_result_count,
                    req_count, resp_count, branch_count, load_use_events,
                    mdu_wait_mem_cycles, mdu_busy_cycles,
                    mdu_done_hold_cycles, if_resp_hold_cycles,
                    if_resp_hold_during_mdu, mem_stall_cycles,
                    unsupported_count, errors);
                $display("ALL TESTS PASSED (V0.8 integrated MDU stress regression)");
                $finish;
            end
        end
    end

    initial begin
        #250000;
        if (!final_complete)
            fail_now("Global simulation watchdog expired");
    end
endmodule
