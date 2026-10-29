`timescale 1ns / 1ps
// Stage-1 arithmetic-only 5-stage pipeline integration.
// Uses the official decoder/regfile/imm_gen/alu and all four official pipeline registers.
// Input is an externally supplied instruction stream (NOT an I-cache/IMEM port).
// NO hazard handling, branch execution, DMEM, or backpressure in this version.
// If unsupported instructions arrive they become bubbles and id_unsupported pulses.
// If RAW hazards arrive, id_raw_hazard is diagnostic ONLY; the caller must avoid them.
// This is a simulation/integration stepping stone, not a completed CPU.
module pipeline_cpu_core_v01 (
    input  wire        clk,
    input  wire        rst,
    input  wire        if_valid,
    input  wire [31:0] if_pc,
    input  wire [31:0] if_inst,

    output wire        wb_commit_valid,
    output wire [31:0] wb_commit_pc,
    output wire [4:0]  wb_commit_rd,
    output wire [31:0] wb_commit_data,

    output wire        id_unsupported,
    output wire        id_raw_hazard
);
    // IF / ID
    wire        id_valid;
    wire [31:0] id_pc, id_inst;
    if_id_reg u_if_id (
        .clk(clk), .rst(rst), .stall(1'b0), .flush(1'b0),
        .if_valid(if_valid), .if_pc(if_pc), .if_inst(if_inst),
        .id_valid(id_valid), .id_pc(id_pc), .id_inst(id_inst)
    );

    // ID decode and register-file read
    wire [4:0] d_rs1_addr, d_rs2_addr, d_rd_addr;
    wire d_rs1_used, d_rs2_used;
    wire [3:0] d_alu_op;
    wire [2:0] d_imm_sel, d_branch_type;
    wire d_alu_src_imm, d_reg_write, d_mem_read, d_mem_write;
    wire d_valid, d_wb_sel_mem;
    wire [1:0] d_wb_sel;
    wire [31:0] d_imm, d_rs1_data, d_rs2_data;

    decoder u_decoder (
        .inst(id_inst), .rs1_addr(d_rs1_addr), .rs2_addr(d_rs2_addr),
        .rd_addr(d_rd_addr), .rs1_used(d_rs1_used), .rs2_used(d_rs2_used),
        .alu_op(d_alu_op), .imm_sel(d_imm_sel), .alu_src_imm(d_alu_src_imm),
        .reg_write(d_reg_write), .mem_read(d_mem_read), .mem_write(d_mem_write),
        .wb_sel_mem(d_wb_sel_mem), .valid(d_valid),
        .branch_type(d_branch_type), .wb_sel(d_wb_sel)
    );

    imm_gen u_imm_gen (.inst(id_inst), .imm_sel(d_imm_sel), .imm(d_imm));

    wire        wb_valid, wb_reg_write, wb_write_en;
    wire [31:0] wb_pc, wb_data;
    wire [4:0]  wb_rd_addr;
    regfile u_regfile (
        .clk(clk), .rst(rst), .raddr1(d_rs1_addr), .raddr2(d_rs2_addr),
        .rdata1(d_rs1_data), .rdata2(d_rs2_data),
        .we(wb_write_en), .waddr(wb_rd_addr), .wdata(wb_data)
    );

    // This version intentionally accepts arithmetic instructions only.
    // The full decoder remains unchanged; unsupported operations are visible bubbles.
    wire arithmetic_supported = d_valid && d_reg_write &&
                                !d_mem_read && !d_mem_write &&
                                (d_branch_type == 3'd0) &&
                                (d_wb_sel == 2'b00);
    wire id_accept = id_valid && arithmetic_supported;
    assign id_unsupported = id_valid && !arithmetic_supported;

    // ID / EX
    wire ex_valid, ex_rs1_used, ex_rs2_used;
    wire ex_alu_src_imm, ex_reg_write, ex_mem_read, ex_mem_write;
    wire [31:0] ex_pc, ex_pc_plus4, ex_inst, ex_rs1_data, ex_rs2_data, ex_imm;
    wire [4:0] ex_rs1_addr, ex_rs2_addr, ex_rd_addr;
    wire [3:0] ex_alu_op;
    wire [2:0] ex_branch_type;
    wire [1:0] ex_wb_sel;

    id_ex_reg u_id_ex (
        .clk(clk), .rst(rst), .stall(1'b0), .flush(1'b0),
        .id_valid(id_accept), .id_pc(id_pc), .id_pc_plus4(id_pc + 32'd4),
        .id_inst(id_inst), .id_rs1_addr(d_rs1_addr), .id_rs2_addr(d_rs2_addr),
        .id_rd_addr(d_rd_addr), .id_rs1_data(d_rs1_data), .id_rs2_data(d_rs2_data),
        .id_rs1_used(d_rs1_used), .id_rs2_used(d_rs2_used),
        .id_imm(d_imm), .id_alu_op(d_alu_op), .id_alu_src_imm(d_alu_src_imm),
        .id_branch_type(d_branch_type), .id_wb_sel(d_wb_sel),
        .id_reg_write(d_reg_write && id_accept),
        .id_mem_read(1'b0), .id_mem_write(1'b0),
        .ex_valid(ex_valid), .ex_pc(ex_pc), .ex_pc_plus4(ex_pc_plus4),
        .ex_inst(ex_inst), .ex_rs1_addr(ex_rs1_addr), .ex_rs2_addr(ex_rs2_addr),
        .ex_rd_addr(ex_rd_addr), .ex_rs1_data(ex_rs1_data), .ex_rs2_data(ex_rs2_data),
        .ex_rs1_used(ex_rs1_used), .ex_rs2_used(ex_rs2_used),
        .ex_imm(ex_imm), .ex_alu_op(ex_alu_op), .ex_alu_src_imm(ex_alu_src_imm),
        .ex_branch_type(ex_branch_type), .ex_wb_sel(ex_wb_sel),
        .ex_reg_write(ex_reg_write), .ex_mem_read(ex_mem_read),
        .ex_mem_write(ex_mem_write)
    );

    // EX: intentionally no forwarding yet.
    wire [31:0] ex_alu_result;
    wire [31:0] ex_operand_b = ex_alu_src_imm ? ex_imm : ex_rs2_data;
    alu u_alu (
        .a(ex_rs1_data), .b(ex_operand_b), .alu_op(ex_alu_op),
        .result(ex_alu_result)
    );

    // EX / MEM
    wire mem_valid, mem_mem_read, mem_mem_write, mem_reg_write;
    wire [31:0] mem_pc, mem_pc_plus4, mem_alu_result, mem_store_data;
    wire [4:0] mem_store_src_addr, mem_rd_addr;
    wire [1:0] mem_wb_sel;
    ex_mem_reg u_ex_mem (
        .clk(clk), .rst(rst), .stall(1'b0), .flush(1'b0),
        .ex_valid(ex_valid), .ex_pc(ex_pc), .ex_pc_plus4(ex_pc_plus4),
        .ex_alu_result(ex_alu_result), .ex_store_data(ex_rs2_data),
        .ex_store_src_addr(ex_rs2_addr), .ex_rd_addr(ex_rd_addr),
        .ex_mem_read(ex_mem_read), .ex_mem_write(ex_mem_write),
        .ex_reg_write(ex_reg_write), .ex_wb_sel(ex_wb_sel),
        .mem_valid(mem_valid), .mem_pc(mem_pc), .mem_pc_plus4(mem_pc_plus4),
        .mem_alu_result(mem_alu_result), .mem_store_data(mem_store_data),
        .mem_store_src_addr(mem_store_src_addr), .mem_rd_addr(mem_rd_addr),
        .mem_mem_read(mem_mem_read), .mem_mem_write(mem_mem_write),
        .mem_reg_write(mem_reg_write), .mem_wb_sel(mem_wb_sel)
    );

    // MEM: arithmetic results simply pass through this stage.
    // No DMEM is used, and therefore no memory side effect is possible.
    wire [31:0] mem_selected_wb_data = mem_alu_result;
    mem_wb_reg u_mem_wb (
        .clk(clk), .rst(rst), .stall(1'b0), .flush(1'b0),
        .mem_valid(mem_valid), .mem_pc(mem_pc),
        .mem_wb_data(mem_selected_wb_data), .mem_rd_addr(mem_rd_addr),
        .mem_reg_write(mem_reg_write),
        .wb_valid(wb_valid), .wb_pc(wb_pc), .wb_data(wb_data),
        .wb_rd_addr(wb_rd_addr), .wb_reg_write(wb_reg_write),
        .wb_write_en(wb_write_en)
    );

    // A level signal is safe as a commit qualifier in this never-stalled V0.1.
    // A future backpressured design requires per-instruction commit acceptance.
    assign wb_commit_valid = wb_write_en && !rst;
    assign wb_commit_pc    = wb_pc;
    assign wb_commit_rd    = wb_rd_addr;
    assign wb_commit_data  = wb_data;

    // Diagnostic only: currently NO hazard resolution. In this implementation,
    // register-file writes occur at the edge, so even a WB-stage match is unsafe
    // for the ID/EX capture at that same edge.
    wire ex_pending = ex_valid && ex_reg_write && (ex_rd_addr != 5'd0);
    wire mem_pending = mem_valid && mem_reg_write && (mem_rd_addr != 5'd0);
    wire wb_pending = wb_valid && wb_reg_write && (wb_rd_addr != 5'd0);
    wire raw_rs1 = d_rs1_used && (d_rs1_addr != 5'd0) &&
                   ((ex_pending  && d_rs1_addr == ex_rd_addr) ||
                    (mem_pending && d_rs1_addr == mem_rd_addr) ||
                    (wb_pending  && d_rs1_addr == wb_rd_addr));
    wire raw_rs2 = d_rs2_used && (d_rs2_addr != 5'd0) &&
                   ((ex_pending  && d_rs2_addr == ex_rd_addr) ||
                    (mem_pending && d_rs2_addr == mem_rd_addr) ||
                    (wb_pending  && d_rs2_addr == wb_rd_addr));
    assign id_raw_hazard = id_accept && (raw_rs1 || raw_rs2);
endmodule
