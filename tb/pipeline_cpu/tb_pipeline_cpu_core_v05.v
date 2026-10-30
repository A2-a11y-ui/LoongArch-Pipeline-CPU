`timescale 1ns / 1ps
// V0.5 cache + PC/IF + UNCHANGED CPU V0.4 behavioral integration test.
// Independent expected WB / STORE / BR values are hard-coded from ISA meaning;
// nothing is learned from CPU output. Uses SAME ROM machine words as V0.4.
// IMPORTANT: variable-length I-Cache miss latency means it is NOT valid to
// demand V0.4's exact load-use stall/forwarding coverage counts in V0.5.
module tb_pipeline_cpu_core_v05;
    parameter MEM_FILE = "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/branch_v05.mem";
    localparam [31:0] PC_BASE = 32'h00001000;
    localparam integer WORDS=62, NCOMMITS=27, NSTORES=6, NBRANCHES=16;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1;
    reg if_delivery_allow=0;
    wire if_valid, if_ready, if_req_fire, if_resp_fire, if_resp_hold;
    wire [31:0] if_pc,if_inst,if_req_pc,if_resp_pc;
    wire fetch_error_fire,adapter_busy;
    wire [31:0] cache_hits,cache_misses,cache_refills,backing_transactions;
    wire branch_resolve_valid,branch_redirect;
    wire [31:0] branch_redirect_pc;
    wire wb_commit_valid;
    wire [31:0] wb_commit_pc,wb_commit_data;
    wire [4:0] wb_commit_rd;
    wire mem_store_commit_valid;
    wire [31:0] mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data;
    wire load_use_stall,id_unsupported,id_raw_hazard;

    pipeline_cpu_core_v05 #(.PC_BASE(PC_BASE),.PROGRAM_WORDS(WORDS),
                             .IMEM_LATENCY(3)) dut (
        .clk(clk),.rst(rst),.if_delivery_allow(if_delivery_allow),
        .if_valid(if_valid),.if_pc(if_pc),.if_inst(if_inst),.if_ready(if_ready),
        .if_req_fire(if_req_fire),.if_req_pc(if_req_pc),
        .if_resp_fire(if_resp_fire),.if_resp_pc(if_resp_pc),
        .if_resp_hold(if_resp_hold),.fetch_error_fire(fetch_error_fire),
        .adapter_busy(adapter_busy),
        .cache_hits(cache_hits),.cache_misses(cache_misses),
        .cache_refills(cache_refills),.backing_transactions(backing_transactions),
        .branch_resolve_valid(branch_resolve_valid),
        .branch_redirect(branch_redirect),.branch_redirect_pc(branch_redirect_pc),
        .load_use_stall(load_use_stall),.id_unsupported(id_unsupported),
        .id_raw_hazard(id_raw_hazard),
        .wb_commit_valid(wb_commit_valid),.wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd),.wb_commit_data(wb_commit_data),
        .mem_store_commit_valid(mem_store_commit_valid),
        .mem_store_commit_pc(mem_store_commit_pc),
        .mem_store_commit_addr(mem_store_commit_addr),
        .mem_store_commit_data(mem_store_commit_data)
    );

    reg [31:0] rom[0:WORDS-1];
    reg [31:0] exp_wb_pc[0:NCOMMITS-1],exp_wb_data[0:NCOMMITS-1];
    reg [4:0] exp_wb_rd[0:NCOMMITS-1];
    reg [31:0] exp_st_pc[0:NSTORES-1],exp_st_addr[0:NSTORES-1],
               exp_st_data[0:NSTORES-1];
    reg [31:0] exp_br_pc[0:NBRANCHES-1],exp_br_target[0:NBRANCHES-1];
    reg exp_br_taken[0:NBRANCHES-1];

    integer wb_count=0,store_count=0,branch_count=0,redirect_count=0;
    integer not_taken_count=0,unsupported_count=0,raw_count=0,stall_count=0;
    integer errors=0,deliveries=0,requests=0,responses=0;
    integer response_held_cycles=0,redirect_while_busy=0,cycles=0;
    reg last_program_word_delivered=0;
    reg outstanding=0;
    reg [31:0] outstanding_pc=0;
    reg request_held_before=0, response_held_before=0;
    reg [31:0] req_pc_before=0,resp_pc_before=0;
    reg [31:0] resp_inst_before=0;
    integer fd,word_index;
    reg [2047:0] mem_path;
    reg [31:0] branch_ex_pc_before,id_pc_before,id_inst_before;
    reg id_valid_before;

    // Force a long initial response hold (longer than first miss), then
    // periodic downstream pauses; this tests adapter ST_RESP retention.
    always @(negedge clk) begin
        if (rst) begin
            if_delivery_allow = 1'b0;
            cycles = 0;
        end else begin
            cycles = cycles+1;
            if_delivery_allow = (cycles>=70) && ((cycles % 29)>=6);
        end
    end

    // Verify outputs BEFORE sequential update at each rising edge.
    always @(posedge clk) begin
        if (!rst) begin
            if (fetch_error_fire) begin
                errors=errors+1;
                $display("FAIL fetch error at virtual PC=%h",if_resp_pc);
            end
            if (if_ready !== (!load_use_stall && !branch_redirect)) begin
                errors=errors+1;
                $display("FAIL CPU IF_READY priority");
            end
            if (dut.u_cpu.ex_valid && (dut.u_cpu.wait_a || dut.u_cpu.wait_b)) begin
                errors=errors+1;
                $display("FAIL unresolved EX forwarding hazard PC=%h",dut.u_cpu.ex_pc);
            end
            if (if_valid && !if_delivery_allow) begin
                errors=errors+1;
                $display("FAIL CPU IF valid when delivery disallowed");
            end
            if (request_held_before && !branch_redirect &&
                if_req_pc !== req_pc_before) begin
                errors=errors+1;
                $display("FAIL PC/IF outstanding request address changed");
            end
            request_held_before = !branch_redirect && !if_req_fire;
            req_pc_before = if_req_pc;
            if (response_held_before && !branch_redirect &&
                (if_resp_pc !== resp_pc_before ||
                 dut.u_adapter.if_resp_inst !== resp_inst_before)) begin
                errors=errors+1;
                $display("FAIL stalled adapter response changed");
            end
            response_held_before = if_resp_hold;
            resp_pc_before = if_resp_pc;
            resp_inst_before = dut.u_adapter.if_resp_inst;
            if (if_resp_hold) response_held_cycles=response_held_cycles+1;
            if (id_unsupported) unsupported_count=unsupported_count+1;
            if (id_raw_hazard) raw_count=raw_count+1;
            if (load_use_stall) stall_count=stall_count+1;

            if (wb_commit_valid) begin
                if (wb_count >= NCOMMITS) begin
                    errors=errors+1;
                    $display("FAIL extra WB %h r%0d=%h",wb_commit_pc,wb_commit_rd,wb_commit_data);
                end else if (wb_commit_pc !== exp_wb_pc[wb_count] ||
                    wb_commit_rd !== exp_wb_rd[wb_count] ||
                    wb_commit_data !== exp_wb_data[wb_count]) begin
                    errors=errors+1;
                    $display("FAIL WB[%0d] pc=%h r%0d=%h expected pc=%h r%0d=%h",
                         wb_count,wb_commit_pc,wb_commit_rd,wb_commit_data,
                         exp_wb_pc[wb_count],exp_wb_rd[wb_count],exp_wb_data[wb_count]);
                end
                wb_count=wb_count+1;
            end
            if (mem_store_commit_valid) begin
                if (store_count >= NSTORES) begin
                    errors=errors+1;
                    $display("FAIL wrong-path/extra STORE pc=%h addr=%h data=%h",
                          mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data);
                end else if (mem_store_commit_pc !== exp_st_pc[store_count] ||
                             mem_store_commit_addr !== exp_st_addr[store_count] ||
                             mem_store_commit_data !== exp_st_data[store_count]) begin
                    errors=errors+1;
                    $display("FAIL STORE[%0d] pc=%h addr=%h data=%h expected pc=%h addr=%h data=%h",
                         store_count,mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data,
                         exp_st_pc[store_count],exp_st_addr[store_count],exp_st_data[store_count]);
                end
                store_count=store_count+1;
            end
            if (branch_resolve_valid) begin
                if (branch_count >= NBRANCHES) begin
                    errors=errors+1;
                    $display("FAIL extra BR at PC=%h",dut.u_cpu.ex_pc);
                end else if (dut.u_cpu.ex_pc !== exp_br_pc[branch_count] ||
                    branch_redirect !== exp_br_taken[branch_count] ||
                    (branch_redirect && branch_redirect_pc !== exp_br_target[branch_count])) begin
                    errors=errors+1;
                    $display("FAIL BR[%0d] PC=%h taken=%b target=%h expected PC=%h taken=%b target=%h",
                        branch_count,dut.u_cpu.ex_pc,branch_redirect,branch_redirect_pc,
                        exp_br_pc[branch_count],exp_br_taken[branch_count],exp_br_target[branch_count]);
                end
                branch_count=branch_count+1;
                if (branch_redirect) redirect_count=redirect_count+1;
                else not_taken_count=not_taken_count+1;
            end else if (branch_redirect) begin
                errors=errors+1;
                $display("FAIL redirect without branch resolve");
            end
            if (branch_redirect) begin
                if (if_ready || if_resp_fire || if_req_fire ||
                    branch_redirect_pc < PC_BASE ||
                    branch_redirect_pc >= PC_BASE+WORDS*4 ||
                    branch_redirect_pc[1:0]!=0) begin
                    errors=errors+1;
                    $display("FAIL redirect priority/target PC=%h",branch_redirect_pc);
                end
                if (adapter_busy) redirect_while_busy=redirect_while_busy+1;
                outstanding=0; // kill old-path outstanding request
            end else begin
                if (if_req_fire) begin
                    if (outstanding || if_req_pc<PC_BASE ||
                        if_req_pc >= PC_BASE+WORDS*4 ||
                        if_req_pc[1:0]!=0) begin
                        errors=errors+1;
                        $display("FAIL request overlap/range PC=%h",if_req_pc);
                    end
                    outstanding=1;
                    outstanding_pc=if_req_pc;
                    requests=requests+1;
                end
                if (if_resp_fire) begin
                    if (!outstanding || if_resp_pc !== outstanding_pc) begin
                        errors=errors+1;
                        $display("FAIL response PC/epoch PC=%h pending=%h valid=%b",
                             if_resp_pc,outstanding_pc,outstanding);
                    end
                    outstanding=0;
                    responses=responses+1;
                end
            end
            if (if_valid && if_ready) begin
                if (if_pc < PC_BASE || if_pc >= PC_BASE+WORDS*4 ||
                    if_pc[1:0]!=0) begin
                    errors=errors+1;
                    $display("FAIL delivered PC out of range: %h",if_pc);
                end else begin
                    word_index=(if_pc-PC_BASE)>>2;
                    if (if_inst !== rom[word_index]) begin
                        errors=errors+1;
                        $display("FAIL IF[%0d] PC=%h instruction=%h expected %h",
                            deliveries,if_pc,if_inst,rom[word_index]);
                    end
                end
                deliveries=deliveries+1;
                if (if_pc == PC_BASE + (WORDS-1)*4)
                    last_program_word_delivered=1;
                if (!if_resp_fire) begin
                    errors=errors+1;
                    $display("FAIL CPU accepted without adapter response");
                end
            end else if (if_resp_fire && !fetch_error_fire) begin
                errors=errors+1;
                $display("FAIL adapter response consumed but CPU did not accept");
            end
            if (load_use_stall && !branch_redirect) begin
                id_pc_before=dut.u_cpu.id_pc;
                id_inst_before=dut.u_cpu.id_inst;
                id_valid_before=dut.u_cpu.id_valid;
                #1;
                if (dut.u_cpu.id_pc !== id_pc_before ||
                    dut.u_cpu.id_inst !== id_inst_before ||
                    dut.u_cpu.id_valid !== id_valid_before ||
                    dut.u_cpu.ex_valid !== 1'b0 ||
                    dut.u_cpu.mem_valid !== 1'b1) begin
                    errors=errors+1;
                    $display("FAIL load-use hold/bubble/older MEM progression");
                end
            end else if (branch_redirect) begin
                branch_ex_pc_before=dut.u_cpu.ex_pc;
                #1;
                if (dut.u_cpu.id_valid !== 1'b0 ||
                    dut.u_cpu.ex_valid !== 1'b0 ||
                    dut.u_cpu.mem_valid !== 1'b1 ||
                    dut.u_cpu.mem_pc !== branch_ex_pc_before) begin
                    errors=errors+1;
                    $display("FAIL redirect younger Flush/older MEM preservation");
                end
            end
        end
    end

    initial begin
        mem_path=MEM_FILE;
        if ($value$plusargs("MEM_FILE=%s",mem_path))
            $display("INFO MEM_FILE plusarg provided");
        fd=$fopen(mem_path,"r");
        if (fd==0) begin
            $display("FAIL cannot open V0.5 ROM file: %0s",mem_path);
            $finish;
        end
        $fclose(fd);
        // After imem_latency's initial defaults have run at time 0,
        // initialize its official ROM through TB hierarchy (RTL UNCHANGED).
        #1;
        $readmemh(mem_path, rom);
        $readmemh(mem_path, dut.u_imem.rom);
        // Independently derived architectural expectations from V0.4 ISA test.
        exp_wb_pc[0] = 32'h00001000; exp_wb_rd[0] = 5'd1; exp_wb_data[0] = 32'h00000005;
        exp_wb_pc[1] = 32'h00001004; exp_wb_rd[1] = 5'd2; exp_wb_data[1] = 32'h00000005;
        exp_wb_pc[2] = 32'h00001014; exp_wb_rd[2] = 5'd3; exp_wb_data[2] = 32'h00000007;
        exp_wb_pc[3] = 32'h00001028; exp_wb_rd[3] = 5'd4; exp_wb_data[3] = 32'h00000009;
        exp_wb_pc[4] = 32'h00001030; exp_wb_rd[4] = 5'd5; exp_wb_data[4] = 32'h0000000b;
        exp_wb_pc[5] = 32'h00001040; exp_wb_rd[5] = 5'd1; exp_wb_data[5] = 32'h00001044;
        exp_wb_pc[6] = 32'h0000104c; exp_wb_rd[6] = 5'd8; exp_wb_data[6] = 32'h00001044;
        exp_wb_pc[7] = 32'h00001050; exp_wb_rd[7] = 5'd12; exp_wb_data[7] = 32'h00001000;
        exp_wb_pc[8] = 32'h00001054; exp_wb_rd[8] = 5'd12; exp_wb_data[8] = 32'h00001064;
        exp_wb_pc[9] = 32'h00001058; exp_wb_rd[9] = 5'd13; exp_wb_data[9] = 32'h0000105c;
        exp_wb_pc[10] = 32'h00001064; exp_wb_rd[10] = 5'd15; exp_wb_data[10] = 32'h0000105c;
        exp_wb_pc[11] = 32'h0000106c; exp_wb_rd[11] = 5'd16; exp_wb_data[11] = 32'h00000007;
        exp_wb_pc[12] = 32'h0000107c; exp_wb_rd[12] = 5'd18; exp_wb_data[12] = 32'h00000001;
        exp_wb_pc[13] = 32'h00001088; exp_wb_rd[13] = 5'd19; exp_wb_data[13] = 32'h00000001;
        exp_wb_pc[14] = 32'h0000108c; exp_wb_rd[14] = 5'd20; exp_wb_data[14] = 32'h00000005;
        exp_wb_pc[15] = 32'h00001090; exp_wb_rd[15] = 5'd21; exp_wb_data[15] = 32'h00000003;
        exp_wb_pc[16] = 32'h00001098; exp_wb_rd[16] = 5'd22; exp_wb_data[16] = 32'h00000000;
        exp_wb_pc[17] = 32'h0000109c; exp_wb_rd[17] = 5'd23; exp_wb_data[17] = 32'h00000003;
        exp_wb_pc[18] = 32'h000010a0; exp_wb_rd[18] = 5'd22; exp_wb_data[18] = 32'h00000001;
        exp_wb_pc[19] = 32'h000010a0; exp_wb_rd[19] = 5'd22; exp_wb_data[19] = 32'h00000002;
        exp_wb_pc[20] = 32'h000010a0; exp_wb_rd[20] = 5'd22; exp_wb_data[20] = 32'h00000003;
        exp_wb_pc[21] = 32'h000010a8; exp_wb_rd[21] = 5'd24; exp_wb_data[21] = 32'h00000004;
        exp_wb_pc[22] = 32'h000010bc; exp_wb_rd[22] = 5'd26; exp_wb_data[22] = 32'h00000004;
        exp_wb_pc[23] = 32'h000010c0; exp_wb_rd[23] = 5'd27; exp_wb_data[23] = 32'h00000005;
        exp_wb_pc[24] = 32'h000010c8; exp_wb_rd[24] = 5'd28; exp_wb_data[24] = 32'h00000005;
        exp_wb_pc[25] = 32'h000010d4; exp_wb_rd[25] = 5'd29; exp_wb_data[25] = 32'h00000003;
        exp_wb_pc[26] = 32'h000010e4; exp_wb_rd[26] = 5'd31; exp_wb_data[26] = 32'h00000001;
        exp_st_pc[0] = 32'h00001068; exp_st_addr[0] = 32'h00000000; exp_st_data[0] = 32'h00000007;
        exp_st_pc[1] = 32'h00001084; exp_st_addr[1] = 32'h00000004; exp_st_data[1] = 32'h00000001;
        exp_st_pc[2] = 32'h00001094; exp_st_addr[2] = 32'h00000008; exp_st_data[2] = 32'h00000003;
        exp_st_pc[3] = 32'h000010ac; exp_st_addr[3] = 32'h0000000c; exp_st_data[3] = 32'h00000004;
        exp_st_pc[4] = 32'h000010d0; exp_st_addr[4] = 32'h00000010; exp_st_data[4] = 32'h00000005;
        exp_st_pc[5] = 32'h000010f0; exp_st_addr[5] = 32'h00000014; exp_st_data[5] = 32'h00000001;
        exp_br_pc[0] = 32'h00001008; exp_br_taken[0] = 1'b1; exp_br_target[0] = 32'h00001014;
        exp_br_pc[1] = 32'h00001018; exp_br_taken[1] = 1'b1; exp_br_target[1] = 32'h00001024;
        exp_br_pc[2] = 32'h00001024; exp_br_taken[2] = 1'b0; exp_br_target[2] = 32'h00000000;
        exp_br_pc[3] = 32'h0000102c; exp_br_taken[3] = 1'b0; exp_br_target[3] = 32'h00000000;
        exp_br_pc[4] = 32'h00001034; exp_br_taken[4] = 1'b1; exp_br_target[4] = 32'h00001040;
        exp_br_pc[5] = 32'h00001040; exp_br_taken[5] = 1'b1; exp_br_target[5] = 32'h0000104c;
        exp_br_pc[6] = 32'h00001058; exp_br_taken[6] = 1'b1; exp_br_target[6] = 32'h00001064;
        exp_br_pc[7] = 32'h00001070; exp_br_taken[7] = 1'b1; exp_br_target[7] = 32'h0000107c;
        exp_br_pc[8] = 32'h00001080; exp_br_taken[8] = 1'b0; exp_br_target[8] = 32'h00000000;
        exp_br_pc[9] = 32'h000010a4; exp_br_taken[9] = 1'b1; exp_br_target[9] = 32'h000010a0;
        exp_br_pc[10] = 32'h000010a4; exp_br_taken[10] = 1'b1; exp_br_target[10] = 32'h000010a0;
        exp_br_pc[11] = 32'h000010a4; exp_br_taken[11] = 1'b0; exp_br_target[11] = 32'h00000000;
        exp_br_pc[12] = 32'h000010b0; exp_br_taken[12] = 1'b1; exp_br_target[12] = 32'h000010bc;
        exp_br_pc[13] = 32'h000010c4; exp_br_taken[13] = 1'b0; exp_br_target[13] = 32'h00000000;
        exp_br_pc[14] = 32'h000010cc; exp_br_taken[14] = 1'b0; exp_br_target[14] = 32'h00000000;
        exp_br_pc[15] = 32'h000010d8; exp_br_taken[15] = 1'b1; exp_br_target[15] = 32'h000010e4;
        repeat(3) @(negedge clk);
        rst=1'b0;
        // Wait for all expected architectural events, then drain extra cycles
        // to catch illegal duplicate commits / stores.
        wait(last_program_word_delivered && wb_count>=NCOMMITS &&
             store_count>=NSTORES && branch_count>=NBRANCHES);
        repeat(12) @(negedge clk);
        if (wb_count!=NCOMMITS || store_count!=NSTORES || branch_count!=NBRANCHES)
            errors=errors+1;
        if (unsupported_count!=2 || redirect_count!=10 || not_taken_count!=6) begin
            errors=errors+1;
            $display("FAIL expected unsupported=2 / taken=10 / not-taken=6");
        end
        if (cache_hits==0 || cache_misses==0 || cache_refills<4 ||
            cache_refills!=backing_transactions ||
            requests==0 || responses==0 ||
            response_held_cycles==0 || redirect_while_busy==0) begin
            errors=errors+1;
            $display("FAIL required cache hit/miss/refill/response-hold/redirect-drain coverage");
        end
        $display("RESULT V0.5: ROM=%0d delivered=%0d req=%0d resp=%0d WB=%0d/%0d STORE=%0d/%0d BR=%0d/%0d redirects=%0d not_taken=%0d unsupported=%0d errors=%0d",
            WORDS,deliveries,requests,responses,wb_count,NCOMMITS,
            store_count,NSTORES,branch_count,NBRANCHES,redirect_count,not_taken_count,
            unsupported_count,errors);
        $display("CACHE: hits=%0d misses=%0d refills=%0d backing_transactions=%0d held_response_cycles=%0d redirect_while_busy=%0d load_use_stalls=%0d RAW=%0d",
            cache_hits,cache_misses,cache_refills,backing_transactions,
            response_held_cycles,redirect_while_busy,stall_count,raw_count);
        if (errors==0) $display("ALL TESTS PASSED (pipeline CPU V0.5 cache integration)");
        else $display("TEST FAILED (pipeline CPU V0.5): errors=%0d",errors);
        $finish;
    end
    initial begin
        #100000;
        $display("FAIL timeout V0.5: WB=%0d/%0d STORE=%0d/%0d BR=%0d/%0d req=%0d resp=%0d",
                 wb_count,NCOMMITS,store_count,NSTORES,branch_count,NBRANCHES,requests,responses);
        $finish;
    end
endmodule
