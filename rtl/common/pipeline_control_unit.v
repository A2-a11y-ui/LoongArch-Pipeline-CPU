
module pipeline_control_unit (
    input  wire rst,

    // Qualified redirect event from EX stage
    input  wire branch_redirect,

    // Load-use dependency detected in ID
    input  wire load_use_hazard,

    // IF/ID pipeline register controls
    output reg  ifid_stall,
    output reg  ifid_flush,

    // ID/EX pipeline register control
    output reg  idex_flush,

    // Advisory request for future IF issue control
    output reg  hold_fetch_issue_req
);

    // Priority:
    // Reset > Branch Redirect > Load-use > Normal
    always @(*) begin

        // Defaults: normal pipeline progress
        ifid_stall          = 1'b0;
        ifid_flush          = 1'b0;
        idex_flush          = 1'b0;
        hold_fetch_issue_req = 1'b0;

        if (rst) begin
            // Pipeline registers also receive rst directly
            ifid_flush           = 1'b1;
            idex_flush           = 1'b1;
            hold_fetch_issue_req = 1'b1;
        end

        else if (branch_redirect) begin
            // Kill younger wrong-path instructions
            ifid_flush = 1'b1;
            idex_flush = 1'b1;

            // Do not freeze the branch in EX.
            // The PC/IF controller handles the redirect.
        end

        else if (load_use_hazard) begin
            // Hold the instruction waiting in IF/ID
            ifid_stall = 1'b1;

            // Insert a bubble into ID/EX
            idex_flush = 1'b1;

            // Request to pause issuing new IF requests
            hold_fetch_issue_req = 1'b1;
        end

    end

endmodule
