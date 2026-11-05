`timescale 1ns / 1ps
// Independent V0.9 EGO1 board-top reset/replay behavioral simulation.
// Uses unchanged fpga_demo.mem; verifies two complete executions against
// the 23-WB/2-Store reference used by the existing FPGA Smoke test.
// Simulation-only hierarchical observations: no production RTL changes.
// NOTE: Set IMEM_FILE to the actual full path of the unchanged fpga_demo.mem
// or ensure Vivado's simulator resolves the supplied memory file.
module tb_v09_ego1_reset_replay;
    parameter IMEM_FILE = "D:/CPU_Project/V09_FPGA_Review/fpga_demo.mem";
    localparam integer N_WB = 23;
    localparam integer N_ST = 2;
    localparam integer N_MDU = 15;

    reg clk = 1'b0;
    always #5 clk = ~clk;    // 100 MHz
    reg sys_rst_n = 1'b0;
    wire [15:0] led;

    ego1_top #(.IMEM_FILE(IMEM_FILE), .PROGRAM_WORDS(29)) dut (
        .clk(clk), .sys_rst_n(sys_rst_n), .led(led)
    );

    reg [31:0] exp_wb_pc [0:N_WB-1];
    reg [4:0]  exp_wb_rd [0:N_WB-1];
    reg [31:0] exp_wb_data [0:N_WB-1];
    reg [31:0] exp_st_pc [0:N_ST-1];
    reg [31:0] exp_st_addr [0:N_ST-1];
    reg [31:0] exp_st_data [0:N_ST-1];

    integer wb_count = 0;
    integer st_count = 0;
    integer branch_count = 0;
    integer mdu_start_count = 0;
    integer mdu_result_count = 0;
    integer dmem_req_count = 0;
    integer dmem_resp_count = 0;
    integer cycles = 0;
    integer errors = 0;
    integer checks = 0;
    integer completed_runs = 0;
    // Phase: 0=initial reset, 1=run #1, 2=second reset,
    // 3=run #2, 10=run #1 completed, 11=run #2 completed.
    integer phase = 0;

    task set_wb;
        input integer idx;
        input [31:0] pc;
        input [4:0] rd;
        input [31:0] value;
        begin
            exp_wb_pc[idx] = pc;
            exp_wb_rd[idx] = rd;
            exp_wb_data[idx] = value;
        end
    endtask

    task set_store;
        input integer idx;
        input [31:0] pc;
        input [31:0] addr;
        input [31:0] value;
        begin
            exp_st_pc[idx] = pc;
            exp_st_addr[idx] = addr;
            exp_st_data[idx] = value;
        end
    endtask

    task reset_counts;
        begin
            wb_count = 0;
            st_count = 0;
            branch_count = 0;
            mdu_start_count = 0;
            mdu_result_count = 0;
            dmem_req_count = 0;
            dmem_resp_count = 0;
            cycles = 0;
        end
    endtask

    task fail_check;
        input [8*100-1:0] message;
        begin
            errors = errors + 1;
            $display("FAIL: %0s @%0t", message, $time);
        end
    endtask

    // Test uses the reference values from tb_pipeline_cpu_v09_fpga_smoke.v.
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

        $display("V09 EGO1 RESET: asserting external active-low reset");
        repeat (8) @(negedge clk);
        checks = checks + 1;
        if (dut.rst !== 1'b1 || led[14:0] !== 15'b0 ||
            dut.program_done !== 1'b0 || dut.fault_sticky !== 1'b0)
            fail_check("initial held reset did not clear top-level status/LEDs");

        $display("V09 EGO1 RESET CASE 1: release, first complete demo run");
        reset_counts();
        phase = 1;
        sys_rst_n = 1'b1;

        wait (phase == 10);
        @(negedge clk);
        checks = checks + 1;
        if (led[13] !== 1'b1 || led[14] !== 1'b0 ||
            led[12:8] !== 5'd25 || led[7:0] !== 8'h01)
            fail_check("first-run LED status or last WB display incorrect");

        $display("V09 EGO1 RESET CASE 2: assert and hold reset after completion");
        phase = 2;
        sys_rst_n = 1'b0;
        // Two-flop synchronous reset latency is intentional.
        repeat (8) @(negedge clk);
        checks = checks + 1;
        if (dut.rst !== 1'b1 || led[14:0] !== 15'b0 ||
            dut.program_done !== 1'b0 || dut.fault_sticky !== 1'b0)
            fail_check("second held reset did not clear status/LEDs");
        checks = checks + 1;
        if (dut.u_cpu.cache_hits !== 32'b0 ||
            dut.u_cpu.cache_misses !== 32'b0)
            fail_check("cache counters did not reset between runs");

        $display("V09 EGO1 RESET CASE 3: release, repeat the same demo");
        reset_counts();
        phase = 3;
        sys_rst_n = 1'b1;
        wait (phase == 11);
        @(negedge clk);
        checks = checks + 1;
        if (led[13] !== 1'b1 || led[14] !== 1'b0 ||
            led[12:8] !== 5'd25 || led[7:0] !== 8'h01)
            fail_check("second-run LED status or last WB display incorrect");

        $display("--------------------------------------------------");
        $display("V09 EGO1 RESET REPLAY RESULT RUNS=%0d/2 WB_LAST=%0d/%0d STORE_LAST=%0d/%0d CHECKS=%0d ERRORS=%0d",
            completed_runs, wb_count, N_WB, st_count, N_ST, checks, errors);
        if (errors == 0 && completed_runs == 2)
            $display("ALL TESTS PASSED (ego1_top reset hold/release + two architectural demo runs)");
        else
            $display("TEST FAILED (ego1_top reset replay)");
        $finish;
    end

    // Inspect each transfer on the active clock edge, before sequential update.
    always @(posedge clk) begin
        if ((phase == 1 || phase == 3) && dut.rst === 1'b0) begin
            cycles = cycles + 1;
            if (cycles > 10000)
                $fatal(1, "V09 EGO1 RESET TIMEOUT phase=%0d wb=%0d st=%0d", phase, wb_count, st_count);

            if (dut.mdu_start_fire)
                mdu_start_count = mdu_start_count + 1;
            if (dut.mdu_result_fire)
                mdu_result_count = mdu_result_count + 1;
            if (dut.dmem_req_fire)
                dmem_req_count = dmem_req_count + 1;
            if (dut.dmem_resp_fire)
                dmem_resp_count = dmem_resp_count + 1;
            if (dut.branch_redirect) begin
                branch_count = branch_count + 1;
                checks = checks + 1;
                if (dut.branch_redirect_pc !== 32'h00001044)
                    fail_check("unexpected redirect target");
            end
            if (dut.mem_fault_valid || dut.fetch_error_fire ||
                dut.id_unsupported || dut.fault_sticky)
                fail_check("fault or unsupported instruction during run");

            if (dut.wb_commit_valid) begin
                checks = checks + 1;
                if (wb_count >= N_WB) begin
                    fail_check("extra architectural WB");
                end else if (dut.wb_commit_pc !== exp_wb_pc[wb_count] ||
                             dut.wb_commit_rd !== exp_wb_rd[wb_count] ||
                             dut.wb_commit_data !== exp_wb_data[wb_count]) begin
                    $display("FAIL: WB[%0d] expected %h/%0d/%h got %h/%0d/%h",
                        wb_count, exp_wb_pc[wb_count], exp_wb_rd[wb_count], exp_wb_data[wb_count],
                        dut.wb_commit_pc, dut.wb_commit_rd, dut.wb_commit_data);
                    errors = errors + 1;
                end
                wb_count = wb_count + 1;
            end
            if (dut.mem_store_commit_valid) begin
                checks = checks + 1;
                if (st_count >= N_ST) begin
                    fail_check("extra architectural STORE");
                end else if (dut.mem_store_commit_pc !== exp_st_pc[st_count] ||
                             dut.mem_store_commit_addr !== exp_st_addr[st_count] ||
                             dut.mem_store_commit_data !== exp_st_data[st_count]) begin
                    $display("FAIL: STORE[%0d] expected %h/%h/%h got %h/%h/%h",
                        st_count, exp_st_pc[st_count], exp_st_addr[st_count], exp_st_data[st_count],
                        dut.mem_store_commit_pc, dut.mem_store_commit_addr, dut.mem_store_commit_data);
                    errors = errors + 1;
                end
                st_count = st_count + 1;
            end

            if (dut.program_done) begin
                checks = checks + 1;
                if (wb_count != N_WB || st_count != N_ST ||
                    branch_count != 1 || mdu_start_count != N_MDU ||
                    mdu_result_count != N_MDU || dmem_req_count != 4 ||
                    dmem_resp_count != 4 || dut.fault_sticky !== 1'b0) begin
                    $display("FAIL RUN%0d counts WB=%0d ST=%0d BR=%0d MDU=%0d/%0d DMEM=%0d/%0d FAULT=%b",
                        completed_runs+1, wb_count, st_count, branch_count,
                        mdu_start_count, mdu_result_count, dmem_req_count, dmem_resp_count,
                        dut.fault_sticky);
                    errors = errors + 1;
                end
                checks = checks + 1;
                if (dut.cache_hits == 0 || dut.cache_misses == 0)
                    fail_check("expected both cache hits and misses");
                completed_runs = completed_runs + 1;
                $display("V09 EGO1 RUN %0d: WB=%0d/%0d STORE=%0d/%0d BR=%0d MDU=%0d/%0d DMEM=%0d/%0d HIT=%0d MISS=%0d FAULT=%b ERRORS=%0d",
                    completed_runs, wb_count, N_WB, st_count, N_ST, branch_count,
                    mdu_start_count, mdu_result_count, dmem_req_count, dmem_resp_count,
                    dut.cache_hits, dut.cache_misses, dut.fault_sticky, errors);
                if (phase == 1) phase = 10;
                else phase = 11;
            end
        end
    end

    // When internal reset has become asserted, its steady state must suppress
    // architectural commits. External assertion has two-clock sync latency.
    always @(negedge clk) begin
        if ((phase == 0 || phase == 2) && dut.rst === 1'b1) begin
            checks = checks + 1;
            if (dut.wb_commit_valid === 1'b1 ||
                dut.mem_store_commit_valid === 1'b1)
                fail_check("commit observed while internal reset held");
        end
    end

    initial begin
        #300000;
        $fatal(1, "V09 EGO1 RESET GLOBAL TIMEOUT phase=%0d wb=%0d st=%0d", phase, wb_count, st_count);
    end
endmodule
