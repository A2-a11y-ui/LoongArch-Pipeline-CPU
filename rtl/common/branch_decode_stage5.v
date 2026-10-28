// Stage 5 temporary branch decoder for BEQ/BNE/B/BL/JIRL.
// Verilog-2001, Vivado 2019.1. Does NOT replace the shared decoder.v.
// Match/Mask values use the real LoongArch opcode bits [31:26].
module branch_decode_stage5 (
    input  wire [31:0] inst,
    output reg         branch_valid,
    output reg  [2:0]  branch_type,
    output reg  [2:0]  imm_sel,
    output reg  [4:0]  rs1_addr,
    output reg  [4:0]  rs2_addr,
    output reg  [4:0]  link_rd,
    output reg         link_write
);
    localparam [5:0] OP_JIRL = 6'h13;
    localparam [5:0] OP_B    = 6'h14;
    localparam [5:0] OP_BL   = 6'h15;
    localparam [5:0] OP_BEQ  = 6'h16;
    localparam [5:0] OP_BNE  = 6'h17;

    always @(*) begin
        branch_valid = 1'b0;
        branch_type  = 3'd0;
        imm_sel      = 3'd0;
        rs1_addr     = 5'd0;
        rs2_addr     = 5'd0;
        link_rd      = 5'd0;
        link_write   = 1'b0;
        case (inst[31:26])
            OP_BEQ: begin
                branch_valid = 1'b1;
                branch_type = 3'd1;
                imm_sel = 3'd5;
                rs1_addr = inst[9:5];
                rs2_addr = inst[4:0]; // LoongArch BEQ compares rj with rd
            end
            OP_BNE: begin
                branch_valid = 1'b1;
                branch_type = 3'd2;
                imm_sel = 3'd5;
                rs1_addr = inst[9:5];
                rs2_addr = inst[4:0];
            end
            OP_B: begin
                branch_valid = 1'b1;
                branch_type = 3'd3;
                imm_sel = 3'd6;
            end
            OP_BL: begin
                branch_valid = 1'b1;
                branch_type = 3'd4;
                imm_sel = 3'd6;
                link_rd = 5'd1;      // BL always links into r1
                link_write = 1'b1;
            end
            OP_JIRL: begin
                branch_valid = 1'b1;
                branch_type = 3'd5;
                imm_sel = 3'd5;
                rs1_addr = inst[9:5];
                link_rd = inst[4:0];
                link_write = 1'b1;
            end
            default: begin end
        endcase
    end
endmodule
