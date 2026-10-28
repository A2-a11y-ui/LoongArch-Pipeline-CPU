`timescale 1ns / 1ps
// Test the unified Decoder V2 + existing ImmGen V2, independent of CPU top.
// Input vectors below are independently specified expected control values.
module tb_decoder_v2;
    reg [31:0] inst;
    wire [4:0] rs1_addr, rs2_addr, rd_addr;
    wire rs1_used, rs2_used;
    wire [3:0] alu_op;
    wire [2:0] imm_sel, branch_type;
    wire alu_src_imm, reg_write, mem_read, mem_write, wb_sel_mem, valid;
    wire [1:0] wb_sel;
    wire [31:0] imm;
    integer tests, errors;

    decoder_v2 dut (
        .inst(inst), .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .rd_addr(rd_addr), .rs1_used(rs1_used), .rs2_used(rs2_used),
        .alu_op(alu_op), .imm_sel(imm_sel), .alu_src_imm(alu_src_imm),
        .reg_write(reg_write), .mem_read(mem_read), .mem_write(mem_write),
        .wb_sel_mem(wb_sel_mem), .valid(valid),
        .branch_type(branch_type), .wb_sel(wb_sel)
    );
    imm_gen u_imm_gen (.inst(inst), .imm_sel(imm_sel), .imm(imm));

    // flags = {valid, rs1_used, rs2_used, alu_src_imm, reg_write, mem_read, mem_write}
    task check;
        input [8*24-1:0] name;
        input [31:0] instruction;
        input [4:0] expect_rs1, expect_rs2, expect_rd;
        input [3:0] expect_alu;
        input [2:0] expect_sel, expect_branch;
        input [1:0] expect_wb;
        input [6:0] expect_flags;
        input [31:0] expect_imm;
        begin
            inst=instruction;
            #1;
            tests=tests+1;
            if (rs1_addr !== expect_rs1 || rs2_addr !== expect_rs2 ||
                rd_addr !== expect_rd || alu_op !== expect_alu ||
                imm_sel !== expect_sel || branch_type !== expect_branch ||
                wb_sel !== expect_wb ||
                {valid,rs1_used,rs2_used,alu_src_imm,reg_write,mem_read,mem_write} !== expect_flags ||
                wb_sel_mem !== (expect_wb == 2'd1) || imm !== expect_imm) begin
                errors=errors+1;
                $display("FAIL %0s inst=%08h",name,inst);
                $display("  got rs1=%0d rs2=%0d rd=%0d alu=%h imm_sel=%0d bt=%0d wb=%0d flags=%07b imm=%08h",
                         rs1_addr,rs2_addr,rd_addr,alu_op,imm_sel,branch_type,wb_sel,
                         {valid,rs1_used,rs2_used,alu_src_imm,reg_write,mem_read,mem_write},imm);
            end else $display("PASS %0s",name);
        end
    endtask

    initial begin
        inst=0; tests=0; errors=0;
        check("AND", 32'h0014883F, 5'd1, 5'd2, 5'd31, 4'h2, 3'd0, 3'd0, 2'd0, 7'b1110100, 32'h00000000);
        check("OR", 32'h001518A4, 5'd5, 5'd6, 5'd4, 4'h3, 3'd0, 3'd0, 2'd0, 7'b1110100, 32'h00000000);
        check("NOR", 32'h00142507, 5'd8, 5'd9, 5'd7, 4'h5, 3'd0, 3'd0, 2'd0, 7'b1110100, 32'h00000000);
        check("XOR", 32'h0015B16A, 5'd11, 5'd12, 5'd10, 4'h4, 3'd0, 3'd0, 2'd0, 7'b1110100, 32'h00000000);
        check("ANDI_FFF", 32'h037FFD64, 5'd11, 5'd0, 5'd4, 4'h2, 3'd2, 3'd0, 2'd0, 7'b1101100, 32'h00000FFF);
        check("ORI_800", 32'h03A00125, 5'd9, 5'd0, 5'd5, 4'h3, 3'd2, 3'd0, 2'd0, 7'b1101100, 32'h00000800);
        check("XORI_0", 32'h03C00146, 5'd10, 5'd0, 5'd6, 4'h4, 3'd2, 3'd0, 2'd0, 7'b1101100, 32'h00000000);
        check("SLLI_31", 32'h0040FD07, 5'd8, 5'd0, 5'd7, 4'h8, 3'd3, 3'd0, 2'd0, 7'b1101100, 32'h0000001F);
        check("SRLI_31", 32'h0044FD49, 5'd10, 5'd0, 5'd9, 4'h9, 3'd3, 3'd0, 2'd0, 7'b1101100, 32'h0000001F);
        check("SRAI_0", 32'h0048818B, 5'd12, 5'd0, 5'd11, 4'hA, 3'd3, 3'd0, 2'd0, 7'b1101100, 32'h00000000);
        check("LU12I_80000", 32'h1500000E, 5'd0, 5'd0, 5'd14, 4'hB, 3'd4, 3'd0, 2'd0, 7'b1001100, 32'h80000000);
        check("LD_W_neg1", 32'h28BFFE72, 5'd19, 5'd0, 5'd18, 4'h0, 3'd1, 3'd0, 2'd1, 7'b1101110, 32'hFFFFFFFF);
        check("ST_W_neg4", 32'h29BFF2B4, 5'd21, 5'd20, 5'd20, 4'h0, 3'd1, 3'd0, 2'd0, 7'b1111001, 32'hFFFFFFFC);
        check("BEQ_equal_decode", 32'h58000C43, 5'd2, 5'd3, 5'd0, 4'h0, 3'd5, 3'd1, 2'd0, 7'b1110000, 32'h0000000C);
        check("BEQ_minus8", 32'h5BFFF8A6, 5'd5, 5'd6, 5'd0, 4'h0, 3'd5, 3'd1, 2'd0, 7'b1110000, 32'hFFFFFFF8);
        check("BNE_plus8", 32'h5C000843, 5'd2, 5'd3, 5'd0, 4'h0, 3'd5, 3'd2, 2'd0, 7'b1110000, 32'h00000008);
        check("BNE_minus4", 32'h5FFFFCA6, 5'd5, 5'd6, 5'd0, 4'h0, 3'd5, 3'd2, 2'd0, 7'b1110000, 32'hFFFFFFFC);
        check("B_plus16", 32'h50001000, 5'd0, 5'd0, 5'd0, 4'h0, 3'd6, 3'd3, 2'd0, 7'b1000000, 32'h00000010);
        check("B_minus8", 32'h53FFFBFF, 5'd0, 5'd0, 5'd0, 4'h0, 3'd6, 3'd3, 2'd0, 7'b1000000, 32'hFFFFFFF8);
        check("BL_plus16", 32'h54001000, 5'd0, 5'd0, 5'd1, 4'h0, 3'd6, 3'd4, 2'd2, 7'b1000100, 32'h00000010);
        check("BL_minus4", 32'h57FFFFFF, 5'd0, 5'd0, 5'd1, 4'h0, 3'd6, 3'd4, 2'd2, 7'b1000100, 32'hFFFFFFFC);
        check("JIRL_plus4", 32'h4C000548, 5'd10, 5'd0, 5'd8, 4'h0, 3'd5, 3'd5, 2'd2, 7'b1100100, 32'h00000004);
        check("JIRL_minus4", 32'h4FFFFD40, 5'd10, 5'd0, 5'd0, 4'h0, 3'd5, 3'd5, 2'd2, 7'b1100100, 32'hFFFFFFFC);
        check("JIRL_zero", 32'h4C000007, 5'd0, 5'd0, 5'd7, 4'h0, 3'd5, 3'd5, 2'd2, 7'b1100100, 32'h00000000);
        check("INVALID_ZERO", 32'h00000000, 5'd0, 5'd0, 5'd0, 4'h0, 3'd0, 3'd0, 2'd0, 7'b0000000, 32'h00000000);
        check("INVALID_FFFFFFFF", 32'hFFFFFFFF, 5'd0, 5'd0, 5'd0, 4'h0, 3'd0, 3'd0, 2'd0, 7'b0000000, 32'h00000000);
        check("INVALID_SLLI_D", 32'h00410000, 5'd0, 5'd0, 5'd0, 4'h0, 3'd0, 3'd0, 2'd0, 7'b0000000, 32'h00000000);
        check("INVALID_LD_D", 32'h28C00000, 5'd0, 5'd0, 5'd0, 4'h0, 3'd0, 3'd0, 2'd0, 7'b0000000, 32'h00000000);
        check("INVALID_ADDI_W", 32'h02800000, 5'd0, 5'd0, 5'd0, 4'h0, 3'd0, 3'd0, 2'd0, 7'b0000000, 32'h00000000);
        $display("================================");
        $display("Total tests = %0d",tests);
        $display("Total errors = %0d",errors);
        if(errors==0) $display("ALL TESTS PASSED");
        else $display("TEST FAILED");
        $finish;
    end
endmodule
