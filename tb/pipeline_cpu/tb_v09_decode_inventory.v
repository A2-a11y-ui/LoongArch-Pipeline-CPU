`timescale 1ns / 1ps
// Independent V0.9 instruction-inventory DECODE-ONLY regression; NOT a CPU-level execution regression.
// Uses actual decoder.v and mdu_decode_v08.v; CPU overlay/FPGA top remains unverified.
module tb_v09_decode_inventory;
    reg [31:0] inst;
    wire [4:0] rs1_addr,rs2_addr,rd_addr;
    wire rs1_used,rs2_used,alu_src_imm,reg_write,mem_read,mem_write,wb_sel_mem,valid;
    wire [3:0] alu_op;
    wire [2:0] imm_sel,branch_type;
    wire [1:0] wb_sel;
    wire is_mdu;
    wire [2:0] mdu_op;
    integer cases,checks,errors;
    decoder u_decoder(
        .inst(inst),.rs1_addr(rs1_addr),.rs2_addr(rs2_addr),.rd_addr(rd_addr),
        .rs1_used(rs1_used),.rs2_used(rs2_used),.alu_op(alu_op),.imm_sel(imm_sel),
        .alu_src_imm(alu_src_imm),.reg_write(reg_write),.mem_read(mem_read),
        .mem_write(mem_write),.wb_sel_mem(wb_sel_mem),.valid(valid),
        .branch_type(branch_type),.wb_sel(wb_sel));
    mdu_decode_v08 u_mdu_decoder(.inst(inst),.is_mdu(is_mdu),.mdu_op(mdu_op));
    // This verifies the actual I26 offset from imm_gen, not just decoder.imm_sel.
    wire [31:0] branch_byte_offset;
    imm_gen u_imm_gen(.inst(inst),.imm_sel(imm_sel),.imm(branch_byte_offset));
    task eq32;
        input [8*32-1:0] what;
        input [31:0] got;
        input [31:0] want;
        begin checks=checks+1; if (got !== want) begin
            errors=errors+1;
            $display("FAIL %0s inst=%h got=%h want=%h",what,inst,got,want);
        end end
    endtask
    task check_base;
        input [8*24-1:0] tag; input [31:0] codeword;
        input [4:0] e_s1,e_s2,e_rd; input e_u1,e_u2,e_wr,e_mr,e_mw;
        input [3:0] e_alu; input [2:0] e_imm,e_br; input e_alsrc; input [1:0] e_wb;
        begin
            inst=codeword; #1; cases=cases+1;
            eq32("valid",valid,1); eq32("is_mdu",is_mdu,0);
            eq32("rs1_addr",rs1_addr,e_s1); eq32("rs2_addr",rs2_addr,e_s2);
            eq32("rd_addr",rd_addr,e_rd); eq32("rs1_used",rs1_used,e_u1);
            eq32("rs2_used",rs2_used,e_u2); eq32("reg_write",reg_write,e_wr);
            eq32("mem_read",mem_read,e_mr); eq32("mem_write",mem_write,e_mw);
            eq32("alu_op",alu_op,e_alu); eq32("imm_sel",imm_sel,e_imm);
            eq32("branch_type",branch_type,e_br); eq32("alu_src_imm",alu_src_imm,e_alsrc);
            eq32("wb_sel",wb_sel,e_wb); eq32("wb_sel_mem",wb_sel_mem,(e_wb==1));
            $display("CHECK base %-12s inst=%h",tag,inst);
        end
    endtask
    task check_mdu;
        input [8*24-1:0] tag; input [31:0] codeword; input [2:0] expect_op;
        begin inst=codeword; #1; cases=cases+1;
            eq32("legacy.valid must be 0",valid,0);
            eq32("mdu.is_mdu",is_mdu,1);
            eq32("mdu.op",mdu_op,expect_op);
            eq32("rj bits",(inst>>5)&31,1);
            eq32("rk bits",(inst>>10)&31,2);
            eq32("rd bits",inst&31,3);
            $display("CHECK MDU  %-12s inst=%h",tag,inst);
        end
    endtask
    task check_invalid;
        input [31:0] codeword;
        begin inst=codeword; #1; cases=cases+1;
            eq32("invalid base",valid,0); eq32("invalid mdu",is_mdu,0);
        end
    endtask
    // Four additional branch-offset checks (B/BL x valid and counterexample).
    // These cases check decoded offset and PC arithmetic, NOT a CPU executing a branch.
    task check_b_target;
        input [8*24-1:0] tag;
        input [31:0] codeword;
        input [2:0] e_br;
        input [31:0] e_offset;
        input [31:0] e_target;
        begin
            inst=codeword; #1; cases=cases+1;
            eq32("branch_type",branch_type,e_br);
            eq32("imm_sel",imm_sel,3'd6);
            eq32("branch_byte_offset",branch_byte_offset,e_offset);
            eq32("PC+branch_offset",(32'h00001000+branch_byte_offset),e_target);
            $display("CHECK B/BL offset %-12s inst=%h offset=%h target=%h", tag, inst, branch_byte_offset, (32'h00001000+branch_byte_offset));
        end
    endtask
    initial begin
        inst=32'd0; cases=0; checks=0; errors=0;
        check_base("ADD.W",32'h00100823,5'd1,5'd2,5'd3,1'b1,1'b1,1'b1,1'b0,1'b0,4'd0,3'd0,3'd0,1'b0,2'd0);
        check_base("SUB.W",32'h00110823,5'd1,5'd2,5'd3,1'b1,1'b1,1'b1,1'b0,1'b0,4'd1,3'd0,3'd0,1'b0,2'd0);
        check_base("SLT",32'h00120823,5'd1,5'd2,5'd3,1'b1,1'b1,1'b1,1'b0,1'b0,4'd6,3'd0,3'd0,1'b0,2'd0);
        check_base("SLTU",32'h00128823,5'd1,5'd2,5'd3,1'b1,1'b1,1'b1,1'b0,1'b0,4'd7,3'd0,3'd0,1'b0,2'd0);
        check_base("SLL.W",32'h00170823,5'd1,5'd2,5'd3,1'b1,1'b1,1'b1,1'b0,1'b0,4'd8,3'd0,3'd0,1'b0,2'd0);
        check_base("SRL.W",32'h00178823,5'd1,5'd2,5'd3,1'b1,1'b1,1'b1,1'b0,1'b0,4'd9,3'd0,3'd0,1'b0,2'd0);
        check_base("SRA.W",32'h00180823,5'd1,5'd2,5'd3,1'b1,1'b1,1'b1,1'b0,1'b0,4'd10,3'd0,3'd0,1'b0,2'd0);
        check_base("NOR",32'h00140823,5'd1,5'd2,5'd3,1'b1,1'b1,1'b1,1'b0,1'b0,4'd5,3'd0,3'd0,1'b0,2'd0);
        check_base("AND",32'h00148823,5'd1,5'd2,5'd3,1'b1,1'b1,1'b1,1'b0,1'b0,4'd2,3'd0,3'd0,1'b0,2'd0);
        check_base("OR",32'h00150823,5'd1,5'd2,5'd3,1'b1,1'b1,1'b1,1'b0,1'b0,4'd3,3'd0,3'd0,1'b0,2'd0);
        check_base("XOR",32'h00158823,5'd1,5'd2,5'd3,1'b1,1'b1,1'b1,1'b0,1'b0,4'd4,3'd0,3'd0,1'b0,2'd0);
        check_base("ADDI.W",32'h02BFF423,5'd1,5'd0,5'd3,1'b1,1'b0,1'b1,1'b0,1'b0,4'd0,3'd1,3'd0,1'b1,2'd0);
        check_base("SLTI",32'h023FF423,5'd1,5'd0,5'd3,1'b1,1'b0,1'b1,1'b0,1'b0,4'd6,3'd1,3'd0,1'b1,2'd0);
        check_base("ANDI",32'h03403C23,5'd1,5'd0,5'd3,1'b1,1'b0,1'b1,1'b0,1'b0,4'd2,3'd2,3'd0,1'b1,2'd0);
        check_base("ORI",32'h03803C23,5'd1,5'd0,5'd3,1'b1,1'b0,1'b1,1'b0,1'b0,4'd3,3'd2,3'd0,1'b1,2'd0);
        check_base("XORI",32'h03C03C23,5'd1,5'd0,5'd3,1'b1,1'b0,1'b1,1'b0,1'b0,4'd4,3'd2,3'd0,1'b1,2'd0);
        check_base("SLLI.W",32'h00408823,5'd1,5'd0,5'd3,1'b1,1'b0,1'b1,1'b0,1'b0,4'd8,3'd3,3'd0,1'b1,2'd0);
        check_base("SRLI.W",32'h00448823,5'd1,5'd0,5'd3,1'b1,1'b0,1'b1,1'b0,1'b0,4'd9,3'd3,3'd0,1'b1,2'd0);
        check_base("SRAI.W",32'h00488823,5'd1,5'd0,5'd3,1'b1,1'b0,1'b1,1'b0,1'b0,4'd10,3'd3,3'd0,1'b1,2'd0);
        check_base("LU12I.W",32'h142468A3,5'd0,5'd0,5'd3,1'b0,1'b0,1'b1,1'b0,1'b0,4'd11,3'd4,3'd0,1'b1,2'd0);
        check_base("LD.W",32'h28802023,5'd1,5'd0,5'd3,1'b1,1'b0,1'b1,1'b1,1'b0,4'd0,3'd1,3'd0,1'b1,2'd1);
        check_base("ST.W",32'h29803022,5'd1,5'd2,5'd2,1'b1,1'b1,1'b0,1'b0,1'b1,4'd0,3'd1,3'd0,1'b1,2'd0);
        check_base("BEQ",32'h58000C22,5'd1,5'd2,5'd0,1'b1,1'b1,1'b0,1'b0,1'b0,4'd0,3'd5,3'd1,1'b0,2'd0);
        check_base("BNE",32'h5C000C22,5'd1,5'd2,5'd0,1'b1,1'b1,1'b0,1'b0,1'b0,4'd0,3'd5,3'd2,1'b0,2'd0);
        check_base("JIRL",32'h4C000C23,5'd1,5'd0,5'd3,1'b1,1'b0,1'b1,1'b0,1'b0,4'd0,3'd5,3'd5,1'b0,2'd2);
        check_base("B",32'h50000C00,5'd0,5'd0,5'd0,1'b0,1'b0,1'b0,1'b0,1'b0,4'd0,3'd6,3'd3,1'b0,2'd0);
        check_base("BL",32'h54000C00,5'd0,5'd0,5'd1,1'b0,1'b0,1'b1,1'b0,1'b0,4'd0,3'd6,3'd4,1'b0,2'd2);
        check_b_target("B plus12", 32'h50000C00, 3'd3, 32'h0000000C, 32'h0000100C);
        check_b_target("BL plus12",32'h54000C00, 3'd4, 32'h0000000C, 32'h0000100C);
        check_b_target("B shifted",32'h50000003, 3'd3, 32'h000C0000, 32'h000C1000);
        check_b_target("BL shifted",32'h54000003,3'd4, 32'h000C0000, 32'h000C1000);
        check_mdu("MUL.W",32'h001C0823,3'b000);
        check_mdu("MULH.W",32'h001C8823,3'b001);
        check_mdu("MULH.WU",32'h001D0823,3'b010);
        check_mdu("DIV.W",32'h00200823,3'b011);
        check_mdu("DIV.WU",32'h00210823,3'b100);
        check_mdu("MOD.W",32'h00208823,3'b101);
        check_mdu("MOD.WU",32'h00218823,3'b110);
        check_invalid(32'h00000000);
        check_invalid(32'hFFFFFFFF);
        check_invalid(32'h001D8000);
        $display("V0.9 INVENTORY DECODE RESULT CASES=%0d CHECKS=%0d ERRORS=%0d",cases,checks,errors);
        if (errors != 0) $fatal(1,"V0.9 decoder inventory FAIL");
        $display("ALL TESTS PASSED (V0.9 decoder-only instruction inventory)");
        $finish;
    end
endmodule
