`include "verilog/sys_defs.svh"

module testbench;

    /* Primarily serves as an example of the functional unit logical flow
     *                                              
     *  S_X_reg -> fu -> X_C_reg -> arbiter -> CDB -> S_X_reg.reset
     *  S_X_reg -> fu -> X_C_reg -> arbiter -> CDB -> S_X_reg.reset
     *  S_X_reg -> fu -> X_C_reg -> arbiter -> CDB -> S_X_reg.reset
     *  S_X_reg -> fu -> X_C_reg -> arbiter -> S_X_reg.reset
     *
     * Basically what happens if S_X_reg gets loaded with a value and begins to increment.
     * Once the desired delay has happened, it tells the arbiter it is ready. Then the arbiter
     * chooses one value and places it on the CDB. The arbiters grant line also triggers the reset
     * of the register.
     */

    logic clock, reset;
    CDB cdb;
    
    S_X_PACKET [`RS_SZ-1:0] S_X_reg;
    X_C_PACKET [`RS_SZ-1:0] X_C_reg, X_C_packet;

    logic [4:0] stall_cnt [`RS_SZ-1:0];
    logic [4:0] max_cnt [`RS_SZ-1:0];
    
    logic [`RS_SZ-1:0] FU_ready, gnt;
    logic [`RS_SZ:0] fu_idx;
    logic [`RS_SZ*2-1:0] gnt_bus;

    // forces a more balanced arbiter to avoid starvation
    assign gnt = (clock) ? gnt_bus[`RS_SZ-1:0] : gnt_bus[`RS_SZ*2-1:`RS_SZ];

    // just 4-bit priority selector
    psel arb #(.WIDTH(`RS_SZ), .REQS(2)) 
    (
        .req(FU_ready), 

        .gnt(),
        .gnt_bus(gnt_bus),
        .empty()
    );

    func_unit_0 FU_0 (
        .S_X_reg(S_X_reg[0]),

        .X_C_packet(X_C_packet[0])
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
            
            for (logic [$clog2(`RS_SZ):0] i; i < `RS_SZ; i++) begin
                if (gnt[i]) begin
                    cdb.T = X_C_reg.T;
                    cdb.V = X_C_reg.result;
                    cdb.valid = `TRUE;
                end

                FU_ready[i] = X_C_packet[i].ready;
            end
        end
    end

    // Functional units
    initial begin
        if (reset | gnt[0])
            S_X_reg[0] <= (S_X_packet[0].valid) ? S_X_packet[0] : 0;    // handled by the RS
        else if (X_C_packet[0].ready)
            X_C_reg[0] <= X_C_packet[0];
        
    end

endmodule