`include "verilog/sys_defs.svh"

module MAP_TABLE (
    input clock, reset,
    input [4:0] r, r1, r2, retire_r,
    input CDB   cdb,
    input ROB_T T, retire_T,
    
    output MT_ENTRY T1, T2,
    MT_ENTRY mt_table [31:0]
);
    logic [5:0] reset_idx, cdb_idx;

    // forwards signal that rob has value present if cdb collides
    assign T1 = (cdb.valid & (cdb.T == mt_table[r1].T)) ?  {mt_table[r1].T, `TRUE} : mt_table[r1];
    assign T2 = (cdb.valid & (cdb.T == mt_table[r2].T)) ?  {mt_table[r2].T, `TRUE} : mt_table[r2];

    always_ff @(posedge clock) begin
        if (reset) begin
            for (reset_idx = 0; reset_idx < 32; reset_idx++)
                mt_table[reset_idx] <= 0;
        end else begin
            mt_table[r] <= (r != 0) ? {T, `FALSE} : 0;

            // clears a tag if its not being reassigned
            if ((mt_table[retire_r].T == retire_T) & (retire_r != r))
                mt_table[retire_r] <= 0;

            // checks whole map table and assigns plus if == cdb_tag (in theory only one)
            for (cdb_idx = 0; cdb_idx < 32; cdb_idx++)
                mt_table[cdb_idx].plus <= (cdb.T == mt_table[cdb_idx].T & cdb.valid);

        end
    end

endmodule