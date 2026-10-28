
`timescale 1ns / 1ps

module tb_branch_unit;

    reg [2:0]  branch_type;
    reg [31:0] pc;
    reg [31:0] rs1_data;
    reg [31:0] rs2_data;
    reg [31:0] branch_imm;

    wire        redirect;
    wire [31:0] target_pc;

    integer errors;
    integer checks;

    // Instantiate Branch Unit
    branch_unit uut (
        .branch_type(branch_type),
        .pc(pc),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .branch_imm(branch_imm),
        .redirect(redirect),
        .target_pc(target_pc)
    );

    // Automatic checking task
    task check_branch;
        input [2:0]  t;
        input [31:0] pc_in;
        input [31:0] a_in;
        input [31:0] b_in;
        input [31:0] imm_in;
        input        expected_redirect;
        input [31:0] expected_target;

        begin
            branch_type = t;
            pc          = pc_in;
            rs1_data    = a_in;
            rs2_data    = b_in;
            branch_imm  = imm_in;

            #1;
            checks = checks + 1;

            if ((redirect !== expected_redirect) ||
                (target_pc !== expected_target)) begin

                errors = errors + 1;

                $display(
                    "FAIL: type=%d pc=%h a=%h b=%h imm=%h redirect=%b target=%h expected_redirect=%b expected_target=%h",
                    t, pc_in, a_in, b_in, imm_in,
                    redirect, target_pc,
                    expected_redirect, expected_target
                );
            end
            else begin
                $display(
                    "PASS: type=%d redirect=%b target=%h",
                    t, redirect, target_pc
                );
            end
        end
    endtask

    initial begin

        errors = 0;
        checks = 0;

        branch_type = 0;
        pc = 0;
        rs1_data = 0;
        rs2_data = 0;
        branch_imm = 0;

        // 1. NONE: no redirect
        check_branch(3'd0, 32'h100, 32'd1, 32'd1,
                     32'h8, 1'b0, 32'h0);

        // 2. BEQ: equal, branch taken
        check_branch(3'd1, 32'h100, 32'd5, 32'd5,
                     32'h8, 1'b1, 32'h108);

        // 3. BEQ: not equal
        check_branch(3'd1, 32'h100, 32'd5, 32'd6,
                     32'h8, 1'b0, 32'h0);

        // 4. BNE: not equal, branch taken
        check_branch(3'd2, 32'h100, 32'd5, 32'd6,
                     32'h8, 1'b1, 32'h108);

        // 5. BNE: equal, no branch
        check_branch(3'd2, 32'h100, 32'd5, 32'd5,
                     32'h8, 1'b0, 32'h0);

        // 6. B: unconditional forward branch
        check_branch(3'd3, 32'h200, 0, 0,
                     32'h14, 1'b1, 32'h214);

        // 7. BL: unconditional forward branch
        check_branch(3'd4, 32'h300, 0, 0,
                     32'h8, 1'b1, 32'h308);

        // 8. JIRL: register-based target
        check_branch(3'd5, 32'h400, 32'h1000, 0,
                     32'hC, 1'b1, 32'h100C);

        // 9. BEQ: negative offset
        check_branch(3'd1, 32'h100, 7, 7,
                     32'hFFFFFFF8, 1'b1, 32'hF8);

        // 10. BNE: negative offset
        check_branch(3'd2, 32'h100, 7, 8,
                     32'hFFFFFFFC, 1'b1, 32'hFC);

        // 11. B: backward branch
        check_branch(3'd3, 32'h80, 0, 0,
                     32'hFFFFFFE0, 1'b1, 32'h60);

        // 12. BL: backward branch
        check_branch(3'd4, 32'h100, 0, 0,
                     32'hFFFFFFC0, 1'b1, 32'hC0);

        // 13. JIRL: negative offset
        check_branch(3'd5, 32'h400, 32'h200, 0,
                     32'hFFFFFFF8, 1'b1, 32'h1F8);

        // 14. B: zero offset
        check_branch(3'd3, 32'h100, 0, 0,
                     32'h0, 1'b1, 32'h100);

        // 15. JIRL: zero offset
        check_branch(3'd5, 32'h400, 32'h1000, 0,
                     32'h0, 1'b1, 32'h1000);

        // 16. Reserved branch type 6
        check_branch(3'd6, 32'h100, 0, 0,
                     32'h8, 1'b0, 32'h0);

        // 17. Reserved branch type 7
        check_branch(3'd7, 32'h100, 0, 0,
                     32'h8, 1'b0, 32'h0);

        // 18. 32-bit address wraparound
        check_branch(3'd3, 32'hFFFFFFFC, 0, 0,
                     32'h8, 1'b1, 32'h4);

        // 19. BEQ: both operands zero
        check_branch(3'd1, 32'h0, 0, 0,
                     32'h0, 1'b1, 32'h0);

        // 20. JIRL must use rs1_data, not PC
        check_branch(3'd5, 32'h1000, 32'h2000, 0,
                     32'h4, 1'b1, 32'h2004);

        // Final result
        if (errors == 0)
            $display("ALL TESTS PASSED (%0d checks)", checks);
        else
            $display("TESTS FAILED: %0d errors", errors);

        $finish;

    end

endmodule
