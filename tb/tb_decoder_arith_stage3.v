`timescale 1ns / 1ps

// Decoder V1.2 Stage-3: 27-instruction directed decode regression.
// Focus: SLL.W / SRL.W / SRA.W, plus all prior 24 instruction kinds.
// Vivado 2019.1, Verilog-2001. Simulation top: tb_decoder_arith_stage3.
// Tests Decoder control signals only; it does not verify ALU data results.
module tb_decoder_arith_stage3;
    reg  [31:0] inst;
    wire [4:0]  rs1_addr, rs2_addr, rd_addr;
    wire        rs1_used, rs2_used;
    wire [3:0]  alu_op;
    wire [2:0]  imm_sel, branch_type;
    wire        alu_src_imm, reg_write, mem_read, mem_write;
    wire        wb_sel_mem, valid;
    wire [1:0]  wb_sel;
    integer checks, errors;

    decoder uut (
        .inst(inst), .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .rd_addr(rd_addr), .rs1_used(rs1_used), .rs2_used(rs2_used),
        .alu_op(alu_op), .imm_sel(imm_sel), .alu_src_imm(alu_src_imm),
        .reg_write(reg_write), .mem_read(mem_read), .mem_write(mem_write),
        .wb_sel_mem(wb_sel_mem), .valid(valid),
        .branch_type(branch_type), .wb_sel(wb_sel)
    );

    task check_case;
        input passed;
        input [8*48-1:0] case_name;
        begin
            checks = checks + 1;
            if (passed !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL [%0d] %0s inst=%h", checks, case_name, inst);
                $display(" r1=%d r2=%d rd=%d used=%b%b alu=%h imm=%h imm_src=%b reg=%b mr=%b mw=%b branch=%h wb=%h alias=%b valid=%b",
                         rs1_addr, rs2_addr, rd_addr, rs1_used, rs2_used,
                         alu_op, imm_sel, alu_src_imm, reg_write,
                         mem_read, mem_write, branch_type, wb_sel, wb_sel_mem, valid);
            end else begin
                $display("PASS [%0d] %0s", checks, case_name);
            end
        end
    endtask

    // R3: opcode | (rk << 10) | (rj << 5) | rd.
    // Check every control output, including that register shifts use rk,
    // rather than the 5-bit immediate control used by SLLI/SRLI/SRAI.
    task check_r3;
        input [31:0] opcode;
        input [3:0] expected_alu;
        input [4:0] rd, rj, rk;
        input [8*48-1:0] case_name;
        begin
            inst = opcode | ({27'd0,rk} << 10) |
                   ({27'd0,rj} << 5) | {27'd0,rd};
            #1;
            check_case(valid === 1'b1 &&
                       rs1_addr === rj && rs2_addr === rk && rd_addr === rd &&
                       rs1_used === 1'b1 && rs2_used === 1'b1 &&
                       alu_op === expected_alu && imm_sel === 3'd0 &&
                       alu_src_imm === 1'b0 && reg_write === 1'b1 &&
                       mem_read === 1'b0 && mem_write === 1'b0 &&
                       branch_type === 3'd0 && wb_sel === 2'd0 &&
                       wb_sel_mem === 1'b0, case_name);
        end
    endtask

    // Immediate ALU: signed I12 (sel=1), unsigned I12 (sel=2), I5 shift (sel=3).
    task check_imm_alu;
        input [31:0] opcode;
        input [3:0] expected_alu;
        input [2:0] expected_sel;
        input [4:0] rd, rj;
        input [11:0] imm_bits;
        input [8*48-1:0] case_name;
        begin
            inst = opcode | ({20'd0,imm_bits} << 10) |
                   ({27'd0,rj} << 5) | {27'd0,rd};
            #1;
            check_case(valid === 1'b1 &&
                       rs1_addr === rj && rs2_addr === 5'd0 && rd_addr === rd &&
                       rs1_used === 1'b1 && rs2_used === 1'b0 &&
                       alu_op === expected_alu && imm_sel === expected_sel &&
                       alu_src_imm === 1'b1 && reg_write === 1'b1 &&
                       mem_read === 1'b0 && mem_write === 1'b0 &&
                       branch_type === 3'd0 && wb_sel === 2'd0 &&
                       wb_sel_mem === 1'b0, case_name);
        end
    endtask

    initial begin
        inst   = 32'd0;
        checks = 0;
        errors = 0;

        // 1-15: New register-shift instructions (five cases each).
        check_r3(32'h00170000, 4'h8,  3,  4,  5, "SLL.W normal registers");
        check_r3(32'h00170000, 4'h8,  7,  8,  0, "SLL.W rk is r0");
        check_r3(32'h00170000, 4'h8, 31, 30, 31, "SLL.W high registers");
        check_r3(32'h00170000, 4'h8,  0,  0,  1, "SLL.W destination r0");
        check_r3(32'h00170000, 4'h8, 15, 15, 15, "SLL.W same registers");

        check_r3(32'h00178000, 4'h9,  2,  6,  9, "SRL.W normal registers");
        check_r3(32'h00178000, 4'h9,  7,  8,  0, "SRL.W rk is r0");
        check_r3(32'h00178000, 4'h9, 31, 30, 31, "SRL.W high registers");
        check_r3(32'h00178000, 4'h9,  0,  0,  1, "SRL.W destination r0");
        check_r3(32'h00178000, 4'h9, 15, 15, 15, "SRL.W same registers");

        check_r3(32'h00180000, 4'hA,  3,  4,  5, "SRA.W normal registers");
        check_r3(32'h00180000, 4'hA,  7,  8,  0, "SRA.W rk is r0");
        check_r3(32'h00180000, 4'hA, 31, 30, 31, "SRA.W high registers");
        check_r3(32'h00180000, 4'hA,  0,  0,  1, "SRA.W destination r0");
        check_r3(32'h00180000, 4'hA, 15, 15, 15, "SRA.W same registers");

        // 16-21: Previously added six instructions.
        check_r3(32'h00100000, 4'h0, 3, 4, 5, "ADD.W regression");
        check_r3(32'h00110000, 4'h1, 3, 4, 5, "SUB.W regression");
        check_imm_alu(32'h02800000, 4'h0, 3'd1, 3, 4, 12'hFFF, "ADDI.W negative immediate");
        check_r3(32'h00120000, 4'h6, 3, 4, 5, "SLT regression");
        check_r3(32'h00128000, 4'h7, 3, 4, 5, "SLTU regression");
        check_imm_alu(32'h02000000, 4'h6, 3'd1, 3, 4, 12'h800, "SLTI negative immediate");

        // 22-34: All 13 original instruction kinds.
        check_r3(32'h00148000, 4'h2, 3, 4, 5, "AND regression");
        check_r3(32'h00150000, 4'h3, 3, 4, 5, "OR regression");
        check_r3(32'h00140000, 4'h5, 3, 4, 5, "NOR regression");
        check_r3(32'h00158000, 4'h4, 3, 4, 5, "XOR regression");
        check_imm_alu(32'h03400000, 4'h2, 3'd2, 3, 4, 12'hABC, "ANDI regression");
        check_imm_alu(32'h03800000, 4'h3, 3'd2, 3, 4, 12'hABC, "ORI regression");
        check_imm_alu(32'h03C00000, 4'h4, 3'd2, 3, 4, 12'hABC, "XORI regression");
        check_imm_alu(32'h00408000, 4'h8, 3'd3, 3, 4, 12'h01F, "SLLI.W regression");
        check_imm_alu(32'h00448000, 4'h9, 3'd3, 3, 4, 12'h000, "SRLI.W regression");
        check_imm_alu(32'h00488000, 4'hA, 3'd3, 3, 4, 12'h007, "SRAI.W regression");

        inst = 32'h14000000 | (32'hABCDE << 5) | 32'd6;
        #1;
        check_case(valid === 1'b1 && alu_op === 4'hB &&
                   rs1_used === 1'b0 && rs2_used === 1'b0 &&
                   rs1_addr === 5'd0 && rs2_addr === 5'd0 && rd_addr === 5'd6 &&
                   imm_sel === 3'd4 && alu_src_imm === 1'b1 &&
                   reg_write === 1'b1 && mem_read === 1'b0 && mem_write === 1'b0 &&
                   branch_type === 3'd0 && wb_sel === 2'd0 && wb_sel_mem === 1'b0,
                   "LU12I.W regression");

        inst = 32'h28800000 | (32'hFFF << 10) | (32'd4 << 5) | 32'd3;
        #1;
        check_case(valid === 1'b1 && alu_op === 4'h0 &&
                   rs1_used === 1'b1 && rs2_used === 1'b0 &&
                   rs1_addr === 5'd4 && rs2_addr === 5'd0 && rd_addr === 5'd3 &&
                   imm_sel === 3'd1 && alu_src_imm === 1'b1 &&
                   reg_write === 1'b1 && mem_read === 1'b1 && mem_write === 1'b0 &&
                   branch_type === 3'd0 && wb_sel === 2'd1 && wb_sel_mem === 1'b1,
                   "LD.W regression");

        inst = 32'h29800000 | (32'd8 << 10) | (32'd4 << 5) | 32'd3;
        #1;
        check_case(valid === 1'b1 && alu_op === 4'h0 &&
                   rs1_used === 1'b1 && rs2_used === 1'b1 &&
                   rs1_addr === 5'd4 && rs2_addr === 5'd3 && rd_addr === 5'd3 &&
                   imm_sel === 3'd1 && alu_src_imm === 1'b1 &&
                   reg_write === 1'b0 && mem_read === 1'b0 && mem_write === 1'b1 &&
                   branch_type === 3'd0 && wb_sel === 2'd0 && wb_sel_mem === 1'b0,
                   "ST.W regression");

        // 35-39: Five branch instructions from the 18-instruction baseline.
        inst = (32'h16 << 26) | (32'd4 << 10) | (32'd7 << 5) | 32'd8;
        #1;
        check_case(valid === 1'b1 && branch_type === 3'd1 &&
                   imm_sel === 3'd5 && rs1_addr === 5'd7 && rs2_addr === 5'd8 &&
                   rs1_used === 1'b1 && rs2_used === 1'b1 &&
                   reg_write === 1'b0 && mem_write === 1'b0 && wb_sel === 2'd0,
                   "BEQ regression");

        inst = (32'h17 << 26) | (32'd4 << 10) | (32'd7 << 5) | 32'd8;
        #1;
        check_case(valid === 1'b1 && branch_type === 3'd2 &&
                   imm_sel === 3'd5 && rs1_addr === 5'd7 && rs2_addr === 5'd8 &&
                   rs1_used === 1'b1 && rs2_used === 1'b1 &&
                   reg_write === 1'b0 && mem_write === 1'b0 && wb_sel === 2'd0,
                   "BNE regression");

        inst = (32'h14 << 26) | 32'h0000_0004;
        #1;
        check_case(valid === 1'b1 && branch_type === 3'd3 &&
                   imm_sel === 3'd6 && rs1_used === 1'b0 && rs2_used === 1'b0 &&
                   reg_write === 1'b0 && mem_write === 1'b0 && wb_sel === 2'd0,
                   "B regression");

        inst = (32'h15 << 26) | 32'h0000_0004;
        #1;
        check_case(valid === 1'b1 && branch_type === 3'd4 &&
                   imm_sel === 3'd6 && reg_write === 1'b1 &&
                   rd_addr === 5'd1 && wb_sel === 2'd2 && wb_sel_mem === 1'b0,
                   "BL regression");

        inst = (32'h13 << 26) | (32'hFFC << 10) | (32'd5 << 5) | 32'd8;
        #1;
        check_case(valid === 1'b1 && branch_type === 3'd5 &&
                   imm_sel === 3'd5 && rs1_addr === 5'd5 && rs1_used === 1'b1 &&
                   rs2_used === 1'b0 && rd_addr === 5'd8 &&
                   reg_write === 1'b1 && wb_sel === 2'd2 && wb_sel_mem === 1'b0,
                   "JIRL regression");

        // 40: Unrecognized opcode must not write architectural state.
        inst = 32'hFFFF_FFFF;
        #1;
        check_case(valid === 1'b0 && rs1_used === 1'b0 && rs2_used === 1'b0 &&
                   rs1_addr === 5'd0 && rs2_addr === 5'd0 && rd_addr === 5'd0 &&
                   reg_write === 1'b0 && mem_read === 1'b0 && mem_write === 1'b0 &&
                   branch_type === 3'd0 && wb_sel === 2'd0 && wb_sel_mem === 1'b0,
                   "Invalid instruction");

        $display("--------------------------------");
        $display("Total checks = %0d, errors = %0d", checks, errors);
        if (checks != 40) begin
            $display("TESTBENCH ERROR: expected 40 cases but got %0d", checks);
            errors = errors + 1;
        end
        if (errors == 0)
            $display("ALL TESTS PASSED (%0d checks)", checks);
        else
            $display("TESTS FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
