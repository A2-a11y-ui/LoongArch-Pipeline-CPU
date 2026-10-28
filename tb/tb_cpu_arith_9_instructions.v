`timescale 1ns / 1ps
// CPU arithmetic integration test for Team A's 9 added LoongArch instructions.
// Derived from the verified tb_cpu_top_smoke.v testing conventions.
// DUT: cpu_top_arith_test (uses the new decoder, not decoder_v2).
// Verilog-2001 / Vivado 2019.1. This test does NOT verify pipelining.
module tb_cpu_arith_9_instructions;
    reg clk, rst, step_en;
    wire [31:0] pc, inst;
    wire fetch_addr_valid, instr_valid;
    wire [2:0] dbg_branch_type;
    wire [31:0] dbg_branch_imm, dbg_target_pc, dbg_next_pc;
    wire dbg_redirect, dbg_reg_we, dbg_mem_we;
    wire [4:0] dbg_waddr;
    wire [31:0] dbg_wb_data, dbg_rs1_data, dbg_rs2_data;
    integer checks, errors, steps;

    cpu_top_arith_test dut (
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

    function [31:0] enc_r3;
        input [31:0] opcode;
        input [4:0] rd, rj, rk;
        begin
            enc_r3 = opcode | ({27'd0,rk} << 10) |
                     ({27'd0,rj} << 5) | {27'd0,rd};
        end
    endfunction

    function [31:0] enc_i12;
        input [31:0] opcode;
        input [4:0] rd, rj;
        input [11:0] si12;
        begin
            enc_i12 = opcode | ({20'd0,si12} << 10) |
                      ({27'd0,rj} << 5) | {27'd0,rd};
        end
    endfunction

    task expect32;
        input [8*40-1:0] label;
        input [31:0] observed, expected;
        begin
            checks = checks + 1;
            if (observed !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s: got=%08h expected=%08h", label, observed, expected);
            end
        end
    endtask

    // Execute one real instruction, verify control and actual regfile content,
    // then insert one full stalled clock to verify architectural hold.
    task step_check;
        input [8*32-1:0] label;
        input integer index;
        input [31:0] expected_inst;
        input [4:0]  dest;
        input [31:0] result;
        reg [31:0] addr;
        integer before_errors;
        begin
            before_errors = errors;
            addr = index * 4;
            @(negedge clk);
            step_en = 1'b1;
            #1;
            expect32("PC",pc,addr);
            expect32("machine code",inst,expected_inst);
            expect32("valid",{31'd0,instr_valid},32'd1);
            expect32("address valid",{31'd0,fetch_addr_valid},32'd1);
            expect32("no branch",{31'd0,dbg_branch_type},32'd0);
            expect32("no redirect",{31'd0,dbg_redirect},32'd0);
            expect32("no memory write",{31'd0,dbg_mem_we},32'd0);
            expect32("destination",{27'd0,dbg_waddr},{27'd0,dest});
            expect32("reg write enable",{31'd0,dbg_reg_we},(dest==5'd0)?32'd0:32'd1);
            if (dest != 5'd0) expect32("ALU writeback result",dbg_wb_data,result);
            expect32("next PC",dbg_next_pc,addr+32'd4);
            @(posedge clk); #1;
            expect32("committed PC",pc,addr+32'd4);
            expect32("stored register",dut.u_regfile.regs[dest],result);
            steps = steps + 1;
            @(negedge clk);
            step_en = 1'b0;
            #1;
            expect32("stalled RF write",{31'd0,dbg_reg_we},32'd0);
            expect32("stalled DMEM write",{31'd0,dbg_mem_we},32'd0);
            @(posedge clk); #1;
            expect32("stalled PC",pc,addr+32'd4);
            if (errors == before_errors) $display("PASS step %0d: %0s",steps,label);
            else $display("FAIL step %0d: %0s",steps,label);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        step_en = 1'b0;
        checks = 0;
        errors = 0;
        steps = 0;
        // Avoid ROM overwrite by its t=0 initialization block.
        #1;
        dut.u_imem.mem[ 0] = enc_i12(32'h03800000,5'd2,5'd0,12'h007); // ORI
        dut.u_imem.mem[ 1] = enc_i12(32'h03800000,5'd3,5'd0,12'h003); // ORI
        dut.u_imem.mem[ 2] = enc_r3(32'h00100000,5'd4,5'd2,5'd3); // ADD.W
        dut.u_imem.mem[ 3] = enc_r3(32'h00110000,5'd5,5'd2,5'd3); // SUB.W
        dut.u_imem.mem[ 4] = enc_i12(32'h02800000,5'd6,5'd5,12'hFFB); // ADDI.W
        dut.u_imem.mem[ 5] = enc_r3(32'h00120000,5'd7,5'd6,5'd3); // SLT
        dut.u_imem.mem[ 6] = enc_r3(32'h00128000,5'd8,5'd6,5'd3); // SLTU
        dut.u_imem.mem[ 7] = enc_i12(32'h02000000,5'd9,5'd6,12'h000); // SLTI
        dut.u_imem.mem[ 8] = enc_i12(32'h02000000,5'd10,5'd3,12'hFFF); // SLTI
        dut.u_imem.mem[ 9] = enc_i12(32'h03800000,5'd11,5'd0,12'h001); // ORI
        dut.u_imem.mem[10] = enc_r3(32'h00170000,5'd12,5'd3,5'd11); // SLL.W
        dut.u_imem.mem[11] = enc_r3(32'h00178000,5'd13,5'd6,5'd11); // SRL.W
        dut.u_imem.mem[12] = enc_r3(32'h00180000,5'd14,5'd6,5'd11); // SRA.W
        dut.u_imem.mem[13] = enc_r3(32'h00170000,5'd15,5'd11,5'd3); // SLL.W
        dut.u_imem.mem[14] = enc_r3(32'h00178000,5'd16,5'd13,5'd3); // SRL.W
        dut.u_imem.mem[15] = enc_r3(32'h00180000,5'd17,5'd13,5'd3); // SRA.W
        dut.u_imem.mem[16] = enc_i12(32'h02800000,5'd18,5'd0,12'h800); // ADDI.W
        dut.u_imem.mem[17] = enc_i12(32'h02800000,5'd19,5'd0,12'h7FF); // ADDI.W
        dut.u_imem.mem[18] = enc_r3(32'h00100000,5'd20,5'd18,5'd19); // ADD.W
        dut.u_imem.mem[19] = enc_r3(32'h00110000,5'd21,5'd0,5'd19); // SUB.W
        dut.u_imem.mem[20] = enc_r3(32'h00120000,5'd22,5'd18,5'd19); // SLT
        dut.u_imem.mem[21] = enc_r3(32'h00128000,5'd23,5'd18,5'd19); // SLTU
        dut.u_imem.mem[22] = enc_i12(32'h03800000,5'd24,5'd0,12'h01F); // ORI
        dut.u_imem.mem[23] = enc_r3(32'h00170000,5'd25,5'd11,5'd24); // SLL.W
        dut.u_imem.mem[24] = enc_r3(32'h00178000,5'd26,5'd25,5'd24); // SRL.W
        dut.u_imem.mem[25] = enc_r3(32'h00180000,5'd27,5'd25,5'd24); // SRA.W
        dut.u_imem.mem[26] = enc_r3(32'h00100000,5'd28,5'd20,5'd11); // ADD.W
        dut.u_imem.mem[27] = enc_i12(32'h02800000,5'd29,5'd0,12'h000); // ADDI.W
        dut.u_imem.mem[28] = enc_r3(32'h00110000,5'd30,5'd29,5'd11); // SUB.W
        dut.u_imem.mem[29] = enc_i12(32'h02000000,5'd31,5'd3,12'h004); // SLTI
        dut.u_imem.mem[30] = enc_r3(32'h00170000,5'd0,5'd11,5'd24); // SLL.W
        dut.u_imem.mem[31] = enc_r3(32'h00100000,5'd1,5'd2,5'd5); // ADD.W
        dut.u_imem.mem[32] = enc_i12(32'h02800000,5'd2,5'd2,12'h001); // ADDI.W
        dut.u_imem.mem[33] = enc_r3(32'h00110000,5'd3,5'd2,5'd2); // SUB.W
        dut.u_imem.mem[34] = enc_r3(32'h00178000,5'd4,5'd25,5'd0); // SRL.W
        dut.u_imem.mem[35] = enc_r3(32'h00180000,5'd5,5'd25,5'd0); // SRA.W
        dut.u_imem.mem[36] = enc_r3(32'h00170000,5'd6,5'd25,5'd0); // SLL.W
        dut.u_imem.mem[37] = enc_i12(32'h02800000,5'd7,5'd0,12'hFFF); // ADDI.W
        dut.u_imem.mem[38] = enc_i12(32'h02000000,5'd8,5'd7,12'hFFF); // SLTI
        dut.u_imem.mem[39] = enc_r3(32'h00128000,5'd9,5'd7,5'd24); // SLTU
        dut.u_imem.mem[40] = enc_r3(32'h00120000,5'd10,5'd7,5'd24); // SLT

        @(posedge clk); #1;
        expect32("synchronous PC reset",pc,32'd0);
        expect32("r0 after reset",dut.u_regfile.regs[0],32'd0);
        rst = 1'b0;
        step_check("ORI step 0",0,32'h03801C02,5'd2,32'h00000007);
        step_check("ORI step 1",1,32'h03800C03,5'd3,32'h00000003);
        step_check("ADD.W step 2",2,32'h00100C44,5'd4,32'h0000000A);
        step_check("SUB.W step 3",3,32'h00110C45,5'd5,32'h00000004);
        step_check("ADDI.W step 4",4,32'h02BFECA6,5'd6,32'hFFFFFFFF);
        step_check("SLT step 5",5,32'h00120CC7,5'd7,32'h00000001);
        step_check("SLTU step 6",6,32'h00128CC8,5'd8,32'h00000000);
        step_check("SLTI step 7",7,32'h020000C9,5'd9,32'h00000001);
        step_check("SLTI step 8",8,32'h023FFC6A,5'd10,32'h00000000);
        step_check("ORI step 9",9,32'h0380040B,5'd11,32'h00000001);
        step_check("SLL.W step 10",10,32'h00172C6C,5'd12,32'h00000006);
        step_check("SRL.W step 11",11,32'h0017ACCD,5'd13,32'h7FFFFFFF);
        step_check("SRA.W step 12",12,32'h00182CCE,5'd14,32'hFFFFFFFF);
        step_check("SLL.W step 13",13,32'h00170D6F,5'd15,32'h00000008);
        step_check("SRL.W step 14",14,32'h00178DB0,5'd16,32'h0FFFFFFF);
        step_check("SRA.W step 15",15,32'h00180DB1,5'd17,32'h0FFFFFFF);
        step_check("ADDI.W step 16",16,32'h02A00012,5'd18,32'hFFFFF800);
        step_check("ADDI.W step 17",17,32'h029FFC13,5'd19,32'h000007FF);
        step_check("ADD.W step 18",18,32'h00104E54,5'd20,32'hFFFFFFFF);
        step_check("SUB.W step 19",19,32'h00114C15,5'd21,32'hFFFFF801);
        step_check("SLT step 20",20,32'h00124E56,5'd22,32'h00000001);
        step_check("SLTU step 21",21,32'h0012CE57,5'd23,32'h00000000);
        step_check("ORI step 22",22,32'h03807C18,5'd24,32'h0000001F);
        step_check("SLL.W step 23",23,32'h00176179,5'd25,32'h80000000);
        step_check("SRL.W step 24",24,32'h0017E33A,5'd26,32'h00000001);
        step_check("SRA.W step 25",25,32'h0018633B,5'd27,32'hFFFFFFFF);
        step_check("ADD.W step 26",26,32'h00102E9C,5'd28,32'h00000000);
        step_check("ADDI.W step 27",27,32'h0280001D,5'd29,32'h00000000);
        step_check("SUB.W step 28",28,32'h00112FBE,5'd30,32'hFFFFFFFF);
        step_check("SLTI step 29",29,32'h0200107F,5'd31,32'h00000001);
        step_check("SLL.W step 30",30,32'h00176160,5'd0,32'h00000000);
        step_check("ADD.W step 31",31,32'h00101441,5'd1,32'h0000000B);
        step_check("ADDI.W step 32",32,32'h02800442,5'd2,32'h00000008);
        step_check("SUB.W step 33",33,32'h00110843,5'd3,32'h00000000);
        step_check("SRL.W step 34",34,32'h00178324,5'd4,32'h80000000);
        step_check("SRA.W step 35",35,32'h00180325,5'd5,32'h80000000);
        step_check("SLL.W step 36",36,32'h00170326,5'd6,32'h80000000);
        step_check("ADDI.W step 37",37,32'h02BFFC07,5'd7,32'hFFFFFFFF);
        step_check("SLTI step 38",38,32'h023FFCE8,5'd8,32'h00000000);
        step_check("SLTU step 39",39,32'h0012E0E9,5'd9,32'h00000000);
        step_check("SLT step 40",40,32'h001260EA,5'd10,32'h00000001);

        $display("========================================");
        $display("Executed program steps = %0d",steps);
        $display("Total checks = %0d, errors = %0d",checks,errors);
        if (errors == 0)
            $display("ALL TESTS PASSED (%0d checks)",checks);
        else
            $display("TESTS FAILED: %0d errors",errors);
        $finish;
    end
endmodule
