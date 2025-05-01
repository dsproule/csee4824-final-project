`include "verilog/sys_defs.svh"

// Dispatch stage (fully combinational)
module RS_ALLOC(
    input clock, reset, en,
    input D_S_PACKET D_S_reg,
    input logic [`RS_SZ-1:0] rs_free,
    input ROB_T               T, 
    input MT_ENTRY            MT_T1, MT_T2,          // from the Map Table     
    input [`XLEN-1:0]         V1, V2,
    input CDB                 cdb,

    output rs_idx_full,
    output logic    [`RS_SZ-1:0] busy,
    output RS_ENTRY [`RS_SZ-1:0] rs_table
);
    /* 
     * Handles just the Dispatch. Passes values to 
     * RS_VALUE for issue stage.
     * 
     * In here we assume the ROB & Map Table feed the proper values based on the decode stage.
     */

    logic [$clog2(`RS_SZ):0] reset_idx, cdb_idx, rs_free_idx, busy_reset_idx, rs_update_idx;
    logic [`RS_SZ-1:0] next_busy, rs_idx;
    RS_ENTRY next_re;
    logic next_re_valid;

    logic [`RS_SZ-1:0] rs_free_latched, rs_free_latched_prev;

    assign rs_idx = D_S_reg.rs_idx;
    assign rs_idx_full = (rs_free_latched_prev[rs_idx]) ? 0 : busy[rs_idx];

    always_ff @(posedge clock) begin
        if (reset) begin
            for (reset_idx = 0; reset_idx < `RS_SZ; reset_idx++) begin
                next_busy[reset_idx] <= `FALSE;
                busy[reset_idx] <= `FALSE;
                rs_table[reset_idx] <= '0;
            end

            next_re <= '0;
            next_re_valid <= `FALSE;
            rs_update_idx <= 0;
            rs_free_latched <= '0;
            rs_free_latched_prev <= '0;
        end else begin  
            // Clear entries when marked free
            for (busy_reset_idx = 0; busy_reset_idx < `RS_SZ; busy_reset_idx++) begin
                if (rs_free[busy_reset_idx]) begin
                    $display(">>> RS[%0d] cleared at time %0t", busy_reset_idx, $time);
                    rs_table[busy_reset_idx] <= '0;
                    busy[busy_reset_idx]     <= `FALSE;
                    next_busy[busy_reset_idx] <= `FALSE;
                end
            end
            // Latch rs_free from RS_VALUE output
            // Latch rs_free from RS_VALUE output (FIXED LOCATION)
            rs_free_latched_prev <= rs_free_latched;
            rs_free_latched <= rs_free;  
 
            if (next_re_valid) begin
                rs_table[rs_update_idx].T         <= next_re.T;
                rs_table[rs_update_idx].D_S_reg   <= next_re.D_S_reg;

                // T1 logic
                if (cdb.valid && next_re.T1 == cdb.T) begin
                    $display(">>> [DISPATCH+CDB] RS[%0d] matched T1 = %0d, setting V1 = %0d", rs_update_idx, cdb.T, cdb.V);
                    rs_table[rs_update_idx].T1      <= 0;
                    rs_table[rs_update_idx].V1      <= cdb.V;
                    rs_table[rs_update_idx].ready[0]<= `TRUE;
                end else begin
                    rs_table[rs_update_idx].T1      <= next_re.T1;
                    rs_table[rs_update_idx].V1      <= next_re.V1;
                    rs_table[rs_update_idx].ready[0]<= next_re.ready[0];
                end

                // T2 logic
                if (cdb.valid && next_re.T2 == cdb.T) begin
                    $display(">>> [DISPATCH+CDB] RS[%0d] matched T2 = %0d, setting V2 = %0d", rs_update_idx, cdb.T, cdb.V);
                    rs_table[rs_update_idx].T2      <= 0;
                    rs_table[rs_update_idx].V2      <= cdb.V;
                    rs_table[rs_update_idx].ready[1]<= `TRUE;
                end else begin
                    rs_table[rs_update_idx].T2      <= next_re.T2;
                    rs_table[rs_update_idx].V2      <= next_re.V2;
                    rs_table[rs_update_idx].ready[1]<= next_re.ready[1];
                    if (rs_update_idx == 1 && next_re.T2 == 4) begin
                        $display(">>> DISPATCH: RS[1] assigned T2=4 at time %0t", $time);
                    end
                end

                next_re_valid <= `FALSE;
            end

            // Ensure CDB updates apply after dispatch
            /*
            if (cdb.valid) begin
                for (cdb_idx = 0; cdb_idx < `RS_SZ; cdb_idx++) begin
                    if (rs_table[cdb_idx].T1 == cdb.T) begin
                        rs_table[cdb_idx].V1 <= cdb.V;
                        rs_table[cdb_idx].T1 <= 0;
                        rs_table[cdb_idx].ready[0] <= `TRUE;
                    end
                    if (rs_table[cdb_idx].T2 == cdb.T) begin
                        $display(">>> RS[%0d] matched T2 = %0d with CDB.T = %0d", cdb_idx, rs_table[cdb_idx].T2, cdb.T);
                        rs_table[cdb_idx].V2 <= cdb.V;
                        rs_table[cdb_idx].T2 <= 0;
                        rs_table[cdb_idx].ready[1] <= `TRUE;
                    end
                end
            end
            */

            // if RS entry is empty, allocate it
             if ((~busy[rs_idx] & ~rs_free[rs_idx]) & en) begin
                next_busy[rs_idx] <= `TRUE;
                busy[rs_idx] <= `TRUE;
                
                // save values in next_re from decode stage (always saved for allocation)
                next_re.T <= T;
                next_re.D_S_reg <= D_S_reg;
                next_re_valid <= `TRUE;

                rs_update_idx <= rs_idx;

                // checks if we can put just the value in or if we need the tag for t1
                // --- T1 handling with CDB forwarding ---
                if (MT_T1 == 0 || MT_T1.plus) begin
                    next_re.T1 <= 0;
                    next_re.V1 <= V1;
                    next_re.ready[0] <= `TRUE;
                end else if (cdb.valid && cdb.T == MT_T1.T) begin
                    next_re.T1 <= 0;
                    next_re.V1 <= cdb.V;
                    next_re.ready[0] <= `TRUE;
                end else begin
                    next_re.T1 <= MT_T1.T;
                    next_re.V1 <= 0;
                    next_re.ready[0] <= `FALSE;
                end

                // --- T2 handling with CDB forwarding ---
                if (MT_T2 == 0 || MT_T2.plus) begin
                    next_re.T2 <= 0;
                    next_re.V2 <= V2;
                    next_re.ready[1] <= `TRUE;
                end else if (cdb.valid && cdb.T == MT_T2.T) begin
                    next_re.T2 <= 0;
                    next_re.V2 <= cdb.V;
                    next_re.ready[1] <= `TRUE;
                end else begin
                    next_re.T2 <= MT_T2.T;
                    next_re.V2 <= 0;
                    next_re.ready[1] <= `FALSE;
                end

                
            end //else begin
                //next_re <= '0;
                //next_re_valid <= `FALSE;
           // end

            // free a line that isn't about to be allocated (should be handled by above)
            for (rs_free_idx = 0; rs_free_idx < `RS_SZ; rs_free_idx++)
                if (((rs_free_idx != rs_update_idx) | ~next_re_valid) & (rs_free[rs_free_idx]))
                    rs_table[rs_free_idx] <= 0;

            // if a CDB line came in 
            if (cdb.valid) 
                for (cdb_idx = 0; cdb_idx < `RS_SZ; cdb_idx++) begin
                    $display(">>> [CDB] Checked RS[%0d] T2=%0d against cdb.T=%0d", cdb_idx, rs_table[cdb_idx].T2, cdb.T);

                    if (rs_table[cdb_idx].T1 == cdb.T) begin
                        $display(">>> [CDB] RS[%0d] T1 matched T=%0d, setting V1=%0d", cdb_idx, cdb.T, cdb.V);
                        $display(">>> [CDB] Valid: %b T=%0d V=%0d", cdb.valid, cdb.T, cdb.V);

                        rs_table[cdb_idx].V1 <= cdb.V;
                        rs_table[cdb_idx].T1 <= 0;
                        rs_table[cdb_idx].ready[0] <= `TRUE;
                    end

                    if (rs_table[cdb_idx].T2 == cdb.T) begin
                         $display(">>> [CDB] RS[%0d] T2 matched T=%0d, setting V2=%0d", cdb_idx, cdb.T, cdb.V);
                         $display(">>> [CDB] Valid: %b T=%0d V=%0d", cdb.valid, cdb.T, cdb.V);

                        rs_table[cdb_idx].V2 <= cdb.V;
                        rs_table[cdb_idx].T2 <= 0;
                        rs_table[cdb_idx].ready[1] <= `TRUE;
                        $display(">>> CDB UPDATE: RS[%0d] T2 matched T=%0d, V2=%0d at time %0t", cdb_idx, cdb.T, cdb.V, $time);
                        if (cdb_idx == 1) begin
                            $display(">>> CDB HIT: RS[1] accepted broadcast T=4 at time %0t", $time);
                        end;
                    end
                end
        end
    end

endmodule   // RS_alloc

// Issue stage (clocked)
module RS_VALUE(
    input clock, reset,
    input RS_ENTRY    [`RS_SZ-1:0] rs_table,
    input logic      [`RS_SZ-1:0] FU_ready,

    output logic      [`RS_SZ-1:0] s_valid, rs_free,  
    output S_X_PACKET [`RS_SZ-1:0] S_packet
);
    /* 
     *  Reads values from rs_table that has the dispatch and passes them to the s_x_regs when
     *  they are valid to begin computing.
     */

    logic [`RS_SZ-1:0] s_idx, reset_idx, rs_free_idx;

    // Issue Stage
    always_comb begin
        if (reset) begin
            for (s_idx = 0; s_idx < `RS_SZ; s_idx++) begin
                s_valid[s_idx] = 1'b0;
                rs_free[s_idx] = 1'b0;
            end
        end else begin
            for (s_idx = 0; s_idx < `RS_SZ; s_idx++) begin
                if ((rs_table[s_idx].ready == 2'b11) & FU_ready[s_idx]) begin
                    S_packet[s_idx].inst          = rs_table[s_idx].D_S_reg.inst;
                    S_packet[s_idx].PC            = rs_table[s_idx].D_S_reg.PC;
                    S_packet[s_idx].NPC           = rs_table[s_idx].D_S_reg.NPC;
                    S_packet[s_idx].cond_branch   = rs_table[s_idx].D_S_reg.cond_branch;
                    S_packet[s_idx].uncond_branch = rs_table[s_idx].D_S_reg.uncond_branch;
                    S_packet[s_idx].opa_select    = rs_table[s_idx].D_S_reg.opa_select;
                    S_packet[s_idx].opb_select    = rs_table[s_idx].D_S_reg.opb_select;
                    S_packet[s_idx].alu_func      = rs_table[s_idx].D_S_reg.alu_func;
                    S_packet[s_idx].T             = rs_table[s_idx].T;
                    S_packet[s_idx].V1            = rs_table[s_idx].V1;
                    S_packet[s_idx].V2            = rs_table[s_idx].V2;
                    S_packet[s_idx].halt          = rs_table[s_idx].D_S_reg.halt;
                    S_packet[s_idx].mem_offset    = rs_table[s_idx].D_S_reg.mem_offset;
                    S_packet[s_idx].rd_unsigned   = rs_table[s_idx].D_S_reg.rd_unsigned;
                    S_packet[s_idx].mem_size      = rs_table[s_idx].D_S_reg.mem_size;
                    S_packet[s_idx].valid         = `TRUE;
                    S_packet[s_idx].has_dest      = rs_table[s_idx].D_S_reg.has_dest;
                    
                    rs_free[s_idx] = 1'b1;
                    if (s_idx == 3) $display(">>> RS_VALUE: RS[3] issued at time %0t", $time);
                end else begin
                    S_packet[s_idx] = 0;
                    rs_free[s_idx] = 0;
                end
            end
        end
    end

endmodule   // RS_VALUE

module rs_stage(
    input clock, reset, alloc_en,
    input CDB cdb,
    input D_S_PACKET D_S_reg,
    input [`RS_SZ-1:0] FU_ready,
    input ROB_T       T,
    input MT_ENTRY    T1, T2,
    input [`XLEN-1:0] V1, V2,                  // uses MT_ENTRY.plus to mux val from regfile or ROB

    output rs_idx_full,              
    output [`RS_SZ-1:0] busy,           
    output S_X_PACKET [`RS_SZ-1:0] S_packet,
    output RS_ENTRY [ `RS_SZ-1:0]  rs_table
);
    logic [`RS_SZ-1:0] free_bus;
    
    // connect alloc with value with cdb
    RS_ALLOC rs_alloc(
        // Inputs
        .clock(clock), .reset(reset), .en(alloc_en),
        .D_S_reg(D_S_reg),
        .rs_free(free_bus),
        .T(T), .MT_T1(T1), .MT_T2(T2),
        .V1(V1), .V2(V2),
        .cdb(cdb),

        // Outputs
        .rs_idx_full(rs_idx_full),
        .rs_table(rs_table),
        .busy(busy)
    );

    RS_VALUE rs_value(
        // Input
        .clock(clock), .reset(reset),
        .rs_table(rs_table),
        .rs_free(free_bus),
        .FU_ready(FU_ready),

        // Output
        .S_packet(S_packet)
    );

endmodule   // top-level module
