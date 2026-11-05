`timescale 1ns / 1ps
// V0.9 PR #41 independent directed verification of the *actual* IF adapter
// plus the unchanged icache_2way_latency RTL. No production RTL modifications.
// Verilog-2001; run as Simulation Top in Vivado 2019.1.
// The simple backing ROM model below is for simulation ONLY.
module tb_v09_adapter_redirect_states;
    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_WAIT  = 2'd1;
    localparam [1:0] ST_RESP  = 2'd2;
    localparam [1:0] ST_DRAIN = 2'd3;

    reg clk, rst, if_req_valid, if_resp_ready, redirect;
    reg [31:0] if_req_addr;
    wire if_req_ready, if_resp_valid, if_resp_error, busy;
    wire [31:0] if_resp_pc, if_resp_inst;
    wire mem_req, mem_ready, mem_addr_valid;
    wire [31:0] mem_addr, mem_rdata;
    wire [31:0] cache_hit_count, cache_miss_count, cache_refill_words;
    wire [31:0] backing_transactions;

    integer checks, errors, cases, wait_cycles;
    integer accepted, expected_count, before_accepted, i;
    reg [31:0] expected_pc [0:15];
    reg        expected_error [0:15];
    reg [31:0] held_pc, held_inst;
    reg held_error;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    icache_if_adapter dut (
        .clk(clk), .rst(rst),
        .if_req_valid(if_req_valid), .if_req_addr(if_req_addr),
        .if_req_ready(if_req_ready),
        .if_resp_valid(if_resp_valid), .if_resp_ready(if_resp_ready),
        .if_resp_pc(if_resp_pc), .if_resp_inst(if_resp_inst),
        .if_resp_error(if_resp_error),
        .redirect(redirect), .busy(busy),
        .mem_req(mem_req), .mem_addr(mem_addr),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata),
        .mem_addr_valid(mem_addr_valid),
        .cache_hit_count(cache_hit_count),
        .cache_miss_count(cache_miss_count),
        .cache_refill_words(cache_refill_words)
    );

    v09_adapter_backing_rom #(.LATENCY(3)) backing (
        .clk(clk), .rst(rst), .mem_req(mem_req), .mem_addr(mem_addr),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata),
        .mem_addr_valid(mem_addr_valid), .transactions(backing_transactions)
    );

    task verify;
        input condition;
        input [8*128-1:0] description;
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                errors = errors + 1;
                $display("V09 ADAPTER FAIL check=%0d time=%0t: %0s", checks, $time, description);
            end
        end
    endtask

    // Architectural IF acceptance scoreboard: ONLY a valid/ready clock-edge
    // handshake may retire an IF response. Stale responses are never expected.
    always @(posedge clk) begin
        if (!rst && if_resp_valid && if_resp_ready) begin
            if (accepted >= expected_count) begin
                errors = errors + 1;
                $display("V09 ADAPTER FAIL unexpected IF response pc=%h time=%0t", if_resp_pc, $time);
            end else begin
                checks = checks + 1;
                if (if_resp_pc !== expected_pc[accepted] ||
                    if_resp_error !== expected_error[accepted] ||
                    if_resp_inst !== (expected_error[accepted] ? 32'h0 :
                                      (32'hA5000000 | (expected_pc[accepted] >> 2)))) begin
                    errors = errors + 1;
                    $display("V09 ADAPTER FAIL IF[%0d] got pc=%h inst=%h err=%b expected pc=%h err=%b",
                             accepted, if_resp_pc, if_resp_inst, if_resp_error,
                             expected_pc[accepted], expected_error[accepted]);
                end
            end
            accepted = accepted + 1;
        end
    end

    task issue;
        input [31:0] addr;
        begin
            @(negedge clk); #1;
            verify(if_req_ready && !if_resp_valid, "request slot available before issue");
            if_req_addr = addr;
            if_req_valid = 1'b1;
            @(posedge clk); #1;
            if_req_valid = 1'b0;
            verify(dut.state == ST_WAIT && busy && !if_req_ready,
                   "one request accepted, adapter enters ST_WAIT");
        end
    endtask

    task await_response;
        input [31:0] addr;
        input error_expected;
        integer n;
        begin
            n = 0;
            @(negedge clk); #1;
            while (!if_resp_valid && n < 220) begin
                verify(!if_req_ready, "outstanding request blocks new requests");
                @(negedge clk); #1;
                n = n + 1;
            end
            verify(if_resp_valid && dut.state == ST_RESP,
                   "expected IF response became valid before timeout");
            if (if_resp_valid) begin
                verify(if_resp_pc === addr, "response has correct PC");
                verify(if_resp_error === error_expected, "response error flag matches");
                verify(if_resp_inst === (error_expected ? 32'h0 :
                       (32'hA5000000 | (addr >> 2))), "response instruction matches backing ROM");
            end
        end
    endtask

    task consume_response;
        input [31:0] addr;
        input error_expected;
        integer n;
        begin
            verify(expected_count < 16, "expected response table has capacity");
            if (expected_count < 16) begin
                expected_pc[expected_count] = addr;
                expected_error[expected_count] = error_expected;
                expected_count = expected_count + 1;
            end
            @(negedge clk);
            if_resp_ready = 1'b1;
            @(posedge clk); #1;
            if_resp_ready = 1'b0;
            verify(accepted == expected_count, "one and only one response consumed");
            verify(dut.state == ST_IDLE && !if_resp_valid && if_req_ready,
                   "response handshake releases IF request slot");
            for (n=0; n<2; n=n+1) begin
                @(posedge clk); #1;
                verify(!if_resp_valid && accepted == expected_count,
                       "no duplicate IF response after consumption");
            end
        end
    endtask

    task redirect_pulse;
        begin
            @(negedge clk);
            redirect = 1'b1;
            #1;
            verify(!if_req_ready && !if_resp_valid,
                   "redirect immediately masks request and response handshakes");
            @(posedge clk); #1;
            redirect = 1'b0;
            #1;
            verify(!if_resp_valid, "no stale response after redirect edge");
        end
    endtask

    task wait_for_idle_after_drain;
        integer n;
        begin
            n = 0;
            @(negedge clk); #1;
            while (!if_req_ready && n < 220) begin
                verify(!if_resp_valid, "draining old cache transaction does not publish stale IF response");
                verify(dut.state == ST_DRAIN, "adapter remains in ST_DRAIN until old cache completion");
                @(negedge clk); #1;
                n = n + 1;
            end
            verify(if_req_ready && dut.state == ST_IDLE,
                   "old cache request drains to idle before timeout");
            verify(!if_resp_valid, "drain completion does not publish old instruction");
        end
    endtask

    initial begin
        rst = 1'b1;
        if_req_valid = 1'b0;
        if_req_addr = 32'h0;
        if_resp_ready = 1'b0;
        redirect = 1'b0;
        checks = 0;
        errors = 0;
        cases = 0;
        accepted = 0;
        expected_count = 0;
        before_accepted = 0;
        wait_cycles = 0;
        repeat (3) @(posedge clk);
        #1;
        @(negedge clk); rst = 1'b0; #1;
        verify(if_req_ready && !if_resp_valid, "reset leaves empty adapter");

        // CASE 1: cold miss then cache hit, both with exact IF response data.
        cases = cases + 1;
        $display("V09 ADAPTER CASE 1: baseline cold miss + hit");
        issue(32'h00000000);
        await_response(32'h00000000,1'b0);
        consume_response(32'h00000000,1'b0);
        verify(cache_miss_count == 1 && cache_refill_words == 4,
               "one cold miss refills exactly one line");
        issue(32'h00000004);
        await_response(32'h00000004,1'b0);
        consume_response(32'h00000004,1'b0);
        verify(cache_hit_count >= 1, "second fetch hits cache");

        // CASE 2: ST_RESP must hold an unconsumed response, including data.
        cases = cases + 1;
        $display("V09 ADAPTER CASE 2: ST_RESP under downstream backpressure");
        issue(32'h00000008);
        await_response(32'h00000008,1'b0);
        held_pc = if_resp_pc;
        held_inst = if_resp_inst;
        held_error = if_resp_error;
        for (i=0; i<5; i=i+1) begin
            @(posedge clk); #1;
            verify(dut.state == ST_RESP && if_resp_valid && !if_req_ready,
                   "ST_RESP remains valid while IF ready is low");
            verify(if_resp_pc === held_pc && if_resp_inst === held_inst &&
                   if_resp_error === held_error, "response data remains stable under backpressure");
        end
        consume_response(32'h00000008,1'b0);

        // CASE 3: redirect in ST_RESP, even if IF ready is high that cycle.
        cases = cases + 1;
        $display("V09 ADAPTER CASE 3: ST_RESP redirect masks simultaneous consume");
        issue(32'h0000000C);
        await_response(32'h0000000C,1'b0);
        held_pc = if_resp_pc;
        held_inst = if_resp_inst;
        held_error = if_resp_error;
        before_accepted = accepted;
        @(negedge clk);
        redirect = 1'b1;
        if_resp_ready = 1'b1;
        #1;
        verify(!if_resp_valid && !if_req_ready,
               "redirect suppresses same-cycle ST_RESP acceptance");
        @(posedge clk); #1;
        redirect = 1'b0;
        if_resp_ready = 1'b0;
        #1;
        verify(dut.state == ST_IDLE && !if_resp_valid && accepted == before_accepted,
               "ST_RESP redirect discards old response without retirement");
        verify(if_resp_pc === held_pc && if_resp_inst === held_inst &&
               if_resp_error === held_error,
               "optimized redirect retains payload register while invalidating response");
        issue(32'h00000100);
        await_response(32'h00000100,1'b0);
        consume_response(32'h00000100,1'b0);

        // CASE 4: redirect in ST_WAIT with a miss; old transaction must drain.
        cases = cases + 1;
        $display("V09 ADAPTER CASE 4: ST_WAIT miss redirect, drain old response");
        issue(32'h00000080);
        verify(dut.state == ST_WAIT && !dut.cache_ready,
               "old miss is not complete before redirect");
        before_accepted = accepted;
        redirect_pulse;
        verify(dut.state == ST_DRAIN, "ST_WAIT redirect while cache busy enters ST_DRAIN");
        wait_for_idle_after_drain;
        verify(accepted == before_accepted, "drained response never retired");
        issue(32'h00000200);
        await_response(32'h00000200,1'b0);
        consume_response(32'h00000200,1'b0);

        // CASE 5: a second redirect while already in ST_DRAIN.
        cases = cases + 1;
        $display("V09 ADAPTER CASE 5: repeated redirect during ST_DRAIN");
        issue(32'h00000180);
        redirect_pulse;
        verify(dut.state == ST_DRAIN && !dut.cache_ready,
               "adapter is draining an unfinished old miss");
        before_accepted = accepted;
        redirect_pulse;
        verify(dut.state == ST_DRAIN,
               "repeated redirect cannot reopen request acceptance prematurely");
        wait_for_idle_after_drain;
        verify(accepted == before_accepted, "repeated redirect did not retire old response");
        issue(32'h00000204);
        await_response(32'h00000204,1'b0);
        consume_response(32'h00000204,1'b0);

        // CASE 6: redirect exactly on a new miss's cache_ready completion edge.
        cases = cases + 1;
        $display("V09 ADAPTER CASE 6: ST_WAIT redirect at cache completion edge");
        issue(32'h00000280);
        wait_cycles = 0;
        @(negedge clk); #1;
        while (!(dut.state == ST_WAIT && dut.cache_ready) && wait_cycles < 220) begin
            verify(!if_resp_valid, "miss not prematurely published before cache completion");
            @(negedge clk); #1;
            wait_cycles = wait_cycles + 1;
        end
        verify(dut.state == ST_WAIT && dut.cache_ready,
               "cache completion observed while adapter still in ST_WAIT");
        before_accepted = accepted;
        redirect = 1'b1;
        #1;
        verify(!if_resp_valid, "completion-edge redirect gates old response");
        @(posedge clk); #1;
        redirect = 1'b0;
        #1;
        verify(dut.state == ST_IDLE && !if_resp_valid && accepted == before_accepted,
               "ST_WAIT completion-edge redirect does not publish old response");
        issue(32'h00000284);
        await_response(32'h00000284,1'b0);
        consume_response(32'h00000284,1'b0);

        // CASE 7: ST_WAIT with cache HIT ready, same-cycle redirect wins.
        cases = cases + 1;
        $display("V09 ADAPTER CASE 7: ST_WAIT cache hit ready + redirect");
        issue(32'h00000288);
        @(negedge clk); #1;
        verify(dut.state == ST_WAIT && dut.cache_ready && dut.u_icache.hit,
               "warm cache hit is ready while adapter in ST_WAIT");
        before_accepted = accepted;
        redirect = 1'b1;
        #1;
        verify(!if_resp_valid, "redirect masks cache-hit response");
        @(posedge clk); #1;
        redirect = 1'b0;
        #1;
        verify(dut.state == ST_IDLE && !if_resp_valid && accepted == before_accepted,
               "cache-hit redirect discards old-path instruction");
        issue(32'h0000028C);
        await_response(32'h0000028C,1'b0);
        consume_response(32'h0000028C,1'b0);

        // CASE 8: redirect at idle beats simultaneous request; error response.
        cases = cases + 1;
        $display("V09 ADAPTER CASE 8: ST_IDLE redirect priority, invalid PC error");
        @(negedge clk);
        redirect = 1'b1;
        if_req_valid = 1'b1;
        if_req_addr = 32'h00000300;
        #1;
        verify(!if_req_ready && !if_resp_valid, "ST_IDLE redirect masks simultaneous request");
        @(posedge clk); #1;
        redirect = 1'b0;
        if_req_valid = 1'b0;
        #1;
        verify(dut.state == ST_IDLE && if_req_ready,
               "redirected ST_IDLE does not capture wrong-path request");
        issue(32'h00000400);
        await_response(32'h00000400,1'b1);
        consume_response(32'h00000400,1'b1);

        verify(cases == 8, "all eight directed cases executed");
        verify(accepted == 9 && expected_count == 9,
               "exactly nine authorized IF responses; no missing/duplicate/stale retirement");
        verify(cache_hit_count > 0 && cache_miss_count > 0 && cache_refill_words > 0,
               "real Cache RTL exercised both hit and miss/refill paths");
        $display("------------------------------------------------------------");
        $display("V09 ADAPTER REDIRECT RESULT CASES=%0d CHECKS=%0d ACCEPTED=%0d/9 HITS=%0d MISSES=%0d ERRORS=%0d",
                 cases, checks, accepted, cache_hit_count, cache_miss_count, errors);
        if (errors == 0)
            $display("ALL TESTS PASSED (V0.9 adapter + real I-Cache, directed simulation only)");
        else
            $display("TESTS FAILED (V0.9 adapter redirect directed verification)");
        $finish;
    end

    initial begin
        #20000;
        $display("FAIL: TIMEOUT in V09 Adapter Redirect verification");
        $finish;
    end
endmodule

// Simulation-only fixed-latency ROM. Synthesizable design uses the official
// imem_bram; THIS TEST MODEL must not be used as production FPGA RTL.
module v09_adapter_backing_rom #(
    parameter integer LATENCY = 3
) (
    input wire clk, input wire rst,
    input wire mem_req, input wire [31:0] mem_addr,
    output reg mem_ready, output reg [31:0] mem_rdata,
    output reg mem_addr_valid, output reg [31:0] transactions
);
    reg busy;
    reg [31:0] pending_addr;
    integer remaining;
    wire legal = (pending_addr[31:10] == 22'b0) &&
                 (pending_addr[1:0] == 2'b00);
    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            pending_addr <= 32'h0;
            remaining <= 0;
            mem_ready <= 1'b0;
            mem_rdata <= 32'h0;
            mem_addr_valid <= 1'b0;
            transactions <= 32'h0;
        end else begin
            mem_ready <= 1'b0;
            if (!busy && mem_req) begin
                busy <= 1'b1;
                pending_addr <= mem_addr;
                remaining <= LATENCY;
                transactions <= transactions + 1;
            end else if (busy) begin
                if (remaining <= 1) begin
                    busy <= 1'b0;
                    mem_ready <= 1'b1;
                    mem_addr_valid <= legal;
                    mem_rdata <= legal ? (32'hA5000000 | (pending_addr >> 2)) : 32'h0;
                end else begin
                    remaining <= remaining - 1;
                end
            end
        end
    end
endmodule
