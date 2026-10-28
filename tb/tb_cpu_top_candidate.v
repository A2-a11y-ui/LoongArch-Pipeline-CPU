`timescale 1ns / 1ps
// Stage 5 self-checking full-chain testbench.
// Simulates program ROM contents by hierarchical writes to imem.mem[] ONLY
// inside the testbench. No third-party assembler or firmware is needed.
module tb_cpu_top_candidate;
    reg clk, rst, step_en;
    wire [31:0] pc, inst;
    wire fetch_addr_valid, instr_valid;
    wire [2:0] dbg_branch_type;
    wire [31:0] dbg_branch_imm, dbg_target_pc, dbg_next_pc;
    wire dbg_redirect, dbg_reg_we, dbg_mem_we;
    wire [4:0] dbg_waddr;
    wire [31:0] dbg_wb_data, dbg_rs1_data, dbg_rs2_data;
    integer tests, errors, steps;

    cpu_top_candidate dut (
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

    // Assemble real LoongArch machine instructions from opcode and fields.
    function [31:0] op_2ri12;
        input [31:0] op;
        input [4:0] rd, rj;
        input [11:0] u12;
        begin
            op_2ri12 = op | ({20'b0,u12} << 10) |
                        ({27'b0,rj} << 5) | {27'b0,rd};
        end
    endfunction
    function [31:0] op_3r;
        input [31:0] op;
        input [4:0] rd, rj, rk;
        begin
            op_3r = op | ({27'b0,rk} << 10) |
                    ({27'b0,rj} << 5) | {27'b0,rd};
        end
    endfunction
    function [31:0] op_b16;
        input [31:0] op;
        input [4:0] rj, rd;
        input integer byte_off;
        reg [15:0] b16;
        begin
            b16 = byte_off >>> 2;
            op_b16 = op | ({16'b0,b16} << 10) |
                     ({27'b0,rj} << 5) | {27'b0,rd};
        end
    endfunction
    function [31:0] op_b26;
        input [31:0] op;
        input integer byte_off;
        reg [25:0] b26;
        begin
            b26 = byte_off >>> 2;
            op_b26 = op | ({16'b0,b26[15:0]} << 10) |
                     {22'b0,b26[25:16]};
        end
    endfunction

    // One check per property, with meaningful diagnostics.
    task expect32;
        input [8*28-1:0] label;
        input [31:0] observed, expected;
        begin
            tests = tests + 1;
            if (observed !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s: got=%08h expected=%08h",label,observed,expected);
            end
        end
    endtask

    // One instruction commit, plus a following full stall clock cycle.
    task run_one;
        input [8*28-1:0] label;
        input [31:0] from_pc, expected_inst, to_pc;
        input [2:0]  expected_bt;
        input        expected_redirect;
        input        expected_rf_we, expected_dm_we, expected_valid;
        input [31:0] expected_branch_imm;
        reg [31:0] captured_pc;
        begin
            @(negedge clk);
            step_en = 1'b1;
            #1;
            expect32("current pc",pc,from_pc);
            expect32("machine instruction",inst,expected_inst);
            expect32("instruction valid",{31'd0,instr_valid},{31'd0,expected_valid});
            expect32("branch type",{29'd0,dbg_branch_type},{29'd0,expected_bt});
            expect32("branch imm",dbg_branch_imm,expected_branch_imm);
            expect32("redirect",{31'd0,dbg_redirect},{31'd0,expected_redirect});
            expect32("regfile write enable",{31'd0,dbg_reg_we},{31'd0,expected_rf_we});
            expect32("memory write enable",{31'd0,dbg_mem_we},{31'd0,expected_dm_we});
            expect32("next PC",dbg_next_pc,to_pc);
            if (expected_redirect)
                expect32("branch target",dbg_target_pc,to_pc);

            @(posedge clk); #1;
            expect32("committed PC",pc,to_pc);
            steps = steps + 1;
            $display("PASS step %0d %0s %08h -> %08h",steps,label,from_pc,to_pc);

            @(negedge clk);
            step_en = 1'b0;
            #1;
            expect32("stall no RF write",{31'd0,dbg_reg_we},32'd0);
            expect32("stall no memory write",{31'd0,dbg_mem_we},32'd0);
            captured_pc = pc;
            @(posedge clk); #1;
            expect32("stall retains PC",pc,captured_pc);
        end
    endtask

    // Team A's regfile.v names its internal array "regs". These probes
    // exist ONLY in the testbench, not synthesizable logic.
    task check_reg;
        input [4:0] r;
        input [31:0] expected;
        begin
            expect32("register content",dut.u_regfile.regs[r],expected);
            $display("  PROBE r%0d=%08h",r,dut.u_regfile.regs[r]);
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        step_en = 0;
        tests = 0;
        errors = 0;
        steps = 0;

        // imem initial block zeroes the ROM at t=0.
        #1;
        dut.u_imem.mem[ 0] = op_2ri12(32'h03800000,10,0,12'h080); // ORI r10,r0,128
        dut.u_imem.mem[ 1] = op_2ri12(32'h03800000, 2,0,12'h033); // ORI r2,r0,51
        dut.u_imem.mem[ 2] = op_2ri12(32'h03800000, 3,0,12'h033); // ORI r3,r0,51
        dut.u_imem.mem[ 3] = op_b16(32'h58000000,2,3,12);        // BEQ taken 0x0c->0x18
        dut.u_imem.mem[ 4] = op_2ri12(32'h03800000,4,0,12'h111); // SKIPPED
        dut.u_imem.mem[ 5] = op_2ri12(32'h29800000,2,0,12'h000); // SKIPPED ST.W
        dut.u_imem.mem[ 6] = op_b16(32'h5C000000,2,3,8);         // BNE not taken
        dut.u_imem.mem[ 7] = op_2ri12(32'h03800000,5,0,12'h05A); // ORI r5,r0,90
        dut.u_imem.mem[ 8] = op_b16(32'h5C000000,2,5,12);        // BNE taken 0x20->0x2c
        dut.u_imem.mem[ 9] = op_2ri12(32'h03800000,6,0,12'h666); // SKIPPED
        dut.u_imem.mem[10] = op_2ri12(32'h29800000,5,0,12'h000); // SKIPPED ST.W
        dut.u_imem.mem[11] = op_b26(32'h54000000,16);             // BL 0x2c->0x3c; r1=0x30
        dut.u_imem.mem[12] = op_2ri12(32'h03800000,7,0,12'h777); // SKIPPED
        dut.u_imem.mem[15] = op_b16(32'h4C000000,10,8,4);        // JIRL 0x3c->0x84;r8=0x40
        dut.u_imem.mem[16] = op_2ri12(32'h03800000,7,0,12'h777); // SKIPPED
        dut.u_imem.mem[31] = op_b26(32'h50000000,32);             // B 0x7c->0x9c
        dut.u_imem.mem[33] = op_2ri12(32'h29800000,8,0,12'h000); // ST.W r8,0(r0)
        dut.u_imem.mem[34] = op_2ri12(32'h28800000,9,0,12'h000); // LD.W r9,0(r0)
        dut.u_imem.mem[35] = op_3r(32'h00148000,11,8,9);         // AND r11,r8,r9
        dut.u_imem.mem[36] = op_b26(32'h50000000,8);              // B 0x90->0x98
        dut.u_imem.mem[37] = op_2ri12(32'h03800000,7,0,12'h777); // SKIPPED
        dut.u_imem.mem[38] = op_b26(32'h50000000,-8);             // B 0x98->0x90
        dut.u_imem.mem[39] = op_b16(32'h5C000000,2,3,8);         // BNE not taken
        dut.u_imem.mem[40] = op_b16(32'h58000000,2,3,-8);        // BEQ neg: 0xa0->0x98
        dut.u_imem.mem[41] = 32'hFFFFFFFF;                        // invalid instruction
        dut.u_imem.mem[42] = op_2ri12(32'h03800000,0,0,12'hFFF); // r0 write ignored
        dut.u_imem.mem[43] = op_b26(32'h50000000,1024);          // out-of-range jump

        @(posedge clk); #1;
        expect32("synchronous PC reset",pc,32'h00000000);
        check_reg(5'd1,32'd0);
        rst = 0;

        run_one("ORI base",32'h00,op_2ri12(32'h03800000,10,0,12'h080),32'h04,0,0,1,0,1,0);
        run_one("ORI r2",32'h04,op_2ri12(32'h03800000,2,0,12'h033),32'h08,0,0,1,0,1,0);
        run_one("ORI r3",32'h08,op_2ri12(32'h03800000,3,0,12'h033),32'h0c,0,0,1,0,1,0);
        run_one("BEQ taken",32'h0c,op_b16(32'h58000000,2,3,12),32'h18,1,1,0,0,1,12);
        check_reg(5'd4,32'd0);
        run_one("BNE not taken",32'h18,op_b16(32'h5C000000,2,3,8),32'h1c,2,0,0,0,1,8);
        run_one("ORI r5",32'h1c,op_2ri12(32'h03800000,5,0,12'h05A),32'h20,0,0,1,0,1,0);
        run_one("BNE taken",32'h20,op_b16(32'h5C000000,2,5,12),32'h2c,2,1,0,0,1,12);
        check_reg(5'd6,32'd0);
        run_one("BL link",32'h2c,op_b26(32'h54000000,16),32'h3c,4,1,1,0,1,16);
        check_reg(5'd1,32'h00000030);
        run_one("JIRL link +4",32'h3c,op_b16(32'h4C000000,10,8,4),32'h84,5,1,1,0,1,4);
        check_reg(5'd8,32'h00000040);
        check_reg(5'd7,32'd0);
        run_one("ST.W r8",32'h84,op_2ri12(32'h29800000,8,0,0),32'h88,0,0,0,1,1,0);
        expect32("dmem[0] after ST.W",dut.u_dmem.mem[0],32'h00000040);
        run_one("LD.W r9",32'h88,op_2ri12(32'h28800000,9,0,0),32'h8c,0,0,1,0,1,0);
        check_reg(5'd9,32'h00000040);
        run_one("AND r11",32'h8c,op_3r(32'h00148000,11,8,9),32'h90,0,0,1,0,1,0);
        check_reg(5'd11,32'h00000040);
        run_one("B forward",32'h90,op_b26(32'h50000000,8),32'h98,3,1,0,0,1,8);
        run_one("B negative",32'h98,op_b26(32'h50000000,-8),32'h90,3,1,0,0,1,32'hFFFFFFF8);

        // Instruction patch is TESTBENCH-ONLY. Test JIRL negative offset.
        dut.u_imem.mem[36] = op_b16(32'h4C000000,10,12,-4);
        run_one("JIRL negative",32'h90,op_b16(32'h4C000000,10,12,-4),32'h7c,5,1,1,0,1,32'hFFFFFFFC);
        check_reg(5'd12,32'h00000094);
        run_one("B to 0x9c",32'h7c,op_b26(32'h50000000,32),32'h9c,3,1,0,0,1,32);
        run_one("BNE false 2",32'h9c,op_b16(32'h5C000000,2,3,8),32'ha0,2,0,0,0,1,8);
        run_one("BEQ negative",32'ha0,op_b16(32'h58000000,2,3,-8),32'h98,1,1,0,0,1,32'hFFFFFFF8);

        // Negative BNE, both operands different.
        dut.u_imem.mem[38] = op_b16(32'h5C000000,2,5,-20);
        run_one("BNE negative",32'h98,op_b16(32'h5C000000,2,5,-20),32'h84,2,1,0,0,1,32'hFFFFFFEC);
        // Revisit the memory/data path, then branch to invalid instruction.
        run_one("ST.W again",32'h84,op_2ri12(32'h29800000,8,0,0),32'h88,0,0,0,1,1,0);
        run_one("LD.W again",32'h88,op_2ri12(32'h28800000,9,0,0),32'h8c,0,0,1,0,1,0);
        run_one("AND again",32'h8c,op_3r(32'h00148000,11,8,9),32'h90,0,0,1,0,1,0);
        run_one("JIRL neg again",32'h90,op_b16(32'h4C000000,10,12,-4),32'h7c,5,1,1,0,1,32'hFFFFFFFC);
        dut.u_imem.mem[31] = op_b26(32'h50000000,40); // 0x7c -> 0xa4
        run_one("B to invalid",32'h7c,op_b26(32'h50000000,40),32'ha4,3,1,0,0,1,40);
        run_one("unsupported opcode",32'ha4,32'hFFFFFFFF,32'ha8,0,0,0,0,0,0);
        run_one("r0 write protected",32'ha8,op_2ri12(32'h03800000,0,0,12'hFFF),32'hac,0,0,0,0,1,0);
        check_reg(5'd0,32'd0);
        run_one("B beyond IMEM",32'hac,op_b26(32'h50000000,1024),32'h4ac,3,1,0,0,1,1024);
        run_one("invalid fetch",32'h4ac,32'd0,32'h4b0,0,0,0,0,0,0);
        check_reg(5'd1,32'h00000030);
        check_reg(5'd8,32'h00000040);
        check_reg(5'd9,32'h00000040);
        check_reg(5'd11,32'h00000040);
        check_reg(5'd12,32'h00000094); // value overwritten by second JIRL? PC 0x90 stays PC+4 = 0x94
        expect32("dmem preserved",dut.u_dmem.mem[0],32'h00000040);

        // Reset has priority over step and over the branch signals.
        @(negedge clk);
        rst = 1;
        step_en = 1;
        @(posedge clk); #1;
        expect32("PC reset priority",pc,32'd0);
        check_reg(5'd1,32'd0);

        $display("========================================");
        $display("Committed instructions = %0d",steps);
        $display("Total checks = %0d",tests);
        $display("Total errors = %0d",errors);
        if (errors == 0) $display("ALL TESTS PASSED");
        else $display("TEST FAILED");
        $finish;
    end
endmodule
