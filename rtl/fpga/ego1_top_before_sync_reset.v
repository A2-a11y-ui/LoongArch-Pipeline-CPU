`timescale 1ns / 1ps
// EGO1 board top for the V0.9 LoongArch pipeline CPU.
//
// EGO1 connections (manual V2.x):
//   clk       : 100 MHz oscillator, P17
//   sys_rst_n : dedicated reset button, P15, active low
//   led[15:0] : 16 active-high board LEDs
//
// LED display:
//   led[7:0]  = low byte of the most recent architectural WB data
//   led[12:8] = destination register of the most recent WB
//   led[13]   = program_done (sticky)
//   led[14]   = fault_sticky (sticky)
//   led[15]   = heartbeat (approximately 1.5 Hz)
//
// All 38 pipeline_cpu_fpga ports are explicitly connected.
// Diagnostic outputs not needed by the first board demo are captured in
// internal wires; they do not alter CPU operation.
module ego1_top #(
    parameter IMEM_FILE = "fpga_demo.mem",
    parameter integer PROGRAM_WORDS = 29
)(
    input  wire        clk,
    input  wire        sys_rst_n,
    output wire [15:0] led
);

    // Active-low external reset, asynchronous assertion and synchronous
    // deassertion. Internal CPU modules receive synchronous active-high rst.
    (* ASYNC_REG = "TRUE" *) reg [1:0] rst_pipe = 2'b11;

    always @(posedge clk or negedge sys_rst_n) begin
        if (!sys_rst_n)
            rst_pipe <= 2'b11;
        else
            rst_pipe <= {rst_pipe[0], 1'b0};
    end

    wire rst = rst_pipe[1];

    // ------------------------------------------------------------------
    // Architectural writeback observations
    // ------------------------------------------------------------------
    wire        wb_commit_valid;
    wire [31:0] wb_commit_pc;
    wire [4:0]  wb_commit_rd;
    wire [31:0] wb_commit_data;

    // ------------------------------------------------------------------
    // Store commit observations
    // ------------------------------------------------------------------
    wire        mem_store_commit_valid;
    wire [31:0] mem_store_commit_pc;
    wire [31:0] mem_store_commit_addr;
    wire [31:0] mem_store_commit_data;

    // ------------------------------------------------------------------
    // Control / diagnostic observations
    // ------------------------------------------------------------------
    wire        branch_resolve_valid;
    wire        branch_redirect;
    wire [31:0] branch_redirect_pc;
    wire        load_use_stall;
    wire        id_unsupported;
    wire        id_raw_hazard;
    wire        mem_stall;
    wire        dmem_req_fire;
    wire        dmem_resp_fire;
    wire        mem_fault_valid;
    wire [31:0] mem_fault_pc;
    wire [31:0] mem_fault_addr;
    wire        mem_fault_store;

    // ------------------------------------------------------------------
    // MDU observations
    // ------------------------------------------------------------------
    wire        mdu_start_fire;
    wire        mdu_busy;
    wire        mdu_done;
    wire        mdu_result_fire;
    wire        mdu_div_zero;

    // ------------------------------------------------------------------
    // Instruction-cache / instruction-fetch observations
    // ------------------------------------------------------------------
    wire        if_resp_fire;
    wire        if_resp_hold;
    wire        fetch_error_fire;
    wire        adapter_busy;
    wire [31:0] cache_hits;
    wire [31:0] cache_misses;
    wire [31:0] cache_refills;
    wire [31:0] backing_transactions;

    // ------------------------------------------------------------------
    // Sticky board-level status
    // ------------------------------------------------------------------
    wire program_done;
    wire fault_sticky;

    // ------------------------------------------------------------------
    // V0.9 FPGA CPU instance
    // ------------------------------------------------------------------
    pipeline_cpu_fpga #(
        .PROGRAM_WORDS(PROGRAM_WORDS),
        .IMEM_FILE(IMEM_FILE)
    ) u_cpu (
        .clk(clk),
        .rst(rst),

        // Architectural commit observations
        .wb_commit_valid(wb_commit_valid),
        .wb_commit_pc(wb_commit_pc),
        .wb_commit_rd(wb_commit_rd),
        .wb_commit_data(wb_commit_data),

        // Store commit observations
        .mem_store_commit_valid(mem_store_commit_valid),
        .mem_store_commit_pc(mem_store_commit_pc),
        .mem_store_commit_addr(mem_store_commit_addr),
        .mem_store_commit_data(mem_store_commit_data),

        // Control / diagnostic observations
        .branch_resolve_valid(branch_resolve_valid),
        .branch_redirect(branch_redirect),
        .branch_redirect_pc(branch_redirect_pc),
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

        // MDU observations
        .mdu_start_fire(mdu_start_fire),
        .mdu_busy(mdu_busy),
        .mdu_done(mdu_done),
        .mdu_result_fire(mdu_result_fire),
        .mdu_div_zero(mdu_div_zero),

        // I-Cache / IF observations
        .if_resp_fire(if_resp_fire),
        .if_resp_hold(if_resp_hold),
        .fetch_error_fire(fetch_error_fire),
        .adapter_busy(adapter_busy),
        .cache_hits(cache_hits),
        .cache_misses(cache_misses),
        .cache_refills(cache_refills),
        .backing_transactions(backing_transactions),

        // Board-level status
        .program_done(program_done),
        .fault_sticky(fault_sticky)
    );

    // ------------------------------------------------------------------
    // Board heartbeat and most-recent writeback display
    // ------------------------------------------------------------------
    reg [25:0] heartbeat_divider;
    reg [31:0] last_wb_data;
    reg [4:0]  last_wb_rd;

    always @(posedge clk) begin
        if (rst) begin
            heartbeat_divider <= 26'd0;
            last_wb_data      <= 32'd0;
            last_wb_rd        <= 5'd0;
        end else begin
            heartbeat_divider <= heartbeat_divider + 1'b1;

            if (wb_commit_valid) begin
                last_wb_data <= wb_commit_data;
                last_wb_rd   <= wb_commit_rd;
            end
        end
    end

    assign led[7:0]   = last_wb_data[7:0];
    assign led[12:8]  = last_wb_rd;
    assign led[13]    = program_done;
    assign led[14]    = fault_sticky;
    assign led[15]    = heartbeat_divider[25];

endmodule
