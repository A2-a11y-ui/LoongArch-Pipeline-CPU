
module if_id_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        flush,

    input  wire        if_valid,
    input  wire [31:0] if_pc,
    input  wire [31:0] if_inst,

    output reg         id_valid,
    output reg  [31:0] id_pc,
    output reg  [31:0] id_inst
);

    always @(posedge clk) begin

        // Priority 1: Reset
        if (rst) begin
            id_valid <= 1'b0;
            id_pc    <= 32'b0;
            id_inst  <= 32'b0;
        end

        // Priority 2: Flush
        else if (flush) begin
            id_valid <= 1'b0;
            id_pc    <= 32'b0;
            id_inst  <= 32'b0;
        end

        // Priority 3: Normal update
        else if (!stall) begin
            id_valid <= if_valid;

            if (if_valid) begin
                id_pc   <= if_pc;
                id_inst <= if_inst;
            end
            else begin
                id_pc   <= 32'b0;
                id_inst <= 32'b0;
            end
        end

        // When stall = 1, keep previous values.

    end

endmodule
