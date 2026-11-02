`timescale 1ns / 1ps
// V0.7 independent stress regression (corrected).
// Full top-level regression: multi-cycle DMEM + the existing one-outstanding
// I-Cache adapter. During MEM backpressure, the next IF response is held at
// the adapter boundary; natural load-use/EX-branch overlap is checked in the
// separate datapath-level regression, which drives a one-instruction/cycle IF.
//
// Vivado 2019.1 / Verilog-2001 compatible.
module tb_pipeline_cpu_v07_mem_stress;
    parameter MEM_FILE =
        "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/v07_mem_stress.mem";

    localparam integer PROGRAM_WORDS = 15;
    localparam integer N_WB = 8;
    localparam integer N_STORE = 3;

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
        .PROGRAM_WORDS(PROGRAM_WORDS),
        .IMEM_LATENCY(3),
        .IMEM_FILE(MEM_FILE),
        .DMEM_READ_LATENCY(32),
        .DMEM_WRITE_LATENCY(36),
        .DMEM_WORDS(64)
    ) dut (
        .clk(clk),
        .rst(rst),
        .if_delivery_allow(if_delivery_allow),

        .if_valid(if_valid),
        .if_pc(if_pc),
        .if_inst(if_inst),
        .if_ready(if_ready),

        .if_req_fire(if_req_fire),
        .if_req_pc(if_req_pc),
        .if_resp_fire(if_resp_fire),
        .if_resp_pc(if_resp_pc),
        .if_resp_hold(if_resp_hold),
        .fetch_error_fire(fetch_error_fire),
        .adapter_busy(adapter_busy),

        .cache_hits(cache_hits),
        .cache_misses(cache_misses),
        .cache_refills(cache_refills),
        .backing_transactions(backing_transactions),

        .branch_resolve_valid(branch_resolve_valid),
        .branch_redirect(branch_redirect),
        .branch_redirect_pc(branch_redirect_pc),

        .load_use_stall(load_use_stall),
        .id_unsupported(id_unsupported),
        .id_raw_hazard(id_raw_hazard),

        .wb_commit_valid(wb_commit_valid),
        .wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd),
        .wb_commit_data(wb_commit_data),

        .mem_store_commit_valid(mem_store_commit_valid),
        .mem_store_commit_pc(mem_store_commit_pc),
        .mem_store_commit_addr(mem_store_commit_addr),
        .mem_store_commit_data(mem_store_commit_data),

        .mem_stall(mem_stall),
        .dmem_req_fire(dmem_req_fire),
        .dmem_resp_fire(dmem_resp_fire),
        .mem_fault_valid(mem_fault_valid),
        .mem_fault_pc(mem_fault_pc),
        .mem_fault_addr(mem_fault_addr),
        .mem_fault_store(mem_fault_store)
    );

    reg [31:0] exp_wb_pc [0:N_WB-1];
    reg [4:0]  exp_wb_rd [0:N_WB-1];
    reg [31:0] exp_wb_data [0:N_WB-1];

    reg [31:0] exp_st_pc [0:N_STORE-1];
    reg [31:0] exp_st_addr [0:N_STORE-1];
    reg [31:0] exp_st_data [0:N_STORE-1];

    integer wb_count = 0;
    integer store_count = 0;
    integer req_count = 0;
    integer resp_count = 0;
    integer branch_count = 0;
    integer branch_resolve_count = 0;
    integer branch_response_hold_cycles = 0;
    integer load_use_count = 0;       // rising-edge episodes
    integer load_use_cycles = 0;      // total cycles request is high
    integer mem_stall_cycles = 0;
    integer if_resp_held_cycles = 0;
    integer if_resp_held_during_mem = 0;
    integer unsupported_count = 0;
    integer errors = 0;
    integer cycles = 0;
    integer after_done = 0;

    reg prev_load_use_stall = 1'b0;
    reg req_outstanding = 1'b0;

    // EX/MEM snapshot used to check payload stability during a stalled MEM slot.
    reg old_mem_stall = 1'b0;
    reg old_mem_valid = 1'b0;
    reg [31:0] old_mem_pc = 32'd0;
    reg [31:0] old_mem_addr = 32'd0;
    reg [31:0] old_mem_store_data = 32'd0;
    reg [4:0] old_mem_rd = 5'd0;
    reg old_mem_read = 1'b0;
    reg old_mem_write = 1'b0;
    reg old_mem_reg_write = 1'b0;

    task fail;
        input [8*160-1:0] message;
        begin
            errors = errors + 1;
            $display("FAIL @%0t: %0s", $time, message);
        end
    endtask

    task set_wb;
        input integer index;
        input [31:0] pc;
        input [4:0] rd;
        input [31:0] data;
        begin
            exp_wb_pc[index] = pc;
            exp_wb_rd[index] = rd;
            exp_wb_data[index] = data;
        end
    endtask

    task set_store;
        input integer index;
        input [31:0] pc;
        input [31:0] addr;
        input [31:0] data;
        begin
            exp_st_pc[index] = pc;
            exp_st_addr[index] = addr;
            exp_st_data[index] = data;
        end
    endtask

    initial begin
        // WB order for v07_mem_stress.mem.
        set_wb(0, 32'h00001000, 5'd1, 32'd64);
        set_wb(1, 32'h00001004, 5'd2, 32'd21);
        set_wb(2, 32'h0000100c, 5'd3, 32'd21);
        set_wb(3, 32'h00001010, 5'd4, 32'd22);
        set_wb(4, 32'h00001014, 5'd5, 32'd21);
        set_wb(5, 32'h00001024, 5'd9, 32'd7);
        set_wb(6, 32'h0000102c, 5'd10, 32'd7);
        set_wb(7, 32'h00001030, 5'd11, 32'd8);

        // The wrong-path Store at PC 0x1020 must never commit.
        set_store(0, 32'h00001008, 32'd64, 32'd21);
        set_store(1, 32'h00001028, 32'd72, 32'd7);
        set_store(2, 32'h00001034, 32'd76, 32'd8);

        repeat (4) @(negedge clk);
        rst = 1'b0;
        if_delivery_allow = 1'b1;
    end

    always @(posedge clk) begin
        if (rst) begin
            prev_load_use_stall = 1'b0;
        end else begin
            cycles = cycles + 1;

            if (fetch_error_fire)
                fail("unexpected instruction-fetch error");

            if (mem_fault_valid)
                fail("unexpected data-memory fault");

            if (mem_stall)
                mem_stall_cycles = mem_stall_cycles + 1;

            if (if_resp_hold) begin
                if_resp_held_cycles = if_resp_held_cycles + 1;
                if (mem_stall)
                    if_resp_held_during_mem = if_resp_held_during_mem + 1;
            end

            // Count hazard episodes separately from the number of cycles
            // for which the level-sensitive request remains asserted.
            if (load_use_stall)
                load_use_cycles = load_use_cycles + 1;

            if (load_use_stall && !prev_load_use_stall) begin
                load_use_count = load_use_count + 1;
                $display("LOAD_USE_EVENT[%0d] @%0t", load_use_count, $time);
            end
            prev_load_use_stall = load_use_stall;

            if (id_unsupported)
                unsupported_count = unsupported_count + 1;

            if (mem_stall && if_ready)
                fail("IF ready must be low during MEM backpressure");

            if (mem_stall && branch_redirect)
                fail("branch redirect must wait until the older MEM transaction completes");

            if (dmem_req_fire) begin
                req_count = req_count + 1;
                if (req_outstanding)
                    fail("a second DMEM request was accepted while one was outstanding");
                req_outstanding = 1'b1;
            end

            if (dmem_resp_fire) begin
                resp_count = resp_count + 1;
                if (!req_outstanding)
                    fail("DMEM response without a previously accepted request");
                req_outstanding = 1'b0;
            end

            if (branch_resolve_valid)
                branch_resolve_count = branch_resolve_count + 1;

            if (branch_redirect) begin
                branch_count = branch_count + 1;
                if (branch_redirect_pc !== 32'h00001024)
                    fail("branch target must be 0x00001024");
            end

            if (wb_commit_valid) begin
                if (wb_count >= N_WB) begin
                    fail("unexpected extra WB: possible duplicate or wrong-path commit");
                end else if (wb_commit_pc !== exp_wb_pc[wb_count] ||
                             wb_commit_rd !== exp_wb_rd[wb_count] ||
                             wb_commit_data !== exp_wb_data[wb_count]) begin
                    $display("WB mismatch[%0d]: got PC=%h rd=%0d data=%h; expected PC=%h rd=%0d data=%h",
                        wb_count, wb_commit_pc, wb_commit_rd, wb_commit_data,
                        exp_wb_pc[wb_count], exp_wb_rd[wb_count], exp_wb_data[wb_count]);
                    fail("WB order/data mismatch");
                end
                wb_count = wb_count + 1;
            end

            if (mem_store_commit_valid) begin
                if (store_count >= N_STORE) begin
                    fail("unexpected extra Store commit: possible duplicate or wrong-path Store");
                end else if (mem_store_commit_pc !== exp_st_pc[store_count] ||
                             mem_store_commit_addr !== exp_st_addr[store_count] ||
                             mem_store_commit_data !== exp_st_data[store_count]) begin
                    $display("STORE mismatch[%0d]: got PC=%h addr=%h data=%h; expected PC=%h addr=%h data=%h",
                        store_count, mem_store_commit_pc, mem_store_commit_addr,
                        mem_store_commit_data, exp_st_pc[store_count],
                        exp_st_addr[store_count], exp_st_data[store_count]);
                    fail("Store order/address/data mismatch");
                end
                store_count = store_count + 1;
            end

            if (cycles > 5000) begin
                $display("TIMEOUT WB=%0d/%0d STORE=%0d/%0d REQ=%0d RESP=%0d BR=%0d LOAD_USE_EVENTS=%0d LOAD_USE_CYCLES=%0d",
                    wb_count, N_WB, store_count, N_STORE, req_count, resp_count,
                    branch_count, load_use_count, load_use_cycles);
                $fatal(1, "V0.7 stress regression timeout");
            end

            if (wb_count == N_WB &&
                store_count == N_STORE &&
                branch_count == 1 &&
                unsupported_count == 1)
                after_done = after_done + 1;
            else
                after_done = 0;

            if (after_done == 60) begin
                if (req_count != 6 || resp_count != 6 || req_outstanding)
                    fail("DMEM request/response count or outstanding-state mismatch");

                if (branch_resolve_count != 1 || branch_response_hold_cycles == 0)
                    fail("branch IF response was not held while the older Load stalled in MEM");

                if (mem_stall_cycles == 0 ||
                    if_resp_held_cycles == 0 ||
                    if_resp_held_during_mem == 0)
                    fail("expected MEM backpressure and held I-Cache response coverage");

                if (wb_count != N_WB || store_count != N_STORE ||
                    branch_count != 1 || unsupported_count != 1)
                    fail("final architectural event counts mismatch");

                if (dut.u_cpu.u_dmem.mem[16] !== 32'd21 ||
                    dut.u_cpu.u_dmem.mem[17] !== 32'd0 ||
                    dut.u_cpu.u_dmem.mem[18] !== 32'd7 ||
                    dut.u_cpu.u_dmem.mem[19] !== 32'd8)
                    fail("final DMEM contents mismatch");

                if (dut.u_cpu.u_regfile.regs[8] !== 32'd0)
                    fail("wrong-path ADDI wrote register r8");

                $display("V0.7 STRESS RESULT:");
                $display("WB=%0d/%0d STORE=%0d/%0d DMEM_REQ=%0d DMEM_RESP=%0d",
                    wb_count, N_WB, store_count, N_STORE, req_count, resp_count);
                $display("BRANCH=%0d BRANCH_RESPONSE_HELD_DURING_LOAD=%0d",
                    branch_count, branch_response_hold_cycles);
                $display("LOAD_USE_EVENTS_OBSERVED=%0d LOAD_USE_HIGH_CYCLES=%0d (see datapath test for natural hazard coverage)",
                    load_use_count, load_use_cycles);
                $display("MEM_STALL_CYCLES=%0d IF_RESP_HELD=%0d IF_RESP_HELD_DURING_MEM=%0d",
                    mem_stall_cycles, if_resp_held_cycles, if_resp_held_during_mem);
                $display("CACHE_HITS=%0d CACHE_MISSES=%0d REFILL_WORDS=%0d BACKING_TXNS=%0d",
                    cache_hits, cache_misses, cache_refills, backing_transactions);
                $display("UNSUPPORTED=%0d ERRORS=%0d", unsupported_count, errors);

                if (errors == 0)
                    $display("ALL TESTS PASSED (V0.7 independent MEM stress regression)");
                else
                    $display("TESTS FAILED errors=%0d", errors);

                $finish;
            end
        end
    end

    // Check EX/MEM payload stability. On the targeted branch scenario,
    // PC=0x1014 Load must remain in MEM while PC=0x1018 Branch is in EX.
    always @(negedge clk) begin
        if (!rst) begin
            if (old_mem_stall &&
                (dut.u_cpu.mem_valid !== old_mem_valid ||
                 dut.u_cpu.mem_pc !== old_mem_pc ||
                 dut.u_cpu.mem_alu_result !== old_mem_addr ||
                 dut.u_cpu.mem_store_data !== old_mem_store_data ||
                 dut.u_cpu.mem_rd_addr !== old_mem_rd ||
                 dut.u_cpu.mem_mem_read !== old_mem_read ||
                 dut.u_cpu.mem_mem_write !== old_mem_write ||
                 dut.u_cpu.mem_reg_write !== old_mem_reg_write))
                fail("EX/MEM payload changed during a multi-cycle MEM stall");

            // The full top has a single-outstanding IF adapter. When the
            // older Load stalls MEM, the younger branch response is held at
            // the adapter/CPU boundary rather than already resident in EX.
            if (mem_stall &&
                dut.u_cpu.mem_valid &&
                dut.u_cpu.mem_mem_read &&
                dut.u_cpu.mem_pc == 32'h00001014 &&
                if_resp_hold &&
                if_resp_pc == 32'h00001018) begin
                branch_response_hold_cycles = branch_response_hold_cycles + 1;
            end

            old_mem_stall = mem_stall;
            old_mem_valid = dut.u_cpu.mem_valid;
            old_mem_pc = dut.u_cpu.mem_pc;
            old_mem_addr = dut.u_cpu.mem_alu_result;
            old_mem_store_data = dut.u_cpu.mem_store_data;
            old_mem_rd = dut.u_cpu.mem_rd_addr;
            old_mem_read = dut.u_cpu.mem_mem_read;
            old_mem_write = dut.u_cpu.mem_mem_write;
            old_mem_reg_write = dut.u_cpu.mem_reg_write;
        end
    end
endmodule
