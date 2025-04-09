`include "verilog/sys_defs.svh"

module func_unit_3(
    input clock, reset, 
    input Dmem_gnt,                 // signal that the memory was listening to this module
    input retired,            // the current mem_store has been 
    input S_X_PACKET S_X_reg,

    output logic mem_store_pend,          // the module is attempting to store a value
    output [`XLEN-1:0] proc2Dmem_addr,
    output [`XLEN-1:0] proc2Dmem_data,
    output X_C_PACKET X_packet
);

    mem_proc_states mem_state;
    logic [`XLEN-1:0] proc2Dmem_addr_raw;

    assign proc2Dmem_data = S_X_reg.V2;
    assign proc2Dmem_addr_raw = S_X_reg.V1 + S_X_reg.mem_offset;
    assign proc2Dmem_addr = {proc2Dmem_addr_raw[`XLEN-1:3], 3'b0};

    always_comb begin
        if (Dmem_gnt) begin
            X_packet.T = S_X_reg.T;
            X_packet.result = '0;
            
            X_packet.ppln_ctrl = '0;
            X_packet.ppln_ctrl.is_store = `TRUE;
            X_packet.valid = Dmem_gnt;
        end else
            X_packet = '0;

    end

    // state machine enforces one memory load 
    always_ff @(posedge clock) begin
        if (reset) begin
            mem_store_pend <= `FALSE;
            mem_state <= MEM_WAIT_FOR_ADDR;
        end else begin
            case (mem_state)
                MEM_WAIT_FOR_ADDR:
                    if (S_X_reg.valid) begin
                        mem_store_pend <= `TRUE;
                        mem_state <= MEM_NEW_ADDR;
                    end
                MEM_NEW_ADDR:
                    if (Dmem_gnt) begin
                        mem_store_pend <= `FALSE;
                        mem_state <= MEM_NONE;
                    end
                MEM_NONE:
                    if (retired) 
                        mem_state <= MEM_WAIT_FOR_ADDR;
            endcase
        end
    end

endmodule   // func_unit_3
