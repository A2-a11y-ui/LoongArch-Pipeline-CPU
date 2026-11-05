`timescale 1ns / 1ps
// V0.9 independent directed verification of the optimized ID/EX register.
// Simulation-only Verilog-2001. DO NOT include this testbench in synthesis.
//
// Real DUTs: rtl/common/id_ex_reg.v (PR #41 optimized version)
//            rtl/common/ex_mem_reg.v (unchanged downstream pipeline register)
//
// Important scope note:
// - This verifies full ID/EX payload, valid priority and the real EX/MEM
//   register's valid/controls after a flushed or invalid ID/EX slot.
// - WB/Store observation below is a valid-gated side-effect *eligibility*
//   condition, not a claim that a complete CPU or DMEM is instantiated.
// - The MDU/MEM backpressure case verifies ID/EX holding under a shared
//   stall. Actual MDU handshake/one-time commit needs a full CPU test.
module tb_v09_idex_flush_sideeffects;
    reg clk;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    reg rst, stall, flush;
    reg id_valid;
    reg [31:0] id_pc, id_pc_plus4, id_inst;
    reg [4:0] id_rs1_addr, id_rs2_addr, id_rd_addr;
    reg [31:0] id_rs1_data, id_rs2_data;
    reg id_rs1_used, id_rs2_used;
    reg [31:0] id_imm;
    reg [3:0] id_alu_op;
    reg id_alu_src_imm;
    reg [2:0] id_branch_type;
    reg [1:0] id_wb_sel;
    reg id_reg_write, id_mem_read, id_mem_write;

    wire ex_valid;
    wire [31:0] ex_pc, ex_pc_plus4, ex_inst;
    wire [4:0] ex_rs1_addr, ex_rs2_addr, ex_rd_addr;
    wire [31:0] ex_rs1_data, ex_rs2_data;
    wire ex_rs1_used, ex_rs2_used;
    wire [31:0] ex_imm;
    wire [3:0] ex_alu_op;
    wire ex_alu_src_imm;
    wire [2:0] ex_branch_type;
    wire [1:0] ex_wb_sel;
    wire ex_reg_write, ex_mem_read, ex_mem_write;

    // The packing verifies *every* payload field, not just PC and flags.
    wire [221:0] id_payload = {
        id_pc, id_pc_plus4, id_inst,
        id_rs1_addr, id_rs2_addr, id_rd_addr,
        id_rs1_data, id_rs2_data, id_rs1_used, id_rs2_used,
        id_imm, id_alu_op, id_alu_src_imm, id_branch_type,
        id_wb_sel, id_reg_write, id_mem_read, id_mem_write
    };
    wire [221:0] ex_payload = {
        ex_pc, ex_pc_plus4, ex_inst,
        ex_rs1_addr, ex_rs2_addr, ex_rd_addr,
        ex_rs1_data, ex_rs2_data, ex_rs1_used, ex_rs2_used,
        ex_imm, ex_alu_op, ex_alu_src_imm, ex_branch_type,
        ex_wb_sel, ex_reg_write, ex_mem_read, ex_mem_write
    };

    id_ex_reg dut (
        .clk(clk), .rst(rst), .stall(stall), .flush(flush),
        .id_valid(id_valid), .id_pc(id_pc), .id_pc_plus4(id_pc_plus4), .id_inst(id_inst),
        .id_rs1_addr(id_rs1_addr), .id_rs2_addr(id_rs2_addr), .id_rd_addr(id_rd_addr),
        .id_rs1_data(id_rs1_data), .id_rs2_data(id_rs2_data),
        .id_rs1_used(id_rs1_used), .id_rs2_used(id_rs2_used),
        .id_imm(id_imm), .id_alu_op(id_alu_op),
        .id_alu_src_imm(id_alu_src_imm), .id_branch_type(id_branch_type),
        .id_wb_sel(id_wb_sel), .id_reg_write(id_reg_write),
        .id_mem_read(id_mem_read), .id_mem_write(id_mem_write),
        .ex_valid(ex_valid), .ex_pc(ex_pc), .ex_pc_plus4(ex_pc_plus4), .ex_inst(ex_inst),
        .ex_rs1_addr(ex_rs1_addr), .ex_rs2_addr(ex_rs2_addr), .ex_rd_addr(ex_rd_addr),
        .ex_rs1_data(ex_rs1_data), .ex_rs2_data(ex_rs2_data),
        .ex_rs1_used(ex_rs1_used), .ex_rs2_used(ex_rs2_used),
        .ex_imm(ex_imm), .ex_alu_op(ex_alu_op),
        .ex_alu_src_imm(ex_alu_src_imm), .ex_branch_type(ex_branch_type),
        .ex_wb_sel(ex_wb_sel), .ex_reg_write(ex_reg_write),
        .ex_mem_read(ex_mem_read), .ex_mem_write(ex_mem_write)
    );

    // EX/MEM is the actual stable downstream pipeline register.
    // A synthetic EX result is enough here: the tested property is that
    // invalid ID/EX slots cannot become eligible for a WB or a Store.
    reg downstream_stall, downstream_flush;
    wire mem_valid;
    wire [31:0] mem_pc, mem_pc_plus4, mem_alu_result, mem_store_data;
    wire [4:0] mem_store_src_addr, mem_rd_addr;
    wire mem_mem_read, mem_mem_write, mem_reg_write;
    wire [1:0] mem_wb_sel;
    ex_mem_reg u_ex_mem (
        .clk(clk), .rst(rst), .stall(downstream_stall), .flush(downstream_flush),
        .ex_valid(ex_valid), .ex_pc(ex_pc), .ex_pc_plus4(ex_pc_plus4),
        .ex_alu_result(ex_rs1_data + ex_imm), .ex_store_data(ex_rs2_data),
        .ex_store_src_addr(ex_rs2_addr), .ex_rd_addr(ex_rd_addr),
        .ex_mem_read(ex_mem_read), .ex_mem_write(ex_mem_write),
        .ex_reg_write(ex_reg_write), .ex_wb_sel(ex_wb_sel),
        .mem_valid(mem_valid), .mem_pc(mem_pc), .mem_pc_plus4(mem_pc_plus4),
        .mem_alu_result(mem_alu_result), .mem_store_data(mem_store_data),
        .mem_store_src_addr(mem_store_src_addr), .mem_rd_addr(mem_rd_addr),
        .mem_mem_read(mem_mem_read), .mem_mem_write(mem_mem_write),
        .mem_reg_write(mem_reg_write), .mem_wb_sel(mem_wb_sel)
    );
    wire ex_wb_eligible = ex_valid && ex_reg_write && (ex_rd_addr != 5'd0);
    wire ex_store_eligible = ex_valid && ex_mem_write;
    wire mem_wb_eligible = mem_valid && mem_reg_write && (mem_rd_addr != 5'd0);
    wire mem_store_eligible = mem_valid && mem_mem_write;

    integer checks, errors, scenarios, cycles, i;
    reg [221:0] snapshot;

    task check;
        input condition;
        input [8*112-1:0] label_text;
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL: %0s (cycle=%0d, ex_valid=%b ex_rw=%b ex_sw=%b mem_valid=%b mem_rw=%b mem_sw=%b)",
                         label_text, cycles, ex_valid, ex_reg_write, ex_mem_write,
                         mem_valid, mem_reg_write, mem_mem_write);
            end
        end
    endtask

    task tick;
        begin
            @(posedge clk);
            #1;   // sample after nonblocking assignments settle
            cycles = cycles + 1;
        end
    endtask

    task init_inputs;
        begin
            rst=0; stall=0; flush=0; id_valid=0;
            id_pc=0; id_pc_plus4=0; id_inst=0;
            id_rs1_addr=0; id_rs2_addr=0; id_rd_addr=0;
            id_rs1_data=0; id_rs2_data=0;
            id_rs1_used=0; id_rs2_used=0;
            id_imm=0; id_alu_op=0; id_alu_src_imm=0;
            id_branch_type=0; id_wb_sel=0;
            id_reg_write=0; id_mem_read=0; id_mem_write=0;
            downstream_stall=0; downstream_flush=0;
        end
    endtask

    task drive_pattern;
        input [31:0] seed;
        begin
            id_pc=seed; id_pc_plus4=seed+32'd4;
            id_inst=seed ^ 32'h1C00AA55;
            id_rs1_addr=5'd7; id_rs2_addr=5'd12; id_rd_addr=5'd5;
            id_rs1_data=seed ^ 32'h13579BDF;
            id_rs2_data=seed ^ 32'h2468ACE0;
            id_rs1_used=1; id_rs2_used=1;
            id_imm=seed+32'h124; id_alu_op=4'hA;
            id_alu_src_imm=1; id_branch_type=3'd4;
            id_wb_sel=2'd2;
            id_reg_write=1; id_mem_read=0; id_mem_write=1;
            id_valid=1;
        end
    endtask

    task reset_all;
        begin
            init_inputs();
            rst=1;
            tick();
            check(ex_valid === 1'b0, "reset clears ID/EX valid");
            check(ex_payload === 222'd0, "reset clears ALL ID/EX payload fields");
            check(mem_valid === 1'b0, "reset clears EX/MEM valid");
            check(mem_reg_write === 1'b0 && mem_mem_write === 1'b0,
                  "reset clears EX/MEM write controls");
            rst=0;
        end
    endtask

    // Targeted flush case. mask[2]=regwrite, [1]=memwrite, [0]=memread.
    // Deliberately allows raw control combinations that would not be a
    // legal decoded instruction: a *flushed* slot must be harmless even so.
    task run_flush_case;
        input [2:0] mask;
        input [8*80-1:0] name;
        begin
            scenarios = scenarios + 1;
            $display("CASE %0d: %0s", scenarios, name);
            reset_all();
            drive_pattern(32'h00002000 + {29'd0,mask});
            id_reg_write=mask[2];
            id_mem_write=mask[1];
            id_mem_read=mask[0];
            flush=1; stall=0;
            tick();
            check(ex_valid === 1'b0, "flush invalidates ID/EX even with write enables asserted");
            check(ex_payload === id_payload, "flush without stall captures exact invalid payload (all fields)");
            check(ex_reg_write === mask[2] && ex_mem_write === mask[1] &&
                  ex_mem_read === mask[0], "raw side-effect flags preserved in invalid payload");
            check(ex_wb_eligible === 1'b0 && ex_store_eligible === 1'b0,
                  "invalid EX slot is ineligible for WB and Store");

            // One cycle later, the REAL EX/MEM pipeline register must have
            // received valid=0, although its raw write controls may be 1.
            flush=0; id_valid=0;
            id_reg_write=0; id_mem_write=0; id_mem_read=0;
            tick();
            check(mem_valid === 1'b0, "flushed ID/EX becomes invalid EX/MEM slot");
            check(mem_reg_write === mask[2] && mem_mem_write === mask[1] &&
                  mem_mem_read === mask[0], "EX/MEM transports raw invalid control bits without corruption");
            check(mem_wb_eligible === 1'b0 && mem_store_eligible === 1'b0,
                  "invalid EX/MEM cannot be eligible for WB or Store");
        end
    endtask

    initial begin
        checks=0; errors=0; scenarios=0; cycles=0;
        init_inputs();

        // 1..4: Flush with writeback, store, both, then all control flags.
        run_flush_case(3'b100, "Flush with reg_write=1");
        run_flush_case(3'b010, "Flush with mem_write=1");
        run_flush_case(3'b110, "Flush with reg_write=1 and mem_write=1");
        run_flush_case(3'b111, "Flush with reg_write/mem_write/mem_read all 1");

        // 5: Flush+Stall must clear valid but hold ALL payload fields.
        scenarios=scenarios+1;
        $display("CASE %0d: Flush+Stall priority and full payload hold", scenarios);
        reset_all();
        drive_pattern(32'h00003100);
        id_reg_write=1; id_mem_write=0;
        tick();
        check(ex_valid === 1'b1, "seed instruction captured before Flush+Stall");
        check(ex_payload === id_payload, "seed payload captured exactly");
        snapshot=ex_payload;
        drive_pattern(32'h00003200);
        stall=1; flush=1;
        id_reg_write=1; id_mem_write=1;
        tick();
        check(ex_valid === 1'b0, "Flush has priority over Stall for ex_valid");
        check(ex_payload === snapshot, "Flush+Stall preserves every payload bit");
        check(ex_wb_eligible === 1'b0 && ex_store_eligible === 1'b0,
              "retained controls are ineligible once flushed");
        // The previous, older EX instruction is allowed to advance on the
        // flush edge. Now explicitly clear it before checking younger bubble.
        flush=0; downstream_flush=1;
        tick();
        check(mem_valid === 1'b0, "downstream cleanup removes prior older slot");
        downstream_flush=0; stall=0; id_valid=0;
        id_reg_write=0; id_mem_write=0;
        tick();
        check(ex_valid === 1'b0, "invalid slot stays invalid after stall release");
        check(mem_valid === 1'b0 && mem_wb_eligible === 1'b0 && mem_store_eligible === 1'b0,
              "no invalid downstream WB/Store eligibility after stall release");

        // 6: Reset must beat Flush and Stall, including all controls.
        scenarios=scenarios+1;
        $display("CASE %0d: Reset > Flush > Stall", scenarios);
        reset_all();
        drive_pattern(32'h00004100);
        tick();
        drive_pattern(32'h00004200);
        rst=1; flush=1; stall=1; downstream_stall=1; downstream_flush=1;
        tick();
        check(ex_valid === 1'b0, "Reset overrides Flush and Stall for valid");
        check(ex_payload === 222'd0, "Reset clears all payload despite Flush+Stall");
        check(mem_valid === 1'b0 && mem_reg_write === 1'b0 && mem_mem_write === 1'b0,
              "Reset clears downstream state despite its Flush+Stall");
        rst=0; flush=0; stall=0; downstream_stall=0; downstream_flush=0;
        id_valid=0; id_reg_write=0; id_mem_write=0;
        tick();
        check(ex_valid === 1'b0, "no ghost instruction appears after reset release");

        // 7: ID/EX payload must hold over synthetic combined MDU + MEM stall.
        // Uses a real MDU instruction word from the Stage3 40-word program.
        // This does NOT instantiate the MDU: repeat/start/done counts need
        // an independent full CPU backpressure test.
        scenarios=scenarios+1;
        $display("CASE %0d: MDU-slot payload hold under MDU/MEM backpressure", scenarios);
        reset_all();
        drive_pattern(32'h00001010);
        id_inst=32'h001C0885;  // Stage3 mul.w instruction
        id_rs1_data=32'd6; id_rs2_data=32'd3;
        id_reg_write=1; id_mem_write=0; id_mem_read=0;
        tick();
        check(ex_valid === 1'b1 && ex_inst === 32'h001C0885,
              "valid MDU instruction initially captured");
        snapshot=ex_payload;
        stall=1;
        for (i=0; i<8; i=i+1) begin
            drive_pattern(32'h00005000+i);
            // First half models an older MEM slot holding while MDU waits.
            // Second half models MDU continuing to wait as MEM clears.
            downstream_stall=(i<4);
            downstream_flush=(i>=4);
            tick();
            check(ex_valid === 1'b1, "MDU-slot valid holds throughout front stall");
            check(ex_payload === snapshot, "all operands/destination/controls hold through MDU+MEM wait");
        end
        downstream_stall=0; downstream_flush=1; stall=0;
        id_valid=0; id_reg_write=0; id_mem_write=0;
        tick();
        check(ex_valid === 1'b0, "MDU slot vacates when stall is released");
        check(ex_payload === id_payload, "new bubble payload captured exactly after release");

        // 8: An invalid ID bubble with write controls must remain ineligible.
        scenarios=scenarios+1;
        $display("CASE %0d: invalid ID bubble with nonzero controls", scenarios);
        reset_all();
        drive_pattern(32'h00006300);
        id_valid=0; id_reg_write=1; id_mem_write=1;
        tick();
        check(ex_valid === 1'b0 && ex_reg_write === 1'b1 && ex_mem_write === 1'b1,
              "invalid input may leave raw EX control bits high");
        check(ex_wb_eligible === 1'b0 && ex_store_eligible === 1'b0,
              "invalid EX bubble does not qualify as WB/Store");
        tick();
        check(mem_valid === 1'b0 && mem_reg_write === 1'b1 && mem_mem_write === 1'b1,
              "invalid EX bubble propagates as invalid EX/MEM with raw controls");
        check(mem_wb_eligible === 1'b0 && mem_store_eligible === 1'b0,
              "invalid EX/MEM bubble does not qualify as WB/Store");

        if (scenarios != 8 || checks != 95) begin
            errors = errors + 1;
            $display("FAIL: test coverage count unexpected (CASES=%0d CHECKS=%0d; expected 8/95)",
                     scenarios, checks);
        end
        $display("--------------------------------------------------");
        $display("V09 IDEX SIDE EFFECTS RESULT CASES=%0d CHECKS=%0d ERRORS=%0d", scenarios, checks, errors);
        if (errors == 0) $display("ALL TESTS PASSED (ID/EX + EX/MEM directed verification only)");
        else $display("TEST FAILED (ID/EX + EX/MEM directed verification)");
        $finish;
    end

    initial begin
        #10000;
        $display("FAIL: TIMEOUT in V09 ID/EX directed verification");
        $finish;
    end
endmodule
