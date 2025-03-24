`include "verilog/sys_defs.svh"

module func_unit_2(
    input S_X_PACKET S_X_reg,

    output logic [1:0]       proc2mem_command, // Command sent to memory
    output logic [`XLEN-1:0] proc2mem_addr,    // Address sent to memory
    output logic [63:0]      proc2mem_data,    // Data sent to memory
    output MEM_SIZE          proc2mem_size,    // Data size sent to m
    output X_C_PACKET        X_C_packet
);
    // TODO: check lsq for mem addr -> X_C_valid if present and data forwarded

    // TODO: else lsq doesn't have it, make mem req 
        // TODO: when data comes back, save it to reg and load to X_C_packet

endmodule