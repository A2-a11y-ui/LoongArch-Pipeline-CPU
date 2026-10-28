`timescale 1ns / 1ps
// Regression suite: V1.1 formats + LoongArch branch offsets (V2).
// This testbench does NOT require decoder, ALU or pc_reg.
module tb_imm_gen_branch;
    reg  [31:0] inst;
    reg  [2:0] imm_sel;
    wire [31:0] imm;
    integer tests;
    integer errors;

    imm_gen dut (
        .inst(inst),
        .imm_sel(imm_sel),
        .imm(imm)
    );

    task check;
        input [8*32-1:0] name;
        input [31:0] ins;
        input [2:0] sel;
        input [31:0] expected;
        begin
            inst = ins;
            imm_sel = sel;
            #1;
            tests = tests + 1;
            if (imm !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s inst=%08h sel=%0d got=%08h expected=%08h",
                         name, inst, sel, imm, expected);
            end
            else
                $display("PASS %0s inst=%08h sel=%0d imm=%08h", name, inst, sel, imm);
        end
    endtask

    initial begin
        inst = 32'd0;
        imm_sel = 3'd0;
        tests = 0;
        errors = 0;
        check("NONE_ZERO", 32'h00000000, 3'd0, 32'h00000000);
        check("NONE_NONZERO", 32'hFFFFFFFF, 3'd0, 32'h00000000);
        check("S12_000", 32'h00000000, 3'd1, 32'h00000000);
        check("S12_7FF", 32'h001FFC00, 3'd1, 32'h000007FF);
        check("S12_800", 32'h00200000, 3'd1, 32'hFFFFF800);
        check("S12_FFF", 32'h003FFC00, 3'd1, 32'hFFFFFFFF);
        check("S12_001", 32'h00000400, 3'd1, 32'h00000001);
        check("U12_000", 32'h00000000, 3'd2, 32'h00000000);
        check("U12_800", 32'h00200000, 3'd2, 32'h00000800);
        check("U12_FFF", 32'h003FFC00, 3'd2, 32'h00000FFF);
        check("U12_001", 32'h00000400, 3'd2, 32'h00000001);
        check("U5_0", 32'h00000000, 3'd3, 32'h00000000);
        check("U5_1", 32'h00000400, 3'd3, 32'h00000001);
        check("U5_15", 32'h00003C00, 3'd3, 32'h0000000F);
        check("U5_31", 32'h00007C00, 3'd3, 32'h0000001F);
        check("U20_00000", 32'h00000000, 3'd4, 32'h00000000);
        check("U20_00001", 32'h00000020, 3'd4, 32'h00001000);
        check("U20_80000", 32'h01000000, 3'd4, 32'h80000000);
        check("U20_FFFFF", 32'h01FFFFE0, 3'd4, 32'hFFFFF000);
        check("U20_12345", 32'h002468A0, 3'd4, 32'h12345000);
        check("RESERVED_7_ZERO", 32'h00000000, 3'd7, 32'h00000000);
        check("RESERVED_7_ALL", 32'hFFFFFFFF, 3'd7, 32'h00000000);
        check("B16_0000", 32'h58000155, 3'd5, 32'h00000000);
        check("B16_0001", 32'h58000555, 3'd5, 32'h00000004);
        check("B16_7FFF", 32'h59FFFD55, 3'd5, 32'h0001FFFC);
        check("B16_8000", 32'h5A000155, 3'd5, 32'hFFFE0000);
        check("B16_FFFF", 32'h5BFFFD55, 3'd5, 32'hFFFFFFFC);
        check("B16_1234", 32'h5848D155, 3'd5, 32'h000048D0);
        check("B16_ABCD", 32'h5AAF3555, 3'd5, 32'hFFFEAF34);
        check("B16_4000", 32'h59000155, 3'd5, 32'h00010000);
        check("B26_0000000", 32'h50000000, 3'd6, 32'h00000000);
        check("B26_0000001", 32'h50000400, 3'd6, 32'h00000004);
        check("B26_1FFFFFF", 32'h53FFFDFF, 3'd6, 32'h07FFFFFC);
        check("B26_2000000", 32'h50000200, 3'd6, 32'hF8000000);
        check("B26_3FFFFFF", 32'h53FFFFFF, 3'd6, 32'hFFFFFFFC);
        check("B26_0010000", 32'h50000001, 3'd6, 32'h00040000);
        check("B26_0010001", 32'h50000401, 3'd6, 32'h00040004);
        check("B26_0008000", 32'h52000000, 3'd6, 32'h00020000);
        check("B26_1555555", 32'h51555555, 3'd6, 32'h05555554);
        check("B26_2AAAAAA", 32'h52AAAAAA, 3'd6, 32'hFAAAAAA8);
        check("B16_BIT_0", 32'h58000555, 3'd5, 32'h00000004);
        check("B16_BIT_1", 32'h58000955, 3'd5, 32'h00000008);
        check("B16_BIT_2", 32'h58001155, 3'd5, 32'h00000010);
        check("B16_BIT_3", 32'h58002155, 3'd5, 32'h00000020);
        check("B16_BIT_4", 32'h58004155, 3'd5, 32'h00000040);
        check("B16_BIT_5", 32'h58008155, 3'd5, 32'h00000080);
        check("B16_BIT_6", 32'h58010155, 3'd5, 32'h00000100);
        check("B16_BIT_7", 32'h58020155, 3'd5, 32'h00000200);
        check("B16_BIT_8", 32'h58040155, 3'd5, 32'h00000400);
        check("B16_BIT_9", 32'h58080155, 3'd5, 32'h00000800);
        check("B16_BIT_10", 32'h58100155, 3'd5, 32'h00001000);
        check("B16_BIT_11", 32'h58200155, 3'd5, 32'h00002000);
        check("B16_BIT_12", 32'h58400155, 3'd5, 32'h00004000);
        check("B16_BIT_13", 32'h58800155, 3'd5, 32'h00008000);
        check("B16_BIT_14", 32'h59000155, 3'd5, 32'h00010000);
        check("B16_BIT_15", 32'h5A000155, 3'd5, 32'hFFFE0000);
        check("B26_BIT_0", 32'h50000400, 3'd6, 32'h00000004);
        check("B26_BIT_1", 32'h50000800, 3'd6, 32'h00000008);
        check("B26_BIT_2", 32'h50001000, 3'd6, 32'h00000010);
        check("B26_BIT_3", 32'h50002000, 3'd6, 32'h00000020);
        check("B26_BIT_4", 32'h50004000, 3'd6, 32'h00000040);
        check("B26_BIT_5", 32'h50008000, 3'd6, 32'h00000080);
        check("B26_BIT_6", 32'h50010000, 3'd6, 32'h00000100);
        check("B26_BIT_7", 32'h50020000, 3'd6, 32'h00000200);
        check("B26_BIT_8", 32'h50040000, 3'd6, 32'h00000400);
        check("B26_BIT_9", 32'h50080000, 3'd6, 32'h00000800);
        check("B26_BIT_10", 32'h50100000, 3'd6, 32'h00001000);
        check("B26_BIT_11", 32'h50200000, 3'd6, 32'h00002000);
        check("B26_BIT_12", 32'h50400000, 3'd6, 32'h00004000);
        check("B26_BIT_13", 32'h50800000, 3'd6, 32'h00008000);
        check("B26_BIT_14", 32'h51000000, 3'd6, 32'h00010000);
        check("B26_BIT_15", 32'h52000000, 3'd6, 32'h00020000);
        check("B26_BIT_16", 32'h50000001, 3'd6, 32'h00040000);
        check("B26_BIT_17", 32'h50000002, 3'd6, 32'h00080000);
        check("B26_BIT_18", 32'h50000004, 3'd6, 32'h00100000);
        check("B26_BIT_19", 32'h50000008, 3'd6, 32'h00200000);
        check("B26_BIT_20", 32'h50000010, 3'd6, 32'h00400000);
        check("B26_BIT_21", 32'h50000020, 3'd6, 32'h00800000);
        check("B26_BIT_22", 32'h50000040, 3'd6, 32'h01000000);
        check("B26_BIT_23", 32'h50000080, 3'd6, 32'h02000000);
        check("B26_BIT_24", 32'h50000100, 3'd6, 32'h04000000);
        check("B26_BIT_25", 32'h50000200, 3'd6, 32'hF8000000);

        $display("=================================");
        $display("Total tests  = %0d", tests);
        $display("Total errors = %0d", errors);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end
endmodule
