`timescale 1ns / 1ps
// Team B's 13-instruction ISA acceptance suite, executed on formal cpu_top.
// Test uses REAL LoongArch machine words: PC -> IMEM -> DECODER -> RF/ALU/DMEM.
// Independent expected register/memory values; continuous single-cycle commits.
// Assumptions: official teammate A modules and validated decoder_v2 + imm_gen V2.
module tb_13_instructions;
    reg clk, rst, step_en;
    wire [31:0] pc, inst;
    wire fetch_addr_valid, instr_valid;
    wire [2:0] dbg_branch_type;
    wire [31:0] dbg_branch_imm, dbg_target_pc, dbg_next_pc;
    wire dbg_redirect, dbg_reg_we, dbg_mem_we;
    wire [4:0] dbg_waddr;
    wire [31:0] dbg_wb_data, dbg_rs1_data, dbg_rs2_data;
    integer checks, errors, committed;
    integer coverage[0:12];
    integer i;

    cpu_top dut (
        .clk(clk), .rst(rst), .step_en(step_en), .pc(pc), .inst(inst),
        .fetch_addr_valid(fetch_addr_valid), .instr_valid(instr_valid),
        .dbg_branch_type(dbg_branch_type), .dbg_branch_imm(dbg_branch_imm),
        .dbg_redirect(dbg_redirect), .dbg_target_pc(dbg_target_pc),
        .dbg_next_pc(dbg_next_pc), .dbg_reg_we(dbg_reg_we),
        .dbg_mem_we(dbg_mem_we), .dbg_waddr(dbg_waddr),
        .dbg_wb_data(dbg_wb_data),
        .dbg_rs1_data(dbg_rs1_data), .dbg_rs2_data(dbg_rs2_data)
    );
    always #5 clk = ~clk;

    task eq32;
        input [8*36-1:0] label;
        input [31:0] got, exp;
        begin
            checks=checks+1;
            if (got !== exp) begin
                errors=errors+1;
                $display("FAIL %0s got=%08h expected=%08h",label,got,exp);
            end
        end
    endtask

    // Execute one genuine instruction word and check PC, decode, side effects.
    // kind 0=reg write, 1=memory write, 2=invalid, 3=r0 write suppressed.
    // dst_data is independently specified expected register/memory content.
    task execute;
        input [8*36-1:0] label;
        input integer instr_num;
        input integer family;
        input [31:0] opcode;
        input [1:0] kind;
        input [4:0] dest;
        input [31:0] dst_data;
        input [7:0] mem_word_index;
        begin
            @(negedge clk);
            step_en=1'b1;
            #1;
            eq32("PC before",pc,instr_num*4);
            eq32("real instruction",inst,opcode);
            eq32("valid fetch",{31'd0,fetch_addr_valid},32'd1);
            eq32("instruction valid",{31'd0,instr_valid},(kind==2)?32'd0:32'd1);
            eq32("not branch",{31'd0,dbg_redirect},32'd0);
            eq32("branch type none",{29'd0,dbg_branch_type},32'd0);
            eq32("next PC",dbg_next_pc,(instr_num+1)*4);
            eq32("RF write",{31'd0,dbg_reg_we},(kind==0)?32'd1:32'd0);
            eq32("DM write",{31'd0,dbg_mem_we},(kind==1)?32'd1:32'd0);
            if (kind==0) begin
                eq32("write register number",{27'd0,dbg_waddr},{27'd0,dest});
                eq32("writeback value",dbg_wb_data,dst_data);
            end
            @(posedge clk); #1;
            eq32("PC after",pc,(instr_num+1)*4);
            if (kind==0 || kind==3)
                eq32("register after",dut.u_regfile.regs[dest],dst_data);
            if (kind==1)
                eq32("memory after",dut.u_dmem.mem[mem_word_index],dst_data);
            committed=committed+1;
            if (family>=0 && family<13)
                coverage[family]=coverage[family]+1;
            $display("PASS [%0d] %0s PC=%08h",instr_num,label,pc);
        end
    endtask

    // A full clock with step_en=0: neither PC nor architectural state advances.
    task hold_one;
        input [8*36-1:0] label;
        input [31:0] exp_pc;
        begin
            @(negedge clk);
            step_en=1'b0;
            #1;
            eq32("stall RF WE",{31'd0,dbg_reg_we},32'd0);
            eq32("stall DM WE",{31'd0,dbg_mem_we},32'd0);
            @(posedge clk); #1;
            eq32("stall PC hold",pc,exp_pc);
            $display("PASS stall %0s",label);
        end
    endtask

    initial begin
        clk=0; rst=1; step_en=0;
        checks=0; errors=0; committed=0;
        for (i=0;i<13;i=i+1) coverage[i]=0;
        // Testbench-only ROM programming, after imem initialization at t=0.
        #1;
        dut.u_imem.mem[ 0] = 32'h15000001; // LU12I_80000
        dut.u_imem.mem[ 1] = 32'h15FFFFE2; // LU12I_FFFFF
        dut.u_imem.mem[ 2] = 32'h03BFFC42; // ORI_make_FFFFFFFF
        dut.u_imem.mem[ 3] = 32'h03955403; // ORI_555
        dut.u_imem.mem[ 4] = 32'h03FFFC64; // XORI_fff
        dut.u_imem.mem[ 5] = 32'h03600045; // ANDI_800
        dut.u_imem.mem[ 6] = 32'h037FFC46; // ANDI_fff
        dut.u_imem.mem[ 7] = 32'h00148447; // AND_hi
        dut.u_imem.mem[ 8] = 32'h00150C28; // OR_hi
        dut.u_imem.mem[ 9] = 32'h00158449; // XOR_hi
        dut.u_imem.mem[10] = 32'h00140C2A; // NOR_hi
        dut.u_imem.mem[11] = 32'h0040806B; // SLLI_0
        dut.u_imem.mem[12] = 32'h0040FC6C; // SLLI_31
        dut.u_imem.mem[13] = 32'h0044FC2D; // SRLI_31
        dut.u_imem.mem[14] = 32'h0048FC2E; // SRAI_31
        dut.u_imem.mem[15] = 32'h0048842F; // SRAI_1
        dut.u_imem.mem[16] = 32'h00448430; // SRLI_1
        dut.u_imem.mem[17] = 32'h03800011; // ORI_zero
        dut.u_imem.mem[18] = 32'h03C00052; // XORI_zero
        dut.u_imem.mem[19] = 32'h03400053; // ANDI_zero
        dut.u_imem.mem[20] = 32'h00158534; // XOR_dep
        dut.u_imem.mem[21] = 32'h00140015; // NOR_zero
        dut.u_imem.mem[22] = 32'h00150816; // OR_zero
        dut.u_imem.mem[23] = 32'h00148817; // AND_zero
        dut.u_imem.mem[24] = 32'h142468B8; // LU12I_12345
        dut.u_imem.mem[25] = 32'h0399E318; // ORI_dep_678
        dut.u_imem.mem[26] = 32'h03820019; // ORI_base128
        dut.u_imem.mem[27] = 32'h29800338; // STW_0
        dut.u_imem.mem[28] = 32'h2880033A; // LDW_0
        dut.u_imem.mem[29] = 32'h2980132E; // STW_plus4
        dut.u_imem.mem[30] = 32'h2880133B; // LDW_plus4
        dut.u_imem.mem[31] = 32'h29BFF329; // STW_minus4
        dut.u_imem.mem[32] = 32'h28BFF33C; // LDW_minus4
        dut.u_imem.mem[33] = 32'h29803323; // STW_plus12
        dut.u_imem.mem[34] = 32'h2880333D; // LDW_plus12
        dut.u_imem.mem[35] = 32'h004093BE; // SLLI_dep4
        dut.u_imem.mem[36] = 32'h004493DF; // SRLI_dep4
        dut.u_imem.mem[37] = 32'h03FFFFFE; // XORI_dep_fff
        dut.u_imem.mem[38] = 32'h00149BDF; // AND_dep
        dut.u_imem.mem[39] = 32'h1400001E; // LU12I_zero
        dut.u_imem.mem[40] = 32'h03BFFC1E; // ORI_max
        dut.u_imem.mem[41] = 32'h037FFFDE; // ANDI_max
        dut.u_imem.mem[42] = 32'h0048805E; // SRAI_0
        dut.u_imem.mem[43] = 32'h0044805E; // SRLI_0
        dut.u_imem.mem[44] = 32'h0040845E; // SLLI_1
        dut.u_imem.mem[45] = 32'h28BFF33E; // LDW_dep_neg4
        dut.u_imem.mem[46] = 32'h2980433E; // STW_dep_plus16
        dut.u_imem.mem[47] = 32'h2880433E; // LDW_dep_plus16
        dut.u_imem.mem[48] = 32'h03FFFFDE; // XORI_fff_result
        dut.u_imem.mem[49] = 32'h037FFFDE; // ANDI_zero_result
        dut.u_imem.mem[50] = 32'h03BFFFDE; // ORI_after_zero
        dut.u_imem.mem[51] = 32'h0015FBDE; // XOR_same_regs
        dut.u_imem.mem[52] = 32'h03BFFC00; // ORI_r0_protection
        dut.u_imem.mem[53] = 32'h1400003E; // LU12I_one
        dut.u_imem.mem[54] = 32'h0048FC5E; // SRAI_31_repeat
        dut.u_imem.mem[55] = 32'h001507DE; // OR_with_sign
        dut.u_imem.mem[56] = 32'h0044FFDE; // SRLI_31_repeat
        dut.u_imem.mem[57] = 32'h29BE033E; // STW_neg128
        dut.u_imem.mem[58] = 32'h28BE033E; // LDW_neg128
        dut.u_imem.mem[59] = 32'h039FFFDE; // ORI_7ff
        dut.u_imem.mem[60] = 32'h036003DE; // ANDI_800_zero
        dut.u_imem.mem[61] = 32'h03A003DE; // ORI_800
        dut.u_imem.mem[62] = 32'h03E003DE; // XORI_800
        dut.u_imem.mem[63] = 32'h0014781E; // NOR_from_zero
        dut.u_imem.mem[64] = 32'hFFFFFFFF; // INVALID_opcode

        @(posedge clk); #1;
        eq32("sync reset PC",pc,32'd0);
        eq32("sync reset r0",dut.u_regfile.regs[0],32'd0);
        @(negedge clk); rst=1'b0;
        execute("LU12I_80000",0,12,32'h15000001,2'd0,5'd1,32'h80000000,8'd0);
        execute("LU12I_FFFFF",1,12,32'h15FFFFE2,2'd0,5'd2,32'hFFFFF000,8'd0);
        execute("ORI_make_FFFFFFFF",2,5,32'h03BFFC42,2'd0,5'd2,32'hFFFFFFFF,8'd0);
        execute("ORI_555",3,5,32'h03955403,2'd0,5'd3,32'h00000555,8'd0);
        hold_one("hold-after-3",32'd16);
        execute("XORI_fff",4,6,32'h03FFFC64,2'd0,5'd4,32'h00000AAA,8'd0);
        execute("ANDI_800",5,4,32'h03600045,2'd0,5'd5,32'h00000800,8'd0);
        execute("ANDI_fff",6,4,32'h037FFC46,2'd0,5'd6,32'h00000FFF,8'd0);
        execute("AND_hi",7,0,32'h00148447,2'd0,5'd7,32'h80000000,8'd0);
        execute("OR_hi",8,1,32'h00150C28,2'd0,5'd8,32'h80000555,8'd0);
        execute("XOR_hi",9,3,32'h00158449,2'd0,5'd9,32'h7FFFFFFF,8'd0);
        execute("NOR_hi",10,2,32'h00140C2A,2'd0,5'd10,32'h7FFFFAAA,8'd0);
        execute("SLLI_0",11,7,32'h0040806B,2'd0,5'd11,32'h00000555,8'd0);
        execute("SLLI_31",12,7,32'h0040FC6C,2'd0,5'd12,32'h80000000,8'd0);
        execute("SRLI_31",13,8,32'h0044FC2D,2'd0,5'd13,32'h00000001,8'd0);
        execute("SRAI_31",14,9,32'h0048FC2E,2'd0,5'd14,32'hFFFFFFFF,8'd0);
        execute("SRAI_1",15,9,32'h0048842F,2'd0,5'd15,32'hC0000000,8'd0);
        execute("SRLI_1",16,8,32'h00448430,2'd0,5'd16,32'h40000000,8'd0);
        execute("ORI_zero",17,5,32'h03800011,2'd0,5'd17,32'h00000000,8'd0);
        execute("XORI_zero",18,6,32'h03C00052,2'd0,5'd18,32'hFFFFFFFF,8'd0);
        execute("ANDI_zero",19,4,32'h03400053,2'd0,5'd19,32'h00000000,8'd0);
        execute("XOR_dep",20,3,32'h00158534,2'd0,5'd20,32'hFFFFFFFF,8'd0);
        execute("NOR_zero",21,2,32'h00140015,2'd0,5'd21,32'hFFFFFFFF,8'd0);
        execute("OR_zero",22,1,32'h00150816,2'd0,5'd22,32'hFFFFFFFF,8'd0);
        execute("AND_zero",23,0,32'h00148817,2'd0,5'd23,32'h00000000,8'd0);
        execute("LU12I_12345",24,12,32'h142468B8,2'd0,5'd24,32'h12345000,8'd0);
        execute("ORI_dep_678",25,5,32'h0399E318,2'd0,5'd24,32'h12345678,8'd0);
        execute("ORI_base128",26,5,32'h03820019,2'd0,5'd25,32'h00000080,8'd0);
        hold_one("hold-after-26",32'd108);
        execute("STW_0",27,11,32'h29800338,2'd1,5'd24,32'h12345678,8'd32);
        hold_one("hold-after-27",32'd112);
        execute("LDW_0",28,10,32'h2880033A,2'd0,5'd26,32'h12345678,8'd0);
        execute("STW_plus4",29,11,32'h2980132E,2'd1,5'd14,32'hFFFFFFFF,8'd33);
        hold_one("hold-after-29",32'd120);
        execute("LDW_plus4",30,10,32'h2880133B,2'd0,5'd27,32'hFFFFFFFF,8'd0);
        execute("STW_minus4",31,11,32'h29BFF329,2'd1,5'd9,32'h7FFFFFFF,8'd31);
        execute("LDW_minus4",32,10,32'h28BFF33C,2'd0,5'd28,32'h7FFFFFFF,8'd0);
        execute("STW_plus12",33,11,32'h29803323,2'd1,5'd3,32'h00000555,8'd35);
        execute("LDW_plus12",34,10,32'h2880333D,2'd0,5'd29,32'h00000555,8'd0);
        execute("SLLI_dep4",35,7,32'h004093BE,2'd0,5'd30,32'h00005550,8'd0);
        execute("SRLI_dep4",36,8,32'h004493DF,2'd0,5'd31,32'h00000555,8'd0);
        execute("XORI_dep_fff",37,6,32'h03FFFFFE,2'd0,5'd30,32'h00000AAA,8'd0);
        execute("AND_dep",38,0,32'h00149BDF,2'd0,5'd31,32'h00000AAA,8'd0);
        execute("LU12I_zero",39,12,32'h1400001E,2'd0,5'd30,32'h00000000,8'd0);
        execute("ORI_max",40,5,32'h03BFFC1E,2'd0,5'd30,32'h00000FFF,8'd0);
        execute("ANDI_max",41,4,32'h037FFFDE,2'd0,5'd30,32'h00000FFF,8'd0);
        execute("SRAI_0",42,9,32'h0048805E,2'd0,5'd30,32'hFFFFFFFF,8'd0);
        execute("SRLI_0",43,8,32'h0044805E,2'd0,5'd30,32'hFFFFFFFF,8'd0);
        execute("SLLI_1",44,7,32'h0040845E,2'd0,5'd30,32'hFFFFFFFE,8'd0);
        execute("LDW_dep_neg4",45,10,32'h28BFF33E,2'd0,5'd30,32'h7FFFFFFF,8'd0);
        execute("STW_dep_plus16",46,11,32'h2980433E,2'd1,5'd30,32'h7FFFFFFF,8'd36);
        execute("LDW_dep_plus16",47,10,32'h2880433E,2'd0,5'd30,32'h7FFFFFFF,8'd0);
        execute("XORI_fff_result",48,6,32'h03FFFFDE,2'd0,5'd30,32'h7FFFF000,8'd0);
        execute("ANDI_zero_result",49,4,32'h037FFFDE,2'd0,5'd30,32'h00000000,8'd0);
        execute("ORI_after_zero",50,5,32'h03BFFFDE,2'd0,5'd30,32'h00000FFF,8'd0);
        execute("XOR_same_regs",51,3,32'h0015FBDE,2'd0,5'd30,32'h00000000,8'd0);
        hold_one("hold-after-51",32'd208);
        execute("ORI_r0_protection",52,5,32'h03BFFC00,2'd3,5'd0,32'h00000000,8'd0);
        execute("LU12I_one",53,12,32'h1400003E,2'd0,5'd30,32'h00001000,8'd0);
        execute("SRAI_31_repeat",54,9,32'h0048FC5E,2'd0,5'd30,32'hFFFFFFFF,8'd0);
        execute("OR_with_sign",55,1,32'h001507DE,2'd0,5'd30,32'hFFFFFFFF,8'd0);
        execute("SRLI_31_repeat",56,8,32'h0044FFDE,2'd0,5'd30,32'h00000001,8'd0);
        execute("STW_neg128",57,11,32'h29BE033E,2'd1,5'd30,32'h00000001,8'd0);
        execute("LDW_neg128",58,10,32'h28BE033E,2'd0,5'd30,32'h00000001,8'd0);
        execute("ORI_7ff",59,5,32'h039FFFDE,2'd0,5'd30,32'h000007FF,8'd0);
        execute("ANDI_800_zero",60,4,32'h036003DE,2'd0,5'd30,32'h00000000,8'd0);
        execute("ORI_800",61,5,32'h03A003DE,2'd0,5'd30,32'h00000800,8'd0);
        execute("XORI_800",62,6,32'h03E003DE,2'd0,5'd30,32'h00000000,8'd0);
        execute("NOR_from_zero",63,2,32'h0014781E,2'd0,5'd30,32'hFFFFFFFF,8'd0);
        execute("INVALID_opcode",64,-1,32'hFFFFFFFF,2'd2,5'd0,32'h00000000,8'd0);

        // Post-program invariants, including all four probed memory words.
        eq32("r0 still zero",dut.u_regfile.regs[0],32'd0);
        eq32("r1 high-bit",dut.u_regfile.regs[1],32'h80000000);
        eq32("r2 all ones",dut.u_regfile.regs[2],32'hFFFFFFFF);
        eq32("r24 assembled",dut.u_regfile.regs[24],32'h12345678);
        eq32("r26 load",dut.u_regfile.regs[26],32'h12345678);
        eq32("r27 negative-data",dut.u_regfile.regs[27],32'hFFFFFFFF);
        eq32("r28 negative-offset",dut.u_regfile.regs[28],32'h7FFFFFFF);
        eq32("r29 load",dut.u_regfile.regs[29],32'h00000555);
        eq32("mem 0 neg128",dut.u_dmem.mem[0],32'h00000001);
        eq32("mem 31 -4",dut.u_dmem.mem[31],32'h7FFFFFFF);
        eq32("mem 32 0",dut.u_dmem.mem[32],32'h12345678);
        eq32("mem 33 +4",dut.u_dmem.mem[33],32'hFFFFFFFF);
        eq32("mem 35 +12",dut.u_dmem.mem[35],32'h00000555);
        eq32("mem 36 +16",dut.u_dmem.mem[36],32'h7FFFFFFF);
        for (i=0;i<13;i=i+1) begin
            checks=checks+1;
            if (coverage[i] == 0) begin
                errors=errors+1;
                $display("FAIL missing coverage family=%0d",i);
            end
            $display("Coverage opcode family %0d : %0d commits",i,coverage[i]);
        end
        $display("====================================");
        $display("Instruction families covered = 13");
        $display("Committed instructions = %0d",committed);
        $display("Total checks = %0d",checks);
        $display("Total errors = %0d",errors);
        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("TEST FAILED");
        $finish;
    end
endmodule
