// Stage 5 single-cycle *functional integration harness*, not pipelined CPU.
// Uses official shared modules: pc_reg, imem, decoder (13 ops), regfile,
// imm_gen V2, alu, dmem and teammate A's branch_unit.
// Branch handling is temporarily provided by branch_decode_stage5;
// DO NOT overwrite the shared decoder.v until both teammates approve.
module branch_cpu_stage5 (
    input  wire        clk,
    input  wire        rst,
    input  wire        step_en,
    output wire [31:0] pc,
    output wire [31:0] inst,
    output wire        fetch_addr_valid,
    output wire        instr_valid,
    output wire [2:0]  dbg_branch_type,
    output wire [31:0] dbg_branch_imm,
    output wire        dbg_redirect,
    output wire [31:0] dbg_target_pc,
    output wire [31:0] dbg_next_pc,
    output wire        dbg_reg_we,
    output wire        dbg_mem_we,
    output wire [4:0]  dbg_waddr,
    output wire [31:0] dbg_wb_data,
    output wire [31:0] dbg_rs1_data,
    output wire [31:0] dbg_rs2_data
);
    // Old 13-instruction decoder (unchanged).
    wire [4:0] base_rs1, base_rs2, base_rd;
    wire base_rs1_used, base_rs2_used;
    wire [3:0] base_alu_op;
    wire [2:0] base_imm_sel;
    wire base_alu_src_imm, base_reg_write, base_mem_read;
    wire base_mem_write, base_wb_sel_mem, base_valid;

    // New temporary five-branch decoder.
    wire branch_valid;
    wire [2:0] branch_type, branch_imm_sel;
    wire [4:0] branch_rs1, branch_rs2, branch_link_rd;
    wire branch_link_write;

    wire [4:0] rs1_addr, rs2_addr, waddr;
    wire [2:0] selected_imm_sel;
    wire [31:0] rs1_data, rs2_data, imm, alu_b, alu_result;
    wire [31:0] mem_rdata, wb_data, next_pc;
    wire branch_redirect;
    wire [31:0] branch_target_pc;
    wire rf_we, dm_we, exec_valid;

    imem u_imem (
        .addr(pc), .inst(inst), .addr_valid(fetch_addr_valid)
    );

    decoder u_decoder (
        .inst(inst),
        .rs1_addr(base_rs1), .rs2_addr(base_rs2), .rd_addr(base_rd),
        .rs1_used(base_rs1_used), .rs2_used(base_rs2_used),
        .alu_op(base_alu_op), .imm_sel(base_imm_sel),
        .alu_src_imm(base_alu_src_imm),
        .reg_write(base_reg_write), .mem_read(base_mem_read),
        .mem_write(base_mem_write), .wb_sel_mem(base_wb_sel_mem),
        .valid(base_valid)
    );

    branch_decode_stage5 u_branch_decoder (
        .inst(inst), .branch_valid(branch_valid),
        .branch_type(branch_type), .imm_sel(branch_imm_sel),
        .rs1_addr(branch_rs1), .rs2_addr(branch_rs2),
        .link_rd(branch_link_rd), .link_write(branch_link_write)
    );

    assign rs1_addr = branch_valid ? branch_rs1 : base_rs1;
    assign rs2_addr = branch_valid ? branch_rs2 : base_rs2;
    assign waddr = branch_valid ? branch_link_rd : base_rd;
    assign selected_imm_sel = branch_valid ? branch_imm_sel : base_imm_sel;

    regfile u_regfile (
        .clk(clk), .rst(rst),
        .raddr1(rs1_addr), .raddr2(rs2_addr),
        .rdata1(rs1_data), .rdata2(rs2_data),
        .we(rf_we), .waddr(waddr), .wdata(wb_data)
    );

    imm_gen u_imm_gen (
        .inst(inst), .imm_sel(selected_imm_sel), .imm(imm)
    );

    assign alu_b = base_alu_src_imm ? imm : rs2_data;
    alu u_alu (
        .a(rs1_data), .b(alu_b),
        .alu_op(base_alu_op), .result(alu_result)
    );

    dmem u_dmem (
        .clk(clk), .we(dm_we),
        .addr(alu_result), .wdata(rs2_data), .rdata(mem_rdata)
    );

    branch_unit u_branch_unit (
        .branch_type(fetch_addr_valid && branch_valid ? branch_type : 3'd0),
        .pc(pc), .rs1_data(rs1_data), .rs2_data(rs2_data),
        .branch_imm(imm),
        .redirect(branch_redirect), .target_pc(branch_target_pc)
    );

    // PC and architectural state advance only when step_en is asserted.
    // Redirect is resolved combinationally in this single-cycle model.
    assign next_pc = branch_redirect ? branch_target_pc : (pc + 32'd4);
    pc_reg u_pc (
        .clk(clk), .rst(rst), .pc_en(step_en),
        .next_pc(next_pc), .pc(pc)
    );

    assign instr_valid = fetch_addr_valid && (base_valid || branch_valid);
    assign exec_valid = step_en && !rst && fetch_addr_valid;
    assign rf_we = exec_valid && (branch_valid ? branch_link_write : (base_valid && base_reg_write))
                  && (waddr != 5'd0);
    assign dm_we = exec_valid && !branch_valid && base_valid && base_mem_write;
    // Separate writeback paths for ALU result, memory load, and PC+4 link.
    assign wb_data = branch_valid ? (pc + 32'd4) :
                     (base_wb_sel_mem ? mem_rdata : alu_result);

    assign dbg_branch_type = fetch_addr_valid && branch_valid ? branch_type : 3'd0;
    assign dbg_branch_imm = branch_valid ? imm : 32'd0;
    assign dbg_redirect = branch_redirect;
    assign dbg_target_pc = branch_target_pc;
    assign dbg_next_pc = next_pc;
    assign dbg_reg_we = rf_we;
    assign dbg_mem_we = dm_we;
    assign dbg_waddr = waddr;
    assign dbg_wb_data = wb_data;
    assign dbg_rs1_data = rs1_data;
    assign dbg_rs2_data = rs2_data;
endmodule
