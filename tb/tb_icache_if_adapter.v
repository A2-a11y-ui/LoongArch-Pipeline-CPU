`timescale 1ns / 1ps
// Self-checking IF adapter + unchanged 2-way LRU Cache + 3-cycle backing ROM.
// V0.5.1: avoid zero-delay check race when deasserting redirect.
// Run in Vivado 2019.1: set this module as Simulation Top, then "run all".
module tb_icache_if_adapter;
    reg clk, rst;
    reg if_req_valid;
    reg [31:0] if_req_addr;
    wire if_req_ready;
    wire if_resp_valid;
    reg if_resp_ready;
    wire [31:0] if_resp_pc, if_resp_inst;
    wire if_resp_error;
    reg redirect;
    wire busy;
    wire mem_req;
    wire [31:0] mem_addr;
    wire mem_ready;
    wire [31:0] mem_rdata;
    wire mem_addr_valid;
    wire [31:0] hit_count,miss_count,refill_words,transactions;

    integer checks, errors, wait_cycles, i;
    reg [31:0] saved_pc, saved_inst;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    icache_if_adapter dut (
        .clk(clk),.rst(rst),
        .if_req_valid(if_req_valid),.if_req_addr(if_req_addr),
        .if_req_ready(if_req_ready),
        .if_resp_valid(if_resp_valid),.if_resp_ready(if_resp_ready),
        .if_resp_pc(if_resp_pc),.if_resp_inst(if_resp_inst),
        .if_resp_error(if_resp_error),
        .redirect(redirect),.busy(busy),
        .mem_req(mem_req),.mem_addr(mem_addr),
        .mem_ready(mem_ready),.mem_rdata(mem_rdata),
        .mem_addr_valid(mem_addr_valid),
        .cache_hit_count(hit_count),.cache_miss_count(miss_count),
        .cache_refill_words(refill_words)
    );
    imem_latency #(.LATENCY(3)) backing (
        .clk(clk),.rst(rst),
        .mem_req(mem_req),.mem_addr(mem_addr),
        .mem_ready(mem_ready),.mem_rdata(mem_rdata),
        .mem_addr_valid(mem_addr_valid),.transactions(transactions)
    );

    task verify;
        input condition;
        input [8*110-1:0] description;
        begin
            checks = checks+1;
            if (condition !== 1'b1) begin
                errors = errors+1;
                $display("FAIL [%0d]: %0s",checks,description);
            end else begin
                $display("PASS [%0d]: %0s",checks,description);
            end
        end
    endtask

    task reset_system;
        begin
            @(negedge clk);
            rst = 1'b1;
            if_req_valid = 1'b0;
            if_resp_ready = 1'b0;
            redirect = 1'b0;
            if_req_addr = 32'b0;
            @(posedge clk); #1;
            verify(!if_resp_valid && !busy,"reset clears adapter outstanding activity");
            verify(hit_count == 0 && miss_count == 0,"reset clears cache hit/miss counters");
            @(negedge clk); rst = 1'b0; #1;
            verify(if_req_ready,"idle after reset can accept requests");
        end
    endtask

    task send_request;
        input [31:0] address;
        begin
            @(negedge clk);
            verify(if_req_ready,"request channel ready before issue");
            if_req_addr = address;
            if_req_valid = 1'b1;
            @(posedge clk); #1;
            if_req_valid = 1'b0;
            verify(busy && !if_req_ready,"one accepted request occupies adapter");
        end
    endtask

    task wait_response;
        input [31:0] expected_address;
        input expected_error;
        begin
            wait_cycles = 0;
            @(negedge clk); #1;
            while (!if_resp_valid && wait_cycles < 200) begin
                verify(!if_req_ready,"cannot accept next request while pending");
                @(negedge clk); #1;
                wait_cycles = wait_cycles+1;
            end
            verify(if_resp_valid,"response available before timeout");
            if (if_resp_valid) begin
                verify(if_resp_pc === expected_address,"response PC matches request PC");
                verify(if_resp_error === expected_error,"response error flag correct");
                verify(if_resp_inst === (expected_error ? 32'b0 :
                       (32'hA5000000 | (expected_address >> 2))),
                       "response instruction data matches ROM or error zero");
            end
        end
    endtask

    task consume_response;
        begin
            @(negedge clk); if_resp_ready = 1'b1;
            @(posedge clk); #1;
            if_resp_ready = 1'b0;
            verify(!if_resp_valid && if_req_ready,"consumed response frees request channel");
        end
    endtask

    task pulse_redirect;
        begin
            @(negedge clk); redirect = 1'b1;
            #1;
            verify(!if_req_ready && !if_resp_valid,"redirect gates old request/response immediately");
            @(posedge clk); #1;
            redirect = 1'b0;
            #1; // Wait for combinational ready/valid to settle after redirect deassertion.
            verify(!if_resp_valid,"redirect invalidates response at rising edge");
        end
    endtask

    task wait_drain;
        begin
            wait_cycles = 0;
            @(negedge clk); #1;
            while (!if_req_ready && wait_cycles < 220) begin
                verify(!if_resp_valid,"draining old request never exposes stale instruction");
                @(negedge clk); #1;
                wait_cycles = wait_cycles+1;
            end
            verify(if_req_ready,"old transaction drained successfully");
            verify(!if_resp_valid,"no stale result after drain");
        end
    endtask

    initial begin
        rst=0; if_req_valid=0; if_req_addr=0;
        if_resp_ready=0; redirect=0;
        checks=0; errors=0; wait_cycles=0;
        reset_system;

        // CASE 1: cold miss; cache refill, correct PC and instruction.
        $display("CASE 1: cold miss");
        send_request(32'h00000000);
        wait_response(32'h00000000,1'b0);
        verify(miss_count==1 && refill_words==4 && transactions==4,
               "cold miss refills one 16-byte line");
        consume_response;

        // CASE 2: hit in same cache line, no extra backing traffic.
        $display("CASE 2: cache hit");
        send_request(32'h00000004);
        wait_response(32'h00000004,1'b0);
        verify(hit_count==1 && miss_count==1 && transactions==4,
               "hit requires no backing reads");
        consume_response;

        // CASE 3: response backpressure retains PC and instruction.
        $display("CASE 3: response backpressure");
        send_request(32'h00000008);
        wait_response(32'h00000008,1'b0);
        saved_pc=if_resp_pc; saved_inst=if_resp_inst;
        for (i=0; i<3; i=i+1) begin
            @(posedge clk); #1;
            verify(if_resp_valid && !if_req_ready,"response valid is held under backpressure");
            verify(if_resp_pc===saved_pc && if_resp_inst===saved_inst,
                   "response payload is stable under backpressure");
        end
        consume_response;

        // CASE 4: redirect during a cold miss, drain old refill silently.
        $display("CASE 4: redirect while cache miss in flight");
        send_request(32'h00000080);
        @(posedge clk); #1; // cache entered S_SEND from first miss cycle
        verify(busy && !if_resp_valid,"miss is pending before redirect");
        pulse_redirect;
        verify(busy,"redirect during miss transitions to drain");
        wait_drain;
        send_request(32'h00000100); // IF controller presents redirect PC
        wait_response(32'h00000100,1'b0);
        consume_response;
        verify(miss_count==3 && transactions==12,
               "old miss and new target refill exactly once each");

        // CASE 5: redirect flushes a response held by backpressure.
        $display("CASE 5: redirect while response is pending");
        send_request(32'h00000104);
        wait_response(32'h00000104,1'b0);
        pulse_redirect;
        verify(if_req_ready && !if_resp_valid,"redirect discards waiting result");
        send_request(32'h00000108);
        wait_response(32'h00000108,1'b0);
        consume_response;

        // CASE 6: out-of-range instruction address returns error, not valid data.
        $display("CASE 6: invalid address");
        send_request(32'h00000400);
        wait_response(32'h00000400,1'b1);
        consume_response;

        // CASE 7: reset during a miss clears pending request and memory.
        $display("CASE 7: reset while miss is pending");
        send_request(32'h00000180);
        @(posedge clk); #1;
        verify(busy && !if_resp_valid,"new miss pending before reset");
        reset_system;
        verify(transactions==0,"backing memory reset removes old transaction");
        send_request(32'h0000000C);
        wait_response(32'h0000000C,1'b0);
        consume_response;

        // CASE 8: redirect when idle blocks simultaneous stale request.
        $display("CASE 8: redirect has priority over request");
        @(negedge clk);
        redirect=1; if_req_valid=1; if_req_addr=32'h00000020;
        #1;
        verify(!if_req_ready,"no request accepted during redirect");
        @(posedge clk); #1;
        redirect=0; if_req_valid=0;
        #1; // Sample settled combinational if_req_ready.
        verify(if_req_ready && !busy,"redirect from idle leaves clean idle state");
        send_request(32'h00000024);
        wait_response(32'h00000024,1'b0);
        consume_response;

        // CASE 9: redirect asserted exactly as old cache response is ready.
        $display("CASE 9: redirect at legacy cache completion edge");
        send_request(32'h00000200);
        wait_cycles=0;
        @(negedge clk); #1;
        while (!dut.u_icache.ready && wait_cycles<200) begin
            @(negedge clk); #1;
            wait_cycles=wait_cycles+1;
        end
        verify(dut.u_icache.ready,"legacy cache reached completion edge");
        verify(!if_resp_valid,"old result not published before edge");
        redirect=1'b1;
        #1;
        verify(!if_resp_valid,"redirect gates final-cycle old result");
        @(posedge clk); #1;
        redirect=1'b0;
        #1; // Sample settled combinational if_req_ready.
        verify(if_req_ready && !if_resp_valid,
               "completion-edge redirect frees IF without publishing stale response");
        send_request(32'h00000204);
        wait_response(32'h00000204,1'b0);
        consume_response;

        $display("==========================================");
        $display("Total checks = %0d",checks);
        $display("Total errors = %0d",errors);
        $display("Cache hits=%0d misses=%0d refill words=%0d",
                 hit_count,miss_count,refill_words);
        if (errors==0) $display("ALL TESTS PASSED");
        else           $display("TESTS FAILED");
        $finish;
    end
    initial begin
        #80000;
        $display("FATAL TIMEOUT: tests did not complete");
        $finish;
    end
endmodule
