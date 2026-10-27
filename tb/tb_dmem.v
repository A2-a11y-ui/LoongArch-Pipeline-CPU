
`timescale 1ns / 1ps

module tb_dmem;

    reg         clk;
    reg         we;
    reg  [31:0] addr;
    reg  [31:0] wdata;
    wire [31:0] rdata;

    integer errors;

    // 实例化被测模块 dmem
    dmem uut (
        .clk   (clk),
        .we    (we),
        .addr  (addr),
        .wdata (wdata),
        .rdata (rdata)
    );

    // 产生时钟：周期 10 ns
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // 写入一个 32 位字：在上升沿写入
    task write_word;
        input [31:0] a;
        input [31:0] d;
        begin
            @(negedge clk);
            addr  = a;
            wdata = d;
            we    = 1'b1;

            @(posedge clk);
            #1;
            we = 1'b0;
        end
    endtask

    // 检查指定地址的数据是否符合预期
    task check_word;
        input [31:0] a;
        input [31:0] expected;
        begin
            addr = a;
            #1;

            if (rdata !== expected) begin
                $display(
                    "[FAIL] addr=%h expected=%h actual=%h",
                    a, expected, rdata
                );
                errors = errors + 1;
            end
            else begin
                $display(
                    "[PASS] addr=%h data=%h",
                    a, rdata
                );
            end
        end
    endtask

    initial begin
        clk    = 1'b0;
        we     = 1'b0;
        addr   = 32'h00000000;
        wdata  = 32'h00000000;
        errors = 0;

        $display("================================");
        $display("       DMEM TEST START");
        $display("================================");

        // 测试 1：基本写入和读取
        write_word(32'h00000004, 32'h12345678);
        check_word(32'h00000004, 32'h12345678);

        // 测试 2：多个地址独立存储
        write_word(32'h00000008, 32'hAAAAAAAA);
        write_word(32'h0000000C, 32'h55555555);
        write_word(32'h00000010, 32'h0F0F0F0F);

        check_word(32'h00000004, 32'h12345678);
        check_word(32'h00000008, 32'hAAAAAAAA);
        check_word(32'h0000000C, 32'h55555555);
        check_word(32'h00000010, 32'h0F0F0F0F);

        // 测试 3：关闭写使能后，原数据不能改变
        @(negedge clk);
        addr  = 32'h00000004;
        wdata = 32'hDEADBEEF;
        we    = 1'b0;

        @(posedge clk);
        #1;
        check_word(32'h00000004, 32'h12345678);

        // 测试 4：新数据必须等到时钟上升沿才能写入
        @(negedge clk);
        addr  = 32'h00000004;
        wdata = 32'hDEADBEEF;
        we    = 1'b1;

        // 此时尚未到达下一个上升沿，旧数据应保持
        #1;
        check_word(32'h00000004, 32'h12345678);

        // 等待上升沿及非阻塞赋值更新
        @(posedge clk);
        #1;
        check_word(32'h00000004, 32'hDEADBEEF);
        we = 1'b0;

        // 测试 5：最低和最高合法字地址
        write_word(32'h00000000, 32'h0BADF00D);
        write_word(32'h000003FC, 32'hC001D00D);

        check_word(32'h00000000, 32'h0BADF00D);
        check_word(32'h000003FC, 32'hC001D00D);

        // 再次检查其他地址，确认边界写入没有覆盖它们
        check_word(32'h00000004, 32'hDEADBEEF);
        check_word(32'h00000008, 32'hAAAAAAAA);
        check_word(32'h0000000C, 32'h55555555);
        check_word(32'h00000010, 32'h0F0F0F0F);

        // 汇总测试结果
        $display("================================");
        $display("Total errors: %0d", errors);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");

        $display("================================");
        $finish;
    end

endmodule
