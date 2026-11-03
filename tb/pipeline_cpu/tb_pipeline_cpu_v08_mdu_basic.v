`timescale 1ns / 1ps
// V0.8 basic FULL CPU integration regression, Vivado 2019.1, Verilog-2001.
// TEST ONLY.  Expected retirement sequence is independent of DUT outputs.
// CPU includes official V0.7 I-Cache, DMEM, and the 7-op iterative MDU.
// IMPORTANT: Not yet run on the user's Vivado; do NOT claim PASS until tested.
module tb_pipeline_cpu_v08_mdu_basic;
    parameter MEM_FILE = "D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/v08_mdu_basic.mem";
    localparam integer N_WORDS=29, N_WB=23, N_ST=2, N_MDU=15;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1;
    reg if_delivery_allow=0;
    wire if_valid, if_ready, if_req_fire, if_resp_fire, if_resp_hold;
    wire [31:0] if_pc,if_inst,if_req_pc,if_resp_pc;
    wire fetch_error_fire,adapter_busy;
    wire [31:0] cache_hits,cache_misses,cache_refills,backing_transactions;
    wire branch_resolve_valid,branch_redirect;
    wire [31:0] branch_redirect_pc;
    wire load_use_stall,id_unsupported,id_raw_hazard;
    wire wb_commit_valid,mem_store_commit_valid;
    wire [31:0] wb_commit_pc,wb_commit_data;
    wire [4:0] wb_commit_rd;
    wire [31:0] mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data;
    wire mem_stall,dmem_req_fire,dmem_resp_fire,mem_fault_valid;
    wire [31:0] mem_fault_pc,mem_fault_addr;
    wire mem_fault_store;
    wire mdu_start_fire,mdu_busy,mdu_done,mdu_result_fire,mdu_div_zero;

    pipeline_cpu_core_v08_mdu #(
        .PC_BASE(32'h00001000),.PROGRAM_WORDS(N_WORDS),
        .IMEM_LATENCY(3),.IMEM_FILE(MEM_FILE),
        .DMEM_READ_LATENCY(8),.DMEM_WRITE_LATENCY(11),.DMEM_WORDS(256)
    ) dut (
        .clk(clk),.rst(rst),.if_delivery_allow(if_delivery_allow),
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
        .mem_fault_addr(mem_fault_addr),.mem_fault_store(mem_fault_store),
        .mdu_start_fire(mdu_start_fire),.mdu_busy(mdu_busy),
        .mdu_done(mdu_done),.mdu_result_fire(mdu_result_fire),
        .mdu_div_zero(mdu_div_zero)
    );

    reg [31:0] expected_wb_pc[0:N_WB-1],expected_wb_data[0:N_WB-1];
    reg [4:0] expected_wb_rd[0:N_WB-1];
    reg [31:0] expected_st_pc[0:N_ST-1],expected_st_addr[0:N_ST-1],expected_st_data[0:N_ST-1];
    integer wb_count=0,st_count=0,br_count=0,req_count=0,resp_count=0;
    integer mdu_start_count=0,mdu_result_count=0,mdu_busy_cycles=0;
    integer mem_stall_cycles=0,if_resp_held=0,unsupported_count=0;
    integer after_done=0,cycles=0,errors=0;
    reg outstanding=0;
    reg prev_mdu_pending=0;
    reg [31:0] prev_mdu_data=0;
    reg prev_mdu_divzero=0;

    task expect_wb;
        input integer i; input [31:0] pc; input [4:0] rd; input [31:0] value;
        begin expected_wb_pc[i]=pc; expected_wb_rd[i]=rd; expected_wb_data[i]=value; end
    endtask
    task expect_st;
        input integer i; input [31:0] pc,addr,value;
        begin expected_st_pc[i]=pc; expected_st_addr[i]=addr; expected_st_data[i]=value; end
    endtask

    initial begin
        expect_wb(0,32'h00001000,5'd1,32'h00000006);
        expect_wb(1,32'h00001004,5'd2,32'h00000003);
        expect_wb(2,32'h00001008,5'd3,32'h00000012);
        expect_wb(3,32'h0000100c,5'd4,32'h00000015);
        expect_wb(4,32'h00001010,5'd5,32'h00000007);
        expect_wb(5,32'h00001014,5'd6,32'h00000003);
        expect_wb(6,32'h00001018,5'd7,32'h00000000);
        expect_wb(7,32'h0000101c,5'd8,32'h00000000);
        expect_wb(8,32'h00001020,5'd9,32'h00000003);
        expect_wb(9,32'h00001024,5'd10,32'h00000003);
        expect_wb(10,32'h0000102c,5'd11,32'h00000007);
        expect_wb(11,32'h00001030,5'd12,32'h00000015);
        expect_wb(12,32'h00001034,5'd13,32'h00000007);
        expect_wb(13,32'h00001044,5'd15,32'h00000008);
        expect_wb(14,32'h0000104c,5'd16,32'h00000008);
        expect_wb(15,32'h00001050,5'd18,32'hffffffff);
        expect_wb(16,32'h00001054,5'd19,32'h00000002);
        expect_wb(17,32'h00001058,5'd20,32'hffffffff);
        expect_wb(18,32'h0000105c,5'd21,32'h00000001);
        expect_wb(19,32'h00001060,5'd22,32'h00000000);
        expect_wb(20,32'h00001064,5'd23,32'hffffffff);
        expect_wb(21,32'h00001068,5'd24,32'h7fffffff);
        expect_wb(22,32'h0000106c,5'd25,32'h00000001);
        expect_st(0,32'h00001028,32'h00000004,32'h00000007);
        expect_st(1,32'h00001048,32'h0000000c,32'h00000008);
        repeat(4) @(negedge clk);
        rst=0;
        if_delivery_allow=1;
    end

    // Sample valid/ready handshakes on the accepting rising edge.
    always @(posedge clk) begin
        if (!rst) begin
            cycles=cycles+1;
            if (mdu_start_fire) mdu_start_count=mdu_start_count+1;
            if (mdu_busy) mdu_busy_cycles=mdu_busy_cycles+1;
            if (mdu_result_fire) mdu_result_count=mdu_result_count+1;
            if (mem_stall) mem_stall_cycles=mem_stall_cycles+1;
            if (if_resp_hold) if_resp_held=if_resp_held+1;
            if (id_unsupported) unsupported_count=unsupported_count+1;
            if (fetch_error_fire || mem_fault_valid) begin
                errors=errors+1;
                $display("FAIL unexpected fetch/mem fault pc=%h addr=%h",mem_fault_pc,mem_fault_addr);
            end
            if (mem_stall && if_ready) begin
                errors=errors+1;
                $display("FAIL IF accepts a word during MEM Stall");
            end
            if (mdu_busy && if_ready) begin
                errors=errors+1;
                $display("FAIL IF accepts a word during MDU Busy");
            end
            if (mdu_busy && branch_redirect) begin
                errors=errors+1;
                $display("FAIL redirect repeated during MDU Busy");
            end
            if (mdu_result_fire && !mdu_done) begin
                errors=errors+1;
                $display("FAIL MDU consumed without Done");
            end
            if (prev_mdu_pending &&
                (!mdu_done || dut.u_cpu.u_mdu.result !== prev_mdu_data ||
                 mdu_div_zero !== prev_mdu_divzero)) begin
                errors=errors+1;
                $display("FAIL held MDU Done/result/div_zero changed");
            end
            prev_mdu_pending=mdu_done && !mdu_result_fire;
            prev_mdu_data=dut.u_cpu.u_mdu.result;
            prev_mdu_divzero=mdu_div_zero;
            if (dmem_req_fire) begin
                if (outstanding) begin
                    errors=errors+1; $display("FAIL overlapping DMEM requests");
                end
                outstanding=1;
                req_count=req_count+1;
            end
            if (dmem_resp_fire) begin
                if (!outstanding) begin
                    errors=errors+1; $display("FAIL DMEM response without request");
                end
                outstanding=0;
                resp_count=resp_count+1;
            end
            if (branch_resolve_valid) begin
                br_count=br_count+1;
                if (!branch_redirect || branch_redirect_pc !== 32'h00001044) begin
                    errors=errors+1;
                    $display("FAIL Branch target expected 0x1044, observed %h",branch_redirect_pc);
                end
            end
            if (wb_commit_valid) begin
                if (wb_count>=N_WB) begin
                    errors=errors+1;$display("FAIL extra WB PC=%h rd=%d data=%h",wb_commit_pc,wb_commit_rd,wb_commit_data);
                end else if (wb_commit_pc !== expected_wb_pc[wb_count] ||
                             wb_commit_rd !== expected_wb_rd[wb_count] ||
                             wb_commit_data !== expected_wb_data[wb_count]) begin
                    errors=errors+1;
                    $display("FAIL WB[%0d] pc=%h rd=%d data=%h; expected %h/%d/%h",wb_count,
                         wb_commit_pc,wb_commit_rd,wb_commit_data,
                         expected_wb_pc[wb_count],expected_wb_rd[wb_count],expected_wb_data[wb_count]);
                end
                wb_count=wb_count+1;
            end
            if (mem_store_commit_valid) begin
                if (st_count>=N_ST) begin
                    errors=errors+1;$display("FAIL extra STORE pc=%h addr=%h data=%h",mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data);
                end else if (mem_store_commit_pc !== expected_st_pc[st_count] ||
                             mem_store_commit_addr !== expected_st_addr[st_count] ||
                             mem_store_commit_data !== expected_st_data[st_count]) begin
                    errors=errors+1;
                    $display("FAIL STORE[%0d] got pc=%h addr=%h data=%h",st_count,
                         mem_store_commit_pc,mem_store_commit_addr,mem_store_commit_data);
                end
                st_count=st_count+1;
            end
            if (cycles>6000) $fatal(1,"TIMEOUT wb=%0d/%0d mdu=%0d/%0d errors=%0d",wb_count,N_WB,mdu_result_count,N_MDU,errors);
            if (wb_count==N_WB && st_count==N_ST && br_count==1 && mdu_result_count==N_MDU)
                after_done=after_done+1;
            else after_done=0;
            if (after_done==80) begin
			if (req_count != 4)
    $display("FAIL DMEM_REQ expected=4 actual=%0d",req_count);

if (resp_count != 4)
    $display("FAIL DMEM_RESP expected=4 actual=%0d",resp_count);

if (dut.u_cpu.u_dmem.mem[1] !== 32'd7)
    $display("FAIL RAM[1] expected=7 actual=%h",
             dut.u_cpu.u_dmem.mem[1]);

if (dut.u_cpu.u_dmem.mem[2] !== 32'd0)
    $display("FAIL RAM[2] expected=0 actual=%h",
             dut.u_cpu.u_dmem.mem[2]);

if (dut.u_cpu.u_dmem.mem[3] !== 32'd8)
    $display("FAIL RAM[3] expected=8 actual=%h",
             dut.u_cpu.u_dmem.mem[3]);

if (dut.u_cpu.u_regfile.regs[14] !== 32'd0)
    $display("FAIL wrong-path r14 expected=0 actual=%h",
             dut.u_cpu.u_regfile.regs[14]);
			 
                if (req_count!=4 || resp_count!=4 || outstanding ||
                    mdu_start_count!=N_MDU || mdu_result_count!=N_MDU ||
                    mdu_busy_cycles==0 || mem_stall_cycles==0 ||
                    dut.u_cpu.u_dmem.mem[1] !== 32'd7 ||
                    dut.u_cpu.u_dmem.mem[2] !== 32'd0 ||
                    dut.u_cpu.u_dmem.mem[3] !== 32'd8 ||
                    dut.u_cpu.u_regfile.regs[14] !== 32'd0) begin
                    errors=errors+1;
                    $display("FAIL final counts/RAM/wrong-path side effects");
                end
                $display("V0.8 MDU BASIC RESULT WB=%0d/%0d STORE=%0d/%0d MDU_START=%0d MDU_DONE=%0d BR=%0d DMEM_REQ=%0d RESP=%0d MDU_BUSY_CYCLES=%0d MEM_STALL_CYCLES=%0d IF_HELD=%0d ERRORS=%0d",
                    wb_count,N_WB,st_count,N_ST,mdu_start_count,mdu_result_count,
                    br_count,req_count,resp_count,mdu_busy_cycles,mem_stall_cycles,if_resp_held,errors);
                if (errors==0) $display("ALL TESTS PASSED (V0.8 MDU + DMEM + I-Cache CPU basic regression)");
                else $fatal(1,"V0.8 basic CPU regression FAILED errors=%0d",errors);
                $finish;
            end
        end
    end
endmodule
