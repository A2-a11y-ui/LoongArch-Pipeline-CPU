
module branch_unit (
    input  wire [2:0]  branch_type,
    input  wire [31:0] pc,
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    input  wire [31:0] branch_imm,

    output reg         redirect,
    output reg  [31:0] target_pc
);

    // Branch type definitions
    localparam BR_NONE = 3'd0;
    localparam BR_BEQ  = 3'd1;
    localparam BR_BNE  = 3'd2;
    localparam BR_B    = 3'd3;
    localparam BR_BL   = 3'd4;
    localparam BR_JIRL = 3'd5;

    
    // Combinational branch decision and target address
    always @(*) begin

        // Default: no branch
        redirect  = 1'b0;
        target_pc = 32'b0;

        case (branch_type)

            BR_NONE: begin
                redirect  = 1'b0;
                target_pc = 32'b0;
            end

            BR_BEQ: begin
                if (rs1_data == rs2_data) begin
                    redirect  = 1'b1;
                    target_pc = pc + branch_imm;
                end
            end

            BR_BNE: begin
                if (rs1_data != rs2_data) begin
                    redirect  = 1'b1;
                    target_pc = pc + branch_imm;
                end
            end

            BR_B: begin
                redirect  = 1'b1;
                target_pc = pc + branch_imm;
            end

            BR_BL: begin
                redirect  = 1'b1;
                target_pc = pc + branch_imm;
            end

            BR_JIRL: begin
                redirect  = 1'b1;
                target_pc = rs1_data + branch_imm;
            end

            default: begin
                redirect  = 1'b0;
                target_pc = 32'b0;
            end

        endcase
    end


endmodule
