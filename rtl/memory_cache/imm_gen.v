
`timescale 1ns / 1ps

// ============================================================
// Module: imm_gen
// Description:
//   Generate a 32-bit immediate according to imm_sel.
//
// Inputs:
//   inst    : 32-bit LoongArch instruction
//   imm_sel : immediate format selector
//
// Output:
//   imm     : 32-bit generated immediate
//
// imm_sel:
//   3'd0 : no immediate, output zero
//   3'd1 : signed 12-bit immediate
//   3'd2 : unsigned 12-bit immediate
//   3'd3 : unsigned 5-bit shift amount
//   3'd4 : upper 20-bit immediate, low 12 bits zero
//   3'd5-7 : reserved, output zero in this version
// ============================================================

module imm_gen (
    input  wire [31:0] inst,
    input  wire [2:0]  imm_sel,
    output reg  [31:0] imm
);

    always @(*) begin
        // Default value prevents unintended latch inference.
        imm = 32'b0;

        case (imm_sel)

            // No immediate
            3'd0: begin
                imm = 32'b0;
            end

            // Signed 12-bit immediate: inst[21:10]
            3'd1: begin
                imm = {{20{inst[21]}}, inst[21:10]};
            end

            // Unsigned 12-bit immediate: inst[21:10]
            3'd2: begin
                imm = {20'b0, inst[21:10]};
            end

            // Unsigned 5-bit shift amount: inst[14:10]
            3'd3: begin
                imm = {27'b0, inst[14:10]};
            end

            // Upper 20-bit immediate: inst[24:5]
            3'd4: begin
                imm = {inst[24:5], 12'b0};
            end

            // Reserved selectors
            default: begin
                imm = 32'b0;
            end

        endcase
    end

endmodule
