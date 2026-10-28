`timescale 1ns / 1ps
// Self-checking PROGRAM-LEVEL simulation, without waiting for pc_reg.v.
// Requires official regfile, imem, datapath_stage1, decoder, imm_gen, alu, dmem.
module tb_fetch_datapath_stage2;
    reg clk;
    reg rst;
    reg exec_en;
    reg [31:0] pc;

    wire [31:0] inst;
    wire fetch_addr_valid;
    wire instr_valid;
    wire dbg_reg_we;
    wire dbg_mem_we;
    wire [31:0] dbg_wb_data;
    wire [31:0] dbg_alu_result;
    wire [31:0] dbg_rs1_data;
    wire [31:0] dbg_rs2_data;

    integer checks;
    integer errors;

    fetch_datapath_stage2 dut (
        .clk(clk), .rst(rst), .exec_en(exec_en), .pc(pc),
        .inst(inst), .fetch_addr_valid(fetch_addr_valid),
        .instr_valid(instr_valid),
        .dbg_reg_we(dbg_reg_we), .dbg_mem_we(dbg_mem_we),
        .dbg_wb_data(dbg_wb_data), .dbg_alu_result(dbg_alu_result),
        .dbg_rs1_data(dbg_rs1_data), .dbg_rs2_data(dbg_rs2_data)
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

    // Drive each new PC at the falling edge. Allow a full cycle to commit.
    task step;
        input integer slot;
        input [31:0] expected_inst;
        begin
            @(negedge clk);
            pc = slot * 4;
            exec_en = 1'b1;
            #1;
            expect32("instruction", inst, expected_inst);
            expect1("fetch address valid", fetch_addr_valid, 1'b1);
            expect1("instruction decoded", instr_valid, 1'b1);
            @(posedge clk);
            #1; // allow synchronous register / dmem write to settle
        end
    endtask

    // Program check relies on the agreed team-A regfile naming regs[0:31].
    // This is testbench-only hierarchy access, never used in synthesizable RTL.
    task check_reg;
        input [4:0] reg_no;
        input [31:0] expected;
        begin
            expect32("regfile value",dut.u_datapath.u_regfile.regs[reg_no],expected);
        end
    endtask

    initial begin
        clk=0;
        rst=1;
        exec_en=0;
        pc=0;
        checks=0;
        errors=0;
        #1;

        // Initialize ROM with a real 16-instruction LoongArch program.
        // Hierarchical ROM loading is TESTBENCH ONLY; not a CPU write port.
        dut.u_imem.mem[0]  = enc_u20(5'd1,20'h12345);            // r1=12345000
        dut.u_imem.mem[1]  = enc_ri12(32'h03800000,5'd1,5'd1,12'h678); // r1=12345678
        dut.u_imem.mem[2]  = enc_u20(5'd2,20'h80000);            // r2=80000000
        dut.u_imem.mem[3]  = enc_3r(32'h00488000,5'd3,5'd2,5'd31); // SRAI r3=r2>>31
        dut.u_imem.mem[4]  = enc_3r(32'h00448000,5'd4,5'd2,5'd31); // SRLI r4=1
        dut.u_imem.mem[5]  = enc_3r(32'h00408000,5'd5,5'd4,5'd31); // SLLI r5=80000000
        dut.u_imem.mem[6]  = enc_3r(32'h00148000,5'd6,5'd1,5'd3);  // AND r6=r1&r3
        dut.u_imem.mem[7]  = enc_3r(32'h00150000,5'd7,5'd4,5'd5);  // OR r7=r4|r5
        dut.u_imem.mem[8]  = enc_3r(32'h00158000,5'd8,5'd1,5'd6);  // XOR r8=r1^r6
        dut.u_imem.mem[9]  = enc_3r(32'h00140000,5'd9,5'd8,5'd0);  // NOR r9=~(r8|r0)
        dut.u_imem.mem[10] = enc_ri12(32'h03400000,5'd10,5'd1,12'h0FF); // ANDI r10=78
        dut.u_imem.mem[11] = enc_ri12(32'h03C00000,5'd11,5'd10,12'h001); // XORI r11=79
        dut.u_imem.mem[12] = enc_ri12(32'h29800000,5'd1,5'd0,12'h000); // ST.W r1,[r0+0]
        dut.u_imem.mem[13] = enc_ri12(32'h28800000,5'd12,5'd0,12'h000); // LD.W r12,[r0+0]
        dut.u_imem.mem[14] = enc_ri12(32'h03800000,5'd13,5'd12,12'h000); // ORI r13=r12|0
        dut.u_imem.mem[15] = enc_ri12(32'h03800000,5'd0,5'd1,12'h333); // ORI r0 (ignored)
        dut.u_imem.mem[16] = 32'h00000000;                 // unsupported

        @(posedge clk);
        #1;
        @(posedge clk);
        #1;
        rst=0;
        expect32("reset r1",dut.u_datapath.u_regfile.regs[1],32'h00000000);
        expect32("reset r12",dut.u_datapath.u_regfile.regs[12],32'h00000000);

        step(0, dut.u_imem.mem[0]);   check_reg(5'd1,32'h12345000);
        step(1, dut.u_imem.mem[1]);   check_reg(5'd1,32'h12345678);
        step(2, dut.u_imem.mem[2]);   check_reg(5'd2,32'h80000000);
        step(3, dut.u_imem.mem[3]);   check_reg(5'd3,32'hFFFFFFFF);
        step(4, dut.u_imem.mem[4]);   check_reg(5'd4,32'h00000001);
        step(5, dut.u_imem.mem[5]);   check_reg(5'd5,32'h80000000);
        step(6, dut.u_imem.mem[6]);   check_reg(5'd6,32'h12345678);
        step(7, dut.u_imem.mem[7]);   check_reg(5'd7,32'h80000001);
        step(8, dut.u_imem.mem[8]);   check_reg(5'd8,32'h00000000);
        step(9, dut.u_imem.mem[9]);   check_reg(5'd9,32'hFFFFFFFF);
        step(10,dut.u_imem.mem[10]);  check_reg(5'd10,32'h00000078);
        step(11,dut.u_imem.mem[11]);  check_reg(5'd11,32'h00000079);
        step(12,dut.u_imem.mem[12]);
        expect32("stored dmem word",dut.u_datapath.u_dmem.mem[0],32'h12345678);
        step(13,dut.u_imem.mem[13]);  check_reg(5'd12,32'h12345678);
        step(14,dut.u_imem.mem[14]);  check_reg(5'd13,32'h12345678);
        step(15,dut.u_imem.mem[15]);
        expect32("r0 stays zero",dut.u_datapath.u_regfile.regs[0],32'h00000000);

        // Unsupported instruction: no architectural side effects.
        @(negedge clk);
        pc=32'd64; exec_en=1'b1; #1;
        expect32("unsupported inst", inst, 32'h00000000);
        expect1("unsupported decode",instr_valid,1'b0);
        expect1("unsupported regwrite",dbg_reg_we,1'b0);
        expect1("unsupported memwrite",dbg_mem_we,1'b0);
        @(posedge clk); #1;
        check_reg(5'd13,32'h12345678);
        expect32("dmem not overwritten",dut.u_datapath.u_dmem.mem[0],32'h12345678);

        // Fetch alignment / range guards.
        @(negedge clk); pc=32'd3; exec_en=1'b1; #1;
        expect1("misaligned fetch",fetch_addr_valid,1'b0);
        expect1("misaligned instr invalid",instr_valid,1'b0);
        expect1("misaligned regwrite",dbg_reg_we,1'b0);
        expect1("misaligned memwrite",dbg_mem_we,1'b0);
        @(posedge clk); #1;
        check_reg(5'd13,32'h12345678);

        @(negedge clk); pc=32'h00000400; exec_en=1'b1; #1;
        expect1("out of range fetch",fetch_addr_valid,1'b0);
        expect1("out of range instr invalid",instr_valid,1'b0);
        expect1("out of range regwrite",dbg_reg_we,1'b0);
        expect1("out of range memwrite",dbg_mem_we,1'b0);
        @(posedge clk); #1;
        check_reg(5'd13,32'h12345678);

        // exec_en must prevent state updates even when instruction is valid.
        @(negedge clk); pc=32'd4; exec_en=1'b0; #1;
        expect1("disabled regwrite",dbg_reg_we,1'b0);
        expect1("disabled memwrite",dbg_mem_we,1'b0);
        @(posedge clk); #1;
        check_reg(5'd1,32'h12345678);

        $display("=============================================");
        $display("Total checks = %0d",checks);
        $display("Total errors = %0d",errors);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end
endmodule
