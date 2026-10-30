`timescale 1ns / 1ps
// Independent V0.5 I-Cache + CPU response-hold / load-use-shaped stall test.
// Vivado 2019.1, Verilog-2001. Production RTL is not modified.
//
// IMPORTANT ARCHITECTURAL LIMIT:
// icache_if_adapter is single-outstanding and returns one instruction only
// after request -> cache completion -> response handshake. Therefore this
// V0.5 integration cannot naturally sustain one instruction/cycle on hits;
// true adjacent Load-use detection is covered by the existing V0.3/V0.4 CPU
// regressions. Here we inject the existing interlock wires for two cycles
// while selected cache responses are pending, verifying response retention,
// IF/ID hold, ID/EX bubble, and exactly-once delivery.
module tb_pipeline_cpu_v05_loaduse;

    parameter MEM_FILE =
        "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/v05_loaduse.mem";

    localparam [31:0] PC_BASE = 32'h00001000;
    localparam integer WORDS = 8;
    localparam integer N_WB = 6;
    localparam integer N_STORES = 2;

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
    wire wb_commit_valid;
    wire [31:0] wb_commit_pc, wb_commit_data;
    wire [4:0] wb_commit_rd;
    wire mem_store_commit_valid;
    wire [31:0] mem_store_commit_pc, mem_store_commit_addr;
    wire [31:0] mem_store_commit_data;

    pipeline_cpu_core_v05 #(
        .PC_BASE(PC_BASE),
        .PROGRAM_WORDS(WORDS),
        .IMEM_LATENCY(3)
    ) dut (
        .clk(clk), .rst(rst), .if_delivery_allow(if_delivery_allow),
        .if_valid(if_valid), .if_pc(if_pc), .if_inst(if_inst),
        .if_ready(if_ready),
        .if_req_fire(if_req_fire), .if_req_pc(if_req_pc),
        .if_resp_fire(if_resp_fire), .if_resp_pc(if_resp_pc),
        .if_resp_hold(if_resp_hold), .fetch_error_fire(fetch_error_fire),
        .adapter_busy(adapter_busy),
        .cache_hits(cache_hits), .cache_misses(cache_misses),
        .cache_refills(cache_refills),
        .backing_transactions(backing_transactions),
        .branch_resolve_valid(branch_resolve_valid),
        .branch_redirect(branch_redirect),
        .branch_redirect_pc(branch_redirect_pc),
        .load_use_stall(load_use_stall),
        .id_unsupported(id_unsupported), .id_raw_hazard(id_raw_hazard),
        .wb_commit_valid(wb_commit_valid), .wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd), .wb_commit_data(wb_commit_data),
        .mem_store_commit_valid(mem_store_commit_valid),
        .mem_store_commit_pc(mem_store_commit_pc),
        .mem_store_commit_addr(mem_store_commit_addr),
        .mem_store_commit_data(mem_store_commit_data)
    );

    reg [31:0] rom [0:WORDS-1];
    reg [31:0] exp_wb_pc [0:N_WB-1];
    reg [4:0]  exp_wb_rd [0:N_WB-1];
    reg [31:0] exp_wb_data [0:N_WB-1];
    reg [31:0] exp_st_pc [0:N_STORES-1];
    reg [31:0] exp_st_addr [0:N_STORES-1];
    reg [31:0] exp_st_data [0:N_STORES-1];

    integer wb_count, store_count, delivered_count;
    integer request_count, response_count;
    integer response_held_cycles, forced_response_hold_cycles;
    integer forced_stall_events, forced_stall_cycles;
    integer natural_load_use_cycles, unsupported_count, errors;
    integer delivery_cycle, force_stall_remaining, fd, i;

    reg [2047:0] mem_path;
    reg request_outstanding;
    reg [31:0] outstanding_pc;
    reg request_held_prev;
    reg [31:0] request_pc_prev;
    reg response_valid_prev;
    reg [31:0] response_pc_prev, response_inst_prev;
    reg force_stall_active;
    reg last_word_delivered;
    reg finished;

    reg [31:0] id_pc_before, id_inst_before, ex_pc_before;
    reg id_valid_before, ex_valid_before;

    // Long initial response hold plus periodic downstream delivery pauses.
    // During the injected interlock, keep delivery_allow high so IF valid
    // remains asserted while IF ready is low (proper ready/valid behavior).
    always @(negedge clk) begin
        if (rst) begin
            delivery_cycle = 0;
            if_delivery_allow = 1'b0;
        end else begin
            delivery_cycle = delivery_cycle + 1;

            if (force_stall_active)
                if_delivery_allow = 1'b1;
            else if (delivery_cycle < 30)
                if_delivery_allow = 1'b0;
            else
                if_delivery_allow = ((delivery_cycle % 17) >= 5);

            // Inject a two-cycle interlock while the two dependent-instruction
            // responses are pending. This is a protocol stress, not a claim
            // that the serial adapter naturally generated a RAW hazard.
            if (!force_stall_active && forced_stall_events < 2 &&
                dut.adapter_resp_valid && if_delivery_allow &&
                ((if_resp_pc == 32'h00001008) ||
                 (if_resp_pc == 32'h00001014))) begin
                force dut.u_cpu.hold_if_req = 1'b1;
                force dut.u_cpu.hold_ifid_req = 1'b1;
                force dut.u_cpu.bubble_idex_req = 1'b1;
                force_stall_active = 1'b1;
                force_stall_remaining = 2;
                forced_stall_events = forced_stall_events + 1;
            end else if (force_stall_active) begin
                force_stall_remaining = force_stall_remaining - 1;
                if (force_stall_remaining == 0) begin
                    release dut.u_cpu.hold_if_req;
                    release dut.u_cpu.hold_ifid_req;
                    release dut.u_cpu.bubble_idex_req;
                    force_stall_active = 1'b0;
                end
            end
        end
    end

    // Scoreboard and protocol assertions; sample transaction outputs before
    // the rising-edge sequential updates.
    always @(posedge clk) begin
        if (!rst && !finished) begin

            if (fetch_error_fire) begin
                errors = errors + 1;
                $display("FAIL unexpected fetch error PC=%h", if_resp_pc);
            end

            if (branch_resolve_valid || branch_redirect) begin
                errors = errors + 1;
                $display("FAIL unexpected branch in this straight-line program");
            end

            if (if_resp_fire !== (if_valid && if_ready)) begin
                errors = errors + 1;
                $display("FAIL adapter response fire != CPU IF handshake");
            end

            if (request_held_prev && if_req_pc !== request_pc_prev) begin
                errors = errors + 1;
                $display("FAIL PC request address changed before acceptance");
            end
            request_held_prev = !if_req_fire;
            request_pc_prev = if_req_pc;

            if (if_req_fire) begin
                if (request_outstanding) begin
                    errors = errors + 1;
                    $display("FAIL multiple outstanding IF requests");
                end
                if (if_req_pc !== (PC_BASE + request_count * 4)) begin
                    errors = errors + 1;
                    $display("FAIL request[%0d] PC=%h expected=%h",
                        request_count, if_req_pc, PC_BASE + request_count * 4);
                end
                request_outstanding = 1'b1;
                outstanding_pc = if_req_pc;
                request_count = request_count + 1;
            end

            if (if_resp_fire) begin
                if (!request_outstanding || if_resp_pc !== outstanding_pc) begin
                    errors = errors + 1;
                    $display("FAIL response without matching outstanding request");
                end
                if (if_resp_pc !== (PC_BASE + response_count * 4)) begin
                    errors = errors + 1;
                    $display("FAIL response[%0d] PC=%h expected=%h",
                        response_count, if_resp_pc, PC_BASE + response_count * 4);
                end
                request_outstanding = 1'b0;
                response_count = response_count + 1;
            end

            // Adapter response PC and instruction must remain stable from
            // first valid until the eventual ready/valid handshake.
            if (dut.adapter_resp_valid) begin
                if (response_valid_prev &&
                    (if_resp_pc !== response_pc_prev ||
                     if_inst !== response_inst_prev)) begin
                    errors = errors + 1;
                    $display("FAIL pending adapter response payload changed");
                end
                response_valid_prev = 1'b1;
                response_pc_prev = if_resp_pc;
                response_inst_prev = if_inst;
            end else begin
                response_valid_prev = 1'b0;
            end

            if (if_resp_hold)
                response_held_cycles = response_held_cycles + 1;

            if (if_valid && if_ready) begin
                if (delivered_count >= WORDS) begin
                    errors = errors + 1;
                    $display("FAIL extra IF delivery PC=%h", if_pc);
                end else begin
                    if (if_pc !== (PC_BASE + delivered_count * 4) ||
                        if_inst !== rom[delivered_count]) begin
                        errors = errors + 1;
                        $display("FAIL IF[%0d] PC=%h INST=%h expected PC=%h INST=%h",
                            delivered_count, if_pc, if_inst,
                            PC_BASE + delivered_count * 4, rom[delivered_count]);
                    end
                    if (delivered_count == WORDS-1)
                        last_word_delivered = 1'b1;
                end
                delivered_count = delivered_count + 1;
            end

            if (id_unsupported)
                unsupported_count = unsupported_count + 1;

            // Actual detector output, separate from the forced interlock.
            if (dut.u_cpu.raw_load_use)
                natural_load_use_cycles = natural_load_use_cycles + 1;

            if (wb_commit_valid) begin
                if (wb_count >= N_WB) begin
                    errors = errors + 1;
                    $display("FAIL extra WB PC=%h rd=%0d data=%h",
                        wb_commit_pc, wb_commit_rd, wb_commit_data);
                end else if (wb_commit_pc !== exp_wb_pc[wb_count] ||
                             wb_commit_rd !== exp_wb_rd[wb_count] ||
                             wb_commit_data !== exp_wb_data[wb_count]) begin
                    errors = errors + 1;
                    $display("FAIL WB[%0d] got PC=%h rd=%0d data=%h expected PC=%h rd=%0d data=%h",
                        wb_count, wb_commit_pc, wb_commit_rd, wb_commit_data,
                        exp_wb_pc[wb_count], exp_wb_rd[wb_count],
                        exp_wb_data[wb_count]);
                end
                wb_count = wb_count + 1;
            end

            if (mem_store_commit_valid) begin
                if (store_count >= N_STORES) begin
                    errors = errors + 1;
                    $display("FAIL extra STORE PC=%h addr=%h data=%h",
                        mem_store_commit_pc, mem_store_commit_addr,
                        mem_store_commit_data);
                end else if (mem_store_commit_pc !== exp_st_pc[store_count] ||
                             mem_store_commit_addr !== exp_st_addr[store_count] ||
                             mem_store_commit_data !== exp_st_data[store_count]) begin
                    errors = errors + 1;
                    $display("FAIL STORE[%0d] got PC=%h addr=%h data=%h expected PC=%h addr=%h data=%h",
                        store_count, mem_store_commit_pc, mem_store_commit_addr,
                        mem_store_commit_data, exp_st_pc[store_count],
                        exp_st_addr[store_count], exp_st_data[store_count]);
                end
                store_count = store_count + 1;
            end

            if (force_stall_active) begin
                forced_stall_cycles = forced_stall_cycles + 1;
                if (load_use_stall !== 1'b1 || if_ready !== 1'b0 ||
                    if_valid !== 1'b1 || if_resp_hold !== 1'b1 ||
                    if_resp_fire !== 1'b0 ||
                    dut.ifid_stall_ctrl !== 1'b1 ||
                    dut.ifid_flush_ctrl !== 1'b0 ||
                    dut.idex_flush_ctrl !== 1'b1) begin
                    errors = errors + 1;
                    $display("FAIL injected interlock did not hold the pending response");
                end
                forced_response_hold_cycles = forced_response_hold_cycles + 1;

                id_pc_before = dut.u_cpu.id_pc;
                id_inst_before = dut.u_cpu.id_inst;
                id_valid_before = dut.u_cpu.id_valid;
                ex_pc_before = dut.u_cpu.ex_pc;
                ex_valid_before = dut.u_cpu.ex_valid;

                #1;
                if (dut.u_cpu.id_pc !== id_pc_before ||
                    dut.u_cpu.id_inst !== id_inst_before ||
                    dut.u_cpu.id_valid !== id_valid_before ||
                    dut.u_cpu.ex_valid !== 1'b0) begin
                    errors = errors + 1;
                    $display("FAIL injected interlock IF/ID hold or ID/EX bubble");
                end
                if (ex_valid_before &&
                    (!dut.u_cpu.mem_valid || dut.u_cpu.mem_pc !== ex_pc_before)) begin
                    errors = errors + 1;
                    $display("FAIL older EX instruction did not advance to MEM");
                end
            end
        end
    end

    initial begin
        wb_count = 0;
        store_count = 0;
        delivered_count = 0;
        request_count = 0;
        response_count = 0;
        response_held_cycles = 0;
        forced_response_hold_cycles = 0;
        forced_stall_events = 0;
        forced_stall_cycles = 0;
        natural_load_use_cycles = 0;
        unsupported_count = 0;
        errors = 0;
        delivery_cycle = 0;
        force_stall_remaining = 0;
        request_outstanding = 1'b0;
        outstanding_pc = 32'b0;
        request_held_prev = 1'b0;
        request_pc_prev = 32'b0;
        response_valid_prev = 1'b0;
        response_pc_prev = 32'b0;
        response_inst_prev = 32'b0;
        force_stall_active = 1'b0;
        last_word_delivered = 1'b0;
        finished = 1'b0;
        mem_path = MEM_FILE;

        if ($value$plusargs("MEM_FILE=%s", mem_path))
            $display("INFO using MEM_FILE: %0s", mem_path);

        fd = $fopen(mem_path, "r");
        if (fd == 0) begin
            $display("FAIL cannot open program file: %0s", mem_path);
            $finish;
        end
        $fclose(fd);

        exp_wb_pc[0] = 32'h00001000; exp_wb_rd[0] = 5'd1; exp_wb_data[0] = 32'h00000000;
        exp_wb_pc[1] = 32'h00001004; exp_wb_rd[1] = 5'd2; exp_wb_data[1] = 32'h00000007;
        exp_wb_pc[2] = 32'h00001008; exp_wb_rd[2] = 5'd3; exp_wb_data[2] = 32'h0000000A;
        exp_wb_pc[3] = 32'h00001010; exp_wb_rd[3] = 5'd4; exp_wb_data[3] = 32'h0000000A;
        exp_wb_pc[4] = 32'h00001014; exp_wb_rd[4] = 5'd5; exp_wb_data[4] = 32'h00000014;
        exp_wb_pc[5] = 32'h00001018; exp_wb_rd[5] = 5'd6; exp_wb_data[5] = 32'h00000015;

        exp_st_pc[0] = 32'h0000100C; exp_st_addr[0] = 32'h00000004; exp_st_data[0] = 32'h0000000A;
        exp_st_pc[1] = 32'h0000101C; exp_st_addr[1] = 32'h00000008; exp_st_data[1] = 32'h00000015;

        #1;
        $readmemh(mem_path, rom);
        $readmemh(mem_path, dut.u_imem.rom);

        for (i = 0; i < 256; i = i + 1)
            dut.u_cpu.u_dmem.mem[i] = 32'b0;
        dut.u_cpu.u_dmem.mem[0] = 32'd7;

        repeat (3) @(negedge clk);
        rst = 1'b0;

        wait(last_word_delivered &&
             wb_count >= N_WB &&
             store_count >= N_STORES);

        repeat (8) @(negedge clk);

        if (wb_count != N_WB || store_count != N_STORES) begin
            errors = errors + 1;
            $display("FAIL final WB/STORE event counts");
        end
        if (delivered_count != WORDS || request_count != WORDS ||
            response_count != WORDS || request_outstanding) begin
            errors = errors + 1;
            $display("FAIL IF counts delivered=%0d req=%0d resp=%0d outstanding=%b",
                delivered_count, request_count, response_count, request_outstanding);
        end
        if (forced_stall_events != 2 || forced_stall_cycles != 4 ||
            forced_response_hold_cycles != 4) begin
            errors = errors + 1;
            $display("FAIL injected stall coverage events=%0d cycles=%0d held=%0d",
                forced_stall_events, forced_stall_cycles, forced_response_hold_cycles);
        end
        if (response_held_cycles == 0) begin
            errors = errors + 1;
            $display("FAIL no adapter response hold observed");
        end
        if (cache_hits < 6 || cache_misses < 2 ||
            cache_refills != 8 || backing_transactions != 8) begin
            errors = errors + 1;
            $display("FAIL Cache coverage hits=%0d misses=%0d refills=%0d backing=%0d",
                cache_hits, cache_misses, cache_refills, backing_transactions);
        end
        if (unsupported_count != 0) begin
            errors = errors + 1;
            $display("FAIL unsupported instruction count=%0d", unsupported_count);
        end
        if (dut.u_cpu.u_dmem.mem[1] !== 32'h0000000A ||
            dut.u_cpu.u_dmem.mem[2] !== 32'h00000015) begin
            errors = errors + 1;
            $display("FAIL final DMEM mem[1]=%h mem[2]=%h",
                dut.u_cpu.u_dmem.mem[1], dut.u_cpu.u_dmem.mem[2]);
        end

        $display("------------------------------------------------------------");
        $display("V0.5 INDEPENDENT I-CACHE + INTERLOCK RESPONSE-HOLD REGRESSION");
        $display("IF: words=%0d delivered=%0d requests=%0d responses=%0d outstanding=%b",
            WORDS, delivered_count, request_count, response_count, request_outstanding);
        $display("CPU: WB=%0d/%0d STORE=%0d/%0d natural_load_use_cycles=%0d",
            wb_count, N_WB, store_count, N_STORES, natural_load_use_cycles);
        $display("INJECTED INTERLOCK: events=%0d cycles=%0d held_response_cycles=%0d",
            forced_stall_events, forced_stall_cycles, forced_response_hold_cycles);
        $display("CACHE: hits=%0d misses=%0d refill_words=%0d backing_transactions=%0d total_held_response_cycles=%0d",
            cache_hits, cache_misses, cache_refills, backing_transactions,
            response_held_cycles);
        $display("DMEM: mem[1]=%h mem[2]=%h",
            dut.u_cpu.u_dmem.mem[1], dut.u_cpu.u_dmem.mem[2]);
        $display("TOTAL ERRORS = %0d", errors);
        if (errors == 0)
            $display("ALL TESTS PASSED (V0.5 independent I-Cache/interlock response hold)");
        else
            $display("TESTS FAILED (V0.5 independent I-Cache/interlock response hold)");
        finished = 1'b1;
        $finish;
    end

    initial begin
        #20000;
        if (!finished) begin
            $display("FAIL TIMEOUT V0.5 INTERLOCK TEST: WB=%0d/%0d STORE=%0d/%0d IF=%0d/%0d",
                wb_count, N_WB, store_count, N_STORES, delivered_count, WORDS);
            $display("TOTAL ERRORS = %0d", errors + 1);
            $finish;
        end
    end

endmodule
