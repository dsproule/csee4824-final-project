`include "verilog/sys_defs.svh"

// in the name of all that is holy make all sizes powers of two <3
module rob(
    input clock, reset,
    input flush,
    input [4:0] r, 
    input ROB_T T1, T2,
    input CDB cdb,
    input dispatch_valid,

    output ROB_T T,
    output logic full, empty, regfile_write_en,
    output logic [4:0] regfile_write_idx,
    output logic [`XLEN-1:0] V1, V2, regfile_write_data
);
    localparam PTR_WIDTH = $clog2(`ROB_SZ);

    ROB_ENTRY rob_table [`ROB_SZ-1:0];

    /* ONLY WORKS IF SIZE IS POWER OF TWO, BUT MORE EFFICIENT AND SIMPLER LOGIC FOR CONTROL BITS/MULTIPLE ISSUES WHEN WE SUPERSCALAR

        Extra bit in big_head or big_tail acts as a wraparound detector. If the MSB of each is equal, they are on the same "wraparound"
        
        for example:    initialized fifo big_head=big_tail=0, MSBs are equal --> empty
                        allocate SIZE entries big_head={1'b0,0} big_tail={1'b1,0} because of wraparound --> full
                        also tells you which entry is newer

                        ht             h t           h   t           h t           h   t       t  h           th (FULL) 
                        [0 0 0 0] --> [1 0 0 0] --> [1 2 0 0] --> [0 2 0 0] --> [0 2 3 0] --> [0 2 3 4] --> [5 2 3 4] 
                        tail=head=1, but big_tail[MSB] == 1 and big_head[MSB] == 0)
    */

    ROB_T head, tail;
    logic [PTR_WIDTH:0] big_head, big_tail;
    assign head = big_head[PTR_WIDTH-1:0];
    assign tail = big_tail[PTR_WIDTH-1:0];

    //outputs
    assign full = (head == tail) && (big_tail[PTR_WIDTH] != big_head[PTR_WIDTH]);
    assign empty = (big_head == big_tail);
    assign T = tail; //value that gets sent to RS

    // if value isn't in regfiles yet, ok if invalid because map table will MUX values from regfile. 
    assign V1 = rob_table[T1].V;
    assign V2 = rob_table[T2].V;

    always_ff @(posedge clock) begin
        if (reset) begin
            for (int i = 0; i < `ROB_SZ; i++) begin
                rob_table[i] <= 0;
            end
            
            big_tail <= 0;
            big_head <= 0;
            regfile_write_en <= 0;

        end else begin
            // load in cdb value into rob# and mark as Complete (C)
            if (cdb.valid) begin
                rob_table[cdb.T].V <= cdb.V;
                rob_table[cdb.T].ready <= `TRUE;
            end

            // dispatch --> allocate value in ROB
            if (dispatch_valid && !full) begin
                rob_table[tail].r <= r;
                rob_table[tail].V <= 0;
                rob_table[tail].ready <= `FALSE;
                big_tail <= big_tail + 1;
            end

            // commit --> retire head/free rob entry [x], write to regfile [x], clear maptable entry if valid, fkush after this if needed
            if (!empty && rob_table[head].ready) begin
                regfile_write_en <= 1;
                regfile_write_idx <= rob_table[head].r;
                regfile_write_data <= rob_table[head].V;
                big_head <= big_head + 1;
            end else begin
                regfile_write_en <= 0;
            end

            // let head advance if successfully written to reg TODO
            if (flush) begin
                big_tail <= big_head;
                for (int i = 0; i < `ROB_SZ; i++) begin
                    rob_table[i] <= 0;
                end
            end
        end
    end

endmodule