`timescale 1ns / 1ps
// V0.8 directed Store->MDU overlap regression.
// Uses the datapath-level ready/valid IF stream (not the serialized I-Cache
// adapter) so the younger MUL.W is already resident in EX when the older
// ST.W occupies MEM and waits for its multi-cycle response.
module tb_pipeline_cpu_v08_mdu_store_wait_stress;
    localparam [31:0] PC_BASE = 32'h00001000;
    localparam integer N_WB = 4;
    localparam integer N_STORE = 1;
    localparam integer N_MEM = 1;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;
    reg src_active = 1'b1;
    reg [31:0] src_pc = PC_BASE;
    wire if_valid = src_active;
    wire [31:0] if_pc = src_pc;
    reg [31:0] if_inst;

    wire if_ready;
    wire branch_resolve_valid, branch_redirect;
    wire [31:0] branch_redirect_pc;
    wire wb_commit_valid, mem_store_commit_valid;
    wire [31:0] wb_commit_pc, wb_commit_data;
    wire [4:0] wb_commit_rd;
    wire [31:0] mem_store_commit_pc, mem_store_commit_addr, mem_store_commit_data;
    wire load_use_stall, id_unsupported, id_raw_hazard;
    wire mem_stall, dmem_req_fire, dmem_resp_fire;
    wire mem_fault_valid;
    wire [31:0] mem_fault_pc, mem_fault_addr;
    wire mem_fault_store;
    wire mdu_start_fire, mdu_busy, mdu_done, mdu_result_fire, mdu_div_zero;

    // Sequence:
    //   ADDI.W r1,r0,0
    //   ADDI.W r2,r0,7
    //   ST.W    r2,[r1+0]       (older, multi-cycle MEM)
    //   MUL.W   r3,r2,r2        (younger, must wait in EX)
    //   ADDI.W  r4,r3,1          (checks MDU->ALU forwarding)
    //   unsupported sentinel
    always @(*) begin
        case (src_pc)
            32'h00001000: if_inst = 32'h02800001;
            32'h00001004: if_inst = 32'h02801c02;
            32'h00001008: if_inst = 32'h29800022;
            32'h0000100c: if_inst = 32'h001c0843;
            32'h00001010: if_inst = 32'h02800464;
            32'h00001014: if_inst = 32'hffffffff;
            default:      if_inst = 32'hffffffff;
        endcase
    end

    pipeline_cpu_core_v08_mdu_datapath #(
        .DMEM_READ_LATENCY(8),
        .DMEM_WRITE_LATENCY(12),
        .DMEM_WORDS(64)
    ) dut (
        .clk(clk), .rst(rst),
        .if_valid(if_valid), .if_pc(if_pc), .if_inst(if_inst),
        .if_ready(if_ready),
        .branch_resolve_valid(branch_resolve_valid),
        .branch_redirect(branch_redirect),
        .branch_redirect_pc(branch_redirect_pc),
        .wb_commit_valid(wb_commit_valid), .wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd), .wb_commit_data(wb_commit_data),
        .mem_store_commit_valid(mem_store_commit_valid),
        .mem_store_commit_pc(mem_store_commit_pc),
        .mem_store_commit_addr(mem_store_commit_addr),
        .mem_store_commit_data(mem_store_commit_data),
        .load_use_stall(load_use_stall),
        .id_unsupported(id_unsupported), .id_raw_hazard(id_raw_hazard),
        .mem_stall(mem_stall), .dmem_req_fire(dmem_req_fire),
        .dmem_resp_fire(dmem_resp_fire),
        .mem_fault_valid(mem_fault_valid),
        .mem_fault_pc(mem_fault_pc), .mem_fault_addr(mem_fault_addr),
        .mem_fault_store(mem_fault_store),
        .mdu_start_fire(mdu_start_fire), .mdu_busy(mdu_busy),
        .mdu_done(mdu_done), .mdu_result_fire(mdu_result_fire),
        .mdu_div_zero(mdu_div_zero)
    );

    reg [31:0] exp_wb_pc [0:N_WB-1];
    reg [4:0]  exp_wb_rd [0:N_WB-1];
    reg [31:0] exp_wb_data [0:N_WB-1];

    integer wb_count = 0;
    integer store_count = 0;
    integer req_count = 0;
    integer resp_count = 0;
    integer mdu_start_count = 0;
    integer mdu_done_count = 0;
    integer mdu_result_count = 0;
    integer mdu_wait_mem_cycles = 0;
    integer mdu_busy_cycles = 0;
    integer mem_stall_cycles = 0;
    integer unsupported_count = 0;
    integer cycles = 0;
    integer after_done = 0;
    integer errors = 0;

    reg prev_mdu_done = 1'b0;
    reg req_outstanding = 1'b0;

    task fail;
        input [8*180-1:0] message;
        begin
            errors = errors + 1;
            $display("FAIL V0.8 STORE/MDU WAIT: %0s @%0t", message, $time);
        end
    endtask

    initial begin
        exp_wb_pc[0] = 32'h00001000; exp_wb_rd[0] = 5'd1; exp_wb_data[0] = 32'd0;
        exp_wb_pc[1] = 32'h00001004; exp_wb_rd[1] = 5'd2; exp_wb_data[1] = 32'd7;
        exp_wb_pc[2] = 32'h0000100c; exp_wb_rd[2] = 5'd3; exp_wb_data[2] = 32'd49;
        exp_wb_pc[3] = 32'h00001010; exp_wb_rd[3] = 5'd4; exp_wb_data[3] = 32'd50;
        repeat (4) @(negedge clk);
        rst = 1'b0;
    end

    // Stable direct IF source: advance only on if_valid && if_ready.
    always @(posedge clk) begin
        if (rst) begin
            src_pc <= PC_BASE;
            src_active <= 1'b1;
        end else if (branch_redirect) begin
            src_pc <= branch_redirect_pc;
            src_active <= 1'b1;
        end else if (if_valid && if_ready) begin
            if (if_inst == 32'hffffffff)
                src_active <= 1'b0;
            else
                src_pc <= src_pc + 32'd4;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            prev_mdu_done = 1'b0;
        end else begin
            cycles = cycles + 1;

            if (branch_redirect || branch_resolve_valid)
                fail("Unexpected branch in directed Store/MDU program");
            if (mem_fault_valid)
                fail("Unexpected DMEM fault");
            if (mdu_div_zero)
                fail("Unexpected MDU divide-by-zero");
            if (mem_stall && if_ready)
                fail("IF ready remained high during older Store MEM stall");
            if (mdu_start_fire && mem_stall)
                fail("MDU started before older Store response completed");
            if (mdu_busy && mem_stall)
                fail("MDU iterated concurrently with real DMEM MEM stall");

            if (dut.ex_valid && dut.ex_is_mdu && mem_stall && !dut.mdu_started) begin
                mdu_wait_mem_cycles = mdu_wait_mem_cycles + 1;
                if (dut.ex_pc !== 32'h0000100c)
                    fail("Unexpected MDU PC waiting behind Store");
                if (!dut.mem_valid || !dut.mem_mem_write || dut.mem_pc !== 32'h00001008)
                    fail("MDU EX wait was not caused by the expected older ST.W in MEM");
            end

            if (mem_stall)
                mem_stall_cycles = mem_stall_cycles + 1;
            if (mdu_busy)
                mdu_busy_cycles = mdu_busy_cycles + 1;
            if (id_unsupported)
                unsupported_count = unsupported_count + 1;

            if (dmem_req_fire) begin
                if (req_outstanding)
                    fail("Overlapping DMEM request");
                req_outstanding = 1'b1;
                req_count = req_count + 1;
            end
            if (dmem_resp_fire) begin
                if (!req_outstanding)
                    fail("DMEM response without accepted request");
                req_outstanding = 1'b0;
                resp_count = resp_count + 1;
            end

            if (mem_store_commit_valid) begin
                if (store_count != 0)
                    fail("Duplicate or unexpected Store commit");
                if (mem_store_commit_pc !== 32'h00001008 ||
                    mem_store_commit_addr !== 32'd0 ||
                    mem_store_commit_data !== 32'd7)
                    fail("Store PC/address/data mismatch");
                store_count = store_count + 1;
            end

            if (mdu_start_fire) begin
                if (mdu_start_count != 0 || dut.ex_pc !== 32'h0000100c ||
                    dut.ex_mdu_op !== 3'b000)
                    fail("Expected exactly one MUL.W start at PC 0x100c");
                if (store_count != 1)
                    fail("MUL.W started before the older Store committed");
                mdu_start_count = mdu_start_count + 1;
            end

            if (mdu_done && !prev_mdu_done) begin
                if (mdu_done_count != 0 || dut.ex_pc !== 32'h0000100c ||
                    dut.u_mdu.result !== 32'd49)
                    fail("MUL.W Done PC/result mismatch");
                mdu_done_count = mdu_done_count + 1;
            end
            prev_mdu_done = mdu_done;

            if (mdu_result_fire) begin
                if (mdu_result_count != 0 || dut.ex_pc !== 32'h0000100c ||
                    dut.u_mdu.result !== 32'd49)
                    fail("MUL.W result transfer was duplicated or incorrect");
                mdu_result_count = mdu_result_count + 1;
            end

            if (wb_commit_valid) begin
                if (wb_count >= N_WB) begin
                    fail("Unexpected extra WB commit");
                end else begin
                    if (wb_commit_pc !== exp_wb_pc[wb_count] ||
                        wb_commit_rd !== exp_wb_rd[wb_count] ||
                        wb_commit_data !== exp_wb_data[wb_count])
                        fail("WB order/PC/rd/data mismatch");
                end
                wb_count = wb_count + 1;
            end

            if (cycles > 3000)
                $fatal(1, "V0.8 Store/MDU wait regression timeout");

            if (wb_count == N_WB && store_count == N_STORE &&
                req_count == N_MEM && resp_count == N_MEM &&
                mdu_start_count == 1 && mdu_done_count == 1 &&
                mdu_result_count == 1 && unsupported_count == 1 &&
                !src_active && !req_outstanding)
                after_done = after_done + 1;
            else
                after_done = 0;

            if (after_done == 12) begin
                if (mdu_wait_mem_cycles == 0)
                    fail("No MDU EX wait cycles were observed behind the older Store");
                if (mem_stall_cycles == 0 || mdu_busy_cycles == 0)
                    fail("Required Store MEM stall or MDU Busy coverage missing");
                if (wb_count != N_WB || store_count != N_STORE ||
                    req_count != N_MEM || resp_count != N_MEM ||
                    mdu_start_count != 1 || mdu_done_count != 1 ||
                    mdu_result_count != 1)
                    fail("Final transaction/retirement count mismatch");
                if (dut.u_dmem.mem[0] !== 32'd7)
                    fail("Final DMEM word[0] mismatch");
                if (dut.u_regfile.regs[1] !== 32'd0 ||
                    dut.u_regfile.regs[2] !== 32'd7 ||
                    dut.u_regfile.regs[3] !== 32'd49 ||
                    dut.u_regfile.regs[4] !== 32'd50)
                    fail("Final architectural register contents mismatch");

                $display("V0.8 STORE/MDU WAIT RESULT:");
                $display("WB=%0d/%0d STORE=%0d/%0d DMEM_REQ=%0d DMEM_RESP=%0d",
                    wb_count, N_WB, store_count, N_STORE, req_count, resp_count);
                $display("MDU_START=%0d MDU_DONE=%0d MDU_RESULT=%0d",
                    mdu_start_count, mdu_done_count, mdu_result_count);
                $display("STORE_MDU_WAIT_CYCLES=%0d MEM_STALL_CYCLES=%0d MDU_BUSY_CYCLES=%0d UNSUPPORTED=%0d ERRORS=%0d",
                    mdu_wait_mem_cycles, mem_stall_cycles, mdu_busy_cycles,
                    unsupported_count, errors);
                if (errors == 0)
                    $display("ALL TESTS PASSED (V0.8 directed Store->MDU wait regression)");
                else
                    $display("TESTS FAILED errors=%0d", errors);
                $finish;
            end
        end
    end
endmodule
