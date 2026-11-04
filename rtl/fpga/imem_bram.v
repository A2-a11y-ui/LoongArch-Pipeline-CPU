`timescale 1ns / 1ps
// V0.9 FPGA instruction ROM.
//
// Synchronous single-port ROM used as the I-Cache backing memory.
// The interface intentionally matches imem_latency.v so the existing
// icache_if_adapter / icache_2way_latency RTL can be reused unchanged.
//
// Address contract:
//   - byte address
//   - 32-bit aligned
//   - physical address range 0x000..0x3ff (256 words)
//
// Timing contract:
//   - mem_req is a one-cycle request pulse from icache_2way_latency.
//   - one clock after request acceptance, mem_ready is asserted for one cycle
//     and mem_rdata / mem_addr_valid are valid.
//   - this is a synchronous ROM read and is intended for BRAM inference.
//
// The ROM is not reset. Its contents are initialized from INIT_FILE.
// Unfilled words default to ADDI.W r0,r0,0 (a harmless LoongArch NOP).
module imem_bram #(
    parameter INIT_FILE = "fpga_demo.mem"
)(
    input  wire        clk,
    input  wire        rst,

    input  wire        mem_req,
    input  wire [31:0] mem_addr,

    output reg         mem_ready,
    output wire [31:0] mem_rdata,
    output reg         mem_addr_valid,
    output reg  [31:0] transactions
);

    (* rom_style = "block" *) reg [31:0] rom [0:255];

    reg        busy;
    reg [31:0] pending_addr;
    reg [31:0] rom_q;

    integer init_index;

    wire pending_addr_legal;
    assign pending_addr_legal =
        (pending_addr[31:10] == 22'b0) &&
        (pending_addr[1:0] == 2'b00);

    assign mem_rdata = rom_q;

    // FPGA configuration-time initialization. Do not clear the ROM on reset.
    initial begin
        for (init_index = 0; init_index < 256; init_index = init_index + 1)
            rom[init_index] = 32'h02800000; // ADDI.W r0,r0,0

        if (INIT_FILE != "")
            $readmemh(INIT_FILE, rom);
    end

    always @(posedge clk) begin
        if (rst) begin
            busy            <= 1'b0;
            pending_addr    <= 32'b0;
            mem_ready       <= 1'b0;
            mem_addr_valid  <= 1'b0;
            transactions    <= 32'b0;
        end else begin
            mem_ready      <= 1'b0;
            mem_addr_valid <= 1'b0;

            if (!busy && mem_req) begin
                // Accept one request. The I-Cache emits a one-cycle pulse.
                busy         <= 1'b1;
                pending_addr <= mem_addr;
                transactions <= transactions + 32'd1;
            end else if (busy) begin
                // Synchronous ROM read; response is visible after this edge.
                busy           <= 1'b0;
                mem_ready      <= 1'b1;
                mem_addr_valid <= pending_addr_legal;

                if (pending_addr_legal)
                    rom_q <= rom[pending_addr[9:2]];
                else
                    rom_q <= 32'b0;
            end
        end
    end

endmodule
