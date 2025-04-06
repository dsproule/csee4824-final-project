`include "verilog/sys_defs.svh"

module func_unit_2(
    input clock, reset, Dmem_gnt,
    input retired,
    input [3:0]  mem2proc_response, mem2proc_tag,
    input [`XLEN-1:0] Dmem2proc_data,
    input S_X_PACKET S_X_reg,

    output logic mem_load_pend,         // the module is attempting to load a value
`ifndef CACHE_MODE // no longer sending size to memory
    output MEM_SIZE          proc2mem_size,    // Data size sent to memory
`endif
    output [`XLEN-1:0] proc2Dmem_addr,
    output X_C_PACKET X_packet
);
    logic [`XLEN-1:0] read_data;
    logic [3:0]  nextImem_tag;
    mem_proc_states mem_state;

    // should be word-aligned. If a value is invalid proc_resp will be 0
    assign proc2Dmem_addr = S_X_reg.V1 + S_X_reg.mem_offset;
    assign proc2mem_size = S_X_reg.mem_size;
    
    // directly from p3
    always_comb begin
        read_data = Dmem2proc_data;
        if (S_X_reg.rd_unsigned) begin
            // unsigned: zero-extend the data
            if (S_X_reg.mem_size == BYTE) begin
                read_data[`XLEN-1:8] = 0;
            end else if (S_X_reg.mem_size == HALF) begin
                read_data[`XLEN-1:16] = 0;
            end
        end else begin
            // signed: sign-extend the data
            if (S_X_reg.mem_size[1:0] == BYTE) begin
                read_data[`XLEN-1:8] = {(`XLEN-8){Dmem2proc_data[7]}};
            end else if (S_X_reg.mem_size == HALF) begin
                read_data[`XLEN-1:16] = {(`XLEN-16){Dmem2proc_data[15]}};
            end
        end
    end

    // state machine to handle loads
    always_ff @(posedge clock) begin
        if (reset) begin
            nextImem_tag <= '0;
            mem_state <= MEM_WAIT_FOR_ADDR;
            mem_load_pend <= `FALSE;
        end else begin
            case (mem_state)
                MEM_WAIT_FOR_ADDR: 
                    // waits here for a mem req to hit S_X_reg
                    if (S_X_reg.valid) begin
                        mem_load_pend <= `TRUE;
                        mem_state <= MEM_NEW_ADDR;
                    end
                MEM_NEW_ADDR: begin
                    // saves every  seen tag and when we know the tag corresp to current req, move to next state
                    nextImem_tag <= mem2proc_response;
                        if (Dmem_gnt & (nextImem_tag != 0)) begin
                            mem_load_pend <= `FALSE;
                            mem_state <= MEM_WAIT_FOR_TAG;
                        end
                end
                MEM_WAIT_FOR_TAG: begin
                    // if the memory is responding to us, save it and wait to be retired
                    if (mem2proc_tag == nextImem_tag) begin
                        X_packet.T = S_X_reg.T;
                        X_packet.result = read_data;
                        X_packet.ppln_ctrl <= '0;
                        X_packet.valid = `TRUE;

                        nextImem_tag <= '0;
                        mem_state <= MEM_NONE;
                    end
                end
                MEM_NONE: begin
                    X_packet <= '0;
                    if (retired) 
                        mem_state <= MEM_WAIT_FOR_ADDR;
                end
            endcase
        end
    end    

endmodule
