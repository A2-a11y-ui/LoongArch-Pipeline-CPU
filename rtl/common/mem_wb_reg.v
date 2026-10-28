// MEM/WB pipeline register for the five-stage LoongArch CPU.
// Verilog-2001; synchronous active-high reset.
// Priority: reset > flush > stall > capture.
module mem_wb_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        flush,

    // MEM-stage results. mem_wb_data is already selected (ALU/DMEM/PC+4).
    input  wire        mem_valid,
    input  wire [31:0] mem_pc,
    input  wire [31:0] mem_wb_data,
    input  wire [4:0]  mem_rd_addr,
    input  wire        mem_reg_write,

    // WB-stage registered outputs.
    output reg         wb_valid,
    output reg  [31:0] wb_pc,
    output reg  [31:0] wb_data,
    output reg  [4:0]  wb_rd_addr,
    output reg         wb_reg_write,

    // Register-file write qualification (not a one-cycle commit pulse).
    output wire        wb_write_en
);

    always @(posedge clk) begin
        if (rst || flush) begin
            wb_valid     <= 1'b0;
            wb_pc        <= 32'd0;
            wb_data      <= 32'd0;
            wb_rd_addr   <= 5'd0;
            wb_reg_write <= 1'b0;
        end else if (!stall) begin
            wb_valid     <= mem_valid;
            wb_pc        <= mem_pc;
            wb_data      <= mem_wb_data;
            wb_rd_addr   <= mem_rd_addr;
            wb_reg_write <= mem_reg_write;
        end
        // stall=1: retain the whole WB register.
    end

    // An invalid slot, non-writing instruction, or destination r0 must
    // never assert the register-file write enable.
    assign wb_write_en = wb_valid && wb_reg_write && (wb_rd_addr != 5'd0);

endmodule
