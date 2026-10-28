// LoongArch-Pipeline-CPU: fetch-to-datapath integration baseline (Stage 2)
// Verilog-2001, Vivado 2019.1
// NOTE: This is not a CPU top. 'pc' is supplied externally by the testbench.
// NOTE: The teammate's pc_reg.v will be connected after its PR is reviewed.
module fetch_datapath_stage2 (
    input  wire        clk,
    input  wire        rst,
    input  wire        exec_en,
    input  wire [31:0] pc,
    output wire [31:0] inst,
    output wire        fetch_addr_valid,
    output wire        instr_valid,
    output wire        dbg_reg_we,
    output wire        dbg_mem_we,
    output wire [31:0] dbg_wb_data,
    output wire [31:0] dbg_alu_result,
    output wire [31:0] dbg_rs1_data,
    output wire [31:0] dbg_rs2_data
);
    wire decode_valid;
    wire fetch_execute;

    imem u_imem (
        .addr(pc),
        .inst(inst),
        .addr_valid(fetch_addr_valid)
    );

    // Suppress architectural state changes on invalid fetch addresses.
    // datapath_stage1 already gates writes with exec_en and decoder.valid.
    assign fetch_execute = exec_en && fetch_addr_valid;
    assign instr_valid = fetch_addr_valid && decode_valid;

    datapath_stage1 u_datapath (
        .clk(clk),
        .rst(rst),
        .exec_en(fetch_execute),
        .inst(inst),
        .dbg_valid(decode_valid),
        .dbg_rs1_data(dbg_rs1_data),
        .dbg_rs2_data(dbg_rs2_data),
        .dbg_alu_result(dbg_alu_result),
        .dbg_wb_data(dbg_wb_data),
        .dbg_reg_we(dbg_reg_we),
        .dbg_mem_we(dbg_mem_we)
    );
endmodule
