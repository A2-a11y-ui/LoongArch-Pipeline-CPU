`timescale 1ns / 1ps
// V0.7 datapath-level stress regression.
// This test intentionally bypasses the serialized I-Cache adapter and drives
// the datapath IF ready/valid input at one instruction per accepted cycle.
// It verifies natural load-use interlocks and a branch held in EX behind an
// older multi-cycle Load. The full CPU+I-Cache contract is tested separately.
module tb_pipeline_cpu_v07_mem_datapath_stress;
    localparam [31:0] PC_BASE = 32'h00001000;
    localparam integer N_WB = 8;
    localparam integer N_STORE = 3;

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

    // Program is identical to the full top-level regression.
    // PC 0x101c/0x1020 are wrong-path ADDI/STORE and must be flushed.
    always @(*) begin
        case (src_pc)
            32'h00001000: if_inst = 32'h02810001; // ADDI.W r1,r0,64
            32'h00001004: if_inst = 32'h02805402; // ADDI.W r2,r0,21
            32'h00001008: if_inst = 32'h29800022; // ST.W r2,[r1+0]
            32'h0000100c: if_inst = 32'h28800023; // LD.W r3,[r1+0]
            32'h00001010: if_inst = 32'h02800464; // ADDI.W r4,r3,1 (load-use)
            32'h00001014: if_inst = 32'h28800025; // LD.W r5,[r1+0]
            32'h00001018: if_inst = 32'h50000c00; // B +12 -> 0x1024
            32'h0000101c: if_inst = 32'h02818c08; // wrong-path ADDI.W r8,r0,99
            32'h00001020: if_inst = 32'h29802028; // wrong-path ST.W r8,[r1+8]
            32'h00001024: if_inst = 32'h02801c09; // ADDI.W r9,r0,7
            32'h00001028: if_inst = 32'h29802029; // ST.W r9,[r1+8]
            32'h0000102c: if_inst = 32'h2880202a; // LD.W r10,[r1+8]
            32'h00001030: if_inst = 32'h0280054b; // ADDI.W r11,r10,1 (load-use)
            32'h00001034: if_inst = 32'h2980302b; // ST.W r11,[r1+12]
            32'h00001038: if_inst = 32'hffffffff; // unsupported end marker
            default:      if_inst = 32'hffffffff;
        endcase
    end

    pipeline_cpu_core_v07_mem_datapath #(
        .DMEM_READ_LATENCY(24),
        .DMEM_WRITE_LATENCY(28),
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
        .mem_fault_addr(mem_fault_addr), .mem_fault_store(mem_fault_store)
    );

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
    integer branch_count = 0;
    integer branch_resolve_count = 0;
    integer branch_wait_cycles = 0;
    integer load_use_count = 0;
    integer load_use_high_cycles = 0;
    integer mem_stall_cycles = 0;
    integer unsupported_count = 0;
    integer errors = 0;
    integer cycles = 0;
    integer after_done = 0;

    reg prev_load_use_stall = 1'b0;
    reg req_outstanding = 1'b0;
    reg old_mem_stall = 1'b0;
    reg old_mem_valid = 1'b0;
    reg [31:0] old_mem_pc = 32'd0;
    reg [31:0] old_mem_addr = 32'd0;
    reg [31:0] old_mem_store_data = 32'd0;
    reg [4:0] old_mem_rd = 5'd0;
    reg old_mem_read = 1'b0;
    reg old_mem_write = 1'b0;
    reg old_mem_reg_write = 1'b0;

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
        exp_wb_pc[3]=32'h00001010; exp_wb_rd[3]=5'd4;  exp_wb_data[3]=32'd22;
        exp_wb_pc[4]=32'h00001014; exp_wb_rd[4]=5'd5;  exp_wb_data[4]=32'd21;
        exp_wb_pc[5]=32'h00001024; exp_wb_rd[5]=5'd9;  exp_wb_data[5]=32'd7;
        exp_wb_pc[6]=32'h0000102c; exp_wb_rd[6]=5'd10; exp_wb_data[6]=32'd7;
        exp_wb_pc[7]=32'h00001030; exp_wb_rd[7]=5'd11; exp_wb_data[7]=32'd8;

        exp_st_pc[0]=32'h00001008; exp_st_addr[0]=32'd64; exp_st_data[0]=32'd21;
        exp_st_pc[1]=32'h00001028; exp_st_addr[1]=32'd72; exp_st_data[1]=32'd7;
        exp_st_pc[2]=32'h00001034; exp_st_addr[2]=32'd76; exp_st_data[2]=32'd8;

        repeat (4) @(negedge clk);
        rst = 1'b0;
    end

    // IF source: hold the current word stable until accepted. Redirect wins
    // over the current wrong-path offer and restarts the source at target PC.
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
            prev_load_use_stall = 1'b0;
        end else begin
            cycles = cycles + 1;

            if (mem_stall)
                mem_stall_cycles = mem_stall_cycles + 1;

            if (load_use_stall)
                load_use_high_cycles = load_use_high_cycles + 1;
            if (load_use_stall && !prev_load_use_stall) begin
                load_use_count = load_use_count + 1;
                $display("LOAD_USE_EVENT[%0d] @%0t", load_use_count, $time);
            end
            prev_load_use_stall = load_use_stall;

            if (id_unsupported)
                unsupported_count = unsupported_count + 1;

            if (mem_stall && if_ready)
                fail("IF ready must be low during MEM backpressure");
            if (mem_stall && branch_redirect)
                fail("branch redirect must wait until older MEM transaction completes");
            if (mem_fault_valid)
                fail("unexpected DMEM fault");

            if (dmem_req_fire) begin
                req_count = req_count + 1;
                if (req_outstanding)
                    fail("overlapping DMEM request");
                req_outstanding = 1'b1;
            end
            if (dmem_resp_fire) begin
                resp_count = resp_count + 1;
                if (!req_outstanding)
                    fail("DMEM response without accepted request");
                req_outstanding = 1'b0;
            end

            if (branch_resolve_valid)
                branch_resolve_count = branch_resolve_count + 1;
            if (branch_redirect) begin
                branch_count = branch_count + 1;
                if (branch_redirect_pc !== 32'h00001024)
                    fail("branch target must be 0x00001024");
            end

            if (wb_commit_valid) begin
                if (wb_count >= N_WB) begin
                    fail("unexpected extra WB");
                end else if (wb_commit_pc !== exp_wb_pc[wb_count] ||
                             wb_commit_rd !== exp_wb_rd[wb_count] ||
                             wb_commit_data !== exp_wb_data[wb_count]) begin
                    $display("WB mismatch[%0d]: got PC=%h rd=%0d data=%h; expected PC=%h rd=%0d data=%h",
                        wb_count, wb_commit_pc, wb_commit_rd, wb_commit_data,
                        exp_wb_pc[wb_count], exp_wb_rd[wb_count], exp_wb_data[wb_count]);
                    fail("WB order/data mismatch");
                end
                wb_count = wb_count + 1;
            end

            if (mem_store_commit_valid) begin
                if (store_count >= N_STORE) begin
                    fail("unexpected extra Store");
                end else if (mem_store_commit_pc !== exp_st_pc[store_count] ||
                             mem_store_commit_addr !== exp_st_addr[store_count] ||
                             mem_store_commit_data !== exp_st_data[store_count]) begin
                    $display("STORE mismatch[%0d]: got PC=%h addr=%h data=%h; expected PC=%h addr=%h data=%h",
                        store_count, mem_store_commit_pc, mem_store_commit_addr,
                        mem_store_commit_data, exp_st_pc[store_count],
                        exp_st_addr[store_count], exp_st_data[store_count]);
                    fail("Store order/address/data mismatch");
                end
                store_count = store_count + 1;
            end

            if (cycles > 5000)
                $fatal(1, "V0.7 datapath stress timeout");

            if (wb_count == N_WB && store_count == N_STORE &&
                branch_count == 1 && unsupported_count == 1 && !src_active)
                after_done = after_done + 1;
            else
                after_done = 0;

            if (after_done == 40) begin
                if (req_count != 6 || resp_count != 6 || req_outstanding)
                    fail("DMEM request/response count mismatch");
                if (branch_resolve_count != 1 || branch_wait_cycles == 0)
                    fail("branch was not held in EX behind the older multi-cycle Load");
                if (load_use_count != 2)
                    fail("expected exactly two natural Load-use hazard episodes");
                if (mem_stall_cycles == 0 || load_use_high_cycles == 0)
                    fail("expected multi-cycle MEM backpressure and Load-use interlocks");

if (dut.u_dmem.mem[16] !== 32'd21 ||
    dut.u_dmem.mem[17] !== 32'd0  ||
    dut.u_dmem.mem[18] !== 32'd7  ||
    dut.u_dmem.mem[19] !== 32'd8  ||
    dut.u_dmem.mem[20] !== 32'd0)
    fail("final DMEM contents mismatch");

                if (dut.u_regfile.regs[8] !== 32'd0)
                    fail("wrong-path ADDI wrote register r8");

                $display("V0.7 DATAPATH STRESS RESULT:");
                $display("WB=%0d/%0d STORE=%0d/%0d DMEM_REQ=%0d DMEM_RESP=%0d",
                    wb_count, N_WB, store_count, N_STORE, req_count, resp_count);
                $display("BRANCH=%0d BRANCH_WAIT_CYCLES=%0d",
                    branch_count, branch_wait_cycles);
                $display("LOAD_USE_EVENTS=%0d LOAD_USE_HIGH_CYCLES=%0d",
                    load_use_count, load_use_high_cycles);
                $display("MEM_STALL_CYCLES=%0d UNSUPPORTED=%0d ERRORS=%0d",
                    mem_stall_cycles, unsupported_count, errors);
                if (errors == 0)
                    $display("ALL TESTS PASSED (V0.7 datapath-level stress regression)");
                else
                    $display("TESTS FAILED errors=%0d", errors);
                $finish;
            end
        end
    end

    // Confirm that the EX/MEM Load and EX branch are simultaneously held.
    always @(negedge clk) begin
        if (!rst) begin
            if (old_mem_stall &&
                (dut.mem_valid !== old_mem_valid ||
                 dut.mem_pc !== old_mem_pc ||
                 dut.mem_alu_result !== old_mem_addr ||
                 dut.mem_store_data !== old_mem_store_data ||
                 dut.mem_rd_addr !== old_mem_rd ||
                 dut.mem_mem_read !== old_mem_read ||
                 dut.mem_mem_write !== old_mem_write ||
                 dut.mem_reg_write !== old_mem_reg_write))
                fail("EX/MEM payload changed during MEM stall");

            if (mem_stall && dut.mem_valid && dut.mem_mem_read &&
                dut.mem_pc == 32'h00001014 && dut.ex_valid &&
                dut.ex_pc == 32'h00001018) begin
                branch_wait_cycles = branch_wait_cycles + 1;
                if (!dut.branch_redirect_raw)
                    fail("branch in EX was not recognized during older Load stall");
                if (branch_redirect)
                    fail("branch redirect escaped during older Load stall");
            end

            old_mem_stall = mem_stall;
            old_mem_valid = dut.mem_valid;
            old_mem_pc = dut.mem_pc;
            old_mem_addr = dut.mem_alu_result;
            old_mem_store_data = dut.mem_store_data;
            old_mem_rd = dut.mem_rd_addr;
            old_mem_read = dut.mem_mem_read;
            old_mem_write = dut.mem_mem_write;
            old_mem_reg_write = dut.mem_reg_write;
        end
    end
endmodule
