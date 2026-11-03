`timescale 1ns / 1ps
// V0.8 MDU+multi-cycle DMEM datapath derived from V0.7 reference; leaves V0.7 untouched.
// No pre-existing official RTL module has been modified.
// Actual official registers, decoder, regfile, ALU, forwarding_unit,
// load_use_hazard_unit and dmem are instantiated below.
// External IF is a READY/VALID stream: IF inputs are accepted ONLY at a
// rising edge where if_valid && if_ready. Hold them during !if_ready.
// Load-use: hold IF/ID, insert bubble into ID/EX; old EX load advances to MEM.
// Redirect: resolved in EX, flush ONLY the younger IF/ID and ID/EX stages;
// the EX branch continues to EX/MEM. Branch redirect cancels the currently
// presented wrong-path IF word, which must NOT be retried. IF producer starts
// offering target PC on the next cycle. These are test-only streaming semantics
// (not an I-Cache request/response bus).
// This datapath has a multi-cycle, handshake-based DMEM; the independent
// V0.7 wrapper adds the official PC/IF and I-Cache subsystem.
// Aligned LD.W/ST.W supported; error responses are consumed and observed,
// but exception/trap handling remains out of scope for this version.
module pipeline_cpu_core_v08_mdu_datapath #(
    parameter integer DMEM_READ_LATENCY=4,
    parameter integer DMEM_WRITE_LATENCY=5,
    parameter integer DMEM_WORDS=256,
    parameter DMEM_INIT_FILE=""
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        if_valid,
    input  wire [31:0] if_pc,
    input  wire [31:0] if_inst,
    output wire        if_ready,
    output wire        branch_resolve_valid,
    output wire        branch_redirect,
    output wire [31:0] branch_redirect_pc,

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
    output wire        id_raw_hazard,
    output wire        mem_stall,
    output wire        dmem_req_fire,
    output wire        dmem_resp_fire,
    output wire        mem_fault_valid,
    output wire [31:0] mem_fault_pc,
    output wire [31:0] mem_fault_addr,
    output wire        mem_fault_store,
    output wire        mdu_start_fire,
    output wire        mdu_busy,
    output wire        mdu_done,
    output wire        mdu_result_fire,
    output wire        mdu_div_zero
);
    // IF / ID
    wire        id_valid;
    wire [31:0] id_pc, id_inst;
    // The upstream IF producer MUST retry the same instruction during a stall.
    wire hold_if_req, hold_ifid_req, bubble_idex_req;
    // Redirect has priority over any younger input. A redirected IF word is
    // canceled, not stalled for replay; see the documented source protocol.
    // Backpressure reaches the IF response acceptance boundary.
    // The fetch adapter retains an already-pending response until ready.
    wire front_stall, ex_operand_wait;
    assign if_ready = !rst && !front_stall && !hold_if_req && !branch_redirect;
    assign load_use_stall = hold_ifid_req;

    if_id_reg u_if_id (
        .clk(clk), .rst(rst), .stall(hold_ifid_req || front_stall), .flush(branch_redirect),
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

    // Stable decoder.v is unchanged.  Only this NEW datapath overlays
    // the six EX control/source fields and reg-write for MDU opcodes.
    wire [4:0] legacy_rs1_addr, legacy_rs2_addr, legacy_rd_addr;
    wire legacy_rs1_used, legacy_rs2_used;
    wire [3:0] legacy_alu_op;
    wire [2:0] legacy_imm_sel, legacy_branch_type;
    wire legacy_alu_src_imm, legacy_reg_write, legacy_mem_read, legacy_mem_write;
    wire legacy_valid;
    wire [1:0] legacy_wb_sel;
    wire id_is_mdu;
    wire [2:0] id_mdu_op;
    mdu_decode_v08 u_mdu_id_decode (
        .inst(id_inst), .is_mdu(id_is_mdu), .mdu_op(id_mdu_op)
    );
    decoder u_decoder (
        .inst(id_inst), .rs1_addr(legacy_rs1_addr), .rs2_addr(legacy_rs2_addr),
        .rd_addr(legacy_rd_addr), .rs1_used(legacy_rs1_used),
        .rs2_used(legacy_rs2_used), .alu_op(legacy_alu_op),
        .imm_sel(legacy_imm_sel), .alu_src_imm(legacy_alu_src_imm),
        .reg_write(legacy_reg_write), .mem_read(legacy_mem_read),
        .mem_write(legacy_mem_write), .wb_sel_mem(d_wb_sel_mem),
        .valid(legacy_valid), .branch_type(legacy_branch_type),
        .wb_sel(legacy_wb_sel)
    );
    assign d_rs1_addr    = id_is_mdu ? id_inst[9:5]   : legacy_rs1_addr;
    assign d_rs2_addr    = id_is_mdu ? id_inst[14:10] : legacy_rs2_addr;
    assign d_rd_addr     = id_is_mdu ? id_inst[4:0]  : legacy_rd_addr;
    assign d_rs1_used    = id_is_mdu ? 1'b1 : legacy_rs1_used;
    assign d_rs2_used    = id_is_mdu ? 1'b1 : legacy_rs2_used;
    assign d_alu_op      = id_is_mdu ? 4'd0 : legacy_alu_op;
    assign d_imm_sel     = id_is_mdu ? 3'd0 : legacy_imm_sel;
    assign d_branch_type = id_is_mdu ? 3'd0 : legacy_branch_type;
    assign d_alu_src_imm = id_is_mdu ? 1'b0 : legacy_alu_src_imm;
    assign d_reg_write   = id_is_mdu ? 1'b1 : legacy_reg_write;
    assign d_mem_read    = id_is_mdu ? 1'b0 : legacy_mem_read;
    assign d_mem_write   = id_is_mdu ? 1'b0 : legacy_mem_write;
    assign d_wb_sel      = id_is_mdu ? 2'b00 : legacy_wb_sel;
    assign d_valid       = id_is_mdu | legacy_valid;

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

    // Arithmetic, LD.W/ST.W and the five decoded branch types are supported.
    wire supported_instruction = d_valid &&
          ((d_branch_type != 3'd0 && d_branch_type <= 3'd5 &&
             !d_mem_read && !d_mem_write) ||
           (d_branch_type == 3'd0 &&
           ((d_mem_read && !d_mem_write && d_reg_write && d_wb_sel==2'b01) ||
            (d_mem_write && !d_mem_read && !d_reg_write) ||
            (!d_mem_read && !d_mem_write && d_reg_write && d_wb_sel==2'b00))));
    wire id_accept = id_valid && supported_instruction;
    // A wrong-path ID instruction must not be reported as a retired error.
    assign id_unsupported = id_valid && !front_stall && !branch_redirect && !supported_instruction;


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
        .clk(clk), .rst(rst), .stall(front_stall), .flush(branch_redirect || (bubble_idex_req && !front_stall)),
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
    // BL/JIRL produce PC+4, not their ALU address. Forward this newer link
    // value from EX/MEM exactly like an ALU result when available.
    wire exmem_result_ready = mem_valid && !mem_mem_read &&
                              ((mem_wb_sel == 2'b00) ||
                               (mem_wb_sel == 2'b10));
    wire [31:0] exmem_forward_data =
            (mem_wb_sel == 2'b10) ? mem_pc_plus4 : mem_alu_result;
    // An old WB may retire during the first stalled MEM cycle.  Save that
    // result until the held EX instruction can advance (otherwise ID/EX's
    // saved operand could be stale after MEM/WB is cleared).
    reg shadow_wb_valid;
    reg [4:0] shadow_wb_rd;
    reg [31:0] shadow_wb_data;
    always @(posedge clk) begin
        if (rst) begin
            shadow_wb_valid <= 1'b0;
            shadow_wb_rd    <= 5'd0;
            shadow_wb_data  <= 32'd0;
        end else if (mem_stall) begin
            if (wb_write_en) begin
                shadow_wb_valid <= 1'b1;
                shadow_wb_rd    <= wb_rd_addr;
                shadow_wb_data  <= wb_data;
            end
        end else begin
            shadow_wb_valid <= 1'b0;
        end
    end
    wire fwd_wb_valid = wb_valid || shadow_wb_valid;
    wire fwd_wb_write = wb_valid ? wb_reg_write : shadow_wb_valid;
    wire [4:0] fwd_wb_rd = wb_valid ? wb_rd_addr : shadow_wb_rd;
    wire [31:0] fwd_wb_data = wb_valid ? wb_data : shadow_wb_data;

    forwarding_unit u_forwarding (
        .ex_valid(ex_valid), .ex_rs1_addr(ex_rs1_addr),
        .ex_rs2_addr(ex_rs2_addr), .ex_rs1_used(ex_rs1_used),
        .ex_rs2_used(ex_rs2_used),
        .exmem_valid(mem_valid), .exmem_reg_write(mem_reg_write),
        .exmem_rd_addr(mem_rd_addr),
        .exmem_result_ready(exmem_result_ready),
        .memwb_valid(fwd_wb_valid), .memwb_reg_write(fwd_wb_write),
        .memwb_rd_addr(fwd_wb_rd),
        .forward_a(forward_a), .forward_b(forward_b),
        .wait_a(wait_a), .wait_b(wait_b)
    );

    wire [31:0] ex_forwarded_a = (forward_a == 2'b10) ? exmem_forward_data :
                                 (forward_a == 2'b01) ? fwd_wb_data : ex_rs1_data;
    wire [31:0] ex_forwarded_b = (forward_b == 2'b10) ? exmem_forward_data :
                                 (forward_b == 2'b01) ? fwd_wb_data : ex_rs2_data;
    // Keep forwarding B available for a future store-data path, even when
    // the current arithmetic instruction takes its ALU B from an immediate.
    wire [31:0] ex_operand_b = ex_alu_src_imm ? ex_imm : ex_forwarded_b;
    wire [31:0] ex_alu_result;
    alu u_alu (
        .a(ex_forwarded_a), .b(ex_operand_b), .alu_op(ex_alu_op),
        .result(ex_alu_result)
    );

    // V0.8 EX-stage MDU.  The operation and operands are latched by the
    // unchanged official MDU on mdu_start_fire; the EX instruction stays
    // in ID/EX until the result is accepted by EX/MEM once.
    wire ex_is_mdu;
    wire [2:0] ex_mdu_op;
    wire [31:0] mdu_result;
    reg mdu_started;
    wire mdu_hold;
    mdu_decode_v08 u_mdu_ex_decode (
        .inst(ex_inst), .is_mdu(ex_is_mdu), .mdu_op(ex_mdu_op)
    );
    wire ex_mdu_valid = ex_valid && ex_is_mdu;
    // Never launch until the forwarded operands are ready and the older MEM
    // slot is free.  In particular, a pending Load may still produce operand B.
    assign mdu_start_fire = !rst && ex_mdu_valid && !mdu_started &&
                            !mdu_busy && !mdu_done &&
                            !ex_operand_wait && !mem_stall;
    // 'done' remains asserted under MEM backpressure; release the result only
    // on the very edge where EX/MEM is able to capture the MDU result.
    assign mdu_result_fire = !rst && ex_mdu_valid && mdu_started &&
                             mdu_done && !mem_stall && !ex_operand_wait;
    assign mdu_hold = ex_mdu_valid && !(mdu_started && mdu_done);
    always @(posedge clk) begin
        if (rst) mdu_started <= 1'b0;
        else if (mdu_result_fire) mdu_started <= 1'b0;
        else if (mdu_start_fire) mdu_started <= 1'b1;
        else if (!ex_mdu_valid) mdu_started <= 1'b0;
    end
    mdu_iterative u_mdu (
        .clk(clk), .rst(rst),
        .start(mdu_start_fire), .op(ex_mdu_op),
        .operand_a(ex_forwarded_a), .operand_b(ex_forwarded_b),
        .result_ready(mdu_result_fire),
        .busy(mdu_busy), .done(mdu_done),
        .result(mdu_result), .div_zero(mdu_div_zero)
    );
    wire [31:0] ex_effective_result = ex_is_mdu ? mdu_result : ex_alu_result;

    // Branch decision uses the same forwarded operand values as EX ALU.
    // Branch types from official Decoder: 1 BEQ, 2 BNE, 3 B, 4 BL, 5 JIRL.
    // Branch stage NEVER flushes its own EX/MEM latch, even on taken redirects.
    // Never issue the same redirect repeatedly while EX is frozen.
    // A load dependency in EX that cannot be forwarded is also held until
    // the producing memory result reaches WB.
    wire branch_resolve_raw, branch_redirect_raw;
    assign ex_operand_wait = ex_valid && (wait_a || wait_b);
    assign front_stall = mem_stall || ex_operand_wait || mdu_hold;
    assign branch_resolve_valid = branch_resolve_raw && !front_stall;
    assign branch_redirect = branch_redirect_raw && !front_stall;
    branch_resolve_v04 u_branch_resolve (
        .rst(rst), .ex_valid(ex_valid), .branch_type(ex_branch_type),
        .pc(ex_pc), .imm(ex_imm),
        .rs1_data(ex_forwarded_a), .rs2_data(ex_forwarded_b),
        .resolve_valid(branch_resolve_raw),
        .redirect_valid(branch_redirect_raw),
        .redirect_pc(branch_redirect_pc)
    );

    // EX / MEM
    ex_mem_reg u_ex_mem (
        .clk(clk), .rst(rst), .stall(mem_stall),
        .flush((ex_operand_wait || mdu_hold) && !mem_stall),
        .ex_valid(ex_valid), .ex_pc(ex_pc), .ex_pc_plus4(ex_pc_plus4),
        .ex_alu_result(ex_effective_result), .ex_store_data(ex_forwarded_b),
        .ex_store_src_addr(ex_rs2_addr), .ex_rd_addr(ex_rd_addr),
        .ex_mem_read(ex_mem_read), .ex_mem_write(ex_mem_write),
        .ex_reg_write(ex_reg_write), .ex_wb_sel(ex_wb_sel),
        .mem_valid(mem_valid), .mem_pc(mem_pc), .mem_pc_plus4(mem_pc_plus4),
        .mem_alu_result(mem_alu_result), .mem_store_data(mem_store_data),
        .mem_store_src_addr(mem_store_src_addr), .mem_rd_addr(mem_rd_addr),
        .mem_mem_read(mem_mem_read), .mem_mem_write(mem_mem_write),
        .mem_reg_write(mem_reg_write), .mem_wb_sel(mem_wb_sel)
    );

    // V0.7 MEM transaction FSM: one accepted request per EX/MEM memory slot.
    // EX/MEM does not advance while the request or its response is pending.
    wire mem_access = mem_valid && (mem_mem_read || mem_mem_write);
    reg mem_request_accepted;
    wire dmem_req_ready, dmem_resp_valid, dmem_resp_error;
    wire [31:0] dmem_resp_rdata;
    wire dmem_req_valid = !rst && mem_access && !mem_request_accepted;
    wire dmem_resp_ready = !rst && mem_access && mem_request_accepted;
    assign dmem_req_fire = dmem_req_valid && dmem_req_ready;
    assign dmem_resp_fire = dmem_resp_valid && dmem_resp_ready;
    assign mem_stall = mem_access && !dmem_resp_fire;

    always @(posedge clk) begin
        if (rst) begin
            mem_request_accepted <= 1'b0;
        end else if (dmem_resp_fire) begin
            mem_request_accepted <= 1'b0;
        end else if (dmem_req_fire) begin
            mem_request_accepted <= 1'b1;
        end else if (!mem_access) begin
            mem_request_accepted <= 1'b0;
        end
    end

    dmem_latency #(
        .READ_LATENCY(DMEM_READ_LATENCY),
        .WRITE_LATENCY(DMEM_WRITE_LATENCY),
        .WORDS(DMEM_WORDS), .INIT_FILE(DMEM_INIT_FILE)
    ) u_dmem (
        .clk(clk), .rst(rst),
        .req_valid(dmem_req_valid), .req_ready(dmem_req_ready),
        .req_write(mem_mem_write), .req_addr(mem_alu_result),
        .req_wdata(mem_store_data),
        .resp_valid(dmem_resp_valid), .resp_ready(dmem_resp_ready),
        .resp_rdata(dmem_resp_rdata), .resp_error(dmem_resp_error)
    );

    // One-cycle completion pulse. Loads with errors are consumed but never WB.
    assign mem_fault_valid = dmem_resp_fire && dmem_resp_error;
    assign mem_fault_pc = mem_pc;
    assign mem_fault_addr = mem_alu_result;
    assign mem_fault_store = mem_mem_write;
    wire mem_slot_complete = mem_valid && (!mem_access || dmem_resp_fire);
    wire mem_slot_writeback = mem_slot_complete && mem_reg_write &&
                                (!mem_access || !dmem_resp_error);
    reg [31:0] mem_selected_wb_data;
    always @(*) begin
        case (mem_wb_sel)
            2'b00: mem_selected_wb_data = mem_alu_result;
            2'b01: mem_selected_wb_data = dmem_resp_rdata;
            2'b10: mem_selected_wb_data = mem_pc_plus4;
            default: mem_selected_wb_data = 32'd0;
        endcase
    end

    // The official DMEM commits ST.W only on resp_fire, not on request.
    assign mem_store_commit_valid = dmem_resp_fire && mem_mem_write &&
                                    !dmem_resp_error && !rst;
    assign mem_store_commit_pc = mem_pc;
    assign mem_store_commit_addr = mem_alu_result;
    assign mem_store_commit_data = mem_store_data;

    // DO NOT stall MEM/WB together with MEM.  During a long MEM wait, WB
    // consumes the older instruction once, then takes invalid bubbles.
    // The completed memory instruction enters MEM/WB on its resp_fire edge.
    mem_wb_reg u_mem_wb (
        .clk(clk), .rst(rst), .stall(1'b0), .flush(1'b0),
        .mem_valid(mem_slot_complete), .mem_pc(mem_pc),
        .mem_wb_data(mem_selected_wb_data), .mem_rd_addr(mem_rd_addr),
        .mem_reg_write(mem_slot_writeback),
        .wb_valid(wb_valid), .wb_pc(wb_pc), .wb_data(wb_data),
        .wb_rd_addr(wb_rd_addr), .wb_reg_write(wb_reg_write),
        .wb_write_en(wb_write_en)
    );
    assign wb_commit_valid = wb_write_en && !rst;
    assign wb_commit_pc = wb_pc;
    assign wb_commit_rd = wb_rd_addr;
    assign wb_commit_data = wb_data;

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
    assign id_raw_hazard = id_accept && !front_stall && !branch_redirect && (raw_rs1 || raw_rs2);
endmodule
