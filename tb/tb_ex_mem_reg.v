
`timescale 1ns / 1ps

// EX/MEM pipeline register standalone self-checking testbench.
// 20 scenarios x 11 output fields = 220 checks.
module tb_ex_mem_reg;

    reg clk, rst, stall, flush;

    reg        ex_valid;
    reg [31:0] ex_pc, ex_pc_plus4;
    reg [31:0] ex_alu_result, ex_store_data;
    reg [4:0]  ex_store_src_addr, ex_rd_addr;
    reg        ex_mem_read, ex_mem_write, ex_reg_write;
    reg [1:0]  ex_wb_sel;

    wire        mem_valid;
    wire [31:0] mem_pc, mem_pc_plus4;
    wire [31:0] mem_alu_result, mem_store_data;
    wire [4:0]  mem_store_src_addr, mem_rd_addr;
    wire        mem_mem_read, mem_mem_write, mem_reg_write;
    wire [1:0]  mem_wb_sel;

    // Expected outputs
    reg        ev;
    reg [31:0] epc, epc4, ealu, estore;
    reg [4:0]  esrc, erd;
    reg        eread, ewrite, eregwrite;
    reg [1:0]  ewbsel;

    integer cases, checks, errors, errors_before;

    ex_mem_reg dut (
        .clk(clk),
        .rst(rst),
        .stall(stall),
        .flush(flush),

        .ex_valid(ex_valid),
        .ex_pc(ex_pc),
        .ex_pc_plus4(ex_pc_plus4),
        .ex_alu_result(ex_alu_result),
        .ex_store_data(ex_store_data),
        .ex_store_src_addr(ex_store_src_addr),
        .ex_rd_addr(ex_rd_addr),
        .ex_mem_read(ex_mem_read),
        .ex_mem_write(ex_mem_write),
        .ex_reg_write(ex_reg_write),
        .ex_wb_sel(ex_wb_sel),

        .mem_valid(mem_valid),
        .mem_pc(mem_pc),
        .mem_pc_plus4(mem_pc_plus4),
        .mem_alu_result(mem_alu_result),
        .mem_store_data(mem_store_data),
        .mem_store_src_addr(mem_store_src_addr),
        .mem_rd_addr(mem_rd_addr),
        .mem_mem_read(mem_mem_read),
        .mem_mem_write(mem_mem_write),
        .mem_reg_write(mem_reg_write),
        .mem_wb_sel(mem_wb_sel)
    );

    // Generate different input patterns.
    task drive;
        input integer n;
        begin
            ex_valid          = 1'b1;
            ex_pc             = 32'h1c00_0000 + n * 4;
            ex_pc_plus4       = ex_pc + 32'd4;
            ex_alu_result     = 32'ha5a5_0000 ^ n;
            ex_store_data     = 32'h5a5a_0000 + n;
            ex_store_src_addr = n + 3;
            ex_rd_addr        = n + 7;
            ex_mem_read       = 1'b0;
            ex_mem_write      = 1'b0;
            ex_reg_write      = 1'b1;
            ex_wb_sel         = 2'b00;
        end
    endtask

    task check_field;
        input [8*24-1:0] field_name;
        input [31:0] got, want;
        begin
            checks = checks + 1;

            if (got !== want) begin
                errors = errors + 1;
                $display(
                    "FAIL [%0d] %0s: got=%h expected=%h",
                    cases, field_name, got, want
                );
            end
        end
    endtask

    task step;
        input [8*48-1:0] case_name;
        begin
            #2;

            // Reference model:
            // Reset > Flush > Stall > Capture

            if (rst || flush) begin
                ev        = 0;
                epc       = 0;
                epc4      = 0;
                ealu      = 0;
                estore    = 0;
                esrc      = 0;
                erd       = 0;
                eread     = 0;
                ewrite    = 0;
                eregwrite = 0;
                ewbsel    = 0;
            end

            else if (!stall) begin
                ev        = ex_valid;
                epc       = ex_pc;
                epc4      = ex_pc_plus4;
                ealu      = ex_alu_result;
                estore    = ex_store_data;
                esrc      = ex_store_src_addr;
                erd       = ex_rd_addr;
                eread     = ex_mem_read;
                ewrite    = ex_mem_write;
                eregwrite = ex_reg_write;
                ewbsel    = ex_wb_sel;
            end

            // Stall: keep all expected values unchanged.

            clk = 1'b1;
            #1;

            cases = cases + 1;
            errors_before = errors;

            check_field("valid",
                        mem_valid, ev);

            check_field("pc",
                        mem_pc, epc);

            check_field("pc_plus4",
                        mem_pc_plus4, epc4);

            check_field("alu_result",
                        mem_alu_result, ealu);

            check_field("store_data",
                        mem_store_data, estore);

            check_field("store_src_addr",
                        mem_store_src_addr, esrc);

            check_field("rd_addr",
                        mem_rd_addr, erd);

            check_field("mem_read",
                        mem_mem_read, eread);

            check_field("mem_write",
                        mem_mem_write, ewrite);

            check_field("reg_write",
                        mem_reg_write, eregwrite);

            check_field("wb_sel",
                        mem_wb_sel, ewbsel);

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

        ev = 0;
        epc = 0;
        epc4 = 0;
        ealu = 0;
        estore = 0;
        esrc = 0;
        erd = 0;
        eread = 0;
        ewrite = 0;
        eregwrite = 0;
        ewbsel = 0;

        // Case 01: Reset
        drive(1);
        rst = 1;
        step("01 reset only");

        // Case 02: ALU result
        rst = 0;
        drive(2);
        step("02 ALU result capture");

        // Case 03: LD.W
        drive(3);
        ex_mem_read = 1;
        ex_wb_sel = 2'b01;
        step("03 LD.W address and controls");

        // Case 04: ST.W
        drive(4);
        ex_mem_write = 1;
        ex_reg_write = 0;
        ex_store_data = 32'hdead_beef;
        ex_store_src_addr = 5'd9;
        step("04 ST.W data and source");

        // Case 05: BL link register
        drive(5);
        ex_wb_sel = 2'b10;
        ex_rd_addr = 5'd1;
        step("05 BL PC+4 and link register");

        // Case 06: JIRL
        drive(6);
        ex_wb_sel = 2'b10;
        ex_rd_addr = 5'd12;
        step("06 JIRL PC+4 and destination");

        // Case 07: Stall holds data
        drive(7);
        stall = 1;
        step("07 stall retains JIRL values");

        // Case 08: Flush overrides Stall
        drive(8);
        flush = 1;
        step("08 flush overrides stall");

        // Case 09: Flush alone
        stall = 0;
        drive(9);
        step("09 flush without stall");

        // Case 10: Stall holds bubble
        flush = 0;
        stall = 1;
        drive(10);
        step("10 stall retains bubble");

        // Case 11: Resume
        stall = 0;
        drive(11);
        step("11 resume capture");

        // Case 12: Reset overrides Stall
        drive(12);
        rst = 1;
        stall = 1;
        step("12 reset overrides stall");

        // Case 13: Reset with Flush
        drive(13);
        stall = 0;
        flush = 1;
        step("13 reset with flush");

        // Case 14: All three asserted
        drive(14);
        stall = 1;
        step("14 reset flush stall together");

        // Case 15: Load after Reset
        rst = 0;
        stall = 0;
        flush = 0;
        drive(15);
        ex_mem_read = 1;
        ex_wb_sel = 2'b01;
        step("15 load after reset");

        // Case 16: Invalid instruction
        drive(16);
        ex_valid = 0;
        ex_mem_write = 1;
        ex_reg_write = 1;
        step("16 invalid instruction payload");

        // Case 17: PC+4 wraparound
        drive(17);
        ex_pc = 32'hffff_fffc;
        ex_pc_plus4 = 32'h0000_0000;
        ex_alu_result = 32'h8000_0000;
        step("17 PC+4 wraparound storage");

        // Case 18: Stall retains prior values
        drive(18);
        stall = 1;
        step("18 hold wraparound values");

        // Case 19: Flush store control
        stall = 0;
        drive(19);
        flush = 1;
        ex_mem_write = 1;
        ex_reg_write = 0;
        step("19 flush cancels store control");

        // Case 20: Final normal capture
        flush = 0;
        drive(20);
        step("20 final normal capture");

        $display("----------------------------------------");

        $display(
            "Total cases = %0d, field checks = %0d, errors = %0d",
            cases, checks, errors
        );

        if (cases == 20 && checks == 220 && errors == 0)
            $display(
                "ALL TESTS PASSED (20 cases, 220 field checks)"
            );
        else
            $display("TESTS FAILED");

        $finish;
    end

endmodule
