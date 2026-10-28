`include "../common/cpu_defs.vh"

// LoongArch LA32 - team B 13-instruction decoder, stage 1.
// This is a shared-decoder PROTOTYPE; branch/other instructions are not yet decoded.
// Combinational, no clock/reset. Designed for Vivado 2019.1 / Verilog-2001.
module decoder (
    input  wire [31:0] inst,
    output reg  [4:0]  rs1_addr,
    output reg  [4:0]  rs2_addr,
    output reg  [4:0]  rd_addr,
    output reg         rs1_used,
    output reg         rs2_used,
    output reg  [3:0]  alu_op,
    output reg  [2:0]  imm_sel,
    output reg         alu_src_imm,
    output reg         reg_write,
    output reg         mem_read,
    output reg         mem_write,
    output reg         wb_sel_mem,
    output reg         valid
);

    // Real LoongArch opcode MATCH values. These are NOT ALU control codes.
    localparam [31:0] MASK_3R    = 32'hFFFF8000;
    localparam [31:0] MASK_I12   = 32'hFFC00000;
    localparam [31:0] MASK_U20   = 32'hFE000000;

    localparam [31:0] OP_NOR     = 32'h00140000;
    localparam [31:0] OP_AND     = 32'h00148000;
    localparam [31:0] OP_OR      = 32'h00150000;
    localparam [31:0] OP_XOR     = 32'h00158000;
    localparam [31:0] OP_ANDI    = 32'h03400000;
    localparam [31:0] OP_ORI     = 32'h03800000;
    localparam [31:0] OP_XORI    = 32'h03C00000;
    localparam [31:0] OP_SLLI_W  = 32'h00408000;
    localparam [31:0] OP_SRLI_W  = 32'h00448000;
    localparam [31:0] OP_SRAI_W  = 32'h00488000;
    localparam [31:0] OP_LU12I_W = 32'h14000000;
    localparam [31:0] OP_LD_W    = 32'h28800000;
    localparam [31:0] OP_ST_W    = 32'h29800000;

    always @(*) begin
        // Safe defaults. Unknown/unsupported instruction: no side effects.
        rs1_addr    = 5'd0;
        rs2_addr    = 5'd0;
        rd_addr     = 5'd0;
        rs1_used    = 1'b0;
        rs2_used    = 1'b0;
        alu_op      = `ALU_ADD;
        imm_sel     = 3'd0;
        alu_src_imm = 1'b0;
        reg_write   = 1'b0;
        mem_read    = 1'b0;
        mem_write   = 1'b0;
        wb_sel_mem  = 1'b0;
        valid       = 1'b0;

        if ((inst & MASK_3R) == OP_AND) begin
            valid = 1'b1;
            alu_op = `ALU_AND;
            rs1_used = 1'b1;
            rs2_used = 1'b1;
            reg_write = 1'b1;
        end
        else if ((inst & MASK_3R) == OP_OR) begin
            valid = 1'b1;
            alu_op = `ALU_OR;
            rs1_used = 1'b1;
            rs2_used = 1'b1;
            reg_write = 1'b1;
        end
        else if ((inst & MASK_3R) == OP_NOR) begin
            valid = 1'b1;
            alu_op = `ALU_NOR;
            rs1_used = 1'b1;
            rs2_used = 1'b1;
            reg_write = 1'b1;
        end
        else if ((inst & MASK_3R) == OP_XOR) begin
            valid = 1'b1;
            alu_op = `ALU_XOR;
            rs1_used = 1'b1;
            rs2_used = 1'b1;
            reg_write = 1'b1;
        end
        else if ((inst & MASK_I12) == OP_ANDI) begin
            valid = 1'b1;
            alu_op = `ALU_AND;
            imm_sel = 3'd2;
            alu_src_imm = 1'b1;
            rs1_used = 1'b1;
            reg_write = 1'b1;
        end
        else if ((inst & MASK_I12) == OP_ORI) begin
            valid = 1'b1;
            alu_op = `ALU_OR;
            imm_sel = 3'd2;
            alu_src_imm = 1'b1;
            rs1_used = 1'b1;
            reg_write = 1'b1;
        end
        else if ((inst & MASK_I12) == OP_XORI) begin
            valid = 1'b1;
            alu_op = `ALU_XOR;
            imm_sel = 3'd2;
            alu_src_imm = 1'b1;
            rs1_used = 1'b1;
            reg_write = 1'b1;
        end
        else if ((inst & MASK_3R) == OP_SLLI_W) begin
            valid = 1'b1;
            alu_op = `ALU_SLL;
            imm_sel = 3'd3;
            alu_src_imm = 1'b1;
            rs1_used = 1'b1;
            reg_write = 1'b1;
        end
        else if ((inst & MASK_3R) == OP_SRLI_W) begin
            valid = 1'b1;
            alu_op = `ALU_SRL;
            imm_sel = 3'd3;
            alu_src_imm = 1'b1;
            rs1_used = 1'b1;
            reg_write = 1'b1;
        end
        else if ((inst & MASK_3R) == OP_SRAI_W) begin
            valid = 1'b1;
            alu_op = `ALU_SRA;
            imm_sel = 3'd3;
            alu_src_imm = 1'b1;
            rs1_used = 1'b1;
            reg_write = 1'b1;
        end
        else if ((inst & MASK_U20) == OP_LU12I_W) begin
            valid = 1'b1;
            alu_op = `ALU_PASS_B;
            imm_sel = 3'd4;
            alu_src_imm = 1'b1;
            reg_write = 1'b1;
        end
        else if ((inst & MASK_I12) == OP_LD_W) begin
            valid = 1'b1;
            alu_op = `ALU_ADD;
            imm_sel = 3'd1;
            alu_src_imm = 1'b1;
            rs1_used = 1'b1;
            reg_write = 1'b1;
            mem_read = 1'b1;
            wb_sel_mem = 1'b1;
        end
        else if ((inst & MASK_I12) == OP_ST_W) begin
            valid = 1'b1;
            alu_op = `ALU_ADD;
            imm_sel = 3'd1;
            alu_src_imm = 1'b1;
            rs1_used = 1'b1;
            rs2_used = 1'b1;
            mem_write = 1'b1;
        end

        // Register-file addresses. ST.W stores GR[rd], not GR[rk].
        if (valid) begin
            rd_addr = inst[4:0];          // destination for regwrite; store-data field for ST.W
            if (rs1_used)
                rs1_addr = inst[9:5];
            if (rs2_used)
                rs2_addr = mem_write ? inst[4:0] : inst[14:10];
        end
    end

endmodule
