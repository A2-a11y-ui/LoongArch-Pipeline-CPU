`timescale 1ns / 1ps
`include "../rtl/common/cpu_defs.vh"

// Self-checking testbench for B's 13 LoongArch instructions.
// Instantiates decoder + your imm_gen + A's alu for cross-module verification.
module tb_decoder;
    reg  [31:0] inst;
    reg  [31:0] rs1_data, rs2_data;
    wire [4:0] rs1_addr, rs2_addr, rd_addr;
    wire       rs1_used, rs2_used;
    wire [3:0] alu_op;
    wire [2:0] imm_sel;
    wire       alu_src_imm, reg_write, mem_read, mem_write, wb_sel_mem, valid;
    wire [31:0] imm, alu_b, alu_result;
    integer tests, errors;

    decoder dut (
        .inst(inst),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .rd_addr(rd_addr),
        .rs1_used(rs1_used), .rs2_used(rs2_used),
        .alu_op(alu_op), .imm_sel(imm_sel), .alu_src_imm(alu_src_imm),
        .reg_write(reg_write), .mem_read(mem_read),
        .mem_write(mem_write), .wb_sel_mem(wb_sel_mem), .valid(valid)
    );

    imm_gen u_imm_gen (.inst(inst), .imm_sel(imm_sel), .imm(imm));

    assign alu_b = alu_src_imm ? imm : rs2_data;
    alu u_alu (.a(rs1_data), .b(alu_b), .alu_op(alu_op), .result(alu_result));

    // code: 0 AND, 1 OR, 2 NOR, 3 XOR, 4 ANDI, 5 ORI, 6 XORI,
    //       7 SLLI.W, 8 SRLI.W, 9 SRAI.W, 10 LU12I.W, 11 LD.W, 12 ST.W,
    //       13 unsupported instruction.
    task check;
        input [8*24-1:0] name;
        input [31:0] ins;
        input integer code;
        input [31:0] expected_imm;

        reg [3:0] x_alu;
        reg [2:0] x_sel;
        reg x_srcimm, x_regwrite, x_memread, x_memwrite, x_wbmem, x_valid;
        reg x_use1, x_use2;
        reg [4:0] x_rs1, x_rs2, x_rd;
        begin
            x_alu = `ALU_ADD;
            x_sel = 3'd0;
            x_srcimm = 0; x_regwrite = 0;
            x_memread = 0; x_memwrite = 0; x_wbmem = 0;
            x_valid = 1; x_use1 = 0; x_use2 = 0;

            case (code)
               0: begin x_alu=`ALU_AND; x_regwrite=1; x_use1=1; x_use2=1; end
               1: begin x_alu=`ALU_OR;  x_regwrite=1; x_use1=1; x_use2=1; end
               2: begin x_alu=`ALU_NOR; x_regwrite=1; x_use1=1; x_use2=1; end
               3: begin x_alu=`ALU_XOR; x_regwrite=1; x_use1=1; x_use2=1; end
               4: begin x_alu=`ALU_AND; x_regwrite=1; x_use1=1; x_srcimm=1; x_sel=2; end
               5: begin x_alu=`ALU_OR;  x_regwrite=1; x_use1=1; x_srcimm=1; x_sel=2; end
               6: begin x_alu=`ALU_XOR; x_regwrite=1; x_use1=1; x_srcimm=1; x_sel=2; end
               7: begin x_alu=`ALU_SLL; x_regwrite=1; x_use1=1; x_srcimm=1; x_sel=3; end
               8: begin x_alu=`ALU_SRL; x_regwrite=1; x_use1=1; x_srcimm=1; x_sel=3; end
               9: begin x_alu=`ALU_SRA; x_regwrite=1; x_use1=1; x_srcimm=1; x_sel=3; end
              10: begin x_alu=`ALU_PASS_B; x_regwrite=1; x_srcimm=1; x_sel=4; end
              11: begin x_alu=`ALU_ADD; x_regwrite=1; x_use1=1; x_srcimm=1;
                        x_sel=1; x_memread=1; x_wbmem=1; end
              12: begin x_alu=`ALU_ADD; x_use1=1; x_use2=1; x_srcimm=1;
                        x_sel=1; x_memwrite=1; end
              default: begin x_valid=0; end
            endcase

            x_rd  = x_valid ? ins[4:0] : 5'd0;
            x_rs1 = x_use1 ? ins[9:5] : 5'd0;
            x_rs2 = x_use2 ? ((code == 12) ? ins[4:0] : ins[14:10]) : 5'd0;

            inst = ins;
            #1;
            tests = tests + 1;

            if (alu_op !== x_alu
                || imm_sel !== x_sel
                || alu_src_imm !== x_srcimm
                || reg_write !== x_regwrite
                || mem_read !== x_memread
                || mem_write !== x_memwrite
                || wb_sel_mem !== x_wbmem
                || valid !== x_valid
                || rs1_used !== x_use1
                || rs2_used !== x_use2
                || rs1_addr !== x_rs1
                || rs2_addr !== x_rs2
                || rd_addr !== x_rd
                || imm !== expected_imm) begin
                errors = errors + 1;
                $display("FAIL %0s inst=%08h code=%0d",name,ins,code);
                $display("  got valid=%b op=%h sel=%h imm=%08h rw=%b mr=%b mw=%b wb=%b",
                    valid,alu_op,imm_sel,imm,reg_write,mem_read,mem_write,wb_sel_mem);
                $display("  got rs1=%0d rs2=%0d rd=%0d use1=%b use2=%b srcimm=%b",
                    rs1_addr,rs2_addr,rd_addr,rs1_used,rs2_used,alu_src_imm);
            end else begin
                $display("PASS %0s inst=%08h",name,ins);
            end
        end
    endtask

    task check_alu;
        input [8*24-1:0] name;
        input [31:0] a_val, b_val, expected;
        begin
            rs1_data = a_val;
            rs2_data = b_val;
            #1;
            tests = tests + 1;
            if (alu_result !== expected) begin
                errors = errors + 1;
                $display("FAIL ALU %0s got=%08h expected=%08h",name,alu_result,expected);
            end else begin
                $display("PASS ALU %0s result=%08h",name,alu_result);
            end
        end
    endtask

    initial begin
        inst=0;
        rs1_data=0;
        rs2_data=0;
        tests=0;
        errors=0;
        check("AND", 32'h0014883F, 0, 32'h00000000);
        check_alu("AND_RESULT",32'hFF00FF00,32'h0F0F0F0F,32'h0F000F00);
        check("OR", 32'h001518A4, 1, 32'h00000000);
        check_alu("OR_RESULT",32'hF0000000,32'h0000000F,32'hF000000F);
        check("NOR", 32'h00142507, 2, 32'h00000000);
        check_alu("NOR_RESULT",32'h00000000,32'h00000000,32'hFFFFFFFF);
        check("XOR", 32'h0015B16A, 3, 32'h00000000);
        check_alu("XOR_RESULT",32'hFF00FF00,32'h0F0F0F0F,32'hF00FF00F);
        check("ANDI_FFF", 32'h037FFD64, 4, 32'h00000FFF);
        check("ORI_800", 32'h03A00125, 5, 32'h00000800);
        check("XORI_000", 32'h03C00146, 6, 32'h00000000);
        check("SLLI_0", 32'h00408107, 7, 32'h00000000);
        check("SLLI_31", 32'h0040FD07, 7, 32'h0000001F);
        check_alu("SLLI_RESULT",32'h00000001,32'h12345678,32'h80000000);
        check("SRLI_1", 32'h00448549, 8, 32'h00000001);
        check("SRLI_31", 32'h0044FD49, 8, 32'h0000001F);
        check_alu("SRLI_RESULT",32'h80000000,32'h12345678,32'h00000001);
        check("SRAI_0", 32'h0048818B, 9, 32'h00000000);
        check("SRAI_31", 32'h0048FD8B, 9, 32'h0000001F);
        check_alu("SRAI_RESULT",32'h80000000,32'h12345678,32'hFFFFFFFF);
        check("LU12I_00000", 32'h1400000D, 10, 32'h00000000);
        check("LU12I_80000", 32'h1500000E, 10, 32'h80000000);
        check_alu("LU12I_RESULT",32'h12345678,32'h12345678,32'h80000000);
        check("LU12I_FFFFF", 32'h15FFFFEF, 10, 32'hFFFFF000);
        check("LD_P2047", 32'h289FFE30, 11, 32'h000007FF);
        check("LD_M2048", 32'h28A00272, 11, 32'hFFFFF800);
        check("LD_M1", 32'h28BFFE72, 11, 32'hFFFFFFFF);
        check_alu("LD_ADDRESS",32'h00001000,32'h12345678,32'h00000FFF);
        check("ST_M4", 32'h29BFF2B4, 12, 32'hFFFFFFFC);
        check_alu("ST_ADDRESS",32'h00001004,32'h12345678,32'h00001000);
        check("ST_0", 32'h298002F6, 12, 32'h00000000);
        check("INVALID_ZERO", 32'h00000000, 13, 32'h00000000);
        check("INVALID_ONES", 32'hFFFFFFFF, 13, 32'h00000000);
        check("INVALID_ORN", 32'h00160000, 13, 32'h00000000);
        check("INVALID_SLLI_D", 32'h00410000, 13, 32'h00000000);
        check("INVALID_LD_D", 32'h28C00000, 13, 32'h00000000);
        check("INVALID_LU32I_D", 32'h16000000, 13, 32'h00000000);
        check("INVALID_ADDI_W", 32'h02800000, 13, 32'h00000000);

        $display("--------------------------------");
        $display("Total tests  = %0d", tests);
        $display("Total errors = %0d", errors);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end
endmodule
