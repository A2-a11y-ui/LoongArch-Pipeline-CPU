// Formal single-cycle CPU integration entry (baseline, 18 instructions).
// Derived from the cpu_top_candidate validated with 397 checks.
// The shared Decoder V1.2 extension is not merged yet: instantiate the validated
// decoder_v2 until both contributors approve the final decoder.v interface.
// NOT a five-stage pipeline. No hazards/Cache implemented in this version.
module cpu_top_arith_test #(
    parameter IMEM_INIT_FILE = ""  // optional $readmemh machine code image
) (
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
    // One unified 18-instruction decoder.
    wire [4:0] rs1_addr, rs2_addr, waddr;
    wire rs1_used, rs2_used;
    wire [3:0] alu_op;
    wire [2:0] selected_imm_sel, branch_type;
    wire [1:0] wb_sel;
    wire alu_src_imm, reg_write, mem_read, mem_write, base_valid;
    wire wb_sel_mem;
    wire [31:0] rs1_data, rs2_data, imm, alu_b, alu_result;
    wire [31:0] mem_rdata, wb_data, next_pc;
    wire branch_redirect;
    wire [31:0] branch_target_pc;
    wire rf_we, dm_we, exec_valid;

    imem #(.INIT_FILE(IMEM_INIT_FILE)) u_imem (
        .addr(pc), .inst(inst), .addr_valid(fetch_addr_valid)
    );

    decoder u_decoder (
        .inst(inst), .rs1_addr(rs1_addr), .rs2_addr(rs2_addr),
        .rd_addr(waddr), .rs1_used(rs1_used), .rs2_used(rs2_used),
        .alu_op(alu_op), .imm_sel(selected_imm_sel),
        .alu_src_imm(alu_src_imm), .reg_write(reg_write),
        .mem_read(mem_read), .mem_write(mem_write),
        .wb_sel_mem(wb_sel_mem), .valid(base_valid),
        .branch_type(branch_type), .wb_sel(wb_sel)
    );

    regfile u_regfile (
        .clk(clk), .rst(rst),
        .raddr1(rs1_addr), .raddr2(rs2_addr),
        .rdata1(rs1_data), .rdata2(rs2_data),
        .we(rf_we), .waddr(waddr), .wdata(wb_data)
    );

    imm_gen u_imm_gen (
        .inst(inst), .imm_sel(selected_imm_sel), .imm(imm)
    );

    assign alu_b = alu_src_imm ? imm : rs2_data;
    alu u_alu (
        .a(rs1_data), .b(alu_b),
        .alu_op(alu_op), .result(alu_result)
    );

    dmem u_dmem (
        .clk(clk), .we(dm_we),
        .addr(alu_result), .wdata(rs2_data), .rdata(mem_rdata)
    );

    branch_unit u_branch_unit (
        .branch_type(fetch_addr_valid && base_valid ? branch_type : 3'd0),
        .pc(pc), .rs1_data(rs1_data), .rs2_data(rs2_data),
        .branch_imm(imm),
        .redirect(branch_redirect), .target_pc(branch_target_pc)
    );

    // PC and architectural state advance only when step_en is asserted.
    // This simple baseline advances past unsupported/out-of-range instructions.
    // Halt/trap logic and FPGA I/O wrapper are separate future tasks.
    // Redirect is resolved combinationally in this single-cycle model.
    assign next_pc = branch_redirect ? branch_target_pc : (pc + 32'd4);
    pc_reg u_pc (
        .clk(clk), .rst(rst), .pc_en(step_en),
        .next_pc(next_pc), .pc(pc)
    );

    assign instr_valid = fetch_addr_valid && base_valid;
    assign exec_valid = step_en && !rst && fetch_addr_valid;
    assign rf_we = exec_valid && base_valid && reg_write && (waddr != 5'd0);
    assign dm_we = exec_valid && base_valid && mem_write;
    // Separate writeback paths for ALU result, memory load, and PC+4 link.
    assign wb_data = (wb_sel == 2'b10) ? (pc + 32'd4) :
                     (wb_sel == 2'b01) ? mem_rdata : alu_result;

    assign dbg_branch_type = fetch_addr_valid && base_valid ? branch_type : 3'd0;
    assign dbg_branch_imm = (branch_type != 3'd0) ? imm : 32'd0;
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
