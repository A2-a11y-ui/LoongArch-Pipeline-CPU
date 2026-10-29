`timescale 1ns / 1ps
// V0.4 PRE-INTEGRATION: official PC IF controller, PCU, IF/ID, ID/EX,
// and EX/MEM registers. EX redirect and load-use are synthetic stimuli.
// Important: hold_fetch_issue_req is advisory; upstream handles readiness.
// This is NOT a five-stage pipelined branch CPU regression.
module tb_branch_flush_control_v04;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg branch_redirect = 1'b0;
    reg [31:0] redirect_pc = 32'h00002000;
    reg load_use_hazard = 1'b0;
    reg if_req_ready = 1'b0;
    wire if_req_valid;
    wire [31:0] if_req_addr;
    wire ifid_stall, ifid_flush, idex_flush, hold_fetch_issue_req;
    reg if_valid = 1'b0;
    reg [31:0] if_pc = 0, if_inst = 0;
    wire id_valid;
    wire [31:0] id_pc, id_inst;
    wire ex_valid;
    wire [31:0] ex_pc, ex_pc_plus4, ex_inst;
    wire [4:0] ex_rs1_addr, ex_rs2_addr, ex_rd_addr;
    wire [31:0] ex_rs1_data, ex_rs2_data, ex_imm;
    wire ex_rs1_used, ex_rs2_used;
    wire [3:0] ex_alu_op;
    wire ex_alu_src_imm;
    wire [2:0] ex_branch_type;
    wire [1:0] ex_wb_sel;
    wire ex_reg_write, ex_mem_read, ex_mem_write;
    wire mem_valid, mem_mem_read, mem_mem_write, mem_reg_write;
    wire [31:0] mem_pc, mem_pc_plus4, mem_alu_result, mem_store_data;
    wire [4:0] mem_store_src_addr, mem_rd_addr;
    wire [1:0] mem_wb_sel;
    integer checks=0, errors=0;

    pc_if_controller #(.RESET_PC(32'h00001000)) u_pc (
        .clk(clk), .rst(rst), .redirect(branch_redirect),
        .redirect_pc(redirect_pc), .if_req_valid(if_req_valid),
        .if_req_addr(if_req_addr), .if_req_ready(if_req_ready)
    );
    pipeline_control_unit u_pcu (
        .rst(rst), .branch_redirect(branch_redirect),
        .load_use_hazard(load_use_hazard),
        .ifid_stall(ifid_stall), .ifid_flush(ifid_flush),
        .idex_flush(idex_flush), .hold_fetch_issue_req(hold_fetch_issue_req)
    );
    if_id_reg u_if_id (
        .clk(clk), .rst(rst), .stall(ifid_stall), .flush(ifid_flush),
        .if_valid(if_valid), .if_pc(if_pc), .if_inst(if_inst),
        .id_valid(id_valid), .id_pc(id_pc), .id_inst(id_inst)
    );
    // Standalone pipeline fixture: treat each synthetic IF instruction
    // as a writing arithmetic instruction, only to exercise pipeline state.
    id_ex_reg u_id_ex (
        .clk(clk), .rst(rst), .stall(1'b0), .flush(idex_flush),
        .id_valid(id_valid), .id_pc(id_pc), .id_pc_plus4(id_pc+32'd4),
        .id_inst(id_inst),
        .id_rs1_addr(5'd1), .id_rs2_addr(5'd2),
        .id_rd_addr(id_inst[4:0]),
        .id_rs1_data(32'd7), .id_rs2_data(32'd11),
        .id_rs1_used(1'b1), .id_rs2_used(1'b1),
        .id_imm(32'd0), .id_alu_op(4'd0), .id_alu_src_imm(1'b0),
        .id_branch_type(3'd0), .id_wb_sel(2'd0),
        .id_reg_write(id_valid), .id_mem_read(1'b0), .id_mem_write(1'b0),
        .ex_valid(ex_valid), .ex_pc(ex_pc), .ex_pc_plus4(ex_pc_plus4),
        .ex_inst(ex_inst),
        .ex_rs1_addr(ex_rs1_addr), .ex_rs2_addr(ex_rs2_addr),
        .ex_rd_addr(ex_rd_addr), .ex_rs1_data(ex_rs1_data),
        .ex_rs2_data(ex_rs2_data), .ex_rs1_used(ex_rs1_used),
        .ex_rs2_used(ex_rs2_used), .ex_imm(ex_imm),
        .ex_alu_op(ex_alu_op), .ex_alu_src_imm(ex_alu_src_imm),
        .ex_branch_type(ex_branch_type), .ex_wb_sel(ex_wb_sel),
        .ex_reg_write(ex_reg_write), .ex_mem_read(ex_mem_read),
        .ex_mem_write(ex_mem_write)
    );
    ex_mem_reg u_ex_mem (
        .clk(clk), .rst(rst), .stall(1'b0), .flush(1'b0),
        .ex_valid(ex_valid), .ex_pc(ex_pc), .ex_pc_plus4(ex_pc_plus4),
        .ex_alu_result(ex_rs1_data+ex_rs2_data),
        .ex_store_data(ex_rs2_data), .ex_store_src_addr(ex_rs2_addr),
        .ex_rd_addr(ex_rd_addr),
        .ex_mem_read(ex_mem_read), .ex_mem_write(ex_mem_write),
        .ex_reg_write(ex_reg_write), .ex_wb_sel(ex_wb_sel),
        .mem_valid(mem_valid), .mem_pc(mem_pc),
        .mem_pc_plus4(mem_pc_plus4), .mem_alu_result(mem_alu_result),
        .mem_store_data(mem_store_data),
        .mem_store_src_addr(mem_store_src_addr), .mem_rd_addr(mem_rd_addr),
        .mem_mem_read(mem_mem_read), .mem_mem_write(mem_mem_write),
        .mem_reg_write(mem_reg_write), .mem_wb_sel(mem_wb_sel)
    );

    task eq32;
        input [8*56-1:0] name;
        input [31:0] actual, expected;
        begin
            checks=checks+1;
            if (actual !== expected) begin
                errors=errors+1;
                $display("FAIL %0s at %0t got=%08h expected=%08h",
                         name, $time, actual, expected);
            end
        end
    endtask

    task edge_step;
        begin
            @(posedge clk); #1;
        end
    endtask

    initial begin
        // Synchronous reset clears ALL four pipeline control outputs/regs.
        edge_step();
        eq32("reset PC",if_req_addr,32'h1000);
        eq32("reset suppress IF",{31'd0,if_req_valid},0);
        eq32("reset IFID flush",{31'd0,ifid_flush},1);
        eq32("reset IDEX flush",{31'd0,idex_flush},1);
        eq32("reset IFID invalid",{31'd0,id_valid},0);
        eq32("reset EX invalid",{31'd0,ex_valid},0);
        eq32("reset MEM invalid",{31'd0,mem_valid},0);

        // Two consecutive normal accepted IF requests fill IF/ID and ID/EX.
        @(negedge clk);
        rst=0; if_req_ready=1;
        if_valid=1; if_pc=32'h1000; if_inst=32'h02801401;
        #1;
        eq32("initial request PC",if_req_addr,32'h1000);
        edge_step();
        eq32("request advance +4",if_req_addr,32'h1004);
        eq32("IFID first valid",{31'd0,id_valid},1);
        eq32("IFID first PC",id_pc,32'h1000);

        @(negedge clk);
        if_pc=32'h1004; if_inst=32'h02802002;
        edge_step();
        eq32("PC requests ahead",if_req_addr,32'h1008);
        eq32("IDEX older valid",{31'd0,ex_valid},1);
        eq32("IDEX older PC",ex_pc,32'h1000);
        eq32("IFID younger PC",id_pc,32'h1004);

        // Redirect from EX: kill IFID and IDEX, but older EX goes to EX/MEM.
        @(negedge clk);
        branch_redirect=1; redirect_pc=32'h2000;
        if_pc=32'h1008; if_inst=32'h02803003;
        #1;
        eq32("redirect stalls? no",{31'd0,ifid_stall},0);
        eq32("redirect flush IFID",{31'd0,ifid_flush},1);
        eq32("redirect flush IDEX",{31'd0,idex_flush},1);
        eq32("redirect suppress request",{31'd0,if_req_valid},0);
        eq32("redirect hold advisory",{31'd0,hold_fetch_issue_req},0);
        edge_step();
        eq32("PC redirected",if_req_addr,32'h2000);
        eq32("wrong path IFID killed",{31'd0,id_valid},0);
        eq32("wrong path IDEX killed",{31'd0,ex_valid},0);
        eq32("older EX survives in MEM",{31'd0,mem_valid},1);
        eq32("older EX PC preserved",mem_pc,32'h1000);

        // No adapter acceptance => PC must hold. No fake IF payload.
        @(negedge clk);
        branch_redirect=0; if_req_ready=0; if_valid=0;
        #1;
        eq32("request active",{31'd0,if_req_valid},1);
        edge_step();
        eq32("IF ready zero holds PC",if_req_addr,32'h2000);
        eq32("empty IFID",{31'd0,id_valid},0);

        // Fetch from redirect target, issue two consecutive instructions.
        @(negedge clk);
        if_req_ready=1; if_valid=1;
        if_pc=32'h2000; if_inst=32'h02802804;
        edge_step();
        eq32("target fetch accepted",if_req_addr,32'h2004);
        eq32("target IFID",id_pc,32'h2000);
        @(negedge clk);
        if_pc=32'h2004; if_inst=32'h02802c05;
        edge_step();
        eq32("target next request",if_req_addr,32'h2008);
        eq32("target EX older",ex_pc,32'h2000);
        eq32("target ID younger",id_pc,32'h2004);

        // Hazard: ID is held; bubble is inserted into EX. Redirect is absent.
        // Pausing external issue requires adapter readiness, NOT merely PCU advice.
        @(negedge clk);
        load_use_hazard=1; if_req_ready=0;
        if_valid=1; if_pc=32'h2008; if_inst=32'h02803006;
        #1;
        eq32("hazard IFID stall",{31'd0,ifid_stall},1);
        eq32("hazard no IFID flush",{31'd0,ifid_flush},0);
        eq32("hazard IDEX flush",{31'd0,idex_flush},1);
        eq32("hazard advisory hold",{31'd0,hold_fetch_issue_req},1);
        edge_step();
        eq32("hazard PC held",if_req_addr,32'h2008);
        eq32("hazard IFID remains valid",{31'd0,id_valid},1);
        eq32("hazard IFID PC held",id_pc,32'h2004);
        eq32("hazard IDEX bubble",{31'd0,ex_valid},0);
        eq32("hazard prior EX to MEM",{31'd0,mem_valid},1);
        eq32("hazard MEM PC",mem_pc,32'h2000);

        // Recovery: held instruction advances exactly once; new fetch accepted.
        @(negedge clk);
        load_use_hazard=0; if_req_ready=1;
        #1;
        eq32("after hazard no stall",{31'd0,ifid_stall},0);
        edge_step();
        eq32("recovery PC +4",if_req_addr,32'h200c);
        eq32("recovery EX from held ID",ex_pc,32'h2004);
        eq32("recovery IFID new PC",id_pc,32'h2008);

        // Redirect wins over an asserted load-use signal.
        @(negedge clk);
        branch_redirect=1; redirect_pc=32'h3000;
        load_use_hazard=1; if_req_ready=1;
        #1;
        eq32("priority no IFID stall",{31'd0,ifid_stall},0);
        eq32("priority IFID flush",{31'd0,ifid_flush},1);
        eq32("priority IDEX flush",{31'd0,idex_flush},1);
        eq32("priority hold advisory 0",{31'd0,hold_fetch_issue_req},0);
        edge_step();
        eq32("priority target PC",if_req_addr,32'h3000);
        eq32("priority IFID killed",{31'd0,id_valid},0);
        eq32("priority EX killed",{31'd0,ex_valid},0);
        eq32("priority older EX preserved",{31'd0,mem_valid},1);
        eq32("priority older EX PC",mem_pc,32'h2004);

        // Reset dominates simultaneous redirect and hazard; kills all state.
        @(negedge clk);
        rst=1; branch_redirect=1; load_use_hazard=1;
        #1;
        eq32("reset highest IFID flush",{31'd0,ifid_flush},1);
        eq32("reset highest IDEX flush",{31'd0,idex_flush},1);
        eq32("reset highest hold advisory",{31'd0,hold_fetch_issue_req},1);
        eq32("reset highest no IFID stall",{31'd0,ifid_stall},0);
        edge_step();
        eq32("reset override redirect PC",if_req_addr,32'h1000);
        eq32("reset clears ID",{31'd0,id_valid},0);
        eq32("reset clears EX",{31'd0,ex_valid},0);
        eq32("reset clears MEM",{31'd0,mem_valid},0);
        eq32("reset suppress request",{31'd0,if_req_valid},0);

        $display("-----------------------------------------");
        $display("V0.4 BRANCH REDIRECT + PIPELINE FLUSH PRE-INTEGRATION");
        $display("checks=%0d errors=%0d",checks,errors);
        if (errors==0 && checks >= 55) $display("ALL TESTS PASSED");
        else $display("TESTS FAILED");
        $finish;
    end
    initial begin
        #5000;
        $display("TESTS FAILED: watchdog");
        $finish;
    end
endmodule
