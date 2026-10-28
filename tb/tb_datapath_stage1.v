`timescale 1ns / 1ps

// Full stage-1 data-path integration test (single-cycle, not pipelined).
// Expected values are independent constants, not taken from DUT internals.
module tb_datapath_stage1;
    reg clk, rst, exec_en;
    reg [31:0] inst;
    wire valid;
    wire [4:0] rs1_addr, rs2_addr, rd_addr;
    wire [31:0] rs1_data, rs2_data, imm, alu_result, wb_data, mem_rdata;
    wire [3:0] alu_op;
    wire [2:0] imm_sel;
    wire reg_we, mem_we, mem_read;
    integer tests, errors;

    localparam [31:0] OP_NOR   = 32'h00140000;
    localparam [31:0] OP_AND   = 32'h00148000;
    localparam [31:0] OP_OR    = 32'h00150000;
    localparam [31:0] OP_XOR   = 32'h00158000;
    localparam [31:0] OP_ANDI  = 32'h03400000;
    localparam [31:0] OP_ORI   = 32'h03800000;
    localparam [31:0] OP_XORI  = 32'h03C00000;
    localparam [31:0] OP_SLLI  = 32'h00408000;
    localparam [31:0] OP_SRLI  = 32'h00448000;
    localparam [31:0] OP_SRAI  = 32'h00488000;
    localparam [31:0] OP_LU12I = 32'h14000000;
    localparam [31:0] OP_LD    = 32'h28800000;
    localparam [31:0] OP_ST    = 32'h29800000;

    // {rd, rj, rk} in low 15 bits for LoongArch 3R and shift-immediate formats.
    function [31:0] enc3;
        input [31:0] opcode;
        input [4:0] rd, rj, rk;
        begin enc3 = opcode | {17'b0, rk, rj, rd}; end
    endfunction

    // 2RI12: opcode | si12/ui12 | rj | rd.
    function [31:0] enc12;
        input [31:0] opcode;
        input [4:0] rd, rj;
        input [11:0] i12;
        begin enc12 = opcode | {10'b0, i12, rj, rd}; end
    endfunction

    // LU12I.W: opcode | si20 | rd.
    function [31:0] enc20;
        input [31:0] opcode;
        input [4:0] rd;
        input [19:0] i20;
        begin enc20 = opcode | {7'b0, i20, rd}; end
    endfunction

    datapath_stage1 dut (
        .clk(clk), .rst(rst), .exec_en(exec_en), .inst(inst),
        .dbg_valid(valid), .dbg_rs1_addr(rs1_addr),
        .dbg_rs2_addr(rs2_addr), .dbg_rd_addr(rd_addr),
        .dbg_rs1_data(rs1_data), .dbg_rs2_data(rs2_data),
        .dbg_imm(imm), .dbg_alu_result(alu_result),
        .dbg_wb_data(wb_data), .dbg_mem_rdata(mem_rdata),
        .dbg_alu_op(alu_op), .dbg_imm_sel(imm_sel),
        .dbg_reg_we(reg_we), .dbg_mem_we(mem_we),
        .dbg_mem_read(mem_read)
    );

    always #5 clk = ~clk;

    // bits of flags: [2] actual RF write, [1] DMEM write, [0] DMEM read.
    // Each valid instruction executes for exactly ONE clock rising edge.
    task issue;
        input [8*30-1:0] name;
        input [31:0] instruction, exp_alu, exp_wb, exp_imm, exp_store_data;
        input [2:0] flags;
        reg fail;
        begin
            @(negedge clk);
            inst = instruction;
            exec_en = 1'b1;
            #1;
            tests = tests + 1;
            fail = 1'b0;
            if (valid !== 1'b1 || alu_result !== exp_alu
                || imm !== exp_imm || reg_we !== flags[2]
                || mem_we !== flags[1] || mem_read !== flags[0])
                fail = 1'b1;
            if (flags[2] && wb_data !== exp_wb)
                fail = 1'b1;
            if (flags[1] && (rs2_addr !== instruction[4:0]
                || rs2_data !== exp_store_data))
                fail = 1'b1;
            if (fail) begin
                errors = errors + 1;
                $display("FAIL step %0s inst=%08h", name, instruction);
                $display("  got alu=%08h wb=%08h imm=%08h flags=%b%b%b",
                         alu_result, wb_data, imm, reg_we, mem_we, mem_read);
                $display("  exp alu=%08h wb=%08h imm=%08h flags=%b store=%08h",
                         exp_alu, exp_wb, exp_imm, flags, exp_store_data);
                $display("  got rs2_addr=%0d rs2_data=%08h", rs2_addr, rs2_data);
            end else begin
                $display("PASS step %0s", name);
            end
            @(posedge clk);
            #1;
            exec_en = 1'b0;
        end
    endtask

    // Probe a register through the real asynchronous register-file READ PORT.
    // exec_en=0 prevents an additional commit (no white-box regfile memory peek).
    task probe;
        input [8*30-1:0] name;
        input [4:0] idx;
        input [31:0] expected;
        begin
            exec_en = 1'b0;
            inst = enc3(OP_AND, 5'd0, idx, idx);
            #1;
            tests = tests + 1;
            if (rs1_addr !== idx || rs1_data !== expected || reg_we !== 1'b0) begin
                errors = errors + 1;
                $display("FAIL probe %0s r%0d got=%08h expected=%08h",
                         name, idx, rs1_data, expected);
            end else begin
                $display("PASS probe %0s r%0d=%08h", name, idx, rs1_data);
            end
        end
    endtask

    task invalid_instruction;
        input [31:0] ins;
        begin
            @(negedge clk);
            inst = ins;
            exec_en = 1'b1;
            #1;
            tests = tests + 1;
            if (valid !== 1'b0 || reg_we !== 1'b0 || mem_we !== 1'b0) begin
                errors = errors + 1;
                $display("FAIL invalid inst=%08h valid=%b rf_we=%b dm_we=%b",
                         ins, valid, reg_we, mem_we);
            end else
                $display("PASS invalid inst=%08h (no side effects)", ins);
            @(posedge clk);
            #1;
            exec_en = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        exec_en = 1'b0;
        inst = 32'b0;
        tests = 0;
        errors = 0;

        // Synchronous reset must cross rising clock edges.
        repeat (2) @(posedge clk);
        #1;
        rst = 1'b0;
        probe("r0 after reset", 5'd0, 32'h00000000);
        probe("r1 after reset", 5'd1, 32'h00000000);

        issue("LU12I r1", enc20(OP_LU12I,1,20'h12345),
              32'h12345000, 32'h12345000, 32'h12345000,32'h0,3'b100);
        probe("r1 high", 1, 32'h12345000);

        issue("ORI r1,r1,678", enc12(OP_ORI,1,1,12'h678),
              32'h12345678,32'h12345678,32'h00000678,32'h0,3'b100);
        probe("r1 constructed", 1, 32'h12345678);

        issue("LU12I r2 sign", enc20(OP_LU12I,2,20'h80000),
              32'h80000000,32'h80000000,32'h80000000,32'h0,3'b100);
        probe("r2 sign", 2, 32'h80000000);

        issue("ORI r3 all12", enc12(OP_ORI,3,0,12'hFFF),
              32'h00000FFF,32'h00000FFF,32'h00000FFF,32'h0,3'b100);
        probe("r3", 3, 32'h00000FFF);

        issue("AND r4", enc3(OP_AND,4,1,3),
              32'h00000678,32'h00000678,32'h0,32'h0,3'b100);
        probe("r4", 4, 32'h00000678);

        issue("OR r5", enc3(OP_OR,5,1,3),
              32'h12345FFF,32'h12345FFF,32'h0,32'h0,3'b100);
        probe("r5", 5, 32'h12345FFF);

        issue("NOR r6", enc3(OP_NOR,6,0,3),
              32'hFFFFF000,32'hFFFFF000,32'h0,32'h0,3'b100);
        probe("r6", 6, 32'hFFFFF000);

        issue("XOR r7", enc3(OP_XOR,7,1,3),
              32'h12345987,32'h12345987,32'h0,32'h0,3'b100);
        probe("r7", 7, 32'h12345987);

        issue("ANDI r8", enc12(OP_ANDI,8,1,12'h0FF),
              32'h00000078,32'h00000078,32'h000000FF,32'h0,3'b100);
        probe("r8", 8, 32'h00000078);

        issue("XORI r9", enc12(OP_XORI,9,3,12'hAAA),
              32'h00000555,32'h00000555,32'h00000AAA,32'h0,3'b100);
        probe("r9", 9, 32'h00000555);

        issue("SLLI r10,4", enc3(OP_SLLI,10,3,4),
              32'h0000FFF0,32'h0000FFF0,32'h00000004,32'h0,3'b100);
        probe("r10", 10, 32'h0000FFF0);

        issue("SRLI r11,31", enc3(OP_SRLI,11,2,31),
              32'h00000001,32'h00000001,32'h0000001F,32'h0,3'b100);
        probe("r11", 11, 32'h00000001);

        issue("SRAI r12,31", enc3(OP_SRAI,12,2,31),
              32'hFFFFFFFF,32'hFFFFFFFF,32'h0000001F,32'h0,3'b100);
        probe("r12", 12, 32'hFFFFFFFF);

        issue("SLLI r13,0", enc3(OP_SLLI,13,1,0),
              32'h12345678,32'h12345678,32'h00000000,32'h0,3'b100);
        probe("r13", 13, 32'h12345678);

        // Store/load at byte address 0, using r1 as ST.W's rd-field data source.
        issue("ST.W r1,0(r0)", enc12(OP_ST,1,0,12'h000),
              32'h00000000,32'h0,32'h0,32'h12345678,3'b010);
        issue("LD.W r16,0(r0)", enc12(OP_LD,16,0,12'h000),
              32'h00000000,32'h12345678,32'h0,32'h0,3'b101);
        probe("r16 loaded", 16, 32'h12345678);

        // Negative sign-extended address: 0x10 + (-4) = 0x0c.
        issue("ORI r17,0x10", enc12(OP_ORI,17,0,12'h010),
              32'h00000010,32'h00000010,32'h00000010,32'h0,3'b100);
        issue("ST.W r2,-4(r17)", enc12(OP_ST,2,17,12'hFFC),
              32'h0000000C,32'h0,32'hFFFFFFFC,32'h80000000,3'b010);
        issue("LD.W r18,-4(r17)", enc12(OP_LD,18,17,12'hFFC),
              32'h0000000C,32'h80000000,32'hFFFFFFFC,32'h0,3'b101);
        probe("r18 loaded sign", 18, 32'h80000000);

        // Store/read zero; do not confuse r0 with unknown DMEM contents.
        issue("ST.W r0,4(r17)", enc12(OP_ST,0,17,12'h004),
              32'h00000014,32'h0,32'h00000004,32'h00000000,3'b010);
        issue("LD.W r19,4(r17)", enc12(OP_LD,19,17,12'h004),
              32'h00000014,32'h0,32'h00000004,32'h0,3'b101);
        probe("r19 zero load", 19, 32'h00000000);

        // Writing r0 must have no effect, even for a decoded RegWrite operation.
        issue("ORI to r0 blocked", enc12(OP_ORI,0,0,12'hFFF),
              32'h00000FFF,32'h0,32'h00000FFF,32'h0,3'b000);
        probe("r0 stays 0", 0, 32'h00000000);

        // Back-to-back dependent instructions (single-cycle, no pipeline hazards yet).
        issue("ORI r22 one", enc12(OP_ORI,22,0,12'h001),
              32'h00000001,32'h00000001,32'h00000001,32'h0,3'b100);
        issue("SLLI r23 dep", enc3(OP_SLLI,23,22,1),
              32'h00000002,32'h00000002,32'h00000001,32'h0,3'b100);
        issue("SLLI r24 dep", enc3(OP_SLLI,24,23,1),
              32'h00000004,32'h00000004,32'h00000001,32'h0,3'b100);
        probe("r24 dependent result", 24, 32'h00000004);

        invalid_instruction(32'hFFFFFFFF);
        invalid_instruction(32'h00000000);
        invalid_instruction(32'h02800000); // ADDI.W belongs to A/shared future set
        probe("r1 survived invalid", 1, 32'h12345678);
        probe("r18 survived invalid", 18, 32'h80000000);

        $display("====================================");
        $display("Total tests  = %0d", tests);
        $display("Total errors = %0d", errors);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end
endmodule
