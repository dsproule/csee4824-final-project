`include "verilog/sys_defs.svh"

// `define USE_D_S_REG

// Dispatch stage (fully combinational)
module RS_ALLOC(
    input              clock, reset, en,
    input logic [`RS_SZ-1:0]       rs_idx, rs_free,
    input ROB_T        T, 
    input MT_ENTRY     MT_T1, MT_T2,          // from the Map Table     
    input [`XLEN-1:0]  V1, V2,
    input CDB          cdb,

    output stall,
    output logic [`RS_SZ-1:0] busy,
    output RS_ENTRY [`RS_SZ-1:0] rs_table
);
    /* 
     * Handles just the Dispatch. Passes values to 
     * RS_VALUE for issue stage.
     * 
     * In here we assume the ROB & Map Table feed the proper values based on the decode stage.
     */

    logic [$clog2(`RS_SZ):0] reset_idx, cdb_idx, rs_free_idx, busy_reset_idx;

    assign stall = busy[rs_idx];

    always_ff @(posedge clock) begin
        if (reset) begin
            for (busy_reset_idx = 0; busy_reset_idx < `RS_SZ; busy_reset_idx++)
                busy[busy_reset_idx] <= `FALSE;
        end else if (en) begin  
            // busy handling. Isolated 
            for (busy_reset_idx = 0; busy_reset_idx < `RS_SZ; busy_reset_idx++)
                if ((rs_idx != busy_reset_idx) & (rs_free[busy_reset_idx]))
                    busy[busy_reset_idx] <= `FALSE;
            busy[rs_idx] <= `TRUE;
        end
    end

    always_comb begin
        if (reset) begin
            for (reset_idx = 0; reset_idx < `RS_SZ; reset_idx++)
                rs_table[reset_idx] = 0;
        end else if (en) begin
            // checks if RS is free to allocate
            if (~busy[rs_idx] | rs_free[rs_idx]) begin
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

                // change these to LD/ST in pipeline. Like this for the tbs
                if (MT_T2 == 0 | MT_T2.plus) begin
                    // value exists somewhere
                    rs_table[rs_idx].V2 = V2;
                    rs_table[rs_idx].T2 = 0;
                    rs_table[rs_idx].ready[1] = `TRUE;
                end else begin
                    rs_table[rs_idx].T2 = MT_T2.T;
                end
                
            end

            // free a line that isn't about to be allocated (should be handled by above)
            for (rs_free_idx = 0; rs_free_idx < `RS_SZ; rs_free_idx++)
                if ((rs_free_idx != rs_idx) & (rs_free[rs_free_idx]))
                    rs_table[rs_free_idx] = 0;

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

// Issue stage (clocked)
module RS_VALUE(
    input                          clock, reset, en,
`ifdef USE_D_S_REG
    input D_S_PACKET  [`RS_SZ-1:0] D_S_reg,
`else
    input RS_ENTRY [`RS_SZ-1:0] rs_table,
`endif
    input S_X_PACKET  [`RS_SZ-1:0] S_X_reg,

    output logic      [`RS_SZ-1:0] s_valid, rs_free,  
    output S_X_PACKET [`RS_SZ-1:0] S_X_packet
);
    /* 
     *  Reads values from rs_table that has the dispatch and passes them to the s_x_regs when
     *  they are valid to begin computing.
     */

    logic [`RS_SZ-1:0] s_idx, reset_idx, rs_free_idx;

    // Issue Stage
    always_comb begin
        if (reset) begin
            for (s_idx = 0; s_idx < `RS_SZ; s_idx++)
                s_valid[s_idx] = 1'b0;
        end else begin
            for (s_idx = 0; s_idx < `RS_SZ; s_idx++) begin
`ifdef USE_D_S_REG
                if (D_S_reg[s_idx].valid & S_X_reg[s_idx].ready & en) begin
                    S_X_packet[s_idx] = {
                        D_S_reg[s_idx].T, 
                        D_S_reg[s_idx].V1, 
                        D_S_reg[s_idx].V2,
                        D_S_reg[s_idx].opa_select,
                        D_S_reg[s_idx].opb_select,
                        D_S_reg[s_idx].alu_func,
                        `FALSE,                     // ready (reg cannot be overwritten in use)
                        `TRUE                       // go (deploys FUs inside)
                        };
`else
                if ((rs_table[s_idx].ready == 2'b11) & S_X_reg[s_idx].ready & en) begin
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
`endif
                    s_valid[s_idx] = 1'b1;
                end else begin
                    S_X_packet[s_idx] = 0;
                    s_valid[s_idx] = 0;
                end
            end
        end
    end

    // clears the RS on the next cycle (works because rest is comb)
    always_ff @(posedge clock) begin
        if (reset) begin
            for (reset_idx = 0; reset_idx < `RS_SZ; reset_idx++)
                rs_free[reset_idx] <= 0;
        end else if (en) begin
            for (rs_free_idx = 0; rs_free_idx < `RS_SZ; rs_free_idx++)
                rs_free[rs_free_idx] <= s_valid[rs_free_idx];
        end
    end

endmodule   // RS_VALUE

module rs_stage(
    input clock, reset, en,
    input CDB                       cdb,
    input logic [`RS_SZ-1:0]                    rs_idx,
    input S_X_PACKET   [`RS_SZ-1:0] S_X_reg,
    input ROB_T                     T,                // coming from dispatch
    input MT_ENTRY                  T1, T2,
    input [`XLEN-1:0]               V1, V2,           // uses MT_ENTRY.plus to mux val from regfile or ROB

    output d_stall,              
    output [`RS_SZ-1:0] busy,           
    output S_X_PACKET [`RS_SZ-1:0] S_X_packet,
    output RS_ENTRY [ `RS_SZ-1:0] rs_table
);
    logic [`RS_SZ-1:0] free_bus;
    
    // connect alloc with value with cdb
    RS_ALLOC rs_alloc(
        // Inputs
        .clock(clock), .reset(reset), .en(en),
        .rs_idx(rs_idx), .rs_free(free_bus),
        .T(T), .MT_T1(T1), .MT_T2(T2),
        .V1(V1), .V2(V2),
        .cdb(cdb),

        // Outputs
        .stall(d_stall),
        .rs_table(rs_table),
        .busy(busy)
    );

`ifdef USE_D_S_REG
    D_S_PACKET [`RS_SZ-1:0] D_S_reg;
    logic [`RS_SZ-1:0] D_S_reg_idx;

    // add registers in between parts of pipeline. This will force 
    // consisten number of cycles for every time.
    always_ff @(posedge clock) begin
        for (D_S_reg_idx = 0; D_S_reg_idx < `RS_SZ; D_S_reg_idx++) begin
            if (en & (rs_table[D_S_reg_idx].ready == 2'b11))
                D_S_reg[D_S_reg_idx] <= {
                        rs_table[D_S_reg_idx].T, 
                        rs_table[D_S_reg_idx].V1, 
                        rs_table[D_S_reg_idx].V2,
                        rs_table[D_S_reg_idx].opa_select,
                        rs_table[D_S_reg_idx].opb_select,
                        rs_table[D_S_reg_idx].alu_func,
                        `TRUE
                    };
        end
    end
`endif

    RS_VALUE rs_value(
        // Input
        .clock(clock), .reset(reset), .en(en),
`ifdef USE_D_S_REG
        .D_S_reg(D_S_reg),
`else
        .rs_table(rs_table),
`endif
        .rs_free(free_bus),
        .S_X_reg(S_X_reg),

        // Output
        .S_X_packet(S_X_packet)
    );

endmodule   // top-level module