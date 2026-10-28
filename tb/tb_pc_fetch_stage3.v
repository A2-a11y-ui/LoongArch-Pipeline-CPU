`timescale 1ns / 1ps
// Self-checking PC -> IMEM -> decoder -> regfile/ALU/dmem program-level test.
// Works with teammate A's approved pc_reg; otherwise use test-only reference.
module tb_pc_fetch_stage3;
    reg clk, rst, step_en, redirect;
    reg [31:0] redirect_pc;
    wire [31:0] pc, inst, dbg_wb_data, dbg_alu_result;
    wire fetch_addr_valid, instr_valid, dbg_reg_we, dbg_mem_we;
    integer checks, errors;

    pc_fetch_stage3 dut (
        .clk(clk), .rst(rst), .step_en(step_en),
        .redirect(redirect), .redirect_pc(redirect_pc),
        .pc(pc), .inst(inst), .fetch_addr_valid(fetch_addr_valid),
        .instr_valid(instr_valid), .dbg_reg_we(dbg_reg_we),
        .dbg_mem_we(dbg_mem_we), .dbg_wb_data(dbg_wb_data),
        .dbg_alu_result(dbg_alu_result)
    );
    always #5 clk = ~clk;

    function [31:0] enc_ri12;
        input [31:0] opcode;
        input [4:0] rd;
        input [4:0] rj;
        input [11:0] imm;
        begin
            enc_ri12 = opcode | ({20'b0, imm} << 10) |
                       ({27'b0, rj} << 5) | {27'b0, rd};
        end
    endfunction

    function [31:0] enc_3r;
        input [31:0] opcode;
        input [4:0] rd;
        input [4:0] rj;
        input [4:0] rk;
        begin
            enc_3r = opcode | ({27'b0, rk} << 10) |
                     ({27'b0, rj} << 5) | {27'b0, rd};
        end
    endfunction

    function [31:0] enc_u20;
        input [4:0] rd;
        input [19:0] imm;
        begin
            enc_u20 = 32'h14000000 | ({12'b0, imm} << 5) | {27'b0, rd};
        end
    endfunction

    task expect32;
        input [8*64-1:0] label;
        input [31:0] got;
        input [31:0] expected;
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s: got=%08h expected=%08h",label,got,expected);
            end else
                $display("PASS %0s = %08h",label,got);
        end
    endtask

    task expect1;
        input [8*64-1:0] label;
        input got;
        input expected;
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s: got=%b expected=%b",label,got,expected);
            end else
                $display("PASS %0s = %b",label,got);
        end
    endtask

    task check_reg;
        input [4:0] r;
        input [31:0] expected;
        begin
            expect32("register content",dut.u_fetch.u_datapath.u_regfile.regs[r],expected);
        end
    endtask

    task run_one;
        input [31:0] pc_before;
        input [31:0] expected_instruction;
        begin
            @(negedge clk);
            step_en = 1'b1;
            redirect = 1'b0;
            #1;
            expect32("PC before execute",pc,pc_before);
            expect32("fetched instruction",inst,expected_instruction);
            expect1("fetch address valid",fetch_addr_valid,1'b1);
            expect1("decoded instruction valid",instr_valid,1'b1);
            @(posedge clk);
            #1;
            expect32("PC after execute",pc,pc_before+32'd4);
        end
    endtask

    task hold_pc;
        input [31:0] expected_pc;
        begin
            @(negedge clk);
            step_en=0; redirect=0;
            #1;
            expect32("held PC before edge",pc,expected_pc);
            expect1("held register write disabled",dbg_reg_we,1'b0);
            expect1("held memory write disabled",dbg_mem_we,1'b0);
            @(posedge clk); #1;
            expect32("held PC after edge",pc,expected_pc);
        end
    endtask

    task jump_without_execute;
        input [31:0] source_pc;
        input [31:0] target_pc;
        begin
            @(negedge clk);
            step_en=1; redirect=1; redirect_pc=target_pc;
            #1;
            expect32("redirect source",pc,source_pc);
            expect1("redirect regwrite disabled",dbg_reg_we,1'b0);
            expect1("redirect memwrite disabled",dbg_mem_we,1'b0);
            @(posedge clk); #1;
            expect32("redirect target",pc,target_pc);
            redirect=0;
        end
    endtask

    initial begin
        clk=0; rst=1; step_en=0; redirect=0;
        redirect_pc=0; checks=0; errors=0;
        #1;

        // Program loading through simulation hierarchy; not synthesizable.
        dut.u_fetch.u_imem.mem[0]  = enc_u20(5'd1,20'h12345);            // r1=12345000
        dut.u_fetch.u_imem.mem[1]  = enc_ri12(32'h03800000,5'd1,5'd1,12'h678); // r1=12345678
        dut.u_fetch.u_imem.mem[2]  = enc_u20(5'd2,20'h80000);            // r2=80000000
        dut.u_fetch.u_imem.mem[3]  = enc_3r(32'h00488000,5'd3,5'd2,5'd31); // SRAI r3=r2>>31
        dut.u_fetch.u_imem.mem[4]  = enc_3r(32'h00448000,5'd4,5'd2,5'd31); // SRLI r4=1
        dut.u_fetch.u_imem.mem[5]  = enc_3r(32'h00408000,5'd5,5'd4,5'd31); // SLLI r5=80000000
        dut.u_fetch.u_imem.mem[6]  = enc_3r(32'h00148000,5'd6,5'd1,5'd3);  // AND r6=r1&r3
        dut.u_fetch.u_imem.mem[7]  = enc_3r(32'h00150000,5'd7,5'd4,5'd5);  // OR r7=r4|r5
        dut.u_fetch.u_imem.mem[8]  = enc_3r(32'h00158000,5'd8,5'd1,5'd6);  // XOR r8=r1^r6
        dut.u_fetch.u_imem.mem[9]  = enc_3r(32'h00140000,5'd9,5'd8,5'd0);  // NOR r9=~(r8|r0)
        dut.u_fetch.u_imem.mem[10] = enc_ri12(32'h03400000,5'd10,5'd1,12'h0FF); // ANDI r10=78
        dut.u_fetch.u_imem.mem[11] = enc_ri12(32'h03C00000,5'd11,5'd10,12'h001); // XORI r11=79
        dut.u_fetch.u_imem.mem[12] = enc_ri12(32'h29800000,5'd1,5'd0,12'h000); // ST.W r1,[r0+0]
        dut.u_fetch.u_imem.mem[13] = enc_ri12(32'h28800000,5'd12,5'd0,12'h000); // LD.W r12,[r0+0]
        dut.u_fetch.u_imem.mem[14] = enc_ri12(32'h03800000,5'd13,5'd12,12'h000); // ORI r13=r12|0
        dut.u_fetch.u_imem.mem[15] = enc_ri12(32'h03800000,5'd0,5'd1,12'h333); // ORI r0 (ignored)
        dut.u_fetch.u_imem.mem[16] = 32'h00000000;                 // unsupported
        dut.u_fetch.u_imem.mem[32] = enc_ri12(32'h03800000,5'd20,5'd0,12'h055); // r20=0x55

        @(posedge clk); #1;
        expect32("PC reset to zero",pc,32'h00000000);
        expect1("reset disables regwrite",dbg_reg_we,1'b0);
        @(negedge clk); rst=0;

        // First two instructions; test hold in the middle of execution.
        run_one(32'd0, dut.u_fetch.u_imem.mem[0]);
        check_reg(5'd1,32'h12345000);
        hold_pc(32'd4);
        check_reg(5'd1,32'h12345000);
        run_one(32'd4, dut.u_fetch.u_imem.mem[1]);
        check_reg(5'd1,32'h12345678);

        // Remaining instructions must advance PC automatically by 4.
        run_one(32'd8, dut.u_fetch.u_imem.mem[2]);
        check_reg(5'd2,32'h80000000);
        run_one(32'd12, dut.u_fetch.u_imem.mem[3]);
        check_reg(5'd3,32'hFFFFFFFF);
        run_one(32'd16, dut.u_fetch.u_imem.mem[4]);
        check_reg(5'd4,32'h00000001);
        run_one(32'd20, dut.u_fetch.u_imem.mem[5]);
        check_reg(5'd5,32'h80000000);
        run_one(32'd24, dut.u_fetch.u_imem.mem[6]);
        check_reg(5'd6,32'h12345678);
        run_one(32'd28, dut.u_fetch.u_imem.mem[7]);
        check_reg(5'd7,32'h80000001);
        run_one(32'd32, dut.u_fetch.u_imem.mem[8]);
        check_reg(5'd8,32'h00000000);
        run_one(32'd36, dut.u_fetch.u_imem.mem[9]);
        check_reg(5'd9,32'hFFFFFFFF);
        run_one(32'd40, dut.u_fetch.u_imem.mem[10]);
        check_reg(5'd10,32'h00000078);
        run_one(32'd44, dut.u_fetch.u_imem.mem[11]);
        check_reg(5'd11,32'h00000079);
        run_one(32'd48,dut.u_fetch.u_imem.mem[12]);
        expect32("ST.W stored",dut.u_fetch.u_datapath.u_dmem.mem[0],32'h12345678);
        run_one(32'd52,dut.u_fetch.u_imem.mem[13]);
        check_reg(5'd12,32'h12345678);
        run_one(32'd56,dut.u_fetch.u_imem.mem[14]);
        check_reg(5'd13,32'h12345678);
        run_one(32'd60,dut.u_fetch.u_imem.mem[15]);
        check_reg(5'd0,32'h00000000);

        // After 16 instructions, PC=64 points to unsupported inst=0.
        @(negedge clk); step_en=1; redirect=0; #1;
        expect32("PC after program",pc,32'd64);
        expect32("unsupported instruction",inst,32'h00000000);
        expect1("unsupported decode",instr_valid,1'b0);
        expect1("unsupported regwrite",dbg_reg_we,1'b0);
        expect1("unsupported memwrite",dbg_mem_we,1'b0);
        @(posedge clk); #1;
        expect32("PC after unsupported inst",pc,32'd68);
        check_reg(5'd13,32'h12345678);

        // Redirect from PC=68 to PC=128 without executing source instruction.
        jump_without_execute(32'd68,32'd128);
        run_one(32'd128, dut.u_fetch.u_imem.mem[32]);
        check_reg(5'd20,32'h00000055);
        hold_pc(32'd132);
        check_reg(5'd20,32'h00000055);

        // Redirect to out-of-range PC; fetch and state writes must be blocked.
        jump_without_execute(32'd132,32'h00000400);
        @(negedge clk); step_en=1; redirect=0; #1;
        expect1("outside IMEM invalid address",fetch_addr_valid,1'b0);
        expect1("outside IMEM invalid instruction",instr_valid,1'b0);
        expect1("outside IMEM no regwrite",dbg_reg_we,1'b0);
        expect1("outside IMEM no memwrite",dbg_mem_we,1'b0);
        @(posedge clk); #1;
        check_reg(5'd20,32'h00000055);
        expect32("outside IMEM no memory corruption",dut.u_fetch.u_datapath.u_dmem.mem[0],32'h12345678);

        // Reset is synchronous and overrides simultaneous PC enable+redirect.
        @(negedge clk);
        step_en=1; redirect=1; redirect_pc=32'd64; rst=1;
        #1;
        expect32("sync reset not before edge",pc,32'h00000404);
        @(posedge clk); #1;
        expect32("reset PC priority",pc,32'h00000000);
        check_reg(5'd20,32'h00000000);
        check_reg(5'd1,32'h00000000);

        $display("============================================");
        $display("Total checks = %0d",checks);
        $display("Total errors = %0d",errors);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED");
        $finish;
    end
endmodule
