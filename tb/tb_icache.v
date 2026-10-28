`timescale 1ns / 1ps
// Self-checking, real imem backing ROM, cache miss/hit/stall/performance tests.
module tb_icache;
    reg clk, rst, req_valid;
    reg [31:0] req_addr;
    wire [31:0] inst, mem_addr, mem_rdata;
    wire ready, fetch_valid, stall, hit, mem_req, mem_addr_valid;
    wire [31:0] hit_count, miss_count, refill_words;
    integer checks, errors, i;
    integer seen_misses, seen_hits, seen_refill;

    always #5 clk = ~clk;

    icache dut (
        .clk(clk), .rst(rst),
        .req_valid(req_valid), .req_addr(req_addr),
        .inst(inst), .ready(ready), .fetch_valid(fetch_valid),
        .stall(stall), .hit(hit),
        .mem_addr(mem_addr), .mem_req(mem_req),
        .mem_rdata(mem_rdata), .mem_addr_valid(mem_addr_valid),
        .hit_count(hit_count), .miss_count(miss_count),
        .refill_words(refill_words)
    );
    imem mem (
        .addr(mem_addr), .inst(mem_rdata), .addr_valid(mem_addr_valid)
    );

    task verify;
        input condition;
        input [8*64-1:0] what;
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL %0s", what);
            end else
                $display("PASS %0s", what);
        end
    endtask

    // kind: 0=MISS, 1=HIT, 2=INVALID.
    task fetch;
        input [31:0] address;
        input [31:0] expected;
        input integer kind;
        integer waits;
        integer before_hits, before_misses, before_refill;
        begin
            @(negedge clk);
            req_addr = address;
            req_valid = 1'b1;
            before_hits = hit_count;
            before_misses = miss_count;
            before_refill = refill_words;
            waits = 0;
            #1;
            while (!ready && waits < 12) begin
                verify(stall === 1'b1, "stall is high until requested line filled");
                @(negedge clk);
                waits = waits + 1;
                #1;
            end
            verify(ready === 1'b1, "cache responds within bounded clocks");
            if (kind == 2) begin
                verify(fetch_valid === 1'b0 && inst === 32'b0,
                       "illegal instruction address returns invalid and zero");
                verify(waits == 0, "illegal address never triggers refill");
            end else begin
                verify(fetch_valid === 1'b1 && inst === expected,
                       "fetched instruction matches IMEM contents");
                verify(hit === 1'b1, "completed valid request has cached line");
                if (kind == 0)
                    verify(waits >= 4, "MISS incurs refill stall");
                else
                    verify(waits == 0, "HIT returns without refill stall");
            end
            // Consume the request at a positive edge; hit counting is clocked.
            @(posedge clk);
            #1;
            req_valid = 1'b0;
            if (kind == 0) begin
                verify(miss_count == before_misses + 1, "exactly one miss counted");
                verify(hit_count == before_hits, "miss service not double-counted as hit");
                verify(refill_words == before_refill + 4, "exactly four backing words read");
            end else if (kind == 1) begin
                verify(miss_count == before_misses, "hit incurs no miss");
                verify(hit_count == before_hits + 1, "hit counted exactly once");
                verify(refill_words == before_refill, "hit incurs no backing fetch");
            end else begin
                verify(miss_count == before_misses && hit_count == before_hits,
                       "invalid address not counted as hit/miss");
                verify(refill_words == before_refill,
                       "invalid address does not access backing memory");
            end
        end
    endtask

    initial begin
        clk=0; rst=1; req_valid=0; req_addr=0;
        checks=0; errors=0;
        #1;
        // TESTBENCH ONLY: seed all ROM words, no file path dependency.
        for (i=0; i<256; i=i+1)
            mem.mem[i] = 32'hA5000000 | i;
        @(posedge clk);
        #1;
        rst=0;
        verify(hit_count == 0 && miss_count == 0 && refill_words == 0,
               "reset counters to zero");
        verify(ready == 0 && stall == 0 && !mem_req,
               "idle: no request, no stall, no backing access");

        fetch(32'h00000000, 32'hA5000000, 0); // cold miss
        fetch(32'h00000004, 32'hA5000001, 1); // same line hit
        fetch(32'h00000008, 32'hA5000002, 1);
        fetch(32'h0000000C, 32'hA5000003, 1);
        fetch(32'h00000100, 32'hA5000040, 0); // same index as 0, different tag
        fetch(32'h00000104, 32'hA5000041, 1);
        fetch(32'h00000000, 32'hA5000000, 0); // conflict miss
        fetch(32'h00000010, 32'hA5000004, 0); // next line
        fetch(32'h000003FC, 32'hA50000FF, 0); // last legal word
        fetch(32'h00000400, 32'h00000000, 2); // out of 1 KiB
        fetch(32'h00000003, 32'h00000000, 2); // misaligned
        fetch(32'hFFFFFFFC, 32'h00000000, 2); // out of range
        fetch(32'h000003FC, 32'hA50000FF, 1); // last line hit
        fetch(32'h000003F8, 32'hA50000FE, 1);
        fetch(32'h00000100, 32'hA5000040, 0); // conflict with line at zero
        fetch(32'h00000000, 32'hA5000000, 0);
        verify(hit_count == 6 && miss_count == 7 && refill_words == 28,
               "hit/miss/refill aggregate counters");

        // Reset invalidates all cache lines: same address MUST miss again.
        @(negedge clk); rst=1;
        @(posedge clk); #1; rst=0;
        verify(hit_count == 0 && miss_count == 0 && refill_words == 0,
               "reset clears performance counters");
        fetch(32'h00000000, 32'hA5000000, 0);

        $display("---------------------------------------");
        $display("Total checks = %0d", checks);
        $display("Total errors = %0d", errors);
        $display("Hits = %0d, Misses = %0d, Refilled words = %0d",
                 hit_count, miss_count, refill_words);
        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("TEST FAILED");
        $finish;
    end
endmodule
