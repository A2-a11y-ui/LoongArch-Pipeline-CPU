`timescale 1ns / 1ps
// Fair fetch-only comparison: two independent copies of identical LATENCY=3
// backing memory. Same request trace, same memory contents, same clock.
// This tests fetch latency / throughput, NOT full-CPU CPI or FPGA Fmax.
module tb_icache_performance;
    reg clk, rst;
    reg d_req, c_req;
    reg [31:0] d_addr, c_addr;
    wire [31:0] d_inst, c_inst;
    wire d_ready, d_valid, d_stall;
    wire c_ready, c_valid, c_stall, c_hit;
    wire d_mem_req, c_mem_req;
    wire [31:0] d_mem_addr, c_mem_addr;
    wire d_mem_ready, c_mem_ready;
    wire [31:0] d_mem_data, c_mem_data;
    wire d_mem_valid, c_mem_valid;
    wire [31:0] d_transactions, c_transactions;
    wire [31:0] hits, misses, refills;
    integer checks, errors, cycles;
    integer direct_cycles, cached_cycles;
    integer i, trace_n;
    integer expected_hits, expected_misses;
    real speedup;
    reg [31:0] address;

    always #5 clk = ~clk;
    always @(posedge clk) begin
        if (rst) cycles = 0;
        else cycles = cycles + 1;
    end

    if_direct_latency direct_if (
        .clk(clk),.rst(rst),.req_valid(d_req),.req_addr(d_addr),
        .inst(d_inst),.ready(d_ready),.fetch_valid(d_valid),.stall(d_stall),
        .mem_req(d_mem_req),.mem_addr(d_mem_addr),
        .mem_ready(d_mem_ready),.mem_rdata(d_mem_data),
        .mem_addr_valid(d_mem_valid)
    );
    imem_latency #(.LATENCY(3)) direct_mem (
        .clk(clk),.rst(rst),.mem_req(d_mem_req),.mem_addr(d_mem_addr),
        .mem_ready(d_mem_ready),.mem_rdata(d_mem_data),
        .mem_addr_valid(d_mem_valid),.transactions(d_transactions)
    );
    icache_latency cache_if (
        .clk(clk),.rst(rst),.req_valid(c_req),.req_addr(c_addr),
        .inst(c_inst),.ready(c_ready),.fetch_valid(c_valid),
        .stall(c_stall),.hit(c_hit),
        .mem_req(c_mem_req),.mem_addr(c_mem_addr),
        .mem_ready(c_mem_ready),.mem_rdata(c_mem_data),
        .mem_addr_valid(c_mem_valid),
        .hit_count(hits),.miss_count(misses),.refill_words(refills)
    );
    imem_latency #(.LATENCY(3)) cache_mem (
        .clk(clk),.rst(rst),.mem_req(c_mem_req),.mem_addr(c_mem_addr),
        .mem_ready(c_mem_ready),.mem_rdata(c_mem_data),
        .mem_addr_valid(c_mem_valid),.transactions(c_transactions)
    );

    task verify;
        input condition;
        input [8*110-1:0] what;
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL: %0s", what);
            end
        end
    endtask

    task reset_all;
        begin
            @(negedge clk);
            rst=1; d_req=0; c_req=0; d_addr=0; c_addr=0;
            @(posedge clk);
            #1;
            rst=0;
            verify(hits == 0 && misses == 0 && refills == 0,
                   "cache counters cleared on reset");
            verify(d_transactions == 0 && c_transactions == 0,
                   "both backing memories reset their transaction counters");
        end
    endtask

    task direct_fetch;
        input [31:0] addr_in;
        integer start_cycle;
        integer waited;
        begin
            @(negedge clk);
            d_addr=addr_in;
            d_req=1;
            start_cycle=cycles;
            waited=0;
            #1;
            while (!d_ready && waited < 150) begin
                verify(d_stall === 1'b1,"uncached fetch stalls before response");
                @(negedge clk);
                #1;
                waited=waited+1;
            end
            verify(d_ready === 1'b1 && d_valid === 1'b1,
                   "uncached fetch completed and valid");
            verify(d_inst === (32'hA5000000 | (addr_in >> 2)),
                   "uncached instruction matches deterministic backing ROM");
            @(posedge clk);
            #1;
            direct_cycles=direct_cycles + cycles-start_cycle;
            d_req=0;
        end
    endtask

    task cached_fetch;
        input [31:0] addr_in;
        integer start_cycle;
        integer waited;
        begin
            @(negedge clk);
            c_addr=addr_in;
            c_req=1;
            start_cycle=cycles;
            waited=0;
            #1;
            while (!c_ready && waited < 500) begin
                verify(c_stall === 1'b1,"cache miss asserts stall until refill done");
                @(negedge clk);
                #1;
                waited=waited+1;
            end
            verify(c_ready === 1'b1 && c_valid === 1'b1,
                   "cache fetch completed and valid");
            verify(c_inst === (32'hA5000000 | (addr_in >> 2)),
                   "cached instruction matches SAME backing ROM data");
            @(posedge clk);
            #1;
            cached_cycles=cached_cycles + cycles-start_cycle;
            c_req=0;
        end
    endtask

    function [31:0] trace_addr;
        input integer pattern;
        input integer seq;
        begin
            case(pattern)
                0: trace_addr=(seq%32)*4; // 32-word sequential working set, 3 rounds
                1: trace_addr=(seq%4)*4; // 4-word hot loop, 16 rounds
                2: trace_addr=(seq%2 == 0) ? 32'h0 : 32'h100; // same-index thrash
                default: trace_addr=0;
            endcase
        end
    endfunction

    task run_case;
        input integer pattern;
        input integer n;
        input integer exp_hit;
        input integer exp_miss;
        begin
            reset_all;
            direct_cycles=0;
            cached_cycles=0;
            for(i=0;i<n;i=i+1) begin
                address=trace_addr(pattern,i);
                direct_fetch(address);
            end
            verify(d_transactions == n,
                   "uncached backing-memory transactions equal instruction count");
            for(i=0;i<n;i=i+1) begin
                address=trace_addr(pattern,i);
                cached_fetch(address);
            end
            verify(hits == exp_hit,"exact expected cache hit count");
            verify(misses == exp_miss,"exact expected cache miss count");
            verify(hits+misses == n,"one hit/miss outcome per valid request");
            verify(refills == exp_miss*4,"exactly four words per cache line refill");
            verify(c_transactions == exp_miss*4,
                   "cache backing traffic equals four words per miss");
            verify(direct_cycles>0 && cached_cycles>0,
                   "both paths have measured nonzero execution cycles");
            speedup = (direct_cycles * 1.0)/cached_cycles;
            $display("-----------------------------------------");
            $display("PATTERN %0d: fetches=%0d",pattern,n);
            $display("Baseline cycles=%0d, backing words=%0d",
                     direct_cycles,d_transactions);
            $display("Cached   cycles=%0d, backing words=%0d",
                     cached_cycles,c_transactions);
            $display("Hits=%0d Misses=%0d Refilled=%0d Hit rate=%0f%%",
                     hits,misses,refills,(hits*100.0)/n);
            $display("Fetch-only speedup (baseline/cache)=%0f",speedup);
            if(pattern==0 || pattern==1)
                verify(cached_cycles < direct_cycles,
                       "sequential or hot-loop cache has less fetch time");
            if(pattern==2)
                verify(cached_cycles > direct_cycles,
                       "conflict-thrashing cache is slower: no false speedup claims");
        end
    endtask

    task invalid_addresses;
        integer dtx, ctx;
        begin
            reset_all;
            @(negedge clk);
            dtx=d_transactions; ctx=c_transactions;
            d_req=1; c_req=1;
            d_addr=32'h00000400;
            c_addr=32'h00000003;
            #1;
            verify(d_ready && !d_valid && !d_stall && d_inst==0,
                   "direct IF: illegal address produces invalid without waiting");
            verify(c_ready && !c_valid && !c_stall && c_inst==0,
                   "cache IF: misaligned address produces invalid without waiting");
            @(posedge clk); #1;
            d_req=0; c_req=0;
            verify(d_transactions==dtx && c_transactions==ctx,
                   "invalid addresses create no backing traffic");
        end
    endtask

    initial begin
        clk=0; rst=0; d_req=0; c_req=0; d_addr=0; c_addr=0;
        checks=0;errors=0;cycles=0;
        // Pattern 0: 8 distinct lines, reuse without capacity evictions.
        run_case(0,96,88,8);
        // Pattern 1: one 16-byte cache line reused 64 times.
        run_case(1,64,63,1);
        // Pattern 2: addresses 0 and 0x100 alias same index, different tags.
        run_case(2,32,0,32);
        invalid_addresses;
        $display("=========================================");
        $display("Total checks = %0d",checks);
        $display("Total errors = %0d",errors);
        if(errors==0) $display("ALL TESTS PASSED");
        else $display("TEST FAILED");
        $finish;
    end
endmodule
