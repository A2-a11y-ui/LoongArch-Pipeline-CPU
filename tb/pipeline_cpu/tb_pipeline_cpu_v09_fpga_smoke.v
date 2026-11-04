`timescale 1ns / 1ps
// V0.9 FPGA-wrapper smoke regression.
// Checks the new synchronous BRAM instruction path against the established
// V0.8 basic-program architectural WB / Store expectations.
// Run in Vivado 2019.1 after adding the package with add_v09_fpga_sources.tcl.
module tb_pipeline_cpu_v09_fpga_smoke #(
    parameter IMEM_FILE = "fpga_demo.mem"
);

    localparam integer N_WB  = 23;
    localparam integer N_ST  = 2;
    localparam integer N_MDU = 15;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;

    wire wb_commit_valid;
    wire [31:0] wb_commit_pc;
    wire [4:0] wb_commit_rd;
    wire [31:0] wb_commit_data;

    wire mem_store_commit_valid;
    wire [31:0] mem_store_commit_pc;
    wire [31:0] mem_store_commit_addr;
    wire [31:0] mem_store_commit_data;

    wire branch_redirect;
    wire [31:0] branch_redirect_pc;
    wire mem_fault_valid;
    wire fetch_error_fire;
    wire id_unsupported;
    wire mdu_start_fire;
    wire mdu_busy;
    wire mdu_result_fire;
    wire dmem_req_fire;
    wire dmem_resp_fire;
    wire mem_stall;
    wire if_resp_hold;
    wire [31:0] cache_hits;
    wire [31:0] cache_misses;
    wire program_done;
    wire fault_sticky;

    pipeline_cpu_fpga #(
        .PROGRAM_WORDS(29),
        .IMEM_FILE(IMEM_FILE),
        .DMEM_READ_LATENCY(8),
        .DMEM_WRITE_LATENCY(11),
        .DMEM_WORDS(256)
    ) dut (
        .clk(clk),
        .rst(rst),

        .wb_commit_valid(wb_commit_valid),
        .wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd),
        .wb_commit_data(wb_commit_data),

        .mem_store_commit_valid(mem_store_commit_valid),
        .mem_store_commit_pc(mem_store_commit_pc),
        .mem_store_commit_addr(mem_store_commit_addr),
        .mem_store_commit_data(mem_store_commit_data),

        .branch_redirect(branch_redirect),
        .branch_redirect_pc(branch_redirect_pc),
        .mem_fault_valid(mem_fault_valid),
        .fetch_error_fire(fetch_error_fire),
        .id_unsupported(id_unsupported),

        .mdu_start_fire(mdu_start_fire),
        .mdu_busy(mdu_busy),
        .mdu_result_fire(mdu_result_fire),

        .dmem_req_fire(dmem_req_fire),
        .dmem_resp_fire(dmem_resp_fire),
        .mem_stall(mem_stall),
        .if_resp_hold(if_resp_hold),
        .cache_hits(cache_hits),
        .cache_misses(cache_misses),
        .program_done(program_done),
        .fault_sticky(fault_sticky)
    );

    reg [31:0] expected_wb_pc   [0:N_WB-1];
    reg [4:0]  expected_wb_rd   [0:N_WB-1];
    reg [31:0] expected_wb_data [0:N_WB-1];

    reg [31:0] expected_st_pc   [0:N_ST-1];
    reg [31:0] expected_st_addr [0:N_ST-1];
    reg [31:0] expected_st_data [0:N_ST-1];

    integer wb_count = 0;
    integer st_count = 0;
    integer branch_count = 0;
    integer mdu_start_count = 0;
    integer mdu_result_count = 0;
    integer dmem_req_count = 0;
    integer dmem_resp_count = 0;
    integer mem_stall_cycles = 0;
    integer if_hold_cycles = 0;
    integer cycles = 0;
    integer errors = 0;

    task set_wb;
        input integer idx;
        input [31:0] pc;
        input [4:0] rd;
        input [31:0] value;
        begin
            expected_wb_pc[idx]   = pc;
            expected_wb_rd[idx]   = rd;
            expected_wb_data[idx] = value;
        end
    endtask

    task set_store;
        input integer idx;
        input [31:0] pc;
        input [31:0] addr;
        input [31:0] value;
        begin
            expected_st_pc[idx]   = pc;
            expected_st_addr[idx] = addr;
            expected_st_data[idx] = value;
        end
    endtask

    initial begin
        set_wb(0,  32'h00001000, 5'd1,  32'h00000006);
        set_wb(1,  32'h00001004, 5'd2,  32'h00000003);
        set_wb(2,  32'h00001008, 5'd3,  32'h00000012);
        set_wb(3,  32'h0000100c, 5'd4,  32'h00000015);
        set_wb(4,  32'h00001010, 5'd5,  32'h00000007);
        set_wb(5,  32'h00001014, 5'd6,  32'h00000003);
        set_wb(6,  32'h00001018, 5'd7,  32'h00000000);
        set_wb(7,  32'h0000101c, 5'd8,  32'h00000000);
        set_wb(8,  32'h00001020, 5'd9,  32'h00000003);
        set_wb(9,  32'h00001024, 5'd10, 32'h00000003);
        set_wb(10, 32'h0000102c, 5'd11, 32'h00000007);
        set_wb(11, 32'h00001030, 5'd12, 32'h00000015);
        set_wb(12, 32'h00001034, 5'd13, 32'h00000007);
        set_wb(13, 32'h00001044, 5'd15, 32'h00000008);
        set_wb(14, 32'h0000104c, 5'd16, 32'h00000008);
        set_wb(15, 32'h00001050, 5'd18, 32'hffffffff);
        set_wb(16, 32'h00001054, 5'd19, 32'h00000002);
        set_wb(17, 32'h00001058, 5'd20, 32'hffffffff);
        set_wb(18, 32'h0000105c, 5'd21, 32'h00000001);
        set_wb(19, 32'h00001060, 5'd22, 32'h00000000);
        set_wb(20, 32'h00001064, 5'd23, 32'hffffffff);
        set_wb(21, 32'h00001068, 5'd24, 32'h7fffffff);
        set_wb(22, 32'h0000106c, 5'd25, 32'h00000001);

        set_store(0, 32'h00001028, 32'h00000004, 32'h00000007);
        set_store(1, 32'h00001048, 32'h0000000c, 32'h00000008);

        repeat (4) @(negedge clk);
        rst = 1'b0;
    end

    always @(posedge clk) begin
        if (!rst) begin
            cycles = cycles + 1;

            if (mdu_start_fire)
                mdu_start_count = mdu_start_count + 1;
            if (mdu_result_fire)
                mdu_result_count = mdu_result_count + 1;
            if (dmem_req_fire)
                dmem_req_count = dmem_req_count + 1;
            if (dmem_resp_fire)
                dmem_resp_count = dmem_resp_count + 1;
            if (mem_stall)
                mem_stall_cycles = mem_stall_cycles + 1;
            if (if_resp_hold)
                if_hold_cycles = if_hold_cycles + 1;

            if (fetch_error_fire || mem_fault_valid || id_unsupported) begin
                errors = errors + 1;
                $display("FAIL unexpected fetch/memory/decoder fault @%0t", $time);
            end

            if (branch_redirect) begin
                if (branch_redirect_pc !== 32'h00001044) begin
                    errors = errors + 1;
                    $display("FAIL branch target expected=00001044 actual=%h",
                             branch_redirect_pc);
                end
                branch_count = branch_count + 1;
            end

            if (wb_commit_valid) begin
                if (wb_count >= N_WB) begin
                    errors = errors + 1;
                    $display("FAIL extra WB pc=%h rd=%0d data=%h",
                             wb_commit_pc, wb_commit_rd, wb_commit_data);
                end else if (wb_commit_pc !== expected_wb_pc[wb_count] ||
                             wb_commit_rd !== expected_wb_rd[wb_count] ||
                             wb_commit_data !== expected_wb_data[wb_count]) begin
                    errors = errors + 1;
                    $display("FAIL WB[%0d] expected=%h/%0d/%h actual=%h/%0d/%h",
                             wb_count,
                             expected_wb_pc[wb_count],
                             expected_wb_rd[wb_count],
                             expected_wb_data[wb_count],
                             wb_commit_pc, wb_commit_rd, wb_commit_data);
                end
                wb_count = wb_count + 1;
            end

            if (mem_store_commit_valid) begin
                if (st_count >= N_ST) begin
                    errors = errors + 1;
                    $display("FAIL extra STORE pc=%h addr=%h data=%h",
                             mem_store_commit_pc,
                             mem_store_commit_addr,
                             mem_store_commit_data);
                end else if (mem_store_commit_pc !== expected_st_pc[st_count] ||
                             mem_store_commit_addr !== expected_st_addr[st_count] ||
                             mem_store_commit_data !== expected_st_data[st_count]) begin
                    errors = errors + 1;
                    $display("FAIL STORE[%0d] expected=%h/%h/%h actual=%h/%h/%h",
                             st_count,
                             expected_st_pc[st_count],
                             expected_st_addr[st_count],
                             expected_st_data[st_count],
                             mem_store_commit_pc,
                             mem_store_commit_addr,
                             mem_store_commit_data);
                end
                st_count = st_count + 1;
            end

            if (program_done) begin
                if (wb_count != N_WB) begin
                    errors = errors + 1;
                    $display("FAIL WB count expected=%0d actual=%0d", N_WB, wb_count);
                end
                if (st_count != N_ST) begin
                    errors = errors + 1;
                    $display("FAIL STORE count expected=%0d actual=%0d", N_ST, st_count);
                end
                if (branch_count != 1) begin
                    errors = errors + 1;
                    $display("FAIL branch count expected=1 actual=%0d", branch_count);
                end
                if (mdu_start_count != N_MDU || mdu_result_count != N_MDU) begin
                    errors = errors + 1;
                    $display("FAIL MDU start/result expected=%0d actual=%0d/%0d",
                             N_MDU, mdu_start_count, mdu_result_count);
                end
                if (dmem_req_count != 4 || dmem_resp_count != 4) begin
                    errors = errors + 1;
                    $display("FAIL DMEM req/resp expected=4/4 actual=%0d/%0d",
                             dmem_req_count, dmem_resp_count);
                end
                if (mem_stall_cycles == 0 || cache_hits == 0 || cache_misses == 0) begin
                    errors = errors + 1;
                    $display("FAIL expected memory stalls and I-Cache hit/miss activity");
                end
                if (fault_sticky !== 1'b0) begin
                    errors = errors + 1;
                    $display("FAIL fault_sticky asserted");
                end

                $display("V0.9 FPGA SMOKE RESULT WB=%0d/%0d STORE=%0d/%0d BR=%0d MDU=%0d/%0d DMEM=%0d/%0d CACHE_HIT=%0d CACHE_MISS=%0d IF_HOLD=%0d ERRORS=%0d",
                         wb_count, N_WB, st_count, N_ST, branch_count,
                         mdu_start_count, mdu_result_count,
                         dmem_req_count, dmem_resp_count,
                         cache_hits, cache_misses, if_hold_cycles, errors);

                if (errors == 0)
                    $display("ALL TESTS PASSED (V0.9 FPGA wrapper + BRAM I-Mem + I-Cache + V0.8 CPU)");
                else
                    $fatal(1, "V0.9 FPGA smoke regression FAILED errors=%0d", errors);

                $finish;
            end

            if (cycles > 10000)
                $fatal(1, "V0.9 FPGA smoke TIMEOUT wb=%0d/%0d store=%0d/%0d",
                       wb_count, N_WB, st_count, N_ST);
        end
    end

endmodule
