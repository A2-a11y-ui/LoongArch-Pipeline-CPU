`timescale 1ns / 1ps

// Vivado 2019.1 / Verilog-2001 self-checking testbench.
// Run standalone with rtl/common/load_use_hazard_unit.v.
// 40 directed cases x 4 output checks = 160 signal checks.
module tb_load_use_hazard_unit;
    reg        id_valid;
    reg [4:0]  id_rs1_addr;
    reg [4:0]  id_rs2_addr;
    reg        id_rs1_used;
    reg        id_rs2_used;
    reg        ex_valid;
    reg        ex_mem_read;
    reg [4:0]  ex_rd_addr;

    wire load_use_hazard;
    wire hold_if_req;
    wire hold_ifid_req;
    wire bubble_idex_req;

    integer cases;
    integer checks;
    integer errors;

    load_use_hazard_unit dut (
        .id_valid(id_valid),
        .id_rs1_addr(id_rs1_addr),
        .id_rs2_addr(id_rs2_addr),
        .id_rs1_used(id_rs1_used),
        .id_rs2_used(id_rs2_used),
        .ex_valid(ex_valid),
        .ex_mem_read(ex_mem_read),
        .ex_rd_addr(ex_rd_addr),
        .load_use_hazard(load_use_hazard),
        .hold_if_req(hold_if_req),
        .hold_ifid_req(hold_ifid_req),
        .bubble_idex_req(bubble_idex_req)
    );

    task check_case;
        input [8*48-1:0] case_name;
        input          t_id_valid;
        input [4:0]    t_rs1;
        input [4:0]    t_rs2;
        input          t_rs1_used;
        input          t_rs2_used;
        input          t_ex_valid;
        input          t_ex_mem_read;
        input [4:0]    t_ex_rd;
        input          expected;
        integer this_errors;
        begin
            id_valid    = t_id_valid;
            id_rs1_addr = t_rs1;
            id_rs2_addr = t_rs2;
            id_rs1_used = t_rs1_used;
            id_rs2_used = t_rs2_used;
            ex_valid    = t_ex_valid;
            ex_mem_read = t_ex_mem_read;
            ex_rd_addr  = t_ex_rd;
            #1; // Allow combinational logic to settle.

            cases = cases + 1;
            checks = checks + 4;
            this_errors = 0;

            if (load_use_hazard !== expected) this_errors = this_errors + 1;
            if (hold_if_req     !== expected) this_errors = this_errors + 1;
            if (hold_ifid_req   !== expected) this_errors = this_errors + 1;
            if (bubble_idex_req !== expected) this_errors = this_errors + 1;

            errors = errors + this_errors;
            if (this_errors == 0)
                $display("PASS [%0d] %0s", cases, case_name);
            else
                $display("FAIL [%0d] %0s: expected=%b got hazard=%b hold_if=%b hold_ifid=%b bubble_idex=%b",
                         cases, case_name, expected, load_use_hazard,
                         hold_if_req, hold_ifid_req, bubble_idex_req);
        end
    endtask

    initial begin
        cases = 0;
        checks = 0;
        errors = 0;
        id_valid = 0; id_rs1_addr = 0; id_rs2_addr = 0;
        id_rs1_used = 0; id_rs2_used = 0;
        ex_valid = 0; ex_mem_read = 0; ex_rd_addr = 0;

        // Arguments: name, id_valid, rs1, rs2, used1, used2,
        //            ex_valid, ex_mem_read, ex_rd, expected_hazard.
        check_case("idle_no_instruction", 1'b0, 5'd0, 5'd0, 1'b0, 1'b0, 1'b0, 1'b0, 5'd0, 1'b0);
        check_case("rs1_exact_match", 1'b1, 5'd3, 5'd8, 1'b1, 1'b1, 1'b1, 1'b1, 5'd3, 1'b1);
        check_case("rs2_exact_match", 1'b1, 5'd8, 5'd3, 1'b1, 1'b1, 1'b1, 1'b1, 5'd3, 1'b1);
        check_case("both_sources_match", 1'b1, 5'd3, 5'd3, 1'b1, 1'b1, 1'b1, 1'b1, 5'd3, 1'b1);
        check_case("both_sources_mismatch", 1'b1, 5'd4, 5'd5, 1'b1, 1'b1, 1'b1, 1'b1, 5'd3, 1'b0);
        check_case("invalid_id_rs1_match", 1'b0, 5'd3, 5'd9, 1'b1, 1'b0, 1'b1, 1'b1, 5'd3, 1'b0);
        check_case("invalid_ex_rs1_match", 1'b1, 5'd3, 5'd9, 1'b1, 1'b0, 1'b0, 1'b1, 5'd3, 1'b0);
        check_case("ex_nonload_rs1_match", 1'b1, 5'd3, 5'd9, 1'b1, 1'b0, 1'b1, 1'b0, 5'd3, 1'b0);
        check_case("zero_destination_both_r0", 1'b1, 5'd0, 5'd0, 1'b1, 1'b1, 1'b1, 1'b1, 5'd0, 1'b0);
        check_case("unused_rs1_same_bits", 1'b1, 5'd3, 5'd9, 1'b0, 1'b0, 1'b1, 1'b1, 5'd3, 1'b0);
        check_case("unused_rs2_same_bits", 1'b1, 5'd9, 5'd3, 1'b0, 1'b0, 1'b1, 1'b1, 5'd3, 1'b0);
        check_case("both_unused_same_bits", 1'b1, 5'd3, 5'd3, 1'b0, 1'b0, 1'b1, 1'b1, 5'd3, 1'b0);
        check_case("only_rs1_used_rs2_match", 1'b1, 5'd4, 5'd3, 1'b1, 1'b0, 1'b1, 1'b1, 5'd3, 1'b0);
        check_case("only_rs2_used_rs1_match", 1'b1, 5'd3, 5'd4, 1'b0, 1'b1, 1'b1, 1'b1, 5'd3, 1'b0);
        check_case("store_data_from_rd", 1'b1, 5'd8, 5'd6, 1'b1, 1'b1, 1'b1, 1'b1, 5'd6, 1'b1);
        check_case("beq_second_src_from_rd", 1'b1, 5'd8, 5'd6, 1'b1, 1'b1, 1'b1, 1'b1, 5'd6, 1'b1);
        check_case("branch_compare_rs1", 1'b1, 5'd6, 5'd8, 1'b1, 1'b1, 1'b1, 1'b1, 5'd6, 1'b1);
        check_case("lu12i_no_sources", 1'b1, 5'd6, 5'd6, 1'b0, 1'b0, 1'b1, 1'b1, 5'd6, 1'b0);
        check_case("ld_base_register_dep", 1'b1, 5'd6, 5'd0, 1'b1, 1'b0, 1'b1, 1'b1, 5'd6, 1'b1);
        check_case("addi_base_dep", 1'b1, 5'd6, 5'd0, 1'b1, 1'b0, 1'b1, 1'b1, 5'd6, 1'b1);
        check_case("shift_immediate_rs1_dep", 1'b1, 5'd6, 5'd0, 1'b1, 1'b0, 1'b1, 1'b1, 5'd6, 1'b1);
        check_case("highest_register_31_dep", 1'b1, 5'd31, 5'd0, 1'b1, 1'b0, 1'b1, 1'b1, 5'd31, 1'b1);
        check_case("lowest_writable_register_1", 1'b1, 5'd1, 5'd0, 1'b1, 1'b0, 1'b1, 1'b1, 5'd1, 1'b1);
        check_case("r30_vs_r31_no_dep", 1'b1, 5'd30, 5'd0, 1'b1, 1'b0, 1'b1, 1'b1, 5'd31, 1'b0);
        check_case("unused_zero_rs1_vs_r7", 1'b1, 5'd0, 5'd5, 1'b1, 1'b0, 1'b1, 1'b1, 5'd7, 1'b0);
        check_case("unused_zero_rs2_vs_r7", 1'b1, 5'd5, 5'd0, 1'b0, 1'b1, 1'b1, 1'b1, 5'd7, 1'b0);
        check_case("r0_dest_zero_rs1_used", 1'b1, 5'd0, 5'd4, 1'b1, 1'b0, 1'b1, 1'b1, 5'd0, 1'b0);
        check_case("r0_dest_zero_rs2_used", 1'b1, 5'd4, 5'd0, 1'b0, 1'b1, 1'b1, 1'b1, 5'd0, 1'b0);
        check_case("invalid_id_both_match", 1'b0, 5'd3, 5'd3, 1'b1, 1'b1, 1'b1, 1'b1, 5'd3, 1'b0);
        check_case("invalid_ex_both_match", 1'b1, 5'd3, 5'd3, 1'b1, 1'b1, 1'b0, 1'b1, 5'd3, 1'b0);
        check_case("ex_alu_both_match", 1'b1, 5'd3, 5'd3, 1'b1, 1'b1, 1'b1, 1'b0, 5'd3, 1'b0);
        check_case("rs2_dep_rs1_mismatch", 1'b1, 5'd7, 5'd6, 1'b1, 1'b1, 1'b1, 1'b1, 5'd6, 1'b1);
        check_case("rs1_dep_rs2_mismatch", 1'b1, 5'd6, 5'd7, 1'b1, 1'b1, 1'b1, 1'b1, 5'd6, 1'b1);
        check_case("zero_dest_nonzero_sources", 1'b1, 5'd7, 5'd8, 1'b1, 1'b1, 1'b1, 1'b1, 5'd0, 1'b0);
        check_case("load_to_andi_rs1", 1'b1, 5'd5, 5'd0, 1'b1, 1'b0, 1'b1, 1'b1, 5'd5, 1'b1);
        check_case("load_to_branch_b_unused", 1'b1, 5'd5, 5'd0, 1'b0, 1'b0, 1'b1, 1'b1, 5'd5, 1'b0);
        check_case("dynamic_set_hazard", 1'b1, 5'd20, 5'd21, 1'b1, 1'b1, 1'b1, 1'b1, 5'd20, 1'b1);
        check_case("dynamic_clear_hazard", 1'b1, 5'd22, 5'd21, 1'b1, 1'b1, 1'b1, 1'b1, 5'd20, 1'b0);
        check_case("dynamic_set_other_source", 1'b1, 5'd22, 5'd20, 1'b1, 1'b1, 1'b1, 1'b1, 5'd20, 1'b1);
        check_case("dynamic_clear_invalid_load", 1'b1, 5'd22, 5'd20, 1'b1, 1'b1, 1'b0, 1'b1, 5'd20, 1'b0);

        $display("---------------------------------------------------");
        $display("Total cases = %0d, signal checks = %0d, errors = %0d",
                 cases, checks, errors);
        if (cases == 40 && checks == 160 && errors == 0)
            $display("ALL TESTS PASSED (40 cases, 160 signal checks)");
        else
            $display("TESTS FAILED: cases=%0d, checks=%0d, errors=%0d",
                     cases, checks, errors);
        $finish;
    end
endmodule
