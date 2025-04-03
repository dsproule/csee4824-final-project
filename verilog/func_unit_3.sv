`include "verilog/sys_defs.svh"

module func_unit_3(
    input clock, reset, Dmem_gnt, store_retired, 
    input S_X_PACKET S_X_reg,

    output mem_store,
    output [`XLEN-1:0] proc2Dmem_addr,
    output [`XLEN-1:0] proc2Dmem_data,
    output X_C_PACKET X_packet
);

    mem_proc_states mem_state;
    logic new_store;

    always_comb begin
        proc2Dmem_data = S_X_reg.V2;
        proc2Dmem_data = S_X_reg.V1 + `RV32_signext_Simm(S_X_reg.inst);

        if (Dmem_gnt) begin
            X_packet.T = S_X_reg.T;
            X_packet.result = '0;
            
            X_packet.ppln_ctrl = {
                `FALSE,     // flush
                `FALSE,     // illegal
                `FALSE,     // halt
                `FALSE,     // is_branch
                `TRUE,      // is_store
            }
            X_packet.valid = Dmem_gnt;
        end
    end

    // state machine enforces one memory load 
    always_ff @(posedge clock) begin
        if (reset) begin
            new_store <= `TRUE;
            mem_state <= WAIT_FOR_ADDR;
        end else begin
            if (store_retired)
                new_store <= `TRUE;

            case (mem_state)
                NEW_ADDR: mem_state <= (Dmem_gnt) ? WAIT_FOR_ADDR : mem_state;
                WAIT_FOR_ADDR: mem_state <= (S_X_reg.valid & new_store) <= NEW_ADDR : mem_state;
                default: ; 
            endcase
        end
    end

endmodule   // func_unit_3