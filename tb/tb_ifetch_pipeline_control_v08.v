`timescale 1ns / 1ps
// V0.8: V0.7 official IF + pipeline_control_unit joint regression.
// 12 V0.7 regression cases + 6 V0.8 control integration cases.
// Verilog-2001, Vivado 2019.1; preserves stable official RTL.
// Uses actual IF/ID, adapter, 2-way Cache and latency-3 backing ROM.
// Uses team-A official pc_if_controller, not reference IF driver.
module tb_ifetch_pipeline_control_v08;
    reg clk, rst, redirect, id_can_advance, ifid_flush;
    reg [31:0] redirect_pc;
    reg load_use_hazard;
    wire ifid_stall, ifid_flush_ctrl, idex_flush, hold_fetch_issue_req;
    wire id_can_advance_effective, ifid_flush_effective;
    wire id_valid, fetch_error_fire, req_fire, resp_fire, adapter_busy;
    wire [31:0] id_pc, id_inst, fetch_error_pc;
    wire [31:0] req_addr_debug, resp_pc_debug;
    wire [31:0] cache_hits, cache_misses, cache_refills, backing_transactions;

    integer checks, errors, delivered_total, errors_seen, req_total, resp_total;
    integer cycles, k, d0;
    reg tracked_request;
    reg [31:0] tracked_pc, expected_next_pc;
    reg expected_id_valid;
    reg [31:0] expected_id_pc, expected_id_inst;
    reg [31:0] held_pc, held_inst;

    initial clk = 0;
    always #5 clk = ~clk;

    ifetch_pipeline_control_v08 dut (
        .clk(clk), .rst(rst), .branch_redirect(redirect),
        .redirect_pc(redirect_pc), .load_use_hazard(load_use_hazard),
        .id_can_advance_external(id_can_advance),
        .ifid_flush_external(ifid_flush),
        .ifid_stall(ifid_stall), .ifid_flush_ctrl(ifid_flush_ctrl),
        .idex_flush(idex_flush), .hold_fetch_issue_req(hold_fetch_issue_req),
        .id_can_advance_effective(id_can_advance_effective),
        .ifid_flush_effective(ifid_flush_effective),
        .id_valid(id_valid), .id_pc(id_pc), .id_inst(id_inst),
        .fetch_error_fire(fetch_error_fire), .fetch_error_pc(fetch_error_pc),
        .req_fire(req_fire), .resp_fire(resp_fire),
        .req_addr_debug(req_addr_debug), .resp_pc_debug(resp_pc_debug),
        .adapter_busy(adapter_busy),
        .cache_hits(cache_hits), .cache_misses(cache_misses),
        .cache_refills(cache_refills), .backing_transactions(backing_transactions)
    );

    task verify;
        input condition;
        input [8*120-1:0] explanation;
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL [%0d] @%0t: %0s",checks,$time,explanation);
            end
        end
    endtask

    // Check ALL registered IF/ID outputs against controls sampled BEFORE
    // the rising edge (NBA assignments settle 1 ns later). Also keep a
    // one-outstanding transaction scoreboard across Miss and Redirect.
    always @(posedge clk) begin
        if (rst || redirect || ifid_flush_effective) begin
            expected_id_valid = 1'b0;
            expected_id_pc = 32'b0;
            expected_id_inst = 32'b0;
        end else if (!id_can_advance_effective) begin
            expected_id_valid = id_valid;
            expected_id_pc = id_pc;
            expected_id_inst = id_inst;
        end else if (resp_fire && !fetch_error_fire) begin
            expected_id_valid = 1'b1;
            expected_id_pc = resp_pc_debug;
            expected_id_inst = dut.u_ifetch.if_resp_inst;
        end else begin
            expected_id_valid = 1'b0;
            expected_id_pc = 32'b0;
            expected_id_inst = 32'b0;
        end

        if (rst) begin
            tracked_request = 1'b0;
            expected_next_pc = 32'b0;
        end else if (redirect) begin
            verify(!req_fire && !resp_fire, "redirect gates both old handshakes");
            tracked_request = 1'b0;
            expected_next_pc = redirect_pc;
        end else begin
            if (req_fire) begin
                verify(!tracked_request, "one outstanding accepted request maximum");
                verify(req_addr_debug === expected_next_pc,
                       "accepted PC follows sequence/redirect target");
                tracked_pc = req_addr_debug;
                expected_next_pc = expected_next_pc + 32'd4;
                tracked_request = 1'b1;
                req_total = req_total + 1;
            end
            if (resp_fire) begin
                verify(tracked_request, "response matches an outstanding request");
                verify(resp_pc_debug === tracked_pc, "response PC matches accepted PC");
                tracked_request = 1'b0;
                resp_total = resp_total + 1;
                if (fetch_error_fire) begin
                    errors_seen = errors_seen + 1;
                end else begin
                    verify(dut.u_ifetch.if_resp_inst ===
                           (32'hA5000000 | (resp_pc_debug >> 2)),
                           "response instruction equals backing ROM word");
                    delivered_total = delivered_total + 1;
                end
            end
        end
        #1;
        verify(id_valid === expected_id_valid,
               "IF/ID valid matches flush/stall/response handshake");
        verify(id_pc === expected_id_pc,
               "IF/ID PC captured once or held/cleared correctly");
        verify(id_inst === expected_id_inst,
               "IF/ID instruction captured once or held/cleared correctly");
        // Continuous cross-module assertions: independent of test scenario.
        verify(ifid_stall === (!rst && !redirect && load_use_hazard),
               "PCU priority: IF/ID stall only for unmasked load-use");
        verify(ifid_flush_ctrl === (rst || redirect),
               "PCU priority: IF/ID flush on reset/redirect");
        verify(idex_flush === (rst || redirect || load_use_hazard),
               "PCU requests ID/EX bubble for reset/redirect/load-use");
        verify(hold_fetch_issue_req ===
                   (rst || (!redirect && load_use_hazard)),
               "PCU advisory hold honors reset/redirect priority");
        verify(id_can_advance_effective ===
                   (id_can_advance && !ifid_stall),
               "V0.8 IF/ID advance gating matches pipeline stall");
        verify(ifid_flush_effective === (ifid_flush || ifid_flush_ctrl),
               "V0.8 IF/ID flush combines local and pipeline flush");
    end

    // Provides a CLEAN start PC without issuing a speculative request.
    task reset_to_pc;
        input [31:0] start_pc;
        begin
            @(negedge clk);
            rst = 1'b1;
            redirect = 1'b0;
            ifid_flush = 1'b0;
            id_can_advance = 1'b1;
            load_use_hazard = 1'b0;
            redirect_pc = start_pc;
            @(posedge clk); #2;
            verify(!id_valid && !adapter_busy, "reset empties IFID and adapter");
            @(negedge clk);
            rst = 1'b0;
            redirect = 1'b1;
            @(posedge clk); #2;
            verify(!id_valid, "initial PC selection does not emit stale data");
            @(negedge clk);
            redirect = 1'b0;
            #1;
        end
    endtask

    task redirect_to;
        input [31:0] target;
        begin
            @(negedge clk);
            redirect = 1'b1;
            redirect_pc = target;
            #1;
            verify(!resp_fire && !req_fire,
                   "redirect blocks old request and response instantly");
            @(posedge clk); #2;
            verify(!id_valid, "redirect clears IF/ID valid even during stall");
            @(negedge clk);
            redirect = 1'b0;
            #1;
        end
    endtask

    task wait_deliveries;
        input integer goal;
        input [8*110-1:0] description;
        begin
            cycles = 0;
            while (delivered_total < goal && cycles < 260) begin
                @(negedge clk); #1;
                cycles = cycles + 1;
            end
            verify(delivered_total >= goal,description);
        end
    endtask

    task wait_adapter_response;
        begin
            cycles = 0;
            @(negedge clk); #1;
            while (!dut.u_ifetch.u_adapter.if_resp_valid && cycles < 260) begin
                @(negedge clk); #1;
                cycles = cycles + 1;
            end
            verify(dut.u_ifetch.u_adapter.if_resp_valid,
                   "adapter response became valid before timeout");
        end
    endtask

    initial begin
        rst=1; redirect=0; redirect_pc=0; ifid_flush=0;
        load_use_hazard=0;
        id_can_advance=1; checks=0; errors=0;
        delivered_total=0; errors_seen=0; req_total=0; resp_total=0;
        tracked_request=0; tracked_pc=0; expected_next_pc=0;
        expected_id_valid=0; expected_id_pc=0; expected_id_inst=0;

        $display("CASE 1: sequential 3+ instruction fetch, Miss then Hits");
        reset_to_pc(32'h00000000);
        d0=delivered_total;
        wait_deliveries(d0+3,"three instructions delivered in sequential order");
        verify(cache_misses==1,"one refill for first three words in one line");
        verify(cache_hits>=2,"subsequent sequential words hit in I-Cache");

        $display("CASE 2: Miss + ID stall, response must hold and consume once");
        reset_to_pc(32'h00000080);
        @(posedge clk); #2; // new request accepted
        @(negedge clk); id_can_advance=0;
        wait_adapter_response;
        held_pc=dut.u_ifetch.if_resp_pc; held_inst=dut.u_ifetch.if_resp_inst;
        for(k=0;k<4;k=k+1) begin
            @(posedge clk); #2;
            verify(dut.u_ifetch.if_resp_valid && !resp_fire,
                   "backpressure holds pending response, not consumed");
            verify(dut.u_ifetch.if_resp_pc===held_pc && dut.u_ifetch.if_resp_inst===held_inst,
                   "backpressure retains response payload");
        end
        d0=delivered_total;
        @(negedge clk); id_can_advance=1;
        wait_deliveries(d0+1,"release of stall consumes exactly one response");
        verify(delivered_total==d0+1,"no duplicate delivery on first release");

        $display("CASE 3: redirect during an outstanding cache Miss");
        reset_to_pc(32'h00000100);
        @(posedge clk); #2;
        verify(adapter_busy,"old cold miss pending");
        d0=delivered_total;
        redirect_to(32'h00000200);
        verify(delivered_total==d0,"stale response not delivered on redirect");
        wait_deliveries(d0+1,"new target eventually delivered after drain");
        verify(id_pc===32'h00000200,"first delivered PC is redirect target");

        $display("CASE 4: redirect while response is held by ID backpressure");
        reset_to_pc(32'h00000040);
        @(posedge clk); #2;
        @(negedge clk); id_can_advance=0;
        wait_adapter_response;
        d0=delivered_total;
        redirect_to(32'h00000090);
        @(negedge clk); id_can_advance=1;
        wait_deliveries(d0+1,"redirect target delivered after old response discarded");
        verify(id_pc===32'h00000090,"held stale instruction never reached IF/ID");

        $display("CASE 5: redirect at cache READY completion edge");
        reset_to_pc(32'h00000280);
        @(posedge clk); #2;
        cycles=0;
        @(negedge clk); #1;
        while (!dut.u_ifetch.u_adapter.u_icache.ready && cycles<240) begin
            @(negedge clk); #1;
            cycles=cycles+1;
        end
        verify(dut.u_ifetch.u_adapter.u_icache.ready,
               "legacy cache reached ready edge for redirect race");
        d0=delivered_total;
        redirect=1; redirect_pc=32'h00000300;
        #1;
        verify(!dut.u_ifetch.u_adapter.if_resp_valid,
               "redirect gates old cache response on completion edge");
        @(posedge clk); #2;
        verify(!id_valid,"no stale instruction in IF/ID on completion edge");
        @(negedge clk); redirect=0;
        wait_deliveries(d0+1,"redirect target eventually delivered after completion race");
        verify(id_pc===32'h00000300,"completion-edge redirect target correct");

        $display("CASE 6: IF/ID flush beats downstream stall");
        reset_to_pc(32'h00000000);
        d0=delivered_total;
        wait_deliveries(d0+1,"initial valid IFID instruction exists");
        verify(id_valid,"IFID has valid instruction before flush");
        @(negedge clk); id_can_advance=0; ifid_flush=1;
        @(posedge clk); #2;
        verify(!id_valid && id_pc==0 && id_inst==0,
               "flush clears IFID despite stall=1");
        @(negedge clk); ifid_flush=0;
        @(posedge clk); #2;
        verify(!id_valid,"empty IFID remains empty while stalled");
        @(negedge clk); id_can_advance=1;

        $display("CASE 7: synchronous reset beats flush + stall");
        reset_to_pc(32'h00000000);
        d0=delivered_total;
        wait_deliveries(d0+1,"valid IFID instruction before reset");
        @(negedge clk); rst=1; ifid_flush=1; id_can_advance=0;
        @(posedge clk); #2;
        verify(!id_valid && id_pc==0 && id_inst==0,
               "synchronous reset wins simultaneous flush and stall");
        verify(!adapter_busy,"reset cancels adapter pending state");
        @(negedge clk); rst=0; ifid_flush=0; id_can_advance=1;

        $display("CASE 8: invalid-address response does not become instruction");
        reset_to_pc(32'h00000400);
        d0=errors_seen;
        cycles=0;
        while(errors_seen==d0 && cycles<260) begin
            @(negedge clk); #1; cycles=cycles+1;
        end
        verify(errors_seen==d0+1,"one invalid fetch returned error status");
        verify(!id_valid,"invalid instruction not sent to IFID as valid");

        $display("CASE 9: redirect during ID stall overrides request + flush");
        reset_to_pc(32'h00000000);
        @(negedge clk); id_can_advance=0; ifid_flush=1;
        d0=delivered_total;
        redirect_to(32'h00000140);
        verify(!id_valid,"redirect+flush+stall keeps IFID invalid");
        @(negedge clk); ifid_flush=0; id_can_advance=1;
        wait_deliveries(d0+1,"redirect during stall eventually fetches target");
        verify(id_pc===32'h00000140,"new PC wins old pending request");


        // V0.7 OFFICIAL additions: extend the formal PC/IF regression.
        // Uses team-A official pc_if_controller; V0.6 reference driver is excluded.
        $display("CASE 10: sequential fetch crosses a 16-byte cache-line boundary");
        reset_to_pc(32'h0000000C); // Last word in line 0, then line 1
        d0=delivered_total;
        wait_deliveries(d0+3,"three cross-line sequential instructions delivered");
        verify(cache_misses==2,
               "crossing 0x0C to 0x10 causes exactly two cold line refills");
        verify(id_pc===32'h00000014,
               "third delivered instruction is at PC=0x14");

        $display("CASE 11: local IFID flush must NOT cancel a held cache response");
        reset_to_pc(32'h000001C0);
        @(posedge clk); #2;
        @(negedge clk); id_can_advance=0;
        wait_adapter_response;
        held_pc=dut.u_ifetch.if_resp_pc;
        held_inst=dut.u_ifetch.if_resp_inst;
        d0=delivered_total;
        @(negedge clk); ifid_flush=1;
        @(posedge clk); #2;
        verify(!id_valid,"local flush clears IFID while ID stalled");
        verify(dut.u_ifetch.if_resp_valid && !resp_fire,
               "local flush alone keeps adapter response pending");
        verify(dut.u_ifetch.if_resp_pc===held_pc && dut.u_ifetch.if_resp_inst===held_inst,
               "local flush alone does not corrupt held response");
        @(negedge clk); ifid_flush=0; id_can_advance=1;
        wait_deliveries(d0+1,"held response consumed after local flush release");
        verify(id_pc===held_pc && id_inst===held_inst,
               "IFID receives original held response after local flush");
        verify(delivered_total===d0+1,
               "local flush did not duplicate a response");

        $display("CASE 12: synchronous reset in flight cancels old miss");
        reset_to_pc(32'h00000280);
        @(posedge clk); #2;
        verify(adapter_busy,"old request is active before mid-miss reset");
        reset_to_pc(32'h000003C0); // Drives rst while old transaction is active
        verify(!id_valid,"reset cleared IFID despite old miss");
        d0=delivered_total;
        wait_deliveries(d0+1,"new PC delivered after mid-miss reset");
        verify(id_pc===32'h000003C0,
               "mid-miss reset dropped old PC and restarted at requested PC");

        // ---------------- V0.8 pipeline control integration ----------------
        $display("CASE 13: load-use stalls a valid IF/ID instruction and bubbles ID/EX");
        reset_to_pc(32'h00000000);
        d0=delivered_total;
        wait_deliveries(d0+1,"IF/ID loaded before real load-use stall");
        // wait_deliveries returns 1ns after a negedge; set hazard now.
        verify(id_valid,"valid IF/ID available before load-use");
        held_pc=id_pc; held_inst=id_inst;
        load_use_hazard=1;
        #1;
        verify(ifid_stall && !ifid_flush_ctrl && idex_flush &&
               hold_fetch_issue_req && !id_can_advance_effective,
               "load-use control asserted and IF/ID advance blocked");
        for(k=0;k<3;k=k+1) begin
            @(posedge clk); #2;
            verify(id_valid && id_pc===held_pc && id_inst===held_inst,
                   "load-use preserves IF/ID valid, PC and instruction");
        end
        @(negedge clk); load_use_hazard=0;
        #1;
        verify(!ifid_stall && !idex_flush && !hold_fetch_issue_req,
               "releasing load-use releases controller outputs");
        d0=delivered_total;
        wait_deliveries(d0+1,"fetch resumes delivery after load-use release");
        verify(id_pc===held_pc+32'd4,
               "first new delivered instruction resumes sequential PC");

        $display("CASE 14: cache Miss + load-use holds a completed IF response");
        reset_to_pc(32'h00000100);
        @(posedge clk); #2;
        verify(adapter_busy,"miss transaction outstanding before hazard");
        @(negedge clk); load_use_hazard=1;
        #1;
        verify(hold_fetch_issue_req && !id_can_advance_effective,
               "hazard requests advisory fetch stop and blocks IFID capture");
        verify(dut.u_ifetch.u_pc.if_req_valid,
               "advisory hold does not cancel PC request valid");
        wait_adapter_response;
        held_pc=dut.u_ifetch.if_resp_pc;
        held_inst=dut.u_ifetch.if_resp_inst;
        for(k=0;k<3;k=k+1) begin
            @(posedge clk); #2;
            verify(dut.u_ifetch.if_resp_valid && !resp_fire,
                   "miss response retained while load-use stalled");
            verify(dut.u_ifetch.if_resp_pc===held_pc &&
                   dut.u_ifetch.if_resp_inst===held_inst,
                   "retained miss response PC/instruction stable");
        end
        d0=delivered_total;
        @(negedge clk); load_use_hazard=0;
        wait_deliveries(d0+1,"held miss response delivered after hazard release");
        verify(id_pc===32'h00000100,
               "correct miss response PC delivered after load-use");

        $display("CASE 15: redirect outranks load-use during outstanding Miss");
        reset_to_pc(32'h00000180);
        @(posedge clk); #2;
        verify(adapter_busy,"miss in progress before redirect+hazard");
        @(negedge clk);
        load_use_hazard=1; redirect=1; redirect_pc=32'h00000200;
        #1;
        verify(!ifid_stall && ifid_flush_ctrl && idex_flush &&
               !hold_fetch_issue_req,
               "redirect outranks load-use on all four outputs");
        verify(!req_fire && !resp_fire,
               "redirect suppresses old IF request/response handshakes");
        @(posedge clk); #2;
        verify(!id_valid,"redirect clears wrong-path IF/ID");
        @(negedge clk); redirect=0; load_use_hazard=0;
        d0=delivered_total;
        wait_deliveries(d0+1,"redirect target delivered after old Miss drain");
        verify(id_pc===32'h00000200,
               "redirect target PC delivered without old-path leak");

        $display("CASE 16: reset outranks redirect and load-use");
        reset_to_pc(32'h00000040);
        d0=delivered_total;
        wait_deliveries(d0+1,"one valid instruction before reset priority test");
        rst=1; redirect=1; load_use_hazard=1; redirect_pc=32'h00000240;
        #1;
        verify(!ifid_stall && ifid_flush_ctrl && idex_flush &&
               hold_fetch_issue_req,
               "reset highest priority for all controls");
        @(posedge clk); #2;
        verify(!id_valid && !adapter_busy,
               "reset empties both IFID and adapter under simultaneous inputs");
        @(negedge clk); rst=0; redirect=0; load_use_hazard=0;
        d0=delivered_total;
        wait_deliveries(d0+1,"clean reset resumes from RESET_PC");
        verify(id_pc===32'h00000000,
               "reset outranks simultaneous redirect target");

        $display("CASE 17: redirect during external stall with load-use asserted");
        reset_to_pc(32'h00000240);
        @(posedge clk); #2;
        @(negedge clk);
        id_can_advance=0; load_use_hazard=1; redirect=1;
        redirect_pc=32'h00000300;
        #1;
        verify(ifid_flush_ctrl && !ifid_stall && idex_flush,
               "redirect flush outranks load-use even under external stall");
        @(posedge clk); #2;
        verify(!id_valid,"IF/ID cleared despite downstream stall");
        @(negedge clk); redirect=0; load_use_hazard=0;
        id_can_advance=1;
        d0=delivered_total;
        wait_deliveries(d0+1,"redirect resumes correctly when external stall clears");
        verify(id_pc===32'h00000300,
               "redirect PC preserved across downstream stall");

        $display("CASE 18: advisory hold must not retract pending valid/PC");
        reset_to_pc(32'h00000140);
        @(posedge clk); #2;
        verify(adapter_busy,"adapter busy before advisory hold test");
        @(negedge clk); load_use_hazard=1;
        held_pc=dut.u_ifetch.if_req_addr;
        #1;
        verify(hold_fetch_issue_req && dut.u_ifetch.if_req_valid,
               "PC request remains asserted despite advisory hold");
        for(k=0;k<2;k=k+1) begin
            @(posedge clk); #2;
            verify(dut.u_ifetch.if_req_valid,
                   "previously asserted PC req_valid remains asserted");
            verify(dut.u_ifetch.if_req_addr===held_pc,
                   "unaccepted PC request address stays stable");
        end
        @(negedge clk); load_use_hazard=0;
        d0=delivered_total;
        wait_deliveries(d0+1,"normal delivery after advisory hold release");
        verify(id_pc===32'h00000140,
               "advisory hold did not corrupt accepted pending request");

        $display("=============================================");
        $display("V0.8 OFFICIAL IF + PIPELINE CONTROL INTEGRATION TEST");
        $display("Total scenarios = 18 (V0.7 regression 12 + V0.8 control 6)");
        $display("Total checks = %0d",checks);
        $display("Total errors = %0d",errors);
        $display("Total requests = %0d, responses = %0d",req_total,resp_total);
        $display("Total valid deliveries = %0d, error responses = %0d",delivered_total,errors_seen);
        $display("Last cache: hits=%0d misses=%0d refill_words=%0d backing_words=%0d",
                 cache_hits,cache_misses,cache_refills,backing_transactions);
        if(errors==0 && delivered_total>0 && errors_seen==1)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED");
        $finish;
    end
    initial begin
        #100000;
        $display("FATAL TIMEOUT at %0t",$time);
        $fatal(1, "V0.8 simulation timed out");
    end
endmodule
