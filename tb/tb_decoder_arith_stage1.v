`timescale 1ns / 1ps

// Decoder V1.2 stage-1 test: ADD.W, SUB.W, ADDI.W + legacy smoke checks.
// Vivado 2019.1 / Verilog-2001. Simulation top: tb_decoder_arith_stage1.
module tb_decoder_arith_stage1;

    reg [31:0] inst;
    wire [4:0] rs1_addr, rs2_addr, rd_addr;
    wire rs1_used, rs2_used;
    wire [3:0] alu_op;
    wire [2:0] imm_sel, branch_type;
    wire alu_src_imm, reg_write, mem_read, mem_write;
    wire wb_sel_mem, valid;
    wire [1:0] wb_sel;
    integer checks, errors;

    decoder uut (
        .inst(inst),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .rd_addr(rd_addr),
        .rs1_used(rs1_used), .rs2_used(rs2_used),
        .alu_op(alu_op), .imm_sel(imm_sel),
        .alu_src_imm(alu_src_imm), .reg_write(reg_write),
        .mem_read(mem_read), .mem_write(mem_write),
        .wb_sel_mem(wb_sel_mem), .valid(valid),
        .branch_type(branch_type), .wb_sel(wb_sel)
    );

    // One directed test counts as one check; all listed outputs are compared.
    task check_case;
        input passed;
        input [8*48-1:0] name;
        begin
            checks = checks + 1;
            if (passed !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL [%0d] %0s inst=%h", checks, name, inst);
                $display("  r1=%d r2=%d rd=%d used=%b%b alu=%h imm=%h src=%b reg=%b mr=%b mw=%b branch=%h wb=%h valid=%b",
                         rs1_addr, rs2_addr, rd_addr, rs1_used, rs2_used,
                         alu_op, imm_sel, alu_src_imm, reg_write,
                         mem_read, mem_write, branch_type, wb_sel, valid);
            end else begin
                $display("PASS [%0d] %0s", checks, name);
            end
        end
    endtask

    // 3-register instruction: inst = opcode | rk | rj | rd
    task check_r3;
        input [31:0] opcode;
        input [3:0] expected_alu;
        input [4:0] rd, rj, rk;
        input [8*48-1:0] name;
        begin
            inst = opcode | ({27'd0, rk} << 10) |
                   ({27'd0, rj} << 5) | {27'd0, rd};
            #1;
            check_case(valid === 1'b1 &&
                       rs1_addr === rj && rs2_addr === rk && rd_addr === rd &&
                       rs1_used === 1'b1 && rs2_used === 1'b1 &&
                       alu_op === expected_alu && imm_sel === 3'd0 &&
                       alu_src_imm === 1'b0 && reg_write === 1'b1 &&
                       mem_read === 1'b0 && mem_write === 1'b0 &&
                       branch_type === 3'd0 && wb_sel === 2'b00 &&
                       wb_sel_mem === 1'b0, name);
        end
    endtask

    // ADDI.W: signed 12-bit immediate is passed to ImmGen by imm_sel=1.
    task check_addi;
        input [4:0] rd, rj;
        input [11:0] si12;
        begin
            inst = 32'h02800000 | ({20'd0, si12} << 10) |
                   ({27'd0, rj} << 5) | {27'd0, rd};
            #1;
            check_case(valid === 1'b1 &&
                       rs1_addr === rj && rs2_addr === 5'd0 && rd_addr === rd &&
                       rs1_used === 1'b1 && rs2_used === 1'b0 &&
                       alu_op === 4'h0 && imm_sel === 3'd1 &&
                       alu_src_imm === 1'b1 && reg_write === 1'b1 &&
                       mem_read === 1'b0 && mem_write === 1'b0 &&
                       branch_type === 3'd0 && wb_sel === 2'b00 &&
                       wb_sel_mem === 1'b0, "ADDI.W");
        end
    endtask

    initial begin
        inst = 32'd0;
        checks = 0;
        errors = 0;

        // New ADD.W: ALU_ADD = 0
        check_r3(32'h00100000, 4'h0, 5'd3, 5'd4, 5'd5, "ADD.W registers");
        check_r3(32'h00100000, 4'h0, 5'd31, 5'd0, 5'd31, "ADD.W boundary regs");
        check_r3(32'h00100000, 4'h0, 5'd1, 5'd1, 5'd1, "ADD.W same regs");

        // New SUB.W: ALU_SUB = 1
        check_r3(32'h00110000, 4'h1, 5'd3, 5'd4, 5'd5, "SUB.W registers");
        check_r3(32'h00110000, 4'h1, 5'd0, 5'd31, 5'd0, "SUB.W boundary regs");
        check_r3(32'h00110000, 4'h1, 5'd7, 5'd7, 5'd7, "SUB.W same regs");

        // New ADDI.W: imm_sel=1, ALU_ADD = 0
        check_addi(5'd3,  5'd4,  12'h005); // +5
        check_addi(5'd6,  5'd7,  12'hFFF); // -1 (signed 12-bit)
        check_addi(5'd31, 5'd0,  12'h800); // -2048
        check_addi(5'd1,  5'd31, 12'h7FF); // +2047

        // Previously supported AND (regression)
        inst = 32'h00148000 | (32'd8 << 10) | (32'd5 << 5) | 32'd2;
        #1;
        check_case(valid === 1'b1 && alu_op === 4'h2 &&
                   rs1_addr === 5'd5 && rs2_addr === 5'd8 && rd_addr === 5'd2 &&
                   reg_write === 1'b1 && wb_sel === 2'd0, "AND regression");

        // Previously supported ORI (regression)
        inst = 32'h03800000 | (32'hABC << 10) | (32'd5 << 5) | 32'd6;
        #1;
        check_case(valid === 1'b1 && alu_op === 4'h3 &&
                   imm_sel === 3'd2 && alu_src_imm === 1'b1 &&
                   rs1_addr === 5'd5 && rs2_used === 1'b0 &&
                   rd_addr === 5'd6 && reg_write === 1'b1, "ORI regression");

        // Previously supported LD.W
        inst = 32'h28800000 | (32'hFFC << 10) | (32'd4 << 5) | 32'd3;
        #1;
        check_case(valid === 1'b1 && imm_sel === 3'd1 &&
                   rs1_addr === 5'd4 && rd_addr === 5'd3 &&
                   mem_read === 1'b1 && mem_write === 1'b0 &&
                   reg_write === 1'b1 && wb_sel === 2'd1 &&
                   wb_sel_mem === 1'b1, "LD.W regression");

        // Previously supported ST.W: second read address is rd field
        inst = 32'h29800000 | (32'd8 << 10) | (32'd4 << 5) | 32'd3;
        #1;
        check_case(valid === 1'b1 && rs1_addr === 5'd4 &&
                   rs2_addr === 5'd3 && rs2_used === 1'b1 &&
                   mem_write === 1'b1 && reg_write === 1'b0, "ST.W regression");

        // Previously supported BEQ/BNE: compare rj and rd
        inst = (32'h16 << 26) | (32'd4 << 10) | (32'd7 << 5) | 32'd8;
        #1;
        check_case(valid === 1'b1 && branch_type === 3'd1 &&
                   imm_sel === 3'd5 && rs1_addr === 5'd7 &&
                   rs2_addr === 5'd8 && reg_write === 1'b0, "BEQ regression");
        inst = (32'h17 << 26) | (32'd4 << 10) | (32'd7 << 5) | 32'd8;
        #1;
        check_case(valid === 1'b1 && branch_type === 3'd2 &&
                   imm_sel === 3'd5 && rs1_addr === 5'd7 &&
                   rs2_addr === 5'd8 && reg_write === 1'b0, "BNE regression");

        // B branch, BL link to r1, JIRL link to rd
        inst = (32'h14 << 26) | 32'h0000_0004;
        #1;
        check_case(valid === 1'b1 && branch_type === 3'd3 &&
                   imm_sel === 3'd6 && reg_write === 1'b0, "B regression");
        inst = (32'h15 << 26) | 32'h0000_0004;
        #1;
        check_case(valid === 1'b1 && branch_type === 3'd4 &&
                   imm_sel === 3'd6 && reg_write === 1'b1 &&
                   rd_addr === 5'd1 && wb_sel === 2'd2, "BL regression");
        inst = (32'h13 << 26) | (32'hFFC << 10) | (32'd5 << 5) | 32'd8;
        #1;
        check_case(valid === 1'b1 && branch_type === 3'd5 &&
                   imm_sel === 3'd5 && rs1_addr === 5'd5 &&
                   rd_addr === 5'd8 && reg_write === 1'b1 &&
                   wb_sel === 2'd2, "JIRL regression");

        // Unsupported opcode: must not write registers or memory
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
