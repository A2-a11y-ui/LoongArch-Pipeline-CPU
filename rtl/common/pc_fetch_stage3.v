// LoongArch-Pipeline-CPU, Stage 3: automatic PC + instruction fetch + datapath
// Verilog-2001 / Vivado 2019.1
// IMPORTANT: Uses teammate A's pc_reg. This is NOT the final CPU top or pipeline.
// This simple one-instruction-per-step harness can verify stall/redirect wiring.
module pc_fetch_stage3 (
    input  wire        clk,
    input  wire        rst,
    input  wire        step_en,
    input  wire        redirect,
    input  wire [31:0] redirect_pc,
    output wire [31:0] pc,
    output wire [31:0] inst,
    output wire        fetch_addr_valid,
    output wire        instr_valid,
    output wire        dbg_reg_we,
    output wire        dbg_mem_we,
    output wire [31:0] dbg_wb_data,
    output wire [31:0] dbg_alu_result
);
    wire [31:0] next_pc;
    wire        exec_en;

    // A bubble on redirect avoids executing the instruction at the old PC.
    // No update on step_en=0; prevents repeating writes while PC is held.
    assign next_pc = redirect ? redirect_pc : (pc + 32'd4);
    assign exec_en = step_en && !redirect;

    pc_reg u_pc (
        .clk(clk), .rst(rst), .pc_en(step_en),
        .next_pc(next_pc), .pc(pc)
    );

    fetch_datapath_stage2 u_fetch (
        .clk(clk), .rst(rst), .exec_en(exec_en), .pc(pc),
        .inst(inst), .fetch_addr_valid(fetch_addr_valid),
        .instr_valid(instr_valid),
        .dbg_reg_we(dbg_reg_we), .dbg_mem_we(dbg_mem_we),
        .dbg_wb_data(dbg_wb_data), .dbg_alu_result(dbg_alu_result),
        .dbg_rs1_data(), .dbg_rs2_data()
    );
endmodule
