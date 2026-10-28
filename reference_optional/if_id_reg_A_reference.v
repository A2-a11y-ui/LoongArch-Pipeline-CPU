// Reference ONLY: matches team-A IF/ID RTL supplied in chat for V0.6.
// If rtl/common/if_id_reg.v already exists in your Vivado project,
// DO NOT ADD this duplicate module to Design/Simulation Sources.
module if_id_reg (
    input wire clk, rst, stall, flush, if_valid,
    input wire [31:0] if_pc, if_inst,
    output reg id_valid,
    output reg [31:0] id_pc, id_inst
);
    always @(posedge clk) begin
        if (rst) begin
            id_valid <= 1'b0; id_pc <= 32'b0; id_inst <= 32'b0;
        end else if (flush) begin
            id_valid <= 1'b0; id_pc <= 32'b0; id_inst <= 32'b0;
        end else if (!stall) begin
            id_valid <= if_valid;
            if (if_valid) begin
                id_pc <= if_pc; id_inst <= if_inst;
            end else begin
                id_pc <= 32'b0; id_inst <= 32'b0;
            end
        end
    end
endmodule
