`include "verilog/sys_defs.svh"

module testbench;

    /* Primarily serves as an example of the functional unit logical flow
     *                                              
     *  S_X_reg -> fu -> X_C_reg -> arbiter -> CDB -> S_X_reg.reset
     *  S_X_reg -> fu -> X_C_reg -> arbiter -> CDB -> S_X_reg.reset
     *  S_X_reg -> fu -> X_C_reg -> arbiter -> CDB -> S_X_reg.reset
     *  S_X_reg -> fu -> X_C_reg -> arbiter -> CDB -> S_X_reg.reset
     *
     * Basically what happens if S_X_reg gets loaded with a value and begins to increment.
     * Once the desired delay has happened, it tells the arbiter it is ready. Then the arbiter
     * chooses one value and places it on the CDB. The arbiters grant line also triggers the reset
     * of the register.
     */

    logic clock, reset;
    CDB cdb;
    
    S_X_PACKET [`RS_SZ-1:0] S_X_reg;
    X_C_PACKET [`RS_SZ-1:0] X_C_reg;

    logic [4:0] stall_cnt [`RS_SZ-1:0];
    logic [4:0] max_cnt [`RS_SZ-1:0];
    
    logic [`RS_SZ-1:0] fu_ready, gnt;
    logic [`RS_SZ:0] fu_idx;

    fu_sel arb #(.WIDTH(`RS_SZ)) 
    (
        .req(fu_ready), 
        .gnt(gnt)
    );

    initial begin
        max_cnt[0] = 1;
        max_cnt[1] = `MULT_STAGES;
        max_cnt[2] = 6;             // assume mem takes 6 cycles for now
        max_cnt[3] = 1;             // lsq takes one cycle to load
    end

    // CDB control
    initial begin
        always_comb begin
            cdb.valid = `FALSE;
            
            for (logic [$clog2(`RS_SZ):0] i; i < `RS_SZ; i++)
                if (gnt[i]) begin
                    cdb.T = X_C_reg.T;
                    cdb.V = X_C_reg.result;
                    cdb.valid = `TRUE;
                end
        end
    end

    // Functional units
    initial begin
        always_ff @(posedge clock) begin
            for (fu_idx = 0; fu_idx < `RS_SZ; fu_idx++) begin
                if (reset | gnt[fu_idx]) begin
                    S_X_reg[fu_idx] <= 0;
                    X_C_reg[fu_idx] <= 0;
                    stall_cnt[fu_idx] <= 0;
                    fu_ready[fu_idx] <= `FALSE;
                end else begin
                    if (S_X_reg.valid) begin
                        if (stall_cnt == max_cnt - 1)
                            fu_ready[fu_idx] <= `TRUE;
                        else
                            stall_cnt[fu_idx] <= stall_cnt[fu_idx] + 1;
                    end
                end
            end
        end
    end

endmodule