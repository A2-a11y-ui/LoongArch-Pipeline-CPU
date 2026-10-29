`timescale 1ns / 1ps
// Independent black-box architectural scoreboard for official CPU V0.4.
// The program differs from teammate A's branch_v04.mem.
// Verilog-2001; Vivado 2019.1.
module tb_pipeline_branch_independent_v04;
    parameter MEM_FILE = "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/branch_v04_independent.mem";
    localparam [31:0] BASE_PC = 32'h00001000;
    localparam integer ROM_WORDS = 65;
    localparam integer EXPECT_WB = 29;
    localparam integer EXPECT_ST = 8;
    localparam integer EXPECT_BR = 15;
    localparam integer EXPECT_UNSUPPORTED = 2;
    localparam integer EXPECT_TAKEN = 10;
    localparam integer EXPECT_NOT_TAKEN = 5;

    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, if_valid=0;
    reg [31:0] if_pc=0, if_inst=0;
    wire if_ready, branch_resolve_valid, branch_redirect;
    wire [31:0] branch_redirect_pc;
    wire wb_commit_valid, mem_store_commit_valid, load_use_stall;
    wire id_unsupported, id_raw_hazard;
    wire [31:0] wb_commit_pc, wb_commit_data;
    wire [4:0] wb_commit_rd;
    wire [31:0] mem_store_commit_pc, mem_store_commit_addr, mem_store_commit_data;

    pipeline_cpu_core_v04 dut (
        .clk(clk),.rst(rst),.if_valid(if_valid),.if_pc(if_pc),.if_inst(if_inst),
        .if_ready(if_ready),.branch_resolve_valid(branch_resolve_valid),
        .branch_redirect(branch_redirect),.branch_redirect_pc(branch_redirect_pc),
        .wb_commit_valid(wb_commit_valid),.wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd),.wb_commit_data(wb_commit_data),
        .mem_store_commit_valid(mem_store_commit_valid),
        .mem_store_commit_pc(mem_store_commit_pc),
        .mem_store_commit_addr(mem_store_commit_addr),
        .mem_store_commit_data(mem_store_commit_data),
        .load_use_stall(load_use_stall),
        .id_unsupported(id_unsupported),.id_raw_hazard(id_raw_hazard)
    );

    reg [31:0] rom [0:ROM_WORDS-1];
    reg [31:0] exp_wb_pc [0:EXPECT_WB-1];
    reg [4:0] exp_wb_rd [0:EXPECT_WB-1];
    reg [31:0] exp_wb_data [0:EXPECT_WB-1];
    reg [31:0] exp_st_pc [0:EXPECT_ST-1];
    reg [31:0] exp_st_addr [0:EXPECT_ST-1];
    reg [31:0] exp_st_data [0:EXPECT_ST-1];
    reg [31:0] exp_br_pc [0:EXPECT_BR-1];
    reg exp_br_taken [0:EXPECT_BR-1];
    reg [31:0] exp_br_target [0:EXPECT_BR-1];

    integer next_index=0, accepted=0, wb_count=0, st_count=0, br_count=0;
    integer unsupported_count=0, stall_count=0, raw_count=0, taken=0, not_taken=0;
    integer br_forward_exmem=0, br_forward_wb=0, errors=0;
    integer fd;
    reg [2047:0] mem_path;
    reg [31:0] held_pc,held_inst,held_ex_pc;
    reg held_valid;
    reg have_stalled=0;
    reg [31:0] blocked_if_pc, blocked_if_inst;

    // Drive the currently pending fetch word at each negative edge.
    // During LOAD STALL, the index remains unchanged (retry on ready).
    // During REDIRECT, the presented wrong-path word is cancelled.
    always @(negedge clk) begin
        if (rst || next_index >= ROM_WORDS) begin
            if_valid=0; if_pc=0; if_inst=0;
        end else begin
            if_valid=1;
            if_pc=BASE_PC + next_index*4;
            if_inst=rom[next_index];
        end
    end

    // Check transactions as seen by synchronous RegFile/DMEM on each edge.
    always @(posedge clk) begin
        if (!rst) begin
            if (if_ready !== (!load_use_stall && !branch_redirect)) begin
                errors=errors+1;
                $display("FAIL if_ready priority @%0t",$time);
            end
            if (id_unsupported) unsupported_count=unsupported_count+1;
            if (id_raw_hazard) raw_count=raw_count+1;
            if (dut.ex_valid && (dut.wait_a || dut.wait_b)) begin
                errors=errors+1;
                $display("FAIL unresolved forwarding wait EX PC=%h",dut.ex_pc);
            end

            if (wb_commit_valid) begin
                if (wb_count >= EXPECT_WB) begin
                    errors=errors+1;
                    $display("FAIL EXTRA WB PC=%h r%0d=%h",wb_commit_pc,wb_commit_rd,wb_commit_data);
                end else if (wb_commit_pc !== exp_wb_pc[wb_count] ||
                             wb_commit_rd !== exp_wb_rd[wb_count] ||
                             wb_commit_data !== exp_wb_data[wb_count]) begin
                    errors=errors+1;
                    $display("FAIL WB[%0d]: PC=%h rd=%0d data=%h; expected PC=%h rd=%0d data=%h",
                      wb_count,wb_commit_pc,wb_commit_rd,wb_commit_data,
                      exp_wb_pc[wb_count],exp_wb_rd[wb_count],exp_wb_data[wb_count]);
                end
                if (wb_commit_rd === 5'd0) begin
                    errors=errors+1;$display("FAIL illegal WB to r0");
                end
                wb_count=wb_count+1;
            end

            if (mem_store_commit_valid) begin
                if (mem_store_commit_addr>=32'd64 && mem_store_commit_addr<=32'd92) begin
                    errors=errors+1;
                    $display("FAIL wrong-path STORE address=%h PC=%h",mem_store_commit_addr,mem_store_commit_pc);
                end
                if (st_count>=EXPECT_ST) begin
                    errors=errors+1;
                    $display("FAIL extra STORE PC=%h addr=%h data=%h",
                        mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data);
                end else if (mem_store_commit_pc !== exp_st_pc[st_count] ||
                             mem_store_commit_addr !== exp_st_addr[st_count] ||
                             mem_store_commit_data !== exp_st_data[st_count]) begin
                    errors=errors+1;
                    $display("FAIL STORE[%0d]: PC=%h addr=%h data=%h; expected PC=%h addr=%h data=%h",
                        st_count,mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data,
                        exp_st_pc[st_count],exp_st_addr[st_count],exp_st_data[st_count]);
                end
                st_count=st_count+1;
            end

            if (branch_resolve_valid) begin
                if (br_count>=EXPECT_BR) begin
                    errors=errors+1;
                    $display("FAIL extra BRANCH at PC=%h",dut.ex_pc);
                end else if (dut.ex_pc !== exp_br_pc[br_count] ||
                             branch_redirect !== exp_br_taken[br_count] ||
                             branch_redirect_pc !== exp_br_target[br_count]) begin
                    errors=errors+1;
                    $display("FAIL BR[%0d]: PC=%h taken=%b target=%h; expected PC=%h taken=%b target=%h",
                        br_count,dut.ex_pc,branch_redirect,branch_redirect_pc,
                        exp_br_pc[br_count],exp_br_taken[br_count],exp_br_target[br_count]);
                end
                br_count=br_count+1;
                if (branch_redirect) taken=taken+1;
                else not_taken=not_taken+1;
                if (dut.forward_a==2'b10 || dut.forward_b==2'b10)
                    br_forward_exmem=br_forward_exmem+1;
                if (dut.forward_a==2'b01 || dut.forward_b==2'b01)
                    br_forward_wb=br_forward_wb+1;
            end else if (branch_redirect) begin
                errors=errors+1;$display("FAIL redirect without resolve");
            end

            // Only an accepted word moves the producer forward.
            // Redirect has priority over handshake and cancels old IF input.
            if (branch_redirect) begin
                if (if_ready !== 1'b0 || branch_redirect_pc < BASE_PC ||
                    branch_redirect_pc >= BASE_PC+ROM_WORDS*4 ||
                    branch_redirect_pc[1:0] != 2'b00) begin
                    errors=errors+1;
                    $display("FAIL redirect target / IF cancel, PC=%h",branch_redirect_pc);
                end else next_index=(branch_redirect_pc-BASE_PC)>>2;
                have_stalled=0;
            end else if (if_valid && if_ready) begin
                if (next_index>=ROM_WORDS || if_pc !== BASE_PC+next_index*4 ||
                    if_inst !== rom[next_index]) begin
                    errors=errors+1;
                    $display("FAIL IF handshake index=%0d pc=%h inst=%h",next_index,if_pc,if_inst);
                end
                next_index=next_index+1;
                accepted=accepted+1;
                have_stalled=0;
            end else if (load_use_stall) begin
                if (!if_valid) begin
                    errors=errors+1;$display("FAIL no IF word presented during load-use");
                end
                if (!have_stalled) begin
                    blocked_if_pc=if_pc; blocked_if_inst=if_inst;
                    have_stalled=1;
                end else if (if_pc !== blocked_if_pc || if_inst !== blocked_if_inst) begin
                    errors=errors+1;$display("FAIL IF changed during stall");
                end
            end

            if (load_use_stall) begin
                stall_count=stall_count+1;
                if (branch_redirect || if_ready!==1'b0 ||
                    !dut.id_valid || !dut.ex_valid || !dut.ex_mem_read) begin
                    errors=errors+1;
                    $display("FAIL malformed load-use stall");
                end
                held_pc=dut.id_pc;held_inst=dut.id_inst;held_valid=dut.id_valid;
                #1;
                if (dut.id_pc!==held_pc || dut.id_inst!==held_inst ||
                    dut.id_valid!==held_valid || dut.ex_valid!==1'b0 ||
                    dut.mem_valid!==1'b1 || !dut.mem_mem_read) begin
                    errors=errors+1;
                    $display("FAIL load stall: IF/ID hold, EX bubble or load advance");
                end
            end else if (branch_redirect) begin
                held_ex_pc=dut.ex_pc;
                #1;
                if (dut.id_valid!==1'b0 || dut.ex_valid!==1'b0 ||
                    dut.mem_valid!==1'b1 || dut.mem_pc!==held_ex_pc) begin
                    errors=errors+1;
                    $display("FAIL branch redirect: failed flush or EX branch lost");
                end
            end
        end
    end

    initial begin
        mem_path=MEM_FILE;
        if ($value$plusargs("MEM_FILE=%s",mem_path))
            $display("INFO using MEM_FILE override");
        fd=$fopen(mem_path,"r");
        if(fd==0)begin
            $display("FAIL missing machine-code ROM: %0s",mem_path);
            $finish;
        end
        $fclose(fd);
        $readmemh(mem_path,rom);
        $display("V0.4 INDEPENDENT BRANCH + FLUSH + LOAD/STORE REGRESSION");
        $display("ROM=%0d expected WB=%0d STORE=%0d BR=%0d",ROM_WORDS,EXPECT_WB,EXPECT_ST,EXPECT_BR);
        exp_wb_pc[0] = 32'h00001000;
        exp_wb_pc[1] = 32'h00001004;
        exp_wb_pc[2] = 32'h00001014;
        exp_wb_pc[3] = 32'h00001028;
        exp_wb_pc[4] = 32'h0000103c;
        exp_wb_pc[5] = 32'h00001048;
        exp_wb_pc[6] = 32'h0000104c;
        exp_wb_pc[7] = 32'h00001050;
        exp_wb_pc[8] = 32'h00001054;
        exp_wb_pc[9] = 32'h00001060;
        exp_wb_pc[10] = 32'h00001068;
        exp_wb_pc[11] = 32'h00001078;
        exp_wb_pc[12] = 32'h0000107c;
        exp_wb_pc[13] = 32'h00001080;
        exp_wb_pc[14] = 32'h00001080;
        exp_wb_pc[15] = 32'h00001080;
        exp_wb_pc[16] = 32'h0000108c;
        exp_wb_pc[17] = 32'h00001090;
        exp_wb_pc[18] = 32'h00001098;
        exp_wb_pc[19] = 32'h000010ac;
        exp_wb_pc[20] = 32'h000010b4;
        exp_wb_pc[21] = 32'h000010bc;
        exp_wb_pc[22] = 32'h000010c0;
        exp_wb_pc[23] = 32'h000010c8;
        exp_wb_pc[24] = 32'h000010d0;
        exp_wb_pc[25] = 32'h000010d8;
        exp_wb_pc[26] = 32'h000010e8;
        exp_wb_pc[27] = 32'h000010f8;
        exp_wb_pc[28] = 32'h000010fc;
        exp_wb_rd[0] = 5'd2;
        exp_wb_rd[1] = 5'd3;
        exp_wb_rd[2] = 5'd4;
        exp_wb_rd[3] = 5'd5;
        exp_wb_rd[4] = 5'd1;
        exp_wb_rd[5] = 5'd8;
        exp_wb_rd[6] = 5'd9;
        exp_wb_rd[7] = 5'd9;
        exp_wb_rd[8] = 5'd10;
        exp_wb_rd[9] = 5'd12;
        exp_wb_rd[10] = 5'd13;
        exp_wb_rd[11] = 5'd15;
        exp_wb_rd[12] = 5'd16;
        exp_wb_rd[13] = 5'd15;
        exp_wb_rd[14] = 5'd15;
        exp_wb_rd[15] = 5'd15;
        exp_wb_rd[16] = 5'd17;
        exp_wb_rd[17] = 5'd18;
        exp_wb_rd[18] = 5'd19;
        exp_wb_rd[19] = 5'd21;
        exp_wb_rd[20] = 5'd22;
        exp_wb_rd[21] = 5'd23;
        exp_wb_rd[22] = 5'd24;
        exp_wb_rd[23] = 5'd25;
        exp_wb_rd[24] = 5'd26;
        exp_wb_rd[25] = 5'd27;
        exp_wb_rd[26] = 5'd29;
        exp_wb_rd[27] = 5'd30;
        exp_wb_rd[28] = 5'd31;
        exp_wb_data[0] = 32'h00000004;
        exp_wb_data[1] = 32'h00000004;
        exp_wb_data[2] = 32'h00000009;
        exp_wb_data[3] = 32'h00000002;
        exp_wb_data[4] = 32'h00001040;
        exp_wb_data[5] = 32'h00001040;
        exp_wb_data[6] = 32'h00001000;
        exp_wb_data[7] = 32'h00001060;
        exp_wb_data[8] = 32'h00001058;
        exp_wb_data[9] = 32'h00001058;
        exp_wb_data[10] = 32'h00000009;
        exp_wb_data[11] = 32'h00000000;
        exp_wb_data[12] = 32'h00000003;
        exp_wb_data[13] = 32'h00000001;
        exp_wb_data[14] = 32'h00000002;
        exp_wb_data[15] = 32'h00000003;
        exp_wb_data[16] = 32'h00000003;
        exp_wb_data[17] = 32'h00000008;
        exp_wb_data[18] = 32'h00000008;
        exp_wb_data[19] = 32'h00000005;
        exp_wb_data[20] = 32'h00000005;
        exp_wb_data[21] = 32'h00000005;
        exp_wb_data[22] = 32'h00000007;
        exp_wb_data[23] = 32'h00000018;
        exp_wb_data[24] = 32'h00000007;
        exp_wb_data[25] = 32'h00000001;
        exp_wb_data[26] = 32'h00000001;
        exp_wb_data[27] = 32'h00000001;
        exp_wb_data[28] = 32'h00000003;
        exp_st_pc[0] = 32'h00001064;
        exp_st_pc[1] = 32'h00001088;
        exp_st_pc[2] = 32'h00001094;
        exp_st_pc[3] = 32'h000010b0;
        exp_st_pc[4] = 32'h000010b8;
        exp_st_pc[5] = 32'h000010c4;
        exp_st_pc[6] = 32'h000010cc;
        exp_st_pc[7] = 32'h000010f4;
        exp_st_addr[0] = 32'h00000000;
        exp_st_addr[1] = 32'h00000004;
        exp_st_addr[2] = 32'h00000008;
        exp_st_addr[3] = 32'h0000000c;
        exp_st_addr[4] = 32'h00000010;
        exp_st_addr[5] = 32'h00000014;
        exp_st_addr[6] = 32'h0000001c;
        exp_st_addr[7] = 32'h00000020;
        exp_st_data[0] = 32'h00000009;
        exp_st_data[1] = 32'h00000003;
        exp_st_data[2] = 32'h00000008;
        exp_st_data[3] = 32'h00000005;
        exp_st_data[4] = 32'h00000005;
        exp_st_data[5] = 32'h00000007;
        exp_st_data[6] = 32'h00000007;
        exp_st_data[7] = 32'h00000001;
        exp_br_pc[0] = 32'h00001008;
        exp_br_pc[1] = 32'h00001018;
        exp_br_pc[2] = 32'h00001024;
        exp_br_pc[3] = 32'h0000102c;
        exp_br_pc[4] = 32'h00001030;
        exp_br_pc[5] = 32'h0000103c;
        exp_br_pc[6] = 32'h00001054;
        exp_br_pc[7] = 32'h0000106c;
        exp_br_pc[8] = 32'h00001084;
        exp_br_pc[9] = 32'h00001084;
        exp_br_pc[10] = 32'h00001084;
        exp_br_pc[11] = 32'h0000109c;
        exp_br_pc[12] = 32'h000010a0;
        exp_br_pc[13] = 32'h000010d4;
        exp_br_pc[14] = 32'h000010dc;
        exp_br_taken[0] = 1'b1;
        exp_br_taken[1] = 1'b1;
        exp_br_taken[2] = 1'b0;
        exp_br_taken[3] = 1'b0;
        exp_br_taken[4] = 1'b1;
        exp_br_taken[5] = 1'b1;
        exp_br_taken[6] = 1'b1;
        exp_br_taken[7] = 1'b1;
        exp_br_taken[8] = 1'b1;
        exp_br_taken[9] = 1'b1;
        exp_br_taken[10] = 1'b0;
        exp_br_taken[11] = 1'b0;
        exp_br_taken[12] = 1'b1;
        exp_br_taken[13] = 1'b0;
        exp_br_taken[14] = 1'b1;
        exp_br_target[0] = 32'h00001014;
        exp_br_target[1] = 32'h00001024;
        exp_br_target[2] = 32'h00000000;
        exp_br_target[3] = 32'h00000000;
        exp_br_target[4] = 32'h0000103c;
        exp_br_target[5] = 32'h00001048;
        exp_br_target[6] = 32'h00001060;
        exp_br_target[7] = 32'h00001078;
        exp_br_target[8] = 32'h00001080;
        exp_br_target[9] = 32'h00001080;
        exp_br_target[10] = 32'h00000000;
        exp_br_target[11] = 32'h00000000;
        exp_br_target[12] = 32'h000010ac;
        exp_br_target[13] = 32'h00000000;
        exp_br_target[14] = 32'h000010e8;
        repeat(3) @(negedge clk);
        rst=0;
        // If a taken branch targets the last instructions, the producer
        // reaches ROM_WORDS after the final word is accepted.
        wait(next_index >= ROM_WORDS && wb_count >= EXPECT_WB &&
             st_count >= EXPECT_ST && br_count >= EXPECT_BR);
        repeat(10) @(negedge clk);
        #1;
        if (wb_count != EXPECT_WB || st_count != EXPECT_ST ||
            br_count != EXPECT_BR || unsupported_count != EXPECT_UNSUPPORTED ||
            taken != EXPECT_TAKEN || not_taken != EXPECT_NOT_TAKEN) begin
            errors=errors+1;
            $display("FAIL totals WB=%0d/%0d STORE=%0d/%0d BR=%0d/%0d unsupported=%0d/%0d taken=%0d/%0d not_taken=%0d/%0d",
                wb_count,EXPECT_WB,st_count,EXPECT_ST,br_count,EXPECT_BR,
                unsupported_count,EXPECT_UNSUPPORTED,taken,EXPECT_TAKEN,not_taken,EXPECT_NOT_TAKEN);
        end
        if (stall_count==0 || raw_count==0 || br_forward_exmem==0) begin
            errors=errors+1;
            $display("FAIL coverage: stalls=%0d RAW=%0d EXMEM branch fwd=%0d",
                stall_count,raw_count,br_forward_exmem);
        end
        $display("RESULT V0.4 independent: ROM=%0d accepted=%0d WB=%0d/%0d STORE=%0d/%0d BR=%0d/%0d redirect=%0d not_taken=%0d stalls=%0d unsupported=%0d errors=%0d",
            ROM_WORDS,accepted,wb_count,EXPECT_WB,st_count,EXPECT_ST,
            br_count,EXPECT_BR,taken,not_taken,stall_count,unsupported_count,errors);
        $display("COVERAGE: RAW=%0d BR_EXMEM_FWD=%0d BR_MEMWB_FWD=%0d",
            raw_count,br_forward_exmem,br_forward_wb);
        if(errors==0)$display("ALL TESTS PASSED (V0.4 independent CPU branch regression)");
        else $display("TESTS FAILED (V0.4 independent CPU branch regression)");
        $finish;
    end
    initial begin
        #8000;
        $display("FAIL WATCHDOG: IF idx=%0d WB=%0d ST=%0d BR=%0d",
            next_index,wb_count,st_count,br_count);
        $finish;
    end
endmodule
