`timescale 1ns / 1ps
// V0.7-MEM independent unit test for dmem_latency.
// Vivado 2019.1: add this file and dmem_latency.v to Simulation Sources,
// then set tb_dmem_latency as the simulation top.

module tb_dmem_latency;

    localparam integer READ_LATENCY  = 3;
    localparam integer WRITE_LATENCY = 4;

    reg clk;
    reg rst;

    reg req_valid;
    wire req_ready;
    reg req_write;
    reg [31:0] req_addr;
    reg [31:0] req_wdata;

    wire resp_valid;
    reg resp_ready;
    wire [31:0] resp_rdata;
    wire resp_error;

    integer checks;
    integer errors;
    integer accepted_requests;
    integer consumed_responses;
    integer store_commit_events;
    integer timeout_count;
    integer i;

    reg accepted;
    reg [31:0] held_rdata;
    reg held_error;

    dmem_latency #(
        .READ_LATENCY(READ_LATENCY),
        .WRITE_LATENCY(WRITE_LATENCY),
        .WORDS(256),
        .INIT_FILE("")
    ) dut (
        .clk(clk),
        .rst(rst),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_write(req_write),
        .req_addr(req_addr),
        .req_wdata(req_wdata),
        .resp_valid(resp_valid),
        .resp_ready(resp_ready),
        .resp_rdata(resp_rdata),
        .resp_error(resp_error)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst) begin
            if (req_valid && req_ready)
                accepted_requests = accepted_requests + 1;

            if (resp_valid && resp_ready)
                consumed_responses = consumed_responses + 1;

            if (dut.store_commit_fire)
                store_commit_events = store_commit_events + 1;
        end
    end

    task check;
        input condition;
        input [8*120-1:0] message;
        begin
            checks = checks + 1;
            if (condition !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL [%0d] @%0t: %0s", checks, $time, message);
            end
        end
    endtask

    task issue_request;
        input write_enable;
        input [31:0] address;
        input [31:0] write_data;
        integer local_timeout;
        begin
            @(negedge clk);
            req_valid = 1'b1;
            req_write = write_enable;
            req_addr  = address;
            req_wdata = write_data;

            local_timeout = 0;
            accepted = 1'b0;

            while ((accepted == 1'b0) && (local_timeout < 40)) begin
                @(posedge clk);
                if (req_valid && req_ready) begin
                    accepted = 1'b1;
                    #1 req_valid = 1'b0;
                end else begin
                    #1 local_timeout = local_timeout + 1;
                end
            end

            check(accepted == 1'b1, "request handshake completes within timeout");
            check(req_valid == 1'b0, "request valid is withdrawn only after acceptance");
        end
    endtask

    task wait_response;
        integer local_timeout;
        begin
            local_timeout = 0;
            while ((resp_valid !== 1'b1) && (local_timeout < 60)) begin
                @(negedge clk);
                local_timeout = local_timeout + 1;
            end
            check(resp_valid === 1'b1, "response arrives within timeout");
        end
    endtask

    task consume_response;
        begin
            @(negedge clk);
            resp_ready = 1'b1;
            @(posedge clk);
            check(resp_valid === 1'b1 && resp_ready === 1'b1,
                  "response is consumed on valid/ready handshake");
            #1;
            resp_ready = 1'b0;
            check(resp_valid === 1'b0, "response valid clears after handshake");
        end
    endtask

    initial begin
        rst = 1'b1;
        req_valid = 1'b0;
        req_write = 1'b0;
        req_addr = 32'd0;
        req_wdata = 32'd0;
        resp_ready = 1'b0;

        checks = 0;
        errors = 0;
        accepted_requests = 0;
        consumed_responses = 0;
        store_commit_events = 0;
        accepted = 1'b0;
        held_rdata = 32'd0;
        held_error = 1'b0;

       repeat (2) @(posedge clk);
       #1 rst = 1'b0;

// 等待 DUT 连续赋值信号完成更新
       #1;

       check(req_ready === 1'b1, "memory is ready after reset");
       check(resp_valid === 1'b0, "no response is pending after reset");

        // CASE 1: Load response appears exactly READ_LATENCY edges after req_fire.
        issue_request(1'b0, 32'd0, 32'd0);

        for (i = 1; i < READ_LATENCY; i = i + 1) begin
            @(posedge clk);
            #1 check(resp_valid === 1'b0,
                     "Load response is not early");
        end

        @(posedge clk);
        #1;
        check(resp_valid === 1'b1, "Load response appears at configured latency");
        check(resp_error === 1'b0, "valid Load has no error");
        check(resp_rdata === 32'd0, "initialized RAM word reads as zero");
        check(req_ready === 1'b0, "new request is blocked while response is pending");

        // CASE 2: Hold a response while a second request waits at the input.
        held_rdata = resp_rdata;
        held_error = resp_error;

        @(negedge clk);
        req_valid = 1'b1;
        req_write = 1'b0;
        req_addr = 32'd4;
        req_wdata = 32'd0;

        repeat (3) begin
            @(posedge clk);
            #1;
            check(resp_valid === 1'b1, "response remains valid under backpressure");
            check(resp_rdata === held_rdata && resp_error === held_error,
                  "response payload remains stable under backpressure");
            check(req_ready === 1'b0, "second request is blocked by outstanding response");
            check(req_valid === 1'b1 && req_addr === 32'd4,
                  "blocked request payload remains stable");
        end

        @(negedge clk);
        resp_ready = 1'b1;
        @(posedge clk);
        check(resp_valid === 1'b1 && resp_ready === 1'b1,
              "first response handshake succeeds");
        #1;
        resp_ready = 1'b0;
        check(resp_valid === 1'b0, "first response is cleared");
        check(req_ready === 1'b1 && req_valid === 1'b1,
              "waiting request becomes eligible after response consumption");

        @(posedge clk);
        check(req_valid === 1'b1 && req_ready === 1'b1,
              "waiting request is accepted exactly once");
        #1 req_valid = 1'b0;
        wait_response;
        check(resp_error === 1'b0 && resp_rdata === 32'd0,
              "second Load returns expected zero data");
        consume_response;

        // CASE 3: Store response uses the same channel. Store commits on resp_fire.
        issue_request(1'b1, 32'd8, 32'hCAFEBABE);
        for (i = 1; i < WRITE_LATENCY; i = i + 1) begin
            @(posedge clk);
            #1 check(resp_valid === 1'b0,
                     "Store response is not early");
        end
        @(posedge clk);
        #1;
        check(resp_valid === 1'b1,
              "Store response appears at configured write latency");
        check(resp_error === 1'b0, "valid Store acknowledgement has no error");
        check(resp_rdata === 32'd0, "Store response data is not used");
        check(dut.mem[2] === 32'd0,
              "Store has no side effect before response handshake");
        check(store_commit_events == 0,
              "Store commit has not occurred before response handshake");

        held_rdata = resp_rdata;
        held_error = resp_error;
        repeat (3) begin
            @(posedge clk);
            #1;
            check(resp_valid === 1'b1, "Store acknowledgement remains pending");
            check(resp_rdata === held_rdata && resp_error === held_error,
                  "Store response payload remains stable");
            check(store_commit_events == 0,
                  "Store side effect is not repeated or early during backpressure");
            check(dut.mem[2] === 32'd0,
                  "RAM remains unchanged until Store response handshake");
        end

        consume_response;
        check(store_commit_events == 1, "Store commits exactly once on resp_fire");
        check(dut.mem[2] === 32'hCAFEBABE, "Store updates the addressed RAM word");

        // CASE 4: Load-after-Store observes the committed value.
        issue_request(1'b0, 32'd8, 32'd0);
        wait_response;
        check(resp_error === 1'b0, "readback has no error");
        check(resp_rdata === 32'hCAFEBABE, "readback returns the stored value");
        consume_response;

        // CASE 5: Unaligned Load returns a stable error response.
        issue_request(1'b0, 32'd3, 32'd0);
        wait_response;
        check(resp_error === 1'b1, "unaligned access reports an error");
        check(resp_rdata === 32'd0, "errored access returns deterministic zero data");
        held_rdata = resp_rdata;
        held_error = resp_error;
        repeat (2) begin
            @(posedge clk);
            #1;
            check(resp_valid === 1'b1, "error response remains pending");
            check(resp_rdata === held_rdata && resp_error === held_error,
                  "error response payload remains stable");
        end
        consume_response;

        // CASE 6: Out-of-range Store reports error and never writes RAM.
        issue_request(1'b1, 32'd1024, 32'hDEADBEEF);
        wait_response;
        check(resp_error === 1'b1, "out-of-range Store reports an error");
        check(store_commit_events == 1, "invalid Store causes no commit event");
        check(dut.mem[2] === 32'hCAFEBABE,
              "invalid Store does not corrupt a valid RAM word");
        consume_response;
        check(store_commit_events == 1, "errored Store still causes no side effect");

        // CASE 7: Reset while a valid Store response is pending.
        // Since the Store has not reached resp_fire, reset must abort it
        // without changing RAM or generating a Store commit event.
        issue_request(1'b1, 32'd12, 32'hDEADC0DE);
        wait_response;
        check(resp_error === 1'b0, "pending valid Store response has no error");
        check(dut.mem[3] === 32'd0,
              "pending Store has not changed RAM before resp_fire");
        check(store_commit_events == 1,
              "pending Store has not generated a commit event");
        @(negedge clk);
        rst = 1'b1;
        @(posedge clk);
        #1;
        check(resp_valid === 1'b0, "reset aborts pending Store response");
        check(dut.mem[3] === 32'd0,
              "reset-aborted Store has no memory side effect");
        check(store_commit_events == 1,
              "reset-aborted Store does not commit");
        @(negedge clk);
        rst = 1'b0;
        #1;
        check(req_ready === 1'b1, "request interface recovers after Store abort");

        // CASE 8: Reset aborts an accepted but not yet completed Load.
        issue_request(1'b0, 32'd8, 32'd0);
        @(negedge clk);
        rst = 1'b1;
        @(posedge clk);
        #1;
        check(resp_valid === 1'b0, "reset aborts the outstanding Load");
        check(req_ready === 1'b0, "request interface is disabled during reset");
        @(negedge clk);
        rst = 1'b0;
        #1;
        check(req_ready === 1'b1, "request interface recovers after reset");
        check(resp_valid === 1'b0, "aborted Load produces no late response");
        check(dut.mem[2] === 32'hCAFEBABE,
              "reset does not erase previously committed RAM contents");

        check(accepted_requests == 8, "eight requests were accepted");
        check(consumed_responses == 6, "six responses consumed; two requests reset-aborted");
        check(store_commit_events == 1, "exactly one valid Store side effect occurred");
        check(resp_valid === 1'b0 && req_ready === 1'b1,
              "memory finishes idle with no pending response");

        $display("------------------------------------------------");
        $display("V0.7-MEM MULTI-CYCLE DATA MEMORY UNIT TEST");
        $display("READ_LATENCY = %0d, WRITE_LATENCY = %0d",
                 READ_LATENCY, WRITE_LATENCY);
        $display("Total checks = %0d", checks);
        $display("Total errors = %0d", errors);
        $display("Accepted requests = %0d", accepted_requests);
        $display("Consumed responses = %0d", consumed_responses);
        $display("Reset-aborted requests = %0d", accepted_requests-consumed_responses);
        $display("Store commit events = %0d", store_commit_events);

        if (errors == 0 &&
            accepted_requests == 8 &&
            consumed_responses == 6 &&
            store_commit_events == 1)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED");
        $display("------------------------------------------------");
        $finish;
    end

    initial begin
        #10000;
        $display("FATAL TIMEOUT: V0.7-MEM unit test did not finish");
        $finish;
    end

endmodule
