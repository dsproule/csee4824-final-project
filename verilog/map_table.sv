`include "verilog/sys_defs.svh"

module MAP_TABLE (
    input MT_ENTRY MT_in
    input MT_req, MT_write

    output MT_valid;
    output MT_ENTRY MT_out;
);
    /* 
     * No longer cooperates with RS. Needs to be fixed. Needs multiple lines at a minimum but
     * also should handle the logic for pulling data from regfile vs ROB
     */
     MT_ENTRY [4:0] mt_table;

     always_comb begin
        if (mt_write) begin
            mt_table[MT_in.reg] = MT_in;
            MT_valid = `FALSE;
        end else if (mt_req) begin
            MT_out = mt_table[MT_in.reg]
            MT_valid = `TRUE;
        end
     end

endmodule