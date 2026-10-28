`timescale 1ns / 1ps
// Same trace / same LATENCY=3 backing model across three independent paths:
// direct IF, 256B direct-mapped, 256B two-way LRU I-Cache.
module tb_icache_2way_performance;
    reg clk, rst;
    reg d_req, one_req, two_req;
    reg [31:0] d_addr, one_addr, two_addr;
    wire [31:0] d_inst, one_inst, two_inst;
    wire d_ready,d_valid,d_stall;
    wire one_ready,one_valid,one_stall,one_hit;
    wire two_ready,two_valid,two_stall,two_hit;
    wire d_mem_req,one_mem_req,two_mem_req;
    wire [31:0] d_mem_addr,one_mem_addr,two_mem_addr;
    wire d_mem_ready,one_mem_ready,two_mem_ready;
    wire [31:0] d_mem_data,one_mem_data,two_mem_data;
    wire d_mem_valid,one_mem_valid,two_mem_valid;
    wire [31:0] d_transactions,one_transactions,two_transactions;
    wire [31:0] one_hits,one_misses,one_refills;
    wire [31:0] two_hits,two_misses,two_refills;
    integer checks,errors,cycles;
    integer d_cycles,one_cycles,two_cycles;
    integer i, waited;
    reg [31:0] addr;
    real d_to_one, d_to_two, two_vs_one;

    always #5 clk=~clk;
    always @(posedge clk) begin
        if(rst) cycles=0;
        else cycles=cycles+1;
    end

    if_direct_latency d_if (
        .clk(clk),.rst(rst),.req_valid(d_req),.req_addr(d_addr),
        .inst(d_inst),.ready(d_ready),.fetch_valid(d_valid),.stall(d_stall),
        .mem_addr(d_mem_addr),.mem_req(d_mem_req),
        .mem_ready(d_mem_ready),.mem_rdata(d_mem_data),.mem_addr_valid(d_mem_valid)
    );
    imem_latency #(.LATENCY(3)) d_mem (
        .clk(clk),.rst(rst),.mem_req(d_mem_req),.mem_addr(d_mem_addr),
        .mem_ready(d_mem_ready),.mem_rdata(d_mem_data),
        .mem_addr_valid(d_mem_valid),.transactions(d_transactions)
    );
    icache_latency one_if (
        .clk(clk),.rst(rst),.req_valid(one_req),.req_addr(one_addr),
        .inst(one_inst),.ready(one_ready),.fetch_valid(one_valid),
        .stall(one_stall),.hit(one_hit),
        .mem_addr(one_mem_addr),.mem_req(one_mem_req),
        .mem_ready(one_mem_ready),.mem_rdata(one_mem_data),
        .mem_addr_valid(one_mem_valid),
        .hit_count(one_hits),.miss_count(one_misses),.refill_words(one_refills)
    );
    imem_latency #(.LATENCY(3)) one_mem (
        .clk(clk),.rst(rst),.mem_req(one_mem_req),.mem_addr(one_mem_addr),
        .mem_ready(one_mem_ready),.mem_rdata(one_mem_data),
        .mem_addr_valid(one_mem_valid),.transactions(one_transactions)
    );
    icache_2way_latency two_if (
        .clk(clk),.rst(rst),.req_valid(two_req),.req_addr(two_addr),
        .inst(two_inst),.ready(two_ready),.fetch_valid(two_valid),
        .stall(two_stall),.hit(two_hit),
        .mem_addr(two_mem_addr),.mem_req(two_mem_req),
        .mem_ready(two_mem_ready),.mem_rdata(two_mem_data),
        .mem_addr_valid(two_mem_valid),
        .hit_count(two_hits),.miss_count(two_misses),.refill_words(two_refills)
    );
    imem_latency #(.LATENCY(3)) two_mem (
        .clk(clk),.rst(rst),.mem_req(two_mem_req),.mem_addr(two_mem_addr),
        .mem_ready(two_mem_ready),.mem_rdata(two_mem_data),
        .mem_addr_valid(two_mem_valid),.transactions(two_transactions)
    );

    task verify;
        input condition;
        input [8*120-1:0] what;
        begin
            checks=checks+1;
            if(condition !== 1'b1) begin
                errors=errors+1;
                $display("FAIL: %0s",what);
            end
        end
    endtask

    task reset_all;
        begin
            @(negedge clk);
            rst=1; d_req=0; one_req=0; two_req=0;
            d_addr=0; one_addr=0; two_addr=0;
            @(posedge clk); #1;
            rst=0;
            verify(d_transactions == 0 && one_transactions == 0 && two_transactions == 0,
                   "all backing-memory counters reset");
            verify(one_hits==0 && one_misses==0 && one_refills==0,
                   "direct-mapped counters reset");
            verify(two_hits==0 && two_misses==0 && two_refills==0,
                   "two-way counters reset");
        end
    endtask

    task direct_fetch;
        input [31:0] a;
        integer start_c, w;
        begin
            @(negedge clk); d_addr=a; d_req=1;
            start_c=cycles; w=0; #1;
            while(!d_ready && w<150) begin
                verify(d_stall===1'b1,"direct IF stalls until ready");
                @(negedge clk); #1; w=w+1;
            end
            verify(d_ready===1'b1 && d_valid===1'b1,"direct IF completes");
            verify(d_inst===(32'hA5000000 | (a >> 2)),"direct IF content");
            @(posedge clk); #1;
            d_cycles=d_cycles+cycles-start_c; d_req=0;
        end
    endtask

    task one_fetch;
        input [31:0] a;
        integer start_c,w;
        begin
            @(negedge clk); one_addr=a; one_req=1;
            start_c=cycles; w=0; #1;
            while(!one_ready && w<500) begin
                verify(one_stall===1'b1,"direct-mapped cache stalls during miss");
                @(negedge clk); #1; w=w+1;
            end
            verify(one_ready===1'b1 && one_valid===1'b1,"direct-mapped IF completes");
            verify(one_inst===(32'hA5000000 | (a >> 2)),"direct-mapped IF content");
            @(posedge clk); #1;
            one_cycles=one_cycles+cycles-start_c; one_req=0;
        end
    endtask

    task two_fetch;
        input [31:0] a;
        integer start_c,w;
        begin
            @(negedge clk); two_addr=a; two_req=1;
            start_c=cycles; w=0; #1;
            while(!two_ready && w<500) begin
                verify(two_stall===1'b1,"two-way cache stalls during miss");
                @(negedge clk); #1; w=w+1;
            end
            verify(two_ready===1'b1 && two_valid===1'b1,"two-way IF completes");
            verify(two_inst===(32'hA5000000 | (a >> 2)),"two-way IF content");
            @(posedge clk); #1;
            two_cycles=two_cycles+cycles-start_c; two_req=0;
        end
    endtask

    function [31:0] trace_addr;
        input integer pattern, seq;
        begin
            case(pattern)
                0: trace_addr=(seq%32)*4;                 // 32 words x3
                1: trace_addr=(seq%4)*4;                  // hot loop
                2: trace_addr=(seq%2 == 0)?32'h0:32'h100; // one-way thrash
                default: trace_addr=0;
            endcase
        end
    endfunction

    task run_case;
        input integer pattern,n,one_h,one_m,two_h,two_m;
        begin
            reset_all;
            d_cycles=0; one_cycles=0; two_cycles=0;
            for(i=0;i<n;i=i+1) begin
                addr=trace_addr(pattern,i);
                direct_fetch(addr);
            end
            for(i=0;i<n;i=i+1) begin
                addr=trace_addr(pattern,i);
                one_fetch(addr);
            end
            for(i=0;i<n;i=i+1) begin
                addr=trace_addr(pattern,i);
                two_fetch(addr);
            end
            verify(d_transactions==n,"direct backing words match fetch count");
            verify(one_hits==one_h && one_misses==one_m,"one-way exact hits/misses");
            verify(two_hits==two_h && two_misses==two_m,"two-way exact hits/misses");
            verify(one_hits+one_misses==n && two_hits+two_misses==n,
                   "each request counted exactly once by both caches");
            verify(one_refills==one_m*4 && one_transactions==one_m*4,
                   "one-way 4-word refill traffic");
            verify(two_refills==two_m*4 && two_transactions==two_m*4,
                   "two-way 4-word refill traffic");
            verify(d_cycles>0 && one_cycles>0 && two_cycles>0,
                   "all three paths have positive measured cycles");
            d_to_one = (d_cycles*1.0)/one_cycles;
            d_to_two = (d_cycles*1.0)/two_cycles;
            two_vs_one = (one_cycles*1.0)/two_cycles;
            $display("------------------------------------------------");
            $display("PATTERN %0d: fetches=%0d",pattern,n);
            $display("Direct IF        cycles=%0d, backing words=%0d",d_cycles,d_transactions);
            $display("Direct-mapped    cycles=%0d, backing words=%0d",one_cycles,one_transactions);
            $display("Two-way LRU      cycles=%0d, backing words=%0d",two_cycles,two_transactions);
            $display("Direct-map Hits=%0d Misses=%0d Hit rate=%0f%%",
                     one_hits,one_misses,(one_hits*100.0)/n);
            $display("Two-way    Hits=%0d Misses=%0d Hit rate=%0f%%",
                     two_hits,two_misses,(two_hits*100.0)/n);
            $display("Speedup: direct->DM=%0f  direct->2way=%0f  DM->2way=%0f",
                     d_to_one,d_to_two,two_vs_one);
            if(pattern==2) begin
                verify(two_cycles < one_cycles,"two-way improves conflict trace");
                verify(two_cycles < d_cycles,"two-way beats direct fetch on conflict trace");
            end
        end
    endtask

    task lru_check;
        begin
            reset_all;
            two_cycles=0;
            // Set 0: A=0, B=0x80, C=0x100, all distinct tags.
            // A miss, B miss, A hit -> evict B on C miss.
            // A hit, B miss -> evict C. Expected: 2 hits, 4 misses.
            two_fetch(32'h00000000);
            two_fetch(32'h00000080);
            two_fetch(32'h00000000);
            two_fetch(32'h00000100);
            two_fetch(32'h00000000);
            two_fetch(32'h00000080);
            verify(two_hits==2 && two_misses==4,
                   "LRU recency distinguishes recently used way");
            verify(two_refills==16 && two_transactions==16,
                   "LRU trace refills four complete lines");
            $display("------------------------------------------------");
            $display("LRU TRACE: hits=%0d misses=%0d backing words=%0d",
                     two_hits,two_misses,two_transactions);
        end
    endtask

    task invalid_addresses;
        integer txd,txone,txtwo;
        begin
            reset_all;
            @(negedge clk);
            txd=d_transactions; txone=one_transactions; txtwo=two_transactions;
            d_req=1; one_req=1; two_req=1;
            d_addr=32'h00000400;
            one_addr=32'h00000003;
            two_addr=32'h00000400;
            #1;
            verify(d_ready && !d_valid && !d_stall && d_inst==0,
                   "direct invalid address response");
            verify(one_ready && !one_valid && !one_stall && one_inst==0,
                   "one-way misaligned address response");
            verify(two_ready && !two_valid && !two_stall && two_inst==0,
                   "two-way invalid address response");
            @(posedge clk); #1;
            d_req=0; one_req=0; two_req=0;
            verify(d_transactions==txd && one_transactions==txone &&
                   two_transactions==txtwo,
                   "invalid address does not touch backing memory");
            verify(two_hits==0 && two_misses==0 && two_refills==0,
                   "invalid address does not count as cache access");
        end
    endtask

    initial begin
        clk=0;rst=0;d_req=0;one_req=0;two_req=0;
        d_addr=0;one_addr=0;two_addr=0;
        checks=0;errors=0;cycles=0;
        // Must use the same traces as verified I-Cache V0.2.
        run_case(0,96,88,8,88,8);
        run_case(1,64,63,1,63,1);
        run_case(2,32,0,32,30,2);
        lru_check;
        invalid_addresses;
        $display("================================================");
        $display("Total checks = %0d",checks);
        $display("Total errors = %0d",errors);
        if(errors==0) $display("ALL TESTS PASSED");
        else $display("TESTS FAILED");
        $finish;
    end
endmodule
