`include "verilog/sys_defs.svh"

module func_unit_2(
    input data_valid,
    input [63:0] Dmem2proc_data,
    input ROB_T T,
    input MEM_ACCESS mem_access,
    
    output X_C_PACKET X_packet
);
    logic [`XLEN-1:0] shifted_result;
    logic [5:0]       shift;
    logic [63:0]      Dmem_data;

    always_comb begin
        // perform the offset shift here to apply the masks. Uses shifting to avoid multiplication
        shift = (mem_access.mem_size == BYTE) ? (mem_access.line_offset)         << 3 :        // turns bytes to num of bits to shift by
                (mem_access.mem_size == HALF) ? (mem_access.line_offset >> 1)    << 4 :        // floor(2)  --> grabs by granularity of 2 bytes at a time
                (mem_access.mem_size == WORD) ? (mem_access.line_offset[2] << 2) << 3 : 0;     // if (line_offset >= 4) shift by a word --> upper 32 bits
        
        Dmem_data = Dmem2proc_data >> shift;

        if (mem_access.rd_unsigned) begin
            if (mem_access.mem_size == BYTE)
                Dmem_data[`XLEN-1:8] = 0;
            else if (mem_access.mem_size == HALF)
                Dmem_data[`XLEN-1:16] = 0;
        end else begin
            if (mem_access.mem_size == BYTE)
                Dmem_data[`XLEN-1:8] = {(`XLEN-8){Dmem2proc_data[7 + shift]}};
            else if (mem_access.mem_size == HALF)
                Dmem_data[`XLEN-1:16] = {(`XLEN-16){Dmem2proc_data[15 + shift]}};
        end
        shifted_result = Dmem_data[`XLEN-1:0];
    end

    always_comb begin
        if (data_valid) begin
            X_packet.T         = T;
            X_packet.result    = shifted_result;
            X_packet.ppln_ctrl = '0;
            X_packet.ppln_ctrl.has_dest = `TRUE;
            X_packet.valid     = `TRUE;
        end else begin
            X_packet           = 0;
        end
    end

endmodule
