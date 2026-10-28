`timescale 1ns / 1ps

// MEM/WB standalone self-checking testbench (Verilog-2001, Vivado 2019.1).
// 24 cases x 6 output checks = 144 checks.
// No CPU/DMEM execution is modeled: MEM-stage inputs are driven directly.
module tb_mem_wb_reg;

    reg        clk, rst, stall, flush;
    reg        mem_valid;
    reg [31:0] mem_pc, mem_wb_data;
    reg [4:0]  mem_rd_addr;
    reg        mem_reg_write;

    wire        wb_valid;
    wire [31:0] wb_pc, wb_data;
    wire [4:0]  wb_rd_addr;
    wire        wb_reg_write, wb_write_en;

    reg        expected_valid;
    reg [31:0] expected_pc, expected_data;
    reg [4:0]  expected_rd;
    reg        expected_reg_write, expected_write_en;

    integer cases, checks, errors, errors_before;

    mem_wb_reg dut (
        .clk(clk),
        .rst(rst),
        .stall(stall),
        .flush(flush),
        .mem_valid(mem_valid),
        .mem_pc(mem_pc),
        .mem_wb_data(mem_wb_data),
        .mem_rd_addr(mem_rd_addr),
        .mem_reg_write(mem_reg_write),
        .wb_valid(wb_valid),
        .wb_pc(wb_pc),
        .wb_data(wb_data),
        .wb_rd_addr(wb_rd_addr),
        .wb_reg_write(wb_reg_write),
        .wb_write_en(wb_write_en)
    );

    task drive;
        input integer n;
        begin
            mem_valid     = 1'b1;
            mem_pc        = 32'h1c00_0000 + (n * 4);
            mem_wb_data   = 32'ha5a5_0000 ^ n;
            mem_rd_addr   = (n % 31) + 1;
            mem_reg_write = 1'b1;
        end
    endtask

    task check_field;
        input [8*24-1:0] field_name;
        input [31:0] got, want;
        begin
            checks = checks + 1;
            if (got !== want) begin
                errors = errors + 1;
                $display("FAIL case=%0d %0s got=%h expected=%h",
                         cases, field_name, got, want);
            end
        end
    endtask

    task step;
        input [8*48-1:0] case_name;
        begin
            // Drive controls and payload while clk=0, then sample after edge.
            #2;
            if (rst || flush) begin
                expected_valid     = 1'b0;
                expected_pc        = 32'd0;
                expected_data      = 32'd0;
                expected_rd        = 5'd0;
                expected_reg_write = 1'b0;
            end else if (!stall) begin
                expected_valid     = mem_valid;
                expected_pc        = mem_pc;
                expected_data      = mem_wb_data;
                expected_rd        = mem_rd_addr;
                expected_reg_write = mem_reg_write;
            end
            // Stall: expected registered state is retained.
            expected_write_en = expected_valid && expected_reg_write &&
                                (expected_rd != 5'd0);

            clk = 1'b1;
            #1;
            cases = cases + 1;
            errors_before = errors;

            check_field("wb_valid",     wb_valid,     expected_valid);
            check_field("wb_pc",        wb_pc,        expected_pc);
            check_field("wb_data",      wb_data,      expected_data);
            check_field("wb_rd_addr",   wb_rd_addr,   expected_rd);
            check_field("wb_reg_write", wb_reg_write, expected_reg_write);
            check_field("wb_write_en",  wb_write_en,  expected_write_en);

            if (errors == errors_before)
                $display("PASS [%0d] %0s", cases, case_name);
            else
                $display("FAIL [%0d] %0s", cases, case_name);
            clk = 1'b0;
            #2;
        end
    endtask

    initial begin
        clk = 0;
        rst = 0;
        stall = 0;
        flush = 0;
        cases = 0;
        checks = 0;
        errors = 0;

        expected_valid = 0;
        expected_pc = 0;
        expected_data = 0;
        expected_rd = 0;
        expected_reg_write = 0;
        expected_write_en = 0;

        // Reset, normal arithmetic, loads, branches, link-address WB.
        drive(1); rst = 1;                  step("01 synchronous reset");
        rst = 0; drive(2);                  step("02 ALU result write");
        drive(3); mem_wb_data = 32'hbeef_1234;
                                              step("03 LD.W result write");
        drive(4); mem_rd_addr = 5'd1;
        mem_wb_data = mem_pc + 32'd4;       step("04 BL PC+4 to r1");
        drive(5); mem_rd_addr = 5'd19;
        mem_wb_data = mem_pc + 32'd4;       step("05 JIRL link to rd");
        drive(6); mem_reg_write = 0;        step("06 ST.W no writeback");
        drive(7); mem_reg_write = 0;        step("07 branch no writeback");
        drive(8); mem_valid = 0;            step("08 invalid slot");
        drive(9); mem_rd_addr = 0;          step("09 r0 blocked");

        // Stall retains all registered fields, including zero-register rule.
        drive(10); stall = 1;               step("10 stall holds r0 slot");
        stall = 0; drive(11);               step("11 resume capture");
        drive(12); stall = 1; flush = 1;    step("12 flush overrides stall");
        flush = 0; drive(13);               step("13 stall holds bubble");
        stall = 0; drive(14);               step("14 capture after bubble");
        drive(15); stall = 1; rst = 1;      step("15 reset overrides stall");
        rst = 0; stall = 0; drive(16);      step("16 resume after reset");
        drive(17); rst = 1; flush = 1;      step("17 reset with flush");
        drive(18); stall = 1;               step("18 reset flush stall");
        rst = 0; stall = 0; drive(19);      step("19 flush alone");
        flush = 0; drive(20);               step("20 resume after flush");

        // Edge cases: zero data, negative values, invalid-but-write control.
        drive(21); mem_wb_data = 32'd0;     step("21 write valid zero data");
        drive(22); mem_wb_data = 32'h8000_0000;
                                              step("22 sign-bit data");
        drive(23); mem_valid = 0;
        mem_reg_write = 1; mem_rd_addr = 5'd31;
                                              step("23 invalid prevents write");
        drive(24); mem_pc = 32'hffff_fffc;
        mem_wb_data = 32'hffff_ffff;       step("24 final boundary capture");

        $display("----------------------------------------------");
        $display("Total cases = %0d, signal checks = %0d, errors = %0d",
                 cases, checks, errors);
        if (cases == 24 && checks == 144 && errors == 0)
            $display("ALL TESTS PASSED (24 cases, 144 signal checks)");
        else
            $display("TESTS FAILED");
        $finish;
    end

endmodule
