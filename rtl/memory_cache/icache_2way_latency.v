// I-Cache V0.3: 256-byte, 2-way set associative, true 1-bit LRU.
// 8 sets x 2 ways x 4 words per line. 16B/line.
// 1KiB backing-memory address range; asynchronous hit response.
// Request contract: keep req_valid=1 and req_addr stable until ready=1;
// completion is consumed on the next rising edge. One outstanding miss.
// No branch-abort/flush, FPGA timing closure or CPU-CPI claim yet.
// Memory contract: mem_req one-cycle pulse; mem_ready single response pulse.
// Compatible with imem_latency.v / Vivado 2019.1 (Verilog-2001).
module icache_2way_latency (
    input  wire        clk,
    input  wire        rst,
    input  wire        req_valid,
    input  wire [31:0] req_addr,
    output wire [31:0] inst,
    output wire        ready,
    output wire        fetch_valid,
    output wire        stall,
    output wire        hit,
    output wire [31:0] mem_addr,
    output wire        mem_req,
    input  wire        mem_ready,
    input  wire [31:0] mem_rdata,
    input  wire        mem_addr_valid,
    output reg  [31:0] hit_count,
    output reg  [31:0] miss_count,
    output reg  [31:0] refill_words
);
    localparam [1:0] S_IDLE=2'd0, S_SEND=2'd1,
                     S_WAIT=2'd2, S_RESP=2'd3;

    reg [1:0] state;
    reg [31:0] lines [0:63]; // address={way[0],set[2:0],word[1:0]}
    reg [24:0] tag_way0 [0:7];
    reg [24:0] tag_way1 [0:7];
    reg valid_way0 [0:7];
    reg valid_way1 [0:7];
    reg lru_victim [0:7]; // when both valid, indicates next victim way

    wire legal = (req_addr[1:0] == 2'b00) &&
                 (req_addr[31:10] == 22'b0);
    wire [2:0] set_idx = req_addr[6:4];
    wire [1:0] word_idx = req_addr[3:2];
    wire [24:0] req_tag = req_addr[31:7];
    wire way0_hit = valid_way0[set_idx] && tag_way0[set_idx] == req_tag;
    wire way1_hit = valid_way1[set_idx] && tag_way1[set_idx] == req_tag;
    wire cache_hit = way0_hit || way1_hit;
    wire hit_way = !way0_hit && way1_hit;
    wire choose_victim = !valid_way0[set_idx] ? 1'b0 :
                         !valid_way1[set_idx] ? 1'b1 :
                         lru_victim[set_idx];

    reg [31:0] miss_addr;
    reg [2:0] miss_set;
    reg [24:0] miss_tag;
    reg victim_way;
    reg [1:0] fill_word;
    reg refill_error;
    integer i;

    assign hit = (state == S_IDLE) && req_valid && legal && cache_hit;
    assign ready = req_valid && (
                       (state == S_RESP) ||
                       (state == S_IDLE && (!legal || cache_hit))
                   );
    assign fetch_valid = ready && legal && !refill_error;
    assign stall = req_valid && !ready;
    assign inst = !fetch_valid ? 32'b0 :
                  (state == S_RESP) ? lines[{victim_way, miss_set, miss_addr[3:2]}] :
                  lines[{hit_way, set_idx, word_idx}];
    assign mem_req = (state == S_SEND);
    assign mem_addr = (state == S_SEND) ?
                      ({miss_addr[31:4], 4'b0} + {28'b0,fill_word,2'b00}) :
                      32'b0;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            miss_addr <= 32'b0;
            miss_set <= 3'b0;
            miss_tag <= 25'b0;
            victim_way <= 1'b0;
            fill_word <= 2'b0;
            refill_error <= 1'b0;
            hit_count <= 32'b0;
            miss_count <= 32'b0;
            refill_words <= 32'b0;
            for (i=0; i<8; i=i+1) begin
                tag_way0[i] <= 25'b0;
                tag_way1[i] <= 25'b0;
                valid_way0[i] <= 1'b0;
                valid_way1[i] <= 1'b0;
                lru_victim[i] <= 1'b0;
            end
        end else begin
            case (state)
                S_IDLE: if (req_valid) begin
                    if (!legal) begin
                        refill_error <= 1'b0;
                    end else if (cache_hit) begin
                        hit_count <= hit_count + 32'd1;
                        lru_victim[set_idx] <= !hit_way; // other way becomes LRU
                        refill_error <= 1'b0;
                    end else begin
                        miss_count <= miss_count + 32'd1;
                        miss_addr <= req_addr;
                        miss_set <= set_idx;
                        miss_tag <= req_tag;
                        victim_way <= choose_victim;
                        fill_word <= 2'b0;
                        refill_error <= 1'b0;
                        // Do not expose a partly filled line as a valid hit.
                        if (choose_victim == 1'b0)
                            valid_way0[set_idx] <= 1'b0;
                        else
                            valid_way1[set_idx] <= 1'b0;
                        state <= S_SEND;
                    end
                end
                S_SEND: state <= S_WAIT;
                S_WAIT: if (mem_ready) begin
                    if (mem_addr_valid) begin
                        lines[{victim_way, miss_set, fill_word}] <= mem_rdata;
                        refill_words <= refill_words + 32'd1;
                        if (fill_word == 2'd3) begin
                            if (victim_way == 1'b0) begin
                                tag_way0[miss_set] <= miss_tag;
                                valid_way0[miss_set] <= 1'b1;
                            end else begin
                                tag_way1[miss_set] <= miss_tag;
                                valid_way1[miss_set] <= 1'b1;
                            end
                            lru_victim[miss_set] <= !victim_way;
                            state <= S_RESP;
                        end else begin
                            fill_word <= fill_word + 2'd1;
                            state <= S_SEND;
                        end
                    end else begin
                        refill_error <= 1'b1;
                        state <= S_RESP;
                    end
                end
                S_RESP: if (req_valid) begin
                    state <= S_IDLE;
                    refill_error <= 1'b0;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
