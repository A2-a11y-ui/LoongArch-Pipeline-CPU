`timescale 1ns / 1ps
// V0.8 add-on decoder: ONLY the 7 LA32 3-register MDU instructions.
// Does NOT replace or modify the stable decoder.v.
// LoongArch encoding: {fixed 17 opcode bits, rk[14:10], rj[9:5], rd[4:0]}.
module mdu_decode_v08 (
    input wire [31:0] inst,
    output reg is_mdu,
    output reg [2:0] mdu_op
);
    localparam [31:0] MASK_3R = 32'hFFFF8000;
    // op mapping is the one implemented by mdu_iterative.v
    always @(*) begin
        is_mdu = 1'b1;
        mdu_op = 3'b111;
        case (inst & MASK_3R)
            32'h001C0000: mdu_op = 3'b000; // MUL.W
            32'h001C8000: mdu_op = 3'b001; // MULH.W
            32'h001D0000: mdu_op = 3'b010; // MULH.WU
            32'h00200000: mdu_op = 3'b011; // DIV.W
            32'h00210000: mdu_op = 3'b100; // DIV.WU
            32'h00208000: mdu_op = 3'b101; // MOD.W
            32'h00218000: mdu_op = 3'b110; // MOD.WU
            default: begin is_mdu=1'b0; mdu_op=3'b111; end
        endcase
    end
endmodule
