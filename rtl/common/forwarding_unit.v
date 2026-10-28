
module forwarding_unit (
    // Current instruction in EX
    input  wire        ex_valid,
    input  wire [4:0]  ex_rs1_addr,
    input  wire [4:0]  ex_rs2_addr,
    input  wire        ex_rs1_used,
    input  wire        ex_rs2_used,

    // Instruction in EX/MEM
    input  wire        exmem_valid,
    input  wire        exmem_reg_write,
    input  wire [4:0]  exmem_rd_addr,
    input  wire        exmem_result_ready,

    // Instruction in MEM/WB
    input  wire        memwb_valid,
    input  wire        memwb_reg_write,
    input  wire [4:0]  memwb_rd_addr,

    // Forwarding select
    output reg [1:0]   forward_a,
    output reg [1:0]   forward_b,

    // Newer matching result is not yet ready
    output reg         wait_a,
    output reg         wait_b
);

    localparam FWD_REG = 2'b00;
    localparam FWD_WB  = 2'b01;
    localparam FWD_MEM = 2'b10;

    always @(*) begin
        // Defaults: use original register operands
        forward_a = FWD_REG;
        forward_b = FWD_REG;
        wait_a    = 1'b0;
        wait_b    = 1'b0;

        if (ex_valid) begin

            // Source register 1
            if (ex_rs1_used && ex_rs1_addr != 5'd0) begin

                if (exmem_valid && exmem_reg_write &&
                    exmem_rd_addr != 5'd0 &&
                    exmem_rd_addr == ex_rs1_addr) begin

                    if (exmem_result_ready)
                        forward_a = FWD_MEM;
                    else
                        wait_a = 1'b1;

                end
                else if (memwb_valid && memwb_reg_write &&
                         memwb_rd_addr != 5'd0 &&
                         memwb_rd_addr == ex_rs1_addr) begin
                    forward_a = FWD_WB;
                end
            end

            // Source register 2
            if (ex_rs2_used && ex_rs2_addr != 5'd0) begin

                if (exmem_valid && exmem_reg_write &&
                    exmem_rd_addr != 5'd0 &&
                    exmem_rd_addr == ex_rs2_addr) begin

                    if (exmem_result_ready)
                        forward_b = FWD_MEM;
                    else
                        wait_b = 1'b1;

                end
                else if (memwb_valid && memwb_reg_write &&
                         memwb_rd_addr != 5'd0 &&
                         memwb_rd_addr == ex_rs2_addr) begin
                    forward_b = FWD_WB;
                end
            end

        end
    end

endmodule
