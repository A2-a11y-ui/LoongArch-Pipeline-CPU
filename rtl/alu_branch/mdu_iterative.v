`timescale 1ns / 1ps
// V0.8 iterative MDU for the LoongArch 32-bit course CPU.
// Verilog-2001; intended for Vivado 2019.1.
//
// Request acceptance:
//   A request is accepted on posedge clk when start=1, busy=0 and done=0.
//   start should be a one-cycle pulse. Requests presented while busy or while
//   a previous result is pending are ignored.
//
// Result handshake:
//   done=1 means result/div_zero are valid. They remain stable until
//   done && result_ready is sampled on a rising edge.
//   A new request may be accepted on a later rising edge after that handshake.
//
// Latency:
//   MUL and non-zero DIV/MOD perform exactly 32 iterative steps.
//   Divide-by-zero and reserved-op requests complete on the acceptance edge.
//
// Divide-by-zero convention (deterministic implementation choice):
//   DIV.W / DIV.WU -> result = 32'hFFFF_FFFF
//   MOD.W / MOD.WU -> result = operand_a
//   div_zero = 1 until the result handshake.
// This is a module-level convention; the CPU does not raise an architectural
// exception in V0.8.
//
// Signed DIV uses truncation toward zero; signed MOD has the sign of operand_a.
// 0x80000000 / 0xFFFF_FFFF returns 0x80000000; corresponding MOD returns 0.
// Reset is synchronous, active high, and cancels both an active operation and
// a completed-but-unconsumed result.

module mdu_iterative (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [2:0]  op,
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,
    input  wire        result_ready,

    output reg         busy,
    output reg         done,
    output reg  [31:0] result,
    output reg         div_zero
);

    localparam [2:0] MDU_MUL_W   = 3'b000;
    localparam [2:0] MDU_MULH_W  = 3'b001;
    localparam [2:0] MDU_MULH_WU = 3'b010;
    localparam [2:0] MDU_DIV_W   = 3'b011;
    localparam [2:0] MDU_DIV_WU  = 3'b100;
    localparam [2:0] MDU_MOD_W   = 3'b101;
    localparam [2:0] MDU_MOD_WU  = 3'b110;
    localparam [2:0] MDU_RSVD    = 3'b111;

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_MUL  = 2'd1;
    localparam [1:0] ST_DIV  = 2'd2;

    reg [1:0] state;
    reg [2:0] op_reg;
    reg [5:0] iter_count;

    // Iterative shift-add multiplier state.
    reg [63:0] mul_accum;
    reg [63:0] mul_multiplicand;
    reg [31:0] mul_multiplier;
    reg        mul_negate;

    // Iterative restoring divider state.
    reg [31:0] div_quotient;
    reg [31:0] div_divisor;
    reg [32:0] div_remainder;
    reg        div_q_negate;
    reg        div_r_negate;

    wire [31:0] abs_operand_a =
        operand_a[31] ? (~operand_a + 32'd1) : operand_a;
    wire [31:0] abs_operand_b =
        operand_b[31] ? (~operand_b + 32'd1) : operand_b;

    wire [63:0] mul_accum_next =
        mul_accum + (mul_multiplier[0] ? mul_multiplicand : 64'd0);
    wire [63:0] mul_product_next =
        mul_negate ? (~mul_accum_next + 64'd1) : mul_accum_next;

    wire [32:0] div_shifted_remainder =
        {div_remainder[31:0], div_quotient[31]};
    wire        div_subtract =
        (div_shifted_remainder >= {1'b0, div_divisor});
    wire [32:0] div_remainder_next =
        div_subtract
            ? (div_shifted_remainder - {1'b0, div_divisor})
            : div_shifted_remainder;
    wire [31:0] div_quotient_next =
        {div_quotient[30:0], div_subtract};
    wire [31:0] div_signed_quotient =
        div_q_negate ? (~div_quotient_next + 32'd1) : div_quotient_next;
    wire [31:0] div_signed_remainder =
        div_r_negate
            ? (~div_remainder_next[31:0] + 32'd1)
            : div_remainder_next[31:0];

    always @(posedge clk) begin
        if (rst) begin
            state             <= ST_IDLE;
            op_reg            <= MDU_RSVD;
            iter_count        <= 6'd0;
            busy              <= 1'b0;
            done              <= 1'b0;
            result            <= 32'd0;
            div_zero          <= 1'b0;

            mul_accum         <= 64'd0;
            mul_multiplicand  <= 64'd0;
            mul_multiplier    <= 32'd0;
            mul_negate        <= 1'b0;

            div_quotient      <= 32'd0;
            div_divisor       <= 32'd0;
            div_remainder     <= 33'd0;
            div_q_negate      <= 1'b0;
            div_r_negate      <= 1'b0;
        end else if (done) begin
            // Hold result and status under backpressure.
            if (result_ready) begin
                done       <= 1'b0;
                result     <= 32'd0;
                div_zero   <= 1'b0;
                state      <= ST_IDLE;
                iter_count <= 6'd0;
            end
        end else if (busy) begin
            case (state)
                ST_MUL: begin
                    mul_accum        <= mul_accum_next;
                    mul_multiplicand <= {mul_multiplicand[62:0], 1'b0};
                    mul_multiplier   <= {1'b0, mul_multiplier[31:1]};

                    if (iter_count == 6'd31) begin
                        if (op_reg == MDU_MUL_W)
                            result <= mul_product_next[31:0];
                        else
                            result <= mul_product_next[63:32];

                        busy       <= 1'b0;
                        done       <= 1'b1;
                        state      <= ST_IDLE;
                        iter_count <= 6'd0;
                    end else begin
                        iter_count <= iter_count + 6'd1;
                    end
                end

                ST_DIV: begin
                    div_quotient  <= div_quotient_next;
                    div_remainder <= div_remainder_next;

                    if (iter_count == 6'd31) begin
                        if (op_reg == MDU_DIV_W || op_reg == MDU_DIV_WU)
                            result <= div_signed_quotient;
                        else
                            result <= div_signed_remainder;

                        busy       <= 1'b0;
                        done       <= 1'b1;
                        state      <= ST_IDLE;
                        iter_count <= 6'd0;
                    end else begin
                        iter_count <= iter_count + 6'd1;
                    end
                end

                default: begin
                    // Defensive recovery from an illegal internal state.
                    state      <= ST_IDLE;
                    busy       <= 1'b0;
                    done       <= 1'b0;
                    result     <= 32'd0;
                    div_zero   <= 1'b0;
                    iter_count <= 6'd0;
                end
            endcase
        end else if (start) begin
            // start is accepted only in IDLE with no pending result.
            op_reg     <= op;
            iter_count <= 6'd0;
            div_zero   <= 1'b0;

            case (op)
                MDU_MUL_W, MDU_MULH_W: begin
                    mul_accum        <= 64'd0;
                    mul_multiplicand <= {32'd0, abs_operand_a};
                    mul_multiplier   <= abs_operand_b;
                    mul_negate       <= operand_a[31] ^ operand_b[31];
                    busy             <= 1'b1;
                    done             <= 1'b0;
                    state            <= ST_MUL;
                end

                MDU_MULH_WU: begin
                    mul_accum        <= 64'd0;
                    mul_multiplicand <= {32'd0, operand_a};
                    mul_multiplier   <= operand_b;
                    mul_negate       <= 1'b0;
                    busy             <= 1'b1;
                    done             <= 1'b0;
                    state            <= ST_MUL;
                end

                MDU_DIV_W, MDU_MOD_W: begin
                    if (operand_b == 32'd0) begin
                        result   <= (op == MDU_DIV_W) ? 32'hFFFF_FFFF : operand_a;
                        div_zero <= 1'b1;
                        busy     <= 1'b0;
                        done     <= 1'b1;
                        state    <= ST_IDLE;
                    end else begin
                        div_quotient  <= abs_operand_a;
                        div_divisor   <= abs_operand_b;
                        div_remainder <= 33'd0;
                        div_q_negate  <= operand_a[31] ^ operand_b[31];
                        div_r_negate  <= operand_a[31];
                        busy          <= 1'b1;
                        done          <= 1'b0;
                        state         <= ST_DIV;
                    end
                end

                MDU_DIV_WU, MDU_MOD_WU: begin
                    if (operand_b == 32'd0) begin
                        result   <= (op == MDU_DIV_WU) ? 32'hFFFF_FFFF : operand_a;
                        div_zero <= 1'b1;
                        busy     <= 1'b0;
                        done     <= 1'b1;
                        state    <= ST_IDLE;
                    end else begin
                        div_quotient  <= operand_a;
                        div_divisor   <= operand_b;
                        div_remainder <= 33'd0;
                        div_q_negate  <= 1'b0;
                        div_r_negate  <= 1'b0;
                        busy          <= 1'b1;
                        done          <= 1'b0;
                        state         <= ST_DIV;
                    end
                end

                default: begin
                    // Reserved op is completed deterministically with zero.
                    result   <= 32'd0;
                    div_zero <= 1'b0;
                    busy     <= 1'b0;
                    done     <= 1'b1;
                    state    <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
