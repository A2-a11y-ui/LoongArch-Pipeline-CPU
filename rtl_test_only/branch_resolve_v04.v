`timescale 1ns / 1ps
// EX-stage branch resolver for the V0.4 TEST-ONLY streaming CPU.
// Uses the branch_type encodings from official decoder.v.
// LoongArch offs16/offs26 are already sign-extended AND shifted by 2
// by the official imm_gen.v. Branch PC is the branch instruction address.
module branch_resolve_v04 (
    input  wire        rst,
    input  wire        ex_valid,
    input  wire [2:0]  branch_type,
    input  wire [31:0] pc,
    input  wire [31:0] imm,
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    output wire        resolve_valid,
    output reg         redirect_valid,
    output reg [31:0]  redirect_pc
);
    localparam [2:0] BR_BEQ=3'd1, BR_BNE=3'd2,
                     BR_B=3'd3, BR_BL=3'd4, BR_JIRL=3'd5;
    assign resolve_valid = !rst && ex_valid &&
           (branch_type >= BR_BEQ) && (branch_type <= BR_JIRL);
    always @(*) begin
        redirect_valid = 1'b0;
        redirect_pc = 32'd0;
        if (resolve_valid) begin
            case (branch_type)
                BR_BEQ:  begin
                    redirect_valid = (rs1_data == rs2_data);
                    redirect_pc = pc + imm;
                end
                BR_BNE:  begin
                    redirect_valid = (rs1_data != rs2_data);
                    redirect_pc = pc + imm;
                end
                BR_B, BR_BL: begin
                    redirect_valid = 1'b1;
                    redirect_pc = pc + imm;
                end
                BR_JIRL: begin
                    redirect_valid = 1'b1;
                    // JIRL clears address bit zero by architectural rule.
                    redirect_pc = (rs1_data + imm) & 32'hffff_fffe;
                end
                default: begin end
            endcase
        end
        // Target is architecturally meaningful only when redirect_valid=1.
        if (!redirect_valid) redirect_pc = 32'd0;
    end
endmodule
