// LoongArch-Pipeline-CPU : immediate generator V2
// Interface remains identical to V1.1: inst[31:0], imm_sel[2:0], imm[31:0].
// Change V2: selects 5 and 6 now generate branch byte offsets.
// BEQ/BNE/JIRL offs16: sign-extend {inst[25:10], 2'b0}.
// B/BL offs26: sign-extend {{inst[9:0], inst[25:10]}, 2'b0}.
// imm_sel=7 stays reserved.
module imm_gen (
    input  wire [31:0] inst,
    input  wire [2:0]  imm_sel,
    output reg  [31:0] imm
);

    always @(*) begin
        case (imm_sel)
            3'd0: imm = 32'b0;
            3'd1: imm = {{20{inst[21]}}, inst[21:10]};
            3'd2: imm = {20'b0, inst[21:10]};
            3'd3: imm = {27'b0, inst[14:10]};
            3'd4: imm = {inst[24:5], 12'b0};
            3'd5: imm = {{14{inst[25]}}, inst[25:10], 2'b0};
            3'd6: imm = {{4{inst[9]}}, inst[9:0], inst[25:10], 2'b0};
            3'd7: imm = 32'b0;
            default: imm = 32'b0;
        endcase
    end
endmodule
