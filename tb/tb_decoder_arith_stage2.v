`timescale 1ns / 1ps

// Decoder V1.2 stage-2 regression: SLT / SLTU / SLTI and existing instructions.
// Vivado 2019.1, Verilog-2001. Simulation top: tb_decoder_arith_stage2.
// Each directed case checks the decoder's output control signals (not ALU data).
module tb_decoder_arith_stage2;
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

    // R3 format: opcode | (rk << 10) | (rj << 5) | rd.
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
                       branch_type === 3'd0 && wb_sel === 2'b00 &&
                       wb_sel_mem === 1'b0, case_name);
        end
    endtask

    // Signed I12 format: opcode | (si12 << 10) | (rj << 5) | rd.
    // ImmGen, not Decoder, performs the actual sign extension.
    task check_i12;
        input [31:0] opcode;
        input [3:0] expected_alu;
        input [4:0] rd, rj;
        input [11:0] si12;
        input [8*48-1:0] case_name;
        begin
            inst = opcode | ({20'd0,si12} << 10) |
                   ({27'd0,rj} << 5) | {27'd0,rd};
            #1;
            check_case(valid === 1'b1 &&
                       rs1_addr === rj && rs2_addr === 5'd0 && rd_addr === rd &&
                       rs1_used === 1'b1 && rs2_used === 1'b0 &&
                       alu_op === expected_alu && imm_sel === 3'd1 &&
                       alu_src_imm === 1'b1 && reg_write === 1'b1 &&
                       mem_read === 1'b0 && mem_write === 1'b0 &&
                       branch_type === 3'd0 && wb_sel === 2'b00 &&
                       wb_sel_mem === 1'b0, case_name);
        end
    endtask

    initial begin
        inst   = 32'd0;
        checks = 0;
        errors = 0;

        // New SLT: signed less-than, ALU_SLT = 4'h6.
        check_r3(32'h00120000, 4'h6,  3,  4,  5, "SLT normal regs");
        check_r3(32'h00120000, 4'h6, 31,  0, 31, "SLT boundary regs");
        check_r3(32'h00120000, 4'h6,  0,  7,  8, "SLT writes r0");
        check_r3(32'h00120000, 4'h6,  7,  7,  7, "SLT same regs");

        // New SLTU: unsigned less-than, ALU_SLTU = 4'h7.
        check_r3(32'h00128000, 4'h7,  5,  6,  7, "SLTU normal regs");
        check_r3(32'h00128000, 4'h7, 31, 31,  0, "SLTU boundary regs");
        check_r3(32'h00128000, 4'h7,  0,  0,  0, "SLTU all r0");
        check_r3(32'h00128000, 4'h7,  9,  9,  9, "SLTU same regs");

        // New SLTI: signed 12-bit immediate (imm_sel=1).
        check_i12(32'h02000000, 4'h6,  3,  4, 12'h000, "SLTI zero");
        check_i12(32'h02000000, 4'h6,  3,  4, 12'h001, "SLTI positive one");
        check_i12(32'h02000000, 4'h6,  3,  4, 12'hFFF, "SLTI negative one");
        check_i12(32'h02000000, 4'h6, 31,  0, 12'h800, "SLTI negative 2048");
        check_i12(32'h02000000, 4'h6,  1, 31, 12'h7FF, "SLTI positive 2047");
        check_i12(32'h02000000, 4'h6,  0,  0, 12'hAAA, "SLTI destination r0");
        check_i12(32'h02000000, 4'h6, 12,  5, 12'h001, "SLTI registers 12,5");
        check_i12(32'h02000000, 4'h6, 12,  5, 12'h0FF, "SLTI immediate 255");

        // Old instructions: regression checks.
        check_r3(32'h00100000, 4'h0, 3, 4, 5, "ADD.W regression");
        check_r3(32'h00110000, 4'h1, 3, 4, 5, "SUB.W regression");
        check_i12(32'h02800000, 4'h0, 7, 8, 12'hFFC, "ADDI.W regression");
        check_r3(32'h00148000, 4'h2, 2, 5, 8, "AND regression");

        inst = 32'h03800000 | (32'hABC << 10) | (32'd5 << 5) | 32'd6;
        #1;
        check_case(valid === 1'b1 && alu_op === 4'h3 &&
                   imm_sel === 3'd2 && alu_src_imm === 1'b1 &&
                   rs1_addr === 5'd5 && rs2_used === 1'b0 &&
                   rd_addr === 5'd6 && reg_write === 1'b1 &&
                   wb_sel === 2'd0, "ORI regression");

        inst = 32'h28800000 | (32'hFFC << 10) | (32'd4 << 5) | 32'd3;
        #1;
        check_case(valid === 1'b1 && imm_sel === 3'd1 &&
                   rs1_addr === 5'd4 && rd_addr === 5'd3 &&
                   mem_read === 1'b1 && mem_write === 1'b0 &&
                   reg_write === 1'b1 && wb_sel === 2'd1 &&
                   wb_sel_mem === 1'b1, "LD.W regression");

        inst = 32'h29800000 | (32'd8 << 10) | (32'd4 << 5) | 32'd3;
        #1;
        check_case(valid === 1'b1 && rs1_addr === 5'd4 &&
                   rs2_addr === 5'd3 && rs2_used === 1'b1 &&
                   mem_write === 1'b1 && reg_write === 1'b0,
                   "ST.W regression");

        inst = (32'h16 << 26) | (32'd4 << 10) | (32'd7 << 5) | 32'd8;
        #1;
        check_case(valid === 1'b1 && branch_type === 3'd1 &&
                   imm_sel === 3'd5 && rs1_addr === 5'd7 &&
                   rs2_addr === 5'd8 && reg_write === 1'b0,
                   "BEQ regression");

        inst = (32'h17 << 26) | (32'd4 << 10) | (32'd7 << 5) | 32'd8;
        #1;
        check_case(valid === 1'b1 && branch_type === 3'd2 &&
                   imm_sel === 3'd5 && rs1_addr === 5'd7 &&
                   rs2_addr === 5'd8 && reg_write === 1'b0,
                   "BNE regression");

        inst = (32'h15 << 26) | 32'h0000_0004;
        #1;
        check_case(valid === 1'b1 && branch_type === 3'd4 &&
                   imm_sel === 3'd6 && reg_write === 1'b1 &&
                   rd_addr === 5'd1 && wb_sel === 2'd2,
                   "BL regression");

        inst = (32'h13 << 26) | (32'hFFC << 10) | (32'd5 << 5) | 32'd8;
        #1;
        check_case(valid === 1'b1 && branch_type === 3'd5 &&
                   imm_sel === 3'd5 && rs1_addr === 5'd5 &&
                   rd_addr === 5'd8 && reg_write === 1'b1 &&
                   wb_sel === 2'd2, "JIRL regression");

        inst = 32'hFFFF_FFFF;
        #1;
        check_case(valid === 1'b0 && reg_write === 1'b0 &&
                   mem_write === 1'b0 && branch_type === 3'd0 &&
                   wb_sel === 2'd0, "Invalid opcode");

        $display("--------------------------------");
        $display("Total checks = %0d, errors = %0d", checks, errors);
        if (errors == 0)
            $display("ALL TESTS PASSED (%0d checks)", checks);
        else
            $display("TESTS FAILED (%0d errors)", errors);
        $finish;
    end
endmodule
