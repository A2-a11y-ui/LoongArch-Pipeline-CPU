`timescale 1ns / 1ps
// V0.8 datapath-level load-use regression.
// Deliberately bypasses the serialized I-Cache adapter and supplies one
// instruction per accepted IF cycle. This guarantees true adjacent
// LD.W -> consumer overlaps in ID/EX and IF/ID.
// Full CPU + I-Cache integration is checked separately by
// tb_pipeline_cpu_v08_mdu_stress.
module tb_pipeline_cpu_v08_mdu_datapath_loaduse_stress;
    localparam [31:0] PC_BASE = 32'h00001000;
    localparam integer N_WB = 10;
    localparam integer N_STORE = 5;
    localparam integer N_MEM = 9;

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

    // Count the actual ID/EX bubble insertion, not the raw hazard level.
    // load_use_stall may remain high while an older MEM transaction stalls
    // the EX load in place. The bubble is inserted only when front_stall
    // clears, through id_ex_reg.flush = bubble_idex_req && !front_stall.
    wire effective_load_use_bubble;

    // The source presents a stable instruction until if_valid && if_ready.
    // Four immediate load consumers are intentionally placed back-to-back:
    //   LD.W r3 -> MUL.W r4,r3,r2
    //   LD.W r5 -> DIV.W r6,r5,r2
    //   LD.W r7 -> ADDI.W r8,r7,1
    //   LD.W r9 -> ADD.W r10,r9,r2
    always @(*) begin
        case (src_pc)
            32'h00001000: if_inst = 32'h02810001; // ADDI.W r1,r0,64
            32'h00001004: if_inst = 32'h02805402; // ADDI.W r2,r0,21
            32'h00001008: if_inst = 32'h29800022; // ST.W r2,[r1+0]
            32'h0000100c: if_inst = 32'h28800023; // LD.W r3,[r1+0]
            32'h00001010: if_inst = 32'h001c0864; // MUL.W r4,r3,r2
            32'h00001014: if_inst = 32'h28800025; // LD.W r5,[r1+0]
            32'h00001018: if_inst = 32'h002008a6; // DIV.W r6,r5,r2
            32'h0000101c: if_inst = 32'h28800027; // LD.W r7,[r1+0]
            32'h00001020: if_inst = 32'h028004e8; // ADDI.W r8,r7,1
            32'h00001024: if_inst = 32'h28800029; // LD.W r9,[r1+0]
            32'h00001028: if_inst = 32'h0010092a; // ADD.W r10,r9,r2
            32'h0000102c: if_inst = 32'h29801024; // ST.W r4,[r1+4]
            32'h00001030: if_inst = 32'h29802026; // ST.W r6,[r1+8]
            32'h00001034: if_inst = 32'h29803028; // ST.W r8,[r1+12]
            32'h00001038: if_inst = 32'h2980402a; // ST.W r10,[r1+16]
            32'h0000103c: if_inst = 32'hffffffff; // unsupported end marker
            default:      if_inst = 32'hffffffff;
        endcase
    end

    pipeline_cpu_core_v08_mdu_datapath #(
        .DMEM_READ_LATENCY(8),
        .DMEM_WRITE_LATENCY(9),
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
        .mem_fault_valid(mem_fault_valid), .mem_fault_pc(mem_fault_pc),
        .mem_fault_addr(mem_fault_addr), .mem_fault_store(mem_fault_store),
        .mdu_start_fire(mdu_start_fire), .mdu_busy(mdu_busy),
        .mdu_done(mdu_done), .mdu_result_fire(mdu_result_fire),
        .mdu_div_zero(mdu_div_zero)
    );

    // This expression mirrors the actual ID/EX flush condition in the DUT.
    assign effective_load_use_bubble = dut.bubble_idex_req &&
                                       !dut.front_stall && !branch_redirect;

    reg [31:0] exp_wb_pc [0:N_WB-1];
    reg [4:0]  exp_wb_rd [0:N_WB-1];
    reg [31:0] exp_wb_data [0:N_WB-1];
    reg [31:0] exp_st_pc [0:N_STORE-1];
    reg [31:0] exp_st_addr [0:N_STORE-1];
    reg [31:0] exp_st_data [0:N_STORE-1];

    integer wb_count = 0;
    integer store_count = 0;
    integer req_count = 0;
    integer resp_count = 0;
    integer mdu_start_count = 0;
    integer mdu_done_count = 0;
    integer mdu_result_count = 0;
    integer load_use_episodes = 0;
    integer load_use_bubble_cycles = 0;
    integer load_use_high_cycles = 0;
    integer mem_stall_cycles = 0;
    integer mdu_busy_cycles = 0;
    integer unsupported_count = 0;
    integer errors = 0;
    integer cycles = 0;
    integer after_done = 0;

    reg prev_load_use_bubble = 1'b0;
    reg prev_mdu_done = 1'b0;
    reg req_outstanding = 1'b0;

    task fail;
        input [8*160-1:0] message;
        begin
            errors = errors + 1;
            $display("FAIL @%0t: %0s", $time, message);
        end
    endtask

    initial begin
        exp_wb_pc[0]=32'h00001000; exp_wb_rd[0]=5'd1;  exp_wb_data[0]=32'd64;
        exp_wb_pc[1]=32'h00001004; exp_wb_rd[1]=5'd2;  exp_wb_data[1]=32'd21;
        exp_wb_pc[2]=32'h0000100c; exp_wb_rd[2]=5'd3;  exp_wb_data[2]=32'd21;
        exp_wb_pc[3]=32'h00001010; exp_wb_rd[3]=5'd4;  exp_wb_data[3]=32'd441;
        exp_wb_pc[4]=32'h00001014; exp_wb_rd[4]=5'd5;  exp_wb_data[4]=32'd21;
        exp_wb_pc[5]=32'h00001018; exp_wb_rd[5]=5'd6;  exp_wb_data[5]=32'd1;
        exp_wb_pc[6]=32'h0000101c; exp_wb_rd[6]=5'd7;  exp_wb_data[6]=32'd21;
        exp_wb_pc[7]=32'h00001020; exp_wb_rd[7]=5'd8;  exp_wb_data[7]=32'd22;
        exp_wb_pc[8]=32'h00001024; exp_wb_rd[8]=5'd9;  exp_wb_data[8]=32'd21;
        exp_wb_pc[9]=32'h00001028; exp_wb_rd[9]=5'd10; exp_wb_data[9]=32'd42;

        exp_st_pc[0]=32'h00001008; exp_st_addr[0]=32'd64; exp_st_data[0]=32'd21;
        exp_st_pc[1]=32'h0000102c; exp_st_addr[1]=32'd68; exp_st_data[1]=32'd441;
        exp_st_pc[2]=32'h00001030; exp_st_addr[2]=32'd72; exp_st_data[2]=32'd1;
        exp_st_pc[3]=32'h00001034; exp_st_addr[3]=32'd76; exp_st_data[3]=32'd22;
        exp_st_pc[4]=32'h00001038; exp_st_addr[4]=32'd80; exp_st_data[4]=32'd42;

        repeat (4) @(negedge clk);
        rst = 1'b0;
    end

    // Direct IF stream: one new instruction per accepted cycle.
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
            prev_load_use_bubble = 1'b0;
            prev_mdu_done = 1'b0;
        end else begin
            cycles = cycles + 1;

            // Diagnostic only: the raw hazard request can span multiple
            // cycles if MEM backpressure keeps the producing load in EX.
            if (load_use_stall)
                load_use_high_cycles = load_use_high_cycles + 1;

            // Functional interlock event: one ID/EX bubble is inserted when
            // the load-use dependency is actionable (front_stall is clear).
            if (effective_load_use_bubble) begin
                if (!load_use_stall || !dut.id_valid ||
                    !dut.ex_valid || !dut.ex_mem_read)
                    fail("ID/EX Load-use bubble lacks a valid ID consumer or EX load");
                load_use_bubble_cycles = load_use_bubble_cycles + 1;
                if (!prev_load_use_bubble) begin
                    load_use_episodes = load_use_episodes + 1;
                    $display("LOAD_USE_BUBBLE[%0d] @%0t ID_PC=%08h ID_INST=%08h EX_PC=%08h EX_INST=%08h EX_RD=%0d",
                        load_use_episodes, $time,
                        dut.id_pc, dut.id_inst, dut.ex_pc, dut.ex_inst, dut.ex_rd_addr);
                end
            end
            prev_load_use_bubble = effective_load_use_bubble;

            if (mem_stall)
                mem_stall_cycles = mem_stall_cycles + 1;
            if (mdu_busy)
                mdu_busy_cycles = mdu_busy_cycles + 1;
            if (id_unsupported)
                unsupported_count = unsupported_count + 1;

            if (branch_redirect || branch_resolve_valid)
                fail("No branch instruction is expected in this datapath program");
            if (mem_fault_valid)
                fail("Unexpected DMEM fault");
            if (mdu_div_zero)
                fail("Unexpected MDU divide-by-zero");
            if (mem_stall && if_ready)
                fail("IF ready must be low during MEM backpressure");

            if (dmem_req_fire) begin
                req_count = req_count + 1;
                if (req_outstanding)
                    fail("Overlapping DMEM request");
                req_outstanding = 1'b1;
            end
            if (dmem_resp_fire) begin
                resp_count = resp_count + 1;
                if (!req_outstanding)
                    fail("DMEM response without accepted request");
                req_outstanding = 1'b0;
            end

            if (wb_commit_valid) begin
                if (wb_count >= N_WB) begin
                    fail("Unexpected extra WB commit");
                end else begin
                    if (wb_commit_pc !== exp_wb_pc[wb_count] ||
                        wb_commit_rd !== exp_wb_rd[wb_count] ||
                        wb_commit_data !== exp_wb_data[wb_count]) begin
                        $display("WB[%0d] got PC=%08h rd=%0d data=%08h expected PC=%08h rd=%0d data=%08h",
                            wb_count, wb_commit_pc, wb_commit_rd, wb_commit_data,
                            exp_wb_pc[wb_count], exp_wb_rd[wb_count], exp_wb_data[wb_count]);
                        fail("WB order/data mismatch");
                    end
                end
                wb_count = wb_count + 1;
            end

            if (mem_store_commit_valid) begin
                if (store_count >= N_STORE) begin
                    fail("Unexpected extra Store commit");
                end else begin
                    if (mem_store_commit_pc !== exp_st_pc[store_count] ||
                        mem_store_commit_addr !== exp_st_addr[store_count] ||
                        mem_store_commit_data !== exp_st_data[store_count]) begin
                        $display("STORE[%0d] got PC=%08h addr=%08h data=%08h expected PC=%08h addr=%08h data=%08h",
                            store_count, mem_store_commit_pc, mem_store_commit_addr,
                            mem_store_commit_data, exp_st_pc[store_count],
                            exp_st_addr[store_count], exp_st_data[store_count]);
                        fail("Store order/address/data mismatch");
                    end
                end
                store_count = store_count + 1;
            end

            if (mdu_start_fire) begin
                if (mdu_start_count == 0) begin
                    if (dut.ex_pc !== 32'h00001010 || dut.ex_mdu_op !== 3'b000)
                        fail("First MDU start must be MUL.W at PC 0x1010");
                end else if (mdu_start_count == 1) begin
                    if (dut.ex_pc !== 32'h00001018 || dut.ex_mdu_op !== 3'b011)
                        fail("Second MDU start must be DIV.W at PC 0x1018");
                end else begin
                    fail("Unexpected extra MDU start");
                end
                mdu_start_count = mdu_start_count + 1;
            end

            if (mdu_done && !prev_mdu_done) begin
                if (mdu_done_count == 0) begin
                    if (dut.ex_pc !== 32'h00001010 ||
                        dut.u_mdu.result !== 32'd441)
                        fail("MUL.W Done result/PC mismatch");
                end else if (mdu_done_count == 1) begin
                    if (dut.ex_pc !== 32'h00001018 ||
                        dut.u_mdu.result !== 32'd1)
                        fail("DIV.W Done result/PC mismatch");
                end else begin
                    fail("Unexpected extra MDU Done");
                end
                mdu_done_count = mdu_done_count + 1;
            end
            prev_mdu_done = mdu_done;

            if (mdu_result_fire) begin
                if (mdu_result_count >= 2)
                    fail("Unexpected extra MDU result transfer");
                mdu_result_count = mdu_result_count + 1;
            end

            if (cycles > 5000)
                $fatal(1, "V0.8 datapath Load-use stress timeout");

            if (wb_count == N_WB && store_count == N_STORE &&
                req_count == N_MEM && resp_count == N_MEM &&
                mdu_start_count == 2 && mdu_done_count == 2 &&
                mdu_result_count == 2 && unsupported_count == 1 &&
                !src_active && !req_outstanding)
                after_done = after_done + 1;
            else
                after_done = 0;

            if (after_done == 20) begin
                if (load_use_episodes != 4 || load_use_bubble_cycles != 4)
                    fail("Expected exactly four one-cycle ID/EX Load-use bubbles");
                if (wb_count != N_WB || store_count != N_STORE ||
                    req_count != N_MEM || resp_count != N_MEM)
                    fail("Final WB/Store/DMEM transaction count mismatch");
                if (mdu_start_count != 2 || mdu_done_count != 2 ||
                    mdu_result_count != 2)
                    fail("Final MDU handshake count mismatch");

                if (dut.u_dmem.mem[16] !== 32'd21 ||
                    dut.u_dmem.mem[17] !== 32'd441 ||
                    dut.u_dmem.mem[18] !== 32'd1 ||
                    dut.u_dmem.mem[19] !== 32'd22 ||
                    dut.u_dmem.mem[20] !== 32'd42)
                    fail("Final DMEM contents mismatch");

                if (dut.u_regfile.regs[1] !== 32'd64 ||
                    dut.u_regfile.regs[2] !== 32'd21 ||
                    dut.u_regfile.regs[3] !== 32'd21 ||
                    dut.u_regfile.regs[4] !== 32'd441 ||
                    dut.u_regfile.regs[5] !== 32'd21 ||
                    dut.u_regfile.regs[6] !== 32'd1 ||
                    dut.u_regfile.regs[7] !== 32'd21 ||
                    dut.u_regfile.regs[8] !== 32'd22 ||
                    dut.u_regfile.regs[9] !== 32'd21 ||
                    dut.u_regfile.regs[10] !== 32'd42)
                    fail("Final architectural register contents mismatch");

                $display("V0.8 DATAPATH LOAD-USE STRESS RESULT:");
                $display("WB=%0d/%0d STORE=%0d/%0d DMEM_REQ=%0d DMEM_RESP=%0d",
                    wb_count, N_WB, store_count, N_STORE, req_count, resp_count);
                $display("MDU_START=%0d MDU_DONE=%0d MDU_RESULT=%0d",
                    mdu_start_count, mdu_done_count, mdu_result_count);
                $display("LOAD_USE_BUBBLE_EPISODES=%0d LOAD_USE_BUBBLE_CYCLES=%0d RAW_HAZARD_HIGH_CYCLES=%0d",
                    load_use_episodes, load_use_bubble_cycles, load_use_high_cycles);
                $display("MEM_STALL_CYCLES=%0d MDU_BUSY_CYCLES=%0d UNSUPPORTED=%0d ERRORS=%0d",
                    mem_stall_cycles, mdu_busy_cycles, unsupported_count, errors);
                if (errors == 0)
                    $display("ALL TESTS PASSED (V0.8 datapath-level Load-use stress)");
                else
                    $display("TESTS FAILED errors=%0d", errors);
                $finish;
            end
        end
    end
endmodule
