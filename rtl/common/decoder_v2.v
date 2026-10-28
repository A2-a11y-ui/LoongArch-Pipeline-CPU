`include "../common/cpu_defs.vh"
// Decoder V2 prototype: 13 base + BEQ/BNE/B/BL/JIRL = 18 instructions.
// Module name is decoder_v2 so existing decoder.v remains untouched.
// Compatible with Vivado 2019.1 (Verilog-2001).
module decoder_v2 (
    input  wire [31:0] inst,
    output reg  [4:0] rs1_addr,
    output reg  [4:0] rs2_addr,
    output reg  [4:0] rd_addr,
    output reg        rs1_used,
    output reg        rs2_used,
    output reg  [3:0] alu_op,
    output reg  [2:0] imm_sel,
    output reg        alu_src_imm,
    output reg        reg_write,
    output reg        mem_read,
    output reg        mem_write,
    output wire       wb_sel_mem, // backward-compatible alias (only true for LD.W)
    output reg        valid,
    output reg  [2:0] branch_type,
    output reg  [1:0] wb_sel
);
    localparam [31:0] MASK_3R=32'hFFFF8000;
    localparam [31:0] MASK_I12=32'hFFC00000;
    localparam [31:0] MASK_U20=32'hFE000000;

    localparam [31:0] OP_NOR     =32'h00140000;
    localparam [31:0] OP_AND     =32'h00148000;
    localparam [31:0] OP_OR      =32'h00150000;
    localparam [31:0] OP_XOR     =32'h00158000;
    localparam [31:0] OP_ANDI    =32'h03400000;
    localparam [31:0] OP_ORI     =32'h03800000;
    localparam [31:0] OP_XORI    =32'h03C00000;
    localparam [31:0] OP_SLLI_W  =32'h00408000;
    localparam [31:0] OP_SRLI_W  =32'h00448000;
    localparam [31:0] OP_SRAI_W  =32'h00488000;
    localparam [31:0] OP_LU12I_W =32'h14000000;
    localparam [31:0] OP_LD_W    =32'h28800000;
    localparam [31:0] OP_ST_W    =32'h29800000;

    localparam [5:0] OP_JIRL =6'h13;
    localparam [5:0] OP_B    =6'h14;
    localparam [5:0] OP_BL   =6'h15;
    localparam [5:0] OP_BEQ  =6'h16;
    localparam [5:0] OP_BNE  =6'h17;

    localparam [2:0] BR_NONE=3'd0, BR_BEQ=3'd1, BR_BNE=3'd2,
                     BR_B=3'd3, BR_BL=3'd4, BR_JIRL=3'd5;
    localparam [1:0] WB_ALU=2'b00, WB_MEM=2'b01, WB_PC4=2'b10;

    // Old users can still connect wb_sel_mem without changing their code.
    assign wb_sel_mem = (wb_sel == WB_MEM);

    always @(*) begin
        rs1_addr = 5'd0;
        rs2_addr = 5'd0;
        rd_addr  = 5'd0;
        rs1_used = 1'b0;
        rs2_used = 1'b0;
        alu_op = `ALU_ADD;
        imm_sel = 3'd0;
        alu_src_imm = 1'b0;
        reg_write = 1'b0;
        mem_read = 1'b0;
        mem_write = 1'b0;
        valid = 1'b0;
        branch_type = BR_NONE;
        wb_sel = WB_ALU;

        if ((inst & MASK_3R) == OP_AND) begin
            valid=1; alu_op=`ALU_AND; rs1_used=1; rs2_used=1; reg_write=1;
        end else if ((inst & MASK_3R) == OP_OR) begin
            valid=1; alu_op=`ALU_OR; rs1_used=1; rs2_used=1; reg_write=1;
        end else if ((inst & MASK_3R) == OP_NOR) begin
            valid=1; alu_op=`ALU_NOR; rs1_used=1; rs2_used=1; reg_write=1;
        end else if ((inst & MASK_3R) == OP_XOR) begin
            valid=1; alu_op=`ALU_XOR; rs1_used=1; rs2_used=1; reg_write=1;
        end else if ((inst & MASK_I12) == OP_ANDI) begin
            valid=1; alu_op=`ALU_AND; imm_sel=2; alu_src_imm=1; rs1_used=1; reg_write=1;
        end else if ((inst & MASK_I12) == OP_ORI) begin
            valid=1; alu_op=`ALU_OR; imm_sel=2; alu_src_imm=1; rs1_used=1; reg_write=1;
        end else if ((inst & MASK_I12) == OP_XORI) begin
            valid=1; alu_op=`ALU_XOR; imm_sel=2; alu_src_imm=1; rs1_used=1; reg_write=1;
        end else if ((inst & MASK_3R) == OP_SLLI_W) begin
            valid=1; alu_op=`ALU_SLL; imm_sel=3; alu_src_imm=1; rs1_used=1; reg_write=1;
        end else if ((inst & MASK_3R) == OP_SRLI_W) begin
            valid=1; alu_op=`ALU_SRL; imm_sel=3; alu_src_imm=1; rs1_used=1; reg_write=1;
        end else if ((inst & MASK_3R) == OP_SRAI_W) begin
            valid=1; alu_op=`ALU_SRA; imm_sel=3; alu_src_imm=1; rs1_used=1; reg_write=1;
        end else if ((inst & MASK_U20) == OP_LU12I_W) begin
            valid=1; alu_op=`ALU_PASS_B; imm_sel=4; alu_src_imm=1; reg_write=1;
        end else if ((inst & MASK_I12) == OP_LD_W) begin
            valid=1; alu_op=`ALU_ADD; imm_sel=1; alu_src_imm=1;
            rs1_used=1; reg_write=1; mem_read=1; wb_sel=WB_MEM;
        end else if ((inst & MASK_I12) == OP_ST_W) begin
            valid=1; alu_op=`ALU_ADD; imm_sel=1; alu_src_imm=1;
            rs1_used=1; rs2_used=1; mem_write=1;
        end else begin
            case (inst[31:26])
                OP_BEQ: begin
                    valid=1; branch_type=BR_BEQ; imm_sel=5;
                    rs1_used=1; rs2_used=1;
                end
                OP_BNE: begin
                    valid=1; branch_type=BR_BNE; imm_sel=5;
                    rs1_used=1; rs2_used=1;
                end
                OP_B: begin
                    valid=1; branch_type=BR_B; imm_sel=6;
                end
                OP_BL: begin
                    valid=1; branch_type=BR_BL; imm_sel=6;
                    reg_write=1; wb_sel=WB_PC4;
                end
                OP_JIRL: begin
                    valid=1; branch_type=BR_JIRL; imm_sel=5;
                    rs1_used=1; reg_write=1; wb_sel=WB_PC4;
                end
                default: begin end
            endcase
        end

        if (valid) begin
            if (rs1_used) rs1_addr = inst[9:5];
            if (rs2_used) begin
                // ST.W and BEQ/BNE use rd field as the second source.
                if (mem_write || branch_type==BR_BEQ || branch_type==BR_BNE)
                    rs2_addr = inst[4:0];
                else
                    rs2_addr = inst[14:10];
            end
            if (reg_write) begin
                if (branch_type==BR_BL) rd_addr=5'd1;
                else rd_addr=inst[4:0];
            end else if (branch_type==BR_NONE && mem_write) begin
                // Preserve old decoder's ST.W rd_addr informational behavior.
                rd_addr=inst[4:0];
            end else if (branch_type==BR_NONE) begin
                // Preserve old decoder's rd_addr output for other valid instructions.
                rd_addr=inst[4:0];
            end
        end
    end
endmodule
