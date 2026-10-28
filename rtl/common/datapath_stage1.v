// LoongArch-Pipeline-CPU / Stage-1 single-cycle integration harness
// Verilog-2001, intended for Vivado 2019.1 functional simulation.
//
// This module is NOT the final CPU top or a pipelined datapath.
// It connects the existing decoder, teammate A's regfile and ALU,
// teammate B's immediate generator and data memory.
//
// IMPORTANT: the register-file interface must be agreed with teammate A.
// The instruction is supplied externally; instruction fetch and PC are future work.
module datapath_stage1 (
    input  wire        clk,
    input  wire        rst,
    input  wire        exec_en,
    input  wire [31:0] inst,

    output wire        dbg_valid,
    output wire [4:0]  dbg_rs1_addr,
    output wire [4:0]  dbg_rs2_addr,
    output wire [4:0]  dbg_rd_addr,
    output wire [31:0] dbg_rs1_data,
    output wire [31:0] dbg_rs2_data,
    output wire [31:0] dbg_imm,
    output wire [31:0] dbg_alu_result,
    output wire [31:0] dbg_wb_data,
    output wire [31:0] dbg_mem_rdata,
    output wire [3:0]  dbg_alu_op,
    output wire [2:0]  dbg_imm_sel,
    output wire        dbg_reg_we,
    output wire        dbg_mem_we,
    output wire        dbg_mem_read
);
    wire [4:0] rs1_addr, rs2_addr, rd_addr;
    wire rs1_used, rs2_used;
    wire [3:0] alu_op;
    wire [2:0] imm_sel;
    wire alu_src_imm, reg_write, mem_read, mem_write, wb_sel_mem, valid;
    wire [31:0] rdata1, rdata2, imm, alu_b, alu_result, mem_rdata, wb_data;
    wire rf_we, dm_we;

    decoder u_decoder (
        .inst(inst),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .rd_addr(rd_addr),
        .rs1_used(rs1_used), .rs2_used(rs2_used),
        .alu_op(alu_op), .imm_sel(imm_sel), .alu_src_imm(alu_src_imm),
        .reg_write(reg_write), .mem_read(mem_read), .mem_write(mem_write),
        .wb_sel_mem(wb_sel_mem), .valid(valid)
    );

    regfile u_regfile (
        .clk(clk), .rst(rst),
        .raddr1(rs1_addr), .raddr2(rs2_addr),
        .rdata1(rdata1), .rdata2(rdata2),
        .we(rf_we), .waddr(rd_addr), .wdata(wb_data)
    );

    imm_gen u_imm_gen (.inst(inst), .imm_sel(imm_sel), .imm(imm));

    assign alu_b = alu_src_imm ? imm : rdata2;
    alu u_alu (.a(rdata1), .b(alu_b), .alu_op(alu_op), .result(alu_result));

    // Current dmem has asynchronous word reads and posedge writes.
    dmem u_dmem (
        .clk(clk), .we(dm_we), .addr(alu_result),
        .wdata(rdata2), .rdata(mem_rdata)
    );

    assign wb_data = wb_sel_mem ? mem_rdata : alu_result;
    assign rf_we = exec_en && !rst && valid && reg_write && (rd_addr != 5'd0);
    assign dm_we = exec_en && !rst && valid && mem_write;

    assign dbg_valid      = valid;
    assign dbg_rs1_addr   = rs1_addr;
    assign dbg_rs2_addr   = rs2_addr;
    assign dbg_rd_addr    = rd_addr;
    assign dbg_rs1_data   = rdata1;
    assign dbg_rs2_data   = rdata2;
    assign dbg_imm        = imm;
    assign dbg_alu_result = alu_result;
    assign dbg_wb_data    = wb_data;
    assign dbg_mem_rdata  = mem_rdata;
    assign dbg_alu_op     = alu_op;
    assign dbg_imm_sel    = imm_sel;
    assign dbg_reg_we     = rf_we;
    assign dbg_mem_we     = dm_we;
    assign dbg_mem_read   = mem_read;
endmodule
