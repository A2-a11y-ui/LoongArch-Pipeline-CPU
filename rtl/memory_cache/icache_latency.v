// I-Cache V0.2 for fixed-latency backing-memory performance experiment.
// Does NOT replace validated icache.v V0.1. Explicit mem_ready handshake.
// 16 direct mapped lines, 4 words/line; 256 bytes data.
// address: tag[31:8], index[7:4], word[3:2].
// Hold req_valid and req_addr while stall=1; no abort/flush support yet.
module icache_latency (
    input wire clk,
    input wire rst,
    input wire req_valid,
    input wire [31:0] req_addr,
    output wire [31:0] inst,
    output wire ready,
    output wire fetch_valid,
    output wire stall,
    output wire hit,
    output wire [31:0] mem_addr,
    output wire mem_req,
    input wire mem_ready,
    input wire [31:0] mem_rdata,
    input wire mem_addr_valid,
    output reg [31:0] hit_count,
    output reg [31:0] miss_count,
    output reg [31:0] refill_words
);
    localparam S_IDLE=2'd0, S_SEND=2'd1, S_WAIT=2'd2, S_RESP=2'd3;
    reg [1:0] state;
    reg [31:0] data_ram [0:63];
    reg [23:0] tags [0:15];
    reg valids [0:15];
    reg [31:0] miss_addr;
    reg [3:0] miss_index;
    reg [23:0] miss_tag;
    reg [1:0] fill_word;
    reg refill_error;
    integer i;

    wire legal=(req_addr[1:0] == 2'b00) &&
               (req_addr[31:10] == 22'b0);
    wire [3:0] index = req_addr[7:4];
    wire [1:0] word = req_addr[3:2];
    wire [23:0] tag = req_addr[31:8];
    wire cached = valids[index] && tags[index] == tag;
    assign hit = (state==S_IDLE) && legal && cached;
    assign ready = req_valid && ((state==S_RESP) ||
                       (state==S_IDLE && (!legal || cached)));
    assign fetch_valid = ready && legal && !refill_error;
    assign stall = req_valid && !ready;
    assign inst = fetch_valid ? data_ram[{index,word}] : 32'b0;
    assign mem_req = (state==S_SEND);
    assign mem_addr = (state==S_SEND) ?
                      ({miss_addr[31:4],4'b0} + {28'b0,fill_word,2'b00}) :
                      32'b0;

    always @(posedge clk) begin
        if(rst) begin
            state <= S_IDLE;
            miss_addr <= 0;
            miss_index <= 0;
            miss_tag <= 0;
            fill_word <= 0;
            refill_error <= 0;
            hit_count <= 0;
            miss_count <= 0;
            refill_words <= 0;
            for(i=0;i<16;i=i+1) begin
                valids[i] <= 1'b0;
                tags[i] <= 24'b0;
            end
        end else begin
            case(state)
                S_IDLE: if(req_valid) begin
                    if(!legal) begin
                        refill_error <= 0;
                    end else if(cached) begin
                        hit_count <= hit_count + 1;
                        refill_error <= 0;
                    end else begin
                        miss_count <= miss_count + 1;
                        miss_addr <= req_addr;
                        miss_index <= index;
                        miss_tag <= tag;
                        fill_word <= 0;
                        refill_error <= 0;
                        valids[index] <= 1'b0;
                        state <= S_SEND;
                    end
                end
                S_SEND: state <= S_WAIT;
                S_WAIT: if(mem_ready) begin
                    if(mem_addr_valid) begin
                        data_ram[{miss_index,fill_word}] <= mem_rdata;
                        refill_words <= refill_words + 1;
                        if(fill_word == 2'd3) begin
                            tags[miss_index] <= miss_tag;
                            valids[miss_index] <= 1'b1;
                            state <= S_RESP;
                        end else begin
                            fill_word <= fill_word + 1;
                            state <= S_SEND;
                        end
                    end else begin
                        refill_error <= 1'b1;
                        state <= S_RESP;
                    end
                end
                S_RESP: if(req_valid) begin
                    state <= S_IDLE;
                    refill_error <= 0;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
