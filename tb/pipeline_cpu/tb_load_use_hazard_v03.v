`timescale 1ns / 1ps
// V0.3 preparation: independent combinational regression against the official
// rtl/common/load_use_hazard_unit.v. Vivado 2019.1 / Verilog-2001.
module tb_load_use_hazard_v03;
    reg id_valid, id_rs1_used, id_rs2_used;
    reg [4:0] id_rs1_addr, id_rs2_addr;
    reg ex_valid, ex_mem_read;
    reg [4:0] ex_rd_addr;
    wire load_use_hazard, hold_if_req, hold_ifid_req, bubble_idex_req;
    integer cases, checks, errors;

    load_use_hazard_unit dut (
        .id_valid(id_valid),
        .id_rs1_addr(id_rs1_addr), .id_rs2_addr(id_rs2_addr),
        .id_rs1_used(id_rs1_used), .id_rs2_used(id_rs2_used),
        .ex_valid(ex_valid), .ex_mem_read(ex_mem_read),
        .ex_rd_addr(ex_rd_addr),
        .load_use_hazard(load_use_hazard),
        .hold_if_req(hold_if_req),
        .hold_ifid_req(hold_ifid_req),
        .bubble_idex_req(bubble_idex_req)
    );

    // Every test checks four independent outputs. Values must match exactly;
    // X and Z are failures as well.
    task run_case;
        input [8*64-1:0] name;
        input iv;
        input [4:0] r1, r2;
        input u1, u2;
        input ev, ld;
        input [4:0] dest;
        input expected;
        begin
            id_valid=iv; id_rs1_addr=r1; id_rs2_addr=r2;
            id_rs1_used=u1; id_rs2_used=u2;
            ex_valid=ev; ex_mem_read=ld; ex_rd_addr=dest;
            #1;
            cases=cases+1;
            checks=checks+4;
            if (load_use_hazard !== expected) begin
                errors=errors+1;
                $display("FAIL %0d %0s: hazard got=%b exp=%b", cases, name, load_use_hazard, expected);
            end
            if (hold_if_req !== expected) begin
                errors=errors+1;
                $display("FAIL %0d %0s: hold_if got=%b exp=%b", cases, name, hold_if_req, expected);
            end
            if (hold_ifid_req !== expected) begin
                errors=errors+1;
                $display("FAIL %0d %0s: hold_ifid got=%b exp=%b", cases, name, hold_ifid_req, expected);
            end
            if (bubble_idex_req !== expected) begin
                errors=errors+1;
                $display("FAIL %0d %0s: bubble_idex got=%b exp=%b", cases, name, bubble_idex_req, expected);
            end
            if (load_use_hazard === expected && hold_if_req === expected &&
                hold_ifid_req === expected && bubble_idex_req === expected)
                $display("PASS %0d %0s", cases, name);
        end
    endtask

    initial begin
        cases=0; checks=0; errors=0;
        // iv, rs1,rs2, used1,used2, ex_valid,ex_load,ex_dest, expected.
        run_case("all invalid",                   0,5,5,1,1,0,0,5,0);
        run_case("rs1 immediate load use",        1,5,8,1,1,1,1,5,1);
        run_case("rs2 immediate load use",        1,8,5,1,1,1,1,5,1);
        run_case("both sources match",           1,5,5,1,1,1,1,5,1);
        run_case("different addresses",          1,6,7,1,1,1,1,5,0);
        run_case("ID invalid",                   0,5,8,1,1,1,1,5,0);
        run_case("EX invalid",                   1,5,8,1,1,0,1,5,0);
        run_case("EX not load",                  1,5,8,1,1,1,0,5,0);
        run_case("load destination r0",          1,0,0,1,1,1,1,0,0);
        run_case("rs1 unused",                   1,5,8,0,1,1,1,5,0);
        run_case("rs2 unused",                   1,8,5,1,0,1,1,5,0);
        run_case("both unused",                  1,5,5,0,0,1,1,5,0);
        run_case("rs1 match rs2 unused",          1,5,5,1,0,1,1,5,1);
        run_case("rs2 match rs1 unused",          1,5,5,0,1,1,1,5,1);
        run_case("rs1 r0 but rd nonzero",        1,0,9,1,1,1,1,9,1);
        run_case("r0 source no false hazard",    1,0,8,1,1,1,1,5,0);
        run_case("destination r1 match",        1,1,4,1,1,1,1,1,1);
        run_case("destination r31 match",       1,31,2,1,1,1,1,31,1);
        run_case("destination r31 no match",    1,30,2,1,1,1,1,31,0);
        run_case("only rs1 used match",         1,7,7,1,0,1,1,7,1);
        run_case("only rs2 used match",         1,7,7,0,1,1,1,7,1);
        run_case("rs1 mismatch rs2 match",      1,2,3,1,1,1,1,3,1);
        run_case("rs1 match rs2 mismatch",      1,3,2,1,1,1,1,3,1);
        run_case("EX valid alone insufficient", 1,3,2,1,1,1,0,3,0);
        run_case("EX load ID invalid",          0,3,2,1,1,1,1,3,0);
        run_case("EX load unused operands",     1,3,3,0,0,1,1,3,0);
        run_case("fresh dependency after clear",1,11,9,1,1,1,1,11,1);
        run_case("release dependency",          1,11,9,1,1,1,1,10,0);
        run_case("reenter dependency via rs2",  1,11,9,1,1,1,1,9,1);
        run_case("release when EX invalid",     1,11,9,1,1,0,1,9,0);
        $display("----------------------------------------");
        $display("V0.3 LOAD-USE HAZARD UNIT REGRESSION");
        $display("cases=%0d checks=%0d errors=%0d", cases, checks, errors);
        if (cases==30 && checks==120 && errors==0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED");
        $finish;
    end
endmodule
