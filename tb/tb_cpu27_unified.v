`timescale 1ns / 1ps
// Generated mixed 27-instruction integration test for FORMAL cpu_top.
// Expected trace independently produced by a Python ISA reference model.
// This checks the actual decoder/ALU/RF/DMEM/PC and branch link behavior.
module tb_cpu27_unified;
  reg clk, rst, step_en;
  wire [31:0] pc, inst;
  wire fetch_addr_valid, instr_valid;
  wire [2:0] dbg_branch_type;
  wire [31:0] dbg_branch_imm, dbg_target_pc, dbg_next_pc;
  wire dbg_redirect, dbg_reg_we, dbg_mem_we;
  wire [4:0] dbg_waddr;
  wire [31:0] dbg_wb_data, dbg_rs1_data, dbg_rs2_data;
  integer checks, errors, committed, k;
  reg [31:0] exp_pc [0:63], exp_inst [0:63], exp_next [0:63], exp_wb [0:63], exp_bimm [0:63];
  reg [4:0]  exp_dest [0:63];
  reg [2:0]  exp_branch [0:63];
  reg exp_redir [0:63], exp_we [0:63], exp_mwe [0:63], exp_valid [0:63];
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
    input [8*40-1:0] label; input [31:0] got, wanted;
    begin
      checks = checks + 1;
      if (got !== wanted) begin
        errors = errors + 1;
        $display("FAIL step=%0d %0s got=%08h wanted=%08h", committed,label,got,wanted);
      end
    end
  endtask
  initial begin
    clk=0; rst=1; step_en=0; checks=0; errors=0; committed=0;
    // Wait for imem t=0 initialization to finish.
    #1;
    dut.u_imem.mem[ 0] = 32'h03801C02; // ORI 
    dut.u_imem.mem[ 1] = 32'h03800C03; // ORI 
    dut.u_imem.mem[ 2] = 32'h00100C44; // ADD.W 
    dut.u_imem.mem[ 3] = 32'h00110C45; // SUB.W 
    dut.u_imem.mem[ 4] = 32'h02BFECA6; // ADDI.W 
    dut.u_imem.mem[ 5] = 32'h00120CC7; // SLT 
    dut.u_imem.mem[ 6] = 32'h00128CC8; // SLTU 
    dut.u_imem.mem[ 7] = 32'h020000C9; // SLTI 
    dut.u_imem.mem[ 8] = 32'h0017086A; // SLL.W 
    dut.u_imem.mem[ 9] = 32'h001788CB; // SRL.W 
    dut.u_imem.mem[10] = 32'h001808CC; // SRA.W 
    dut.u_imem.mem[11] = 32'h00148C4D; // AND 
    dut.u_imem.mem[12] = 32'h00150C4E; // OR 
    dut.u_imem.mem[13] = 32'h00140C4F; // NOR 
    dut.u_imem.mem[14] = 32'h00158C50; // XOR 
    dut.u_imem.mem[15] = 32'h036000D1; // ANDI 
    dut.u_imem.mem[16] = 32'h03AAA812; // ORI 
    dut.u_imem.mem[17] = 32'h03FFFE53; // XORI 
    dut.u_imem.mem[18] = 32'h00409074; // SLLI.W 
    dut.u_imem.mem[19] = 32'h0044FCD5; // SRLI.W 
    dut.u_imem.mem[20] = 32'h0048FCD6; // SRAI.W 
    dut.u_imem.mem[21] = 32'h142468B7; // LU12I.W 
    dut.u_imem.mem[22] = 32'h29800004; // ST.W 
    dut.u_imem.mem[23] = 32'h28800018; // LD.W 
    dut.u_imem.mem[24] = 32'h0382301B; // ORI 
    dut.u_imem.mem[25] = 32'h58000898; // BEQ 
    dut.u_imem.mem[26] = 32'h03844419; // ORI (SKIPPED)
    dut.u_imem.mem[27] = 32'h5C000878; // BNE 
    dut.u_imem.mem[28] = 32'h03888819; // ORI (SKIPPED)
    dut.u_imem.mem[29] = 32'h50000800; // B 
    dut.u_imem.mem[30] = 32'h29801004; // ST.W (SKIPPED)
    dut.u_imem.mem[31] = 32'h54000800; // BL 
    dut.u_imem.mem[32] = 32'h038CCC19; // ORI (SKIPPED)
    dut.u_imem.mem[33] = 32'h4C00077A; // JIRL 
    dut.u_imem.mem[34] = 32'h03911019; // ORI (SKIPPED)
    dut.u_imem.mem[35] = 32'h03955419; // ORI (SKIPPED)
    dut.u_imem.mem[36] = 32'h0015E09C; // XOR 
    dut.u_imem.mem[37] = 32'hFFFFFFFF; // ILLEGAL 
    dut.u_imem.mem[38] = 32'h03BFFC1D; // ORI 
    dut.u_imem.mem[39] = 32'h2980101D; // ST.W 
    dut.u_imem.mem[40] = 32'h2880101E; // LD.W 
    dut.u_imem.mem[41] = 32'h0014FBBF; // AND 
    dut.u_imem.mem[42] = 32'h02800400; // ADDI.W 
    // Reference commit 00: ROM[0] ORI
    exp_pc[0] = 32'h0;
    exp_inst[0] = 32'h3801C02;
    exp_next[0] = 32'h4;
    exp_dest[0] = 5'h2;
    exp_wb[0] = 32'h7;
    exp_bimm[0] = 32'h0;
    exp_branch[0] = 3'h0;
    exp_redir[0] = 1'h0;
    exp_we[0] = 1'h1;
    exp_mwe[0] = 1'h0;
    exp_valid[0] = 1'b1;
    // Reference commit 01: ROM[1] ORI
    exp_pc[1] = 32'h4;
    exp_inst[1] = 32'h3800C03;
    exp_next[1] = 32'h8;
    exp_dest[1] = 5'h3;
    exp_wb[1] = 32'h3;
    exp_bimm[1] = 32'h0;
    exp_branch[1] = 3'h0;
    exp_redir[1] = 1'h0;
    exp_we[1] = 1'h1;
    exp_mwe[1] = 1'h0;
    exp_valid[1] = 1'b1;
    // Reference commit 02: ROM[2] ADD.W
    exp_pc[2] = 32'h8;
    exp_inst[2] = 32'h100C44;
    exp_next[2] = 32'hC;
    exp_dest[2] = 5'h4;
    exp_wb[2] = 32'hA;
    exp_bimm[2] = 32'h0;
    exp_branch[2] = 3'h0;
    exp_redir[2] = 1'h0;
    exp_we[2] = 1'h1;
    exp_mwe[2] = 1'h0;
    exp_valid[2] = 1'b1;
    // Reference commit 03: ROM[3] SUB.W
    exp_pc[3] = 32'hC;
    exp_inst[3] = 32'h110C45;
    exp_next[3] = 32'h10;
    exp_dest[3] = 5'h5;
    exp_wb[3] = 32'h4;
    exp_bimm[3] = 32'h0;
    exp_branch[3] = 3'h0;
    exp_redir[3] = 1'h0;
    exp_we[3] = 1'h1;
    exp_mwe[3] = 1'h0;
    exp_valid[3] = 1'b1;
    // Reference commit 04: ROM[4] ADDI.W
    exp_pc[4] = 32'h10;
    exp_inst[4] = 32'h2BFECA6;
    exp_next[4] = 32'h14;
    exp_dest[4] = 5'h6;
    exp_wb[4] = 32'hFFFFFFFF;
    exp_bimm[4] = 32'h0;
    exp_branch[4] = 3'h0;
    exp_redir[4] = 1'h0;
    exp_we[4] = 1'h1;
    exp_mwe[4] = 1'h0;
    exp_valid[4] = 1'b1;
    // Reference commit 05: ROM[5] SLT
    exp_pc[5] = 32'h14;
    exp_inst[5] = 32'h120CC7;
    exp_next[5] = 32'h18;
    exp_dest[5] = 5'h7;
    exp_wb[5] = 32'h1;
    exp_bimm[5] = 32'h0;
    exp_branch[5] = 3'h0;
    exp_redir[5] = 1'h0;
    exp_we[5] = 1'h1;
    exp_mwe[5] = 1'h0;
    exp_valid[5] = 1'b1;
    // Reference commit 06: ROM[6] SLTU
    exp_pc[6] = 32'h18;
    exp_inst[6] = 32'h128CC8;
    exp_next[6] = 32'h1C;
    exp_dest[6] = 5'h8;
    exp_wb[6] = 32'h0;
    exp_bimm[6] = 32'h0;
    exp_branch[6] = 3'h0;
    exp_redir[6] = 1'h0;
    exp_we[6] = 1'h1;
    exp_mwe[6] = 1'h0;
    exp_valid[6] = 1'b1;
    // Reference commit 07: ROM[7] SLTI
    exp_pc[7] = 32'h1C;
    exp_inst[7] = 32'h20000C9;
    exp_next[7] = 32'h20;
    exp_dest[7] = 5'h9;
    exp_wb[7] = 32'h1;
    exp_bimm[7] = 32'h0;
    exp_branch[7] = 3'h0;
    exp_redir[7] = 1'h0;
    exp_we[7] = 1'h1;
    exp_mwe[7] = 1'h0;
    exp_valid[7] = 1'b1;
    // Reference commit 08: ROM[8] SLL.W
    exp_pc[8] = 32'h20;
    exp_inst[8] = 32'h17086A;
    exp_next[8] = 32'h24;
    exp_dest[8] = 5'hA;
    exp_wb[8] = 32'h180;
    exp_bimm[8] = 32'h0;
    exp_branch[8] = 3'h0;
    exp_redir[8] = 1'h0;
    exp_we[8] = 1'h1;
    exp_mwe[8] = 1'h0;
    exp_valid[8] = 1'b1;
    // Reference commit 09: ROM[9] SRL.W
    exp_pc[9] = 32'h24;
    exp_inst[9] = 32'h1788CB;
    exp_next[9] = 32'h28;
    exp_dest[9] = 5'hB;
    exp_wb[9] = 32'h1FFFFFF;
    exp_bimm[9] = 32'h0;
    exp_branch[9] = 3'h0;
    exp_redir[9] = 1'h0;
    exp_we[9] = 1'h1;
    exp_mwe[9] = 1'h0;
    exp_valid[9] = 1'b1;
    // Reference commit 10: ROM[10] SRA.W
    exp_pc[10] = 32'h28;
    exp_inst[10] = 32'h1808CC;
    exp_next[10] = 32'h2C;
    exp_dest[10] = 5'hC;
    exp_wb[10] = 32'hFFFFFFFF;
    exp_bimm[10] = 32'h0;
    exp_branch[10] = 3'h0;
    exp_redir[10] = 1'h0;
    exp_we[10] = 1'h1;
    exp_mwe[10] = 1'h0;
    exp_valid[10] = 1'b1;
    // Reference commit 11: ROM[11] AND
    exp_pc[11] = 32'h2C;
    exp_inst[11] = 32'h148C4D;
    exp_next[11] = 32'h30;
    exp_dest[11] = 5'hD;
    exp_wb[11] = 32'h3;
    exp_bimm[11] = 32'h0;
    exp_branch[11] = 3'h0;
    exp_redir[11] = 1'h0;
    exp_we[11] = 1'h1;
    exp_mwe[11] = 1'h0;
    exp_valid[11] = 1'b1;
    // Reference commit 12: ROM[12] OR
    exp_pc[12] = 32'h30;
    exp_inst[12] = 32'h150C4E;
    exp_next[12] = 32'h34;
    exp_dest[12] = 5'hE;
    exp_wb[12] = 32'h7;
    exp_bimm[12] = 32'h0;
    exp_branch[12] = 3'h0;
    exp_redir[12] = 1'h0;
    exp_we[12] = 1'h1;
    exp_mwe[12] = 1'h0;
    exp_valid[12] = 1'b1;
    // Reference commit 13: ROM[13] NOR
    exp_pc[13] = 32'h34;
    exp_inst[13] = 32'h140C4F;
    exp_next[13] = 32'h38;
    exp_dest[13] = 5'hF;
    exp_wb[13] = 32'hFFFFFFF8;
    exp_bimm[13] = 32'h0;
    exp_branch[13] = 3'h0;
    exp_redir[13] = 1'h0;
    exp_we[13] = 1'h1;
    exp_mwe[13] = 1'h0;
    exp_valid[13] = 1'b1;
    // Reference commit 14: ROM[14] XOR
    exp_pc[14] = 32'h38;
    exp_inst[14] = 32'h158C50;
    exp_next[14] = 32'h3C;
    exp_dest[14] = 5'h10;
    exp_wb[14] = 32'h4;
    exp_bimm[14] = 32'h0;
    exp_branch[14] = 3'h0;
    exp_redir[14] = 1'h0;
    exp_we[14] = 1'h1;
    exp_mwe[14] = 1'h0;
    exp_valid[14] = 1'b1;
    // Reference commit 15: ROM[15] ANDI
    exp_pc[15] = 32'h3C;
    exp_inst[15] = 32'h36000D1;
    exp_next[15] = 32'h40;
    exp_dest[15] = 5'h11;
    exp_wb[15] = 32'h800;
    exp_bimm[15] = 32'h0;
    exp_branch[15] = 3'h0;
    exp_redir[15] = 1'h0;
    exp_we[15] = 1'h1;
    exp_mwe[15] = 1'h0;
    exp_valid[15] = 1'b1;
    // Reference commit 16: ROM[16] ORI
    exp_pc[16] = 32'h40;
    exp_inst[16] = 32'h3AAA812;
    exp_next[16] = 32'h44;
    exp_dest[16] = 5'h12;
    exp_wb[16] = 32'hAAA;
    exp_bimm[16] = 32'h0;
    exp_branch[16] = 3'h0;
    exp_redir[16] = 1'h0;
    exp_we[16] = 1'h1;
    exp_mwe[16] = 1'h0;
    exp_valid[16] = 1'b1;
    // Reference commit 17: ROM[17] XORI
    exp_pc[17] = 32'h44;
    exp_inst[17] = 32'h3FFFE53;
    exp_next[17] = 32'h48;
    exp_dest[17] = 5'h13;
    exp_wb[17] = 32'h555;
    exp_bimm[17] = 32'h0;
    exp_branch[17] = 3'h0;
    exp_redir[17] = 1'h0;
    exp_we[17] = 1'h1;
    exp_mwe[17] = 1'h0;
    exp_valid[17] = 1'b1;
    // Reference commit 18: ROM[18] SLLI.W
    exp_pc[18] = 32'h48;
    exp_inst[18] = 32'h409074;
    exp_next[18] = 32'h4C;
    exp_dest[18] = 5'h14;
    exp_wb[18] = 32'h30;
    exp_bimm[18] = 32'h0;
    exp_branch[18] = 3'h0;
    exp_redir[18] = 1'h0;
    exp_we[18] = 1'h1;
    exp_mwe[18] = 1'h0;
    exp_valid[18] = 1'b1;
    // Reference commit 19: ROM[19] SRLI.W
    exp_pc[19] = 32'h4C;
    exp_inst[19] = 32'h44FCD5;
    exp_next[19] = 32'h50;
    exp_dest[19] = 5'h15;
    exp_wb[19] = 32'h1;
    exp_bimm[19] = 32'h0;
    exp_branch[19] = 3'h0;
    exp_redir[19] = 1'h0;
    exp_we[19] = 1'h1;
    exp_mwe[19] = 1'h0;
    exp_valid[19] = 1'b1;
    // Reference commit 20: ROM[20] SRAI.W
    exp_pc[20] = 32'h50;
    exp_inst[20] = 32'h48FCD6;
    exp_next[20] = 32'h54;
    exp_dest[20] = 5'h16;
    exp_wb[20] = 32'hFFFFFFFF;
    exp_bimm[20] = 32'h0;
    exp_branch[20] = 3'h0;
    exp_redir[20] = 1'h0;
    exp_we[20] = 1'h1;
    exp_mwe[20] = 1'h0;
    exp_valid[20] = 1'b1;
    // Reference commit 21: ROM[21] LU12I.W
    exp_pc[21] = 32'h54;
    exp_inst[21] = 32'h142468B7;
    exp_next[21] = 32'h58;
    exp_dest[21] = 5'h17;
    exp_wb[21] = 32'h12345000;
    exp_bimm[21] = 32'h0;
    exp_branch[21] = 3'h0;
    exp_redir[21] = 1'h0;
    exp_we[21] = 1'h1;
    exp_mwe[21] = 1'h0;
    exp_valid[21] = 1'b1;
    // Reference commit 22: ROM[22] ST.W
    exp_pc[22] = 32'h58;
    exp_inst[22] = 32'h29800004;
    exp_next[22] = 32'h5C;
    exp_dest[22] = 5'h4;
    exp_wb[22] = 32'h0;
    exp_bimm[22] = 32'h0;
    exp_branch[22] = 3'h0;
    exp_redir[22] = 1'h0;
    exp_we[22] = 1'h0;
    exp_mwe[22] = 1'h1;
    exp_valid[22] = 1'b1;
    // Reference commit 23: ROM[23] LD.W
    exp_pc[23] = 32'h5C;
    exp_inst[23] = 32'h28800018;
    exp_next[23] = 32'h60;
    exp_dest[23] = 5'h18;
    exp_wb[23] = 32'hA;
    exp_bimm[23] = 32'h0;
    exp_branch[23] = 3'h0;
    exp_redir[23] = 1'h0;
    exp_we[23] = 1'h1;
    exp_mwe[23] = 1'h0;
    exp_valid[23] = 1'b1;
    // Reference commit 24: ROM[24] ORI
    exp_pc[24] = 32'h60;
    exp_inst[24] = 32'h382301B;
    exp_next[24] = 32'h64;
    exp_dest[24] = 5'h1B;
    exp_wb[24] = 32'h8C;
    exp_bimm[24] = 32'h0;
    exp_branch[24] = 3'h0;
    exp_redir[24] = 1'h0;
    exp_we[24] = 1'h1;
    exp_mwe[24] = 1'h0;
    exp_valid[24] = 1'b1;
    // Reference commit 25: ROM[25] BEQ
    exp_pc[25] = 32'h64;
    exp_inst[25] = 32'h58000898;
    exp_next[25] = 32'h6C;
    exp_dest[25] = 5'h18;
    exp_wb[25] = 32'h0;
    exp_bimm[25] = 32'h8;
    exp_branch[25] = 3'h1;
    exp_redir[25] = 1'h1;
    exp_we[25] = 1'h0;
    exp_mwe[25] = 1'h0;
    exp_valid[25] = 1'b1;
    // Reference commit 26: ROM[27] BNE
    exp_pc[26] = 32'h6C;
    exp_inst[26] = 32'h5C000878;
    exp_next[26] = 32'h74;
    exp_dest[26] = 5'h18;
    exp_wb[26] = 32'h0;
    exp_bimm[26] = 32'h8;
    exp_branch[26] = 3'h2;
    exp_redir[26] = 1'h1;
    exp_we[26] = 1'h0;
    exp_mwe[26] = 1'h0;
    exp_valid[26] = 1'b1;
    // Reference commit 27: ROM[29] B
    exp_pc[27] = 32'h74;
    exp_inst[27] = 32'h50000800;
    exp_next[27] = 32'h7C;
    exp_dest[27] = 5'h0;
    exp_wb[27] = 32'h0;
    exp_bimm[27] = 32'h8;
    exp_branch[27] = 3'h3;
    exp_redir[27] = 1'h1;
    exp_we[27] = 1'h0;
    exp_mwe[27] = 1'h0;
    exp_valid[27] = 1'b1;
    // Reference commit 28: ROM[31] BL
    exp_pc[28] = 32'h7C;
    exp_inst[28] = 32'h54000800;
    exp_next[28] = 32'h84;
    exp_dest[28] = 5'h1;
    exp_wb[28] = 32'h80;
    exp_bimm[28] = 32'h8;
    exp_branch[28] = 3'h4;
    exp_redir[28] = 1'h1;
    exp_we[28] = 1'h1;
    exp_mwe[28] = 1'h0;
    exp_valid[28] = 1'b1;
    // Reference commit 29: ROM[33] JIRL
    exp_pc[29] = 32'h84;
    exp_inst[29] = 32'h4C00077A;
    exp_next[29] = 32'h90;
    exp_dest[29] = 5'h1A;
    exp_wb[29] = 32'h88;
    exp_bimm[29] = 32'h4;
    exp_branch[29] = 3'h5;
    exp_redir[29] = 1'h1;
    exp_we[29] = 1'h1;
    exp_mwe[29] = 1'h0;
    exp_valid[29] = 1'b1;
    // Reference commit 30: ROM[36] XOR
    exp_pc[30] = 32'h90;
    exp_inst[30] = 32'h15E09C;
    exp_next[30] = 32'h94;
    exp_dest[30] = 5'h1C;
    exp_wb[30] = 32'h0;
    exp_bimm[30] = 32'h0;
    exp_branch[30] = 3'h0;
    exp_redir[30] = 1'h0;
    exp_we[30] = 1'h1;
    exp_mwe[30] = 1'h0;
    exp_valid[30] = 1'b1;
    // Reference commit 31: ROM[37] ILLEGAL
    exp_pc[31] = 32'h94;
    exp_inst[31] = 32'hFFFFFFFF;
    exp_next[31] = 32'h98;
    exp_dest[31] = 5'h0;
    exp_wb[31] = 32'h0;
    exp_bimm[31] = 32'h0;
    exp_branch[31] = 3'h0;
    exp_redir[31] = 1'h0;
    exp_we[31] = 1'h0;
    exp_mwe[31] = 1'h0;
    exp_valid[31] = 1'b0;
    // Reference commit 32: ROM[38] ORI
    exp_pc[32] = 32'h98;
    exp_inst[32] = 32'h3BFFC1D;
    exp_next[32] = 32'h9C;
    exp_dest[32] = 5'h1D;
    exp_wb[32] = 32'hFFF;
    exp_bimm[32] = 32'h0;
    exp_branch[32] = 3'h0;
    exp_redir[32] = 1'h0;
    exp_we[32] = 1'h1;
    exp_mwe[32] = 1'h0;
    exp_valid[32] = 1'b1;
    // Reference commit 33: ROM[39] ST.W
    exp_pc[33] = 32'h9C;
    exp_inst[33] = 32'h2980101D;
    exp_next[33] = 32'hA0;
    exp_dest[33] = 5'h1D;
    exp_wb[33] = 32'h0;
    exp_bimm[33] = 32'h0;
    exp_branch[33] = 3'h0;
    exp_redir[33] = 1'h0;
    exp_we[33] = 1'h0;
    exp_mwe[33] = 1'h1;
    exp_valid[33] = 1'b1;
    // Reference commit 34: ROM[40] LD.W
    exp_pc[34] = 32'hA0;
    exp_inst[34] = 32'h2880101E;
    exp_next[34] = 32'hA4;
    exp_dest[34] = 5'h1E;
    exp_wb[34] = 32'hFFF;
    exp_bimm[34] = 32'h0;
    exp_branch[34] = 3'h0;
    exp_redir[34] = 1'h0;
    exp_we[34] = 1'h1;
    exp_mwe[34] = 1'h0;
    exp_valid[34] = 1'b1;
    // Reference commit 35: ROM[41] AND
    exp_pc[35] = 32'hA4;
    exp_inst[35] = 32'h14FBBF;
    exp_next[35] = 32'hA8;
    exp_dest[35] = 5'h1F;
    exp_wb[35] = 32'hFFF;
    exp_bimm[35] = 32'h0;
    exp_branch[35] = 3'h0;
    exp_redir[35] = 1'h0;
    exp_we[35] = 1'h1;
    exp_mwe[35] = 1'h0;
    exp_valid[35] = 1'b1;
    // Reference commit 36: ROM[42] ADDI.W
    exp_pc[36] = 32'hA8;
    exp_inst[36] = 32'h2800400;
    exp_next[36] = 32'hAC;
    exp_dest[36] = 5'h0;
    exp_wb[36] = 32'h1;
    exp_bimm[36] = 32'h0;
    exp_branch[36] = 3'h0;
    exp_redir[36] = 1'h0;
    exp_we[36] = 1'h0;
    exp_mwe[36] = 1'h0;
    exp_valid[36] = 1'b1;
    @(posedge clk); #1;
    eq32("reset PC",pc,32'd0);
    eq32("reset r0",dut.u_regfile.regs[0],32'd0);
    rst=0;
    for (k=0; k<37; k=k+1) begin
      @(negedge clk); step_en=1; #1;
      eq32("PC",pc,exp_pc[k]);
      eq32("machine word",inst,exp_inst[k]);
      eq32("fetch address valid",{31'b0,fetch_addr_valid},32'd1);
      eq32("decoded valid",{31'b0,instr_valid},{31'b0,exp_valid[k]});
      eq32("branch type",{29'b0,dbg_branch_type},{29'b0,exp_branch[k]});
      eq32("branch immediate",dbg_branch_imm,exp_bimm[k]);
      eq32("redirect",{31'b0,dbg_redirect},{31'b0,exp_redir[k]});
      eq32("next PC",dbg_next_pc,exp_next[k]);
      eq32("write enable",{31'b0,dbg_reg_we},{31'b0,exp_we[k]});
      eq32("memory write enable",{31'b0,dbg_mem_we},{31'b0,exp_mwe[k]});
      if (exp_we[k]) begin
        eq32("write address",{27'b0,dbg_waddr},{27'b0,exp_dest[k]});
        eq32("writeback data",dbg_wb_data,exp_wb[k]);
      end
      if (exp_redir[k]) eq32("redirect target",dbg_target_pc,exp_next[k]);
      @(posedge clk); #1;
      eq32("committed next PC",pc,exp_next[k]);
      if (exp_we[k]) eq32("committed register",dut.u_regfile.regs[exp_dest[k]],exp_wb[k]);
      committed=committed+1;
      // One full stalled cycle every fourth commit tests architectural hold.
      if ((k%4)==0) begin
        @(negedge clk); step_en=0; #1;
        eq32("stall RF write",{31'b0,dbg_reg_we},32'd0);
        eq32("stall MEM write",{31'b0,dbg_mem_we},32'd0);
        @(posedge clk); #1;
        eq32("stall PC",pc,exp_next[k]);
      end
    end
    eq32("final r1",dut.u_regfile.regs[1],32'h00000080);
    eq32("final r2",dut.u_regfile.regs[2],32'h00000007);
    eq32("final r3",dut.u_regfile.regs[3],32'h00000003);
    eq32("final r4",dut.u_regfile.regs[4],32'h0000000A);
    eq32("final r5",dut.u_regfile.regs[5],32'h00000004);
    eq32("final r6",dut.u_regfile.regs[6],32'hFFFFFFFF);
    eq32("final r7",dut.u_regfile.regs[7],32'h00000001);
    eq32("final r9",dut.u_regfile.regs[9],32'h00000001);
    eq32("final r10",dut.u_regfile.regs[10],32'h00000180);
    eq32("final r11",dut.u_regfile.regs[11],32'h01FFFFFF);
    eq32("final r12",dut.u_regfile.regs[12],32'hFFFFFFFF);
    eq32("final r13",dut.u_regfile.regs[13],32'h00000003);
    eq32("final r14",dut.u_regfile.regs[14],32'h00000007);
    eq32("final r15",dut.u_regfile.regs[15],32'hFFFFFFF8);
    eq32("final r16",dut.u_regfile.regs[16],32'h00000004);
    eq32("final r17",dut.u_regfile.regs[17],32'h00000800);
    eq32("final r18",dut.u_regfile.regs[18],32'h00000AAA);
    eq32("final r19",dut.u_regfile.regs[19],32'h00000555);
    eq32("final r20",dut.u_regfile.regs[20],32'h00000030);
    eq32("final r21",dut.u_regfile.regs[21],32'h00000001);
    eq32("final r22",dut.u_regfile.regs[22],32'hFFFFFFFF);
    eq32("final r23",dut.u_regfile.regs[23],32'h12345000);
    eq32("final r24",dut.u_regfile.regs[24],32'h0000000A);
    eq32("final r26",dut.u_regfile.regs[26],32'h00000088);
    eq32("final r27",dut.u_regfile.regs[27],32'h0000008C);
    eq32("final r29",dut.u_regfile.regs[29],32'h00000FFF);
    eq32("final r30",dut.u_regfile.regs[30],32'h00000FFF);
    eq32("final r31",dut.u_regfile.regs[31],32'h00000FFF);
    eq32("r0 must remain zero",dut.u_regfile.regs[0],32'd0);
    eq32("skipped r25 is zero",dut.u_regfile.regs[25],32'd0);
    eq32("mem[0] original store",dut.u_dmem.mem[0],32'd10);
    eq32("mem[1] final store",dut.u_dmem.mem[1],32'h00000FFF);
    eq32("committed trace length",committed,37);
    $display("============================================");
    $display("Instruction kinds tested = 27 + illegal");
    $display("Committed instructions = %0d",committed);
    $display("Total checks = %0d",checks);
    $display("Total errors = %0d",errors);
    if (errors==0) $display("ALL TESTS PASSED");
    else $display("TEST FAILED");
    $finish;
  end
endmodule
