
`timescale 1ns / 1ps

module tb_id_ex_reg;

    reg clk, rst, stall, flush;

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

    // Expected values for all 19 output fields.
    reg ev;
    reg [31:0] epc, epc4, einst;
    reg [4:0] ers1_addr, ers2_addr, erd_addr;
    reg [31:0] ers1_data, ers2_data;
    reg ers1_used, ers2_used;
    reg [31:0] eimm;
    reg [3:0] ealu_op;
    reg ealu_src_imm;
    reg [2:0] ebranch_type;
    reg [1:0] ewb_sel;
    reg ereg_write, emem_read, emem_write;

    integer cases, checks, errors, errors_before;

    // Device Under Test
    id_ex_reg dut (
        .clk(clk),
        .rst(rst),
        .stall(stall),
        .flush(flush),

        .id_valid(id_valid),
        .id_pc(id_pc),
        .id_pc_plus4(id_pc_plus4),
        .id_inst(id_inst),

        .id_rs1_addr(id_rs1_addr),
        .id_rs2_addr(id_rs2_addr),
        .id_rd_addr(id_rd_addr),

        .id_rs1_data(id_rs1_data),
        .id_rs2_data(id_rs2_data),
        .id_rs1_used(id_rs1_used),
        .id_rs2_used(id_rs2_used),

        .id_imm(id_imm),
        .id_alu_op(id_alu_op),
        .id_alu_src_imm(id_alu_src_imm),
        .id_branch_type(id_branch_type),

        .id_wb_sel(id_wb_sel),
        .id_reg_write(id_reg_write),
        .id_mem_read(id_mem_read),
        .id_mem_write(id_mem_write),

        .ex_valid(ex_valid),
        .ex_pc(ex_pc),
        .ex_pc_plus4(ex_pc_plus4),
        .ex_inst(ex_inst),

        .ex_rs1_addr(ex_rs1_addr),
        .ex_rs2_addr(ex_rs2_addr),
        .ex_rd_addr(ex_rd_addr),

        .ex_rs1_data(ex_rs1_data),
        .ex_rs2_data(ex_rs2_data),
        .ex_rs1_used(ex_rs1_used),
        .ex_rs2_used(ex_rs2_used),

        .ex_imm(ex_imm),
        .ex_alu_op(ex_alu_op),
        .ex_alu_src_imm(ex_alu_src_imm),
        .ex_branch_type(ex_branch_type),

        .ex_wb_sel(ex_wb_sel),
        .ex_reg_write(ex_reg_write),
        .ex_mem_read(ex_mem_read),
        .ex_mem_write(ex_mem_write)
    );

    // Prepare different instruction-field combinations.
    // These are storage tests, not instruction execution tests.
    task drive;
        input integer n;
        begin
            id_valid       = (n != 21);
            id_pc          = 32'h1c00_0000 + n * 4;
			id_pc_plus4 = id_pc + 32'd4;
            id_inst        = 32'ha500_0000 ^ n;

            id_rs1_addr    = n;
            id_rs2_addr    = n + 1;
            id_rd_addr     = n + 2;

            id_rs1_data    = 32'h1234_0000 + n;
            id_rs2_data    = 32'h5678_0000 ^ n;
            id_rs1_used    = 1;
            id_rs2_used    = 1;

            id_imm         = 32'hffff_ff00 + n;
            id_alu_op      = n % 12;
            id_alu_src_imm = 0;
            id_branch_type = 0;

            id_wb_sel      = 0;
            id_reg_write   = 1;
            id_mem_read    = 0;
            id_mem_write   = 0;

            case (n % 6)

                0: begin
                    // ALU immediate
                    id_alu_src_imm = 1;
                    id_rs2_used = 0;
                end

                1: begin
                    // LD.W
                    id_mem_read = 1;
                    id_wb_sel = 1;
                    id_alu_src_imm = 1;
                    id_rs2_used = 0;
                end

                2: begin
                    // ST.W: preserve store-data operand
                    id_mem_write = 1;
                    id_reg_write = 0;
                    id_alu_src_imm = 1;
                end

                3: begin
                    // Conditional branch
                    id_branch_type = 1;
                    id_reg_write = 0;
                end

                4: begin
                    // BL: link address PC+4 to r1
                    id_branch_type = 4;
                    id_wb_sel = 2;
                    id_rd_addr = 1;
                    id_rs1_used = 0;
                    id_rs2_used = 0;
                end

                5: begin
                    // JIRL: link address PC+4
                    id_branch_type = 5;
                    id_wb_sel = 2;
                    id_rs2_used = 0;
                end

            endcase
        end
    endtask

    // Check one output field.
    task check_field;
        input [8*24-1:0] field_name;
        input [31:0] got;
        input [31:0] expected;
        begin
            checks = checks + 1;

            if (got !== expected) begin
                errors = errors + 1;
                $display(
                    "  FAIL %0s: got=%h expected=%h",
                    field_name, got, expected
                );
            end
        end
    endtask

    // Perform one clock cycle and check all outputs.
    task step;
        input [8*48-1:0] case_name;
        begin
            #2;

            // Reference model priority:
            // reset > flush > stall > capture

            if (rst || flush) begin
                {
                    ev, epc, epc4, einst,
                    ers1_addr, ers2_addr, erd_addr,
                    ers1_data, ers2_data,
                    ers1_used, ers2_used,
                    eimm, ealu_op, ealu_src_imm,
                    ebranch_type, ewb_sel,
                    ereg_write, emem_read, emem_write
                } = 223'd0;
            end

            else if (!stall) begin
                {
                    ev, epc, epc4, einst,
                    ers1_addr, ers2_addr, erd_addr,
                    ers1_data, ers2_data,
                    ers1_used, ers2_used,
                    eimm, ealu_op, ealu_src_imm,
                    ebranch_type, ewb_sel,
                    ereg_write, emem_read, emem_write
                } = {
                    id_valid, id_pc, id_pc_plus4, id_inst,
                    id_rs1_addr, id_rs2_addr, id_rd_addr,
                    id_rs1_data, id_rs2_data,
                    id_rs1_used, id_rs2_used,
                    id_imm, id_alu_op, id_alu_src_imm,
                    id_branch_type, id_wb_sel,
                    id_reg_write, id_mem_read, id_mem_write
                };
            end

            // stall=1: expected values remain unchanged.

            clk = 1;
            #1;

            cases = cases + 1;
            errors_before = errors;

            check_field("valid", ex_valid, ev);
           check_field("pc", ex_pc, epc);
           check_field("pc_plus4", ex_pc_plus4, epc4);
           check_field("inst", ex_inst, einst);

            check_field(
                "rs1_addr", ex_rs1_addr, ers1_addr
            );
            check_field(
                "rs2_addr", ex_rs2_addr, ers2_addr
            );
            check_field(
                "rd_addr", ex_rd_addr, erd_addr
            );

            check_field(
                "rs1_data", ex_rs1_data, ers1_data
            );
            check_field(
                "rs2_data", ex_rs2_data, ers2_data
            );

            check_field(
                "rs1_used", ex_rs1_used, ers1_used
            );
            check_field(
                "rs2_used", ex_rs2_used, ers2_used
            );

            check_field("imm", ex_imm, eimm);
            check_field("alu_op", ex_alu_op, ealu_op);

            check_field(
                "alu_src_imm",
                ex_alu_src_imm,
                ealu_src_imm
            );

            check_field(
                "branch_type",
                ex_branch_type,
                ebranch_type
            );

            check_field("wb_sel", ex_wb_sel, ewb_sel);

            check_field(
                "reg_write",
                ex_reg_write,
                ereg_write
            );

            check_field(
                "mem_read",
                ex_mem_read,
                emem_read
            );

            check_field(
                "mem_write",
                ex_mem_write,
                emem_write
            );

            if (errors == errors_before)
                $display(
                    "PASS [%0d] %0s",
                    cases, case_name
                );
            else
                $display(
                    "FAIL [%0d] %0s",
                    cases, case_name
                );

            clk = 0;
            #2;
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        stall = 0;
        flush = 0;

        cases = 0;
        checks = 0;
        errors = 0;

        // Case 01: Reset
        drive(1);
        step("01 reset startup");

        // Case 02: Normal field capture
        rst = 0;
        drive(1);
        step("02 LD.W field capture");

        // Case 03: Store fields
        drive(2);
        step("03 ST.W field capture");

        // Case 04: Branch fields
        drive(3);
        step("04 branch field capture");

        // Case 05: BL link fields
        drive(4);
        step("05 BL link field capture");

        // Case 06: JIRL link fields
        drive(5);
        step("06 JIRL link field capture");

        // Case 07: ALU immediate
        drive(6);
        step("07 ALU immediate capture");

        // Case 08: Stall must retain old data
        stall = 1;
        drive(7);
        step("08 stall holds prior values");

        // Case 09: Flush overrides stall
        flush = 1;
        drive(8);
        step("09 flush wins over stall");

        // Case 10: Stall keeps the bubble
        flush = 0;
        drive(9);
        step("10 stall holds cleared bubble");

        // Case 11: Resume
        stall = 0;
        drive(10);
        step("11 resume after stall");

        // Case 12: Reset with stall
        stall = 1;
        rst = 1;
        drive(11);
        step("12 reset wins over stall");

        // Case 13: Resume after reset
        rst = 0;
        stall = 0;
        drive(12);
        step("13 resume after reset");

        // Case 14: Reset, flush and stall together
        rst = 1;
        flush = 1;
        stall = 1;
        drive(13);
        step("14 reset flush stall together");

        // Case 15: Flush alone
        rst = 0;
        stall = 0;
        drive(14);
        step("15 flush alone clears fields");

        // Case 16: Capture after flush
        flush = 0;
        drive(15);
        step("16 capture after flush");

        // Case 17: Stall while inputs change
        stall = 1;
        drive(16);
        step("17 hold when inputs change");

        // Case 18: Invalid instruction bubble
        stall = 0;
        drive(21);
        step("18 invalid ID bubble capture");

        // Case 19: New load
        drive(18);
        step("19 LD.W field recapture");

        // Case 20: Final field capture
        drive(19);
        step("20 final field capture");

        $display("----------------------------------------");

        $display(
            "Total cases = %0d, field checks = %0d, errors = %0d",
            cases, checks, errors
        );

        if (cases == 20 && checks == 380 && errors == 0)
            $display(
                "ALL TESTS PASSED (20 cases, 380 field checks)"
            );
        else
            $display("TESTS FAILED");

        $finish;
    end

endmodule
