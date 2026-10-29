`timescale 1ns / 1ps
// Independent test of A's official forwarding_unit.v (no CPU v02 needed).
// 27 directed scenarios x 4 outputs = 108 checks.
module tb_forwarding_unit_v02;
    reg ex_valid;
    reg [4:0] ex_rs1_addr, ex_rs2_addr;
    reg ex_rs1_used, ex_rs2_used;
    reg exmem_valid, exmem_reg_write, exmem_result_ready;
    reg [4:0] exmem_rd_addr;
    reg memwb_valid, memwb_reg_write;
    reg [4:0] memwb_rd_addr;
    wire [1:0] forward_a, forward_b;
    wire wait_a, wait_b;
    integer cases=0, checks=0, errors=0;

    forwarding_unit dut (
        .ex_valid(ex_valid), .ex_rs1_addr(ex_rs1_addr),
        .ex_rs2_addr(ex_rs2_addr), .ex_rs1_used(ex_rs1_used),
        .ex_rs2_used(ex_rs2_used), .exmem_valid(exmem_valid),
        .exmem_reg_write(exmem_reg_write),
        .exmem_rd_addr(exmem_rd_addr),
        .exmem_result_ready(exmem_result_ready),
        .memwb_valid(memwb_valid),
        .memwb_reg_write(memwb_reg_write),
        .memwb_rd_addr(memwb_rd_addr),
        .forward_a(forward_a), .forward_b(forward_b),
        .wait_a(wait_a), .wait_b(wait_b)
    );

    task run_case;
        input [8*64-1:0] name;
        input ev;
        input [4:0] rs1,rs2;
        input used1,used2;
        input mv,mw;
        input [4:0] mrd;
        input ready;
        input wv,ww;
        input [4:0] wrd;
        input [1:0] a,b;
        input wa,wb;
        begin
            ex_valid=ev; ex_rs1_addr=rs1; ex_rs2_addr=rs2;
            ex_rs1_used=used1; ex_rs2_used=used2;
            exmem_valid=mv; exmem_reg_write=mw;
            exmem_rd_addr=mrd; exmem_result_ready=ready;
            memwb_valid=wv; memwb_reg_write=ww; memwb_rd_addr=wrd;
            #1;
            cases=cases+1;
            checks=checks+4;
            if (forward_a !== a || forward_b !== b ||
                wait_a !== wa || wait_b !== wb) begin
                errors=errors+1;
                $display("FAIL [%0d] %0s: got a=%b b=%b wa=%b wb=%b; exp=%b %b %b %b",
                    cases,name,forward_a,forward_b,wait_a,wait_b,a,b,wa,wb);
            end else
                $display("PASS [%0d] %0s",cases,name);
        end
    endtask

    initial begin
        run_case("idle no instruction", 0, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0);
        run_case("no producer", 1, 1, 2, 1, 1, 0, 0, 1, 1, 0, 0, 2, 0, 0, 0, 0);
        run_case("exmem matches A", 1, 1, 2, 1, 1, 1, 1, 1, 1, 0, 0, 2, 2, 0, 0, 0);
        run_case("exmem matches B", 1, 1, 2, 1, 1, 1, 1, 2, 1, 0, 0, 2, 0, 2, 0, 0);
        run_case("exmem matches both", 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 2, 2, 2, 0, 0);
        run_case("memwb matches A", 1, 1, 2, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0);
        run_case("memwb matches B", 1, 1, 2, 1, 1, 0, 0, 1, 1, 1, 1, 2, 0, 1, 0, 0);
        run_case("memwb both", 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0);
        run_case("newer EXMEM beats WB", 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0);
        run_case("newer EXMEM beats WB B", 1, 1, 2, 1, 1, 1, 1, 2, 1, 1, 1, 2, 0, 2, 0, 0);
        run_case("unready EXMEM stalls A", 1, 1, 2, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 1, 0);
        run_case("unready EXMEM stalls B", 1, 1, 2, 1, 1, 1, 1, 2, 0, 1, 1, 2, 0, 0, 0, 1);
        run_case("unready EXMEM both", 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 1, 1);
        run_case("unused A ignored", 1, 1, 2, 0, 1, 1, 1, 1, 1, 0, 0, 2, 0, 0, 0, 0);
        run_case("unused B ignored", 1, 1, 2, 1, 0, 1, 1, 2, 1, 0, 0, 2, 0, 0, 0, 0);
        run_case("invalid EXMEM ignored", 1, 1, 2, 1, 1, 0, 1, 1, 1, 0, 0, 2, 0, 0, 0, 0);
        run_case("EXMEM regwrite false", 1, 1, 2, 1, 1, 1, 0, 1, 1, 0, 0, 2, 0, 0, 0, 0);
        run_case("invalid MEMWB ignored", 1, 1, 2, 1, 1, 0, 0, 1, 1, 0, 1, 1, 0, 0, 0, 0);
        run_case("MEMWB regwrite false", 1, 1, 2, 1, 1, 0, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0);
        run_case("r0 source A ignored", 1, 0, 2, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0);
        run_case("r0 source B ignored", 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0);
        run_case("r0 producer never forwarded", 1, 0, 0, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0);
        run_case("A exmem B memwb", 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 1, 0, 0);
        run_case("A memwb B exmem", 1, 1, 2, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 2, 0, 0);
        run_case("A unready B WB", 1, 1, 2, 1, 1, 1, 1, 1, 0, 1, 1, 2, 0, 1, 1, 0);
        run_case("A WB B unready", 1, 1, 2, 1, 1, 1, 1, 2, 0, 1, 1, 1, 1, 0, 0, 1);
        run_case("both sources unused", 1, 1, 2, 0, 0, 1, 1, 1, 0, 1, 1, 2, 0, 0, 0, 0);
        $display("-------------------------------------------");
        $display("FORWARDING UNIT INDEPENDENT VERIFICATION");
        $display("cases=%0d checks=%0d errors=%0d",cases,checks,errors);
        if(cases==27 && checks==108 && errors==0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED");
        $finish;
    end
endmodule
