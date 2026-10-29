`timescale 1ns / 1ps
// V0.3 PRE-INTEGRATION verification: official IF/ID + ID/EX registers,
// official decoder, official load_use_hazard_unit and pipeline_control_unit.
// This does NOT model data memory or the complete five-stage CPU.
// Vivado 2019.1 / Verilog-2001.
module tb_load_use_control_v03;
    reg clk=1'b0;
    always #5 clk=~clk;
    reg rst=1'b1, branch_redirect=1'b0;
    reg if_valid=1'b0;
    reg [31:0] if_pc=32'd0, if_inst=32'd0;
    wire id_valid;
    wire [31:0] id_pc, id_inst;
    wire [4:0] rs1, rs2, rd;
    wire rs1_used, rs2_used, alu_src_imm, reg_write, mem_read, mem_write;
    wire dec_valid, wb_sel_mem;
    wire [3:0] alu_op;
    wire [2:0] imm_sel, branch_type;
    wire [1:0] wb_sel;
    wire [31:0] imm;
    wire ex_valid, ex_mem_read;
    wire [4:0] ex_rd_addr;
    wire [31:0] ex_pc;
    wire load_use_hazard, hold_if_req, hold_ifid_req, bubble_idex_req;
    wire ifid_stall, ifid_flush, idex_flush, hold_fetch_issue_req;
    integer phases=0, checks=0, errors=0;

    if_id_reg u_if_id (
        .clk(clk), .rst(rst), .stall(ifid_stall), .flush(ifid_flush),
        .if_valid(if_valid), .if_pc(if_pc), .if_inst(if_inst),
        .id_valid(id_valid), .id_pc(id_pc), .id_inst(id_inst)
    );
    decoder u_decoder (
        .inst(id_inst), .rs1_addr(rs1), .rs2_addr(rs2),
        .rd_addr(rd), .rs1_used(rs1_used), .rs2_used(rs2_used),
        .alu_op(alu_op), .imm_sel(imm_sel), .alu_src_imm(alu_src_imm),
        .reg_write(reg_write), .mem_read(mem_read), .mem_write(mem_write),
        .wb_sel_mem(wb_sel_mem), .valid(dec_valid),
        .branch_type(branch_type), .wb_sel(wb_sel)
    );
    imm_gen u_imm_gen(.inst(id_inst), .imm_sel(imm_sel), .imm(imm));
    id_ex_reg u_id_ex (
        .clk(clk), .rst(rst), .stall(1'b0), .flush(idex_flush),
        .id_valid(id_valid && dec_valid), .id_pc(id_pc),
        .id_pc_plus4(id_pc + 32'd4), .id_inst(id_inst),
        .id_rs1_addr(rs1), .id_rs2_addr(rs2), .id_rd_addr(rd),
        .id_rs1_data(32'd0), .id_rs2_data(32'd0),
        .id_rs1_used(rs1_used), .id_rs2_used(rs2_used),
        .id_imm(imm), .id_alu_op(alu_op),
        .id_alu_src_imm(alu_src_imm), .id_branch_type(branch_type),
        .id_wb_sel(wb_sel), .id_reg_write(reg_write),
        .id_mem_read(mem_read), .id_mem_write(mem_write),
        .ex_valid(ex_valid), .ex_pc(ex_pc),
        .ex_rd_addr(ex_rd_addr), .ex_mem_read(ex_mem_read)
    );
    load_use_hazard_unit u_hazard (
        .id_valid(id_valid && dec_valid),
        .id_rs1_addr(rs1), .id_rs2_addr(rs2),
        .id_rs1_used(rs1_used), .id_rs2_used(rs2_used),
        .ex_valid(ex_valid), .ex_mem_read(ex_mem_read),
        .ex_rd_addr(ex_rd_addr),
        .load_use_hazard(load_use_hazard),
        .hold_if_req(hold_if_req),
        .hold_ifid_req(hold_ifid_req),
        .bubble_idex_req(bubble_idex_req)
    );
    pipeline_control_unit u_pcu (
        .rst(rst), .branch_redirect(branch_redirect),
        .load_use_hazard(load_use_hazard),
        .ifid_stall(ifid_stall), .ifid_flush(ifid_flush),
        .idex_flush(idex_flush),
        .hold_fetch_issue_req(hold_fetch_issue_req)
    );

    function [31:0] inst_i;
        input [31:0] opcode;
        input [4:0] dest, source;
        input [11:0] immediate;
        begin inst_i=opcode | {10'd0,immediate,source,dest}; end
    endfunction
    function [31:0] inst_r;
        input [31:0] opcode;
        input [4:0] dest, source1, source2;
        begin inst_r=opcode | {17'd0,source2,source1,dest}; end
    endfunction

    task drive_if;
        input v;
        input [31:0] pc, instr;
        begin
            @(negedge clk);
            if_valid=v; if_pc=pc; if_inst=instr;
        end
    endtask
    task step;
        input [8*64-1:0] desc;
        input expected_id_v;
        input [31:0] expected_id_pc;
        input expected_ex_v;
        input [4:0] expected_ex_rd;
        input expected_ex_load;
        input expected_hazard, expected_stall, expected_if_flush,
              expected_ex_flush, expected_hold;
        begin
            phases=phases+1;
            checks=checks+10;
            if (id_valid !== expected_id_v) begin errors=errors+1; $display("FAIL %0s id_valid=%b expected=%b",desc,id_valid,expected_id_v); end
            if (id_pc !== expected_id_pc) begin errors=errors+1; $display("FAIL %0s id_pc=%h expected=%h",desc,id_pc,expected_id_pc); end
            if (ex_valid !== expected_ex_v) begin errors=errors+1; $display("FAIL %0s ex_valid=%b expected=%b",desc,ex_valid,expected_ex_v); end
            if (ex_rd_addr !== expected_ex_rd) begin errors=errors+1; $display("FAIL %0s ex_rd=%d expected=%d",desc,ex_rd_addr,expected_ex_rd); end
            if (ex_mem_read !== expected_ex_load) begin errors=errors+1; $display("FAIL %0s ex_mem_read=%b expected=%b",desc,ex_mem_read,expected_ex_load); end
            if (load_use_hazard !== expected_hazard) begin errors=errors+1; $display("FAIL %0s load_use=%b expected=%b",desc,load_use_hazard,expected_hazard); end
            if (ifid_stall !== expected_stall) begin errors=errors+1; $display("FAIL %0s ifid_stall=%b expected=%b",desc,ifid_stall,expected_stall); end
            if (ifid_flush !== expected_if_flush) begin errors=errors+1; $display("FAIL %0s ifid_flush=%b expected=%b",desc,ifid_flush,expected_if_flush); end
            if (idex_flush !== expected_ex_flush) begin errors=errors+1; $display("FAIL %0s idex_flush=%b expected=%b",desc,idex_flush,expected_ex_flush); end
            if (hold_fetch_issue_req !== expected_hold) begin errors=errors+1; $display("FAIL %0s hold_issue=%b expected=%b",desc,hold_fetch_issue_req,expected_hold); end
            $display("PHASE %0d: %0s",phases,desc);
        end
    endtask

    initial begin
        // Synchronous reset active across two edges.
        @(posedge clk); #1;
        step("reset state",0,32'd0,0,5'd0,0,0,0,1,1,1);
        @(posedge clk); #1;
        @(negedge clk); rst=0;

        // Feed LD.W r5, 0(r0) followed immediately by dependent ADD.W.
        // NOTE: this harness only verifies control; no DMEM result exists.
        if_valid=1; if_pc=32'h1000;
        if_inst=inst_i(32'h28800000,5'd5,5'd0,12'd0);
        @(posedge clk); #1;
        step("load held in ID",1,32'h1000,0,5'd0,0,0,0,0,0,0);

        drive_if(1,32'h1004,inst_r(32'h00100000,5'd6,5'd5,5'd0));
        @(posedge clk); #1;
        step("load in EX dependent ADD in ID",1,32'h1004,1,5'd5,1,1,1,0,1,1);

        // New fetch is PRESENT but must not replace stalled IF/ID entry.
        drive_if(1,32'h1008,inst_i(32'h02800000,5'd7,5'd0,12'd3));
        @(posedge clk); #1;
        step("one bubble inserted and IFID held",1,32'h1004,0,5'd0,0,0,0,0,0,0);

        // In a full CPU the LD.W continues into EX/MEM at the previous edge;
        // the front end must retry the held fetch as IF/ID can advance now.
        drive_if(1,32'h1008,inst_i(32'h02800000,5'd7,5'd0,12'd3));
        @(posedge clk); #1;
        step("consumer resumes into EX",1,32'h1008,1,5'd6,0,0,0,0,0,0);

        drive_if(0,32'd0,32'd0);
        @(posedge clk); #1;
        step("IF bubble ID/EX advances",0,32'd0,1,5'd7,0,0,0,0,0,0);
        @(posedge clk); #1;
        step("pipeline front drain",0,32'd0,0,5'd0,0,0,0,0,0,0);

        // Repeat dependency; assert branch redirect at the same time as
        // load-use. Redirect must beat load-use, flushing both registers.
        drive_if(1,32'h2000,inst_i(32'h28800000,5'd9,5'd0,12'd0));
        @(posedge clk); #1;
        step("second load in ID",1,32'h2000,0,5'd0,0,0,0,0,0,0);
        drive_if(1,32'h2004,inst_r(32'h00100000,5'd10,5'd9,5'd0));
        @(posedge clk); #1;
        step("second load-use dependency",1,32'h2004,1,5'd9,1,1,1,0,1,1);
        @(negedge clk); branch_redirect=1;
        #1;
        step("redirect beats load-use",1,32'h2004,1,5'd9,1,1,0,1,1,0);
        @(posedge clk); #1;
        step("redirect flush completed",0,32'd0,0,5'd0,0,0,0,1,1,0);
        @(negedge clk); branch_redirect=0;
        #1;
        step("redirect released",0,32'd0,0,5'd0,0,0,0,0,0,0);
        rst=1;
        #1;
        step("reset priority",0,32'd0,0,5'd0,0,0,0,1,1,1);

        $display("----------------------------------------");
        $display("V0.3 LOAD-USE CONTROL AND REGISTER TEST");
        $display("phases=%0d checks=%0d errors=%0d",phases,checks,errors);
        if (phases==13 && checks==130 && errors==0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED");
        $finish;
    end
    initial begin
        #5000;
        $display("TESTS FAILED: watchdog timeout");
        $finish;
    end
endmodule
