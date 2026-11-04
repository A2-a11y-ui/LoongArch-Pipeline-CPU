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
// No seven-segment display or external SRAM is required for this first
// hardware integration milestone.
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

    wire        wb_commit_valid;
    wire [4:0]  wb_commit_rd;
    wire [31:0] wb_commit_data;
    wire        program_done;
    wire        fault_sticky;

    pipeline_cpu_fpga #(
        .PROGRAM_WORDS(PROGRAM_WORDS),
        .IMEM_FILE(IMEM_FILE)
    ) u_cpu (
        .clk(clk),
        .rst(rst),
        .wb_commit_valid(wb_commit_valid),
        .wb_commit_rd(wb_commit_rd),
        .wb_commit_data(wb_commit_data),
        .program_done(program_done),
        .fault_sticky(fault_sticky)
    );

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
