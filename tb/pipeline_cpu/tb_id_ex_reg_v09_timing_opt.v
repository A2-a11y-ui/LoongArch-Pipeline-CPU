`timescale 1ns / 1ps

module tb_id_ex_reg_v09_timing_opt;

    reg clk;
    always #5 clk = ~clk;

    reg rst, stall, flush;
    reg id_valid;
    reg [31:0] id_pc, id_pc_plus4, id_inst;
    reg [4:0] id_rs1_addr, id_rs2_addr, id_rd_addr;
    reg [31:0] id_rs1_data, id_rs2_data;
    reg id_rs1_used, id_rs2_used;
    reg [31:0] id_imm;
    reg [3:0] id_alu_op;
    reg id_alu_src_imm;
    reg [2:0] id_branch_type;
    reg [1:0] id_wb_sel;
    reg id_reg_write, id_mem_read, id_mem_write;

    wire ex_valid;
    wire [31:0] ex_pc, ex_pc_plus4, ex_inst;
    wire [4:0] ex_rs1_addr, ex_rs2_addr, ex_rd_addr;
    wire [31:0] ex_rs1_data, ex_rs2_data;
    wire ex_rs1_used, ex_rs2_used;
    wire [31:0] ex_imm;
    wire [3:0] ex_alu_op;
    wire ex_alu_src_imm;
    wire [2:0] ex_branch_type;
    wire [1:0] ex_wb_sel;
    wire ex_reg_write, ex_mem_read, ex_mem_write;

    integer checks;
    integer errors;

    id_ex_reg dut (
        .clk(clk), .rst(rst), .stall(stall), .flush(flush),
        .id_valid(id_valid),
        .id_pc(id_pc), .id_pc_plus4(id_pc_plus4), .id_inst(id_inst),
        .id_rs1_addr(id_rs1_addr), .id_rs2_addr(id_rs2_addr),
        .id_rd_addr(id_rd_addr),
        .id_rs1_data(id_rs1_data), .id_rs2_data(id_rs2_data),
        .id_rs1_used(id_rs1_used), .id_rs2_used(id_rs2_used),
        .id_imm(id_imm), .id_alu_op(id_alu_op),
        .id_alu_src_imm(id_alu_src_imm), .id_branch_type(id_branch_type),
        .id_wb_sel(id_wb_sel), .id_reg_write(id_reg_write),
        .id_mem_read(id_mem_read), .id_mem_write(id_mem_write),
        .ex_valid(ex_valid),
        .ex_pc(ex_pc), .ex_pc_plus4(ex_pc_plus4), .ex_inst(ex_inst),
        .ex_rs1_addr(ex_rs1_addr), .ex_rs2_addr(ex_rs2_addr),
        .ex_rd_addr(ex_rd_addr),
        .ex_rs1_data(ex_rs1_data), .ex_rs2_data(ex_rs2_data),
        .ex_rs1_used(ex_rs1_used), .ex_rs2_used(ex_rs2_used),
        .ex_imm(ex_imm), .ex_alu_op(ex_alu_op),
        .ex_alu_src_imm(ex_alu_src_imm), .ex_branch_type(ex_branch_type),
        .ex_wb_sel(ex_wb_sel), .ex_reg_write(ex_reg_write),
        .ex_mem_read(ex_mem_read), .ex_mem_write(ex_mem_write)
    );

    task check;
        input condition;
        input [8*96-1:0] label_text;
        begin
            checks = checks + 1;
            if (!condition) begin
                errors = errors + 1;
                $display("FAIL: %0s", label_text);
            end else begin
                $display("PASS: %0s", label_text);
            end
        end
    endtask

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        clk=1'b0;
        checks=0;
        errors=0;
        rst=0; stall=0; flush=0; id_valid=0;
        id_pc=0; id_pc_plus4=0; id_inst=0;
        id_rs1_addr=0; id_rs2_addr=0; id_rd_addr=0;
        id_rs1_data=0; id_rs2_data=0;
        id_rs1_used=0; id_rs2_used=0;
        id_imm=0; id_alu_op=0; id_alu_src_imm=0;
        id_branch_type=0; id_wb_sel=0;
        id_reg_write=0; id_mem_read=0; id_mem_write=0;

        // 1. Reset clears valid and all payload fields.
        rst=1;
        tick();
        check(ex_valid === 1'b0, "reset clears ex_valid");
        check(ex_pc === 32'd0 && ex_inst === 32'd0 &&
              ex_rs1_data === 32'd0 && ex_imm === 32'd0,
              "reset clears representative payload fields");
        check(ex_reg_write === 1'b0 && ex_mem_read === 1'b0 &&
              ex_mem_write === 1'b0 && ex_branch_type === 3'd0,
              "reset clears side-effect control fields");

        // 2. Normal capture.
        rst=0; stall=0; flush=0; id_valid=1;
        id_pc=32'h00001000; id_pc_plus4=32'h00001004;
        id_inst=32'h02800000;
        id_rs1_addr=5'd3; id_rs2_addr=5'd4; id_rd_addr=5'd5;
        id_rs1_data=32'h11223344; id_rs2_data=32'h55667788;
        id_rs1_used=1; id_rs2_used=1;
        id_imm=32'h00000020; id_alu_op=4'h3;
        id_alu_src_imm=1; id_branch_type=3'd0;
        id_wb_sel=2'd0; id_reg_write=1;
        id_mem_read=0; id_mem_write=0;
        tick();
        check(ex_valid === 1'b1, "normal capture sets ex_valid");
        check(ex_pc === 32'h00001000 && ex_pc_plus4 === 32'h00001004 &&
              ex_inst === 32'h02800000, "normal capture transfers PC and instruction");
        check(ex_rs1_data === 32'h11223344 &&
              ex_rs2_data === 32'h55667788 &&
              ex_imm === 32'h00000020, "normal capture transfers operands and immediate");
        check(ex_rd_addr === 5'd5 && ex_reg_write === 1'b1,
              "normal capture transfers destination and write control");

        // 3. Flush invalidates the slot, while the wide payload bank is not
        // cleared; it may capture the current ID payload on this edge.
        flush=1; id_valid=1;
        id_pc=32'h00002000; id_inst=32'h58000000;
        id_rs1_data=32'hA5A5A5A5; id_imm=32'h00000100;
        id_branch_type=3'd1; id_reg_write=0;
        tick();
        check(ex_valid === 1'b0, "flush clears ex_valid");
        check(ex_pc === 32'h00002000 && ex_inst === 32'h58000000 &&
              ex_rs1_data === 32'hA5A5A5A5 && ex_imm === 32'h00000100,
              "flush does not reset wide payload bank");
        check(ex_branch_type === 3'd1 && ex_reg_write === 1'b0,
              "flushed payload remains invalid and has no write enable");

        // 4. Stall holds payload and the invalid valid-bit.
        flush=0; stall=1;
        id_pc=32'h00003000; id_inst=32'hFFFFFFFF;
        id_rs1_data=32'hFFFFFFFF; id_imm=32'hFFFFFFFF; id_valid=1;
        tick();
        check(ex_valid === 1'b0, "stall holds invalid ex_valid");
        check(ex_pc === 32'h00002000 && ex_inst === 32'h58000000 &&
              ex_rs1_data === 32'hA5A5A5A5 && ex_imm === 32'h00000100,
              "stall holds payload fields");

        // 5. Capture resumes when stall is released.
        stall=0; id_valid=1;
        id_pc=32'h00004000; id_inst=32'h12345678;
        id_rs1_data=32'hCAFEBABE; id_imm=32'h00000044;
        id_branch_type=0; id_reg_write=1;
        tick();
        check(ex_valid === 1'b1, "capture after stall restores ex_valid");
        check(ex_pc === 32'h00004000 && ex_inst === 32'h12345678 &&
              ex_rs1_data === 32'hCAFEBABE && ex_imm === 32'h00000044,
              "capture after stall updates payload");

        // 6. Flush has priority over stall for the valid bit; payload holds.
        flush=1; stall=1; id_valid=1;
        id_pc=32'h00005000; id_inst=32'hAAAAAAAA;
        tick();
        check(ex_valid === 1'b0, "flush clears valid even when stalled");
        check(ex_pc === 32'h00004000 && ex_inst === 32'h12345678,
              "payload holds when flush and stall are both asserted");

        $display("--------------------------------------------------");
        $display("ID_EX_TIMING_OPT: CHECKS=%0d ERRORS=%0d", checks, errors);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end

endmodule
