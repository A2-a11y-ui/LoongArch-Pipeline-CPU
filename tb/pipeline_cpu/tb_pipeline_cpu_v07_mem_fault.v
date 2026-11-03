`timescale 1ns / 1ps
// V0.7 WHOLE-CPU DMEM error-response regression (Vivado 2019.1 / Verilog-2001)
// NEW testbench only. Does not modify production/reference RTL.
// REAL unaligned/out-of-range LD.W and ST.W, not force() on resp_error.
// IMPORTANT: THIS TB HAS NOT BEEN RUN IN VIVADO BY THE PACKAGE AUTHOR.
// Use a user-local absolute MEM_FILE path, or customize parameter before launch.
module tb_pipeline_cpu_v07_mem_fault;
    parameter MEM_FILE = "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/v07_mem_fault_basic.mem";
    localparam integer WORDS=19;
    localparam integer N_WB=10, N_STORE=2, N_FAULT=4, N_MEM=8;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1;
    reg if_delivery_allow=0;
    wire if_valid, if_ready, if_req_fire, if_resp_fire, if_resp_hold;
    wire [31:0] if_pc, if_inst, if_req_pc, if_resp_pc;
    wire fetch_error_fire, adapter_busy;
    wire [31:0] cache_hits, cache_misses, cache_refills, backing_transactions;
    wire branch_resolve_valid, branch_redirect;
    wire [31:0] branch_redirect_pc;
    wire load_use_stall, id_unsupported, id_raw_hazard;
    wire wb_commit_valid, mem_store_commit_valid;
    wire [31:0] wb_commit_pc, wb_commit_data;
    wire [4:0] wb_commit_rd;
    wire [31:0] mem_store_commit_pc, mem_store_commit_addr, mem_store_commit_data;
    wire mem_stall, dmem_req_fire, dmem_resp_fire;
    wire mem_fault_valid, mem_fault_store;
    wire [31:0] mem_fault_pc, mem_fault_addr;

    pipeline_cpu_core_v07_mem #(
        .PC_BASE(32'h00001000), .PROGRAM_WORDS(WORDS),
        .IMEM_LATENCY(3), .IMEM_FILE(MEM_FILE),
        .DMEM_READ_LATENCY(6), .DMEM_WRITE_LATENCY(7),
        .DMEM_WORDS(8) // Only byte addresses 0...31 are valid and aligned.
    ) dut (
        .clk(clk), .rst(rst), .if_delivery_allow(if_delivery_allow),
        .if_valid(if_valid), .if_pc(if_pc), .if_inst(if_inst), .if_ready(if_ready),
        .if_req_fire(if_req_fire), .if_req_pc(if_req_pc),
        .if_resp_fire(if_resp_fire), .if_resp_pc(if_resp_pc),
        .if_resp_hold(if_resp_hold), .fetch_error_fire(fetch_error_fire),
        .adapter_busy(adapter_busy), .cache_hits(cache_hits),
        .cache_misses(cache_misses), .cache_refills(cache_refills),
        .backing_transactions(backing_transactions),
        .branch_resolve_valid(branch_resolve_valid),
        .branch_redirect(branch_redirect), .branch_redirect_pc(branch_redirect_pc),
        .load_use_stall(load_use_stall), .id_unsupported(id_unsupported),
        .id_raw_hazard(id_raw_hazard),
        .wb_commit_valid(wb_commit_valid), .wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd), .wb_commit_data(wb_commit_data),
        .mem_store_commit_valid(mem_store_commit_valid),
        .mem_store_commit_pc(mem_store_commit_pc),
        .mem_store_commit_addr(mem_store_commit_addr),
        .mem_store_commit_data(mem_store_commit_data),
        .mem_stall(mem_stall), .dmem_req_fire(dmem_req_fire),
        .dmem_resp_fire(dmem_resp_fire),
        .mem_fault_valid(mem_fault_valid), .mem_fault_pc(mem_fault_pc),
        .mem_fault_addr(mem_fault_addr), .mem_fault_store(mem_fault_store)
    );

    reg [31:0] exp_wb_pc[0:N_WB-1], exp_wb_data[0:N_WB-1];
    reg [4:0] exp_wb_rd[0:N_WB-1];
    reg [31:0] exp_st_pc[0:N_STORE-1], exp_st_addr[0:N_STORE-1], exp_st_data[0:N_STORE-1];
    reg [31:0] exp_fault_pc[0:N_FAULT-1], exp_fault_addr[0:N_FAULT-1];
    reg exp_fault_store[0:N_FAULT-1];
    reg [31:0] exp_req_pc[0:N_MEM-1], exp_req_addr[0:N_MEM-1];
    reg exp_req_write[0:N_MEM-1];

    integer wb_count=0, st_count=0, fault_count=0, req_count=0, resp_count=0;
    integer error_load_count=0, error_store_count=0, branch_count=0;
    integer mem_stall_cycles=0, if_resp_hold_cycles=0, cycles=0, errors=0;
    integer after_done=0, j;
    reg outstanding=0;
    reg pending_error_expected=0, pending_write=0;
    reg [31:0] pending_pc=0, pending_addr=0;
    reg prev_fault=0;

    task expect_wb;
      input integer idx;
      input [31:0] pc;
      input [4:0] rd;
      input [31:0] data;
      begin exp_wb_pc[idx]=pc; exp_wb_rd[idx]=rd; exp_wb_data[idx]=data; end
    endtask
    task expect_store;
      input integer idx;
      input [31:0] pc, addr, data;
      begin exp_st_pc[idx]=pc; exp_st_addr[idx]=addr; exp_st_data[idx]=data; end
    endtask
    task expect_fault;
      input integer idx;
      input [31:0] pc, addr;
      input is_store;
      begin exp_fault_pc[idx]=pc; exp_fault_addr[idx]=addr; exp_fault_store[idx]=is_store; end
    endtask
    task expect_req;
      input integer idx;
      input [31:0] pc, addr;
      input is_store;
      begin exp_req_pc[idx]=pc; exp_req_addr[idx]=addr; exp_req_write[idx]=is_store; end
    endtask

    initial begin
        // Expected architectural WB sequence, independent of DUT outputs.
        expect_wb(0, 'h1000, 1, 10);
        expect_wb(1, 'h1008, 3, 55);    // Must survive failed LD at 0x100c.
        expect_wb(2, 'h1010, 4, 66);    // Must survive failed LD at 0x1014.
        expect_wb(3, 'h1020, 5, 10);
        expect_wb(4, 'h1024, 6, 11);
        expect_wb(5, 'h102c, 7, 11);
        expect_wb(6, 'h1030, 8, 13);
        expect_wb(7, 'h1040,10, 56);    // Read preserved r3.
        expect_wb(8, 'h1044,11, 67);    // Read preserved r4.
        expect_wb(9, 'h1048,12, 7);     // CPU recovered after faults.
        expect_store(0, 'h1004, 4, 10);
        expect_store(1, 'h1028, 8, 11);
        expect_fault(0, 'h100c, 2,  1'b0); // Misaligned load.
        expect_fault(1, 'h1014, 64, 1'b0); // Out-of-range load.
        expect_fault(2, 'h1018, 6,  1'b1); // Misaligned store.
        expect_fault(3, 'h101c, 64, 1'b1); // Out-of-range store.
        expect_req(0, 'h1004, 4,  1'b1);
        expect_req(1, 'h100c, 2,  1'b0);
        expect_req(2, 'h1014, 64, 1'b0);
        expect_req(3, 'h1018, 6,  1'b1);
        expect_req(4, 'h101c, 64, 1'b1);
        expect_req(5, 'h1020, 4,  1'b0);
        expect_req(6, 'h1028, 8,  1'b1);
        expect_req(7, 'h102c, 8,  1'b0);
        repeat (4) @(negedge clk);
        rst=0;
        if_delivery_allow=1;
    end

    // All public interface events sampled on the rising handshake edge.
    // The expected request list does NOT depend on DUT-generated results.
    always @(posedge clk) begin
      if (!rst) begin
        cycles=cycles+1;
        if (mem_stall) mem_stall_cycles=mem_stall_cycles+1;
        if (if_resp_hold) if_resp_hold_cycles=if_resp_hold_cycles+1;
        if (fetch_error_fire) begin
          errors=errors+1;
          $display("FAIL unexpected IF error at PC=%h",if_resp_pc);
        end
        if (mem_stall && if_ready) begin
          errors=errors+1;
          $display("FAIL IF ready asserted during MEM stall");
        end
        if (mem_stall && branch_redirect) begin
          errors=errors+1;
          $display("FAIL branch redirect while MEM frozen");
        end
        if (dmem_req_fire) begin
          if (outstanding) begin
            errors=errors+1;
            $display("FAIL overlapping DMEM requests");
          end
          if (req_count >= N_MEM) begin
            errors=errors+1;
            $display("FAIL extra DMEM request pc=%h addr=%h",dut.u_cpu.mem_pc,dut.u_cpu.mem_alu_result);
          end else if (dut.u_cpu.mem_pc !== exp_req_pc[req_count] ||
                       dut.u_cpu.mem_alu_result !== exp_req_addr[req_count] ||
                       dut.u_cpu.mem_mem_write !== exp_req_write[req_count]) begin
            errors=errors+1;
            $display("FAIL REQ[%0d] pc=%h addr=%h write=%b exp pc=%h addr=%h write=%b",
               req_count,dut.u_cpu.mem_pc,dut.u_cpu.mem_alu_result,dut.u_cpu.mem_mem_write,
               exp_req_pc[req_count],exp_req_addr[req_count],exp_req_write[req_count]);
          end
          pending_error_expected=(req_count>=1 && req_count<=4);
          pending_pc=dut.u_cpu.mem_pc;
          pending_addr=dut.u_cpu.mem_alu_result;
          pending_write=dut.u_cpu.mem_mem_write;
          outstanding=1;
          req_count=req_count+1;
        end
        if (dmem_resp_fire) begin
          if (!outstanding) begin
            errors=errors+1;
            $display("FAIL DMEM response without outstanding request");
          end
          if (dut.u_cpu.dmem_resp_error !== pending_error_expected ||
              dut.u_cpu.mem_pc !== pending_pc ||
              dut.u_cpu.mem_alu_result !== pending_addr ||
              dut.u_cpu.mem_mem_write !== pending_write) begin
            errors=errors+1;
            $display("FAIL RESP[%0d] err=%b exp=%b pc=%h exp_pc=%h addr=%h exp_addr=%h",
              resp_count,dut.u_cpu.dmem_resp_error,pending_error_expected,
              dut.u_cpu.mem_pc,pending_pc,dut.u_cpu.mem_alu_result,pending_addr);
          end
          if (mem_fault_valid !== pending_error_expected) begin
            errors=errors+1;
            $display("FAIL fault-valid mismatch with response error");
          end
          resp_count=resp_count+1;
          outstanding=0;
        end else if (mem_fault_valid) begin
          errors=errors+1;
          $display("FAIL ghost fault with no DMEM response handshake");
        end

        if (mem_fault_valid) begin
          if (prev_fault) begin
            errors=errors+1;
            $display("FAIL mem_fault_valid consecutive-cycle pulse");
          end
          if (fault_count >= N_FAULT) begin
            errors=errors+1;
            $display("FAIL extra FAULT pc=%h addr=%h",mem_fault_pc,mem_fault_addr);
          end else if (mem_fault_pc !== exp_fault_pc[fault_count] ||
                       mem_fault_addr !== exp_fault_addr[fault_count] ||
                       mem_fault_store !== exp_fault_store[fault_count]) begin
            errors=errors+1;
            $display("FAIL FAULT[%0d] pc=%h addr=%h store=%b, exp pc=%h addr=%h store=%b",
              fault_count,mem_fault_pc,mem_fault_addr,mem_fault_store,
              exp_fault_pc[fault_count],exp_fault_addr[fault_count],exp_fault_store[fault_count]);
          end
          if (mem_fault_store) error_store_count=error_store_count+1;
          else error_load_count=error_load_count+1;
          if (mem_store_commit_valid) begin
            errors=errors+1;
            $display("FAIL errored Store generated commit");
          end
          fault_count=fault_count+1;
          $display("COVERAGE FAULT pc=%h addr=%h store=%b",mem_fault_pc,mem_fault_addr,mem_fault_store);
        end
        prev_fault=mem_fault_valid;

        if (wb_commit_valid) begin
          if (wb_commit_pc==32'h100c || wb_commit_pc==32'h1014 || wb_commit_pc==32'h103c) begin
            errors=errors+1;
            $display("FAIL errored/wrong-path instruction WB pc=%h",wb_commit_pc);
          end
          if (wb_count >= N_WB) begin
            errors=errors+1;
            $display("FAIL extra WB pc=%h rd=%d data=%h",wb_commit_pc,wb_commit_rd,wb_commit_data);
          end else if (wb_commit_pc !== exp_wb_pc[wb_count] ||
                       wb_commit_rd !== exp_wb_rd[wb_count] ||
                       wb_commit_data !== exp_wb_data[wb_count]) begin
            errors=errors+1;
            $display("FAIL WB[%0d] pc=%h rd=%d data=%h exp pc=%h rd=%d data=%h",
              wb_count,wb_commit_pc,wb_commit_rd,wb_commit_data,
              exp_wb_pc[wb_count],exp_wb_rd[wb_count],exp_wb_data[wb_count]);
          end
          wb_count=wb_count+1;
        end
        if (mem_store_commit_valid) begin
          if (mem_store_commit_pc == 32'h1018 || mem_store_commit_pc == 32'h101c ||
              mem_store_commit_pc == 32'h1038) begin
            errors=errors+1;
            $display("FAIL errored/wrong-path STORE committed PC=%h",mem_store_commit_pc);
          end
          if (st_count >= N_STORE) begin
            errors=errors+1;
            $display("FAIL extra STORE pc=%h addr=%h data=%h",
                mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data);
          end else if (mem_store_commit_pc !== exp_st_pc[st_count] ||
                       mem_store_commit_addr !== exp_st_addr[st_count] ||
                       mem_store_commit_data !== exp_st_data[st_count]) begin
            errors=errors+1;
            $display("FAIL STORE[%0d] pc=%h addr=%h data=%h",
                st_count,mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data);
          end
          st_count=st_count+1;
        end
        if (branch_resolve_valid) begin
          branch_count=branch_count+1;
          if (!branch_redirect || branch_redirect_pc !== 32'h00001040) begin
            errors=errors+1;
            $display("FAIL branch redirect target=%h taken=%b",branch_redirect_pc,branch_redirect);
          end
        end
        if (cycles > 4000) begin
          $display("FAIL TIMEOUT WB=%0d/%0d ST=%0d/%0d FLT=%0d/%0d REQ=%0d/%0d RESP=%0d/%0d",
             wb_count,N_WB,st_count,N_STORE,fault_count,N_FAULT,req_count,N_MEM,resp_count,N_MEM);
          $fatal(1,"V0.7 DMEM fault regression timeout");
        end
        if (wb_count==N_WB && st_count==N_STORE && fault_count==N_FAULT && branch_count==1)
          after_done=after_done+1;
        else after_done=0;
        if (after_done==90) begin
          if (req_count!=N_MEM || resp_count!=N_MEM || outstanding ||
              error_load_count!=2 || error_store_count!=2 || mem_stall_cycles==0 ||
              dut.u_cpu.u_dmem.mem[0] !== 32'd0 ||
              dut.u_cpu.u_dmem.mem[1] !== 32'd10 ||
              dut.u_cpu.u_dmem.mem[2] !== 32'd11 ||
              dut.u_cpu.u_dmem.mem[3] !== 32'd0 ||
              dut.u_cpu.u_dmem.mem[4] !== 32'd0 ||
              dut.u_cpu.u_dmem.mem[5] !== 32'd0 ||
              dut.u_cpu.u_dmem.mem[6] !== 32'd0 ||
              dut.u_cpu.u_dmem.mem[7] !== 32'd0 ||
              dut.u_cpu.u_regfile.regs[3] !== 32'd55 ||
              dut.u_cpu.u_regfile.regs[4] !== 32'd66 ||
              dut.u_cpu.u_regfile.regs[9] !== 32'd0) begin
            errors=errors+1;
            $display("FAIL FINAL: counters, RAM unchanged, bad-Load destination, or wrong-path r9");
          end
          $display("V0.7 MEM FAULT RESULT WB=%0d/%0d STORE=%0d/%0d FAULT=%0d/%0d LOAD_ERROR=%0d STORE_ERROR=%0d REQ=%0d/%0d RESP=%0d/%0d BR=%0d STALL=%0d IF_RESP_HELD=%0d ERRORS=%0d",
             wb_count,N_WB,st_count,N_STORE,fault_count,N_FAULT,
             error_load_count,error_store_count,req_count,N_MEM,resp_count,N_MEM,
             branch_count,mem_stall_cycles,if_resp_hold_cycles,errors);
          if (errors==0) begin
            $display("ALL TESTS PASSED (V0.7 multi-cycle DMEM error response CPU regression)");
            $finish;
          end else begin
            $fatal(1,"TESTS FAILED errors=%0d",errors);
          end
        end
      end
    end
endmodule
