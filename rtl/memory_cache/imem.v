// LoongArch-Pipeline-CPU - Baseline instruction memory (Stage 2)
// Vivado 2019.1 / Verilog-2001
// Addressing: 32-bit byte address; 256 x 32-bit words = 1024 bytes.
// Instruction fetch is combinational. No dynamic writes: this is a ROM model.
// Optional INIT_FILE is a $readmemh-style, one 32-bit word per line file.
// This is a baseline memory, NOT the future instruction cache.
module imem #(
    parameter INIT_FILE = ""
) (
    input  wire [31:0] addr,
    output wire [31:0] inst,
    output wire        addr_valid
);
    reg [31:0] mem [0:255];
    integer i;

    initial begin
        for (i = 0; i < 256; i = i + 1)
            mem[i] = 32'h00000000;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    // Four-byte alignment and 1 KiB address range required.
    assign addr_valid = (addr[1:0] == 2'b00) && (addr[31:10] == 22'b0);
    assign inst = addr_valid ? mem[addr[9:2]] : 32'h00000000;
endmodule
