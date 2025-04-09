`include "verilog/sys_defs.svh"

module func_unit_2(
    input clock, reset, Dmem_gnt,
    input retired,
    input [3:0]  mem2proc_response, mem2proc_tag,
    input [63:0] Dmem2proc_data,
    input S_X_PACKET S_X_reg,

    output logic mem_load_pend,
    output [`XLEN-1:0] proc2Dmem_addr,
    output X_C_PACKET X_packet
);
    logic [`XLEN-1:0] rawDmem_addr, shifted_result;
    logic [5:0]       shift;
    logic [63:0]      Dmem_data;
    logic [3:0]       nextImem_tag, line_offset;
    mem_proc_states   mem_state;

    // should be word-aligned. If a value is invalid proc_resp will be 0
    assign rawDmem_addr   = S_X_reg.V1 + S_X_reg.mem_offset;
    assign proc2Dmem_addr = {rawDmem_addr[`XLEN-1:3], 3'b0};
    assign line_offset    = rawDmem_addr[2:0];

    always_comb begin
        // perform the offset shift here to apply the masks. Uses shifting to avoid multiplication
        shift = (S_X_reg.mem_size == BYTE) ? (line_offset)         << 3 :        // turns bytes to num of bits to shift by
                (S_X_reg.mem_size == HALF) ? (line_offset >> 1)    << 4 :        // floor(2)  --> grabs by granularity of 2 bytes at a time
                (S_X_reg.mem_size == WORD) ? (line_offset[2] << 2) << 3 : 0;     // if (line_offset >= 4) shift by a word --> upper 32 bits
        
        Dmem_data = Dmem2proc_data >> shift;

        if (S_X_reg.rd_unsigned) begin
            if (S_X_reg.mem_size == BYTE)
                Dmem_data[`XLEN-1:8] = 0;
            else if (S_X_reg.mem_size == HALF)
                Dmem_data[`XLEN-1:16] = 0;
        end else begin
            if (S_X_reg.mem_size == BYTE)
                Dmem_data[`XLEN-1:8] = {(`XLEN-8){Dmem2proc_data[7 + shift]}};
            else if (S_X_reg.mem_size == HALF)
                Dmem_data[`XLEN-1:16] = {(`XLEN-16){Dmem2proc_data[15 + shift]}};
        end
        shifted_result = Dmem_data[`XLEN-1:0];
    end

    // state machine to handle loads
    always_ff @(posedge clock) begin
        if (reset) begin
            X_packet      <= '0;
            nextImem_tag  <= '0;
            mem_state     <= MEM_WAIT_FOR_ADDR;
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
                        X_packet.T         <= S_X_reg.T;
                        X_packet.result    <= shifted_result;
                        X_packet.ppln_ctrl <= '0;
                        X_packet.ppln_ctrl.has_dest <= `TRUE;
                        X_packet.valid     <= `TRUE;

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
