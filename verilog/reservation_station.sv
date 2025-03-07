`include "verilog/sys_defs.svh"

module reservation_station(
    input                        clock, reset,
    input CDB                    cdb,
    input RS_ENTRY               rs_cmd,              // from decode stage to populate RS
    input [$clog2(RS_SZ):0]      rs_alloc_idx,

    output                       rs_alloc_valid,
    output [RS_SZ-1:0]           rs_entry_ready,
    output [`XLEN:0] [RS_SZ-1:0] rs_entry_values
);
    RS_ENTRY [RS_SZ-1:0] rs_table;
    logic [RS_SZ:0] reset_ent_idx;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            for (reset_ent_idx = 0; reset_ent_idx < RS_SZ; reset_ent_idx++)
                rs_table[reset_ent_idx] <= 0;
        end
    end

endmodule