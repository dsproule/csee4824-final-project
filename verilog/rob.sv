`include "verilog/sys_defs.svh"

// in the name of all that is holy make all sizes powers of two <3
module rob(
    input clock, reset,
    input [4:0] r, 
    input ROB_T T1, T2,
    input CDB cdb,
    input dispatch_valid,

    output ROB_T T,
    output PPL_CTRL ppl_ctrl,
    output logic full, empty, retire,
    output logic [4:0] regfile_write_idx, 
    output logic [`XLEN-1:0] V1, V2, regfile_write_data,
    output logic [($bits(ROB_ENTRY)*`ROB_SZ)-1:0] rob_table_out
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

    always_comb begin
        for (int i = 0; i < `ROB_SZ; i++) begin
            rob_table_out[i * $bits(ROB_ENTRY) +: $bits(ROB_ENTRY)] = rob_table[i];
        end
    end

    /* always_comb begin
        if (cdb.valid) begin
            $display("DEBUG UPDATE: ROB[%d] -> Ready: %b, Value: %d", 
                    cdb.T, rob_table[cdb.T].ready, rob_table[cdb.T].V);
        end
    end */

    always_ff @(posedge clock) begin
        if (reset) begin
            for (int i = 0; i < `ROB_SZ; i++) begin
                rob_table[i] <= 0;
            end
            big_tail <= 0;
            big_head <= 0;
            retire <= 0;
        end else begin
            // load in cdb value into rob# and mark as Complete (C) --> deals with all types of instructions
            if (cdb.valid) begin
                //$display("DEBUG: CDB Write - Target ROB[%d], Value = %d, Valid = %b", cdb.T, cdb.V, cdb.valid);
                rob_table[cdb.T].V <= cdb.V;
                rob_table[cdb.T].ppl_ctrl <= cdb.ppl_ctrl;
                rob_table[cdb.T].ready <= `TRUE;
            end

            // dispatch --> allocate value in ROB
            if (dispatch_valid && !full) begin
                //$display("Dispatching: ROB[%d] with Dest Reg %d", tail, r);  // Debug print
                rob_table[tail] <= 0;
                rob_table[tail].r <= r;
                big_tail <= big_tail + 1;
            end

            // commit --> retire head/free rob entry [x], write to regfile [x], clear maptable entry if valid, fkush after this if needed
            if (!empty && rob_table[head].ready) begin
                //$display("Committing ROB[%d]: Reg %d <- %d", head, rob_table[head].r, rob_table[head].V);  // Debug print
                retire <= 1;
                regfile_write_idx <= rob_table[head].r;
                regfile_write_data <= rob_table[head].V;
                ppl_ctrl <= rob_table[head].ppl_ctrl;

                big_head <= big_head + 1;

                if (rob_table[head].ppl_ctrl) begin //FLUSH
                    for (int i = 0; i < `ROB_SZ; i++) begin
                        rob_table[i] <= 0;  
                    end
                    big_head <= 0;  // flushing zeros out the head/tail --> empty
                    big_tail <= 0; 
                end
            end else begin
                retire <= 0;
            end
        end
    end

endmodule