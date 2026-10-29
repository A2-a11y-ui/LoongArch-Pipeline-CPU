`timescale 1ns / 1ps
// V0.3 five-stage LoongArch integration: ALU forwarding + single-cycle LD.W/ST.W.
// The V0.1 and V0.2 cores are UNCHANGED.
// Actual official registers, decoder, regfile, ALU, forwarding_unit,
// load_use_hazard_unit and dmem are instantiated below.
// External IF is a READY/VALID stream: IF inputs are accepted ONLY at a
// rising edge where if_valid && if_ready. Hold them during !if_ready.
// Load-use: hold IF/ID, insert bubble into ID/EX; old EX load advances to MEM.
// This test-only version has no redirect, cache, bus latency, or downstream
// backpressure; DMEM has combinational read and synchronous write (1 KiB).
// ALIGNED and in-range memory accesses ONLY; no exceptions are implemented.
module pipeline_cpu_core_v03 (
    input  wire        clk,
    input  wire        rst,
    input  wire        if_valid,
    input  wire [31:0] if_pc,
    input  wire [31:0] if_inst,
    output wire        if_ready,

    output wire        wb_commit_valid,
    output wire [31:0] wb_commit_pc,
    output wire [4:0]  wb_commit_rd,
    output wire [31:0] wb_commit_data,

    output wire        mem_store_commit_valid,
    output wire [31:0] mem_store_commit_pc,
    output wire [31:0] mem_store_commit_addr,
    output wire [31:0] mem_store_commit_data,

    output wire        load_use_stall,
    output wire        id_unsupported,
    output wire        id_raw_hazard
);
    // IF / ID
    wire        id_valid;
    wire [31:0] id_pc, id_inst;
    // The upstream IF producer MUST retry the same instruction during a stall.
    wire hold_if_req, hold_ifid_req, bubble_idex_req;
    assign if_ready = !rst && !hold_if_req;
    assign load_use_stall = hold_ifid_req;

    if_id_reg u_if_id (
        .clk(clk), .rst(rst), .stall(hold_ifid_req), .flush(1'b0),
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
    wire [31:0] rf_rs1_data, rf_rs2_data;

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
        .rdata1(rf_rs1_data), .rdata2(rf_rs2_data),
        .we(wb_write_en), .waddr(wb_rd_addr), .wdata(wb_data)
    );

    // Same-edge WB -> ID bypass (write-first behavior at the ID/EX capture edge).
    // The official regfile writes synchronously, and ID/EX captures on the SAME edge.
    // Without this bypass, a producer 3 instruction slots earlier may be stale.
    wire id_rs1_wb_bypass_hit = id_valid && d_rs1_used &&
                                (d_rs1_addr != 5'd0) && wb_write_en &&
                                (d_rs1_addr == wb_rd_addr);
    wire id_rs2_wb_bypass_hit = id_valid && d_rs2_used &&
                                (d_rs2_addr != 5'd0) && wb_write_en &&
                                (d_rs2_addr == wb_rd_addr);
    assign d_rs1_data = id_rs1_wb_bypass_hit ? wb_data : rf_rs1_data;
    assign d_rs2_data = id_rs2_wb_bypass_hit ? wb_data : rf_rs2_data;

    // Arithmetic and LD.W/ST.W only. Branch and illegal encodings are bubbles.
    wire supported_instruction = d_valid && (d_branch_type == 3'd0) &&
          ((d_mem_read && !d_mem_write && d_reg_write && d_wb_sel==2'b01) ||
           (d_mem_write && !d_mem_read && !d_reg_write) ||
           (!d_mem_read && !d_mem_write && d_reg_write && d_wb_sel==2'b00));
    wire id_accept = id_valid && supported_instruction;
    assign id_unsupported = id_valid && !supported_instruction;


    // ID / EX
    wire ex_valid, ex_rs1_used, ex_rs2_used;
    wire ex_alu_src_imm, ex_reg_write, ex_mem_read, ex_mem_write;
    wire [31:0] ex_pc, ex_pc_plus4, ex_inst, ex_rs1_data, ex_rs2_data, ex_imm;
    wire [4:0] ex_rs1_addr, ex_rs2_addr, ex_rd_addr;
    wire [3:0] ex_alu_op;
    wire [2:0] ex_branch_type;
    wire [1:0] ex_wb_sel;

    // RAW against a load in EX: the younger ID instruction must wait one
    // cycle, while the older EX load continues advancing into EX/MEM.
    wire raw_load_use;
    load_use_hazard_unit u_load_use (
        .id_valid(id_accept),
        .id_rs1_addr(d_rs1_addr), .id_rs2_addr(d_rs2_addr),
        .id_rs1_used(d_rs1_used), .id_rs2_used(d_rs2_used),
        .ex_valid(ex_valid), .ex_mem_read(ex_mem_read), .ex_rd_addr(ex_rd_addr),
        .load_use_hazard(raw_load_use),
        .hold_if_req(hold_if_req), .hold_ifid_req(hold_ifid_req),
        .bubble_idex_req(bubble_idex_req)
    );

    id_ex_reg u_id_ex (
        .clk(clk), .rst(rst), .stall(1'b0), .flush(bubble_idex_req),
        .id_valid(id_accept), .id_pc(id_pc), .id_pc_plus4(id_pc + 32'd4),
        .id_inst(id_inst), .id_rs1_addr(d_rs1_addr), .id_rs2_addr(d_rs2_addr),
        .id_rd_addr(d_rd_addr), .id_rs1_data(d_rs1_data), .id_rs2_data(d_rs2_data),
        .id_rs1_used(d_rs1_used), .id_rs2_used(d_rs2_used),
        .id_imm(d_imm), .id_alu_op(d_alu_op), .id_alu_src_imm(d_alu_src_imm),
        .id_branch_type(d_branch_type), .id_wb_sel(d_wb_sel),
        .id_reg_write(d_reg_write && id_accept),
        .id_mem_read(d_mem_read && id_accept),
        .id_mem_write(d_mem_write && id_accept),
        .ex_valid(ex_valid), .ex_pc(ex_pc), .ex_pc_plus4(ex_pc_plus4),
        .ex_inst(ex_inst), .ex_rs1_addr(ex_rs1_addr), .ex_rs2_addr(ex_rs2_addr),
        .ex_rd_addr(ex_rd_addr), .ex_rs1_data(ex_rs1_data), .ex_rs2_data(ex_rs2_data),
        .ex_rs1_used(ex_rs1_used), .ex_rs2_used(ex_rs2_used),
        .ex_imm(ex_imm), .ex_alu_op(ex_alu_op), .ex_alu_src_imm(ex_alu_src_imm),
        .ex_branch_type(ex_branch_type), .ex_wb_sel(ex_wb_sel),
        .ex_reg_write(ex_reg_write), .ex_mem_read(ex_mem_read),
        .ex_mem_write(ex_mem_write)
    );

    // EX / MEM stage state used by the forwarding network.
    wire mem_valid, mem_mem_read, mem_mem_write, mem_reg_write;
    wire [31:0] mem_pc, mem_pc_plus4, mem_alu_result, mem_store_data;
    wire [4:0] mem_store_src_addr, mem_rd_addr;
    wire [1:0] mem_wb_sel;

    // EX forwarding: EX/MEM (newer) > MEM/WB (older) > ID/EX saved value.
    // Loads in EX/MEM cannot forward from ALU address; their values become
    // available in MEM/WB after the one-cycle load-use bubble.
    // Forwarded B is ALSO the ST.W payload (not the ALU immediate operand).
    wire [1:0] forward_a, forward_b;
    wire wait_a, wait_b;
    wire exmem_result_ready = mem_valid && !mem_mem_read &&
                              (mem_wb_sel == 2'b00);
    forwarding_unit u_forwarding (
        .ex_valid(ex_valid), .ex_rs1_addr(ex_rs1_addr),
        .ex_rs2_addr(ex_rs2_addr), .ex_rs1_used(ex_rs1_used),
        .ex_rs2_used(ex_rs2_used),
        .exmem_valid(mem_valid), .exmem_reg_write(mem_reg_write),
        .exmem_rd_addr(mem_rd_addr),
        .exmem_result_ready(exmem_result_ready),
        .memwb_valid(wb_valid), .memwb_reg_write(wb_reg_write),
        .memwb_rd_addr(wb_rd_addr),
        .forward_a(forward_a), .forward_b(forward_b),
        .wait_a(wait_a), .wait_b(wait_b)
    );

    wire [31:0] ex_forwarded_a = (forward_a == 2'b10) ? mem_alu_result :
                                 (forward_a == 2'b01) ? wb_data : ex_rs1_data;
    wire [31:0] ex_forwarded_b = (forward_b == 2'b10) ? mem_alu_result :
                                 (forward_b == 2'b01) ? wb_data : ex_rs2_data;
    // Keep forwarding B available for a future store-data path, even when
    // the current arithmetic instruction takes its ALU B from an immediate.
    wire [31:0] ex_operand_b = ex_alu_src_imm ? ex_imm : ex_forwarded_b;
    wire [31:0] ex_alu_result;
    alu u_alu (
        .a(ex_forwarded_a), .b(ex_operand_b), .alu_op(ex_alu_op),
        .result(ex_alu_result)
    );

    // EX / MEM
    ex_mem_reg u_ex_mem (
        .clk(clk), .rst(rst), .stall(1'b0), .flush(1'b0),
        .ex_valid(ex_valid), .ex_pc(ex_pc), .ex_pc_plus4(ex_pc_plus4),
        .ex_alu_result(ex_alu_result), .ex_store_data(ex_forwarded_b),
        .ex_store_src_addr(ex_rs2_addr), .ex_rd_addr(ex_rd_addr),
        .ex_mem_read(ex_mem_read), .ex_mem_write(ex_mem_write),
        .ex_reg_write(ex_reg_write), .ex_wb_sel(ex_wb_sel),
        .mem_valid(mem_valid), .mem_pc(mem_pc), .mem_pc_plus4(mem_pc_plus4),
        .mem_alu_result(mem_alu_result), .mem_store_data(mem_store_data),
        .mem_store_src_addr(mem_store_src_addr), .mem_rd_addr(mem_rd_addr),
        .mem_mem_read(mem_mem_read), .mem_mem_write(mem_mem_write),
        .mem_reg_write(mem_reg_write), .mem_wb_sel(mem_wb_sel)
    );

    // Single-cycle data memory (official module): synchronous ST.W and
    // combinational LD.W. Every memory side effect requires mem_valid.
    // No MEM stall is asserted: every EX/MEM entry is consumed once per cycle.
    wire [31:0] dmem_rdata;
    wire dmem_we = mem_valid && mem_mem_write && !rst;
    dmem u_dmem (
        .clk(clk), .we(dmem_we), .addr(mem_alu_result),
        .wdata(mem_store_data), .rdata(dmem_rdata)
    );
    // WB_SEL: 00 ALU, 01 MEM, 10 PC+4; this version rejects branches.
    reg [31:0] mem_selected_wb_data;
    always @(*) begin
        case (mem_wb_sel)
            2'b00: mem_selected_wb_data = mem_alu_result;
            2'b01: mem_selected_wb_data = dmem_rdata;
            2'b10: mem_selected_wb_data = mem_pc_plus4;
            default: mem_selected_wb_data = 32'd0;
        endcase
    end
    // A store has no register writeback; expose its accepted MEM transaction
    // for a black-box checker instead of relying on hierarchical DMEM pokes.
    assign mem_store_commit_valid = dmem_we;
    assign mem_store_commit_pc    = mem_pc;
    assign mem_store_commit_addr  = mem_alu_result;
    assign mem_store_commit_data  = mem_store_data;
    mem_wb_reg u_mem_wb (
        .clk(clk), .rst(rst), .stall(1'b0), .flush(1'b0),
        .mem_valid(mem_valid), .mem_pc(mem_pc),
        .mem_wb_data(mem_selected_wb_data), .mem_rd_addr(mem_rd_addr),
        .mem_reg_write(mem_reg_write),
        .wb_valid(wb_valid), .wb_pc(wb_pc), .wb_data(wb_data),
        .wb_rd_addr(wb_rd_addr), .wb_reg_write(wb_reg_write),
        .wb_write_en(wb_write_en)
    );

    // WB never stalls in this bounded, single-cycle memory test core.
    // In a future backpressured core, a per-instruction consume/commit handshake
    // is required to prevent duplicate architectural retirement.
    assign wb_commit_valid = wb_write_en && !rst;
    assign wb_commit_pc    = wb_pc;
    assign wb_commit_rd    = wb_rd_addr;
    assign wb_commit_data  = wb_data;

    // RAW diagnostic: may be high even when forwarding solves the dependence.
    // load_use_stall is the actual one-cycle interlock request.
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
