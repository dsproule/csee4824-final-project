`include "verilog/sys_defs.svh"

// in the name of all that is holy make all sizes powers of two <3
module rob(
    input clock, reset,
    input [4:0] r, 
    input ROB_T T1, T2,
    input CDB cdb,
    input dispatch_valid,
    input logic [`XLEN-1:0] NPC,                // used for wb

    output ROB_T T, retire_T_out,
    output PPLN_CTRL ppln_ctrl,
    output logic full, empty, retire,
    output logic [4:0] regfile_write_idx_out, 
    output logic [`XLEN-1:0] V1, V2, regfile_write_data,
    output logic [($bits(ROB_ENTRY)*`ROB_SZ)-1:0] rob_table_out,
    output ROB_T head, tail,
    output logic [`XLEN-1:0] commit_NPC
);
    localparam PTR_WIDTH = $clog2(`ROB_SZ);

    ROB_ENTRY rob_table [`ROB_SZ:1];
    
    ROB_T retire_T;
    logic [4:0] regfile_write_idx;

    assign retire_T_out = (retire) ? retire_T : 0;
    assign regfile_write_idx_out = (retire) ? regfile_write_idx : 0;

    assign commit_NPC = rob_table[head].NPC;

    /* ONLY WORKS IF SIZE IS POWER OF TWO, BUT MORE EFFICIENT AND SIMPLER LOGIC FOR CONTROL BITS/MULTIPLE ISSUES WHEN WE SUPERSCALAR

        Extra bit in big_head or big_tail acts as a wraparound detector. If the MSB of each is equal, they are on the same "wraparound"
        
        for example:    initialized fifo big_head=big_tail=0, MSBs are equal --> empty
                        allocate SIZE entries big_head={1'b0,0} big_tail={1'b1,0} because of wraparound --> full
                        also tells you which entry is newer

                        ht             h t           h   t           h t           h   t       t  h           th (FULL) 
                        [0 0 0 0] --> [1 0 0 0] --> [1 2 0 0] --> [0 2 0 0] --> [0 2 3 0] --> [0 2 3 4] --> [5 2 3 4] 
                        tail=head=1, but big_tail[MSB] == 1 and big_head[MSB] == 0)
    */

    logic head_wrap, tail_wrap;

    // logic [PTR_WIDTH:0] big_head, big_tail;
    // assign head = big_head[PTR_WIDTH-1:0];
    // assign tail = big_tail[PTR_WIDTH-1:0];

    //outputs // change here
    assign full = (head == tail) && (head_wrap != tail_wrap);
    assign empty = (head == tail) && (head_wrap == tail_wrap);
    // assign T = tail; //value that gets sent to RS

    // if value isn't in regfiles yet, ok if invalid because map table will MUX values from regfile. 
    assign V1 = (cdb.valid && cdb.T == T1) ? cdb.V : rob_table[T1].V;
    assign V2 = (cdb.valid && cdb.T == T2) ? cdb.V : rob_table[T2].V;

    always_comb begin
        for (int i = 0; i < `ROB_SZ; i++) begin
            rob_table_out[i * $bits(ROB_ENTRY) +: $bits(ROB_ENTRY)] = rob_table[i+1];
        end
        T = dispatch_valid ? tail : 0; // change here
    end

    /* always_comb begin
        if (cdb.valid) begin
            $display("DEBUG UPDATE: ROB[%d] -> Ready: %b, Value: %d", 
                    cdb.T, rob_table[cdb.T].ready, rob_table[cdb.T].V);
        end
    end */

    always_ff @(posedge clock) begin
        if (reset) begin
            for (int i = 1; i <= `ROB_SZ; i++) begin
                rob_table[i] <= 0;
            end
            tail <= 1;
            head <= 1;
            retire <= 0;
            retire_T <= 0;
            regfile_write_idx <= 0;
            regfile_write_data <= 0;
            ppln_ctrl <= 0;
            head_wrap <= 0; // change here
            tail_wrap <= 0;

        end else begin
            // load in cdb value into rob# and mark as Complete (C) --> deals with all types of instructions
            if (cdb.valid) begin
                //$display("DEBUG: CDB Write - Target ROB[%d], Value = %d, Valid = %b", cdb.T, cdb.V, cdb.valid);
                rob_table[cdb.T].V <= cdb.V;
                rob_table[cdb.T].ppln_ctrl <= cdb.ppln_ctrl;
                rob_table[cdb.T].ready <= `TRUE;
            end

            // dispatch --> allocate value in ROB
            if (dispatch_valid && !full) begin
                //$display("Dispatching: ROB[%d] with Dest Reg %d", tail, r);  // Debug print
                rob_table[tail] <= 0;
                rob_table[tail].r <= r;
                rob_table[tail].NPC <= NPC;
                tail <= (tail == `ROB_SZ - 1) ? 1 : (tail + 1);
                tail_wrap <= (tail == `ROB_SZ - 1) ? ~tail_wrap : tail_wrap; // change here
            end

            // commit --> retire head/free rob entry [x], write to regfile [x], clear maptable entry if valid, fkush after this if needed
            if (!empty && rob_table[head].ready) begin
                //$display("Committing ROB[%d]: Reg %d <- %d", head, rob_table[head].r, rob_table[head].V);  // Debug print
                retire <= 1;
                regfile_write_idx <= rob_table[head].r; 
                regfile_write_data <= rob_table[head].V; 
                ppln_ctrl <= rob_table[head].ppln_ctrl;
                rob_table[head] <= 0;

                retire_T <= head;
                head <= (head == `ROB_SZ - 1) ? 1 : head + 1; // change here
                head_wrap <= (head == `ROB_SZ - 1) ? ~head_wrap : head_wrap; // change here

                if (rob_table[head].ppln_ctrl.flush) begin //FLUSH
                    for (int i = 1; i <= `ROB_SZ; i++) begin
                        rob_table[i] <= 0;  
                    end
                    head <= 1;  // flushing zeros out the head/tail --> empty
                    tail <= 1; 
                end
            end else begin
                retire <= 0;
            end
        end
    end

endmodule