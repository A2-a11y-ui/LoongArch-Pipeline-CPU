`timescale 1ns / 1ps
// CPU V0.4: branch redirect/flush + LD/ST/load-use + ALU forwarding.
// TB uses an external IF READY/VALID producer with redirect cancellation.
// Expected WBs/stores/branches are independently GENERATED FROM ISA semantics
// at package build time and HARD-CODED below (not read from DUT).
module tb_pipeline_cpu_core_v04;
    parameter MEM_FILE = "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/branch_v04.mem";
    localparam [31:0] PC_BASE=32'h00001000;
    localparam integer WORDS=62;
    localparam integer NCOMMITS=27;
    localparam integer NSTORES=6;
    localparam integer NBRANCHES=16;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst=1;
    reg if_valid=0;
    reg [31:0] if_pc=0, if_inst=0;
    wire if_ready, branch_resolve_valid, branch_redirect;
    wire [31:0] branch_redirect_pc;
    wire wb_commit_valid;
    wire [31:0] wb_commit_pc, wb_commit_data;
    wire [4:0] wb_commit_rd;
    wire mem_store_commit_valid;
    wire [31:0] mem_store_commit_pc, mem_store_commit_addr, mem_store_commit_data;
    wire load_use_stall, id_unsupported, id_raw_hazard;

    pipeline_cpu_core_v04 dut(
        .clk(clk), .rst(rst),
        .if_valid(if_valid), .if_pc(if_pc), .if_inst(if_inst),
        .if_ready(if_ready), .branch_resolve_valid(branch_resolve_valid),
        .branch_redirect(branch_redirect), .branch_redirect_pc(branch_redirect_pc),
        .wb_commit_valid(wb_commit_valid), .wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd), .wb_commit_data(wb_commit_data),
        .mem_store_commit_valid(mem_store_commit_valid),
        .mem_store_commit_pc(mem_store_commit_pc),
        .mem_store_commit_addr(mem_store_commit_addr),
        .mem_store_commit_data(mem_store_commit_data),
        .load_use_stall(load_use_stall), .id_unsupported(id_unsupported),
        .id_raw_hazard(id_raw_hazard)
    );

    reg [31:0] rom [0:WORDS-1];
    reg [31:0] exp_wb_pc [0:NCOMMITS-1], exp_wb_data [0:NCOMMITS-1];
    reg [4:0] exp_wb_rd [0:NCOMMITS-1];
    reg [31:0] exp_st_pc [0:NSTORES-1], exp_st_addr [0:NSTORES-1], exp_st_data [0:NSTORES-1];
    reg [31:0] exp_br_pc [0:NBRANCHES-1], exp_br_target [0:NBRANCHES-1];
    reg exp_br_taken [0:NBRANCHES-1];

    integer fetch_index=0, wb_count=0, store_count=0, branch_count=0;
    integer redirect_count=0, not_taken_count=0, load_stall_count=0;
    integer unsupported_count=0, raw_count=0, errors=0, accepted_count=0;
    integer mem_fwd_branch=0, wb_fwd_branch=0;
    integer fd, idx;
    reg [2047:0] mem_path;
    reg [31:0] pre_ex_pc, pre_ifid_pc, pre_ifid_inst;
    reg pre_ifid_valid;

    // Offer only on falling edges, to avoid input/sampling races.
    // On Load-use stall, keep the SAME fetch_index and offered instruction.
    // On redirect, the previously presented wrong-path instruction is CANCELED.
    always @(negedge clk) begin
        if (rst || fetch_index >= WORDS) begin
            if_valid = 1'b0;
            if_pc=0; if_inst=0;
        end else begin
            if_valid=1'b1;
            if_pc=PC_BASE+(fetch_index*4);
            if_inst=rom[fetch_index];
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            if (if_ready !== (!load_use_stall && !branch_redirect)) begin
                errors=errors+1;
                $display("FAIL IF_READY priority at %0t",$time);
            end
            if (dut.ex_valid && (dut.wait_a || dut.wait_b)) begin
                errors=errors+1;
                $display("FAIL unresolved EX forwarding hazard PC=%h",dut.ex_pc);
            end
            if (id_unsupported) unsupported_count=unsupported_count+1;
            if (id_raw_hazard) raw_count=raw_count+1;
            if (wb_commit_valid) begin
                if (wb_count>=NCOMMITS) begin
                    errors=errors+1;
                    $display("FAIL extra WB pc=%h rd=%0d data=%h",wb_commit_pc,wb_commit_rd,wb_commit_data);
                end else if ((wb_commit_pc !== exp_wb_pc[wb_count]) ||
                             (wb_commit_rd !== exp_wb_rd[wb_count]) ||
                             (wb_commit_data !== exp_wb_data[wb_count])) begin
                    errors=errors+1;
                    $display("FAIL WB[%0d] got %h r%0d=%h expected %h r%0d=%h",
                        wb_count, wb_commit_pc, wb_commit_rd, wb_commit_data,
                        exp_wb_pc[wb_count],exp_wb_rd[wb_count],exp_wb_data[wb_count]);
                end
                wb_count=wb_count+1;
            end
            if (mem_store_commit_valid) begin
                if (store_count>=NSTORES) begin
                    errors=errors+1;
                    $display("FAIL wrong-path/extra STORE PC=%h addr=%h data=%h",
                             mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data);
                end else if ((mem_store_commit_pc !== exp_st_pc[store_count]) ||
                             (mem_store_commit_addr !== exp_st_addr[store_count]) ||
                             (mem_store_commit_data !== exp_st_data[store_count])) begin
                    errors=errors+1;
                    $display("FAIL STORE[%0d] got %h %h=%h expected %h %h=%h",
                        store_count,mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data,
                        exp_st_pc[store_count],exp_st_addr[store_count],exp_st_data[store_count]);
                end
                store_count=store_count+1;
            end
            if (branch_resolve_valid) begin
                if (branch_count>=NBRANCHES) begin
                    errors=errors+1;
                    $display("FAIL extra branch resolve PC=%h",dut.ex_pc);
                end else if (dut.ex_pc !== exp_br_pc[branch_count] ||
                             branch_redirect !== exp_br_taken[branch_count] ||
                             (branch_redirect && branch_redirect_pc !== exp_br_target[branch_count])) begin
                    errors=errors+1;
                    $display("FAIL BR[%0d] PC=%h taken=%b target=%h expected PC=%h taken=%b target=%h",
                        branch_count,dut.ex_pc,branch_redirect,branch_redirect_pc,
                        exp_br_pc[branch_count],exp_br_taken[branch_count],exp_br_target[branch_count]);
                end
                branch_count=branch_count+1;
                if (dut.forward_a==2'b10 || dut.forward_b==2'b10)
                    mem_fwd_branch=mem_fwd_branch+1;
                if (dut.forward_a==2'b01 || dut.forward_b==2'b01)
                    wb_fwd_branch=wb_fwd_branch+1;
                if (branch_redirect) redirect_count=redirect_count+1;
                else not_taken_count=not_taken_count+1;
            end else if (branch_redirect) begin
                errors=errors+1;
                $display("FAIL redirect without branch resolve");
            end

            // Producer index is committed ONLY at the sampling edge.
            // Redirect wins over IF handshake; old presented IF is canceled.
            if (branch_redirect) begin
                if (if_ready!==1'b0 || branch_redirect_pc < PC_BASE ||
                    branch_redirect_pc >= PC_BASE + WORDS*4 ||
                    branch_redirect_pc[1:0]!=2'b00) begin
                    errors=errors+1;
                    $display("FAIL invalid branch target / IF cancellation: %h",branch_redirect_pc);
                end else fetch_index = (branch_redirect_pc-PC_BASE)>>2;
            end else if (if_valid && if_ready) begin
                if (fetch_index>=WORDS || if_pc !== PC_BASE+fetch_index*4 ||
                    if_inst !== rom[fetch_index]) begin
                    errors=errors+1;
                    $display("FAIL IF handshake idx=%0d pc=%h inst=%h",fetch_index,if_pc,if_inst);
                end
                fetch_index=fetch_index+1;
                accepted_count=accepted_count+1;
            end

            if (load_use_stall) begin
                load_stall_count=load_stall_count+1;
                if (if_ready !== 1'b0 || !dut.id_valid ||
                    !dut.ex_valid || !dut.ex_mem_read) begin
                    errors=errors+1;
                    $display("FAIL load-use stall conditions at %0t",$time);
                end
                pre_ifid_pc=dut.id_pc; pre_ifid_inst=dut.id_inst;
                pre_ifid_valid=dut.id_valid;
                #1;
                if (dut.id_pc !== pre_ifid_pc || dut.id_inst !== pre_ifid_inst ||
                    dut.id_valid !== pre_ifid_valid || dut.ex_valid !== 1'b0 ||
                    dut.mem_valid !== 1'b1 || !dut.mem_mem_read) begin
                    errors=errors+1;
                    $display("FAIL load-use: IF/ID not held, EX bubble missing or old load lost");
                end
            end else if (branch_redirect) begin
                pre_ex_pc=dut.ex_pc;
                #1;
                if (dut.id_valid !== 1'b0 || dut.ex_valid !== 1'b0 ||
                    dut.mem_valid !== 1'b1 || dut.mem_pc !== pre_ex_pc) begin
                    errors=errors+1;
                    $display("FAIL redirect: younger stages not flushed or branch lost in EX/MEM");
                end
            end
        end
    end

    initial begin
        mem_path=MEM_FILE;
        if ($value$plusargs("MEM_FILE=%s",mem_path))
            $display("INFO using MEM_FILE plusarg");
        fd=$fopen(mem_path,"r");
        if (fd==0) begin
            $display("FAIL cannot open ROM: %0s",mem_path);
            $finish;
        end
        $fclose(fd);
        $readmemh(mem_path,rom);
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
        // Run until the producer reaches the end of the program and all
        // expected commits, stores and branch resolves have been observed.
        wait(fetch_index>=WORDS && wb_count>=NCOMMITS &&
             store_count>=NSTORES && branch_count>=NBRANCHES);
        repeat(10) @(negedge clk);  // Drain and detect extra side effects.
        if (wb_count!=NCOMMITS || store_count!=NSTORES || branch_count!=NBRANCHES)
            errors=errors+1;
        if (unsupported_count!=2) begin
            errors=errors+1;
            $display("FAIL expected two illegal instructions, got %0d",unsupported_count);
        end
        if (redirect_count!=10 ||
            not_taken_count!=6) begin
            errors=errors+1;
            $display("FAIL expected taken/not-taken branch coverage");
        end
        if (load_stall_count<3 || mem_fwd_branch==0 || wb_fwd_branch==0 || raw_count==0) begin
            errors=errors+1;
            $display("FAIL required load-use/branch-forwarding/RAW coverage missing");
        end
        // Wrong-path stores at addresses 64..92 are excluded from the
        // independent Store scoreboard; any such side effect fails instantly.
        $display("RESULT V0.4: ROM=%0d accepted=%0d WB=%0d/27 STORE=%0d/6 BR=%0d/16 redirects=%0d stalls=%0d unsupported=%0d errors=%0d",
            WORDS,accepted_count,wb_count,store_count,branch_count,redirect_count,load_stall_count,unsupported_count,errors);
        $display("COVERAGE: not_taken=%0d branch_EXMEM_forward=%0d branch_MEMWB_forward=%0d RAW=%0d",
            not_taken_count,mem_fwd_branch,wb_fwd_branch,raw_count);
        if (errors==0) $display("ALL TESTS PASSED (pipeline CPU V0.4 branch redirect/flush)");
        else $display("TEST FAILED (pipeline CPU V0.4): %0d errors",errors);
        $finish;
    end
    initial begin
        #8000;
        $display("FAIL timeout V0.4: pc_index=%0d wb=%0d store=%0d branch=%0d",fetch_index,wb_count,store_count,branch_count);
        $finish;
    end
endmodule
