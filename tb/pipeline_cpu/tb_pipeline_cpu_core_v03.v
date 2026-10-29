`timescale 1ns / 1ps
// V0.3 self-check: official CPU top with LD.W/ST.W and one-cycle load-use.
// 62 independent ISA-model instruction words; 43 register commits; 16 stores.
// TB drives external IF using READY/VALID; PC and ROM index advance ONLY on
// if_valid && if_ready at a rising edge. Never drop the instruction on stall.
// Independent hard-coded PC/rd/data scoreboard and store-event scoreboard.
module tb_pipeline_cpu_core_v03;
    parameter MEM_FILE = "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/load_store_v03.mem";
    localparam integer WORDS = 62;
    localparam integer NCOMMITS = 43;
    localparam integer NSTORES = 16;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg if_valid = 1'b0;
    reg [31:0] if_pc = 32'd0;
    reg [31:0] if_inst = 32'd0;
    wire if_ready, load_use_stall, id_unsupported, id_raw_hazard;
    wire wb_commit_valid;
    wire [31:0] wb_commit_pc, wb_commit_data;
    wire [4:0] wb_commit_rd;
    wire mem_store_commit_valid;
    wire [31:0] mem_store_commit_pc, mem_store_commit_addr, mem_store_commit_data;

    pipeline_cpu_core_v03 dut (
        .clk(clk), .rst(rst),
        .if_valid(if_valid), .if_pc(if_pc), .if_inst(if_inst), .if_ready(if_ready),
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
    reg [31:0] exp_pc [0:NCOMMITS-1];
    reg [4:0] exp_rd [0:NCOMMITS-1];
    reg [31:0] exp_data [0:NCOMMITS-1];
    reg [31:0] exp_store_pc [0:NSTORES-1];
    reg [31:0] exp_store_addr [0:NSTORES-1];
    reg [31:0] exp_store_data [0:NSTORES-1];

    integer sent_count=0;
    integer commit_count=0;
    integer store_count=0;
    integer stall_count=0;
    integer load_store_data_stalls=0;
    integer load_store_base_stalls=0;
    integer load_to_ex_forward_count=0;
    integer store_fwd_count=0;
    integer unsupported_count=0;
    integer raw_count=0;
    integer errors=0;
    integer fd;
    reg [2047:0] mem_path;
    reg [31:0] held_id_pc, held_id_inst;
    reg held_id_valid;

    // Next IF word is offered on the falling edge; send_count advances ONLY
    // on an accepted positive edge. This prevents testbench-induced drops.
    always @(negedge clk) begin
        if (rst || sent_count >= WORDS) begin
            if_valid = 1'b0;
            if_pc = 32'd0;
            if_inst = 32'd0;
        end else begin
            if_valid = 1'b1;
            if_pc = 32'h00001000 + (sent_count * 4);
            if_inst = rom[sent_count];
        end
    end

    function is_load_pc;
        input [31:0] pc;
        integer n;
        begin
            is_load_pc = 1'b0;
            if (pc >= 32'h00001000 && pc < (32'h00001000 + WORDS*4)) begin
                n = (pc - 32'h00001000) >> 2;
                if ((rom[n] & 32'hffc00000) == 32'h28800000)
                    is_load_pc = 1'b1;
            end
        end
    endfunction

    // Observe the old WB/MEM transaction at the SAME edge as RegFile/DMEM.
    always @(posedge clk) begin
        if (!rst) begin
            if (if_ready !== !load_use_stall) begin
                errors=errors+1;
                $display("FAIL IF ready must be inverse of load-use stall");
            end
            if (if_valid && if_ready) begin
                if (sent_count >= WORDS ||
                    if_pc !== (32'h00001000 + sent_count*4) ||
                    if_inst !== rom[sent_count]) begin
                    errors=errors+1;
                    $display("FAIL IF handshake index=%0d PC=%h INST=%h",sent_count,if_pc,if_inst);
                end
                sent_count = sent_count + 1;
            end
            if (id_unsupported) unsupported_count = unsupported_count + 1;
            if (id_raw_hazard) raw_count = raw_count + 1;
            if (dut.ex_valid && (dut.wait_a || dut.wait_b)) begin
                errors=errors+1;
                $display("FAIL forwarding wait despite load-use interlock, EX PC=%h",dut.ex_pc);
            end
            if (dut.ex_valid && dut.ex_mem_write && dut.forward_b != 2'b00)
                store_fwd_count = store_fwd_count + 1;
            if (dut.ex_valid &&
                ((dut.forward_a == 2'b01) || (dut.forward_b == 2'b01)) &&
                is_load_pc(dut.wb_pc))
                load_to_ex_forward_count = load_to_ex_forward_count + 1;

            if (wb_commit_valid) begin
                if (commit_count >= NCOMMITS) begin
                    errors=errors+1;
                    $display("FAIL unexpected WB PC=%h rd=%0d data=%h",wb_commit_pc,wb_commit_rd,wb_commit_data);
                end else if (wb_commit_pc !== exp_pc[commit_count] ||
                             wb_commit_rd !== exp_rd[commit_count] ||
                             wb_commit_data !== exp_data[commit_count]) begin
                    errors=errors+1;
                    $display("FAIL WB[%0d] got PC=%h rd=%0d data=%h expected PC=%h rd=%0d data=%h",
                             commit_count, wb_commit_pc, wb_commit_rd, wb_commit_data,
                             exp_pc[commit_count], exp_rd[commit_count], exp_data[commit_count]);
                end
                commit_count = commit_count + 1;
            end
            if (mem_store_commit_valid) begin
                if (store_count >= NSTORES) begin
                    errors=errors+1;
                    $display("FAIL extra ST.W PC=%h addr=%h data=%h",
                             mem_store_commit_pc, mem_store_commit_addr, mem_store_commit_data);
                end else if (mem_store_commit_pc !== exp_store_pc[store_count] ||
                             mem_store_commit_addr !== exp_store_addr[store_count] ||
                             mem_store_commit_data !== exp_store_data[store_count]) begin
                    errors=errors+1;
                    $display("FAIL STORE[%0d] got PC=%h addr=%h data=%h expected PC=%h addr=%h data=%h",
                             store_count, mem_store_commit_pc, mem_store_commit_addr, mem_store_commit_data,
                             exp_store_pc[store_count], exp_store_addr[store_count], exp_store_data[store_count]);
                end
                store_count = store_count + 1;
            end
            if (load_use_stall) begin
                stall_count = stall_count + 1;
                if (if_ready !== 1'b0 || !dut.ex_valid || !dut.ex_mem_read ||
                    !dut.id_valid || !dut.id_accept) begin
                    errors=errors+1;
                    $display("FAIL bad load-use precondition at %0t", $time);
                end
                if (dut.d_mem_write && dut.d_rs2_addr == dut.ex_rd_addr)
                    load_store_data_stalls = load_store_data_stalls + 1;
                if (dut.d_mem_write && dut.d_rs1_addr == dut.ex_rd_addr)
                    load_store_base_stalls = load_store_base_stalls + 1;
                held_id_pc=dut.id_pc; held_id_inst=dut.id_inst;
                held_id_valid=dut.id_valid;
                // Check state AFTER nonblocking assignments have committed.
                #1;
                if (dut.id_pc !== held_id_pc ||
                    dut.id_inst !== held_id_inst ||
                    dut.id_valid !== held_id_valid ||
                    dut.ex_valid !== 1'b0 ||
                    dut.mem_valid !== 1'b1 || !dut.mem_mem_read) begin
                    errors=errors+1;
                    $display("FAIL load-use control: IF/ID did not hold, EX bubble absent, or old load did not advance");
                end
            end
        end
    end

    initial begin
        mem_path = MEM_FILE;
        if ($value$plusargs("MEM_FILE=%s", mem_path)) begin
            $display("INFO overriding MEM_FILE from plusargs");
        end
        fd = $fopen(mem_path, "r");
        if (fd == 0) begin
            $display("FAIL cannot open ROM file: %0s", mem_path);
            $finish;
        end
        $fclose(fd);
        $readmemh(mem_path, rom);
        $display("INFO loading %0d instructions from %0s", WORDS, mem_path);

        // Independently calculated architectural expectations:
        exp_pc[0] = 32'h00001000; exp_rd[0] = 5'd1; exp_data[0] = 32'h00000005;
        exp_pc[1] = 32'h00001004; exp_rd[1] = 5'd2; exp_data[1] = 32'h00000008;
        exp_pc[2] = 32'h00001008; exp_rd[2] = 5'd3; exp_data[2] = 32'h0000000d;
        exp_pc[3] = 32'h00001010; exp_rd[3] = 5'd4; exp_data[3] = 32'h0000000d;
        exp_pc[4] = 32'h00001014; exp_rd[4] = 5'd5; exp_data[4] = 32'h00000014;
        exp_pc[5] = 32'h00001018; exp_rd[5] = 5'd6; exp_data[5] = 32'h00000021;
        exp_pc[6] = 32'h00001020; exp_rd[6] = 5'd7; exp_data[6] = 32'h00000021;
        exp_pc[7] = 32'h00001028; exp_rd[7] = 5'd8; exp_data[7] = 32'h00000021;
        exp_pc[8] = 32'h0000102c; exp_rd[8] = 5'd9; exp_data[8] = 32'h00000026;
        exp_pc[9] = 32'h00001030; exp_rd[9] = 5'd10; exp_data[9] = 32'h00000000;
        exp_pc[10] = 32'h00001034; exp_rd[10] = 5'd11; exp_data[10] = 32'h0000000d;
        exp_pc[11] = 32'h00001038; exp_rd[11] = 5'd12; exp_data[11] = 32'h0000001a;
        exp_pc[12] = 32'h00001040; exp_rd[12] = 5'd13; exp_data[12] = 32'h0000001a;
        exp_pc[13] = 32'h00001044; exp_rd[13] = 5'd14; exp_data[13] = 32'h00000014;
        exp_pc[14] = 32'h0000104c; exp_rd[14] = 5'd15; exp_data[14] = 32'h00000014;
        exp_pc[15] = 32'h00001050; exp_rd[15] = 5'd16; exp_data[15] = 32'h00000021;
        exp_pc[16] = 32'h00001054; exp_rd[16] = 5'd17; exp_data[16] = 32'h00000035;
        exp_pc[17] = 32'h00001058; exp_rd[17] = 5'd18; exp_data[17] = 32'h00000001;
        exp_pc[18] = 32'h0000105c; exp_rd[18] = 5'd18; exp_data[18] = 32'h00000003;
        exp_pc[19] = 32'h00001064; exp_rd[19] = 5'd19; exp_data[19] = 32'h00000003;
        exp_pc[20] = 32'h00001068; exp_rd[20] = 5'd20; exp_data[20] = 32'hfffffffe;
        exp_pc[21] = 32'h00001070; exp_rd[21] = 5'd21; exp_data[21] = 32'h00000009;
        exp_pc[22] = 32'h00001078; exp_rd[22] = 5'd22; exp_data[22] = 32'h00000000;
        exp_pc[23] = 32'h0000107c; exp_rd[23] = 5'd23; exp_data[23] = 32'h00000009;
        exp_pc[24] = 32'h00001080; exp_rd[24] = 5'd24; exp_data[24] = 32'h00000037;
        exp_pc[25] = 32'h00001088; exp_rd[25] = 5'd24; exp_data[25] = 32'h00000042;
        exp_pc[26] = 32'h00001090; exp_rd[26] = 5'd25; exp_data[26] = 32'h00000037;
        exp_pc[27] = 32'h00001094; exp_rd[27] = 5'd26; exp_data[27] = 32'h00000042;
        exp_pc[28] = 32'h00001098; exp_rd[28] = 5'd27; exp_data[28] = 32'h00000079;
        exp_pc[29] = 32'h000010a0; exp_rd[29] = 5'd28; exp_data[29] = 32'hfffffffb;
        exp_pc[30] = 32'h000010a8; exp_rd[30] = 5'd29; exp_data[30] = 32'hfffffffb;
        exp_pc[31] = 32'h000010ac; exp_rd[31] = 5'd30; exp_data[31] = 32'h00000001;
        exp_pc[32] = 32'h000010b4; exp_rd[32] = 5'd31; exp_data[32] = 32'h00000001;
        exp_pc[33] = 32'h000010b8; exp_rd[33] = 5'd2; exp_data[33] = 32'h00000006;
        exp_pc[34] = 32'h000010c0; exp_rd[34] = 5'd3; exp_data[34] = 32'h00000006;
        exp_pc[35] = 32'h000010c4; exp_rd[35] = 5'd4; exp_data[35] = 32'h00000040;
        exp_pc[36] = 32'h000010cc; exp_rd[36] = 5'd5; exp_data[36] = 32'h00000006;
        exp_pc[37] = 32'h000010d0; exp_rd[37] = 5'd6; exp_data[37] = 32'h00000011;
        exp_pc[38] = 32'h000010d8; exp_rd[38] = 5'd7; exp_data[38] = 32'h00000011;
        exp_pc[39] = 32'h000010dc; exp_rd[39] = 5'd9; exp_data[39] = 32'h00000040;
        exp_pc[40] = 32'h000010e4; exp_rd[40] = 5'd10; exp_data[40] = 32'h00000040;
        exp_pc[41] = 32'h000010ec; exp_rd[41] = 5'd11; exp_data[41] = 32'h00000005;
        exp_pc[42] = 32'h000010f0; exp_rd[42] = 5'd12; exp_data[42] = 32'h00000016;
        exp_store_pc[0] = 32'h0000100c; exp_store_addr[0] = 32'h00000000; exp_store_data[0] = 32'h0000000d;
        exp_store_pc[1] = 32'h0000101c; exp_store_addr[1] = 32'h00000004; exp_store_data[1] = 32'h00000021;
        exp_store_pc[2] = 32'h00001024; exp_store_addr[2] = 32'h00000008; exp_store_data[2] = 32'h00000021;
        exp_store_pc[3] = 32'h0000103c; exp_store_addr[3] = 32'h0000000c; exp_store_data[3] = 32'h0000001a;
        exp_store_pc[4] = 32'h00001048; exp_store_addr[4] = 32'h00000010; exp_store_data[4] = 32'h00000014;
        exp_store_pc[5] = 32'h00001060; exp_store_addr[5] = 32'h00000014; exp_store_data[5] = 32'h00000003;
        exp_store_pc[6] = 32'h00001074; exp_store_addr[6] = 32'h00000018; exp_store_data[6] = 32'h00000000;
        exp_store_pc[7] = 32'h00001084; exp_store_addr[7] = 32'h0000001c; exp_store_data[7] = 32'h00000037;
        exp_store_pc[8] = 32'h0000108c; exp_store_addr[8] = 32'h00000020; exp_store_data[8] = 32'h00000042;
        exp_store_pc[9] = 32'h000010a4; exp_store_addr[9] = 32'h00000024; exp_store_data[9] = 32'hfffffffb;
        exp_store_pc[10] = 32'h000010b0; exp_store_addr[10] = 32'h00000028; exp_store_data[10] = 32'h00000001;
        exp_store_pc[11] = 32'h000010bc; exp_store_addr[11] = 32'h0000002c; exp_store_data[11] = 32'h00000006;
        exp_store_pc[12] = 32'h000010c8; exp_store_addr[12] = 32'h00000040; exp_store_data[12] = 32'h00000006;
        exp_store_pc[13] = 32'h000010d4; exp_store_addr[13] = 32'h0000003c; exp_store_data[13] = 32'h00000011;
        exp_store_pc[14] = 32'h000010e0; exp_store_addr[14] = 32'h00000034; exp_store_data[14] = 32'h00000040;
        exp_store_pc[15] = 32'h000010e8; exp_store_addr[15] = 32'h00000040; exp_store_data[15] = 32'h00000005;

        repeat (2) @(negedge clk);
        rst = 1'b0;
        wait (sent_count == WORDS);
        repeat (14) @(negedge clk);
        #1;
        if (commit_count != NCOMMITS || store_count != NSTORES ||
            unsupported_count != 2) begin
            errors=errors+1;
            $display("FAIL totals commits=%0d/%0d stores=%0d/%0d unsupported=%0d/2",
                     commit_count,NCOMMITS,store_count,NSTORES,unsupported_count);
        end
        if (stall_count < 6 || load_store_data_stalls == 0 ||
            load_store_base_stalls == 0 || load_to_ex_forward_count == 0 ||
            store_fwd_count == 0 || raw_count == 0) begin
            errors=errors+1;
            $display("FAIL coverage stalls=%0d ST_DATA_STALL=%0d ST_BASE_STALL=%0d LD_FWD=%0d STORE_FWD=%0d RAW=%0d",
                     stall_count,load_store_data_stalls,load_store_base_stalls,
                     load_to_ex_forward_count,store_fwd_count,raw_count);
        end
        if (dut.u_regfile.regs[0] !== 32'h00000000) begin
            errors=errors+1; $display("FAIL final reg r0: got=%h expected=00000000",dut.u_regfile.regs[0]);
        end
        if (dut.u_regfile.regs[1] !== 32'h00000005) begin
            errors=errors+1; $display("FAIL final reg r1: got=%h expected=00000005",dut.u_regfile.regs[1]);
        end
        if (dut.u_regfile.regs[2] !== 32'h00000006) begin
            errors=errors+1; $display("FAIL final reg r2: got=%h expected=00000006",dut.u_regfile.regs[2]);
        end
        if (dut.u_regfile.regs[3] !== 32'h00000006) begin
            errors=errors+1; $display("FAIL final reg r3: got=%h expected=00000006",dut.u_regfile.regs[3]);
        end
        if (dut.u_regfile.regs[4] !== 32'h00000040) begin
            errors=errors+1; $display("FAIL final reg r4: got=%h expected=00000040",dut.u_regfile.regs[4]);
        end
        if (dut.u_regfile.regs[5] !== 32'h00000006) begin
            errors=errors+1; $display("FAIL final reg r5: got=%h expected=00000006",dut.u_regfile.regs[5]);
        end
        if (dut.u_regfile.regs[6] !== 32'h00000011) begin
            errors=errors+1; $display("FAIL final reg r6: got=%h expected=00000011",dut.u_regfile.regs[6]);
        end
        if (dut.u_regfile.regs[7] !== 32'h00000011) begin
            errors=errors+1; $display("FAIL final reg r7: got=%h expected=00000011",dut.u_regfile.regs[7]);
        end
        if (dut.u_regfile.regs[10] !== 32'h00000040) begin
            errors=errors+1; $display("FAIL final reg r10: got=%h expected=00000040",dut.u_regfile.regs[10]);
        end
        if (dut.u_regfile.regs[11] !== 32'h00000005) begin
            errors=errors+1; $display("FAIL final reg r11: got=%h expected=00000005",dut.u_regfile.regs[11]);
        end
        if (dut.u_regfile.regs[12] !== 32'h00000016) begin
            errors=errors+1; $display("FAIL final reg r12: got=%h expected=00000016",dut.u_regfile.regs[12]);
        end
        if (dut.u_regfile.regs[17] !== 32'h00000035) begin
            errors=errors+1; $display("FAIL final reg r17: got=%h expected=00000035",dut.u_regfile.regs[17]);
        end
        if (dut.u_regfile.regs[20] !== 32'hfffffffe) begin
            errors=errors+1; $display("FAIL final reg r20: got=%h expected=fffffffe",dut.u_regfile.regs[20]);
        end
        if (dut.u_regfile.regs[21] !== 32'h00000009) begin
            errors=errors+1; $display("FAIL final reg r21: got=%h expected=00000009",dut.u_regfile.regs[21]);
        end
        if (dut.u_regfile.regs[24] !== 32'h00000042) begin
            errors=errors+1; $display("FAIL final reg r24: got=%h expected=00000042",dut.u_regfile.regs[24]);
        end
        if (dut.u_regfile.regs[27] !== 32'h00000079) begin
            errors=errors+1; $display("FAIL final reg r27: got=%h expected=00000079",dut.u_regfile.regs[27]);
        end
        if (dut.u_regfile.regs[28] !== 32'hfffffffb) begin
            errors=errors+1; $display("FAIL final reg r28: got=%h expected=fffffffb",dut.u_regfile.regs[28]);
        end
        if (dut.u_regfile.regs[29] !== 32'hfffffffb) begin
            errors=errors+1; $display("FAIL final reg r29: got=%h expected=fffffffb",dut.u_regfile.regs[29]);
        end
        if (dut.u_regfile.regs[30] !== 32'h00000001) begin
            errors=errors+1; $display("FAIL final reg r30: got=%h expected=00000001",dut.u_regfile.regs[30]);
        end
        if (dut.u_regfile.regs[31] !== 32'h00000001) begin
            errors=errors+1; $display("FAIL final reg r31: got=%h expected=00000001",dut.u_regfile.regs[31]);
        end
        if (dut.u_dmem.mem[0] !== 32'h0000000d) begin
            errors=errors+1; $display("FAIL final MEM[%0d]: got=%h expected=0000000d", 0, dut.u_dmem.mem[0]);
        end
        if (dut.u_dmem.mem[1] !== 32'h00000021) begin
            errors=errors+1; $display("FAIL final MEM[%0d]: got=%h expected=00000021", 1, dut.u_dmem.mem[1]);
        end
        if (dut.u_dmem.mem[2] !== 32'h00000021) begin
            errors=errors+1; $display("FAIL final MEM[%0d]: got=%h expected=00000021", 2, dut.u_dmem.mem[2]);
        end
        if (dut.u_dmem.mem[3] !== 32'h0000001a) begin
            errors=errors+1; $display("FAIL final MEM[%0d]: got=%h expected=0000001a", 3, dut.u_dmem.mem[3]);
        end
        if (dut.u_dmem.mem[4] !== 32'h00000014) begin
            errors=errors+1; $display("FAIL final MEM[%0d]: got=%h expected=00000014", 4, dut.u_dmem.mem[4]);
        end
        if (dut.u_dmem.mem[5] !== 32'h00000003) begin
            errors=errors+1; $display("FAIL final MEM[%0d]: got=%h expected=00000003", 5, dut.u_dmem.mem[5]);
        end
        if (dut.u_dmem.mem[6] !== 32'h00000000) begin
            errors=errors+1; $display("FAIL final MEM[%0d]: got=%h expected=00000000", 6, dut.u_dmem.mem[6]);
        end
        if (dut.u_dmem.mem[7] !== 32'h00000037) begin
            errors=errors+1; $display("FAIL final MEM[%0d]: got=%h expected=00000037", 7, dut.u_dmem.mem[7]);
        end
        if (dut.u_dmem.mem[8] !== 32'h00000042) begin
            errors=errors+1; $display("FAIL final MEM[%0d]: got=%h expected=00000042", 8, dut.u_dmem.mem[8]);
        end
        if (dut.u_dmem.mem[9] !== 32'hfffffffb) begin
            errors=errors+1; $display("FAIL final MEM[%0d]: got=%h expected=fffffffb", 9, dut.u_dmem.mem[9]);
        end
        if (dut.u_dmem.mem[10] !== 32'h00000001) begin
            errors=errors+1; $display("FAIL final MEM[%0d]: got=%h expected=00000001", 10, dut.u_dmem.mem[10]);
        end
        if (dut.u_dmem.mem[11] !== 32'h00000006) begin
            errors=errors+1; $display("FAIL final MEM[%0d]: got=%h expected=00000006", 11, dut.u_dmem.mem[11]);
        end
        if (dut.u_dmem.mem[13] !== 32'h00000040) begin
            errors=errors+1; $display("FAIL final MEM[%0d]: got=%h expected=00000040", 13, dut.u_dmem.mem[13]);
        end
        if (dut.u_dmem.mem[15] !== 32'h00000011) begin
            errors=errors+1; $display("FAIL final MEM[%0d]: got=%h expected=00000011", 15, dut.u_dmem.mem[15]);
        end
        if (dut.u_dmem.mem[16] !== 32'h00000005) begin
            errors=errors+1; $display("FAIL final MEM[%0d]: got=%h expected=00000005", 16, dut.u_dmem.mem[16]);
        end
        $display("RESULT V0.3: words=%0d commits=%0d/%0d stores=%0d/%0d unsupported=%0d stalls=%0d errors=%0d",
                 WORDS, commit_count, NCOMMITS, store_count, NSTORES,
                 unsupported_count, stall_count, errors);
        $display("COVERAGE: RAW=%0d STORE_DATA_STALL=%0d STORE_BASE_STALL=%0d LD_TO_EX_FWD=%0d STORE_FWD=%0d",
                 raw_count,load_store_data_stalls,load_store_base_stalls,
                 load_to_ex_forward_count,store_fwd_count);
        if (errors == 0)
            $display("ALL TESTS PASSED (pipeline CPU V0.3 load/store and load-use)");
        else
            $display("TESTS FAILED (pipeline CPU V0.3)");
        $finish;
    end

    initial begin
        #4000;
        $display("FAIL WATCHDOG V0.3 at %0t",$time);
        $finish;
    end
endmodule
