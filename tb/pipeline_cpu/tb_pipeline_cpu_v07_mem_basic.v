`timescale 1ns / 1ps
// V0.7 first-pass multi-cycle DMEM + I-Cache CPU integration TB.
// Expected data are ISA-derived constants, NOT sampled from the DUT.
// IMPORTANT: preliminary TB; not yet executed in Vivado 2019.1.
module tb_pipeline_cpu_v07_mem_basic;
    parameter MEM_FILE = "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/v07_mem_basic.mem";
    localparam integer WORDS=18, N_WB=10, N_ST=3;
    reg clk=0;
    always #5 clk = ~clk;
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
    wire mem_stall, dmem_req_fire, dmem_resp_fire, mem_fault_valid;
    wire [31:0] mem_fault_pc, mem_fault_addr;
    wire mem_fault_store;

    pipeline_cpu_core_v07_mem #(
        .PC_BASE(32'h00001000), .PROGRAM_WORDS(WORDS),
        .IMEM_LATENCY(3), .IMEM_FILE(MEM_FILE),
        .DMEM_READ_LATENCY(4), .DMEM_WRITE_LATENCY(5), .DMEM_WORDS(256)
    ) dut (
        .clk(clk), .rst(rst), .if_delivery_allow(if_delivery_allow),
        .if_valid(if_valid),.if_pc(if_pc),.if_inst(if_inst),.if_ready(if_ready),
        .if_req_fire(if_req_fire),.if_req_pc(if_req_pc),
        .if_resp_fire(if_resp_fire),.if_resp_pc(if_resp_pc),
        .if_resp_hold(if_resp_hold),.fetch_error_fire(fetch_error_fire),
        .adapter_busy(adapter_busy),.cache_hits(cache_hits),
        .cache_misses(cache_misses),.cache_refills(cache_refills),
        .backing_transactions(backing_transactions),
        .branch_resolve_valid(branch_resolve_valid),
        .branch_redirect(branch_redirect),.branch_redirect_pc(branch_redirect_pc),
        .load_use_stall(load_use_stall),.id_unsupported(id_unsupported),
        .id_raw_hazard(id_raw_hazard),
        .wb_commit_valid(wb_commit_valid),.wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd),.wb_commit_data(wb_commit_data),
        .mem_store_commit_valid(mem_store_commit_valid),
        .mem_store_commit_pc(mem_store_commit_pc),
        .mem_store_commit_addr(mem_store_commit_addr),
        .mem_store_commit_data(mem_store_commit_data),
        .mem_stall(mem_stall),.dmem_req_fire(dmem_req_fire),
        .dmem_resp_fire(dmem_resp_fire),
        .mem_fault_valid(mem_fault_valid),.mem_fault_pc(mem_fault_pc),
        .mem_fault_addr(mem_fault_addr),.mem_fault_store(mem_fault_store)
    );

    reg [31:0] expected_wb_pc[0:N_WB-1],expected_wb_data[0:N_WB-1];
    reg [4:0] expected_wb_rd[0:N_WB-1];
    reg [31:0] expected_st_pc[0:N_ST-1],expected_st_addr[0:N_ST-1],expected_st_data[0:N_ST-1];
    integer wb_count=0, st_count=0, req_count=0, resp_count=0;
    integer br_count=0, mem_stall_cycles=0, if_resp_held=0;
    integer errors=0, cycles=0, unsupported_count=0;
    integer after_done=0;
    reg old_mem_stall=0;
    reg [31:0] old_mem_pc=0, old_mem_addr=0, old_mem_store=0;
    reg [4:0] old_mem_rd=0;
    reg old_mem_valid=0;
    reg req_outstanding=0;

    task expect_wb;
      input integer idx;
      input [31:0] pc;
      input [4:0] rd;
      input [31:0] data;
      begin
        expected_wb_pc[idx]=pc;
        expected_wb_rd[idx]=rd;
        expected_wb_data[idx]=data;
      end
    endtask
    task expect_st;
      input integer idx;
      input [31:0] pc;
      input [31:0] addr;
      input [31:0] data;
      begin
        expected_st_pc[idx]=pc;
        expected_st_addr[idx]=addr;
        expected_st_data[idx]=data;
      end
    endtask

    initial begin
        expect_wb(0,'h1000,1,10);
        expect_wb(1,'h1004,2,20);
        expect_wb(2,'h100c,3,10);
        expect_wb(3,'h1010,4,30);
        expect_wb(4,'h1018,5,30);
        expect_wb(5,'h101c,6,31);
        expect_wb(6,'h102c,8,30);
        expect_wb(7,'h1030,9,32);
        expect_wb(8,'h1038,10,32);
        expect_wb(9,'h103c,11,31);
        expect_st(0,'h1008,4,10);
        expect_st(1,'h1014,8,30);
        expect_st(2,'h1034,16,32);
        repeat (4) @(negedge clk);
        rst=0;
        if_delivery_allow=1;
    end

    // Scoreboard checks pre-edge transactions and the held EX/MEM register.
    always @(posedge clk) begin
      if (!rst) begin
        cycles=cycles+1;
        if (fetch_error_fire) begin
          errors=errors+1;
          $display("FAIL fetch error PC=%h",if_resp_pc);
        end
        if (mem_fault_valid) begin
          errors=errors+1;
          $display("FAIL unexpected DMEM fault PC=%h addr=%h store=%b",
                     mem_fault_pc,mem_fault_addr,mem_fault_store);
        end
        if (mem_stall) mem_stall_cycles=mem_stall_cycles+1;
        if (if_resp_hold) if_resp_held=if_resp_held+1;
        if (id_unsupported) unsupported_count=unsupported_count+1;
        if (mem_stall && if_ready) begin
          errors=errors+1;
          $display("FAIL upstream IF ready during MEM backpressure");
        end
        if (mem_stall && branch_redirect) begin
          errors=errors+1;
          $display("FAIL repeated/early redirect while MEM frozen");
        end
        if (dmem_req_fire) begin
          req_count=req_count+1;
          if (req_outstanding) begin
            errors=errors+1;
            $display("FAIL overlapping DMEM request");
          end
          req_outstanding=1;
        end
        if (dmem_resp_fire) begin
          resp_count=resp_count+1;
          if (!req_outstanding) begin
            errors=errors+1;
            $display("FAIL response without accepted DMEM request");
          end
          req_outstanding=0;
        end
        if (branch_resolve_valid) begin
          br_count=br_count+1;
          if (!branch_redirect || branch_redirect_pc !== 32'h0000102c) begin
            errors=errors+1;
            $display("FAIL branch taken/PC: taken=%b target=%h",branch_redirect,branch_redirect_pc);
          end
        end
        if (wb_commit_valid) begin
          if (wb_count >= N_WB) begin
            errors=errors+1;
            $display("FAIL unexpected extra WB PC=%h r%0d data=%h", wb_commit_pc,wb_commit_rd,wb_commit_data);
          end else if (wb_commit_pc !== expected_wb_pc[wb_count] ||
                       wb_commit_rd !== expected_wb_rd[wb_count] ||
                       wb_commit_data !== expected_wb_data[wb_count]) begin
            errors=errors+1;
            $display("FAIL WB[%0d] PC=%h r%0d data=%h expected PC=%h r%0d data=%h",
              wb_count,wb_commit_pc,wb_commit_rd,wb_commit_data,
              expected_wb_pc[wb_count],expected_wb_rd[wb_count],expected_wb_data[wb_count]);
          end
          wb_count=wb_count+1;
        end
        if (mem_store_commit_valid) begin
          if (st_count >= N_ST) begin
            errors=errors+1;
            $display("FAIL extra/incorrect-path STORE PC=%h addr=%h data=%h",
                       mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data);
          end else if (mem_store_commit_pc !== expected_st_pc[st_count] ||
                       mem_store_commit_addr !== expected_st_addr[st_count] ||
                       mem_store_commit_data !== expected_st_data[st_count]) begin
            errors=errors+1;
            $display("FAIL STORE[%0d] PC=%h addr=%h data=%h expected PC=%h addr=%h data=%h",
              st_count,mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data,
              expected_st_pc[st_count],expected_st_addr[st_count],expected_st_data[st_count]);
          end
          st_count=st_count+1;
        end
        if (cycles > 3500) begin
          $display("FAIL TIMEOUT WB=%0d/%0d ST=%0d/%0d req=%0d resp=%0d",
                  wb_count,N_WB,st_count,N_ST,req_count,resp_count);
          $fatal(1,"V0.7 timeout");
        end
        if (wb_count==N_WB && st_count==N_ST && br_count==1) after_done=after_done+1;
        else after_done=0;
        if (after_done==80) begin
          if (req_count != 7 || resp_count != 7 || req_outstanding ||
              mem_stall_cycles==0 || errors!=0 ||
              dut.u_cpu.u_dmem.mem[1] !== 32'd10 ||
              dut.u_cpu.u_dmem.mem[2] !== 32'd30 ||
              dut.u_cpu.u_dmem.mem[3] !== 32'd0 ||
              dut.u_cpu.u_dmem.mem[4] !== 32'd32 ||
              dut.u_cpu.u_regfile.regs[7] !== 32'd0) begin
            $display("FAIL FINAL DMEM check / counters / wrong path");
            errors=errors+1;
          end
          $display("V0.7 BASIC RESULT WB=%0d/%0d STORE=%0d/%0d BR=%0d MEM_REQ=%0d MEM_RESP=%0d MEM_STALL_CYCLES=%0d IF_RESP_HELD=%0d UNSUPPORTED=%0d ERRORS=%0d",
                     wb_count,N_WB,st_count,N_ST,br_count,req_count,resp_count,mem_stall_cycles,if_resp_held,unsupported_count,errors);
          if (errors==0) $display("ALL TESTS PASSED (V0.7 multi-cycle DMEM basic CPU integration)");
          else $display("TESTS FAILED errors=%0d",errors);
          $finish;
        end
      end
    end
    // At each later sampling edge, the previously frozen EX/MEM payload
    // must remain unchanged if the preceding interval stalled.
    always @(negedge clk) begin
      if (!rst) begin
        if (old_mem_stall && (dut.u_cpu.mem_valid !== old_mem_valid ||
            dut.u_cpu.mem_pc !== old_mem_pc ||
            dut.u_cpu.mem_alu_result !== old_mem_addr ||
            dut.u_cpu.mem_store_data !== old_mem_store ||
            dut.u_cpu.mem_rd_addr !== old_mem_rd)) begin
          errors=errors+1;
          $display("FAIL EX/MEM changed while MEM stalled");
        end
        old_mem_stall=mem_stall;
        old_mem_valid=dut.u_cpu.mem_valid;
        old_mem_pc=dut.u_cpu.mem_pc;
        old_mem_addr=dut.u_cpu.mem_alu_result;
        old_mem_store=dut.u_cpu.mem_store_data;
        old_mem_rd=dut.u_cpu.mem_rd_addr;
      end
    end
endmodule
