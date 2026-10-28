
module ex_mem_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        flush,

    // Inputs from EX stage
    input  wire        ex_valid,
    input  wire [31:0] ex_pc,
    input  wire [31:0] ex_pc_plus4,

    input  wire [31:0] ex_alu_result,
    input  wire [31:0] ex_store_data,

    input  wire [4:0]  ex_store_src_addr,
    input  wire [4:0]  ex_rd_addr,

    input  wire        ex_mem_read,
    input  wire        ex_mem_write,
    input  wire        ex_reg_write,
    input  wire [1:0]  ex_wb_sel,

    // Outputs to MEM stage
    output reg         mem_valid,
    output reg  [31:0] mem_pc,
    output reg  [31:0] mem_pc_plus4,

    output reg  [31:0] mem_alu_result,
    output reg  [31:0] mem_store_data,

    output reg  [4:0]  mem_store_src_addr,
    output reg  [4:0]  mem_rd_addr,

    output reg         mem_mem_read,
    output reg         mem_mem_write,
    output reg         mem_reg_write,
    output reg  [1:0]  mem_wb_sel
);

    // Synchronous pipeline register
    // Priority: Reset > Flush > Stall > Capture

    always @(posedge clk) begin

        if (rst || flush) begin

            mem_valid          <= 1'b0;
            mem_pc             <= 32'd0;
            mem_pc_plus4       <= 32'd0;

            mem_alu_result     <= 32'd0;
            mem_store_data     <= 32'd0;

            mem_store_src_addr <= 5'd0;
            mem_rd_addr        <= 5'd0;

            mem_mem_read       <= 1'b0;
            mem_mem_write      <= 1'b0;
            mem_reg_write      <= 1'b0;
            mem_wb_sel         <= 2'd0;

        end

        else if (!stall) begin

            mem_valid          <= ex_valid;
            mem_pc             <= ex_pc;
            mem_pc_plus4       <= ex_pc_plus4;

            mem_alu_result     <= ex_alu_result;
            mem_store_data     <= ex_store_data;

            mem_store_src_addr <= ex_store_src_addr;
            mem_rd_addr        <= ex_rd_addr;

            mem_mem_read       <= ex_mem_read;
            mem_mem_write      <= ex_mem_write;
            mem_reg_write      <= ex_reg_write;
            mem_wb_sel         <= ex_wb_sel;

        end

        // stall=1:
        // All registered values remain unchanged.

    end

endmodule
