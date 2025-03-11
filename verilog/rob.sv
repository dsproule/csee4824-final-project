`include "verilog/sys_defs.svh"

module ROB(
    input clock, reset,
    input [4:0] r,
    input dispatch_valid, commit_valid,         // commit happening, dispatch happening

    output ROB_T T,
    output full, empty
);
    logic [$clog2(`ROB_SZ)-1:0] next_tail, next_head, tail, head;
    logic [$clog2(`ROB_SZ):0] reset_idx;

    ROB_ENTRY [ROB_SZ-1:0] rob_table;

    // wraparound logic for incrementing pointers
    assign next_tail = (full & ~dispatch_valid) ? tail : 
                       (`ROB_SZ - 1 == tail) ? 0 : tail + 1;

    assign next_head = (empty & ~commit_valid) ? head : 
                       (`ROB_SZ - 1 == head) ? 0 : head + 1;

    always_ff @(posedge clock) begin
        if (reset) begin
            for (reset_idx = 0; reset_idx < `ROB_SZ; reset_idx++)
                rob_table[reset_idx] <= 0;

            tail <= 0;
            head <= 0;
        end else begin
            // set tail before it changes
            rob_table[tail] <= r;

            // CDB LINE HANDLE
            // WRITE head TO REGFILE if changing (commiting)

            // setting wraparound status
            full <= (next_tail == next_head) & (tail != next_tail);
            empty <= (next_head == next_tail) & (head != next_head);

            tail <= next_tail;
            head <= next_head;
        end
    end

endmodule