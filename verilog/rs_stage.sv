`include "verilog/sys_defs.svh"

// Dispatch stage
module RS_ALLOC(
    input             reset,
    input [`RS_SZ-1:0] rs_idx, rs_free,
    input ROB_T       T, 
    input MT_ENTRY    MT_T1, MT_T2,          // from the Map Table     
    input [`XLEN-1:0] V1, V2,
    input CDB         cdb,

    output stall,
    output RS_ENTRY [`RS_SZ-1:0] rs_table
);
    /* 
     * Handles just the Dispatch. Passes values to 
     * RS_VALUE for issue stage.
     * 
     * In here we assume the ROB & Map Table feed the proper values based on the decode stage.
     */

    logic [`RS_SZ:0] reset_idx, cdb_idx;

    assign stall = rs_table[rs_idx].busy;

    always_comb begin
        if (reset) begin
            for (reset_idx = 0; reset_idx < `RS_SZ; reset_idx++)
                rs_table[reset_idx] = 0;
        end else begin
            // checks if RS is free to allocate
            if (~rs_table[rs_idx].busy | rs_free[rs_idx]) begin
                rs_table[rs_idx].busy = `TRUE;
                rs_table[rs_idx].T = T;

                // checks if we can put just the value in or if we need the tag for t1
                if (MT_T1 == 0 | MT_T1.plus) begin
                    // value exists somewhere
                    rs_table[rs_idx].V1 = V1;
                    rs_table[rs_idx].T1 = 0;
                    rs_table[rs_idx].ready[0] = `TRUE;
                end else begin
                    rs_table[rs_idx].T1 = MT_T1.T;
                end

                if (MT_T2 == 0 | MT_T2.plus) begin
                    // value exists somewhere
                    rs_table[rs_idx].V2 = V2;
                    rs_table[rs_idx].T2 = 0;
                    rs_table[rs_idx].ready[1] = `TRUE;
                end else begin
                    rs_table[rs_idx].T2 = MT_T2.T;
                end
                
            end

            // if a CDB line came in 
            if (cdb.valid)
                for (cdb_idx = 0; cdb_idx < `RS_SZ; cdb_idx++) begin
                    if (rs_table[cdb_idx].T1 == cdb.T) begin
                        rs_table[cdb_idx].V1 = cdb.V;
                        rs_table[cdb_idx].T1 = 0;
                        rs_table[cdb_idx].ready[0] = `TRUE;
                    end

                    if (rs_table[cdb_idx].T2 == cdb.T) begin
                        rs_table[cdb_idx].V2 = cdb.V;
                        rs_table[cdb_idx].T2 = 0;
                        rs_table[cdb_idx].ready[1] = `TRUE;
                    end
                end
        end
    end

endmodule   // RS_alloc

// Issue stage
module RS_VALUE(
    input RS_ENTRY    [`RS_SZ-1:0]  rs_table,
    input S_X_PACKET  [`RS_SZ-1:0]  S_X_reg,

    output logic       [`RS_SZ-1:0] rs_free, // used to signal that RS_entry is now freed
    output S_X_PACKET [`RS_SZ-1:0]  S_X_packet
);
    /* 
     *  Reads values from rs_table that has the dispatch and passes them to the s_x_regs when
     *  they are valid to begin computing.
     */

    logic [`RS_SZ:0] s_idx;

    // Issue Stage
    always_comb begin
        for (s_idx = 0; s_idx < `RS_SZ; s_idx++) begin
            if ((rs_table[s_idx].ready == 2'b11) & S_X_reg[s_idx].ready) begin
                S_X_packet[s_idx] = {
                    rs_table[s_idx].T, 
                    rs_table[s_idx].V1, 
                    rs_table[s_idx].V2,
                    rs_table[s_idx].opa_select,
                    rs_table[s_idx].opb_select,
                    rs_table[s_idx].alu_func,
                    `FALSE,                     // ready (reg cannot be overwritten in use)
                    `TRUE                       // go (deploys FUs inside)
                    };
                rs_free[s_idx] = `TRUE;
            end else begin
                rs_free[s_idx] = `FALSE;
            end
        end
    end

endmodule   // RS_VALUE

module RS_STAGE(
    input reset,
    input CDB                       cdb,
    input [`RS_SZ-1:0]              rs_idx,
    input S_X_PACKET   [`RS_SZ-1:0] S_X_reg,
    input ROB_T                     T,                // coming from dispatch
    input MT_ENTRY                  T1, T2,
    input [`XLEN-1:0]               V1, V2,           // uses MT_ENTRY.plus to mux val from regfile or ROB

    output stall_d,                         
    output S_X_PACKET [`RS_SZ-1:0] S_X_packet,
    output RS_ENTRY [ `RS_SZ-1:0] rs_table
);
    logic [`RS_SZ-1:0] free_bus;
    
    // connect alloc with value with cdb
    RS_ALLOC rs_alloc(
        // Inputs
        .reset(reset),
        .rs_idx(rs_idx), .rs_free(free_bus),
        .T(T), .MT_T1(T1), .MT_T2(T2),
        .V1(V1), .V2(V2),
        .cdb(cdb),

        // Outputs
        .stall(stall_d),
        .rs_table(rs_table)
    );

    RS_VALUE rs_value(
        // Input
        .rs_table(rs_table),
        .rs_free(free_bus),
        .S_X_reg(S_X_reg),

        // Output
        .S_X_packet(S_X_packet)
    );

endmodule   // top-level module