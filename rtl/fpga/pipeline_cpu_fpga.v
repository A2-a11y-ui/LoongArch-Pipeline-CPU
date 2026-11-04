`timescale 1ns / 1ps
// V0.9 FPGA-oriented hardware integration wrapper.
//
// Reuses the validated V0.8 CPU datapath, PC controller, pipeline control,
// I-Cache adapter and 2-way I-Cache. The only fetch-memory substitution is
// imem_bram, a synchronous ROM intended for FPGA BRAM inference.
//
// Unlike pipeline_cpu_core_v08_mdu.v, this module has no test-only
// if_delivery_allow input and no fixed-latency imem_latency instance.
//
// PC mapping:
//   CPU-visible PC starts at PC_BASE (default 0x1000).
//   I-Cache/backing-ROM addresses are physical offsets from PC_BASE.
//   PROGRAM_WORDS bounds instruction issue to the supplied ROM image.
//
// Data memory remains the existing synthesizable dmem_latency module.
// Exceptions/traps remain outside the V0.8 CPU scope.
module pipeline_cpu_fpga #(
    parameter [31:0] PC_BASE = 32'h00001000,
    parameter integer PROGRAM_WORDS = 29,
    parameter IMEM_FILE = "fpga_demo.mem",
    parameter integer DMEM_READ_LATENCY = 4,
    parameter integer DMEM_WRITE_LATENCY = 5,
    parameter integer DMEM_WORDS = 256,
    parameter DMEM_INIT_FILE = ""
)(
    input  wire        clk,
    input  wire        rst,

    // Architectural commit observations.
    output wire        wb_commit_valid,
    output wire [31:0] wb_commit_pc,
    output wire [4:0]  wb_commit_rd,
    output wire [31:0] wb_commit_data,

    output wire        mem_store_commit_valid,
    output wire [31:0] mem_store_commit_pc,
    output wire [31:0] mem_store_commit_addr,
    output wire [31:0] mem_store_commit_data,

    // Control / diagnostic observations.
    output wire        branch_resolve_valid,
    output wire        branch_redirect,
    output wire [31:0] branch_redirect_pc,
    output wire        load_use_stall,
    output wire        id_unsupported,
    output wire        id_raw_hazard,
    output wire        mem_stall,
    output wire        dmem_req_fire,
    output wire        dmem_resp_fire,
    output wire        mem_fault_valid,
    output wire [31:0] mem_fault_pc,
    output wire [31:0] mem_fault_addr,
    output wire        mem_fault_store,
    output wire        mdu_start_fire,
    output wire        mdu_busy,
    output wire        mdu_done,
    output wire        mdu_result_fire,
    output wire        mdu_div_zero,

    // I-Cache / IF observations.
    output wire        if_resp_fire,
    output wire        if_resp_hold,
    output wire        fetch_error_fire,
    output wire        adapter_busy,
    output wire [31:0] cache_hits,
    output wire [31:0] cache_misses,
    output wire [31:0] cache_refills,
    output wire [31:0] backing_transactions,

    // Sticky board-level status.
    output reg         program_done,
    output reg         fault_sticky
);

    // ---------------------------------------------------------------------
    // PC request and bounded ROM window
    // ---------------------------------------------------------------------
    wire        pc_req_valid;
    wire [31:0] pc_req_addr;
    wire        adapter_req_ready;
    wire        adapter_req_valid;
    wire [31:0] physical_req_addr;
    wire [31:0] program_end;

    assign program_end = PC_BASE + (PROGRAM_WORDS * 4);

    wire request_in_window =
        (pc_req_addr >= PC_BASE) &&
        (pc_req_addr < program_end) &&
        (pc_req_addr[1:0] == 2'b00);

    assign adapter_req_valid = pc_req_valid && request_in_window;
    assign physical_req_addr = pc_req_addr - PC_BASE;

    pc_if_controller #(
        .RESET_PC(PC_BASE)
    ) u_pc (
        .clk(clk),
        .rst(rst),
        .redirect(branch_redirect),
        .redirect_pc(branch_redirect_pc),
        .if_req_valid(pc_req_valid),
        .if_req_addr(pc_req_addr),
        .if_req_ready(adapter_req_ready && request_in_window)
    );

    // ---------------------------------------------------------------------
    // Pipeline control and IF response backpressure
    // ---------------------------------------------------------------------
    wire ifid_stall_ctrl;
    wire ifid_flush_ctrl;
    wire idex_flush_ctrl;
    wire hold_fetch_issue_req;

    pipeline_control_unit u_pipeline_ctrl (
        .rst(rst),
        .branch_redirect(branch_redirect),
        .load_use_hazard(load_use_stall),
        .ifid_stall(ifid_stall_ctrl),
        .ifid_flush(ifid_flush_ctrl),
        .idex_flush(idex_flush_ctrl),
        .hold_fetch_issue_req(hold_fetch_issue_req)
    );

    wire        adapter_resp_valid;
    wire        adapter_resp_ready;
    wire        adapter_resp_error;
    wire [31:0] adapter_resp_pc;
    wire [31:0] adapter_resp_inst;

    wire        mem_req;
    wire        mem_ready;
    wire        mem_addr_valid;
    wire [31:0] mem_addr;
    wire [31:0] mem_rdata;

    wire        if_ready;
    wire        if_valid;
    wire [31:0] if_pc;
    wire [31:0] if_inst;

    // Do not consume or overwrite an I-Cache response while the CPU is
    // stalled, flushing a wrong-path instruction, or otherwise not ready.
    assign adapter_resp_ready =
        !rst &&
        !ifid_stall_ctrl &&
        !ifid_flush_ctrl &&
        if_ready;

    assign if_resp_fire = adapter_resp_valid && adapter_resp_ready;
    assign if_resp_hold = adapter_resp_valid &&
                          !adapter_resp_ready &&
                          !branch_redirect &&
                          !rst;
    assign fetch_error_fire = if_resp_fire && adapter_resp_error;

    // I-Cache stores physical offsets. Restore the architectural PC before
    // delivering the instruction to the CPU datapath.
    assign if_pc = adapter_resp_pc + PC_BASE;
    assign if_inst = adapter_resp_inst;
    assign if_valid = adapter_resp_valid &&
                      !adapter_resp_error &&
                      !rst &&
                      !ifid_flush_ctrl;

    // ---------------------------------------------------------------------
    // Existing I-Cache adapter + existing 2-way I-Cache
    // ---------------------------------------------------------------------
    icache_if_adapter u_adapter (
        .clk(clk),
        .rst(rst),
        .if_req_valid(adapter_req_valid),
        .if_req_addr(physical_req_addr),
        .if_req_ready(adapter_req_ready),
        .if_resp_valid(adapter_resp_valid),
        .if_resp_ready(adapter_resp_ready),
        .if_resp_pc(adapter_resp_pc),
        .if_resp_inst(adapter_resp_inst),
        .if_resp_error(adapter_resp_error),
        .redirect(branch_redirect),
        .busy(adapter_busy),
        .mem_req(mem_req),
        .mem_addr(mem_addr),
        .mem_ready(mem_ready),
        .mem_rdata(mem_rdata),
        .mem_addr_valid(mem_addr_valid),
        .cache_hit_count(cache_hits),
        .cache_miss_count(cache_misses),
        .cache_refill_words(cache_refills)
    );

    // Synchronous ROM replaces only the simulation-oriented imem_latency.
    imem_bram #(
        .INIT_FILE(IMEM_FILE)
    ) u_imem (
        .clk(clk),
        .rst(rst),
        .mem_req(mem_req),
        .mem_addr(mem_addr),
        .mem_ready(mem_ready),
        .mem_rdata(mem_rdata),
        .mem_addr_valid(mem_addr_valid),
        .transactions(backing_transactions)
    );

    // ---------------------------------------------------------------------
    // Existing V0.8 CPU datapath (IF/ID through MEM/WB)
    // ---------------------------------------------------------------------
    pipeline_cpu_core_v08_mdu_datapath #(
        .DMEM_READ_LATENCY(DMEM_READ_LATENCY),
        .DMEM_WRITE_LATENCY(DMEM_WRITE_LATENCY),
        .DMEM_WORDS(DMEM_WORDS),
        .DMEM_INIT_FILE(DMEM_INIT_FILE)
    ) u_cpu (
        .clk(clk),
        .rst(rst),
        .if_valid(if_valid),
        .if_pc(if_pc),
        .if_inst(if_inst),
        .if_ready(if_ready),

        .branch_resolve_valid(branch_resolve_valid),
        .branch_redirect(branch_redirect),
        .branch_redirect_pc(branch_redirect_pc),

        .wb_commit_valid(wb_commit_valid),
        .wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd),
        .wb_commit_data(wb_commit_data),

        .mem_store_commit_valid(mem_store_commit_valid),
        .mem_store_commit_pc(mem_store_commit_pc),
        .mem_store_commit_addr(mem_store_commit_addr),
        .mem_store_commit_data(mem_store_commit_data),

        .load_use_stall(load_use_stall),
        .id_unsupported(id_unsupported),
        .id_raw_hazard(id_raw_hazard),

        .mem_stall(mem_stall),
        .dmem_req_fire(dmem_req_fire),
        .dmem_resp_fire(dmem_resp_fire),
        .mem_fault_valid(mem_fault_valid),
        .mem_fault_pc(mem_fault_pc),
        .mem_fault_addr(mem_fault_addr),
        .mem_fault_store(mem_fault_store),

        .mdu_start_fire(mdu_start_fire),
        .mdu_busy(mdu_busy),
        .mdu_done(mdu_done),
        .mdu_result_fire(mdu_result_fire),
        .mdu_div_zero(mdu_div_zero)
    );

    // ---------------------------------------------------------------------
    // Board-visible completion and fault indicators
    // ---------------------------------------------------------------------
    // After the final in-range fetch, allow a quiet drain interval so that
    // the final MDU / DMEM operations and pipeline writebacks can complete.
    // This is a status indicator only; it does not change CPU control.
    localparam integer DONE_DRAIN_CYCLES = 128;
    reg [7:0] done_quiet_count;

    always @(posedge clk) begin
        if (rst) begin
            done_quiet_count <= 8'd0;
            program_done     <= 1'b0;
            fault_sticky     <= 1'b0;
        end else begin
            if (mem_fault_valid || fetch_error_fire || id_unsupported)
                fault_sticky <= 1'b1;

            if (!program_done) begin
                if (!request_in_window &&
                    !adapter_busy &&
                    !mem_stall &&
                    !mdu_busy &&
                    !wb_commit_valid &&
                    !mem_store_commit_valid &&
                    !branch_redirect &&
                    !if_resp_hold) begin

                    if (done_quiet_count < DONE_DRAIN_CYCLES)
                        done_quiet_count <= done_quiet_count + 1'b1;

                    if (done_quiet_count == DONE_DRAIN_CYCLES - 1)
                        program_done <= 1'b1;
                end else begin
                    done_quiet_count <= 8'd0;
                end
            end
        end
    end

endmodule
