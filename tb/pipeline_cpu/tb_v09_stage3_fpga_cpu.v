`timescale 1ns / 1ps
// V0.9 Stage 3 independent reference-program FPGA CPU wrapper regression.
// IMPORTANT: DUT is pipeline_cpu_fpga (FPGA-oriented wrapper), NOT ego1_top.
// Same 40-word program and golden commits as the previously passed V0.8 staging run.
// Requires existing v09_commit_scoreboard.v from Stage 2 / PR #40.
// Verilog-2001; verified in Vivado 2019.1.
// Independent V0.9 FPGA CPU wrapper regression: ALL TESTS PASSED.
module tb_v09_stage3_fpga_cpu;
    parameter MEM_FILE = "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/v09_stage3_hazard_mdu.mem";
    localparam integer N_WORDS=40, N_WB=29, N_ST=3, N_MDU=14;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, sb_rst=1, check_finish=0;
    wire if_resp_fire,if_resp_hold;
    wire if_ready; // read-only debug observation from FPGA wrapper
    wire fetch_error_fire,adapter_busy;
    wire [31:0] cache_hits,cache_misses,cache_refills,backing_transactions;
    wire program_done,fault_sticky;
    wire branch_resolve_valid,branch_redirect;
    wire [31:0] branch_redirect_pc;
    wire load_use_stall,id_unsupported,id_raw_hazard;
    wire wb_commit_valid;
    wire [31:0] wb_commit_pc,wb_commit_data;
    wire [4:0] wb_commit_rd;
    wire mem_store_commit_valid;
    wire [31:0] mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data;
    wire mem_stall,dmem_req_fire,dmem_resp_fire;
    wire mem_fault_valid;
    wire [31:0] mem_fault_pc,mem_fault_addr;
    wire mem_fault_store;
    wire mdu_start_fire,mdu_busy,mdu_done,mdu_result_fire,mdu_div_zero;
    wire [31:0] sb_wb_count,sb_st_count,sb_error_count;
    wire sb_check_done,sb_check_pass;
    integer cycles=0,branch_seen=0,redirect_seen=0,mdu_start_seen=0,mdu_result_seen=0;
    integer mem_req_seen=0,mem_resp_seen=0,mdu_busy_cycles=0,mem_stall_cycles=0;
    integer if_hold_cycles=0,other_errors=0;
    reg outstanding=0;

    pipeline_cpu_fpga #(
        .PC_BASE(32'h00001000),
        .PROGRAM_WORDS(N_WORDS),
        .IMEM_FILE(MEM_FILE),
        .DMEM_READ_LATENCY(8),
        .DMEM_WRITE_LATENCY(11),
        .DMEM_WORDS(256)
    ) dut (
        .clk(clk),.rst(rst),
        .wb_commit_valid(wb_commit_valid),.wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd),.wb_commit_data(wb_commit_data),
        .mem_store_commit_valid(mem_store_commit_valid),
        .mem_store_commit_pc(mem_store_commit_pc),
        .mem_store_commit_addr(mem_store_commit_addr),
        .mem_store_commit_data(mem_store_commit_data),
        .branch_resolve_valid(branch_resolve_valid),
        .branch_redirect(branch_redirect),.branch_redirect_pc(branch_redirect_pc),
        .load_use_stall(load_use_stall),.id_unsupported(id_unsupported),
        .id_raw_hazard(id_raw_hazard),
        .mem_stall(mem_stall),.dmem_req_fire(dmem_req_fire),
        .dmem_resp_fire(dmem_resp_fire),
        .mem_fault_valid(mem_fault_valid),.mem_fault_pc(mem_fault_pc),
        .mem_fault_addr(mem_fault_addr),.mem_fault_store(mem_fault_store),
        .mdu_start_fire(mdu_start_fire),.mdu_busy(mdu_busy),
        .mdu_done(mdu_done),.mdu_result_fire(mdu_result_fire),
        .mdu_div_zero(mdu_div_zero),
        .if_resp_fire(if_resp_fire),.if_resp_hold(if_resp_hold),
        .fetch_error_fire(fetch_error_fire),.adapter_busy(adapter_busy),
        .cache_hits(cache_hits),.cache_misses(cache_misses),
        .cache_refills(cache_refills),.backing_transactions(backing_transactions),
        .program_done(program_done),.fault_sticky(fault_sticky)
    );

    // Only this non-architectural check accesses a read-only internal signal.
    // No force/deposit or RTL modification is performed.
    assign if_ready = dut.if_ready;

    v09_commit_scoreboard #(.MAX_WB(64),.MAX_STORE(16)) sb (
        .clk(clk),.sb_rst(sb_rst),
        .wb_commit_valid(wb_commit_valid),.wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd),.wb_commit_data(wb_commit_data),
        .store_commit_valid(mem_store_commit_valid),
        .store_commit_pc(mem_store_commit_pc),
        .store_commit_addr(mem_store_commit_addr),
        .store_commit_data(mem_store_commit_data),
        .check_finish(check_finish),
        .wb_count(sb_wb_count),.store_count(sb_st_count),
        .error_count(sb_error_count),.check_done(sb_check_done),
        .check_pass(sb_check_pass)
    );

    initial begin
        // Wait beyond module initial blocks before programming reference arrays.
        #1;
        sb.clear_expectations();
        sb.expect_wb(32'h00001000,5'd1,32'h00000006); // word 0 ADDI.W
        sb.expect_wb(32'h00001004,5'd2,32'h00000003); // word 1 ADDI.W
        sb.expect_wb(32'h00001008,5'd3,32'h00000009); // word 2 ADD.W
        sb.expect_wb(32'h0000100c,5'd4,32'h00000006); // word 3 SUB.W
        sb.expect_wb(32'h00001010,5'd5,32'h00000012); // word 4 MUL.W
        sb.expect_wb(32'h00001014,5'd6,32'h0000001b); // word 5 ADD.W
        sb.expect_wb(32'h00001018,5'd7,32'h00000009); // word 6 DIV.W
        sb.expect_wb(32'h0000101c,5'd8,32'h00000003); // word 7 MOD.W
        sb.expect_wb(32'h00001020,5'd9,32'h00000000); // word 8 MULH.W
        sb.expect_wb(32'h00001024,5'd10,32'h00000000); // word 9 MULH.WU
        sb.expect_wb(32'h00001028,5'd11,32'h00000009); // word 10 DIV.WU
        sb.expect_wb(32'h0000102c,5'd12,32'h00000003); // word 11 MOD.WU
        sb.expect_wb(32'h00001034,5'd13,32'h00000012); // word 13 LD.W
        sb.expect_wb(32'h00001038,5'd14,32'h0000001b); // word 14 ADD.W
        sb.expect_wb(32'h0000104c,5'd16,32'h00000036); // word 19 MUL.W
        sb.expect_wb(32'h00001050,5'd17,32'h00000037); // word 20 ADDI.W
        sb.expect_wb(32'h00001058,5'd18,32'h00000037); // word 22 LD.W
        sb.expect_wb(32'h0000105c,5'd19,32'h00000001); // word 23 MOD.W
        sb.expect_wb(32'h00001070,5'd21,32'h0000006e); // word 28 ADD.W
        sb.expect_wb(32'h00001074,5'd22,32'h00000075); // word 29 XOR
        sb.expect_wb(32'h0000107c,5'd23,32'h00000075); // word 31 LD.W
        sb.expect_wb(32'h00001080,5'd24,32'h00000074); // word 32 ADDI.W
        sb.expect_wb(32'h00001084,5'd25,32'h0000000f); // word 33 ORI
        sb.expect_wb(32'h00001088,5'd26,32'hfffffff9); // word 34 ADDI.W
        sb.expect_wb(32'h0000108c,5'd27,32'hffffffeb); // word 35 MUL.W
        sb.expect_wb(32'h00001090,5'd28,32'hfffffff9); // word 36 DIV.W
        sb.expect_wb(32'h00001094,5'd29,32'hfffffffd); // word 37 MOD.W
        sb.expect_wb(32'h00001098,5'd30,32'hffffffff); // word 38 MULH.W
        sb.expect_wb(32'h0000109c,5'd31,32'h00000002); // word 39 MULH.WU
        sb.expect_store(32'h00001030,32'h00000004,32'h00000012); // word 12 ST.W
        sb.expect_store(32'h00001054,32'h0000000c,32'h00000037); // word 21 ST.W
        sb.expect_store(32'h00001078,32'h00000014,32'h00000075); // word 30 ST.W
        repeat(4) @(negedge clk);
        rst=0;
        sb_rst=0;
        wait ((sb_wb_count==N_WB) && (sb_st_count==N_ST));
        // Wait for the FPGA wrapper's own finite-ROM completion indicator.
        // The global watchdog below catches a missing or stuck program_done.
        wait (program_done === 1'b1);
        // Extra observation window catches duplicate or late WB/Store commits.
        repeat(30) @(negedge clk);
        check_finish=1;
        @(negedge clk);
        check_finish=0;
        repeat(20) @(negedge clk);
        if (sb_check_done !== 1'b1 || sb_check_pass !== 1'b1 ||
            sb_error_count !== 32'd0) begin
            other_errors=other_errors+1;
            $display("FAIL scoreboard final result WB=%0d ST=%0d errors=%0d",sb_wb_count,sb_st_count,sb_error_count);
        end
        if (program_done !== 1'b1 || fault_sticky !== 1'b0 ||
            cache_hits === 32'd0 || cache_misses === 32'd0 ||
            backing_transactions === 32'd0 ||
            (^cache_hits === 1'bx) || (^cache_misses === 1'bx) ||
            (^backing_transactions === 1'bx)) begin
            other_errors=other_errors+1;
            $display("FAIL FPGA wrapper state done=%b fault=%b hits=%0d misses=%0d backing=%0d",
                     program_done,fault_sticky,cache_hits,cache_misses,backing_transactions);
        end
        if (branch_seen!=4 || redirect_seen!=2 || mdu_start_seen!=N_MDU ||
            mdu_result_seen!=N_MDU || mem_req_seen!=6 || mem_resp_seen!=6 ||
            outstanding || mdu_busy_cycles==0 || mem_stall_cycles==0 ||
            if_hold_cycles==0) begin
            other_errors=other_errors+1;
            $display("FAIL final counters: branches=%0d redirects=%0d MDU=%0d/%0d DMEM=%0d/%0d outstanding=%b MDU_BUSY=%0d MEM_STALL=%0d IF_HOLD=%0d",
                branch_seen,redirect_seen,mdu_start_seen,mdu_result_seen,
                mem_req_seen,mem_resp_seen,outstanding,mdu_busy_cycles,mem_stall_cycles,if_hold_cycles);
        end
        if (dut.u_cpu.u_dmem.mem[1] !== 32'd18 ||
            dut.u_cpu.u_dmem.mem[2] !== 32'd0 ||
            dut.u_cpu.u_dmem.mem[3] !== 32'd55 ||
            dut.u_cpu.u_dmem.mem[4] !== 32'd0 ||
            dut.u_cpu.u_dmem.mem[5] !== 32'd117 ||
            dut.u_cpu.u_regfile.regs[15] !== 32'd0 ||
            dut.u_cpu.u_regfile.regs[20] !== 32'd0) begin
            other_errors=other_errors+1;
            $display("FAIL final RAM/wrong-path state ram1=%h ram2=%h ram3=%h ram4=%h ram5=%h r15=%h r20=%h",
                dut.u_cpu.u_dmem.mem[1],dut.u_cpu.u_dmem.mem[2],
                dut.u_cpu.u_dmem.mem[3],dut.u_cpu.u_dmem.mem[4],
                dut.u_cpu.u_dmem.mem[5],
                dut.u_cpu.u_regfile.regs[15],dut.u_cpu.u_regfile.regs[20]);
        end
        $display("V09 STAGE3 FPGA RESULT WB=%0d/29 STORE=%0d/3 BR=%0d REDIRECT=%0d MDU=%0d/%0d DMEM=%0d/%0d CACHE_HIT=%0d CACHE_MISS=%0d IF_HOLD=%0d PROGRAM_DONE=%b FAULT=%b OTHER_ERRORS=%0d SB_ERRORS=%0d",
            sb_wb_count,sb_st_count,branch_seen,redirect_seen,mdu_start_seen,
            mdu_result_seen,mem_req_seen,mem_resp_seen,
            cache_hits,cache_misses,if_hold_cycles,program_done,fault_sticky,
            other_errors,sb_error_count);
        if (other_errors==0 && sb_check_pass && sb_error_count==0)
            $display("ALL TESTS PASSED (V0.9 Stage3 program on pipeline_cpu_fpga wrapper)");
        else
            $fatal(1,"V09 STAGE3 FPGA CPU REGRESSION FAILED");
        $finish;
    end

    // Separate hard timeout is required even if no WB ever occurs.
    initial begin
        repeat(20000) @(posedge clk);
        $fatal(1,"TIMEOUT Stage3 WB=%0d/%0d Store=%0d/%0d",sb_wb_count,N_WB,sb_st_count,N_ST);
    end

    always @(posedge clk) begin
        if (!rst) begin
            cycles=cycles+1;
            if (fetch_error_fire || mem_fault_valid || id_unsupported) begin
                other_errors=other_errors+1;
                $display("FAIL unexpected fetch/memory/unsupported event fault_pc=%h addr=%h unsupported=%b",mem_fault_pc,mem_fault_addr,id_unsupported);
            end
            if (mdu_start_fire) mdu_start_seen=mdu_start_seen+1;
            if (mdu_result_fire) begin
                mdu_result_seen=mdu_result_seen+1;
                if (!mdu_done) begin
                    other_errors=other_errors+1;
                    $display("FAIL MDU result accepted without done");
                end
            end
            if (mdu_busy) mdu_busy_cycles=mdu_busy_cycles+1;
            if (mem_stall) mem_stall_cycles=mem_stall_cycles+1;
            if (if_resp_hold) if_hold_cycles=if_hold_cycles+1;
            if (mem_stall && if_ready) begin
                other_errors=other_errors+1;
                $display("FAIL IF ready while MEM stalled");
            end
            if (mdu_busy && if_ready) begin
                other_errors=other_errors+1;
                $display("FAIL IF ready while MDU busy");
            end
            if (branch_resolve_valid) branch_seen=branch_seen+1;
            if (branch_redirect) begin
                if (redirect_seen==0 && branch_redirect_pc!==32'h0000104c) begin
                    other_errors=other_errors+1;
                    $display("FAIL first redirect expected 104c got %h",branch_redirect_pc);
                end
                if (redirect_seen==1 && branch_redirect_pc!==32'h00001070) begin
                    other_errors=other_errors+1;
                    $display("FAIL second redirect expected 1070 got %h",branch_redirect_pc);
                end
                if (redirect_seen>=2) begin
                    other_errors=other_errors+1;
                    $display("FAIL unexpected extra redirect PC %h",branch_redirect_pc);
                end
                redirect_seen=redirect_seen+1;
            end
            if (dmem_req_fire) begin
                if (outstanding) begin
                    other_errors=other_errors+1;
                    $display("FAIL overlapping DMEM request");
                end
                outstanding=1;
                mem_req_seen=mem_req_seen+1;
            end
            if (dmem_resp_fire) begin
                if (!outstanding) begin
                    other_errors=other_errors+1;
                    $display("FAIL response without accepted request");
                end
                outstanding=0;
                mem_resp_seen=mem_resp_seen+1;
            end
        end
    end
endmodule
