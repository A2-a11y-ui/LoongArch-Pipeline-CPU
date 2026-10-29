`timescale 1ns / 1ps
// V0.4 PRE-INTEGRATION: official decoder + imm_gen + branch_unit.
// Verilog-2001; does NOT instantiate a V0.4 pipeline CPU.
module tb_branch_decode_redirect_v04;
    reg [31:0] inst, pc, rs1_data, rs2_data;
    wire [4:0] rs1_addr, rs2_addr, rd_addr;
    wire rs1_used, rs2_used, alu_src_imm, reg_write, mem_read, mem_write;
    wire wb_sel_mem, valid;
    wire [3:0] alu_op;
    wire [2:0] imm_sel, branch_type;
    wire [1:0] wb_sel;
    wire [31:0] imm;
    wire redirect;
    wire [31:0] target_pc;
    integer cases, checks, errors;

    decoder u_decoder (
        .inst(inst), .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .rd_addr(rd_addr), .rs1_used(rs1_used), .rs2_used(rs2_used),
        .alu_op(alu_op), .imm_sel(imm_sel), .alu_src_imm(alu_src_imm),
        .reg_write(reg_write), .mem_read(mem_read), .mem_write(mem_write),
        .wb_sel_mem(wb_sel_mem), .valid(valid),
        .branch_type(branch_type), .wb_sel(wb_sel)
    );
    imm_gen u_imm (.inst(inst), .imm_sel(imm_sel), .imm(imm));
    branch_unit u_branch (
        .branch_type(valid ? branch_type : 3'd0),
        .pc(pc), .rs1_data(rs1_data), .rs2_data(rs2_data),
        .branch_imm(imm), .redirect(redirect), .target_pc(target_pc)
    );

    function [31:0] enc16;
        input [31:0] opcode;
        input [4:0] rd, rj;
        input integer offset_bytes;
        reg [15:0] off;
        begin
            off = offset_bytes >>> 2;
            enc16 = opcode | ({16'd0,off} << 10) |
                    ({27'd0,rj} << 5) | {27'd0,rd};
        end
    endfunction

    function [31:0] enc26;
        input [31:0] opcode;
        input integer offset_bytes;
        reg [25:0] off;
        begin
            off = offset_bytes >>> 2;
            enc26 = opcode | ({16'd0,off[15:0]} << 10) |
                    {22'd0,off[25:16]};
        end
    endfunction

    task check;
        input [8*60-1:0] name;
        input [31:0] observed, expected;
        begin
            checks = checks + 1;
            if (observed !== expected) begin
                errors = errors + 1;
                $display("FAIL case=%0d %0s got=%08h expected=%08h",
                         cases, name, observed, expected);
            end
        end
    endtask

    // 12 independently evaluated outputs per program case.
    task run_case;
        input [8*60-1:0] name;
        input [31:0] instruction, at_pc, a, b, expected_imm, expected_target;
        input expected_valid;
        input [2:0] expected_type;
        input expected_redirect;
        input [4:0] expected_rs1, expected_rs2, expected_rd;
        input expected_rs1_used, expected_rs2_used, expected_reg_write;
        input [1:0] expected_wb_sel;
        begin
            inst = instruction;
            pc = at_pc;
            rs1_data = a;
            rs2_data = b;
            #1;
            cases = cases + 1;
            check("decode valid", {31'd0,valid}, {31'd0,expected_valid});
            check("branch type", {29'd0,branch_type}, {29'd0,expected_type});
            check("branch immediate", imm, expected_imm);
            check("branch redirect", {31'd0,redirect}, {31'd0,expected_redirect});
            check("target pc", target_pc, expected_target);
            check("rs1 addr", {27'd0,rs1_addr}, {27'd0,expected_rs1});
            check("rs2 addr", {27'd0,rs2_addr}, {27'd0,expected_rs2});
            check("rd addr", {27'd0,rd_addr}, {27'd0,expected_rd});
            check("rs1 used", {31'd0,rs1_used}, {31'd0,expected_rs1_used});
            check("rs2 used", {31'd0,rs2_used}, {31'd0,expected_rs2_used});
            check("link write", {31'd0,reg_write}, {31'd0,expected_reg_write});
            check("wb select", {30'd0,wb_sel}, {30'd0,expected_wb_sel});
            $display("CASE %0d %0s checked", cases, name);
        end
    endtask

    initial begin
        cases=0; checks=0; errors=0;
        inst=0; pc=0; rs1_data=0; rs2_data=0;
        // B16 format: BEQ/BNE use rj and the rd bitfield as their source operands.
        run_case("BEQ equal forward",enc16(32'h58000000,7,4,12),32'h1000,5,5,12,32'h100c,1,1,1,4,7,0,1,1,0,0);
        run_case("BEQ not equal",enc16(32'h58000000,7,4,12),32'h1000,5,6,12,0,1,1,0,4,7,0,1,1,0,0);
        run_case("BEQ negative",enc16(32'h58000000,2,1,-8),32'h1000,9,9,32'hfffffff8,32'h0ff8,1,1,1,1,2,0,1,1,0,0);
        run_case("BEQ zero values",enc16(32'h58000000,2,1,0),32'h1000,0,0,0,32'h1000,1,1,1,1,2,0,1,1,0,0);
        run_case("BNE different",enc16(32'h5c000000,9,8,20),32'h1000,3,4,20,32'h1014,1,2,1,8,9,0,1,1,0,0);
        run_case("BNE equal",enc16(32'h5c000000,9,8,20),32'h1000,4,4,20,0,1,2,0,8,9,0,1,1,0,0);
        run_case("BNE negative",enc16(32'h5c000000,6,3,-12),32'h1000,1,2,32'hfffffff4,32'h0ff4,1,2,1,3,6,0,1,1,0,0);
        run_case("BNE zero equality",enc16(32'h5c000000,0,0,0),32'h1000,0,0,0,0,1,2,0,0,0,0,1,1,0,0);
        // B26 immediate is split across instruction bit ranges [25:10],[9:0].
        run_case("B forward",enc26(32'h50000000,12),32'h1000,0,0,12,32'h100c,1,3,1,0,0,0,0,0,0,0);
        run_case("B negative",enc26(32'h50000000,-16),32'h1000,0,0,32'hfffffff0,32'h0ff0,1,3,1,0,0,0,0,0,0,0);
        run_case("B zero offset",enc26(32'h50000000,0),32'h1000,0,0,0,32'h1000,1,3,1,0,0,0,0,0,0,0);
        run_case("B wraps address",enc26(32'h50000000,8),32'hfffffffc,0,0,8,4,1,3,1,0,0,0,0,0,0,0);
        run_case("BL forward link r1",enc26(32'h54000000,64),32'h1000,0,0,64,32'h1040,1,4,1,0,0,1,0,0,1,2);
        run_case("BL back link r1",enc26(32'h54000000,-16),32'h1000,0,0,32'hfffffff0,32'h0ff0,1,4,1,0,0,1,0,0,1,2);
        // JIRL target is rs1_data + offset, not PC + offset.
        run_case("JIRL forward",enc16(32'h4c000000,15,10,4),32'h1000,32'h2000,0,4,32'h2004,1,5,1,10,0,15,1,0,1,2);
        run_case("JIRL negative",enc16(32'h4c000000,8,3,-8),32'h1000,32'h2000,0,32'hfffffff8,32'h1ff8,1,5,1,3,0,8,1,0,1,2);
        run_case("JIRL link to zero",enc16(32'h4c000000,0,3,0),32'h1000,32'h2000,0,0,32'h2000,1,5,1,3,0,0,1,0,1,2);
        run_case("JIRL 32b wrap",enc16(32'h4c000000,1,3,-8),32'h1000,4,0,32'hfffffff8,32'hfffffffc,1,5,1,3,0,1,1,0,1,2);
        run_case("JIRL zero immediate",enc16(32'h4c000000,1,4,0),32'h2000,32'h4000,0,0,32'h4000,1,5,1,4,0,1,1,0,1,2);
        // Invalid is not branch; ordinary ADDI is valid but not a branch.
        run_case("ILLEGAL ignored",32'hffffffff,32'h1000,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
        run_case("ADDI not branch",32'h02801425,32'h1000,0,0,32'd5,0,1,0,0,1,0,5,1,0,1,0);
        run_case("BEQ register fields",enc16(32'h58000000,31,2,8),32'h1040,20,20,8,32'h1048,1,1,1,2,31,0,1,1,0,0);
        run_case("BL larger off26",enc26(32'h54000000,32'h00040000),32'h1000,0,0,32'h00040000,32'h00041000,1,4,1,0,0,1,0,0,1,2);
        $display("-----------------------------------------");
        $display("V0.4 BRANCH DECODE + IMM + DECISION REGRESSION");
        $display("cases=%0d checks=%0d errors=%0d",cases,checks,errors);
        if (cases == 23 && checks == 276 && errors == 0)
            $display("ALL TESTS PASSED");
        else $display("TESTS FAILED");
        $finish;
    end
endmodule
