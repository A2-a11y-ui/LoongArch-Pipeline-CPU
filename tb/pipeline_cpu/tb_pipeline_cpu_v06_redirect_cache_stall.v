`timescale 1ns / 1ps
// V0.6 TEST-ONLY: UNMODIFIED pipeline_cpu_core_v05 + actual V0.4 datapath.
// SCENARIO A: NATURAL EX-stage BEQ at the last word of a 16-byte line;
//   wrong-path address 0x1010 starts a new miss when redirect occurs.
// SCENARIO B: DIRECTED REDIRECT INJECTION while a response is in ST_RESP
//   with if_delivery_allow=0.  This is a protocol stress test, NOT a naturally
//   executed branch and NOT a natural Load-use hazard.  It does not modify RTL.
// Requires Vivado 2019.1 Verilog-2001.  Program ROM at physical 0x000..0x02f.
module tb_pipeline_cpu_v06_redirect_cache_stall;
    parameter MEM_FILE = "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/v06_redirect_cache_stall.mem";
    localparam [31:0] BASE = 32'h00001000;
    localparam [31:0] TARGET = 32'h00001020;
    localparam integer WORDS = 12;
    localparam [1:0] ST_IDLE=2'd0, ST_WAIT=2'd1, ST_RESP=2'd2, ST_DRAIN=2'd3;

    reg clk=0;
    always #5 clk=~clk;
    reg rst=1;
    reg if_delivery_allow=1;
    integer phase=0;  // 0 reset, 1 natural branch/miss, 2 injected redirect/pending
    wire if_valid,if_ready,if_req_fire,if_resp_fire,if_resp_hold;
    wire [31:0] if_pc,if_inst,if_req_pc,if_resp_pc;
    wire fetch_error_fire,adapter_busy;
    wire [31:0] cache_hits,cache_misses,cache_refills,backing_transactions;
    wire branch_resolve_valid,branch_redirect,load_use_stall,id_unsupported,id_raw_hazard;
    wire [31:0] branch_redirect_pc;
    wire wb_commit_valid,mem_store_commit_valid;
    wire [31:0] wb_commit_pc,wb_commit_data;
    wire [4:0] wb_commit_rd;
    wire [31:0] mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data;

    pipeline_cpu_core_v05 #(.PC_BASE(BASE),.PROGRAM_WORDS(WORDS),.IMEM_LATENCY(3)) dut (
        .clk(clk),.rst(rst),.if_delivery_allow(if_delivery_allow),
        .if_valid(if_valid),.if_pc(if_pc),.if_inst(if_inst),.if_ready(if_ready),
        .if_req_fire(if_req_fire),.if_req_pc(if_req_pc),
        .if_resp_fire(if_resp_fire),.if_resp_pc(if_resp_pc),
        .if_resp_hold(if_resp_hold),.fetch_error_fire(fetch_error_fire),
        .adapter_busy(adapter_busy),.cache_hits(cache_hits),
        .cache_misses(cache_misses),.cache_refills(cache_refills),
        .backing_transactions(backing_transactions),
        .branch_resolve_valid(branch_resolve_valid),
        .branch_redirect(branch_redirect),.branch_redirect_pc(branch_redirect_pc),
        .load_use_stall(load_use_stall),.id_unsupported(id_unsupported),
        .id_raw_hazard(id_raw_hazard),.wb_commit_valid(wb_commit_valid),
        .wb_commit_pc(wb_commit_pc),.wb_commit_rd(wb_commit_rd),
        .wb_commit_data(wb_commit_data),
        .mem_store_commit_valid(mem_store_commit_valid),
        .mem_store_commit_pc(mem_store_commit_pc),
        .mem_store_commit_addr(mem_store_commit_addr),
        .mem_store_commit_data(mem_store_commit_data)
    );

    reg [31:0] rom[0:WORDS-1];
    reg [31:0] expected_wb_pc[0:4],expected_wb_data[0:4];
    reg [4:0] expected_wb_rd[0:4];
    reg [31:0] expected_store_pc[0:1],expected_store_addr[0:1],expected_store_data[0:1];
    integer errors=0, wb_count=0, store_count=0, branch_count=0;
    integer req_count=0,resp_count=0,delivered_count=0,target_fetch_count=0,target_req_count=0;
    integer wrong_path_wb_count=0,wrong_path_store_count=0;
    integer redirect_while_cache_busy=0,redirect_while_response_pending=0;
    integer stale_response_dropped=0,stale_pending_flushed=0;
    integer drain_cycles=0,held_pending_cycles=0,force_cycles=0;
    integer cycles=0;
    reg first_word_delivered=0;
    reg outstanding=0,await_target_req=0;
    reg [31:0] outstanding_pc=0;
    reg was_held=0;
    reg [31:0] prev_resp_pc=0,prev_resp_inst=0;
    reg [31:0] pre_id_pc=0,pre_id_inst=0;
    reg pre_id_valid=0;
    reg [2047:0] file_path;
    integer fd,index;

    task fail;
        input [8*180-1:0] message;
        begin
            errors=errors+1;
            $display("FAIL V0.6 phase=%0d t=%0t: %0s",phase,$time,message);
        end
    endtask

    task reset_metrics;
        begin
            wb_count=0;store_count=0;branch_count=0;
            req_count=0;resp_count=0;delivered_count=0;target_fetch_count=0;target_req_count=0;
            wrong_path_wb_count=0;wrong_path_store_count=0;
            redirect_while_cache_busy=0;redirect_while_response_pending=0;
            stale_response_dropped=0;stale_pending_flushed=0;
            drain_cycles=0;held_pending_cycles=0;force_cycles=0;
            cycles=0;first_word_delivered=0;outstanding=0;
            outstanding_pc=0;await_target_req=0;was_held=0;prev_resp_pc=0;prev_resp_inst=0;
        end
    endtask

    // Golden WB events are written by hand from ISA semantics, not sampled
    // from DUT outputs. Phase B skips 0x1004..0x101c by directed redirect.
    task setup_golden;
        input integer which_phase;
        begin
            expected_wb_pc[0]=32'h1000; expected_wb_rd[0]=5'd2;
            expected_wb_data[0]=32'd5;
            if (which_phase==1) begin
                expected_wb_pc[1]=32'h1004; expected_wb_rd[1]=5'd3;
                expected_wb_data[1]=32'd5;
                expected_wb_pc[2]=32'h1008; expected_wb_rd[2]=5'd4;
                expected_wb_data[2]=32'd2;
                expected_wb_pc[3]=32'h1020; expected_wb_rd[3]=5'd5;
                expected_wb_data[3]=32'd9;
                expected_wb_pc[4]=32'h1028; expected_wb_rd[4]=5'd6;
                expected_wb_data[4]=32'd10;
            end else begin
                expected_wb_pc[1]=32'h1020; expected_wb_rd[1]=5'd5;
                expected_wb_data[1]=32'd9;
                expected_wb_pc[2]=32'h1028; expected_wb_rd[2]=5'd6;
                expected_wb_data[2]=32'd10;
            end
            expected_store_pc[0]=32'h1024;expected_store_addr[0]=32'd0;
            expected_store_data[0]=32'd9;
            expected_store_pc[1]=32'h102c;expected_store_addr[1]=32'd4;
            expected_store_data[1]=32'd10;
        end
    endtask

    // Monitor pre-edge handshakes and architectural commits.  The scoreboard
    // rejects wrong-path/extra commits even if final counts happen to match.
    always @(posedge clk) begin
        if (!rst && phase!=0) begin
            cycles=cycles+1;
            if (cycles>15000) begin
                fail("phase watchdog/deadlock");
                $display("FAIL WATCHDOG: phase=%0d WB=%0d Store=%0d req=%0d resp=%0d",
                         phase,wb_count,store_count,req_count,resp_count);
                $finish;
            end
            if (fetch_error_fire) fail("IMEM error delivered");
            if (if_resp_fire && (!if_ready || !if_delivery_allow || branch_redirect))
                fail("response consumed without CPU acceptance or during redirect");
            if (if_req_fire && branch_redirect) fail("new IF request accepted in redirect cycle");
            if (was_held && !branch_redirect) begin
                if (dut.u_adapter.state!==ST_RESP ||
                    dut.u_adapter.if_resp_valid!==1'b1 ||
                    if_resp_pc!==prev_resp_pc ||
                    dut.u_adapter.if_resp_inst!==prev_resp_inst)
                    fail("pending response not stable across held cycle");
            end
            was_held=if_resp_hold;
            prev_resp_pc=if_resp_pc;
            prev_resp_inst=dut.u_adapter.if_resp_inst;
            if (phase==2 && if_resp_hold && if_resp_pc==32'h1004)
                held_pending_cycles=held_pending_cycles+1;
            if (phase==1 && dut.u_adapter.state==ST_DRAIN) begin
                drain_cycles=drain_cycles+1;
                if (if_resp_fire || dut.u_adapter.if_resp_valid)
                    fail("stale response exposed while draining");
                if (dut.u_adapter.cache_ready) begin
                    stale_response_dropped=stale_response_dropped+1;
                    if (dut.u_adapter.pending_pc!==32'h00000010)
                        fail("wrong drained physical PC; expected 0x10");
                end
            end

            if (branch_redirect) begin
                if (if_req_fire || if_resp_fire || if_ready || if_valid)
                    fail("redirect priority failed; wrong-path handshake");
                if (branch_redirect_pc!==TARGET) fail("redirect target mismatch");
                if (phase==1) begin
                    if (!branch_resolve_valid || dut.u_cpu.ex_pc!==32'h100c)
                        fail("phase A must be a real BEQ at 0x100c");
                    if (dut.u_adapter.state!==ST_WAIT ||
                        dut.u_adapter.pending_pc!==32'h00000010 ||
                        dut.u_adapter.cache_ready!==1'b0)
                        fail("phase A did not overlap outstanding next-line miss");
                    redirect_while_cache_busy=redirect_while_cache_busy+1;
                    branch_count=branch_count+1;
                end else if (phase==2) begin
                    if (branch_resolve_valid) fail("phase B should be directed protocol injection");
                    if (dut.u_adapter.state!==ST_RESP ||
                        dut.u_adapter.result_pc!==32'h00000004)
                        fail("phase B redirect was not concurrent with pending response");
                    redirect_while_response_pending=redirect_while_response_pending+1;
                    stale_pending_flushed=stale_pending_flushed+1;
                end
                outstanding=0;await_target_req=1; // logical epoch invalidated
            end else begin
                if (if_req_fire) begin
                    if (outstanding) fail("second request accepted while previous outstanding");
                    if (await_target_req && if_req_pc!==TARGET)
                        fail("first request after redirect not target PC");
                    if (await_target_req) await_target_req=0;
                    if (if_req_pc==TARGET) target_req_count=target_req_count+1;
                    if (target_req_count>1) fail("duplicate target request");
                    if (if_req_pc<BASE || if_req_pc>=BASE+WORDS*4 || if_req_pc[1:0]!=0)
                        fail("request address out of bounded ROM window");
                    outstanding=1;outstanding_pc=if_req_pc;req_count=req_count+1;
                end
                if (if_resp_fire) begin
                    if (!outstanding || if_resp_pc!==outstanding_pc)
                        fail("stale/wrong epoch/duplicate IF response");
                    outstanding=0;resp_count=resp_count+1;
                end
            end
            if (if_valid && if_ready) begin
                if (!if_resp_fire) fail("CPU accepted without adapter response handshake");
                if (if_pc<BASE || if_pc>=BASE+WORDS*4 || if_pc[1:0]!=0) begin
                    fail("delivered PC out of ROM range");
                end else begin
                    index=(if_pc-BASE)>>2;
                    if (if_inst!==rom[index]) fail("delivered machine code != ROM");
                end
                if (phase==2 && if_pc>=32'h1004 && if_pc<TARGET)
                    fail("stale wrong-path instruction delivered after directed redirect");
                if (phase==1 && if_pc>=32'h1010 && if_pc<TARGET)
                    fail("stale wrong-path instruction delivered after natural branch");
                if (if_pc==32'h1000) first_word_delivered=1;
                if (if_pc==TARGET) target_fetch_count=target_fetch_count+1;
                if (target_fetch_count>1) fail("target instruction delivered more than once");
                delivered_count=delivered_count+1;
            end
            if (wb_commit_valid) begin
                if (wb_commit_pc>=32'h1010 && wb_commit_pc<TARGET ||
                    (phase==2 && wb_commit_pc>=32'h1004 && wb_commit_pc<TARGET)) begin
                    wrong_path_wb_count=wrong_path_wb_count+1;
                    fail("wrong-path WB architectural side effect");
                end
                if (wb_count >= ((phase==1)?5:3))
                    fail("duplicate/extra WB");
                else if (wb_commit_pc!==expected_wb_pc[wb_count] ||
                         wb_commit_rd!==expected_wb_rd[wb_count] ||
                         wb_commit_data!==expected_wb_data[wb_count]) begin
                    $display("WB[%0d] got pc=%h rd=%0d data=%h, exp pc=%h rd=%0d data=%h",
                        wb_count,wb_commit_pc,wb_commit_rd,wb_commit_data,
                        expected_wb_pc[wb_count],expected_wb_rd[wb_count],
                        expected_wb_data[wb_count]);
                    fail("WB scoreboard mismatch");
                end
                wb_count=wb_count+1;
            end
            if (mem_store_commit_valid) begin
                if (mem_store_commit_pc>=32'h1010 && mem_store_commit_pc<TARGET ||
                    (phase==2 && mem_store_commit_pc>=32'h1004 && mem_store_commit_pc<TARGET)) begin
                    wrong_path_store_count=wrong_path_store_count+1;
                    fail("wrong-path Store architectural side effect");
                end
                if (store_count>=2) fail("duplicate/extra Store");
                else if (mem_store_commit_pc!==expected_store_pc[store_count] ||
                         mem_store_commit_addr!==expected_store_addr[store_count] ||
                         mem_store_commit_data!==expected_store_data[store_count]) begin
                    $display("STORE[%0d] got pc=%h addr=%h data=%h",
                         store_count,mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data);
                    fail("Store scoreboard mismatch");
                end
                store_count=store_count+1;
            end
        end
    end

    task check_phase;
        input integer which_phase;
        begin
            if (which_phase==1) begin
                if (branch_count!=1 || redirect_while_cache_busy!=1 ||
                    drain_cycles==0 || stale_response_dropped!=1 ||
                    cache_misses<3 || cache_refills<12)
                    fail("A: no real redirect/WAIT/DRAIN/stale-drop coverage");
            end else begin
                if (redirect_while_response_pending!=1 || stale_pending_flushed!=1 ||
                    held_pending_cycles<2 || branch_count!=0 ||
                    cache_misses<2 || cache_refills<8)
                    fail("B: pending/stall/injected redirect coverage not achieved");
            end
            if (wb_count!=((which_phase==1)?5:3) || store_count!=2 ||
                target_fetch_count!=1 || target_req_count!=1 || wrong_path_wb_count!=0 ||
                wrong_path_store_count!=0)
                fail("final scoreboard count/target/wrong-path mismatch");
            if (dut.u_cpu.u_dmem.mem[0]!==32'd9 ||
                dut.u_cpu.u_dmem.mem[1]!==32'd10)
                fail("final DMEM contents mismatch");
            $display("V0.6 SCENARIO %0d: WB=%0d/%0d STORE=%0d/2 target_fetch_count=%0d target_req_count=%0d",
                  which_phase,wb_count,which_phase==1?5:3,store_count,target_fetch_count,target_req_count);
            $display("V0.6 COVERAGE phase=%0d: redirect_while_cache_busy=%0d redirect_while_response_pending=%0d stale_response_dropped=%0d stale_pending_flushed=%0d drain_cycles=%0d held_pending_cycles=%0d requests=%0d responses=%0d cache_misses=%0d cache_refills=%0d errors=%0d",
                  which_phase,redirect_while_cache_busy,redirect_while_response_pending,
                  stale_response_dropped,stale_pending_flushed,drain_cycles,
                  held_pending_cycles,req_count,resp_count,cache_misses,cache_refills,errors);
        end
    endtask

    initial begin
        file_path=MEM_FILE;
        if ($value$plusargs("MEM_FILE=%s",file_path))
            $display("V0.6 ROM path from +MEM_FILE");
        fd=$fopen(file_path,"r");
        if (fd==0) begin
            $display("FAIL V0.6 cannot open ROM: %0s",file_path);
            $finish;
        end
        $fclose(fd);
        #1;
        $readmemh(file_path,rom);
        $readmemh(file_path,dut.u_imem.rom);

        // -------- A: real BEQ at last word of 16-byte I-Cache line --------
        reset_metrics(); setup_golden(1);
        repeat(4) @(negedge clk);
        phase=1; rst=0; if_delivery_allow=1;
        wait(wb_count>=5 && store_count>=2 && target_fetch_count==1);
        repeat(20) @(negedge clk); // catch delayed extra wrong-path commits
        check_phase(1);

        // -------- B: protocol-directed redirect while ST_RESP held --------
        @(negedge clk); rst=1; phase=0; if_delivery_allow=1;
        repeat(5) @(negedge clk);
        reset_metrics(); setup_golden(2);
        phase=2; rst=0;
        wait(first_word_delivered);
        // Stop CPU receiving any *next* response before it becomes ST_RESP.
        @(negedge clk); if_delivery_allow=0;
        wait(dut.u_adapter.state==ST_RESP &&
             dut.u_adapter.result_pc==32'h00000004);
        // At least two complete held response cycles: no natural hazard claimed.
        repeat(3) @(negedge clk);
        if (dut.u_adapter.state!==ST_RESP || !if_resp_hold ||
            if_resp_fire || if_resp_pc!==32'h1004)
            fail("B: old-path pending response not held before redirect");
        // TESTBENCH-ONLY protocol injection; NOT a naturally decoded branch.
        force dut.branch_redirect = 1'b1;
        force dut.branch_redirect_pc = 32'h00001020;
        #1;
        if (if_req_fire!==1'b0 || if_resp_fire!==1'b0 ||
            dut.u_adapter.if_resp_valid!==1'b0)
            fail("B: redirect must synchronously mask old response handshake");
        @(posedge clk); #1;
        if (dut.u_adapter.state!==ST_IDLE ||
            dut.u_adapter.if_resp_valid!==1'b0)
            fail("B: old ST_RESP not flushed after redirect");
        @(negedge clk);
        release dut.branch_redirect;
        release dut.branch_redirect_pc;
        if_delivery_allow=1;
        wait(wb_count>=3 && store_count>=2 && target_fetch_count==1);
        repeat(20) @(negedge clk);
        check_phase(2);
        $display("V0.6 RESULT: natural_busy=%0d injected_pending=%0d wrong_path_WB=%0d wrong_path_STORE=%0d errors=%0d",
            1,redirect_while_response_pending,wrong_path_wb_count,
            wrong_path_store_count,errors);
        if (errors==0)
            $display("ALL TESTS PASSED (V0.6 redirect/cache outstanding/downstream stall)");
        else
            $display("TEST FAILED (V0.6): errors=%0d",errors);
        $finish;
    end

    initial begin
        #300000;
        $display("FAIL V0.6 global watchdog: phase=%0d WB=%0d Store=%0d errors=%0d",
                  phase,wb_count,store_count,errors);
        $finish;
    end
endmodule
