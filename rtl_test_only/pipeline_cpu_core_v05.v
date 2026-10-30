`timescale 1ns / 1ps
// V0.5 TEST-ONLY whole-CPU integration (Vivado 2019.1 / Verilog-2001).
// Instantiates UNCHANGED official pc_if_controller, pipeline_control_unit,
// icache_if_adapter, icache_2way_latency and imem_latency, plus UNCHANGED
// pipeline_cpu_core_v04 (the IF-stream five-stage execution datapath).
// This is a bounded program verification harness, NOT final FPGA hardware.
// VIRTUAL CPU PC starts at 0x1000; Cache/IMEM legal PHYSICAL addresses are
// 0x000..0x3ff. Only the new bridge translates PC - PC_BASE and response PC
// + PC_BASE. Existing cache, adapter and CPU RTL MUST NOT be modified.
//
// IF/ID is instantiated INSIDE the unchanged V0.4 CPU, NOT in the fetch block:
// responses are fed directly to the V0.4 ready/valid IF stream.
// Redirect cancels (drains/discards) stale adapter requests; Load-use or
// external IF backpressure holds the adapter response until CPU accepts it.
// hold_fetch_issue_req is ADVISORY and NEVER revokes an outstanding request.
// PROGRAM_WORDS enforces a bounded legal ROM window for this TEST harness.
module pipeline_cpu_core_v05 #(
    parameter [31:0] PC_BASE = 32'h00001000,
    parameter integer PROGRAM_WORDS = 62,
    parameter integer IMEM_LATENCY = 3,
    parameter IMEM_FILE = ""
)(
    input wire clk,
    input wire rst,
    input wire if_delivery_allow,    // test-only downstream backpressure injection
    output wire if_valid,            // CPU-facing instruction (for observability)
    output wire [31:0] if_pc,
    output wire [31:0] if_inst,
    output wire if_ready,
    output wire if_req_fire,
    output wire [31:0] if_req_pc,
    output wire if_resp_fire,
    output wire [31:0] if_resp_pc,
    output wire if_resp_hold,
    output wire fetch_error_fire,
    output wire adapter_busy,
    output wire [31:0] cache_hits,
    output wire [31:0] cache_misses,
    output wire [31:0] cache_refills,
    output wire [31:0] backing_transactions,
    output wire branch_resolve_valid,
    output wire branch_redirect,
    output wire [31:0] branch_redirect_pc,
    output wire load_use_stall,
    output wire id_unsupported,
    output wire id_raw_hazard,
    output wire wb_commit_valid,
    output wire [31:0] wb_commit_pc,
    output wire [4:0] wb_commit_rd,
    output wire [31:0] wb_commit_data,
    output wire mem_store_commit_valid,
    output wire [31:0] mem_store_commit_pc,
    output wire [31:0] mem_store_commit_addr,
    output wire [31:0] mem_store_commit_data
);
    wire pc_req_valid;
    wire [31:0] pc_req_addr;
    wire adapter_req_ready;
    wire adapter_req_valid;
    wire [31:0] physical_req_addr;
    wire request_in_window = (pc_req_addr >= PC_BASE) &&
        (pc_req_addr < (PC_BASE + (PROGRAM_WORDS * 4))) &&
        (pc_req_addr[1:0] == 2'b00);
    // Gating to the finite test ROM is NOT the pipeline load-use advisory.
    assign adapter_req_valid = pc_req_valid && request_in_window;
    assign physical_req_addr = pc_req_addr - PC_BASE;
    assign if_req_fire = adapter_req_valid && adapter_req_ready;
    assign if_req_pc = pc_req_addr;

    pc_if_controller #(.RESET_PC(PC_BASE)) u_pc (
        .clk(clk), .rst(rst),
        .redirect(branch_redirect), .redirect_pc(branch_redirect_pc),
        .if_req_valid(pc_req_valid), .if_req_addr(pc_req_addr),
        .if_req_ready(adapter_req_ready && request_in_window)
    );

    wire ifid_stall_ctrl, ifid_flush_ctrl, idex_flush_ctrl;
    wire hold_fetch_issue_req;
    pipeline_control_unit u_pipeline_ctrl (
        .rst(rst), .branch_redirect(branch_redirect),
        .load_use_hazard(load_use_stall),
        .ifid_stall(ifid_stall_ctrl), .ifid_flush(ifid_flush_ctrl),
        .idex_flush(idex_flush_ctrl),
        .hold_fetch_issue_req(hold_fetch_issue_req)
    );

    wire adapter_resp_valid, adapter_resp_ready, adapter_resp_error;
    wire [31:0] adapter_resp_pc, adapter_resp_inst;
    wire mem_req, mem_ready, mem_addr_valid;
    wire [31:0] mem_addr, mem_rdata;

    // The adapter holds the response until this handshake.  In particular,
    // a response cannot overwrite IF/ID while the CPU detects Load-use.
    assign adapter_resp_ready = !rst && !ifid_stall_ctrl &&
        !ifid_flush_ctrl && if_ready && if_delivery_allow;
    assign if_resp_fire = adapter_resp_valid && adapter_resp_ready;
    assign if_resp_hold = adapter_resp_valid && !adapter_resp_ready &&
                          !branch_redirect && !rst;
    assign fetch_error_fire = if_resp_fire && adapter_resp_error;
    assign if_resp_pc = adapter_resp_pc + PC_BASE;
    assign if_pc = if_resp_pc;
    assign if_inst = adapter_resp_inst;
    assign if_valid = adapter_resp_valid && !adapter_resp_error &&
                      !rst && !ifid_flush_ctrl && if_delivery_allow;

    icache_if_adapter u_adapter (
        .clk(clk), .rst(rst),
        .if_req_valid(adapter_req_valid),
        .if_req_addr(physical_req_addr), .if_req_ready(adapter_req_ready),
        .if_resp_valid(adapter_resp_valid),
        .if_resp_ready(adapter_resp_ready),
        .if_resp_pc(adapter_resp_pc), .if_resp_inst(adapter_resp_inst),
        .if_resp_error(adapter_resp_error),
        .redirect(branch_redirect), .busy(adapter_busy),
        .mem_req(mem_req), .mem_addr(mem_addr),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata),
        .mem_addr_valid(mem_addr_valid),
        .cache_hit_count(cache_hits), .cache_miss_count(cache_misses),
        .cache_refill_words(cache_refills)
    );

    imem_latency #(.LATENCY(IMEM_LATENCY), .INIT_FILE(IMEM_FILE)) u_imem (
        .clk(clk), .rst(rst),
        .mem_req(mem_req), .mem_addr(mem_addr),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata),
        .mem_addr_valid(mem_addr_valid),
        .transactions(backing_transactions)
    );

    // V0.4 owns IF/ID, ID/EX, EX/MEM, MEM/WB and all architectural effects.
    // No duplicate pipeline register or fake decoder is introduced here.
    pipeline_cpu_core_v04 u_cpu (
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
        .load_use_stall(load_use_stall), .id_unsupported(id_unsupported),
        .id_raw_hazard(id_raw_hazard)
    );
endmodule
