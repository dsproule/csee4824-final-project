`include "verilog/sys_defs.svh"

module MAP_TABLE (
    input reset,
    input [4:0] r, r1, r2, retire_r,
    input CDB   cdb,
    input ROB_T T, retire_T,
    
    output MT_ENTRY T1, T2
);
    logic [5:0] reset_idx, cdb_idx;
    MT_ENTRY [4:0] mt_table;

    assign T1 = mt_table[r1];
    assign T2 = mt_table[r2];

    always_comb begin
        if (reset) begin
            for (reset_idx = 0; reset_idx < 32; reset_idx++)
                mt_table[reset_idx] = 0;
        end else begin
            mt_table[r] = (r != 0) ? {T, `FALSE} : 0;

            // commit stage tells mt_table that tag value is in ROB
            for (cdb_idx = 0; cdb_idx < 32; cdb_idx++)
                mt_table[cdb_idx].plus = (cdb.T == mt_table[cdb_idx].T & cdb.valid);

            // clears a tag at the end if it was just retired. (Gives r the chance to rename to new tag if desired)
            if (mt_table[retire_r].T == retire_T)
                mt_table[retire_r] = 0;
        end
    end

endmodule