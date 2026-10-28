
`timescale 1ns / 1ps

module dmem (
    input  wire        clk,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output wire [31:0] rdata
);

    // 256 个 32 位存储单元，总容量为 1 KiB
    reg [31:0] mem [0:255];

    // 同步写入：只有时钟上升沿且写使能有效时才写入
    always @(posedge clk) begin
        if (we) begin
            mem[addr[9:2]] <= wdata;
        end
    end

    // 组合逻辑读取：地址变化后，输出相应存储单元的数据
    assign rdata = mem[addr[9:2]];

endmodule
