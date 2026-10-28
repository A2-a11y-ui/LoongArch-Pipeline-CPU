
module id_ex_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        flush,

    // Inputs from ID stage
    input  wire        id_valid,
    input  wire [31:0] id_pc,
    input  wire [31:0] id_pc_plus4,
    input  wire [31:0] id_inst,

    input  wire [4:0]  id_rs1_addr,
    input  wire [4:0]  id_rs2_addr,
    input  wire [4:0]  id_rd_addr,

    input  wire [31:0] id_rs1_data,
    input  wire [31:0] id_rs2_data,
    input  wire        id_rs1_used,
    input  wire        id_rs2_used,

    input  wire [31:0] id_imm,
    input  wire [3:0]  id_alu_op,
    input  wire        id_alu_src_imm,
    input  wire [2:0]  id_branch_type,

    input  wire [1:0]  id_wb_sel,
    input  wire        id_reg_write,
    input  wire        id_mem_read,
    input  wire        id_mem_write,

    // Outputs to EX stage
    output reg         ex_valid,
    output reg  [31:0] ex_pc,
    output reg  [31:0] ex_pc_plus4,
    output reg  [31:0] ex_inst,

    output reg  [4:0]  ex_rs1_addr,
    output reg  [4:0]  ex_rs2_addr,
    output reg  [4:0]  ex_rd_addr,

    output reg  [31:0] ex_rs1_data,
    output reg  [31:0] ex_rs2_data,
    output reg         ex_rs1_used,
    output reg         ex_rs2_used,

    output reg  [31:0] ex_imm,
    output reg  [3:0]  ex_alu_op,
    output reg         ex_alu_src_imm,
    output reg  [2:0]  ex_branch_type,

    output reg  [1:0]  ex_wb_sel,
    output reg         ex_reg_write,
    output reg         ex_mem_read,
    output reg         ex_mem_write
);

    // Priority: Reset > Flush > Stall > Capture
    always @(posedge clk) begin

        if (rst || flush) begin
            ex_valid       <= 1'b0;
            ex_pc          <= 32'd0;
            ex_pc_plus4    <= 32'd0;
            ex_inst        <= 32'd0;

            ex_rs1_addr    <= 5'd0;
            ex_rs2_addr    <= 5'd0;
            ex_rd_addr     <= 5'd0;

            ex_rs1_data    <= 32'd0;
            ex_rs2_data    <= 32'd0;
            ex_rs1_used    <= 1'b0;
            ex_rs2_used    <= 1'b0;

            ex_imm         <= 32'd0;
            ex_alu_op      <= 4'd0;
            ex_alu_src_imm <= 1'b0;
            ex_branch_type <= 3'd0;

            ex_wb_sel      <= 2'd0;
            ex_reg_write   <= 1'b0;
            ex_mem_read    <= 1'b0;
            ex_mem_write   <= 1'b0;
        end

        else if (!stall) begin
            ex_valid       <= id_valid;
            ex_pc          <= id_pc;
            ex_pc_plus4    <= id_pc_plus4;
            ex_inst        <= id_inst;

            ex_rs1_addr    <= id_rs1_addr;
            ex_rs2_addr    <= id_rs2_addr;
            ex_rd_addr     <= id_rd_addr;

            ex_rs1_data    <= id_rs1_data;
            ex_rs2_data    <= id_rs2_data;
            ex_rs1_used    <= id_rs1_used;
            ex_rs2_used    <= id_rs2_used;

            ex_imm         <= id_imm;
            ex_alu_op      <= id_alu_op;
            ex_alu_src_imm <= id_alu_src_imm;
            ex_branch_type <= id_branch_type;

            ex_wb_sel      <= id_wb_sel;
            ex_reg_write   <= id_reg_write;
            ex_mem_read    <= id_mem_read;
            ex_mem_write   <= id_mem_write;
        end

        // Stall: hold all registered fields.

    end

endmodule
