// LoongArch-Pipeline-CPU -- instruction cache, independent baseline (V0.1)
// Verilog-2001 / Vivado 2019.1.
// 16 direct-mapped lines, four 32-bit words per line = 256 bytes of data.
// Address breakdown: TAG[31:8], INDEX[7:4], WORD[3:2], BYTE[1:0].
// Valid request address: 4-byte aligned and in 0x00000000..0x000003FC.
// IMPORTANT: This demo assumes a combinational (zero-wait) backing imem.
// It takes four clock edges to refill, then serves the held request.
// Hold req_addr and req_valid stable while stall=1.
module icache (
    input  wire        clk,
    input  wire        rst,
    input  wire        req_valid,
    input  wire [31:0] req_addr,

    output wire [31:0] inst,
    output wire        ready,          // one request can be consumed this cycle
    output wire        fetch_valid,    // address legal AND request ready
    output wire        stall,          // hold PC and suppress architectural writes
    output wire        hit,            // current request found in cache

    output wire [31:0] mem_addr,       // connect to imem.addr
    output wire        mem_req,        // informational: refill underway
    input  wire [31:0] mem_rdata,      // connect to imem.inst
    input  wire        mem_addr_valid, // connect to imem.addr_valid

    output reg  [31:0] hit_count,
    output reg  [31:0] miss_count,
    output reg  [31:0] refill_words
);
    localparam STATE_IDLE = 1'b0;
    localparam STATE_FILL = 1'b1;

    reg state;
    reg [31:0] data_ram [0:63];
    reg [23:0] tags     [0:15];
    reg        valids   [0:15];

    reg [31:0] miss_addr;
    reg [3:0]  miss_index;
    reg [23:0] miss_tag;
    reg [1:0]  fill_word;
    reg        pending_miss; // first hit after refill is service of a MISS
    integer i;

    wire req_legal = (req_addr[1:0] == 2'b00) &&
                     (req_addr[31:10] == 22'b0);
    wire [3:0]  index = req_addr[7:4];
    wire [1:0]  word  = req_addr[3:2];
    wire [23:0] tag   = req_addr[31:8];
    wire cache_hit = valids[index] && (tags[index] == tag);

    assign hit = (state == STATE_IDLE) && req_legal && cache_hit;
    assign ready = req_valid && (state == STATE_IDLE) &&
                   (!req_legal || cache_hit);
    assign fetch_valid = ready && req_legal;
    assign stall = req_valid && !ready;
    assign inst = fetch_valid ? data_ram[{index, word}] : 32'h00000000;

    assign mem_req = (state == STATE_FILL);
    // The backing ROM is addressed by BYTE addresses. Each line = 16 bytes.
    assign mem_addr = mem_req ? ({miss_addr[31:4], 4'b0000} +
                                 {28'b0, fill_word, 2'b00}) : 32'b0;

    always @(posedge clk) begin
        if (rst) begin
            state        <= STATE_IDLE;
            miss_addr    <= 32'd0;
            miss_index   <= 4'd0;
            miss_tag     <= 24'd0;
            fill_word    <= 2'd0;
            pending_miss <= 1'b0;
            hit_count    <= 32'd0;
            miss_count   <= 32'd0;
            refill_words <= 32'd0;
            for (i = 0; i < 16; i = i + 1) begin
                valids[i] <= 1'b0;
                tags[i]   <= 24'd0;
            end
        end else if (state == STATE_IDLE) begin
            if (req_valid) begin
                if (!req_legal) begin
                    // Invalid fetch: no refill, no instruction to execute.
                    pending_miss <= 1'b0;
                end else if (cache_hit) begin
                    if (!(pending_miss && (req_addr == miss_addr)))
                        hit_count <= hit_count + 32'd1;
                    pending_miss <= 1'b0;
                end else begin
                    miss_count <= miss_count + 32'd1;
                    miss_addr  <= req_addr;
                    miss_index <= index;
                    miss_tag   <= tag;
                    fill_word  <= 2'd0;
                    pending_miss <= 1'b0;
                    // Make line invalid immediately to avoid partial-line hits.
                    valids[index] <= 1'b0;
                    state <= STATE_FILL;
                end
            end
        end else begin
            // State FILL. Backing memory is combinational, so sample at edge.
            // Requests are only launched for legal 1 KiB addresses; all four
            // words of the aligned 16-byte line are then legal, too.
            if (mem_addr_valid) begin
                data_ram[{miss_index, fill_word}] <= mem_rdata;
                refill_words <= refill_words + 32'd1;
                if (fill_word == 2'd3) begin
                    tags[miss_index]   <= miss_tag;
                    valids[miss_index] <= 1'b1;
                    pending_miss <= 1'b1;
                    state <= STATE_IDLE;
                end else begin
                    fill_word <= fill_word + 2'd1;
                end
            end
            // If the memory says the refill address is invalid, remain stalled.
            // In this V0.1 model that cannot happen for a legal request.
        end
    end
endmodule
