`include "verilog/sys_defs.svh"

module map_table (
    input clock, reset, en,
    input [4:0] r, r1, r2, retire_r,
    input CDB   cdb,
    input ROB_T T, retire_T,
    
    output MT_ENTRY T1, T2,
    MT_ENTRY mt_table [31:0]
);
    logic [5:0] reset_idx, cdb_idx;
    logic retire_entry;

    MT_ENTRY next_T1, next_T2;

    assign retire_entry = (mt_table[retire_r].T == retire_T) && (retire_r != r);

    // forwards signal that rob has value present if cdb collides
    always_comb begin
        next_T1 = 0;
        next_T1 = 0;
        
        //functionally conditionals should never both be true
        next_T1 = (cdb.valid && (cdb.T == mt_table[r1].T)) ? {mt_table[r1].T, `TRUE} : mt_table[r1]; //functionally conditionals should never both be true
        next_T2 = (cdb.valid && (cdb.T == mt_table[r2].T)) ? {mt_table[r2].T, `TRUE} : mt_table[r2];

        if (retire_entry && (retire_r == r1)) 
            next_T1 = 0;
        if (retire_entry && (retire_r == r2)) 
            next_T2 = 0;

    end
    

    always_ff @(posedge clock) begin
        if (reset) begin
            for (reset_idx = 0; reset_idx < 32; reset_idx++)
                mt_table[reset_idx] <= 0;
        end else (en) begin
            mt_table[r] <= (r != 0) ? {T, `FALSE} : 0;
            T1 <= next_T1;
            T2 <= next_T2;

            // clears a tag if its not being reassigned
            if (retire_entry)
                mt_table[retire_r] <= 0;

            // checks whole map table and assigns plus if == cdb_tag (in theory only one)
            for (cdb_idx = 0; cdb_idx < 32; cdb_idx++)
                mt_table[cdb_idx].plus <= (cdb.T == mt_table[cdb_idx].T & cdb.valid);
        end
    end

endmodule