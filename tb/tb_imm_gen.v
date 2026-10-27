
`timescale 1ns / 1ps

module tb_imm_gen;

    reg  [31:0] inst;
    reg  [2:0]  imm_sel;
    wire [31:0] imm;

    integer errors;
    integer tests;

    // 实例化立即数生成器
    imm_gen uut (
        .inst    (inst),
        .imm_sel (imm_sel),
        .imm     (imm)
    );

    // 自动测试任务：输入指令位模式、选择码和预期结果
    task check_case;
        input [31:0] test_inst;
        input [2:0]  test_sel;
        input [31:0] expected;
        begin
            inst    = test_inst;
            imm_sel = test_sel;
            #1;

            tests = tests + 1;

            if (imm !== expected) begin
                $display(
                    "[FAIL] sel=%0d inst=%h expected=%h actual=%h",
                    test_sel, test_inst, expected, imm
                );
                errors = errors + 1;
            end
            else begin
                $display(
                    "[PASS] sel=%0d inst=%h imm=%h",
                    test_sel, test_inst, imm
                );
            end
        end
    endtask

    initial begin
        inst    = 32'b0;
        imm_sel = 3'd0;
        errors  = 0;
        tests   = 0;

        $display("========================================");
        $display("       IMM_GEN TEST START");
        $display("========================================");

        // 1. 无立即数
        check_case(32'hFFFFFFFF, 3'd0, 32'h00000000);

        // 2-5. 有符号 12 位立即数
        // inst[21:10] = 0
        check_case({10'b0, 12'h000, 10'b0},
                   3'd1, 32'h00000000);

        // 最大正数：2047
        check_case({10'b0, 12'h7FF, 10'b0},
                   3'd1, 32'h000007FF);

        // 最小负数：-2048
        check_case({10'b0, 12'h800, 10'b0},
                   3'd1, 32'hFFFFF800);

        // -1
        check_case({10'b0, 12'hFFF, 10'b0},
                   3'd1, 32'hFFFFFFFF);

        // 6-8. 无符号 12 位立即数
        check_case({10'b0, 12'h000, 10'b0},
                   3'd2, 32'h00000000);

        check_case({10'b0, 12'h800, 10'b0},
                   3'd2, 32'h00000800);

        check_case({10'b0, 12'hFFF, 10'b0},
                   3'd2, 32'h00000FFF);

        // 9-12. 无符号 5 位移位量
        check_case({17'b0, 5'd0, 10'b0},
                   3'd3, 32'h00000000);

        check_case({17'b0, 5'd1, 10'b0},
                   3'd3, 32'h00000001);

        check_case({17'b0, 5'd15, 10'b0},
                   3'd3, 32'h0000000F);

        check_case({17'b0, 5'd31, 10'b0},
                   3'd3, 32'h0000001F);

        // 13-16. 高 20 位立即数构造
        check_case({7'b0, 20'h00000, 5'b0},
                   3'd4, 32'h00000000);

        check_case({7'b0, 20'h00001, 5'b0},
                   3'd4, 32'h00001000);

        check_case({7'b0, 20'h80000, 5'b0},
                   3'd4, 32'h80000000);

        check_case({7'b0, 20'hFFFFF, 5'b0},
                   3'd4, 32'hFFFFF000);

        // 17-19. 保留选择码：当前版本规定输出 0
        check_case(32'hFFFFFFFF, 3'd5, 32'h00000000);
        check_case(32'hFFFFFFFF, 3'd6, 32'h00000000);
        check_case(32'hFFFFFFFF, 3'd7, 32'h00000000);

        // 汇总测试结果
        $display("========================================");
        $display("Total tests : %0d", tests);
        $display("Total errors: %0d", errors);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");

        $display("========================================");

        $finish;
    end

endmodule
