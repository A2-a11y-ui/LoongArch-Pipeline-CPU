`timescale 1ns / 1ps
// Independent V0.3 CPU regression - follows actual A integration RTL.
// Vivado 2019.1; Verilog-2001 only.
// 60 independent ISA-model machine words, NOT A's 62-word original test.
// Upstream IF changes only on negedge; a word is consumed only when
// if_valid && if_ready at posedge. On a stall the SAME PC/inst are held.
module tb_pipeline_loadstore_independent_v03;
    parameter MEM_FILE =
        "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/load_store_v03_independent.mem";
    localparam integer WORDS = 60;
    localparam integer N_WB = 43;
    localparam integer N_ST = 14;
    localparam [31:0] FIRST_PC = 32'h00001000;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg if_valid = 1'b0;
    reg [31:0] if_pc = 32'b0;
    reg [31:0] if_inst = 32'b0;
    wire if_ready, load_use_stall, id_unsupported, id_raw_hazard;
    wire wb_commit_valid;
    wire [31:0] wb_commit_pc, wb_commit_data;
    wire [4:0] wb_commit_rd;
    wire mem_store_commit_valid;
    wire [31:0] mem_store_commit_pc, mem_store_commit_addr;
    wire [31:0] mem_store_commit_data;

    pipeline_cpu_core_v03 dut (
        .clk(clk), .rst(rst),
        .if_valid(if_valid), .if_pc(if_pc), .if_inst(if_inst), .if_ready(if_ready),
        .wb_commit_valid(wb_commit_valid),
        .wb_commit_pc(wb_commit_pc), .wb_commit_rd(wb_commit_rd),
        .wb_commit_data(wb_commit_data),
        .mem_store_commit_valid(mem_store_commit_valid),
        .mem_store_commit_pc(mem_store_commit_pc),
        .mem_store_commit_addr(mem_store_commit_addr),
        .mem_store_commit_data(mem_store_commit_data),
        .load_use_stall(load_use_stall),
        .id_unsupported(id_unsupported),
        .id_raw_hazard(id_raw_hazard)
    );

    reg [31:0] rom [0:WORDS-1];
    reg [31:0] gold_wb_pc [0:N_WB-1];
    reg [4:0]  gold_wb_rd [0:N_WB-1];
    reg [31:0] gold_wb_data [0:N_WB-1];
    reg [31:0] gold_st_pc [0:N_ST-1];
    reg [31:0] gold_st_addr [0:N_ST-1];
    reg [31:0] gold_st_data [0:N_ST-1];

    integer issued=0, written=0, stored=0, unsupported=0, raw=0;
    integer stalls=0, store_data_stalls=0, store_base_stalls=0;
    integer load_wb_forward=0, store_data_forward=0;
    integer errors=0, fd, i;
    integer hold_checks=0;
    reg [2047:0] mem_path;
    reg [31:0] previous_pc=0, previous_inst=0;
    reg previous_stall=0;
    reg finished=0;

    // Only change IF drive on the falling edge. issued is advanced by the
    // accepted positive edge, so an unaccepted instruction remains offered.
    always @(negedge clk) begin
        if (rst || issued >= WORDS) begin
            if_valid = 1'b0;
            if_pc = 32'b0;
            if_inst = 32'b0;
        end else begin
            if_valid = 1'b1;
            if_pc = FIRST_PC + 32'd4 * issued;
            if_inst = rom[issued];
        end
    end

    // The WB and Store wires describe the transaction consumed AT this edge.
    // Sample BEFORE nonblocking pipeline and memory updates.
    always @(posedge clk) begin
        if (!rst && !finished) begin
            if (if_ready !== !load_use_stall) begin
                errors=errors+1;
                $display("FAIL READY/STall mismatch at %0t",$time);
            end
            if (previous_stall) begin
                if (if_valid !== 1'b1 || if_pc !== previous_pc ||
                    if_inst !== previous_inst) begin
                    errors=errors+1;
                    $display("FAIL IF input changed across stall at %0t",$time);
                end
            end
            previous_stall = (if_valid && if_ready === 1'b0);
            if (previous_stall) begin
                previous_pc=if_pc;
                previous_inst=if_inst;
            end
            if (if_valid && if_ready) begin
                if (issued >= WORDS ||
                    if_pc !== FIRST_PC + 32'd4 * issued ||
                    if_inst !== rom[issued]) begin
                    errors=errors+1;
                    $display("FAIL IF duplicate/loss issued=%0d pc=%h inst=%h",issued,if_pc,if_inst);
                end
                issued=issued+1;
            end
            if (id_unsupported) unsupported=unsupported+1;
            if (id_raw_hazard) raw=raw+1;
            if (load_use_stall) begin
                stalls=stalls+1;
                if (if_ready !== 1'b0 || dut.ex_mem_read !== 1'b1 ||
                    dut.id_valid !== 1'b1) begin
                    errors=errors+1;
                    $display("FAIL load-use stall qualification at %0t",$time);
                end
                if (dut.d_mem_write && dut.d_rs2_used &&
                    dut.d_rs2_addr == dut.ex_rd_addr)
                    store_data_stalls=store_data_stalls+1;
                if (dut.d_mem_write && dut.d_rs1_used &&
                    dut.d_rs1_addr == dut.ex_rd_addr)
                    store_base_stalls=store_base_stalls+1;
            end
            if (dut.ex_valid && dut.ex_mem_write && dut.forward_b != 2'b00)
                store_data_forward=store_data_forward+1;
            if (wb_commit_valid) begin
                if (written >= N_WB) begin
                    errors=errors+1;
                    $display("FAIL EXTRA WB pc=%h rd=%0d data=%h",wb_commit_pc,wb_commit_rd,wb_commit_data);
                end else if (wb_commit_pc !== gold_wb_pc[written] ||
                             wb_commit_rd !== gold_wb_rd[written] ||
                             wb_commit_data !== gold_wb_data[written]) begin
                    errors=errors+1;
                    $display("FAIL WB[%0d] got pc=%h rd=%0d data=%h; expect pc=%h rd=%0d data=%h",
                             written,wb_commit_pc,wb_commit_rd,wb_commit_data,
                             gold_wb_pc[written],gold_wb_rd[written],gold_wb_data[written]);
                end
                if (wb_commit_rd === 5'd0) begin
                    errors=errors+1; $display("FAIL invalid r0 WB");
                end
                written=written+1;
            end
            if (mem_store_commit_valid) begin
                if (stored >= N_ST) begin
                    errors=errors+1;
                    $display("FAIL EXTRA STORE pc=%h addr=%h data=%h",
                             mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data);
                end else if (mem_store_commit_pc !== gold_st_pc[stored] ||
                             mem_store_commit_addr !== gold_st_addr[stored] ||
                             mem_store_commit_data !== gold_st_data[stored]) begin
                    errors=errors+1;
                    $display("FAIL STORE[%0d] got pc=%h addr=%h data=%h; expect pc=%h addr=%h data=%h",
                             stored,mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data,
                             gold_st_pc[stored],gold_st_addr[stored],gold_st_data[stored]);
                end
                if (mem_store_commit_addr[1:0] !== 2'b00) begin
                    errors=errors+1; $display("FAIL unaligned store");
                end
                stored=stored+1;
            end
        end
    end

    // Check pipeline invariant one delta after the interlock edge:
    // ID holds its PC/inst; EX is bubbled; the old load reaches MEM.
    always @(posedge clk) begin : check_load_use_pipeline
        reg [31:0] saved_pc, saved_inst;
        reg saved_valid;
        if (!rst && load_use_stall === 1'b1) begin
            saved_pc = dut.id_pc;
            saved_inst = dut.id_inst;
            saved_valid = dut.id_valid;
            #1;
            hold_checks=hold_checks+1;
            if (dut.id_pc !== saved_pc ||
                dut.id_inst !== saved_inst ||
                dut.id_valid !== saved_valid ||
                dut.ex_valid !== 1'b0 ||
                dut.mem_valid !== 1'b1 ||
                dut.mem_mem_read !== 1'b1) begin
                errors=errors+1;
                $display("FAIL load-use register hold/bubble/old-load-advance at %0t",$time);
            end
        end
    end

    initial begin
        mem_path=MEM_FILE;
        if ($value$plusargs("MEM_FILE=%s",mem_path))
            $display("INFO overridden MEM_FILE = %0s",mem_path);
        fd=$fopen(mem_path,"r");
        if (!fd) begin
            $display("FAIL cannot open memory file: %0s",mem_path);
            $finish;
        end
        $fclose(fd);
        for (i=0;i<WORDS;i=i+1) rom[i]=32'hxxxxxxxx;
        $readmemh(mem_path,rom);
        if (rom[0] !== 32'h02801401 || rom[WORDS-1] !== 32'h00102d6c) begin
            $display("FAIL expected different independent ROM (check file path)");
            $finish;
        end
        // These expected results were independently computed using ISA
        // reference execution: no data is copied from DUT outputs.
        gold_wb_pc[0]=32'h00001000; gold_wb_rd[0]=5'd1; gold_wb_data[0]=32'h00000005;
        gold_wb_pc[1]=32'h00001004; gold_wb_rd[1]=5'd2; gold_wb_data[1]=32'h0000000b;
        gold_wb_pc[2]=32'h00001008; gold_wb_rd[2]=5'd3; gold_wb_data[2]=32'h00000010;
        gold_wb_pc[3]=32'h00001010; gold_wb_rd[3]=5'd4; gold_wb_data[3]=32'h00000010;
        gold_wb_pc[4]=32'h00001014; gold_wb_rd[4]=5'd5; gold_wb_data[4]=32'h00000013;
        gold_wb_pc[5]=32'h0000101c; gold_wb_rd[5]=5'd6; gold_wb_data[5]=32'h00000013;
        gold_wb_pc[6]=32'h00001024; gold_wb_rd[6]=5'd7; gold_wb_data[6]=32'h00000013;
        gold_wb_pc[7]=32'h00001028; gold_wb_rd[7]=5'd8; gold_wb_data[7]=32'h00000026;
        gold_wb_pc[8]=32'h0000102c; gold_wb_rd[8]=5'd9; gold_wb_data[8]=32'h00000021;
        gold_wb_pc[9]=32'h00001034; gold_wb_rd[9]=5'd10; gold_wb_data[9]=32'h00000021;
        gold_wb_pc[10]=32'h00001038; gold_wb_rd[10]=5'd11; gold_wb_data[10]=32'h0000002c;
        gold_wb_pc[11]=32'h0000103c; gold_wb_rd[11]=5'd12; gold_wb_data[11]=32'h00000040;
        gold_wb_pc[12]=32'h00001044; gold_wb_rd[12]=5'd13; gold_wb_data[12]=32'h0000002c;
        gold_wb_pc[13]=32'h00001048; gold_wb_rd[13]=5'd14; gold_wb_data[13]=32'h00000028;
        gold_wb_pc[14]=32'h00001050; gold_wb_rd[14]=5'd15; gold_wb_data[14]=32'h00000028;
        gold_wb_pc[15]=32'h00001054; gold_wb_rd[15]=5'd16; gold_wb_data[15]=32'h00000050;
        gold_wb_pc[16]=32'h00001058; gold_wb_rd[16]=5'd17; gold_wb_data[16]=32'h00000060;
        gold_wb_pc[17]=32'h00001060; gold_wb_rd[17]=5'd18; gold_wb_data[17]=32'h00000060;
        gold_wb_pc[18]=32'h00001068; gold_wb_rd[18]=5'd19; gold_wb_data[18]=32'h00000005;
        gold_wb_pc[19]=32'h0000106c; gold_wb_rd[19]=5'd20; gold_wb_data[19]=32'h00000010;
        gold_wb_pc[20]=32'h00001070; gold_wb_rd[20]=5'd21; gold_wb_data[20]=32'h00000001;
        gold_wb_pc[21]=32'h00001074; gold_wb_rd[21]=5'd21; gold_wb_data[21]=32'h00000003;
        gold_wb_pc[22]=32'h00001078; gold_wb_rd[22]=5'd21; gold_wb_data[22]=32'h0000000a;
        gold_wb_pc[23]=32'h0000107c; gold_wb_rd[23]=5'd22; gold_wb_data[23]=32'h00000014;
        gold_wb_pc[24]=32'h00001084; gold_wb_rd[24]=5'd23; gold_wb_data[24]=32'h00000014;
        gold_wb_pc[25]=32'h0000108c; gold_wb_rd[25]=5'd24; gold_wb_data[25]=32'h00000000;
        gold_wb_pc[26]=32'h00001090; gold_wb_rd[26]=5'd25; gold_wb_data[26]=32'hfffffffd;
        gold_wb_pc[27]=32'h00001098; gold_wb_rd[27]=5'd26; gold_wb_data[27]=32'hfffffffd;
        gold_wb_pc[28]=32'h0000109c; gold_wb_rd[28]=5'd27; gold_wb_data[28]=32'h00000001;
        gold_wb_pc[29]=32'h000010a0; gold_wb_rd[29]=5'd28; gold_wb_data[29]=32'h00000000;
        gold_wb_pc[30]=32'h000010a4; gold_wb_rd[30]=5'd29; gold_wb_data[30]=32'hffffffff;
        gold_wb_pc[31]=32'h000010a8; gold_wb_rd[31]=5'd30; gold_wb_data[31]=32'h00000010;
        gold_wb_pc[32]=32'h000010ac; gold_wb_rd[32]=5'd31; gold_wb_data[32]=32'h00000004;
        gold_wb_pc[33]=32'h000010b4; gold_wb_rd[33]=5'd3; gold_wb_data[33]=32'h00000004;
        gold_wb_pc[34]=32'h000010b8; gold_wb_rd[34]=5'd4; gold_wb_data[34]=32'h00000009;
        gold_wb_pc[35]=32'h000010c0; gold_wb_rd[35]=5'd5; gold_wb_data[35]=32'h00000009;
        gold_wb_pc[36]=32'h000010c4; gold_wb_rd[36]=5'd6; gold_wb_data[36]=32'h00000012;
        gold_wb_pc[37]=32'h000010d0; gold_wb_rd[37]=5'd7; gold_wb_data[37]=32'h00000014;
        gold_wb_pc[38]=32'h000010d8; gold_wb_rd[38]=5'd8; gold_wb_data[38]=32'h00000014;
        gold_wb_pc[39]=32'h000010dc; gold_wb_rd[39]=5'd9; gold_wb_data[39]=32'h00000035;
        gold_wb_pc[40]=32'h000010e0; gold_wb_rd[40]=5'd10; gold_wb_data[40]=32'h00000000;
        gold_wb_pc[41]=32'h000010e8; gold_wb_rd[41]=5'd11; gold_wb_data[41]=32'h00000000;
        gold_wb_pc[42]=32'h000010ec; gold_wb_rd[42]=5'd12; gold_wb_data[42]=32'h00000000;
        gold_st_pc[0]=32'h0000100c; gold_st_addr[0]=32'h00000000; gold_st_data[0]=32'h00000010;
        gold_st_pc[1]=32'h00001018; gold_st_addr[1]=32'h00000004; gold_st_data[1]=32'h00000013;
        gold_st_pc[2]=32'h00001020; gold_st_addr[2]=32'h00000008; gold_st_data[2]=32'h00000013;
        gold_st_pc[3]=32'h00001030; gold_st_addr[3]=32'h0000000c; gold_st_data[3]=32'h00000021;
        gold_st_pc[4]=32'h00001040; gold_st_addr[4]=32'h00000040; gold_st_data[4]=32'h0000002c;
        gold_st_pc[5]=32'h0000104c; gold_st_addr[5]=32'h0000003c; gold_st_data[5]=32'h00000028;
        gold_st_pc[6]=32'h0000105c; gold_st_addr[6]=32'h00000014; gold_st_data[6]=32'h00000060;
        gold_st_pc[7]=32'h00001064; gold_st_addr[7]=32'h00000060; gold_st_data[7]=32'h00000005;
        gold_st_pc[8]=32'h00001088; gold_st_addr[8]=32'h00000018; gold_st_data[8]=32'h00000000;
        gold_st_pc[9]=32'h00001094; gold_st_addr[9]=32'h0000001c; gold_st_data[9]=32'hfffffffd;
        gold_st_pc[10]=32'h000010b0; gold_st_addr[10]=32'h00000020; gold_st_data[10]=32'h00000004;
        gold_st_pc[11]=32'h000010bc; gold_st_addr[11]=32'h00000024; gold_st_data[11]=32'h00000009;
        gold_st_pc[12]=32'h000010d4; gold_st_addr[12]=32'h00000028; gold_st_data[12]=32'h00000014;
        gold_st_pc[13]=32'h000010e4; gold_st_addr[13]=32'h0000002c; gold_st_data[13]=32'h00000000;
        $display("CPU V0.3 INDEPENDENT READY/VALID + LOAD/STORE REGRESSION");
        $display("Input words=%0d expected WB=%0d expected STORE=%0d",WORDS,N_WB,N_ST);
        repeat (2) @(negedge clk);
        rst=1'b0;
        wait(issued == WORDS);
        repeat (14) @(negedge clk);
        #1;
        finished=1;
        if (written!=N_WB || stored!=N_ST || unsupported!=2) begin
            errors=errors+1;
            $display("FAIL totals WB=%0d/%0d STORE=%0d/%0d UNSUPPORTED=%0d/2",
                     written,N_WB,stored,N_ST,unsupported);
        end
        if (stalls<3 || store_data_stalls<1 || store_base_stalls<1 ||
            store_data_forward<1 || raw<1 || hold_checks < 3) begin
            errors=errors+1;
            $display("FAIL coverage stalls=%0d store_data_stalls=%0d store_base_stalls=%0d store_fwd=%0d raw=%0d",
                     stalls,store_data_stalls,store_base_stalls,store_data_forward,raw);
        end
        // Secondary final-state RAM checks for every Store destination.
        // Store-event / load-result scoreboards above remain primary.
        if (dut.u_dmem.mem[0] !== 32'h00000010) begin
            errors=errors+1;
            $display("FAIL final DMEM[0] expected 00000010 got=%h",dut.u_dmem.mem[0]);
        end
        if (dut.u_dmem.mem[1] !== 32'h00000013) begin
            errors=errors+1;
            $display("FAIL final DMEM[1] expected 00000013 got=%h",dut.u_dmem.mem[1]);
        end
        if (dut.u_dmem.mem[2] !== 32'h00000013) begin
            errors=errors+1;
            $display("FAIL final DMEM[2] expected 00000013 got=%h",dut.u_dmem.mem[2]);
        end
        if (dut.u_dmem.mem[3] !== 32'h00000021) begin
            errors=errors+1;
            $display("FAIL final DMEM[3] expected 00000021 got=%h",dut.u_dmem.mem[3]);
        end
        if (dut.u_dmem.mem[5] !== 32'h00000060) begin
            errors=errors+1;
            $display("FAIL final DMEM[5] expected 00000060 got=%h",dut.u_dmem.mem[5]);
        end
        if (dut.u_dmem.mem[6] !== 32'h00000000) begin
            errors=errors+1;
            $display("FAIL final DMEM[6] expected 00000000 got=%h",dut.u_dmem.mem[6]);
        end
        if (dut.u_dmem.mem[7] !== 32'hfffffffd) begin
            errors=errors+1;
            $display("FAIL final DMEM[7] expected fffffffd got=%h",dut.u_dmem.mem[7]);
        end
        if (dut.u_dmem.mem[8] !== 32'h00000004) begin
            errors=errors+1;
            $display("FAIL final DMEM[8] expected 00000004 got=%h",dut.u_dmem.mem[8]);
        end
        if (dut.u_dmem.mem[9] !== 32'h00000009) begin
            errors=errors+1;
            $display("FAIL final DMEM[9] expected 00000009 got=%h",dut.u_dmem.mem[9]);
        end
        if (dut.u_dmem.mem[10] !== 32'h00000014) begin
            errors=errors+1;
            $display("FAIL final DMEM[10] expected 00000014 got=%h",dut.u_dmem.mem[10]);
        end
        if (dut.u_dmem.mem[11] !== 32'h00000000) begin
            errors=errors+1;
            $display("FAIL final DMEM[11] expected 00000000 got=%h",dut.u_dmem.mem[11]);
        end
        if (dut.u_dmem.mem[15] !== 32'h00000028) begin
            errors=errors+1;
            $display("FAIL final DMEM[15] expected 00000028 got=%h",dut.u_dmem.mem[15]);
        end
        if (dut.u_dmem.mem[16] !== 32'h0000002c) begin
            errors=errors+1;
            $display("FAIL final DMEM[16] expected 0000002c got=%h",dut.u_dmem.mem[16]);
        end
        if (dut.u_dmem.mem[24] !== 32'h00000005) begin
            errors=errors+1;
            $display("FAIL final DMEM[24] expected 00000005 got=%h",dut.u_dmem.mem[24]);
        end
        $display("RESULT: words=%0d issued=%0d WB=%0d/%0d STORE=%0d/%0d unsupported=%0d stalls=%0d errors=%0d",
                 WORDS,issued,written,N_WB,stored,N_ST,unsupported,stalls,errors);
        $display("COVERAGE: raw=%0d stall_checks=%0d store_data_stall=%0d store_base_stall=%0d store_fwd=%0d",
                 raw,hold_checks,store_data_stalls,store_base_stalls,store_data_forward);
        if (errors==0 && written==N_WB && stored==N_ST && unsupported==2)
            $display("ALL TESTS PASSED (V0.3 independent full CPU)");
        else
            $display("TESTS FAILED (V0.3 independent full CPU)");
        $finish;
    end

    initial begin
        #6000;
        if (!finished) begin
            $display("TESTS FAILED: V0.3 WATCHDOG TIMEOUT");
            $finish;
        end
    end
endmodule
