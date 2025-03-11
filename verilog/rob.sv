`include "verilog/sys_defs.svh"

module ROB(
    input clock, reset,
    input [4:0] r, r1, r2,
    input CDB cdb,
    input dispatch_valid,

    output ROB_T T,
    output full, empty, regfile_write_en,
    output [4:0] regfile_write_idx,
    output [`XLEN-1:0] V1, V2, regfile_write_data,
);
    logic [$clog2(`ROB_SZ)-1:0] next_tail, next_head, tail, head;
    logic [$clog2(`ROB_SZ):0] reset_idx;

    ROB_ENTRY [ROB_SZ-1:0] rob_table;

    // wraparound logic for incrementing pointers
    assign next_tail = (full & ~dispatch_valid) ? tail : 
                       (`ROB_SZ - 1 == tail)    ? 0 : tail + 1;

    assign next_head = (empty & ~rob_table[head].ready) ? head :
                       (`ROB_SZ - 1 == head)            ? 0 : head + 1;

    // if value isn't in regfiles yet, ok if invalid because map table will MUX values from regfile
    assign V1 = rob_table[r1];
    assign V2 = rob_table[r2];

    always_ff @(posedge clock) begin
        if (cdb.valid) begin
            rob_table[cdb.T]       <=  cdb.V;
            rob_table[cdb.T].ready <= `TRUE;
        end

        if (reset) begin
            for (reset_idx = 0; reset_idx < `ROB_SZ; reset_idx++)
                rob_table[reset_idx] <= 0;

            tail <= 0;
            head <= 0;
        end else begin

            // dispatch
            if (dispatch_valid & ~full) begin
                rob_table[tail].r <= r;
                rob_table[tail].V <= 0;
                rob_table[tail].ready <= `FALSE;
            end

            // commit
            if (head != next_head) begin
                regfile_write_en <= 1;
                regfile_write_idx <= rob_table[head].r;
                regfile_write_data <= rob_table[head].V;
            end else 
                regfile_write_en <= 0;

            // setting wraparound status
            full <= (next_tail == next_head) & (tail != next_tail);
            empty <= (next_head == next_tail) & (head != next_head);

            tail <= next_tail;
            head <= next_head;
        end
    end

endmodule