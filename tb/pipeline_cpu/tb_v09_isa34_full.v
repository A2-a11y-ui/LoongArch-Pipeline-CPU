`timescale 1ns / 1ps
// V0.9 34-type ISA full CPU regression, simulation only (Verilog-2001).
// No modification of formal RTL or existing Stage3/Demo memories.
// Use with pipeline_cpu_fpga.v, v09_commit_scoreboard.v and production dependencies.
// Architectural reference is generated independently from decoded machine words.
module tb_v09_isa34_full;
    parameter MEM_FILE = "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/v09_isa34_full.mem";
    localparam [31:0] BASE = 32'h00001000;
    localparam integer N_WORDS=61, N_WB=48, N_ST=3, N_BR=7, N_MDU=7;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, sb_rst=1, check_finish=0;
    wire wb_commit_valid, mem_store_commit_valid, branch_resolve_valid, branch_redirect;
    wire [31:0] wb_commit_pc, wb_commit_data, mem_store_commit_pc, mem_store_commit_addr, mem_store_commit_data;
    wire [4:0] wb_commit_rd;
    wire [31:0] branch_redirect_pc;
    wire load_use_stall,id_unsupported,id_raw_hazard,mem_stall,dmem_req_fire,dmem_resp_fire;
    wire mem_fault_valid,mem_fault_store,mdu_start_fire,mdu_busy,mdu_done,mdu_result_fire,mdu_div_zero;
    wire [31:0] mem_fault_pc,mem_fault_addr;
    wire if_resp_fire,if_resp_hold,fetch_error_fire,adapter_busy;
    wire [31:0] cache_hits,cache_misses,cache_refills,backing_transactions;
    wire program_done,fault_sticky;
    wire [31:0] sb_wb_count,sb_st_count,sb_error_count;
    wire sb_check_done,sb_check_pass;
    reg [5:0] kind_for_word [0:255];
    reg [33:0] coverage_mask=34'b0;
    reg [33:0] branch_coverage_mask=34'b0;
    reg [31:0] exp_branch_pc[0:N_BR-1],exp_branch_target[0:N_BR-1];
    reg exp_branch_taken[0:N_BR-1];
    integer cycles=0,other_errors=0,branch_seen=0,redirect_seen=0;
    integer mdu_start_seen=0,mdu_result_seen=0,mem_req_seen=0,mem_resp_seen=0;
    integer mdu_busy_cycles=0,mem_stall_cycles=0,load_use_seen=0,if_hold_cycles=0;
    integer ix,kk,br_kk;
    reg outstanding=0;
    wire [31:0] rom_data [0:255];
    genvar g;
    generate for (g=0;g<256;g=g+1) begin : rom_probe
        assign rom_data[g] = dut.u_imem.rom[g]; // read-only assertion; no force/deposit
    end endgenerate

    pipeline_cpu_fpga #(
        .PC_BASE(BASE),.PROGRAM_WORDS(N_WORDS),.IMEM_FILE(MEM_FILE),
        .DMEM_READ_LATENCY(8),.DMEM_WRITE_LATENCY(11),.DMEM_WORDS(256)
    ) dut (
        .clk(clk),.rst(rst),
        .wb_commit_valid(wb_commit_valid),.wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd),.wb_commit_data(wb_commit_data),
        .mem_store_commit_valid(mem_store_commit_valid),
        .mem_store_commit_pc(mem_store_commit_pc),
        .mem_store_commit_addr(mem_store_commit_addr),
        .mem_store_commit_data(mem_store_commit_data),
        .branch_resolve_valid(branch_resolve_valid),
        .branch_redirect(branch_redirect),.branch_redirect_pc(branch_redirect_pc),
        .load_use_stall(load_use_stall),.id_unsupported(id_unsupported),.id_raw_hazard(id_raw_hazard),
        .mem_stall(mem_stall),.dmem_req_fire(dmem_req_fire),.dmem_resp_fire(dmem_resp_fire),
        .mem_fault_valid(mem_fault_valid),.mem_fault_pc(mem_fault_pc),
        .mem_fault_addr(mem_fault_addr),.mem_fault_store(mem_fault_store),
        .mdu_start_fire(mdu_start_fire),.mdu_busy(mdu_busy),
        .mdu_done(mdu_done),.mdu_result_fire(mdu_result_fire),.mdu_div_zero(mdu_div_zero),
        .if_resp_fire(if_resp_fire),.if_resp_hold(if_resp_hold),
        .fetch_error_fire(fetch_error_fire),.adapter_busy(adapter_busy),
        .cache_hits(cache_hits),.cache_misses(cache_misses),
        .cache_refills(cache_refills),.backing_transactions(backing_transactions),
        .program_done(program_done),.fault_sticky(fault_sticky)
    );
    v09_commit_scoreboard #(.MAX_WB(128),.MAX_STORE(32)) sb (
        .clk(clk),.sb_rst(sb_rst),
        .wb_commit_valid(wb_commit_valid),.wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd),.wb_commit_data(wb_commit_data),
        .store_commit_valid(mem_store_commit_valid),
        .store_commit_pc(mem_store_commit_pc),.store_commit_addr(mem_store_commit_addr),
        .store_commit_data(mem_store_commit_data),
        .check_finish(check_finish),.wb_count(sb_wb_count),.store_count(sb_st_count),
        .error_count(sb_error_count),.check_done(sb_check_done),.check_pass(sb_check_pass)
    );

    initial begin
        for(ix=0;ix<256;ix=ix+1) kind_for_word[ix]=6'd63;
        kind_for_word[0] = 6'd1;
        kind_for_word[1] = 6'd1;
        kind_for_word[2] = 6'd1;
        kind_for_word[3] = 6'd1;
        kind_for_word[4] = 6'd12;
        kind_for_word[5] = 6'd12;
        kind_for_word[6] = 6'd1;
        kind_for_word[7] = 6'd0;
        kind_for_word[8] = 6'd31;
        kind_for_word[9] = 6'd23;
        kind_for_word[10] = 6'd25;
        kind_for_word[11] = 6'd24;
        kind_for_word[12] = 6'd21;
        kind_for_word[13] = 6'd28;
        kind_for_word[14] = 6'd26;
        kind_for_word[15] = 6'd18;
        kind_for_word[16] = 6'd2;
        kind_for_word[17] = 6'd19;
        kind_for_word[18] = 6'd32;
        kind_for_word[19] = 6'd3;
        kind_for_word[20] = 6'd20;
        kind_for_word[21] = 6'd33;
        kind_for_word[22] = 6'd22;
        kind_for_word[23] = 6'd29;
        kind_for_word[24] = 6'd27;
        kind_for_word[25] = 6'd1;
        kind_for_word[26] = 6'd12;
        kind_for_word[27] = 6'd15;
        kind_for_word[28] = 6'd16;
        kind_for_word[29] = 6'd17;
        kind_for_word[30] = 6'd8;
        kind_for_word[31] = 6'd13;
        kind_for_word[32] = 6'd9;
        kind_for_word[33] = 6'd14;
        kind_for_word[34] = 6'd0;
        kind_for_word[35] = 6'd0;
        kind_for_word[36] = 6'd30;
        kind_for_word[37] = 6'd11;
        kind_for_word[38] = 6'd0;
        kind_for_word[39] = 6'd30;
        kind_for_word[40] = 6'd11;
        kind_for_word[41] = 6'd5;
        kind_for_word[42] = 6'd1;
        kind_for_word[43] = 6'd5;
        kind_for_word[44] = 6'd7;
        kind_for_word[45] = 6'd1;
        kind_for_word[46] = 6'd7;
        kind_for_word[47] = 6'd4;
        kind_for_word[48] = 6'd1;
        kind_for_word[49] = 6'd6;
        kind_for_word[50] = 6'd1;
        kind_for_word[51] = 6'd1;
        kind_for_word[52] = 6'd12;
        kind_for_word[53] = 6'd10;
        kind_for_word[54] = 6'd1;
        kind_for_word[55] = 6'd1;
        kind_for_word[56] = 6'd11;
        kind_for_word[57] = 6'd30;
        kind_for_word[58] = 6'd11;
        kind_for_word[59] = 6'd0;
        kind_for_word[60] = 6'd32;
        exp_branch_pc[0] = 32'h000010a4; exp_branch_taken[0] = 1'b1; exp_branch_target[0] = 32'h000010ac; // BEQ
        exp_branch_pc[1] = 32'h000010ac; exp_branch_taken[1] = 1'b0; exp_branch_target[1] = 32'h00000000; // BEQ
        exp_branch_pc[2] = 32'h000010b0; exp_branch_taken[2] = 1'b1; exp_branch_target[2] = 32'h000010b8; // BNE
        exp_branch_pc[3] = 32'h000010b8; exp_branch_taken[3] = 1'b0; exp_branch_target[3] = 32'h00000000; // BNE
        exp_branch_pc[4] = 32'h000010bc; exp_branch_taken[4] = 1'b1; exp_branch_target[4] = 32'h000010c4; // B
        exp_branch_pc[5] = 32'h000010c4; exp_branch_taken[5] = 1'b1; exp_branch_target[5] = 32'h000010cc; // BL
        exp_branch_pc[6] = 32'h000010d4; exp_branch_taken[6] = 1'b1; exp_branch_target[6] = 32'h000010dc; // JIRL
        #1;
        // Before releasing reset, confirm this simulation loaded the NEW 34-ISA program.
        // Vivado can otherwise silently run the old Stage3 or FPGA demo file.
        if (rom_data[0] !== 32'h02801801) $fatal(1,"ISA34 ROM mismatch index=%0d", 0);
        if (rom_data[1] !== 32'h02800c02) $fatal(1,"ISA34 ROM mismatch index=%0d", 1);
        if (rom_data[2] !== 32'h02bfe403) $fatal(1,"ISA34 ROM mismatch index=%0d", 2);
        if (rom_data[3] !== 32'h02800404) $fatal(1,"ISA34 ROM mismatch index=%0d", 3);
        if (rom_data[4] !== 32'h15000005) $fatal(1,"ISA34 ROM mismatch index=%0d", 4);
        if (rom_data[5] !== 32'h142468a6) $fatal(1,"ISA34 ROM mismatch index=%0d", 5);
        if (rom_data[6] !== 32'h02bffca7) $fatal(1,"ISA34 ROM mismatch index=%0d", 6);
        if (rom_data[7] !== 32'h00100829) $fatal(1,"ISA34 ROM mismatch index=%0d", 7);
        if (rom_data[8] !== 32'h0011082a) $fatal(1,"ISA34 ROM mismatch index=%0d", 8);
        if (rom_data[9] !== 32'h0012086b) $fatal(1,"ISA34 ROM mismatch index=%0d", 9);
        if (rom_data[10] !== 32'h0012886c) $fatal(1,"ISA34 ROM mismatch index=%0d", 10);
        if (rom_data[11] !== 32'h023ff46d) $fatal(1,"ISA34 ROM mismatch index=%0d", 11);
        if (rom_data[12] !== 32'h0017082e) $fatal(1,"ISA34 ROM mismatch index=%0d", 12);
        if (rom_data[13] !== 32'h001790af) $fatal(1,"ISA34 ROM mismatch index=%0d", 13);
        if (rom_data[14] !== 32'h001810b0) $fatal(1,"ISA34 ROM mismatch index=%0d", 14);
        if (rom_data[15] !== 32'h00140831) $fatal(1,"ISA34 ROM mismatch index=%0d", 15);
        if (rom_data[16] !== 32'h00148832) $fatal(1,"ISA34 ROM mismatch index=%0d", 16);
        if (rom_data[17] !== 32'h00150833) $fatal(1,"ISA34 ROM mismatch index=%0d", 17);
        if (rom_data[18] !== 32'h00158834) $fatal(1,"ISA34 ROM mismatch index=%0d", 18);
        if (rom_data[19] !== 32'h0343fe35) $fatal(1,"ISA34 ROM mismatch index=%0d", 19);
        if (rom_data[20] !== 32'h03848036) $fatal(1,"ISA34 ROM mismatch index=%0d", 20);
        if (rom_data[21] !== 32'h03cffc57) $fatal(1,"ISA34 ROM mismatch index=%0d", 21);
        if (rom_data[22] !== 32'h00409098) $fatal(1,"ISA34 ROM mismatch index=%0d", 22);
        if (rom_data[23] !== 32'h0044fcb9) $fatal(1,"ISA34 ROM mismatch index=%0d", 23);
        if (rom_data[24] !== 32'h0048fcba) $fatal(1,"ISA34 ROM mismatch index=%0d", 24);
        if (rom_data[25] !== 32'h02bffc3b) $fatal(1,"ISA34 ROM mismatch index=%0d", 25);
        if (rom_data[26] !== 32'h1420001c) $fatal(1,"ISA34 ROM mismatch index=%0d", 26);
        if (rom_data[27] !== 32'h001c083d) $fatal(1,"ISA34 ROM mismatch index=%0d", 27);
        if (rom_data[28] !== 32'h001c887e) $fatal(1,"ISA34 ROM mismatch index=%0d", 28);
        if (rom_data[29] !== 32'h001d08bf) $fatal(1,"ISA34 ROM mismatch index=%0d", 29);
        if (rom_data[30] !== 32'h00200869) $fatal(1,"ISA34 ROM mismatch index=%0d", 30);
        if (rom_data[31] !== 32'h0020886a) $fatal(1,"ISA34 ROM mismatch index=%0d", 31);
        if (rom_data[32] !== 32'h002108ab) $fatal(1,"ISA34 ROM mismatch index=%0d", 32);
        if (rom_data[33] !== 32'h002188ac) $fatal(1,"ISA34 ROM mismatch index=%0d", 33);
        if (rom_data[34] !== 32'h0010292d) $fatal(1,"ISA34 ROM mismatch index=%0d", 34);
        if (rom_data[35] !== 32'h0010316e) $fatal(1,"ISA34 ROM mismatch index=%0d", 35);
        if (rom_data[36] !== 32'h2980101d) $fatal(1,"ISA34 ROM mismatch index=%0d", 36);
        if (rom_data[37] !== 32'h2880100f) $fatal(1,"ISA34 ROM mismatch index=%0d", 37);
        if (rom_data[38] !== 32'h001005f0) $fatal(1,"ISA34 ROM mismatch index=%0d", 38);
        if (rom_data[39] !== 32'h29802010) $fatal(1,"ISA34 ROM mismatch index=%0d", 39);
        if (rom_data[40] !== 32'h28802011) $fatal(1,"ISA34 ROM mismatch index=%0d", 40);
        if (rom_data[41] !== 32'h58000a30) $fatal(1,"ISA34 ROM mismatch index=%0d", 41);
        if (rom_data[42] !== 32'h02818c12) $fatal(1,"ISA34 ROM mismatch index=%0d", 42);
        if (rom_data[43] !== 32'h58000c22) $fatal(1,"ISA34 ROM mismatch index=%0d", 43);
        if (rom_data[44] !== 32'h5c000822) $fatal(1,"ISA34 ROM mismatch index=%0d", 44);
        if (rom_data[45] !== 32'h02819012) $fatal(1,"ISA34 ROM mismatch index=%0d", 45);
        if (rom_data[46] !== 32'h5c000c21) $fatal(1,"ISA34 ROM mismatch index=%0d", 46);
        if (rom_data[47] !== 32'h50000800) $fatal(1,"ISA34 ROM mismatch index=%0d", 47);
        if (rom_data[48] !== 32'h02819412) $fatal(1,"ISA34 ROM mismatch index=%0d", 48);
        if (rom_data[49] !== 32'h54000800) $fatal(1,"ISA34 ROM mismatch index=%0d", 49);
        if (rom_data[50] !== 32'h02819812) $fatal(1,"ISA34 ROM mismatch index=%0d", 50);
        if (rom_data[51] !== 32'h02800422) $fatal(1,"ISA34 ROM mismatch index=%0d", 51);
        if (rom_data[52] !== 32'h1400003e) $fatal(1,"ISA34 ROM mismatch index=%0d", 52);
        if (rom_data[53] !== 32'h4c00dfdb) $fatal(1,"ISA34 ROM mismatch index=%0d", 53);
        if (rom_data[54] !== 32'h02819c12) $fatal(1,"ISA34 ROM mismatch index=%0d", 54);
        if (rom_data[55] !== 32'h0280077c) $fatal(1,"ISA34 ROM mismatch index=%0d", 55);
        if (rom_data[56] !== 32'h28801013) $fatal(1,"ISA34 ROM mismatch index=%0d", 56);
        if (rom_data[57] !== 32'h29803013) $fatal(1,"ISA34 ROM mismatch index=%0d", 57);
        if (rom_data[58] !== 32'h28803014) $fatal(1,"ISA34 ROM mismatch index=%0d", 58);
        if (rom_data[59] !== 32'h00101295) $fatal(1,"ISA34 ROM mismatch index=%0d", 59);
        if (rom_data[60] !== 32'h001586b6) $fatal(1,"ISA34 ROM mismatch index=%0d", 60);
        sb.clear_expectations();
        sb.expect_wb(32'h00001000, 5'd1, 32'h00000006); // ADDI.W
        sb.expect_wb(32'h00001004, 5'd2, 32'h00000003); // ADDI.W
        sb.expect_wb(32'h00001008, 5'd3, 32'hfffffff9); // ADDI.W
        sb.expect_wb(32'h0000100c, 5'd4, 32'h00000001); // ADDI.W
        sb.expect_wb(32'h00001010, 5'd5, 32'h80000000); // LU12I.W
        sb.expect_wb(32'h00001014, 5'd6, 32'h12345000); // LU12I.W
        sb.expect_wb(32'h00001018, 5'd7, 32'h7fffffff); // ADDI.W
        sb.expect_wb(32'h0000101c, 5'd9, 32'h00000009); // ADD.W
        sb.expect_wb(32'h00001020, 5'd10, 32'h00000003); // SUB.W
        sb.expect_wb(32'h00001024, 5'd11, 32'h00000001); // SLT
        sb.expect_wb(32'h00001028, 5'd12, 32'h00000000); // SLTU
        sb.expect_wb(32'h0000102c, 5'd13, 32'h00000001); // SLTI
        sb.expect_wb(32'h00001030, 5'd14, 32'h00000030); // SLL.W
        sb.expect_wb(32'h00001034, 5'd15, 32'h40000000); // SRL.W
        sb.expect_wb(32'h00001038, 5'd16, 32'hc0000000); // SRA.W
        sb.expect_wb(32'h0000103c, 5'd17, 32'hfffffff8); // NOR
        sb.expect_wb(32'h00001040, 5'd18, 32'h00000002); // AND
        sb.expect_wb(32'h00001044, 5'd19, 32'h00000007); // OR
        sb.expect_wb(32'h00001048, 5'd20, 32'h00000005); // XOR
        sb.expect_wb(32'h0000104c, 5'd21, 32'h000000f8); // ANDI
        sb.expect_wb(32'h00001050, 5'd22, 32'h00000126); // ORI
        sb.expect_wb(32'h00001054, 5'd23, 32'h000003fc); // XORI
        sb.expect_wb(32'h00001058, 5'd24, 32'h00000010); // SLLI.W
        sb.expect_wb(32'h0000105c, 5'd25, 32'h00000001); // SRLI.W
        sb.expect_wb(32'h00001060, 5'd26, 32'hffffffff); // SRAI.W
        sb.expect_wb(32'h00001064, 5'd27, 32'h00000005); // ADDI.W
        sb.expect_wb(32'h00001068, 5'd28, 32'h10000000); // LU12I.W
        sb.expect_wb(32'h0000106c, 5'd29, 32'h00000012); // MUL.W
        sb.expect_wb(32'h00001070, 5'd30, 32'hffffffff); // MULH.W
        sb.expect_wb(32'h00001074, 5'd31, 32'h00000001); // MULH.WU
        sb.expect_wb(32'h00001078, 5'd9, 32'hfffffffe); // DIV.W
        sb.expect_wb(32'h0000107c, 5'd10, 32'hffffffff); // MOD.W
        sb.expect_wb(32'h00001080, 5'd11, 32'h2aaaaaaa); // DIV.WU
        sb.expect_wb(32'h00001084, 5'd12, 32'h00000002); // MOD.WU
        sb.expect_wb(32'h00001088, 5'd13, 32'hfffffffd); // ADD.W
        sb.expect_wb(32'h0000108c, 5'd14, 32'h2aaaaaac); // ADD.W
        sb.expect_wb(32'h00001094, 5'd15, 32'h00000012); // LD.W
        sb.expect_wb(32'h00001098, 5'd16, 32'h00000018); // ADD.W
        sb.expect_wb(32'h000010a0, 5'd17, 32'h00000018); // LD.W
        sb.expect_wb(32'h000010c4, 5'd1, 32'h000010c8); // BL
        sb.expect_wb(32'h000010cc, 5'd2, 32'h000010c9); // ADDI.W
        sb.expect_wb(32'h000010d0, 5'd30, 32'h00001000); // LU12I.W
        sb.expect_wb(32'h000010d4, 5'd27, 32'h000010d8); // JIRL
        sb.expect_wb(32'h000010dc, 5'd28, 32'h000010d9); // ADDI.W
        sb.expect_wb(32'h000010e0, 5'd19, 32'h00000012); // LD.W
        sb.expect_wb(32'h000010e8, 5'd20, 32'h00000012); // LD.W
        sb.expect_wb(32'h000010ec, 5'd21, 32'h00000013); // ADD.W
        sb.expect_wb(32'h000010f0, 5'd22, 32'h000010db); // XOR
        sb.expect_store(32'h00001090, 32'h00000004, 32'h00000012);
        sb.expect_store(32'h0000109c, 32'h00000008, 32'h00000018);
        sb.expect_store(32'h000010e4, 32'h0000000c, 32'h00000012);
        repeat(4) @(negedge clk);
        rst=0; sb_rst=0;
        wait(sb_wb_count==N_WB && sb_st_count==N_ST);
        wait(program_done===1'b1);
        repeat(30) @(negedge clk); // catch late or repeated commits
        check_finish=1;
        @(negedge clk);check_finish=0;
        repeat(20) @(negedge clk);
        if(sb_check_done!==1'b1 || sb_check_pass!==1'b1 || sb_error_count!==0) begin
            other_errors=other_errors+1;
            $display("FAIL final WB/Store golden reference checker");
        end
        if(branch_seen!=N_BR || redirect_seen!=5 ||
           mdu_start_seen!=N_MDU || mdu_result_seen!=N_MDU ||
           mem_req_seen!=7 || mem_resp_seen!=7 || outstanding ||
           !program_done || fault_sticky!==1'b0 ||
           cache_hits===0 || cache_misses===0 || backing_transactions===0 ||
           mdu_busy_cycles==0 || mem_stall_cycles==0 || if_hold_cycles==0) begin
            other_errors=other_errors+1;
            $display("FAIL counters BR=%0d/%0d REDIR=%0d/%0d MDU=%0d/%0d DMEM=%0d/%0d LU=%0d CACHE=%0d/%0d IF_HOLD=%0d DONE=%b FAULT=%b",
                branch_seen,N_BR,redirect_seen,5,mdu_start_seen,mdu_result_seen,
                mem_req_seen,mem_resp_seen,load_use_seen,cache_hits,cache_misses,
                if_hold_cycles,program_done,fault_sticky);
        end
        // An adjacent LD.W/consumer in program order does not guarantee a
        // same-cycle ID-vs-EX load/use hazard under a blocking I-Cache.
        // LOAD_USE is observational here, not proof of hazard coverage.
        // The structural hazard requirement needs a separate directed test.
        if (load_use_seen==0)
            $display("INFO ISA34 LOAD_USE=0: no natural load-use interlock occurred; verify load-use with a separate directed hazard regression");
        if(coverage_mask !== {34{1'b1}}) begin
            other_errors=other_errors+1;
            $display("FAIL not all 34 types executed; coverage bits=%h",coverage_mask);
        end
        if (!coverage_mask[0]) begin other_errors=other_errors+1; $display("FAIL missing instruction type ADD.W"); end
        if (!coverage_mask[1]) begin other_errors=other_errors+1; $display("FAIL missing instruction type ADDI.W"); end
        if (!coverage_mask[2]) begin other_errors=other_errors+1; $display("FAIL missing instruction type AND"); end
        if (!coverage_mask[3]) begin other_errors=other_errors+1; $display("FAIL missing instruction type ANDI"); end
        if (!coverage_mask[4]) begin other_errors=other_errors+1; $display("FAIL missing instruction type B"); end
        if (!coverage_mask[5]) begin other_errors=other_errors+1; $display("FAIL missing instruction type BEQ"); end
        if (!coverage_mask[6]) begin other_errors=other_errors+1; $display("FAIL missing instruction type BL"); end
        if (!coverage_mask[7]) begin other_errors=other_errors+1; $display("FAIL missing instruction type BNE"); end
        if (!coverage_mask[8]) begin other_errors=other_errors+1; $display("FAIL missing instruction type DIV.W"); end
        if (!coverage_mask[9]) begin other_errors=other_errors+1; $display("FAIL missing instruction type DIV.WU"); end
        if (!coverage_mask[10]) begin other_errors=other_errors+1; $display("FAIL missing instruction type JIRL"); end
        if (!coverage_mask[11]) begin other_errors=other_errors+1; $display("FAIL missing instruction type LD.W"); end
        if (!coverage_mask[12]) begin other_errors=other_errors+1; $display("FAIL missing instruction type LU12I.W"); end
        if (!coverage_mask[13]) begin other_errors=other_errors+1; $display("FAIL missing instruction type MOD.W"); end
        if (!coverage_mask[14]) begin other_errors=other_errors+1; $display("FAIL missing instruction type MOD.WU"); end
        if (!coverage_mask[15]) begin other_errors=other_errors+1; $display("FAIL missing instruction type MUL.W"); end
        if (!coverage_mask[16]) begin other_errors=other_errors+1; $display("FAIL missing instruction type MULH.W"); end
        if (!coverage_mask[17]) begin other_errors=other_errors+1; $display("FAIL missing instruction type MULH.WU"); end
        if (!coverage_mask[18]) begin other_errors=other_errors+1; $display("FAIL missing instruction type NOR"); end
        if (!coverage_mask[19]) begin other_errors=other_errors+1; $display("FAIL missing instruction type OR"); end
        if (!coverage_mask[20]) begin other_errors=other_errors+1; $display("FAIL missing instruction type ORI"); end
        if (!coverage_mask[21]) begin other_errors=other_errors+1; $display("FAIL missing instruction type SLL.W"); end
        if (!coverage_mask[22]) begin other_errors=other_errors+1; $display("FAIL missing instruction type SLLI.W"); end
        if (!coverage_mask[23]) begin other_errors=other_errors+1; $display("FAIL missing instruction type SLT"); end
        if (!coverage_mask[24]) begin other_errors=other_errors+1; $display("FAIL missing instruction type SLTI"); end
        if (!coverage_mask[25]) begin other_errors=other_errors+1; $display("FAIL missing instruction type SLTU"); end
        if (!coverage_mask[26]) begin other_errors=other_errors+1; $display("FAIL missing instruction type SRA.W"); end
        if (!coverage_mask[27]) begin other_errors=other_errors+1; $display("FAIL missing instruction type SRAI.W"); end
        if (!coverage_mask[28]) begin other_errors=other_errors+1; $display("FAIL missing instruction type SRL.W"); end
        if (!coverage_mask[29]) begin other_errors=other_errors+1; $display("FAIL missing instruction type SRLI.W"); end
        if (!coverage_mask[30]) begin other_errors=other_errors+1; $display("FAIL missing instruction type ST.W"); end
        if (!coverage_mask[31]) begin other_errors=other_errors+1; $display("FAIL missing instruction type SUB.W"); end
        if (!coverage_mask[32]) begin other_errors=other_errors+1; $display("FAIL missing instruction type XOR"); end
        if (!coverage_mask[33]) begin other_errors=other_errors+1; $display("FAIL missing instruction type XORI"); end
        if(!branch_coverage_mask[6] || !branch_coverage_mask[10]) begin
            other_errors=other_errors+1;
            $display("FAIL BL/JIRL not both observed at EX branch resolution");
        end
        if(dut.u_cpu.u_regfile.regs[18]!==32'd2) begin
            other_errors=other_errors+1;
            $display("FAIL wrong-path poison writes reached r18=%h",dut.u_cpu.u_regfile.regs[18]);
        end
        $display("--------------------------------------------------------");
        $display("V09 ISA34 RESULT TYPES=%0d/34 WB=%0d/%0d STORE=%0d/%0d BR=%0d/%0d REDIRECT=%0d MDU=%0d/%0d DMEM=%0d/%0d LOAD_USE=%0d CACHE_HIT=%0d CACHE_MISS=%0d OTHER_ERRORS=%0d SB_ERRORS=%0d",
           count_ones(coverage_mask),sb_wb_count,N_WB,sb_st_count,N_ST,branch_seen,N_BR,
           redirect_seen,mdu_start_seen,mdu_result_seen,mem_req_seen,mem_resp_seen,
           load_use_seen,cache_hits,cache_misses,other_errors,sb_error_count);
        if(other_errors==0 && sb_check_pass && sb_error_count==0)
            $display("ALL TESTS PASSED (V0.9 FPGA CPU ISA34 instruction regression; load-use directed coverage separate)");
        else $fatal(1,"V09 ISA34 REGRESSION FAILED");
        $finish;
    end

    function integer count_ones;
        input [33:0] bits;
        integer n;
        begin
            count_ones=0;
            for(n=0;n<34;n=n+1) if(bits[n]) count_ones=count_ones+1;
        end
    endfunction

    initial begin
        repeat(20000) @(posedge clk);
        $fatal(1,"TIMEOUT ISA34 WB=%0d/%0d ST=%0d/%0d BR=%0d/%0d",
            sb_wb_count,N_WB,sb_st_count,N_ST,branch_seen,N_BR);
    end

    // Architectural commits, validated concurrently by PR #40 checker.
    // Branches do not all write back: monitor true EX-stage branch resolutions
    // using a read-only, already-existing core debug register `ex_pc`.
    always @(posedge clk) if(!rst) begin
        cycles=cycles+1;
        if(fetch_error_fire || mem_fault_valid || id_unsupported || mdu_div_zero) begin
            other_errors=other_errors+1;
            $display("FAIL invalid instruction/fetch/mem/div zero at t=%0t",$time);
        end
        if(wb_commit_valid) begin
            if(wb_commit_pc<BASE || wb_commit_pc>=BASE+N_WORDS*4 || wb_commit_pc[1:0]!=0) begin
                other_errors=other_errors+1;
                $display("FAIL WB PC out of ROM: %h",wb_commit_pc);
            end else begin
                ix=(wb_commit_pc-BASE)>>2;
                kk=kind_for_word[ix];
                if(kk<34) coverage_mask[kk]=1'b1;
                else begin other_errors=other_errors+1; $display("FAIL WB unknown kind PC=%h",wb_commit_pc); end
            end
        end
        if(mem_store_commit_valid) begin
            if(mem_store_commit_pc<BASE || mem_store_commit_pc>=BASE+N_WORDS*4 || mem_store_commit_pc[1:0]!=0) begin
                other_errors=other_errors+1;
                $display("FAIL STORE PC out of ROM: %h",mem_store_commit_pc);
            end else begin
                ix=(mem_store_commit_pc-BASE)>>2;
                kk=kind_for_word[ix];
                if(kk==30) coverage_mask[kk]=1'b1;
                else begin other_errors=other_errors+1; $display("FAIL unexpected STORE instruction PC=%h kind=%0d",mem_store_commit_pc,kk); end
            end
        end
        if(branch_resolve_valid) begin
            if(branch_seen>=N_BR) begin
                other_errors=other_errors+1;
                $display("FAIL unexpected extra branch at PC=%h",dut.u_cpu.ex_pc);
            end else begin
                if(dut.u_cpu.ex_pc!==exp_branch_pc[branch_seen] ||
                   branch_redirect!==exp_branch_taken[branch_seen] ||
                   (exp_branch_taken[branch_seen] &&
                    branch_redirect_pc!==exp_branch_target[branch_seen])) begin
                    other_errors=other_errors+1;
                    $display("FAIL BR[%0d] PC got=%h expect=%h taken=%b expected=%b target=%h expected=%h",
                        branch_seen,dut.u_cpu.ex_pc,exp_branch_pc[branch_seen],branch_redirect,
                        exp_branch_taken[branch_seen],branch_redirect_pc,exp_branch_target[branch_seen]);
                end
            end
            if(dut.u_cpu.ex_pc>=BASE && dut.u_cpu.ex_pc<BASE+N_WORDS*4 && dut.u_cpu.ex_pc[1:0]==0) begin
                ix=(dut.u_cpu.ex_pc-BASE)>>2;
                br_kk=kind_for_word[ix];
                if(br_kk<34) begin
                    coverage_mask[br_kk]=1'b1;
                    branch_coverage_mask[br_kk]=1'b1;
                end
            end
            branch_seen=branch_seen+1;
        end
        if(branch_redirect) redirect_seen=redirect_seen+1;
        if(load_use_stall) load_use_seen=load_use_seen+1;
        if(mdu_start_fire) mdu_start_seen=mdu_start_seen+1;
        if(mdu_result_fire) begin
            mdu_result_seen=mdu_result_seen+1;
            if(!mdu_done) begin other_errors=other_errors+1; $display("FAIL MDU result accepted without done"); end
        end
        if(mdu_busy) mdu_busy_cycles=mdu_busy_cycles+1;
        if(mem_stall) mem_stall_cycles=mem_stall_cycles+1;
        if(if_resp_hold) if_hold_cycles=if_hold_cycles+1;
        if(mem_stall && dut.if_ready) begin other_errors=other_errors+1; $display("FAIL IF ready while MEM stalled"); end
        if(mdu_busy && dut.if_ready) begin other_errors=other_errors+1; $display("FAIL IF ready while MDU busy"); end
        if(dmem_req_fire) begin
            if(outstanding) begin other_errors=other_errors+1; $display("FAIL overlapping DMEM req"); end
            outstanding=1; mem_req_seen=mem_req_seen+1;
        end
        if(dmem_resp_fire) begin
            if(!outstanding) begin other_errors=other_errors+1; $display("FAIL DMEM response without req"); end
            outstanding=0; mem_resp_seen=mem_resp_seen+1;
        end
    end
endmodule
